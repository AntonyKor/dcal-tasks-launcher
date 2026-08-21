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
}
