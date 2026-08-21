# DcalTasks — DMS launcher plugin for dcal tasks

Date: 2026-08-21
Status: approved for implementation

## Purpose

Manage [dcal](https://github.com/AvengeMedia/dankcalendar) tasks from the
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) launcher:
see every open task, search it, toggle one complete, and capture a new task
without leaving the launcher.

The reference for plugin structure is
[DankTodoLauncher](https://github.com/iskepr/DankTodoLauncher); the reference
for talking to dcal is the installed `dcalUpcoming` widget and
[arqueon/dms-dankcalendar](https://github.com/arqueon/dms-dankcalendar).

## Scope

In scope for v1:

- List tasks from every task-capable calendar.
- Substring search over task summary and list name.
- First result creates a task named after the current query, in a default
  task list chosen in plugin settings.
- Enter on an existing task toggles it complete / reopened.
- Settings: trigger, default task list, show-completed toggle.

Out of scope for v1: due dates, priorities, descriptions, subtasks,
reordering, deleting tasks, editing a task's text, creating task lists,
and per-list filtering inside the launcher.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Transport | `dcal ipc <method> k=v` as a subprocess | Matches every existing DMS↔dcal plugin; no socket discovery or reconnect logic. |
| Enter on a task | `tasks.complete` toggle | The one action worth a keystroke in a launcher. |
| Completed tasks | Hidden, revealed by a settings toggle | Keeps the default list to what is still open. |
| Task sources | All calendars with `holdsTasks: true` | The default list only decides where *new* tasks go. |
| Default trigger | `;` | Free on a stock DMS + common plugin set; single char, cannot collide with a word. |
| Freshness | Refresh when stale on `getItems`, plus after mutations | A launcher plugin is only read when the launcher is open, so polling is waste. |

### Transport: why not the socket

dcal's own UI (`quickshell/Services/DankCalService.qml`) opens
`$XDG_RUNTIME_DIR/dankcal-<pid>.sock` with `DankSocket` and issues
`subscribe topics=tasks`, which gives push updates and no subprocess per call.
That removes cache staleness entirely and is the natural v2 upgrade. It costs
socket discovery, connect/reconnect handling, and request-id correlation — around
150 lines that v1 does not need. The `TaskItems.js` interface below is transport
agnostic, so swapping later touches only the QML.

### Transport: why not bash + jq

`dcalUpcoming` and `dms-dankcalendar` both wrap `dcal ipc` in a bash script that
pipes through `jq`. They need it: both do time-window filtering and
next-event selection that is awkward in QML. `tasks.list` needs neither. Calling
`["dcal", "ipc", "tasks.list"]` as argv directly drops the `jq` runtime
dependency, drops shell quoting concerns for arbitrary task text, and puts the
logic somewhere it can be unit tested.

## Repository layout

```
plugin.json               DMS manifest
DcalTasksLauncher.qml     launcher surface: getItems / executeItem, Process wiring
DcalTasksSettings.qml     PluginSettings form
TaskItems.js              pure logic: parse, filter, sort, format, build items
tests/tst_TaskItems.qml   qmltestrunner TestCase over TaskItems.js
README.md
LICENSE                   MIT
```

Everything with side effects (`Process`, `pluginService` reads and writes) lives
in the QML. Everything decidable lives in `TaskItems.js` and is tested. This
mirrors dcal's own `Common/EventUtils.js` + `tests/tst_EventUtils.qml` split.

## Manifest

```json
{
  "id": "dcalTasks",
  "name": "Dcal Tasks",
  "type": "launcher",
  "capabilities": ["launcher"],
  "component": "./DcalTasksLauncher.qml",
  "settings": "./DcalTasksSettings.qml",
  "trigger": ";",
  "icon": "task_alt",
  "requires_dms": ">=1.5.0",
  "requires": ["dcal"],
  "permissions": ["settings_read", "settings_write", "process"]
}
```

`requires_dms` is `>=1.5.0` because 1.5.3 is the only version this is verified
against, though nothing used here is newer than the 1.4 launcher contract.

## dcal IPC contract

Verified against a running dcal daemon on 2026-08-21. All four calls are used
as argv arrays, never through a shell.

| Call | Used for |
|---|---|
| `dcal ipc tasks.list [includeCompleted=false]` | The task cache. Returns `{"tasks": [...], "total": n}`. |
| `dcal ipc calendars.list` | List names for subtitles, and the settings picker. Returns a bare array. |
| `dcal ipc tasks.create calendarId=<id> summary=<text>` | The create item. |
| `dcal ipc tasks.complete id=<id> completed=<true\|false>` | The toggle action. |

Task fields consumed: `id`, `summary`, `status`, `calendarId`, `due`, `allDay`,
`completed`. Calendar fields consumed: `id`, `name`, `accountName`,
`holdsTasks`, `readOnly`.

`dcal ipc` writes pretty-printed JSON to stdout, exits non-zero on failure, and
prints `dcal daemon not running: ...` to stderr when the daemon is down.

### All-day due dates

dcal serialises all-day values as UTC midnight: the task "Find therapist" has
`allDay: true` with `due: "2026-02-21T00:00:00Z"`. Rendering that with a local
formatter shows the previous day for any user west of UTC. `TaskItems.js` must
shift all-day values to local midnight before formatting. This is the same trap
documented at length in `dms-dankcalendar`'s `get-next-event`.

## Architecture

### Instance lifetime

`PluginService` creates one launcher instance per plugin at load time and keeps
it (`Services/PluginService.qml:412`), so the instance can hold an async cache.
`AppSearchService.getPluginItemsForPlugin` falls back to a throwaway instance
only when no persistent one exists; in that path the cache is empty and the
plugin reports the loading state rather than a wrong empty list.

### State

- `tasks` — last successful `tasks.list` payload.
- `calendars` — id → `{name, accountName, holdsTasks, readOnly}`.
- `lastRefreshMs`, `loading`, `lastError`.
- Settings mirrors: `trigger`, `defaultCalendarId`, `showCompleted`.

### Read path

1. `getItems(query)` calls `refreshIfStale()` and returns from cache
   immediately. It never blocks and never waits on a process.
2. `refreshIfStale()` starts `tasks.list` and `calendars.list` if the last
   refresh is older than 2000 ms and no refresh is in flight.
3. Each `Process` collects stdout with `StdioCollector` and hands the raw text
   to `TaskItems.parseTasks` / `TaskItems.parseCalendars`, which return
   `{ok, value, error}` rather than throwing.
4. `getItems` delegates entirely to `TaskItems.buildItems(state, query)`.
5. When a refresh lands and changes the cache, the plugin emits
   `pluginService.requestLauncherUpdate("dcalTasks")`. `Controller.qml:135`
   re-runs `performSearch()` on that signal, so an open launcher repaints with
   the fresh data; the handler early-returns when the launcher is closed, so a
   background refresh costs nothing. This is the working equivalent of the
   contract's `itemsChanged()` signal, which nothing in DMS 1.5.3 listens to.

### Write path

`executeItem(item)` parses `item.action` as `type:payload`, runs the matching
`dcal ipc` call, and on process exit invalidates `lastRefreshMs` and triggers a
refresh. The launcher closes itself after `executeItem` (`Controller.qml:2006`),
so the refreshed cache is normally observed on the next open rather than in
place.

Action strings:

- `create:<summary>` → `tasks.create`
- `toggle:<id>:<nextCompletedBool>` → `tasks.complete`
- `noop` → ignored

`summary` may contain `:`; the payload is everything after the first separator.
For `toggle` the id is a UUID and the trailing bool is split from the right.

## Item construction

`TaskItems.buildItems(state, query)` is the whole display contract. Ordering is
expressed with descending `_preScored`, which the launcher honours verbatim for
any value above 900 (`Modals/DankLauncherV2/Scorer.js:157`). Under a trigger the
launcher applies no per-section cap (`Controller.qml:748` passes 500).

Order:

1. **Create item** — only when `query` is non-empty.
   `_preScored: 100000`, icon `material:add_task`,
   name `Create task: <query>`, comment `in <default list name>`.
2. **Open tasks** — `_preScored` from 90000 descending, icon
   `material:radio_button_unchecked`, name = summary, comment = list name,
   plus ` · due <date>` when the task has a due date.
3. **Completed tasks** — only when `showCompleted` is on. `_preScored` from
   80000 descending, icon `material:check_circle`, comment = list name.

All items carry `categories: ["Tasks"]`.

Within open tasks: soonest due date first, undated last, then alphabetical by
summary for a stable order. Completed tasks sort by completion time, most
recent first.

Search is case-insensitive substring over summary and list name. The query
arrives already trimmed — DMS does `query.substring(trigger.length).trim()`
(`Controller.qml:1322`) — so a task cannot be created with leading or trailing
whitespace, and no trimming is needed on our side.

## Error and empty states

Each state is a single non-actionable item so the launcher never shows a bare
empty list, and each is decided in `TaskItems.js` so each is testable.

| Condition | Name | Comment |
|---|---|---|
| `dcal` missing or daemon down | `dcal is not running` | `Start it with: dcal run -d` |
| Output did not parse | `Could not read tasks from dcal` | the parse error |
| Cache still cold | `Loading tasks…` | — |
| No tasks, no query | `No tasks` | `Type to create one` |
| Query matches nothing | — no item — | only the create item is shown |
| No default list configured | `Set a default task list in plugin settings` | replaces the create item, action `noop` |
| Default list id no longer exists | same as above | the configured list was deleted or is no longer syncing |

A failed refresh keeps the previous cache rather than blanking it; the error
item is shown only when there is nothing cached to show.

## Settings

`DcalTasksSettings.qml` is a `PluginSettings` with three controls:

- `StringSetting` `trigger`, default `;`.
- `SelectionSetting` `defaultCalendarId`. `options` is a plain `var` property,
  so it can be bound to a list populated asynchronously from `calendars.list`,
  filtered to `holdsTasks && !readOnly`, each labelled `<accountName> — <name>`.
  Until the call returns the dropdown shows the stored raw value, which
  `SelectionSetting` already falls back to.
- `ToggleSetting` `showCompleted`, default false.

The launcher surface re-reads all three in `loadSettings()`, called from
`Component.onCompleted` and from `onPluginServiceChanged`.

## Testing

**Unit — `qmltestrunner`.** Use the **Qt6** runner at
`/usr/lib/qt6/bin/qmltestrunner`; `/usr/bin/qmltestrunner` is the Qt5 build from
`qt5-declarative` and exits 1 with no output at all against Qt6 QML. Run headless:

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Fixtures are real captured `tasks.list` and `calendars.list` payloads. Cases:

- parse: valid payload, malformed JSON, empty `tasks`, a bare array from
  `calendars.list`, and stderr-only output.
- ordering: open before completed; due-date ascending; undated last;
  `_preScored` strictly descending across the whole list.
- search: case-insensitive; matches summary; matches list name; no match yields
  only the create item.
- create item: present only with a query; absent with an empty query; degrades
  to the noop item when no default list is set or the id is unknown.
- due formatting: an all-day `…T00:00:00Z` value renders as its calendar date
  regardless of local timezone; a timed value renders in local time.
- action round trip: a summary containing `:` survives build → parse; the
  toggle bool is the inverse of current status.
- each error and empty state produces exactly one item with action `noop`.

**Manual** — against the live daemon, since `Process` and `pluginService` are
not exercised by the unit tests:

```bash
ln -s "$PWD" ~/.config/DankMaterialShell/plugins/dcalTasks
```

Then reload plugins and verify: the list appears under `;`; typing filters it;
the create item makes a task in the configured list and it shows up on the next
open; Enter on a task completes it and Enter again reopens it; with the daemon
stopped (`dcal kill`) the error item appears and the plugin recovers once the
daemon is back.

## Follow-ups (not v1)

- Socket transport with `subscribe topics=tasks` for push updates.
- Due dates on creation, parsed from the query (`buy milk tomorrow`).
- A per-list trigger suffix, or a list filter in the launcher.
- Delete via the launcher's context-menu action API.
