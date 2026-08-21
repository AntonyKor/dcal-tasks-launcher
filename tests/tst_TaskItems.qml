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
}
