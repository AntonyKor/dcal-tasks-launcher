.pragma library
.import "DateParser.js" as DateParser

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
            readOnly: c.readOnly === true,
            hidden: c.hidden === true,
            syncDisabled: c.syncDisabled === true
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
// use24Hour comes from DMS's SettingsData.use24HourClock, passed in rather
// than read here so this file keeps its no-Qt, no-singleton guarantee.
function dueLabel(due, allDay, use24Hour) {
    if (!due)
        return ""
    var d = new Date(due)
    if (isNaN(d.getTime()))
        return ""

    // An all-day due has no time of day — its UTC midnight is a storage
    // convention, not an hour the user picked — so it stays date-only.
    if (allDay)
        return MONTHS[d.getUTCMonth()] + " " + d.getUTCDate()

    return MONTHS[d.getMonth()] + " " + d.getDate() + ", " + _timeLabel(d, use24Hour)
}

// Mirrors what DMS itself renders: "HH:mm" or "h:mm AP".
function _timeLabel(d, use24Hour) {
    var hour = d.getHours()
    var minute = d.getMinutes()
    var mm = (minute < 10 ? "0" : "") + minute

    if (use24Hour)
        return (hour < 10 ? "0" : "") + hour + ":" + mm

    var hour12 = hour % 12
    if (hour12 === 0)
        hour12 = 12
    return hour12 + ":" + mm + (hour < 12 ? " AM" : " PM")
}

// A calendar hidden in dcal, or excluded from sync (which purges its local
// copy), is one the user has switched off. Its tasks do not belong in the
// launcher and it is not a valid creation target.
function isUsableTaskList(cal) {
    return !!cal && cal.holdsTasks === true && !cal.readOnly
        && !cal.hidden && !cal.syncDisabled
}

// view is the resolved default view from resolveView(), or undefined for the
// unfiltered "all" behaviour. It narrows the no-query list only: buildItems
// passes it through untouched for an empty query and drops it once the user
// types, so a filter can never hide something being searched for.
var VIEW_ALL = "all"
var VIEW_TODAY = "today"
var VIEW_DEFAULT_LIST = "defaultList"

// Resolves the configured defaultView against the state it needs to work.
// A view that cannot be honoured degrades to "all" rather than to an empty
// launcher: "today" without a clock, "defaultList" with no default set, and
// "defaultList" pointing at a list dcal no longer has are all
// misconfigurations, not filters the user asked for.
function resolveView(state) {
    var mode = state.defaultView || VIEW_ALL
    var defaultCalendarId = state.defaultCalendarId || ""
    var nowMs = state.nowMs

    if (mode === VIEW_TODAY && typeof nowMs === "number" && isFinite(nowMs))
        return {mode: VIEW_TODAY, defaultCalendarId: defaultCalendarId, nowMs: nowMs}

    // An id we cannot resolve while calendars are still loading means "not
    // fetched yet", so keep filtering by it — same optimism as _createItem.
    var cals = state.calendars || {}
    if (mode === VIEW_DEFAULT_LIST && defaultCalendarId.length > 0
        && !(state.calendarsLoaded && !cals[defaultCalendarId]))
        return {mode: VIEW_DEFAULT_LIST, defaultCalendarId: defaultCalendarId, nowMs: nowMs}

    return {mode: VIEW_ALL, defaultCalendarId: defaultCalendarId, nowMs: nowMs}
}

function _matchesView(task, view) {
    if (!view || view.mode === VIEW_ALL)
        return true
    if (view.mode === VIEW_DEFAULT_LIST)
        return task.calendarId === view.defaultCalendarId
    if (view.mode === VIEW_TODAY)
        return _isDueByEndOfToday(task.due, task.allDay === true, view.nowMs)
    return true
}

// Due today or already overdue. Undated and unparseable dues are out: with no
// date there is nothing placing the task in today.
//
// dcal writes all-day dues as UTC midnight, so their calendar date must be
// read with the UTC getters (see dueLabel) and compared against today's local
// calendar date. A timed due is a real instant, so it is compared against
// local midnight tonight.
function _isDueByEndOfToday(due, allDay, nowMs) {
    if (!due)
        return false
    var d = new Date(due)
    if (isNaN(d.getTime()))
        return false

    var now = new Date(nowMs)
    if (allDay) {
        var dueDay = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate())
        var today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate())
        return dueDay <= today
    }

    // Day + 1 rolls the month and year over on its own.
    var endOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
    return d.getTime() < endOfToday.getTime()
}

