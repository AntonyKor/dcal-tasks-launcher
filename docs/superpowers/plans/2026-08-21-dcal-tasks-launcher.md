# DcalTasks Launcher Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A DankMaterialShell launcher plugin that lists, searches, creates, and completes dcal tasks.

**Architecture:** All decidable logic lives in `TaskItems.js`, a `.pragma library` JS
file with no QML dependencies, unit tested with the Qt6 `qmltestrunner`. All side
effects — `dcal ipc` subprocesses, plugin settings I/O — live in two QML files that
call into that library. Tasks 1–6 build and test the library; Tasks 7–9 wire it up
and verify against the live daemon.

**Tech Stack:** QML (Qt 6.11), Quickshell (`Process`, `StdioCollector`), DMS plugin
API 1.5.3, dcal IPC via the `dcal` CLI, QtTest via `/usr/lib/qt6/bin/qmltestrunner`.

**Spec:** `docs/superpowers/specs/2026-08-21-dcal-tasks-launcher-design.md`

## Global Constraints

- Plugin id is `dcalTasks` everywhere: `plugin.json`, `loadPluginData`/`savePluginData`
  calls, and `PluginSettings.pluginId`. A mismatch silently breaks settings.
- Default trigger is `;`. Default `showCompleted` is `false`. Default
  `defaultCalendarId` is `""`.
- `requires_dms` is `">=1.5.0"`. Runtime requirement is `dcal` only — do **not**
  add a `jq` dependency.
- Every launcher item carries `categories: ["Tasks"]` and a `_preScored` above 900.
  Values below 900 are ignored by the launcher when the query is empty
  (`Scorer.js:157`).
- Never invoke a shell. All `dcal` calls are argv arrays: `["dcal", "ipc", …]`.
- `TaskItems.js` must not import QML modules or reference `Qt`, `Theme`, or any
  singleton. It is a `.pragma library` and must stay pure so the tests can run it.
- No locale-dependent formatting (`toLocaleDateString`, `localeCompare`) — it makes
  tests environment-dependent. Use the fixed month table defined in Task 2.
- Run tests headless: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests`.
  **Do not use `/usr/bin/qmltestrunner`** — that is the Qt5 build from
  `qt5-declarative` and exits 1 with no output whatsoever against Qt6 QML.

### Deviation from the spec

The spec's IPC table lists `tasks.list [includeCompleted=false]`. This plan always
calls plain `tasks.list` and filters completed tasks client-side in `selectTasks`.
One command instead of two, no refetch when the `showCompleted` toggle flips, and
the completed set is small. Behaviour is identical.

---

### Task 1: Repo scaffolding, test harness, and response parsing

**Files:**
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `TaskItems.js`
- Test: `tests/tst_TaskItems.qml`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `parseTasks(text) -> {ok: bool, tasks: Array, error: string}`
  - `parseCalendars(text) -> {ok: bool, calendars: Object, error: string}`
    where `calendars` maps id → `{id, name, accountName, holdsTasks, readOnly}`.

- [ ] **Step 1: Create the repo scaffolding**

`.gitignore`:

```
*.log
out.txt
err.txt
```

`LICENSE` — MIT, copyright holder `Anton Kalodzich`, year 2026. Use the standard
MIT text verbatim.

- [ ] **Step 2: Write the failing test**

Create `tests/tst_TaskItems.qml`:

```qml
import QtQuick
import QtTest
import "../TaskItems.js" as TaskItems

