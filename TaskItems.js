.pragma library

// Pure helpers behind the dcalTasks launcher plugin. No QML imports, no
// singletons, no Qt globals — everything here is unit tested by
// tests/tst_TaskItems.qml, so it must stay runnable outside Quickshell.

function parseTasks(text) {
    var parsed = _parseJson(text)
    if (!parsed.ok)
        return {ok: false, tasks: [], error: parsed.error, kind: parsed.kind}

    var tasks = parsed.value && parsed.value.tasks
    return {ok: true, tasks: Array.isArray(tasks) ? tasks : [], error: "", kind: ""}
}

function parseCalendars(text) {
    var parsed = _parseJson(text)
    if (!parsed.ok)
        return {ok: false, calendars: {}, error: parsed.error, kind: parsed.kind}

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
    return {ok: true, calendars: byId, error: "", kind: ""}
}

// kind distinguishes two read failures that look identical downstream but
// need different messages: "empty" is no output at all (dcal missing, or the
// daemon down and writing only to stderr); "parse" is output that arrived but
// isn't valid JSON (e.g. a stray non-JSON line ahead of the real payload).
function _parseJson(text) {
    if (!text || text.trim().length === 0)
        return {ok: false, value: null, error: "dcal returned no output", kind: "empty"}
    try {
        return {ok: true, value: JSON.parse(text), error: "", kind: ""}
    } catch (e) {
        return {ok: false, value: null, error: String(e.message || e), kind: "parse"}
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

var CATEGORIES = ["Tasks"]

var SCORE_CREATE = 100000
var SCORE_OPEN = 90000
var SCORE_DONE = 80000

function buildItems(state, query) {
    var q = query || ""

    // Only claim a failure when there is no cache to fall back on. A refresh
    // that fails while a good list is already loaded keeps showing that list.
    if (!state.tasksLoaded && state.error && state.error.length > 0) {
        // "parse" means dcal answered but the output wasn't valid JSON — a
        // different failure from "not running", and the parse error itself
        // is the only diagnostic that explains it, so surface it verbatim.
        if (state.errorKind === "parse")
            return [_noopItem("Could not read tasks from dcal", state.error)]
        return [_noopItem("dcal is not running", "Start it with: dcal run -d")]
    }

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

// Builds the settings dropdown's option list. Only writable task lists are
// offerable. The label leads with the list name because DankDropdown elides
// right at a fixed width: leading with the account name makes every entry of a
// multi-list account render as an identical truncated stub. The account is
// appended only to disambiguate lists that share a name.
function taskListOptions(calendars) {
    var cals = calendars || {}
    var writable = []
    for (var id in cals) {
        var cal = cals[id]
        if (!cal || !cal.holdsTasks || cal.readOnly)
            continue
        writable.push(cal)
    }

    var nameCounts = {}
    for (var i = 0; i < writable.length; i++) {
        var n = writable[i].name || ""
        nameCounts[n] = (nameCounts[n] || 0) + 1
    }

    var options = []
    for (var j = 0; j < writable.length; j++) {
        var c = writable[j]
        var name = c.name || ""
        var ambiguous = nameCounts[name] > 1 && c.accountName
        options.push({
            label: ambiguous ? name + " — " + c.accountName : name,
            value: c.id
        })
    }

    options.sort(function (a, b) {
        var la = a.label.toLowerCase()
        var lb = b.label.toLowerCase()
        if (la < lb)
            return -1
        return la > lb ? 1 : 0
    })
    return options
}