function selectTasks(tasks, calendars, query, showCompleted, view, use24Hour) {
    var open = []
    var done = []
    var needle = (query || "").toLowerCase()
    var cals = calendars || {}
    var list = Array.isArray(tasks) ? tasks : []

    for (var i = 0; i < list.length; i++) {
        var task = list[i]
        if (!task || task.status === "cancelled")
            continue

        if (!_matchesView(task, view))
            continue

        var cal = cals[task.calendarId]
        // An unknown calendar means calendars.list has not landed yet, so the
        // task is kept; only a calendar we can positively see is off is dropped.
        if (cal && (cal.hidden || cal.syncDisabled))
            continue
        var listName = cal ? cal.name : ""
        var summary = task.summary || ""

        if (needle.length > 0
            && summary.toLowerCase().indexOf(needle) === -1
            && listName.toLowerCase().indexOf(needle) === -1)
            continue

        var entry = {
            task: task,
            listName: listName,
            due: dueLabel(task.due, task.allDay === true, use24Hour)
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

// JSON rather than a delimited string: the payload now carries a due date
// alongside a summary that may itself contain any character.
function createAction(summary, due, allDay) {
    return "create:" + JSON.stringify({
        summary: summary || "",
        due: due || "",
        allDay: allDay === true
    })
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

    if (kind === "create") {
        var fields = null
        try {
            fields = JSON.parse(payload)
        } catch (e) {
            return {type: "noop"}
        }
        if (!fields || !fields.summary)
            return {type: "noop"}
        return {
            type: "create",
            summary: fields.summary,
            due: fields.due || "",
            allDay: fields.allDay === true
        }
    }

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
    // The default view narrows the list you get for free; typing means you are
    // looking for something, so a query searches everything.
    var view = q.length > 0 ? null : resolveView(state)
    if (q.length > 0) {
        var createRows = _createItems(state, q)
        for (var c = 0; c < createRows.length; c++)
            items.push(createRows[c])
    }

    var picked = selectTasks(state.tasks, state.calendars, q, state.showCompleted, view,
                             state.use24Hour)

    for (var i = 0; i < picked.open.length; i++)
        items.push(_taskItem(picked.open[i], false, SCORE_OPEN - i))

    for (var j = 0; j < picked.done.length; j++)
        items.push(_taskItem(picked.done[j], true, SCORE_DONE - j))

    if (items.length === 0)
        items.push(_emptyItem(state, view))

    return items
}

// A list emptied by the default view has to say so, or it reads as "you have
// no tasks" when the tasks are merely filtered out.
function _emptyItem(state, view) {
    var mode = view ? view.mode : VIEW_ALL
    if (mode === VIEW_TODAY)
        return _noopItem("Nothing due today", "Type to search all tasks")

    if (mode === VIEW_DEFAULT_LIST) {
        var cals = state.calendars || {}
        var cal = cals[view.defaultCalendarId]
        return _noopItem(cal && cal.name ? "Nothing in " + cal.name : "Nothing in this list",
                         "Type to search all tasks")
    }

    return _noopItem("No tasks", "Type to create one")
}

// One create row, or two when the query ends in something that reads as a
// date: the dated one first, the literal text right under it. The second row
// is the only escape hatch for a task genuinely titled "... tomorrow", and it
// keeps a wrong guess one arrow key away from being harmless.
function _createItems(state, query) {
    var cals = state.calendars || {}
    var cal = cals[state.defaultCalendarId]

    // While calendars are still loading an unknown id means "not fetched yet",
    // not "misconfigured", so stay optimistic and keep the item actionable.
    if (!cal && state.calendarsLoaded) {
        return [_createRow("Set a default task list in plugin settings",
                           "Plugin settings → Dcal Tasks → Default task list",
                           "noop", SCORE_CREATE)]
    }

    var where = cal ? "in " + cal.name : "in the default task list"
    var dated = DateParser.parseTrailingDate(query, state.nowMs)

    // A query that is nothing but a date leaves no title behind, so there is
    // no dated row to offer — only the literal text.
    if (!dated || dated.summary.length === 0)
        return [_createRow("Create task: " + query, where, createAction(query), SCORE_CREATE)]

    return [
        _createRow("Create task: " + dated.summary,
                   where + " · due " + dueLabel(dated.due, dated.allDay, state.use24Hour),
                   createAction(dated.summary, dated.due, dated.allDay),
                   SCORE_CREATE),
        _createRow("Create task: " + query, where + " · no due date",
                   createAction(query), SCORE_CREATE - 1)
    ]
}

function _createRow(name, comment, action, score) {
    return {
        name: name,
        icon: "material:add_task",
        comment: comment,
        action: action,
        categories: CATEGORIES,
        _preScored: score
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
        if (!isUsableTaskList(cal))
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

// dcal is a cobra CLI: a failed call prints "Error: ipc error: <reason>" and
// then dumps its whole usage text, which is useless in a toast. Pull out the
// reason and drop the rest.
function dcalErrorDetail(stderrText) {
    var text = (stderrText || "").trim()
    if (text.length === 0)
        return "dcal gave no error output."

    var lines = text.split("\n")
    var picked = ""
    var firstNonEmpty = ""
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (line.length === 0)
            continue
        if (firstNonEmpty.length === 0)
            firstNonEmpty = line
        if (line.indexOf("Error:") === 0) {
            picked = line.substring("Error:".length).trim()
            break
        }
    }
    if (picked.length === 0)
        picked = firstNonEmpty

    if (picked.indexOf("ipc error:") === 0)
        picked = picked.substring("ipc error:".length).trim()

    // Strip the Go sentinel prefix ("ErrNotFound: calendar not found").
    var sentinel = picked.match(/^Err[A-Za-z]+:\s*/)
    if (sentinel && picked.length > sentinel[0].length)
        picked = picked.substring(sentinel[0].length)

    return picked.length > 0 ? picked : text
}

// Toast content for a failed tasks.create / tasks.complete. The launcher has
// already closed by the time these land, so a toast is the only surface left.
function mutationFailure(actionType, stderrText) {
    return {
        message: actionType === "create"
            ? "Could not create the task"
            : "Could not update the task",
        details: dcalErrorDetail(stderrText)
    }
}
