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
