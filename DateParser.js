.pragma library

// Natural-language due dates for the launcher's create row. Pure and
// clock-injected (nowMs) so every case is deterministic under test — no Qt,
// no singletons, no Date.now().
//
// Only a *trailing* phrase is ever read as a date, so "buy milk for saturday
// party" keeps its saturday. The launcher offers the undated summary as a
// second create row, which is the escape hatch when this guesses wrong.

function _pad(n) {
    return n < 10 ? "0" + n : "" + n
}

// dcal stores an all-day due as UTC midnight (see TaskItems.dueLabel), so the
// calendar date is what travels, not an instant.
function _allDayIso(y, m, d) {
    return y + "-" + _pad(m + 1) + "-" + _pad(d) + "T00:00:00Z"
}

// A timed due is a real instant, so it carries the local UTC offset rather
// than pretending to be UTC.
function _timedIso(date) {
    var offset = -date.getTimezoneOffset()
    var sign = offset < 0 ? "-" : "+"
    var abs = Math.abs(offset)
    return date.getFullYear() + "-" + _pad(date.getMonth() + 1) + "-" + _pad(date.getDate())
        + "T" + _pad(date.getHours()) + ":" + _pad(date.getMinutes()) + ":00"
        + sign + _pad(Math.floor(abs / 60)) + ":" + _pad(abs % 60)
}

// Rules are tried in order and each is anchored at end-of-string, so the first
// hit is the trailing phrase. Every pattern opens with (?:^|\s) so a rule can
// only fire on a word boundary — "12pm" never matches inside "task12pm".
var _TIME_RULES = [
    // "at 6PM", "6:30pm", "6 pm"
    {
        re: /(?:^|\s)(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)$/i,
        read: function (m) {
            var hour = parseInt(m[1], 10)
            if (hour < 1 || hour > 12)
                return null
            if (m[3].toLowerCase() === "pm" && hour !== 12)
                hour += 12
            if (m[3].toLowerCase() === "am" && hour === 12)
                hour = 0
            return {hour: hour, minute: m[2] ? parseInt(m[2], 10) : 0}
        }
    },
    // "at 18:00", "18:00"
    {
        re: /(?:^|\s)(?:at\s+)?(\d{1,2}):(\d{2})$/,
        read: function (m) {
            var hour = parseInt(m[1], 10)
            var minute = parseInt(m[2], 10)
            if (hour > 23 || minute > 59)
                return null
            return {hour: hour, minute: minute}
        }
    },
    // "at 17", "at 5" — a 24-hour clock, so 5 is 05:00 and not the evening.
    // Tried last so the am/pm and HH:MM forms above keep their reading, and
    // "at" is mandatory: without it every "buy 5" would sprout a due date.
    {
        re: /(?:^|\s)at\s+(\d{1,2})$/i,
        read: function (m) {
            var hour = parseInt(m[1], 10)
            if (hour > 23)
                return null
            return {hour: hour, minute: 0}
        }
    }
]

var _WEEKDAYS = {
    sunday: 0, sun: 0, monday: 1, mon: 1, tuesday: 2, tues: 2, tue: 2,
    wednesday: 3, weds: 3, wed: 3, thursday: 4, thurs: 4, thur: 4, thu: 4,
    friday: 5, fri: 5, saturday: 6, sat: 6
}

var _WEEKDAY_PATTERN = "sunday|sun|monday|mon|tuesday|tues|tue|wednesday|weds|wed"
    + "|thursday|thurs|thur|thu|friday|fri|saturday|sat"

var _MONTHS = {
    january: 0, jan: 0, february: 1, feb: 1, march: 2, mar: 2, april: 3, apr: 3,
    may: 4, june: 5, jun: 5, july: 6, jul: 6, august: 7, aug: 7,
    september: 8, sept: 8, sep: 8, october: 9, oct: 9, november: 10, nov: 10,
    december: 11, dec: 11
}

