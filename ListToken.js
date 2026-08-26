.pragma library

// The "/List" token: which task list a query names, and what is left of the
// query once that token is taken out. Pure and Qt-free like DateParser.js, so
// every case is covered by tests/tst_ListToken.qml.
//
// The token is read from anywhere in the query rather than only at the end,
// because DateParser owns the *trailing* phrase — "milk /personal tomorrow"
// and "milk tomorrow /personal" have to mean the same thing.

// Matching a name is deliberately forgiving, but a name it cannot match is
// left alone: an unrecognised "/etc/hosts" is a path the user typed, not a
// mistake worth reporting.
var MAX_MATCHES = 5

// A calendar hidden in dcal, or excluded from sync (which purges its local
// copy), is one the user has switched off. Its tasks do not belong in the
// launcher, it is not a valid creation target, and a token must not be able
// to name it. TaskItems delegates to this so the rule has one home; it lives
// here because TaskItems imports this file and not the other way round.
function isUsableTaskList(cal) {
    return !!cal && cal.holdsTasks === true && !cal.readOnly
        && !cal.hidden && !cal.syncDisabled
}

var RANK_EXACT = 0
var RANK_NAME_PREFIX = 1
var RANK_WORD_PREFIX = 2

// -1 when the name does not answer to this token at all. Everything is
// compared lowercased; the name is also compared with its spaces squashed out
// so "Guitar Learning" can be typed as one word.
function _rank(name, token) {
    var lower = (name || "").toLowerCase()
    if (lower.length === 0)
        return -1

    var squashed = lower.replace(/\s+/g, "")
    if (squashed === token)
        return RANK_EXACT
    if (squashed.indexOf(token) === 0)
        return RANK_NAME_PREFIX

    // Any word may be the one the user reached for: "Understand ADHD" is
    // /adhd to anyone who filed it, and "0. Inbox" is /inbox.
    var words = lower.split(/\s+/)
    for (var i = 0; i < words.length; i++) {
        if (words[i].indexOf(token) === 0)
            return RANK_WORD_PREFIX
    }
    return -1
}

// Best match first: exact name, then a prefix of the whole name, then a
// prefix of some later word; ties go to the shorter name, then alphabetically.
// An exact match does not suppress the others — with both "Inbox" and
// "0. Inbox" present, /inbox offers a row for each and merely leads with the
// one it matches outright.
function _matchingLists(token, calendars) {
    var cals = calendars || {}
    var matches = []

    for (var id in cals) {
        var cal = cals[id]
        if (!isUsableTaskList(cal))
            continue
        var rank = _rank(cal.name, token)
        if (rank === -1)
            continue
        matches.push({rank: rank, cal: cal})
    }

    matches.sort(function (a, b) {
        if (a.rank !== b.rank)
            return a.rank - b.rank

        var na = (a.cal.name || "").toLowerCase()
        var nb = (b.cal.name || "").toLowerCase()
        if (na.length !== nb.length)
            return na.length - nb.length
        if (na !== nb)
            return na < nb ? -1 : 1

        // Same name in two accounts: order by id so the rows never shuffle
        // between keystrokes.
        return a.cal.id < b.cal.id ? -1 : (a.cal.id > b.cal.id ? 1 : 0)
    })

    var lists = []
    for (var i = 0; i < matches.length && i < MAX_MATCHES; i++)
        lists.push(matches[i].cal)
    return lists
}

// Returns null when nothing in the query names a usable task list, or
// {token, rest, lists} when something does. rest is the query with that one
// token removed — it may be empty, and the caller decides what an empty one
// means. lists is never empty.
function parseListToken(query, calendars) {
    var s = typeof query === "string" ? query : ""
    if (s.length === 0)
        return null

    // A token is a whole word opening with a slash, so a path, a URL or a
    // fraction ("1/2") is never mistaken for one. Built per call: a global
    // regexp carries lastIndex between uses, and this file is a library.
    var re = /(?:^|\s)\/(\S+)/g
    var found = []
    var m
    while ((m = re.exec(s)) !== null)
        found.push({token: m[1].toLowerCase(), start: m.index, end: m.index + m[0].length})

    // Last one wins: it is the one being typed, and it lets an earlier
    // slashed word stay in the title.
    for (var i = found.length - 1; i >= 0; i--) {
        var lists = _matchingLists(found[i].token, calendars)
        if (lists.length === 0)
            continue
        return {
            token: found[i].token,
            rest: (s.substring(0, found[i].start) + s.substring(found[i].end)).trim(),
            lists: lists
        }
    }

    return null
}
