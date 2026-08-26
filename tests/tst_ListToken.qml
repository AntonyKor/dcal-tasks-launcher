import QtQuick
import QtTest
import "../ListToken.js" as ListToken

TestCase {
    name: "ListToken"

    function makeCal(over) {
        var base = {
            id: "c", name: "List", accountName: "Radicale", holdsTasks: true,
            readOnly: false, hidden: false, syncDisabled: false
        }
        for (var k in over)
            base[k] = over[k]
        return base
    }

    // Mirrors the shape TaskItems.parseCalendars produces: id -> calendar.
    function calsOf(list) {
        var byId = {}
        for (var i = 0; i < list.length; i++)
            byId[list[i].id] = list[i]
        return byId
    }

    readonly property var cals: calsOf([
        makeCal({id: "c-inbox0", name: "0. Inbox"}),
        makeCal({id: "c-chores", name: "Chores"}),
        makeCal({id: "c-fitness", name: "Fitness"}),
        makeCal({id: "c-guitar", name: "Guitar Learning"}),
        makeCal({id: "c-inbox", name: "Inbox"}),
        makeCal({id: "c-personal", name: "Personal"}),
        makeCal({id: "c-adhd", name: "Understand ADHD"})
    ])

    function idsOf(result) {
        var ids = []
        for (var i = 0; i < result.lists.length; i++)
            ids.push(result.lists[i].id)
        return ids
    }

    function test_nullWhenQueryHasNoToken() {
        compare(ListToken.parseListToken("buy milk", cals), null)
    }

    function test_nullForEmptyOrMissingQuery() {
        compare(ListToken.parseListToken("", cals), null)
        compare(ListToken.parseListToken(undefined, cals), null)
        compare(ListToken.parseListToken(null, cals), null)
    }

    function test_nullWhenNoCalendars() {
        compare(ListToken.parseListToken("milk /personal", {}), null)
        compare(ListToken.parseListToken("milk /personal", null), null)
    }

    // An unrecognised token is ordinary text, not an error: "fix /etc/hosts"
    // keeps its path and creates in the default list.
    function test_nullWhenTokenNamesNoList() {
        compare(ListToken.parseListToken("buy milk /nosuchlist", cals), null)
        compare(ListToken.parseListToken("fix /etc/hosts", cals), null)
    }

    function test_exactNameMatches() {
        var r = ListToken.parseListToken("buy milk /personal", cals)
        compare(idsOf(r), ["c-personal"])
        compare(r.token, "personal")
        compare(r.rest, "buy milk")
    }

    function test_matchIsCaseInsensitive() {
        compare(idsOf(ListToken.parseListToken("milk /PERSONAL", cals)), ["c-personal"])
        compare(idsOf(ListToken.parseListToken("milk /PeRsOnAl", cals)), ["c-personal"])
    }

    function test_wholeNamePrefixMatches() {
        compare(idsOf(ListToken.parseListToken("milk /pers", cals)), ["c-personal"])
        compare(idsOf(ListToken.parseListToken("milk /fit", cals)), ["c-fitness"])
    }

    // "Guitar Learning" is reachable both as a leading word and by typing the
    // name through the space.
    function test_multiWordNameMatchesByFirstWord() {
        compare(idsOf(ListToken.parseListToken("scales /guitar", cals)), ["c-guitar"])
    }

    function test_multiWordNameMatchesWithSpacesStripped() {
        compare(idsOf(ListToken.parseListToken("scales /guitarlearn", cals)), ["c-guitar"])
    }

    function test_matchesALaterWordOfTheName() {
        compare(idsOf(ListToken.parseListToken("read up /adhd", cals)), ["c-adhd"])
    }

    // "0. Inbox" and "Inbox" both answer to /inbox — the caller offers a row
    // for each rather than guessing.
    function test_ambiguousTokenReturnsEveryMatch() {
        var r = ListToken.parseListToken("milk /inbox", cals)
        compare(r.lists.length, 2)
        compare(r.rest, "milk")
    }

    // /inbox is literally "Inbox", so that list leads — but "0. Inbox" is
    // still offered underneath rather than being ruled out.
    function test_exactMatchLeadsOverWordPrefixMatch() {
        compare(idsOf(ListToken.parseListToken("milk /inbox", cals))[0], "c-inbox")
    }

    function test_wholeNamePrefixOutranksWordPrefix() {
        // "Inbox" is a whole-name prefix match for "inb"; "0. Inbox" only
        // matches on its second word.
        compare(idsOf(ListToken.parseListToken("milk /inb", cals)), ["c-inbox", "c-inbox0"])
    }

    function test_equalRankOrdersShorterNameFirst() {
        var r = ListToken.parseListToken("x /i", calsOf([
            makeCal({id: "c-long", name: "Insightful"}),
            makeCal({id: "c-short", name: "Inbox"})
        ]))
        compare(idsOf(r), ["c-short", "c-long"])
    }

    function test_equalRankAndLengthOrdersAlphabetically() {
        var r = ListToken.parseListToken("x /c", calsOf([
            makeCal({id: "c-2", name: "Cycling"}),
            makeCal({id: "c-1", name: "Cooking"})
        ]))
        compare(idsOf(r), ["c-1", "c-2"])
    }

    function test_capsTheNumberOfMatches() {
        var many = []
        for (var i = 0; i < 9; i++)
            many.push(makeCal({id: "c" + i, name: "List " + i}))
        var r = ListToken.parseListToken("x /list", calsOf(many))
        compare(r.lists.length, 5)
    }

    // A list the user has switched off in dcal is not a creation target, so
    // its name must not answer to a token either.
    function test_ignoresUnusableLists() {
        var unusable = calsOf([
            makeCal({id: "c-hidden", name: "Hidden", hidden: true}),
            makeCal({id: "c-nosync", name: "Archived", syncDisabled: true}),
            makeCal({id: "c-ro", name: "Readonly", readOnly: true}),
            makeCal({id: "c-events", name: "Events", holdsTasks: false})
        ])
        compare(ListToken.parseListToken("x /hidden", unusable), null)
        compare(ListToken.parseListToken("x /archived", unusable), null)
        compare(ListToken.parseListToken("x /readonly", unusable), null)
        compare(ListToken.parseListToken("x /events", unusable), null)
    }

    // The date parser owns the trailing phrase, so the token has to be
    // readable anywhere in the query.
    function test_tokenAtTheStart() {
        var r = ListToken.parseListToken("/personal buy milk", cals)
        compare(idsOf(r), ["c-personal"])
        compare(r.rest, "buy milk")
    }

    function test_tokenInTheMiddle() {
        var r = ListToken.parseListToken("buy /personal milk tomorrow", cals)
        compare(r.rest, "buy milk tomorrow")
    }

    function test_tokenBeforeATrailingDate() {
        var r = ListToken.parseListToken("buy milk /personal tomorrow at 6PM", cals)
        compare(idsOf(r), ["c-personal"])
        compare(r.rest, "buy milk tomorrow at 6PM")
    }

    function test_tokenAfterATrailingDate() {
        var r = ListToken.parseListToken("buy milk tomorrow at 6PM /personal", cals)
        compare(idsOf(r), ["c-personal"])
        compare(r.rest, "buy milk tomorrow at 6PM")
    }

    function test_restIsEmptyWhenTheTokenIsTheWholeQuery() {
        var r = ListToken.parseListToken("/personal", cals)
        compare(idsOf(r), ["c-personal"])
        compare(r.rest, "")
    }

    function test_restKeepsSurroundingSpacingReadable() {
        compare(ListToken.parseListToken("   /personal   milk  ", cals).rest, "milk")
    }

    // Only the token that names a list is consumed; another slashed word is
    // left in the title where the user typed it.
    function test_leavesUnmatchedSlashedWordsInPlace() {
        var r = ListToken.parseListToken("fix /etc/hosts /personal", cals)
        compare(idsOf(r), ["c-personal"])
        compare(r.rest, "fix /etc/hosts")
    }

    function test_lastMatchingTokenWins() {
        var r = ListToken.parseListToken("milk /chores /personal", cals)
        compare(idsOf(r), ["c-personal"])
        compare(r.rest, "milk /chores")
    }

    // A slash inside a word is not a token: it is a path, a fraction or a URL.
    function test_slashMustStartAWord() {
        compare(ListToken.parseListToken("ratio 1/personal", cals), null)
        compare(ListToken.parseListToken("read https://personal", cals), null)
    }

    function test_bareSlashIsNotAToken() {
        compare(ListToken.parseListToken("either / or", cals), null)
        compare(ListToken.parseListToken("/", cals), null)
    }
}