// Longest name first: unlike the weekday pattern, these are not anchored at
// end-of-string, so "january" must be offered before "jan" can swallow it.
var _MONTH_PATTERN = "january|jan|february|feb|march|mar|april|apr|may|june|jun"
    + "|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec"

var _CONNECTOR = "(?:on\\s+|by\\s+|due\\s+)?"

// Rejects a date that does not exist (32 August, 30 February): JS rolls those
// over into the next month instead of failing. A year-less date that has
// already gone means next year's — "file taxes jan 5" typed in August is 5
// January, not a date four months in the past.
function _calendarDay(year, month, day, now, yearWasGiven) {
    if (month < 0 || month > 11 || day < 1 || day > 31)
        return null

    var d = new Date(year, month, day)
    if (d.getFullYear() !== year || d.getMonth() !== month || d.getDate() !== day)
        return null

    if (!yearWasGiven) {
        var today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        if (d.getTime() < today.getTime()) {
            d = new Date(year + 1, month, day)
            if (d.getMonth() !== month || d.getDate() !== day)
                return null
        }
    }

    return {year: d.getFullYear(), month: d.getMonth(), day: d.getDate()}
}

// A two-digit year is this century: "30/8/26" is 2026.
function _fullYear(text) {
    var y = parseInt(text, 10)
    return y < 100 ? 2000 + y : y
}

// Each rule resolves to a calendar day plus, optionally, a time the phrase
// implies on its own ("tonight" means 20:00 unless a time follows it).
var _DATE_RULES = [
    {
        re: /(?:^|\s)(?:on\s+|by\s+|due\s+)?today$/i,
        read: function (m, now) {
            return {year: now.getFullYear(), month: now.getMonth(), day: now.getDate()}
        }
    },
    {
        re: /(?:^|\s)(?:on\s+|by\s+|due\s+)?tomorrow$/i,
        read: function (m, now) {
            // Day + 1 rolls the month and year over on its own.
            var d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
            return {year: d.getFullYear(), month: d.getMonth(), day: d.getDate()}
        }
    },
    {
        re: /(?:^|\s)tonight$/i,
        read: function (m, now) {
            return {year: now.getFullYear(), month: now.getMonth(), day: now.getDate(),
                    impliedTime: {hour: 20, minute: 0}}
        }
    },
    {
        // "friday", "this friday", "next friday", "on tuesday"
        re: new RegExp("(?:^|\\s)(?:on\\s+|by\\s+|due\\s+)?(?:(this|next)\\s+)?("
                       + _WEEKDAY_PATTERN + ")$", "i"),
        read: function (m, now) {
            var target = _WEEKDAYS[m[2].toLowerCase()]
            var day

            if ((m[1] || "").toLowerCase() === "next") {
                // The weekday of the *following* Mon-Sun week. "next friday" on
                // a Tuesday means eleven days out, not three — anything else
                // makes "next" mean nothing on some days of the week.
                var backToMonday = (now.getDay() + 6) % 7
                var monday = new Date(now.getFullYear(), now.getMonth(),
                                      now.getDate() - backToMonday + 7)
                day = new Date(monday.getFullYear(), monday.getMonth(),
                               monday.getDate() + ((target + 6) % 7))
            } else {
                // Today counts: "gym friday" typed on a Friday means today.
                day = new Date(now.getFullYear(), now.getMonth(),
                               now.getDate() + ((target - now.getDay() + 7) % 7))
            }

            return {year: day.getFullYear(), month: day.getMonth(), day: day.getDate()}
        }
    },
    {
        // "in 3 days", "in a week", "in 2 months"
        re: /(?:^|\s)in\s+(\d{1,3}|an?)\s+(days?|weeks?|months?)$/i,
        read: function (m, now) {
            var count = /^an?$/i.test(m[1]) ? 1 : parseInt(m[1], 10)
            var unit = m[2].toLowerCase()
            var day

            if (unit.indexOf("month") === 0)
                day = new Date(now.getFullYear(), now.getMonth() + count, now.getDate())
            else
                day = new Date(now.getFullYear(), now.getMonth(),
                               now.getDate() + count * (unit.indexOf("week") === 0 ? 7 : 1))

            return {year: day.getFullYear(), month: day.getMonth(), day: day.getDate()}
        }
    },
    {
        // "aug 30", "august 30th", "aug 30 2027"
        re: new RegExp("(?:^|\\s)" + _CONNECTOR + "(" + _MONTH_PATTERN
                       + ")\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{4}))?$", "i"),
        read: function (m, now) {
            return _calendarDay(m[3] ? parseInt(m[3], 10) : now.getFullYear(),
                                _MONTHS[m[1].toLowerCase()], parseInt(m[2], 10), now, !!m[3])
        }
    },
    {
        // "30 aug", "30th august 2027"
        re: new RegExp("(?:^|\\s)" + _CONNECTOR + "(\\d{1,2})(?:st|nd|rd|th)?\\s+("
                       + _MONTH_PATTERN + ")\\.?(?:,?\\s+(\\d{4}))?$", "i"),
        read: function (m, now) {
            return _calendarDay(m[3] ? parseInt(m[3], 10) : now.getFullYear(),
                                _MONTHS[m[2].toLowerCase()], parseInt(m[1], 10), now, !!m[3])
        }
    },
    {
        // "2026-08-30"
        re: new RegExp("(?:^|\\s)" + _CONNECTOR + "(\\d{4})-(\\d{1,2})-(\\d{1,2})$"),
        read: function (m, now) {
            return _calendarDay(parseInt(m[1], 10), parseInt(m[2], 10) - 1,
                                parseInt(m[3], 10), now, true)
        }
    },
    {
        // "30/8", "30/8/2026", "30.8.26" — day first, which is what makes
        // "2/9" the second of September. The other reading needs the year.
        re: new RegExp("(?:^|\\s)" + _CONNECTOR + "(\\d{1,2})([\\/.])(\\d{1,2})(?:\\2(\\d{2,4}))?$"),
        read: function (m, now) {
            return _calendarDay(m[4] ? _fullYear(m[4]) : now.getFullYear(),
                                parseInt(m[3], 10) - 1, parseInt(m[1], 10), now, !!m[4])
        }
    }
]

