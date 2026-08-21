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
