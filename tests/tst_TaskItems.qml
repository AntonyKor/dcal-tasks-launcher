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

    function test_parseTasks_malformedJsonHasParseKind() {
        var r = TaskItems.parseTasks('dcal daemon not running')
        compare(r.kind, "parse")
    }

    function test_parseTasks_emptyStringFails() {
        var r = TaskItems.parseTasks('')
        verify(!r.ok)
        compare(r.tasks.length, 0)
    }

    function test_parseTasks_emptyStringHasEmptyKind() {
        var r = TaskItems.parseTasks('')
        compare(r.kind, "empty")
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
        compare(TaskItems.dueLabel(local.toISOString(), false), "Feb 21, 3:30 PM")
    }

    function test_dueLabel_timedShowsMorningAndNoonBoundaries() {
        compare(TaskItems.dueLabel(new Date(2026, 1, 21, 0, 5, 0).toISOString(), false),
                "Feb 21, 12:05 AM")
        compare(TaskItems.dueLabel(new Date(2026, 1, 21, 12, 0, 0).toISOString(), false),
                "Feb 21, 12:00 PM")
        compare(TaskItems.dueLabel(new Date(2026, 1, 21, 9, 0, 0).toISOString(), false),
                "Feb 21, 9:00 AM")
    }

    // An all-day due has no time to show, and midnight UTC is not one.
    function test_dueLabel_allDayStaysDateOnly() {
        compare(TaskItems.dueLabel("2026-02-21T00:00:00Z", true), "Feb 21")
    }

    function test_dueLabel_emptyWhenNoDueDate() {
        compare(TaskItems.dueLabel("", true), "")
        compare(TaskItems.dueLabel(undefined, false), "")
        compare(TaskItems.dueLabel(null, false), "")
    }

    function test_dueLabel_emptyWhenUnparseable() {
        compare(TaskItems.dueLabel("not-a-date", true), "")
    }

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

    // "Today" is a local calendar date, so the clock and every timed due below
    // are built from a local Date — noon on 21 August wherever the suite runs.
    // A UTC instant cannot stand in for them: 2026-08-21T12:00:00Z is already
    // 22 August at UTC+14, which silently moves "today" under the assertions.
    // All-day dues stay literal UTC midnights, because that is the wire format
    // whose comparison against the local date is the thing under test.
    readonly property double nowMs: localMs(2026, 7, 21, 12, 0)

    function localMs(y, m, d, h, min) {
        return new Date(y, m, d, h === undefined ? 0 : h, min === undefined ? 0 : min, 0).getTime()
    }

    function localIso(y, m, d, h, min) {
        return new Date(localMs(y, m, d, h, min)).toISOString()
    }

    function todayView() {
        return {mode: "today", defaultCalendarId: "", nowMs: nowMs}
    }

    function test_selectTasks_todayViewKeepsOverdue() {
        var tasks = [makeTask({id: "a", summary: "Alpha",
                               due: localIso(2026, 7, 19, 12, 0)})]
        var r = TaskItems.selectTasks(tasks, cals, "", false, todayView())
        compare(r.open.length, 1)
        compare(r.open[0].task.id, "a")
    }

    // Half an hour after nowMs and still the same local day, at any offset.
    function test_selectTasks_todayViewKeepsTimedDueLaterToday() {
        var tasks = [makeTask({id: "a", summary: "Alpha",
                               due: localIso(2026, 7, 21, 12, 30)})]
        var r = TaskItems.selectTasks(tasks, cals, "", false, todayView())
        compare(r.open.length, 1)
    }

    function test_selectTasks_todayViewDropsFutureTask() {
        var tasks = [makeTask({id: "a", summary: "Alpha",
                               due: localIso(2026, 7, 23, 12, 0)})]
        var r = TaskItems.selectTasks(tasks, cals, "", false, todayView())
        compare(r.open.length, 0)
    }

    function test_selectTasks_todayViewDropsUndatedTask() {
        var tasks = [makeTask({id: "a", summary: "Alpha"})]
        var r = TaskItems.selectTasks(tasks, cals, "", false, todayView())
        compare(r.open.length, 0)
    }

    function test_selectTasks_todayViewKeepsAllDayDueToday() {
        var tasks = [makeTask({id: "a", summary: "Alpha", allDay: true,
                               due: "2026-08-21T00:00:00Z"})]
        var r = TaskItems.selectTasks(tasks, cals, "", false, todayView())
        compare(r.open.length, 1)
    }

    // Reading this all-day due with local getters instead of UTC getters puts
    // it on Aug 21 west of UTC, which would wrongly show it as due today. Only
    // catches the bug under TZ=America/Los_Angeles — see dueLabel's tests.
    function test_selectTasks_todayViewAllDayIsTimezoneIndependent() {
        var tasks = [makeTask({id: "a", summary: "Alpha", allDay: true,
                               due: "2026-08-22T00:00:00Z"})]
        var r = TaskItems.selectTasks(tasks, cals, "", false, todayView())
        compare(r.open.length, 0)
    }

    function test_selectTasks_todayViewAlsoFiltersCompleted() {
        var tasks = [
            makeTask({id: "a", summary: "Alpha", status: "completed",
                      completed: "2026-08-21T10:00:00Z",
                      due: localIso(2026, 7, 19, 12, 0)}),
            makeTask({id: "b", summary: "Bravo", status: "completed",
                      completed: "2026-08-21T10:00:00Z",
                      due: localIso(2026, 7, 23, 12, 0)})
        ]
        var r = TaskItems.selectTasks(tasks, cals, "", true, todayView())
        compare(r.done.length, 1)
        compare(r.done[0].task.id, "a")
    }

    function test_selectTasks_todayViewIgnoresUnparseableDue() {
        var tasks = [makeTask({id: "a", summary: "Alpha", due: "not a date"})]
        var r = TaskItems.selectTasks(tasks, cals, "", false, todayView())
        compare(r.open.length, 0)
    }

    function test_selectTasks_defaultListViewKeepsOnlyThatList() {
        var tasks = [
            makeTask({id: "a", summary: "Alpha", calendarId: "cal-chores"}),
            makeTask({id: "b", summary: "Bravo", calendarId: "cal-fitness"})
        ]
        var r = TaskItems.selectTasks(tasks, cals, "", false,
                                      {mode: "defaultList",
                                       defaultCalendarId: "cal-chores",
                                       nowMs: nowMs})
        compare(r.open.length, 1)
        compare(r.open[0].task.id, "a")
    }

    function test_selectTasks_allViewKeepsEverything() {
        var tasks = [
            makeTask({id: "a", summary: "Alpha", calendarId: "cal-chores"}),
            makeTask({id: "b", summary: "Bravo", calendarId: "cal-fitness",
                      due: "2026-08-23T12:00:00Z"})
        ]
        var r = TaskItems.selectTasks(tasks, cals, "", false,
                                      {mode: "all", defaultCalendarId: "cal-chores",
                                       nowMs: nowMs})
        compare(r.open.length, 2)
    }

    function test_selectTasks_omittedViewKeepsEverything() {
        var tasks = [
            makeTask({id: "a", summary: "Alpha"}),
            makeTask({id: "b", summary: "Bravo", calendarId: "cal-fitness"})
        ]
        var r = TaskItems.selectTasks(tasks, cals, "", false)
        compare(r.open.length, 2)
    }

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
        compare(TaskItems.parseAction(items[0].action).summary, "buy milk")
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
        compare(TaskItems.parseAction(items[0].action).summary, "match")
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
        compare(TaskItems.parseAction(items[0].action).summary, "zzz")
    }

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

    function test_buildItems_parseErrorShowsCouldNotReadTasksMessage() {
        var items = TaskItems.buildItems(readyState({
            tasksLoaded: false, calendarsLoaded: false,
            error: "Unexpected token d in JSON at position 0", errorKind: "parse"
        }), "")
        compare(items.length, 1)
        compare(items[0].name, "Could not read tasks from dcal")
        compare(items[0].comment, "Unexpected token d in JSON at position 0")
        compare(items[0].action, "noop")
        compare(items[0].categories[0], "Tasks")
        verify(items[0]._preScored > 900)
    }

    function test_buildItems_parseErrorDistinctFromDaemonDown() {
        var items = TaskItems.buildItems(readyState({
            tasksLoaded: false, calendarsLoaded: false,
            error: "boom", errorKind: "parse"
        }), "")
        verify(items[0].name !== "dcal is not running")
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
        compare(TaskItems.parseAction(items[0].action).summary, "buy milk")
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
        compare(TaskItems.parseAction(items[0].action).summary, "zzz")
    }

    readonly property var viewTasks: [
        makeTask({id: "today", summary: "Due today", calendarId: "cal-chores",
                  due: "2026-08-21T09:00:00Z"}),
        makeTask({id: "later", summary: "Due later", calendarId: "cal-fitness",
                  due: "2026-08-30T09:00:00Z"})
    ]

    function test_buildItems_defaultsToAllTasksWhenViewUnset() {
        var items = TaskItems.buildItems(
            readyState({tasks: viewTasks, nowMs: nowMs}), "")
        compare(items.length, 2)
    }

    function test_buildItems_todayViewFiltersTheNoQueryList() {
        var items = TaskItems.buildItems(
            readyState({tasks: viewTasks, defaultView: "today", nowMs: nowMs}), "")
        compare(items.length, 1)
        compare(items[0].name, "Due today")
    }

    function test_buildItems_defaultListViewFiltersTheNoQueryList() {
        var items = TaskItems.buildItems(
            readyState({tasks: viewTasks, defaultView: "defaultList",
                        defaultCalendarId: "cal-fitness", nowMs: nowMs}), "")
        compare(items.length, 1)
        compare(items[0].name, "Due later")
    }

    function test_buildItems_queryBypassesTodayView() {
        var items = TaskItems.buildItems(
            readyState({tasks: viewTasks, defaultView: "today", nowMs: nowMs}),
            "due")
        compare(items.length, 3)
        compare(items[1].name, "Due today")
        compare(items[2].name, "Due later")
    }

    function test_buildItems_queryBypassesDefaultListView() {
        var items = TaskItems.buildItems(
            readyState({tasks: viewTasks, defaultView: "defaultList",
                        defaultCalendarId: "cal-fitness", nowMs: nowMs}),
            "due")
        compare(items.length, 3)
    }

    function test_buildItems_todayViewEmptyStateExplainsTheFilter() {
        var items = TaskItems.buildItems(
            readyState({tasks: [viewTasks[1]], defaultView: "today", nowMs: nowMs}),
            "")
        compare(items.length, 1)
        compare(items[0].name, "Nothing due today")
        compare(items[0].comment, "Type to search all tasks")
        compare(items[0].action, "noop")
    }

    function test_buildItems_defaultListViewEmptyStateNamesTheList() {
        var items = TaskItems.buildItems(
            readyState({tasks: [viewTasks[1]], defaultView: "defaultList",
                        defaultCalendarId: "cal-chores", nowMs: nowMs}), "")
        compare(items.length, 1)
        compare(items[0].name, "Nothing in Chores")
        compare(items[0].comment, "Type to search all tasks")
    }

    // An unset or deleted default list is a misconfiguration, not a filter.
    // Honouring it would leave the launcher permanently empty with no hint.
    function test_buildItems_defaultListViewFallsBackToAllWhenUnset() {
        var items = TaskItems.buildItems(
            readyState({tasks: viewTasks, defaultView: "defaultList",
                        defaultCalendarId: "", nowMs: nowMs}), "")
        compare(items.length, 2)
    }

    function test_buildItems_defaultListViewFallsBackToAllWhenListDeleted() {
        var items = TaskItems.buildItems(
            readyState({tasks: viewTasks, defaultView: "defaultList",
                        defaultCalendarId: "cal-deleted", nowMs: nowMs}), "")
        compare(items.length, 2)
    }

    // Calendars arrive on a separate IPC call; an id we cannot resolve yet is
    // "not loaded", so keep filtering by it rather than dropping the view.
    function test_buildItems_defaultListViewFiltersBeforeCalendarsLoad() {
        var items = TaskItems.buildItems(
            readyState({tasks: viewTasks, calendarsLoaded: false, calendars: {},
                        defaultView: "defaultList",
                        defaultCalendarId: "cal-chores", nowMs: nowMs}), "")
        compare(items.length, 1)
        compare(items[0].name, "Due today")
    }

    function test_buildItems_todayViewFallsBackToAllWithoutAClock() {
        var items = TaskItems.buildItems(
            readyState({tasks: viewTasks, defaultView: "today"}), "")
        compare(items.length, 2)
    }

    function test_buildItems_unknownViewFallsBackToAll() {
        var items = TaskItems.buildItems(
            readyState({tasks: viewTasks, defaultView: "nonsense", nowMs: nowMs}), "")
        compare(items.length, 2)
    }

    readonly property var writableCals: ({
        "c1": {id: "c1", name: "Chores", accountName: "Radicale (mac mini)",
               holdsTasks: true, readOnly: false},
        "c2": {id: "c2", name: "Fitness", accountName: "Radicale (mac mini)",
               holdsTasks: true, readOnly: false},
        "c3": {id: "c3", name: "Family", accountName: "iCloud",
               holdsTasks: false, readOnly: false},
        "c4": {id: "c4", name: "Holidays", accountName: "Google",
               holdsTasks: true, readOnly: true}
    })

    function test_taskListOptions_onlyWritableTaskLists() {
        var o = TaskItems.taskListOptions(writableCals)
        compare(o.length, 2)
        compare(o[0].value, "c1")
        compare(o[1].value, "c2")
    }

    // DankDropdown elides right at a fixed width, so a shared account prefix
    // would truncate every entry to the same stub. The list name leads.
    function test_taskListOptions_labelIsBareNameWhenUnambiguous() {
        var o = TaskItems.taskListOptions(writableCals)
        compare(o[0].label, "Chores")
        compare(o[1].label, "Fitness")
    }

    function test_taskListOptions_appendsAccountOnlyForDuplicateNames() {
        var o = TaskItems.taskListOptions({
            "a": {id: "a", name: "Inbox", accountName: "Radicale",
                  holdsTasks: true, readOnly: false},
            "b": {id: "b", name: "Inbox", accountName: "iCloud",
                  holdsTasks: true, readOnly: false},
            "c": {id: "c", name: "Chores", accountName: "Radicale",
                  holdsTasks: true, readOnly: false}
        })
        compare(o.length, 3)
        compare(o[0].label, "Chores")
        compare(o[1].label, "Inbox — iCloud")
        compare(o[2].label, "Inbox — Radicale")
    }

    function test_taskListOptions_sortsByLabel() {
        var o = TaskItems.taskListOptions({
            "z": {id: "z", name: "zebra", accountName: "A",
                  holdsTasks: true, readOnly: false},
            "a": {id: "a", name: "Apple", accountName: "A",
                  holdsTasks: true, readOnly: false},
            "m": {id: "m", name: "mango", accountName: "A",
                  holdsTasks: true, readOnly: false}
        })
        compare(o[0].label, "Apple")
        compare(o[1].label, "mango")
        compare(o[2].label, "zebra")
    }

    function test_taskListOptions_emptyWhenNothingWritable() {
        compare(TaskItems.taskListOptions({}).length, 0)
        compare(TaskItems.taskListOptions(null).length, 0)
    }

    function test_taskListOptions_missingAccountNameFallsBackToBareName() {
        var o = TaskItems.taskListOptions({
            "a": {id: "a", name: "Inbox", accountName: "", holdsTasks: true, readOnly: false},
            "b": {id: "b", name: "Inbox", accountName: "", holdsTasks: true, readOnly: false}
        })
        compare(o[0].label, "Inbox")
        compare(o[1].label, "Inbox")
    }

    function test_parseCalendars_retainsHiddenAndSyncDisabled() {
        var r = TaskItems.parseCalendars('[{"id":"h","name":"Hidden","accountName":"A",' +
            '"holdsTasks":true,"readOnly":false,"hidden":true,"syncDisabled":true}]')
        verify(r.ok)
        compare(r.calendars["h"].hidden, true)
        compare(r.calendars["h"].syncDisabled, true)
    }

    function test_parseCalendars_defaultsFlagsToFalseWhenAbsent() {
        var r = TaskItems.parseCalendars('[{"id":"n","name":"Normal","holdsTasks":true}]')
        compare(r.calendars["n"].hidden, false)
        compare(r.calendars["n"].syncDisabled, false)
    }

    readonly property var mixedCals: ({
        "ok": {id: "ok", name: "Chores", accountName: "R", holdsTasks: true,
               readOnly: false, hidden: false, syncDisabled: false},
        "hid": {id: "hid", name: "My Tasks", accountName: "R", holdsTasks: true,
                readOnly: false, hidden: true, syncDisabled: true},
        "nosync": {id: "nosync", name: "Archived", accountName: "R", holdsTasks: true,
                   readOnly: false, hidden: false, syncDisabled: true}
    })

    function test_taskListOptions_excludesHiddenAndSyncDisabled() {
        var o = TaskItems.taskListOptions(mixedCals)
        compare(o.length, 1)
        compare(o[0].label, "Chores")
    }

    function test_selectTasks_dropsTasksFromHiddenCalendars() {
        var tasks = [
            makeTask({id: "a", summary: "Visible", calendarId: "ok"}),
            makeTask({id: "b", summary: "Hidden one", calendarId: "hid"}),
            makeTask({id: "c", summary: "Unsynced", calendarId: "nosync"})
        ]
        var r = TaskItems.selectTasks(tasks, mixedCals, "", false)
        compare(r.open.length, 1)
        compare(r.open[0].task.id, "a")
    }

    // calendars.list is a second IPC call; until it lands every calendar is
    // unknown, and dropping those tasks would blank the launcher on open.
    function test_selectTasks_keepsTasksWhoseCalendarIsNotLoadedYet() {
        var tasks = [makeTask({id: "a", summary: "Visible", calendarId: "ok"})]
        var r = TaskItems.selectTasks(tasks, {}, "", false)
        compare(r.open.length, 1)
    }

    readonly property string cobraFailure: 'Error: ipc error: ErrNotFound: calendar not found\n' +
        'Usage:\n  dcal ipc <method> [key=value...]\n\nFlags:\n  -h, --help   help for ipc\n'

    function test_dcalErrorDetail_extractsReasonAndDropsUsageDump() {
        compare(TaskItems.dcalErrorDetail(cobraFailure), "calendar not found")
    }

    function test_dcalErrorDetail_stripsIpcErrorPrefixWithoutSentinel() {
        compare(TaskItems.dcalErrorDetail("Error: ipc error: daemon not running"),
                "daemon not running")
    }

    function test_dcalErrorDetail_keepsPlainErrorLine() {
        compare(TaskItems.dcalErrorDetail("Error: something broke"), "something broke")
    }

    function test_dcalErrorDetail_fallsBackToFirstNonEmptyLine() {
        compare(TaskItems.dcalErrorDetail("\n  permission denied\nmore noise\n"),
                "permission denied")
    }

    function test_dcalErrorDetail_handlesEmptyStderr() {
        compare(TaskItems.dcalErrorDetail(""), "dcal gave no error output.")
        compare(TaskItems.dcalErrorDetail("   \n  "), "dcal gave no error output.")
        compare(TaskItems.dcalErrorDetail(undefined), "dcal gave no error output.")
    }

    // A bare sentinel with nothing after it must not strip down to "".
    function test_dcalErrorDetail_keepsBareSentinel() {
        compare(TaskItems.dcalErrorDetail("Error: ErrNotFound:"), "ErrNotFound:")
    }

    function test_mutationFailure_createHeadline() {
        var f = TaskItems.mutationFailure("create", cobraFailure)
        compare(f.message, "Could not create the task")
        compare(f.details, "calendar not found")
    }

    function test_mutationFailure_toggleHeadline() {
        var f = TaskItems.mutationFailure("toggle", "Error: ipc error: task has no calendar")
        compare(f.message, "Could not update the task")
        compare(f.details, "task has no calendar")
    }

    // Fri 21 Aug 2026, 10:00 local.
    readonly property double friMorning: new Date(2026, 7, 21, 10, 0, 0).getTime()

    function test_createAction_carriesDueAndAllDay() {
        var p = TaskItems.parseAction(
            TaskItems.createAction("gym", "2026-08-30T00:00:00Z", true))
        compare(p.type, "create")
        compare(p.summary, "gym")
        compare(p.due, "2026-08-30T00:00:00Z")
        compare(p.allDay, true)
    }

    function test_createAction_withoutADueIsUndated() {
        var p = TaskItems.parseAction(TaskItems.createAction("gym"))
        compare(p.type, "create")
        compare(p.summary, "gym")
        compare(p.due, "")
        compare(p.allDay, false)
    }

    function test_createAction_stillPreservesColonsAlongsideADue() {
        var p = TaskItems.parseAction(
            TaskItems.createAction("standup: prep notes: 10am", "2026-08-30T00:00:00Z", true))
        compare(p.summary, "standup: prep notes: 10am")
        compare(p.due, "2026-08-30T00:00:00Z")
    }

    function test_buildItems_datedQueryOffersDatedRowFirst() {
        var items = TaskItems.buildItems(readyState({nowMs: friMorning}),
                                         "publish tasks plugin tomorrow at 6PM")
        compare(items[0].name, "Create task: publish tasks plugin")
        compare(items[0].comment, "in Chores · due Aug 22, 6:00 PM")
        compare(items[0]._preScored, 100000)

        var p = TaskItems.parseAction(items[0].action)
        compare(p.summary, "publish tasks plugin")
        compare(p.allDay, false)
        var due = new Date(p.due)
        compare(due.getDate(), 22)
        compare(due.getHours(), 18)
    }

    // The escape hatch: the literal text is always one row down.
    function test_buildItems_datedQueryAlsoOffersTheLiteralText() {
        var items = TaskItems.buildItems(readyState({nowMs: friMorning}),
                                         "publish tasks plugin tomorrow at 6PM")
        compare(items[1].name, "Create task: publish tasks plugin tomorrow at 6PM")
        compare(items[1].comment, "in Chores · no due date")
        compare(items[1]._preScored, 99999)

        var p = TaskItems.parseAction(items[1].action)
        compare(p.summary, "publish tasks plugin tomorrow at 6PM")
        compare(p.due, "")
    }

    function test_buildItems_allDayQueryShowsDateWithoutATime() {
        var items = TaskItems.buildItems(readyState({nowMs: friMorning}),
                                         "renew passport aug 30")
        compare(items[0].name, "Create task: renew passport")
        compare(items[0].comment, "in Chores · due Aug 30")
    }

    function test_buildItems_undatedQueryOffersOneCreateRow() {
        var items = TaskItems.buildItems(readyState({nowMs: friMorning}), "buy milk")
        compare(items[0].name, "Create task: buy milk")
        compare(items[0].comment, "in Chores")
        compare(items.length, 1)
    }

    // A query that is nothing but a date has no title to create, so the
    // dated row would be blank. Only the literal row is worth offering.
    function test_buildItems_dateOnlyQueryOffersOnlyTheLiteralRow() {
        var items = TaskItems.buildItems(readyState({nowMs: friMorning}), "tomorrow")
        compare(items[0].name, "Create task: tomorrow")
        compare(items[0].comment, "in Chores")
        compare(items[0]._preScored, 100000)
    }

    // Without a default list neither row can create anything, so the prompt
    // to configure one stays a single row.
    function test_buildItems_datedQueryWithoutADefaultListStaysASinglePrompt() {
        var items = TaskItems.buildItems(
            readyState({nowMs: friMorning, defaultCalendarId: ""}), "gym tomorrow")
        compare(items[0].name, "Set a default task list in plugin settings")
        compare(items[0].action, "noop")
        compare(items.length, 1)
    }

    function test_buildItems_timedTaskRowShowsTheTime() {
        var local = new Date(2026, 1, 21, 18, 0, 0)
        var items = TaskItems.buildItems(readyState({
            tasks: [makeTask({id: "a", summary: "Alpha", allDay: false,
                              due: local.toISOString()})]
        }), "")
        compare(items[0].comment, "Chores · due Feb 21, 6:00 PM")
    }

    // DMS exposes SettingsData.use24HourClock ("auto" resolves it from the
    // locale); the launcher passes it in so this stays pure and testable.
    function test_dueLabel_twentyFourHourPadsTheHour() {
        compare(TaskItems.dueLabel(new Date(2026, 1, 21, 18, 0, 0).toISOString(), false, true),
                "Feb 21, 18:00")
        compare(TaskItems.dueLabel(new Date(2026, 1, 21, 9, 30, 0).toISOString(), false, true),
                "Feb 21, 09:30")
        compare(TaskItems.dueLabel(new Date(2026, 1, 21, 0, 5, 0).toISOString(), false, true),
                "Feb 21, 00:05")
    }

    function test_dueLabel_twelveHourIsUnchanged() {
        compare(TaskItems.dueLabel(new Date(2026, 1, 21, 18, 0, 0).toISOString(), false, false),
                "Feb 21, 6:00 PM")
    }

    // An all-day due has no time either way, so the flag cannot change it.
    function test_dueLabel_allDayIgnoresTheClockFormat() {
        compare(TaskItems.dueLabel("2026-02-21T00:00:00Z", true, true), "Feb 21")
        compare(TaskItems.dueLabel("2026-02-21T00:00:00Z", true, false), "Feb 21")
    }

    function test_buildItems_createPreviewUsesTwentyFourHourClock() {
        var items = TaskItems.buildItems(
            readyState({nowMs: friMorning, use24Hour: true}),
            "publish tasks plugin tomorrow at 18:00")
        compare(items[0].name, "Create task: publish tasks plugin")
        compare(items[0].comment, "in Chores · due Aug 22, 18:00")
    }

    function test_buildItems_taskRowUsesTwentyFourHourClock() {
        var local = new Date(2026, 1, 21, 18, 0, 0)
        var items = TaskItems.buildItems(readyState({
            use24Hour: true,
            tasks: [makeTask({id: "a", summary: "Alpha", allDay: false,
                              due: local.toISOString()})]
        }), "")
        compare(items[0].comment, "Chores · due Feb 21, 18:00")
    }

    function test_selectTasks_passesTheClockFormatThrough() {
        var local = new Date(2026, 1, 21, 18, 0, 0)
        var tasks = [makeTask({id: "a", summary: "Alpha", due: local.toISOString()})]
        compare(TaskItems.selectTasks(tasks, cals, "", false, null, true).open[0].due,
                "Feb 21, 18:00")
        compare(TaskItems.selectTasks(tasks, cals, "", false, null, false).open[0].due,
                "Feb 21, 6:00 PM")
    }

    // The locale's date order reaches the parser through the state object,
    // the same way the clock format reaches dueLabel.
    function test_buildItems_createPreviewHonoursMonthFirstOrder() {
        var items = TaskItems.buildItems(
            readyState({nowMs: friMorning, dayFirst: false}), "renew passport 2/9")
        compare(items[0].name, "Create task: renew passport")
        compare(items[0].comment, "in Chores · due Feb 9")
    }

    function test_buildItems_createPreviewHonoursDayFirstOrder() {
        var items = TaskItems.buildItems(
            readyState({nowMs: friMorning, dayFirst: true}), "renew passport 2/9")
        compare(items[0].comment, "in Chores · due Sep 2")
    }
}