function _matchFirst(rules, text, now) {
    for (var i = 0; i < rules.length; i++) {
        var m = rules[i].re.exec(text)
        if (!m)
            continue
        var value = rules[i].read(m, now)
        if (!value)
            continue
        // m.index sits on the leading space (or 0 at the start of the string),
        // so it is exactly where the phrase begins.
        value.index = m.index
        return value
    }
    return null
}

// Returns null when nothing trailing reads as a date, or
// {summary, due, allDay} when it does. summary may be empty — the caller
// decides whether a date with no title is worth offering.
function parseTrailingDate(text, nowMs) {
    var s = typeof text === "string" ? text : ""
    if (s.trim().length === 0)
        return null

    var now = new Date(nowMs)
    if (isNaN(now.getTime()))
        return null

    var time = _matchFirst(_TIME_RULES, s, now)
    var head = time ? s.substring(0, time.index) : s
    var date = _matchFirst(_DATE_RULES, head, now)

    if (!date && !time)
        return null

    var summary = (date ? head.substring(0, date.index) : head).trim()

    if (!date) {
        // A bare time means today, or tomorrow when today's has already gone.
        var candidate = new Date(now.getFullYear(), now.getMonth(), now.getDate(),
                                 time.hour, time.minute, 0)
        if (candidate.getTime() <= now.getTime())
            candidate = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1,
                                 time.hour, time.minute, 0)
        return {summary: summary, due: _timedIso(candidate), allDay: false}
    }

    var clock = time || date.impliedTime
    if (!clock)
        return {summary: summary, due: _allDayIso(date.year, date.month, date.day), allDay: true}

    var due = new Date(date.year, date.month, date.day, clock.hour, clock.minute, 0)
    return {summary: summary, due: _timedIso(due), allDay: false}
}