TestCase {
    name: "TaskItems"

    readonly property string tasksJson: '{
      "tasks": [
        {"allDay": false, "calendarId": "cal-chores", "completed": "2026-08-21T10:50:55Z",
         "description": "", "id": "t-done", "location": "", "parentUid": "",
         "percentComplete": 100, "priority": 0, "status": "completed",
         "summary": "Potato dumplings", "uid": "U-DONE"},
        {"allDay": true, "calendarId": "cal-fitness", "description": "",
         "due": "2026-02-21T00:00:00Z", "id": "t-open", "location": "", "parentUid": "",
         "percentComplete": 0, "priority": 0, "status": "needs_action",
         "summary": "Find therapist", "uid": "U-OPEN"}
      ],
      "total": 2
    }'

    readonly property string calendarsJson: '[
      {"accountId": "a1", "accountKind": "caldav", "accountName": "Radicale",
       "holdsTasks": true, "id": "cal-chores", "name": "Chores", "readOnly": false,
       "supportedComponents": ["VTODO"]},
      {"accountId": "a2", "accountKind": "caldav", "accountName": "iCloud",
       "holdsTasks": false, "id": "cal-family", "name": "Family", "readOnly": false,
       "supportedComponents": ["VEVENT"]},
      {"accountId": "a1", "accountKind": "caldav", "accountName": "Radicale",
       "holdsTasks": true, "id": "cal-fitness", "name": "Fitness", "readOnly": true,
       "supportedComponents": ["VTODO"]}
    ]'

    function test_parseTasks_readsTaskArray() {
        var r = TaskItems.parseTasks(tasksJson)
        verify(r.ok)
        compare(r.error, "")
        compare(r.tasks.length, 2)
        compare(r.tasks[1].summary, "Find therapist")
    }

    function test_parseTasks_emptyPayloadIsOkAndEmpty() {
        var r = TaskItems.parseTasks('{"tasks": [], "total": 0}')
        verify(r.ok)
        compare(r.tasks.length, 0)
    }

    function test_parseTasks_missingTasksKeyIsOkAndEmpty() {
        var r = TaskItems.parseTasks('{"total": 0}')
        verify(r.ok)
        compare(r.tasks.length, 0)
    }

    function test_parseTasks_malformedJsonFails() {
        var r = TaskItems.parseTasks('dcal daemon not running')
        verify(!r.ok)
        verify(r.error.length > 0)
        compare(r.tasks.length, 0)
    }

    function test_parseTasks_emptyStringFails() {
        var r = TaskItems.parseTasks('')
        verify(!r.ok)
        compare(r.tasks.length, 0)
    }

    function test_parseCalendars_indexesById() {
        var r = TaskItems.parseCalendars(calendarsJson)
        verify(r.ok)
        compare(r.calendars["cal-chores"].name, "Chores")
        compare(r.calendars["cal-chores"].accountName, "Radicale")
        compare(r.calendars["cal-chores"].holdsTasks, true)
        compare(r.calendars["cal-fitness"].readOnly, true)
        compare(r.calendars["cal-family"].holdsTasks, false)
    }

    function test_parseCalendars_malformedFails() {
        var r = TaskItems.parseCalendars('nope')
        verify(!r.ok)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Expected: FAIL. The runner reports it cannot resolve `../TaskItems.js`.

- [ ] **Step 4: Write the minimal implementation**

Create `TaskItems.js`:

```js
.pragma library

// Pure helpers behind the dcalTasks launcher plugin. No QML imports, no
// singletons, no Qt globals — everything here is unit tested by
// tests/tst_TaskItems.qml, so it must stay runnable outside Quickshell.

function parseTasks(text) {
    var parsed = _parseJson(text)
    if (!parsed.ok)
        return {ok: false, tasks: [], error: parsed.error}

    var tasks = parsed.value && parsed.value.tasks
    return {ok: true, tasks: Array.isArray(tasks) ? tasks : [], error: ""}
}

function parseCalendars(text) {
    var parsed = _parseJson(text)
    if (!parsed.ok)
        return {ok: false, calendars: {}, error: parsed.error}

    var list = Array.isArray(parsed.value) ? parsed.value : []
    var byId = {}
    for (var i = 0; i < list.length; i++) {
        var c = list[i]
        if (!c || !c.id)
            continue
        byId[c.id] = {
            id: c.id,
            name: c.name || "",
            accountName: c.accountName || "",
            holdsTasks: c.holdsTasks === true,
            readOnly: c.readOnly === true
        }
    }
    return {ok: true, calendars: byId, error: ""}
}

function _parseJson(text) {
    if (!text || text.trim().length === 0)
        return {ok: false, value: null, error: "dcal returned no output"}
    try {
        return {ok: true, value: JSON.parse(text), error: ""}
    } catch (e) {
        return {ok: false, value: null, error: String(e.message || e)}
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Expected: PASS, 7 test functions plus `initTestCase`/`cleanupTestCase`.

- [ ] **Step 6: Commit**

```bash
git add .gitignore LICENSE TaskItems.js tests/tst_TaskItems.qml
git commit -m "feat: parse dcal tasks.list and calendars.list responses"
```

---

### Task 2: Due-date labels

**Files:**
- Modify: `TaskItems.js`
- Test: `tests/tst_TaskItems.qml`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `dueLabel(due, allDay) -> string` — always `"<Mon> <D>"` (e.g.
  `"Feb 21"`), or `""` when there is no due date or the value is unparseable. No
  year is ever shown. Callers add their own `"due "` prefix.

- [ ] **Step 1: Write the failing test**

Append these functions inside the existing `TestCase` in `tests/tst_TaskItems.qml`:

```qml
    // dcal serialises all-day values as UTC midnight. Reading those with local
    // getters shows the previous day for anyone west of UTC, so all-day values
    // must be read with the UTC getters. This test would fail under TZ=America/
    // Los_Angeles if that shift were missing, and passes in every zone with it.
    function test_dueLabel_allDayUsesUtcCalendarDate() {
        compare(TaskItems.dueLabel("2026-02-21T00:00:00Z", true), "Feb 21")
    }

    function test_dueLabel_allDayIsTimezoneIndependent() {
        compare(TaskItems.dueLabel("2026-12-31T00:00:00Z", true), "Dec 31")
        compare(TaskItems.dueLabel("2026-01-01T00:00:00Z", true), "Jan 1")
    }

    // Built from a local Date so the expectation holds in any zone.
    function test_dueLabel_timedUsesLocalCalendarDate() {
        var local = new Date(2026, 1, 21, 15, 30, 0)
        compare(TaskItems.dueLabel(local.toISOString(), false), "Feb 21")
    }

    function test_dueLabel_emptyWhenNoDueDate() {
        compare(TaskItems.dueLabel("", true), "")
        compare(TaskItems.dueLabel(undefined, false), "")
        compare(TaskItems.dueLabel(null, false), "")
    }

    function test_dueLabel_emptyWhenUnparseable() {
        compare(TaskItems.dueLabel("not-a-date", true), "")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Expected: FAIL with `TypeError: Property 'dueLabel' of object [object Object] is not a function`.

- [ ] **Step 3: Write the minimal implementation**

Append to `TaskItems.js`:

```js
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// dcal writes all-day values as UTC midnight ("2026-02-21T00:00:00Z"), so an
// all-day date must be read with the UTC getters or it renders as the previous
// day west of UTC. Timed values are genuine instants and render in local time.
function dueLabel(due, allDay) {
    if (!due)
        return ""
    var d = new Date(due)
    if (isNaN(d.getTime()))
        return ""

    var month = allDay ? d.getUTCMonth() : d.getMonth()
    var day = allDay ? d.getUTCDate() : d.getDate()
    return MONTHS[month] + " " + day
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Expected: PASS.

- [ ] **Step 5: Verify the all-day shift really is timezone independent**

This step is load-bearing, not a formality. An implementation that wrongly uses
local getters for all-day values **passes all of these tests under `TZ=UTC`** —
verified by mutation. The bug is only observable from another zone.

```bash
TZ=America/Los_Angeles QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
TZ=Pacific/Kiritimati QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Expected: PASS in both. If `test_dueLabel_allDayUsesUtcCalendarDate` and
`test_dueLabel_allDayIsTimezoneIndependent` fail in Los Angeles but pass in UTC,
the UTC getters were not used.

- [ ] **Step 6: Commit**

```bash
git add TaskItems.js tests/tst_TaskItems.qml
git commit -m "feat: format task due dates, shifting all-day values off UTC midnight"
```

---

### Task 3: Task selection, bucketing, and ordering

**Files:**
- Modify: `TaskItems.js`
- Test: `tests/tst_TaskItems.qml`

**Interfaces:**
- Consumes: `parseTasks`, `parseCalendars` output shapes from Task 1.
- Produces: `selectTasks(tasks, calendars, query, showCompleted) -> {open: Array, done: Array}`.
  Each returned element is `{task: Object, listName: string, due: string}` where
  `due` is the `dueLabel` output and `listName` is `""` when the calendar is unknown.

Rules:
- `status === "completed"` goes to `done`; `status === "cancelled"` is dropped
  entirely; everything else goes to `open`.
- `done` is empty when `showCompleted` is false.
- `query` matches case-insensitively as a substring of the summary or the list name.
  An empty query matches everything.
- `open` sorts by due time ascending, undated last, then by lowercased summary.
- `done` sorts by completion time, most recent first.

- [ ] **Step 1: Write the failing test**

Append inside the existing `TestCase`:

```qml
    function makeTask(over) {
        var base = {
            id: "t1", summary: "Task", status: "needs_action",
            calendarId: "cal-chores", allDay: false
        }
        for (var k in over)
            base[k] = over[k]
        return base
    }

    readonly property var cals: ({
        "cal-chores": {id: "cal-chores", name: "Chores", accountName: "Radicale",
                       holdsTasks: true, readOnly: false},
        "cal-fitness": {id: "cal-fitness", name: "Fitness", accountName: "Radicale",
                        holdsTasks: true, readOnly: false}
    })

    function test_selectTasks_splitsOpenFromCompleted() {
        var tasks = [
            makeTask({id: "a", summary: "Alpha"}),
            makeTask({id: "b", summary: "Bravo", status: "completed",
                      completed: "2026-08-21T10:00:00Z"})
        ]
        var r = TaskItems.selectTasks(tasks, cals, "", true)
        compare(r.open.length, 1)
        compare(r.open[0].task.id, "a")
        compare(r.done.length, 1)
        compare(r.done[0].task.id, "b")
    }

    function test_selectTasks_hidesCompletedWhenToggleOff() {
        var tasks = [
            makeTask({id: "a", summary: "Alpha"}),
            makeTask({id: "b", summary: "Bravo", status: "completed",
                      completed: "2026-08-21T10:00:00Z"})
        ]
        var r = TaskItems.selectTasks(tasks, cals, "", false)
        compare(r.open.length, 1)
        compare(r.done.length, 0)
    }

    function test_selectTasks_dropsCancelled() {
        var tasks = [
            makeTask({id: "a", summary: "Alpha"}),
            makeTask({id: "x", summary: "Scrapped", status: "cancelled"})
        ]
        var r = TaskItems.selectTasks(tasks, cals, "", true)
        compare(r.open.length, 1)
        compare(r.open[0].task.id, "a")
        compare(r.done.length, 0)
    }

    function test_selectTasks_ordersByDueThenUndatedLast() {
        var tasks = [
            makeTask({id: "none", summary: "No due date"}),
            makeTask({id: "late", summary: "Later", allDay: true,
                      due: "2026-03-01T00:00:00Z"}),
            makeTask({id: "soon", summary: "Sooner", allDay: true,
                      due: "2026-02-21T00:00:00Z"})
        ]
        var r = TaskItems.selectTasks(tasks, cals, "", false)
        compare(r.open.length, 3)
        compare(r.open[0].task.id, "soon")
        compare(r.open[1].task.id, "late")
        compare(r.open[2].task.id, "none")
    }

    function test_selectTasks_undatedTiesBreakBySummary() {
        var tasks = [
            makeTask({id: "z", summary: "zebra"}),
            makeTask({id: "a", summary: "Apple"}),
            makeTask({id: "m", summary: "mango"})
        ]
        var r = TaskItems.selectTasks(tasks, cals, "", false)
        compare(r.open[0].task.id, "a")
        compare(r.open[1].task.id, "m")
        compare(r.open[2].task.id, "z")
    }

    function test_selectTasks_completedNewestFirst() {
        var tasks = [
            makeTask({id: "old", summary: "Old", status: "completed",
                      completed: "2026-08-01T10:00:00Z"}),
            makeTask({id: "new", summary: "New", status: "completed",
                      completed: "2026-08-21T10:00:00Z"})
        ]
        var r = TaskItems.selectTasks(tasks, cals, "", true)
        compare(r.done[0].task.id, "new")
        compare(r.done[1].task.id, "old")
    }

    function test_selectTasks_searchIsCaseInsensitiveOnSummary() {
        var tasks = [
            makeTask({id: "a", summary: "Find therapist"}),
            makeTask({id: "b", summary: "Buy milk"})
        ]
        var r = TaskItems.selectTasks(tasks, cals, "THERAPIST", false)
        compare(r.open.length, 1)
        compare(r.open[0].task.id, "a")
    }

    function test_selectTasks_searchMatchesListName() {
        var tasks = [
            makeTask({id: "a", summary: "Alpha", calendarId: "cal-chores"}),
            makeTask({id: "b", summary: "Bravo", calendarId: "cal-fitness"})
        ]
        var r = TaskItems.selectTasks(tasks, cals, "fitn", false)
        compare(r.open.length, 1)
        compare(r.open[0].task.id, "b")
    }

    function test_selectTasks_annotatesListNameAndDue() {
        var tasks = [makeTask({id: "a", summary: "Alpha", allDay: true,
                               due: "2026-02-21T00:00:00Z"})]
        var r = TaskItems.selectTasks(tasks, cals, "", false)
        compare(r.open[0].listName, "Chores")
        compare(r.open[0].due, "Feb 21")
    }

    function test_selectTasks_unknownCalendarGivesEmptyListName() {
        var tasks = [makeTask({id: "a", summary: "Alpha", calendarId: "gone"})]
        var r = TaskItems.selectTasks(tasks, {}, "", false)
        compare(r.open.length, 1)
        compare(r.open[0].listName, "")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Expected: FAIL, `selectTasks` is not a function.

- [ ] **Step 3: Write the minimal implementation**

Append to `TaskItems.js`:

```js
function selectTasks(tasks, calendars, query, showCompleted) {
    var open = []
    var done = []
    var needle = (query || "").toLowerCase()
    var cals = calendars || {}
    var list = Array.isArray(tasks) ? tasks : []

    for (var i = 0; i < list.length; i++) {
        var task = list[i]
        if (!task || task.status === "cancelled")
            continue

        var cal = cals[task.calendarId]
        var listName = cal ? cal.name : ""
        var summary = task.summary || ""

        if (needle.length > 0
            && summary.toLowerCase().indexOf(needle) === -1
            && listName.toLowerCase().indexOf(needle) === -1)
            continue

        var entry = {
            task: task,
            listName: listName,
            due: dueLabel(task.due, task.allDay === true)
        }

        if (task.status === "completed") {
            if (showCompleted)
                done.push(entry)
        } else {
            open.push(entry)
        }
    }

    open.sort(_byDueThenSummary)
    done.sort(_byCompletedDesc)
    return {open: open, done: done}
}

function _byDueThenSummary(a, b) {
    var ta = _timeOf(a.task.due)
    var tb = _timeOf(b.task.due)
    if (ta !== tb)
        return ta - tb

    var sa = (a.task.summary || "").toLowerCase()
    var sb = (b.task.summary || "").toLowerCase()
    if (sa < sb)
        return -1
    return sa > sb ? 1 : 0
}

function _byCompletedDesc(a, b) {
    return _timeOf(b.task.completed) - _timeOf(a.task.completed)
}

// Undated sorts last; Infinity keeps it there without a special case in the
// comparators. Infinity - Infinity is NaN, so equal-undated pairs fall through
// to the summary tiebreak only because _byDueThenSummary compares before
// subtracting.
function _timeOf(value) {
    if (!value)
        return Infinity
    var t = new Date(value).getTime()
    return isNaN(t) ? Infinity : t
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Expected: PASS. If `test_selectTasks_undatedTiesBreakBySummary` fails, the
comparator subtracted two `Infinity` values before reaching the summary tiebreak —
`_byDueThenSummary` must compare `ta !== tb` first, not `ta - tb`.

- [ ] **Step 5: Commit**

```bash
git add TaskItems.js tests/tst_TaskItems.qml
git commit -m "feat: filter, bucket, and order tasks for the launcher list"
```

---

### Task 4: Action encoding and decoding

**Files:**
- Modify: `TaskItems.js`
- Test: `tests/tst_TaskItems.qml`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `createAction(summary) -> string`
  - `toggleAction(id, nextCompleted) -> string`
  - `parseAction(action) -> {type: "create", summary} | {type: "toggle", id, completed} | {type: "noop"}`

`summary` is arbitrary user text and may contain `:`, so `create` keeps everything
after the first separator. A task id is a UUID, so `toggle` splits its trailing
boolean from the right.

- [ ] **Step 1: Write the failing test**

Append inside the existing `TestCase`:

```qml
    function test_createAction_roundTrips() {
        var a = TaskItems.createAction("buy milk")
        var p = TaskItems.parseAction(a)
        compare(p.type, "create")
        compare(p.summary, "buy milk")
    }

    function test_createAction_preservesColonsInSummary() {
        var a = TaskItems.createAction("standup: prep notes: 10am")
        var p = TaskItems.parseAction(a)
        compare(p.type, "create")
        compare(p.summary, "standup: prep notes: 10am")
    }

    function test_toggleAction_roundTripsTrue() {
        var a = TaskItems.toggleAction("aad244a3-93dd-411c-a020-9c37cdfb799b", true)
        var p = TaskItems.parseAction(a)
        compare(p.type, "toggle")
        compare(p.id, "aad244a3-93dd-411c-a020-9c37cdfb799b")
        compare(p.completed, true)
    }

    function test_toggleAction_roundTripsFalse() {
        var p = TaskItems.parseAction(TaskItems.toggleAction("t-1", false))
        compare(p.type, "toggle")
        compare(p.id, "t-1")
        compare(p.completed, false)
    }

    function test_parseAction_noopForUnknownOrEmpty() {
        compare(TaskItems.parseAction("noop").type, "noop")
        compare(TaskItems.parseAction("").type, "noop")
        compare(TaskItems.parseAction(undefined).type, "noop")
        compare(TaskItems.parseAction("whatever:1").type, "noop")
    }

    function test_parseAction_createWithEmptySummaryIsNoop() {
        compare(TaskItems.parseAction("create:").type, "noop")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Expected: FAIL, `createAction` is not a function.

- [ ] **Step 3: Write the minimal implementation**

Append to `TaskItems.js`:

```js
function createAction(summary) {
    return "create:" + summary
}

function toggleAction(id, nextCompleted) {
    return "toggle:" + id + ":" + (nextCompleted ? "true" : "false")
}

function parseAction(action) {
    if (!action || typeof action !== "string")
        return {type: "noop"}

    var sep = action.indexOf(":")
    if (sep === -1)
        return {type: "noop"}

    var kind = action.substring(0, sep)
    var payload = action.substring(sep + 1)

    // A summary may contain ":", so everything after the first separator is text.
    if (kind === "create")
        return payload.length > 0 ? {type: "create", summary: payload} : {type: "noop"}

    // A task id is a UUID, so the trailing boolean splits from the right.
    if (kind === "toggle") {
        var last = payload.lastIndexOf(":")
        if (last === -1)
            return {type: "noop"}
        var id = payload.substring(0, last)
        if (id.length === 0)
            return {type: "noop"}
        return {type: "toggle", id: id, completed: payload.substring(last + 1) === "true"}
    }

    return {type: "noop"}
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add TaskItems.js tests/tst_TaskItems.qml
git commit -m "feat: encode and decode launcher item actions"
```

---

### Task 5: Building launcher items — the populated case

**Files:**
- Modify: `TaskItems.js`
- Test: `tests/tst_TaskItems.qml`

**Interfaces:**
- Consumes: `selectTasks` (Task 3), `createAction`/`toggleAction` (Task 4).
- Produces: `buildItems(state, query) -> Array` of launcher items.

The `state` object has exactly these fields; Task 7 constructs it:

```js
{
    tasksLoaded: bool,        // a tasks.list call has parsed successfully at least once
    calendarsLoaded: bool,    // same for calendars.list
    error: string,            // last failure, "" when none
    tasks: Array,             // parseTasks(...).tasks
    calendars: Object,        // parseCalendars(...).calendars
    defaultCalendarId: string,
    showCompleted: bool
}
```

Every item is `{name, icon, comment, action, categories: ["Tasks"], _preScored}`.

Order and scores:
1. Create item, only when `query` is non-empty — `_preScored: 100000`.
2. Open tasks — `_preScored` from 90000 descending.
3. Completed tasks — `_preScored` from 80000 descending.

Task 6 covers the degraded states; this task assumes `tasksLoaded` and
`calendarsLoaded` are true, `error` is `""`, and `defaultCalendarId` names a
known calendar.

- [ ] **Step 1: Write the failing test**

Append inside the existing `TestCase`:

```qml
    function readyState(over) {
        var base = {
            tasksLoaded: true,
            calendarsLoaded: true,
            error: "",
            tasks: [],
            calendars: cals,
            defaultCalendarId: "cal-chores",
            showCompleted: false
        }
        for (var k in over)
            base[k] = over[k]
        return base
    }

    function test_buildItems_createItemIsFirstAndLabelledWithQuery() {
        var items = TaskItems.buildItems(readyState({}), "buy milk")
        compare(items[0].name, "Create task: buy milk")
        compare(items[0].comment, "in Chores")
        compare(items[0].icon, "material:add_task")
        compare(items[0].action, "create:buy milk")
        compare(items[0]._preScored, 100000)
    }

    function test_buildItems_noCreateItemWithoutQuery() {
        var items = TaskItems.buildItems(
            readyState({tasks: [makeTask({id: "a", summary: "Alpha"})]}), "")
        compare(items.length, 1)
        compare(items[0].name, "Alpha")
    }

    function test_buildItems_openTaskItemShape() {
        var items = TaskItems.buildItems(readyState({
            tasks: [makeTask({id: "a", summary: "Alpha", allDay: true,
                              due: "2026-02-21T00:00:00Z"})]
        }), "")
        compare(items[0].name, "Alpha")
        compare(items[0].icon, "material:radio_button_unchecked")
        compare(items[0].comment, "Chores · due Feb 21")
        compare(items[0].action, "toggle:a:true")
        compare(items[0]._preScored, 90000)
        compare(items[0].categories.length, 1)
        compare(items[0].categories[0], "Tasks")
    }

    function test_buildItems_openTaskWithoutDueOmitsDueSuffix() {
        var items = TaskItems.buildItems(
            readyState({tasks: [makeTask({id: "a", summary: "Alpha"})]}), "")
        compare(items[0].comment, "Chores")
    }

    function test_buildItems_unknownCalendarLeavesCommentEmpty() {
        var items = TaskItems.buildItems(readyState({
            tasks: [makeTask({id: "a", summary: "Alpha", calendarId: "gone"})]
        }), "")
        compare(items[0].comment, "")
    }

    function test_buildItems_completedTaskItemShape() {
        var items = TaskItems.buildItems(readyState({
            showCompleted: true,
            tasks: [makeTask({id: "b", summary: "Bravo", status: "completed",
                              completed: "2026-08-21T10:00:00Z"})]
        }), "")
        compare(items[0].name, "Bravo")
        compare(items[0].icon, "material:check_circle")
        compare(items[0].action, "toggle:b:false")
        compare(items[0]._preScored, 80000)
    }

    function test_buildItems_orderIsCreateThenOpenThenCompleted() {
        var items = TaskItems.buildItems(readyState({
            showCompleted: true,
            tasks: [
                makeTask({id: "b", summary: "match done", status: "completed",
                          completed: "2026-08-21T10:00:00Z"}),
                makeTask({id: "a", summary: "match open"})
            ]
        }), "match")
        compare(items.length, 3)
        compare(items[0].action, "create:match")
        compare(items[1].name, "match open")
        compare(items[2].name, "match done")
    }

    function test_buildItems_preScoredStrictlyDescending() {
        var items = TaskItems.buildItems(readyState({
            showCompleted: true,
            tasks: [
                makeTask({id: "a", summary: "Alpha"}),
                makeTask({id: "c", summary: "Charlie"}),
                makeTask({id: "b", summary: "Bravo", status: "completed",
                          completed: "2026-08-21T10:00:00Z"})
            ]
        }), "a")
        verify(items.length > 1)
        for (var i = 1; i < items.length; i++)
            verify(items[i]._preScored < items[i - 1]._preScored)
    }

    function test_buildItems_allItemsAreScoredAbove900() {
        var items = TaskItems.buildItems(readyState({
            tasks: [makeTask({id: "a", summary: "Alpha"})]
        }), "")
        for (var i = 0; i < items.length; i++)
            verify(items[i]._preScored > 900)
    }

    function test_buildItems_queryFiltersTasksButKeepsCreateItem() {
        var items = TaskItems.buildItems(readyState({
            tasks: [
                makeTask({id: "a", summary: "Find therapist"}),
                makeTask({id: "b", summary: "Buy milk"})
            ]
        }), "zzz")
        compare(items.length, 1)
        compare(items[0].action, "create:zzz")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Expected: FAIL, `buildItems` is not a function.

- [ ] **Step 3: Write the minimal implementation**

Append to `TaskItems.js`:

```js
var CATEGORIES = ["Tasks"]

var SCORE_CREATE = 100000
var SCORE_OPEN = 90000
var SCORE_DONE = 80000

function buildItems(state, query) {
    var q = query || ""
    var items = []

    if (q.length > 0)
        items.push(_createItem(state, q))

    var picked = selectTasks(state.tasks, state.calendars, q, state.showCompleted)

    for (var i = 0; i < picked.open.length; i++)
        items.push(_taskItem(picked.open[i], false, SCORE_OPEN - i))

    for (var j = 0; j < picked.done.length; j++)
        items.push(_taskItem(picked.done[j], true, SCORE_DONE - j))

    return items
}

function _createItem(state, query) {
    var cal = state.calendars ? state.calendars[state.defaultCalendarId] : null
    return {
        name: "Create task: " + query,
        icon: "material:add_task",
        comment: "in " + cal.name,
        action: createAction(query),
        categories: CATEGORIES,
        _preScored: SCORE_CREATE
    }
}

function _taskItem(entry, isDone, score) {
    var comment = entry.listName
    if (entry.due.length > 0)
        comment = comment.length > 0 ? comment + " · due " + entry.due : "due " + entry.due

    return {
        name: entry.task.summary || "",
        icon: isDone ? "material:check_circle" : "material:radio_button_unchecked",
        comment: comment,
        action: toggleAction(entry.task.id, !isDone),
        categories: CATEGORIES,
        _preScored: score
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Expected: PASS. `_createItem` dereferences `cal.name` without a guard — that is
deliberate and Task 6 adds the guard along with the test that demands it.

- [ ] **Step 5: Commit**

```bash
git add TaskItems.js tests/tst_TaskItems.qml
git commit -m "feat: build launcher items for tasks and task creation"
```

---

### Task 6: Building launcher items — degraded states

**Files:**
- Modify: `TaskItems.js`
- Test: `tests/tst_TaskItems.qml`

**Interfaces:**
- Consumes: `buildItems` (Task 5).
- Produces: no new exports. `buildItems` gains the states below, each returning
  exactly one item whose `action` is `"noop"`.

| Condition | name | comment |
|---|---|---|
| `error` set and `tasksLoaded` false | `dcal is not running` | `Start it with: dcal run -d` |
| `tasksLoaded` false, no error | `Loading tasks…` | `""` |
| `calendarsLoaded` true and `defaultCalendarId` empty or unknown, with a query | `Set a default task list in plugin settings` | `Plugin settings → Dcal Tasks → Default task list` |
| loaded, no tasks, no query | `No tasks` | `Type to create one` |

A failed refresh that has a previous good cache (`tasksLoaded` true with `error`
set) keeps showing the cache — the error item appears only when there is nothing
to show. While `calendarsLoaded` is false the create item stays optimistic rather
than accusing the user of not configuring a list that simply has not loaded yet.

- [ ] **Step 1: Write the failing test**

Append inside the existing `TestCase`:

```qml
    function test_buildItems_daemonDownShowsSingleErrorItem() {
        var items = TaskItems.buildItems(readyState({
            tasksLoaded: false, calendarsLoaded: false,
            error: "dcal daemon not running"
        }), "")
        compare(items.length, 1)
        compare(items[0].name, "dcal is not running")
        compare(items[0].comment, "Start it with: dcal run -d")
        compare(items[0].action, "noop")
        compare(items[0].categories[0], "Tasks")
        verify(items[0]._preScored > 900)
    }

    function test_buildItems_errorItemWinsEvenWithAQuery() {
        var items = TaskItems.buildItems(readyState({
            tasksLoaded: false, error: "boom"
        }), "buy milk")
        compare(items.length, 1)
        compare(items[0].action, "noop")
    }

    function test_buildItems_coldCacheShowsLoading() {
        var items = TaskItems.buildItems(readyState({
            tasksLoaded: false, calendarsLoaded: false, error: ""
        }), "")
        compare(items.length, 1)
        compare(items[0].name, "Loading tasks…")
        compare(items[0].action, "noop")
    }

    function test_buildItems_staleCacheSurvivesAFailedRefresh() {
        var items = TaskItems.buildItems(readyState({
            error: "dcal daemon not running",
            tasks: [makeTask({id: "a", summary: "Alpha"})]
        }), "")
        compare(items.length, 1)
        compare(items[0].name, "Alpha")
    }

    function test_buildItems_noDefaultListReplacesCreateItem() {
        var items = TaskItems.buildItems(
            readyState({defaultCalendarId: ""}), "buy milk")
        compare(items[0].name, "Set a default task list in plugin settings")
        compare(items[0].comment, "Plugin settings → Dcal Tasks → Default task list")
        compare(items[0].action, "noop")
        compare(items[0]._preScored, 100000)
    }

    function test_buildItems_deletedDefaultListReplacesCreateItem() {
        var items = TaskItems.buildItems(
            readyState({defaultCalendarId: "cal-deleted"}), "buy milk")
        compare(items[0].name, "Set a default task list in plugin settings")
        compare(items[0].action, "noop")
    }

    // Calendars arrive on their own IPC call. Until it lands, an unknown id
    // means "not loaded yet", not "misconfigured".
    function test_buildItems_unloadedCalendarsKeepCreateItemOptimistic() {
        var items = TaskItems.buildItems(readyState({
            calendarsLoaded: false, calendars: {}, defaultCalendarId: "cal-chores"
        }), "buy milk")
        compare(items[0].action, "create:buy milk")
        compare(items[0].name, "Create task: buy milk")
        compare(items[0].comment, "in the default task list")
    }

    function test_buildItems_emptyListWithNoQuery() {
        var items = TaskItems.buildItems(readyState({tasks: []}), "")
        compare(items.length, 1)
        compare(items[0].name, "No tasks")
        compare(items[0].comment, "Type to create one")
        compare(items[0].action, "noop")
    }

    function test_buildItems_allTasksHiddenByToggleStillShowsEmptyState() {
        var items = TaskItems.buildItems(readyState({
            showCompleted: false,
            tasks: [makeTask({id: "b", summary: "Bravo", status: "completed",
                              completed: "2026-08-21T10:00:00Z"})]
        }), "")
        compare(items.length, 1)
        compare(items[0].name, "No tasks")
    }

    function test_buildItems_noEmptyStateItemWhenQueryPresent() {
        var items = TaskItems.buildItems(readyState({tasks: []}), "zzz")
        compare(items.length, 1)
        compare(items[0].action, "create:zzz")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Expected: FAIL. `test_buildItems_daemonDownShowsSingleErrorItem` reports
`Loading tasks…` was never produced (the function returns an empty array), and
`test_buildItems_noDefaultListReplacesCreateItem` fails with a TypeError on
`cal.name`.

- [ ] **Step 3: Write the minimal implementation**

Replace `buildItems` and `_createItem` in `TaskItems.js` with:

```js
function buildItems(state, query) {
    var q = query || ""

    // Only claim a failure when there is no cache to fall back on. A refresh
    // that fails while a good list is already loaded keeps showing that list.
    if (!state.tasksLoaded && state.error && state.error.length > 0)
        return [_noopItem("dcal is not running", "Start it with: dcal run -d")]

    if (!state.tasksLoaded)
        return [_noopItem("Loading tasks…", "")]

    var items = []
    if (q.length > 0)
        items.push(_createItem(state, q))

    var picked = selectTasks(state.tasks, state.calendars, q, state.showCompleted)

    for (var i = 0; i < picked.open.length; i++)
        items.push(_taskItem(picked.open[i], false, SCORE_OPEN - i))

    for (var j = 0; j < picked.done.length; j++)
        items.push(_taskItem(picked.done[j], true, SCORE_DONE - j))

    if (items.length === 0)
        items.push(_noopItem("No tasks", "Type to create one"))

    return items
}

function _createItem(state, query) {
    var cals = state.calendars || {}
    var cal = cals[state.defaultCalendarId]

    // While calendars are still loading an unknown id means "not fetched yet",
    // not "misconfigured", so stay optimistic and keep the item actionable.
    if (!cal && state.calendarsLoaded) {
        return {
            name: "Set a default task list in plugin settings",
            icon: "material:add_task",
            comment: "Plugin settings → Dcal Tasks → Default task list",
            action: "noop",
            categories: CATEGORIES,
            _preScored: SCORE_CREATE
        }
    }

    return {
        name: "Create task: " + query,
        icon: "material:add_task",
        comment: cal ? "in " + cal.name : "in the default task list",
        action: createAction(query),
        categories: CATEGORIES,
        _preScored: SCORE_CREATE
    }
}

function _noopItem(name, comment) {
    return {
        name: name,
        icon: "material:task_alt",
        comment: comment,
        action: "noop",
        categories: CATEGORIES,
        _preScored: SCORE_CREATE
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Expected: PASS, all of Tasks 1–6 (roughly 45 test functions).

- [ ] **Step 5: Re-run under two timezones as a regression check**

```bash
TZ=America/Los_Angeles QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
TZ=Pacific/Kiritimati QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Expected: PASS in both.

- [ ] **Step 6: Commit**

```bash
git add TaskItems.js tests/tst_TaskItems.qml
git commit -m "feat: handle daemon-down, loading, empty, and unconfigured states"
```

---

### Task 7: Launcher surface and plugin manifest

**Files:**
- Create: `plugin.json`
- Create: `DcalTasksLauncher.qml`

**Interfaces:**
- Consumes: every export of `TaskItems.js`.
- Produces: the DMS launcher contract — `getItems(query)`, `executeItem(item)`,
  the `trigger` property, and the `itemsChanged()` signal (declared for contract
  conformance; DMS 1.5.3 does not connect to it).

This task cannot be unit tested — `Process` and `pluginService` need a live
Quickshell. It is verified by loading it into DMS in Step 4.

- [ ] **Step 1: Write the manifest**

Create `plugin.json`:

```json
{
  "id": "dcalTasks",
  "name": "Dcal Tasks",
  "description": "List, search, create, and complete dcal tasks from the launcher.",
  "version": "0.1.0",
  "author": "Anton Kalodzich",
  "icon": "task_alt",
  "type": "launcher",
  "capabilities": ["launcher"],
  "component": "./DcalTasksLauncher.qml",
  "settings": "./DcalTasksSettings.qml",
  "trigger": ";",
  "requires_dms": ">=1.5.0",
  "requires": ["dcal"],
  "permissions": ["settings_read", "settings_write", "process"]
}
```

- [ ] **Step 2: Write the launcher surface**

Create `DcalTasksLauncher.qml`:

```qml
import QtQuick
import Quickshell.Io
import "TaskItems.js" as TaskItems

Item {
    id: root

    property var pluginService: null
    property string trigger: ";"

    readonly property string pluginName: "dcalTasks"

    signal itemsChanged

    property string defaultCalendarId: ""
    property bool showCompleted: false

    property var tasks: []
    property var calendars: ({})
    property bool tasksLoaded: false
    property bool calendarsLoaded: false
    property string lastError: ""
    property double lastRefreshMs: 0

    readonly property int staleAfterMs: 2000

    Component.onCompleted: loadSettings()

    onPluginServiceChanged: {
        if (pluginService)
            loadSettings()
    }

    Connections {
        target: root.pluginService
        enabled: root.pluginService !== null

        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginName) {
                root.loadSettings()
                root.refresh()
            }
        }
    }

    function loadSettings() {
        if (!pluginService)
            return
        trigger = pluginService.loadPluginData(pluginName, "trigger", ";")
        defaultCalendarId = pluginService.loadPluginData(pluginName, "defaultCalendarId", "")
        showCompleted = pluginService.loadPluginData(pluginName, "showCompleted", false) === true
    }

    // The DMS launcher calls this synchronously on every keystroke, so it must
    // never block. Return whatever is cached and let the refresh land later.
    function getItems(query) {
        refreshIfStale()
        return TaskItems.buildItems({
            tasksLoaded: root.tasksLoaded,
            calendarsLoaded: root.calendarsLoaded,
            error: root.lastError,
            tasks: root.tasks,
            calendars: root.calendars,
            defaultCalendarId: root.defaultCalendarId,
            showCompleted: root.showCompleted
        }, query || "")
    }

    function executeItem(item) {
        const parsed = TaskItems.parseAction(item ? item.action : "")

        if (parsed.type === "create") {
            if (!defaultCalendarId)
                return
            mutateProcess.command = ["dcal", "ipc", "tasks.create",
                                     "calendarId=" + defaultCalendarId,
                                     "summary=" + parsed.summary]
            mutateProcess.running = true
        } else if (parsed.type === "toggle") {
            mutateProcess.command = ["dcal", "ipc", "tasks.complete",
                                     "id=" + parsed.id,
                                     "completed=" + (parsed.completed ? "true" : "false")]
            mutateProcess.running = true
        }
    }

    function refreshIfStale() {
        if (Date.now() - lastRefreshMs < staleAfterMs)
            return
        refresh()
    }

    function refresh() {
        lastRefreshMs = Date.now()
        if (!tasksProcess.running)
            tasksProcess.running = true
        if (!calendarsProcess.running)
            calendarsProcess.running = true
    }

    // Controller.qml:135 re-runs the launcher search on this signal, and
    // early-returns when the launcher is closed, so this is free when nobody
    // is looking.
    function notifyLauncher() {
        if (pluginService && pluginService.requestLauncherUpdate)
            pluginService.requestLauncherUpdate(pluginName)
        itemsChanged()
    }

    Process {
        id: tasksProcess
        command: ["dcal", "ipc", "tasks.list"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const result = TaskItems.parseTasks(text)
                if (result.ok) {
                    root.tasks = result.tasks
                    root.tasksLoaded = true
                    root.lastError = ""
                } else {
                    root.lastError = result.error
                }
            }
        }

        onExited: root.notifyLauncher()
    }

    Process {
        id: calendarsProcess
        command: ["dcal", "ipc", "calendars.list"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const result = TaskItems.parseCalendars(text)
                if (result.ok) {
                    root.calendars = result.calendars
                    root.calendarsLoaded = true
                }
            }
        }

        onExited: root.notifyLauncher()
    }

    Process {
        id: mutateProcess
        running: false

        // Force the next getItems to refetch rather than serve the pre-mutation
        // cache. The launcher normally closes right after executeItem, so this
        // is usually observed on the next open.
        onExited: {
            root.lastRefreshMs = 0
            root.refresh()
        }
    }
}
```

- [ ] **Step 3: Check the QML parses**

```bash
QT_QPA_PLATFORM=offscreen qmllint6 DcalTasksLauncher.qml 2>&1 | head -20
```

Expected: warnings about the unresolved `Quickshell.Io` import are fine — that
module only exists inside a Quickshell process. Syntax errors are not; fix those.
If `qmllint6` is unavailable, skip this step; Step 4 catches the same failures.

- [ ] **Step 4: Load it into DMS and verify by hand**

```bash
ln -sfn "$PWD" ~/.config/DankMaterialShell/plugins/dcalTasks
dms ipc call plugin-scan rescan
dms ipc call plugins enable dcalTasks
dms ipc call plugins list | grep dcalTasks
```

Expected: `dcalTasks [loaded]`. After any later edit to the QML, reload with
`dms ipc call plugins reload dcalTasks`. The CLI shape is
`dms ipc call <target> <function> [args]` — `dms ipc reload` is not valid.

`plugin.json` names `./DcalTasksSettings.qml`, which Task 8 creates. That is
fine: `PluginService._resolveComponentPaths` reads only `component`/`components`,
never `settings`, so the plugin loads normally and only the settings page is
unavailable until Task 8.

Then open the launcher and type `;`. Verify each of these:

1. The task list appears — at minimum "Find therapist", which is open in dcal.
2. Typing `;the` narrows to that task; typing `;zzz` leaves only the create item.
3. The create item reads `Set a default task list in plugin settings` — nothing
   is configured yet. Pressing Enter does nothing. This is the expected state
   until Task 8.
4. With `dcal kill` run first, `;` shows `dcal is not running`. Restart with
   `dcal run -d` and confirm the list comes back without reloading the plugin.

Do **not** test task creation yet; there is no configured list. Toggling
completion is safe to test: press Enter on a task, reopen the launcher, and
confirm it disappears (`showCompleted` is off by default). Reopen dcal and
un-complete it there, or set `showCompleted` after Task 8 and toggle it back.

- [ ] **Step 5: Commit**

```bash
git add plugin.json DcalTasksLauncher.qml
git commit -m "feat: add the launcher surface and plugin manifest"
```

---

### Task 8: Settings panel

**Files:**
- Create: `DcalTasksSettings.qml`

**Interfaces:**
- Consumes: `parseCalendars` from Task 1.
- Produces: the three settings keys `DcalTasksLauncher.qml` reads —
  `trigger` (string), `defaultCalendarId` (string), `showCompleted` (bool).

`SelectionSetting.options` is a plain `var` property and its derived
`optionLabels`/`valueToLabel`/`labelToValue` are `readonly property var`
bindings, so assigning `options` later re-evaluates all three. That is what makes
an asynchronously populated dropdown work.

- [ ] **Step 1: Write the settings component**

Create `DcalTasksSettings.qml`:

```qml
import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "TaskItems.js" as TaskItems

PluginSettings {
    id: root

    pluginId: "dcalTasks"

    property var calendarOptions: [{label: "Loading task lists…", value: ""}]

    Component.onCompleted: calendarsProcess.running = true

    Process {
        id: calendarsProcess
        command: ["dcal", "ipc", "calendars.list"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const result = TaskItems.parseCalendars(text)
                if (!result.ok) {
                    root.calendarOptions = [{label: "dcal is not running", value: ""}]
                    return
                }

                const options = []
                for (const id in result.calendars) {
                    const cal = result.calendars[id]
                    if (!cal.holdsTasks || cal.readOnly)
                        continue
                    options.push({
                        label: cal.accountName ? cal.accountName + " — " + cal.name : cal.name,
                        value: cal.id
                    })
                }
                options.sort((a, b) => a.label < b.label ? -1 : (a.label > b.label ? 1 : 0))

                root.calendarOptions = options.length > 0
                    ? options
                    : [{label: "No writable task lists found", value: ""}]
            }
        }
    }

    StyledText {
        width: parent.width
        text: "Reload the plugin after changing the trigger."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "trigger"
        label: "Trigger prefix"
        description: "Type this prefix in the launcher to reach your tasks"
        placeholder: ";"
        defaultValue: ";"
    }

    SelectionSetting {
        settingKey: "defaultCalendarId"
        label: "Default task list"
        description: "New tasks are created in this list"
        defaultValue: ""
        options: root.calendarOptions
    }

    ToggleSetting {
        settingKey: "showCompleted"
        label: "Show completed tasks"
        description: "List completed tasks below the open ones"
        defaultValue: false
    }
}
```

- [ ] **Step 2: Reload and verify the picker populates**

```bash
dms ipc call plugins reload dcalTasks
```

Open DMS Settings → Plugins → Dcal Tasks. Verify:

1. The **Default task list** dropdown lists only writable task lists — on a
   machine with dcal task lists these appear as `Account — List`. Calendars with
   `holdsTasks: false` must be absent, and so must read-only ones.
2. Selecting one persists: check with
   `grep -A5 dcalTasks ~/.config/DankMaterialShell/plugin_settings.json`.
3. The trigger field shows `;` and the toggle shows off.

- [ ] **Step 3: Verify creation now works end to end**

Open the launcher, type `; plan the week`, and press Enter. Then:

```bash
dcal ipc tasks.list | grep -A3 'plan the week'
```

Expected: the task exists with the `calendarId` chosen in Step 2. Reopen the
launcher and confirm it now appears in the list.

- [ ] **Step 4: Verify the completed toggle**

Turn **Show completed tasks** on. Open the launcher, press Enter on
`plan the week` to complete it, then reopen: it should still be listed with a
filled check icon. Press Enter again to reopen the task.

- [ ] **Step 5: Clean up the test task**

```bash
dcal ipc tasks.list | grep -B2 -A3 'plan the week'
dcal ipc tasks.delete id=<the id printed above>
```

- [ ] **Step 6: Commit**

```bash
git add DcalTasksSettings.qml
git commit -m "feat: add settings with an async task-list picker"
```

---

### Task 9: README and final verification

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: everything.
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Write the README**

Create `README.md` covering, in this order:

- One-paragraph description: a DMS launcher plugin for
  [dcal](https://github.com/AvengeMedia/dankcalendar) tasks.
- **Requirements**: DankMaterialShell ≥ 1.5.0, dcal installed with its daemon
  running (`dcal run -d`). No other runtime dependencies.
- **Installation**, manual:
  ```bash
  git clone <repo> ~/.config/DankMaterialShell/plugins/dcalTasks
  ```
  and the Nix flake input form, copied from DankTodoLauncher's README structure
  but with this plugin's attribute name.
- **Setup**: open DMS Settings → Plugins → Dcal Tasks and pick a default task
  list, otherwise task creation is disabled and says so in the launcher.
- **Usage**: `;` lists every open task; `;<text>` filters and offers
  `Create task: <text>` as the first result; Enter on a task toggles it complete.
- **Settings**: the three keys, their defaults, and what each does.
- **Development**: how to run the tests, with the Qt5-vs-Qt6 warning:
  ```bash
  QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
  ```
  Note that `/usr/bin/qmltestrunner` may be the Qt5 build, which exits 1 with no
  output. Explain the `TaskItems.js` / QML split: pure logic is tested, side
  effects are not.
- **License**: MIT.

- [ ] **Step 2: Run the full test suite one final time**

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
TZ=America/Los_Angeles QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Expected: PASS in both, 0 failed, 0 skipped.

- [ ] **Step 3: Confirm the working tree is clean and the plugin still loads**

```bash
git status --short
dcal ipc tasks.list | head -5
```

Open the launcher, type `;`, and confirm the list renders. Then verify the
symlink used for development is not committed:

```bash
git ls-files | grep -c dcalTasks || echo "no stray symlink committed"
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

## Self-Review Notes

Spec coverage check against
`docs/superpowers/specs/2026-08-21-dcal-tasks-launcher-design.md`:

| Spec section | Covered by |
|---|---|
| Repository layout | Tasks 1, 7, 8, 9 |
| Manifest | Task 7 Step 1 |
| dcal IPC contract (4 calls) | Task 7 (`tasks.list`, `tasks.create`, `tasks.complete`), Tasks 7 & 8 (`calendars.list`) |
| All-day due dates | Task 2 |
| Instance lifetime / state | Task 7 |
| Read path | Task 7 (`getItems`, `refreshIfStale`, `notifyLauncher`) |
| Write path + action strings | Tasks 4 and 7 |
| Item construction and ordering | Task 5 |
| Error and empty states (7 rows) | Task 6 |
| Settings (3 controls) | Task 8 |
| Unit testing (8 case groups) | Tasks 1–6 |
| Manual testing | Tasks 7 Step 4, 8 Steps 2–5, 9 Step 3 |

Known deviations, both deliberate and recorded above: `tasks.list` is always
called without `includeCompleted`, and the spec's `/usr/bin/qmltestrunner` path
is replaced by the Qt6 binary throughout.

**Plan validation.** Before publishing this plan the `TaskItems.js` and
`tests/tst_TaskItems.qml` sources above were assembled verbatim and executed:
48 test functions, 50 assertions, 0 failures, under `TZ` of `UTC`,
`America/Los_Angeles`, `Pacific/Kiritimati`, and `Asia/Kolkata`. Two mutation
checks confirmed the diagnostics quoted in the plan are real: removing the
all-day UTC shift fails 4 tests outside UTC (and none inside it), and rewriting
the `ta !== tb` guard as `ta - tb !== 0` fails
`test_selectTasks_undatedTiesBreakBySummary`. Tasks 7–9 are QML and manual, and
were not executed.
