import QtQuick
import QtTest
import "../DateParser.js" as DateParser

TestCase {
    name: "DateParser"

    // Every expectation is built from local Date getters so the suite holds in
    // any timezone. All-day dues are UTC midnight (dcal's convention), so they
    // are read back with the UTC getters; timed dues are real instants and are
    // read back with the local ones.

    function at(y, m, d, h, min) {
        return new Date(y, m, d, h === undefined ? 0 : h, min === undefined ? 0 : min, 0).getTime()
    }

    function verifyAllDay(r, y, m, d) {
        verify(r !== null, "expected a parse, got null")
        compare(r.allDay, true)
        var due = new Date(r.due)
        compare(due.getUTCFullYear(), y)
        compare(due.getUTCMonth(), m)
        compare(due.getUTCDate(), d)
        compare(due.getUTCHours(), 0)
        compare(due.getUTCMinutes(), 0)
    }

    function verifyTimed(r, y, m, d, h, min) {
        verify(r !== null, "expected a parse, got null")
        compare(r.allDay, false)
        var due = new Date(r.due)
        compare(due.getFullYear(), y)
        compare(due.getMonth(), m)
        compare(due.getDate(), d)
        compare(due.getHours(), h)
        compare(due.getMinutes(), min)
    }

    // Fri 21 Aug 2026, 10:00 local — the reference "now" for most cases.
    readonly property double friMorning: at(2026, 7, 21, 10, 0)

    function test_tomorrowAtTime_splitsSummaryFromDue() {
        var r = DateParser.parseTrailingDate("publish tasks plugin tomorrow at 6PM", friMorning)
        compare(r.summary, "publish tasks plugin")
        verifyTimed(r, 2026, 7, 22, 18, 0)
    }

    function test_tomorrowAlone_isAllDay() {
        var r = DateParser.parseTrailingDate("renew passport tomorrow", friMorning)
        compare(r.summary, "renew passport")
        verifyAllDay(r, 2026, 7, 22)
    }

    function test_today_isAllDayToday() {
        var r = DateParser.parseTrailingDate("water plants today", friMorning)
        compare(r.summary, "water plants")
        verifyAllDay(r, 2026, 7, 21)
    }

    function test_tonight_isTodayAtEight() {
        var r = DateParser.parseTrailingDate("take the bins out tonight", friMorning)
        compare(r.summary, "take the bins out")
        verifyTimed(r, 2026, 7, 21, 20, 0)
    }

    function test_plainTextHasNoDate() {
        compare(DateParser.parseTrailingDate("buy milk", friMorning), null)
    }

    function test_dateWordMidSentenceIsNotStripped() {
        compare(DateParser.parseTrailingDate("buy milk for saturday party", friMorning), null)
    }

    function test_emptyInputHasNoDate() {
        compare(DateParser.parseTrailingDate("", friMorning), null)
        compare(DateParser.parseTrailingDate(undefined, friMorning), null)
    }

    function test_bareWeekdayCountsToday() {
        var r = DateParser.parseTrailingDate("gym friday", friMorning)
        compare(r.summary, "gym")
        verifyAllDay(r, 2026, 7, 21)
    }

    function test_bareWeekdayTakesNearestFutureOccurrence() {
        var r = DateParser.parseTrailingDate("gym monday", friMorning)
        compare(r.summary, "gym")
        verifyAllDay(r, 2026, 7, 24)
    }

    function test_weekdayAbbreviationWorks() {
        var r = DateParser.parseTrailingDate("gym sat", friMorning)
        compare(r.summary, "gym")
        verifyAllDay(r, 2026, 7, 22)
    }

    function test_thisWeekdayMatchesBareWeekday() {
        var r = DateParser.parseTrailingDate("gym this friday", friMorning)
        compare(r.summary, "gym")
        verifyAllDay(r, 2026, 7, 21)
    }

    // "next friday" is the friday of the following Mon-Sun week, never a
    // friday that is only days away.
    function test_nextWeekdayIsInTheFollowingWeek() {
        var r = DateParser.parseTrailingDate("call dentist next friday", friMorning)
        compare(r.summary, "call dentist")
        verifyAllDay(r, 2026, 7, 28)
    }

    function test_nextWeekdayFromSundayStaysInTheFollowingWeek() {
        var r = DateParser.parseTrailingDate("call dentist next monday", at(2026, 7, 23, 10, 0))
        verifyAllDay(r, 2026, 7, 24)
    }

    function test_weekdayWithTimeIsTimed() {
        var r = DateParser.parseTrailingDate("standup monday at 9:30am", friMorning)
        compare(r.summary, "standup")
        verifyTimed(r, 2026, 7, 24, 9, 30)
    }

    function test_onWeekdayConnectorIsAbsorbed() {
        var r = DateParser.parseTrailingDate("pay rent on tuesday", friMorning)
        compare(r.summary, "pay rent")
        verifyAllDay(r, 2026, 7, 25)
    }

    function test_inNDays() {
        var r = DateParser.parseTrailingDate("review PR in 3 days", friMorning)
        compare(r.summary, "review PR")
        verifyAllDay(r, 2026, 7, 24)
    }

    function test_inNWeeksRollsIntoNextMonth() {
        var r = DateParser.parseTrailingDate("dentist in 2 weeks", friMorning)
        compare(r.summary, "dentist")
        verifyAllDay(r, 2026, 8, 4)
    }

    function test_inAWeekMeansSeven() {
        var r = DateParser.parseTrailingDate("dentist in a week", friMorning)
        verifyAllDay(r, 2026, 7, 28)
    }

    function test_inNMonths() {
        var r = DateParser.parseTrailingDate("renew insurance in 1 month", friMorning)
        compare(r.summary, "renew insurance")
        verifyAllDay(r, 2026, 8, 21)
    }

    function test_inNDaysWithTimeIsTimed() {
        var r = DateParser.parseTrailingDate("ship it in 2 days at 5pm", friMorning)
        compare(r.summary, "ship it")
        verifyTimed(r, 2026, 7, 23, 17, 0)
    }

    function test_inSomethingThatIsNotAUnitHasNoDate() {
        compare(DateParser.parseTrailingDate("pick up 3 apples", friMorning), null)
        compare(DateParser.parseTrailingDate("hand in 3 forms", friMorning), null)
    }

    function test_monthNameThenDay() {
        var r = DateParser.parseTrailingDate("renew passport aug 30", friMorning)
        compare(r.summary, "renew passport")
        verifyAllDay(r, 2026, 7, 30)
    }

    function test_fullMonthNameAndOrdinalSuffix() {
        verifyAllDay(DateParser.parseTrailingDate("renew passport august 30th", friMorning),
                     2026, 7, 30)
    }

    function test_dayThenMonthName() {
        var r = DateParser.parseTrailingDate("renew passport 30 aug", friMorning)
        compare(r.summary, "renew passport")
        verifyAllDay(r, 2026, 7, 30)
    }

    function test_explicitYearIsHonoured() {
        verifyAllDay(DateParser.parseTrailingDate("renew passport 30 august 2027", friMorning),
                     2027, 7, 30)
    }

    // A year-less date that has already gone means the next one.
    function test_yearlessDateInThePastRollsForward() {
        verifyAllDay(DateParser.parseTrailingDate("file taxes jan 5", friMorning), 2027, 0, 5)
    }

    function test_isoDate() {
        var r = DateParser.parseTrailingDate("renew passport 2026-08-30", friMorning)
        compare(r.summary, "renew passport")
        verifyAllDay(r, 2026, 7, 30)
    }

    function test_slashDateIsDayFirst() {
        verifyAllDay(DateParser.parseTrailingDate("renew passport 30/8", friMorning), 2026, 7, 30)
    }

    // Pins the ambiguous case: 2/9 is 2 September, never 9 February.
    function test_ambiguousSlashDateIsDayFirst() {
        verifyAllDay(DateParser.parseTrailingDate("renew passport 2/9", friMorning), 2026, 8, 2)
    }

    function test_dottedDateWithYear() {
        verifyAllDay(DateParser.parseTrailingDate("renew passport 30.8.2026", friMorning),
                     2026, 7, 30)
    }

    function test_explicitDateWithTimeIsTimed() {
        var r = DateParser.parseTrailingDate("board flight aug 30 at 6:45am", friMorning)
        compare(r.summary, "board flight")
        verifyTimed(r, 2026, 7, 30, 6, 45)
    }

    function test_impossibleDatesAreNotDates() {
        compare(DateParser.parseTrailingDate("split the bill 32/8", friMorning), null)
        compare(DateParser.parseTrailingDate("split the bill 30/13", friMorning), null)
        compare(DateParser.parseTrailingDate("feed cat feb 30", friMorning), null)
    }

    function test_monthNameWithoutADayIsNotADate() {
        compare(DateParser.parseTrailingDate("plan for august", friMorning), null)
    }

    function test_bareTimeStillAheadMeansToday() {
        var r = DateParser.parseTrailingDate("standup at 6pm", friMorning)
        compare(r.summary, "standup")
        verifyTimed(r, 2026, 7, 21, 18, 0)
    }

    function test_bareTimeAlreadyPassedMeansTomorrow() {
        var r = DateParser.parseTrailingDate("standup at 9:30am", friMorning)
        compare(r.summary, "standup")
        verifyTimed(r, 2026, 7, 22, 9, 30)
    }

    function test_bareTwentyFourHourTime() {
        verifyTimed(DateParser.parseTrailingDate("standup 18:00", friMorning),
                    2026, 7, 21, 18, 0)
    }

    function test_noonAndMidnightBoundaries() {
        verifyTimed(DateParser.parseTrailingDate("lunch at 12pm", friMorning),
                    2026, 7, 21, 12, 0)
        verifyTimed(DateParser.parseTrailingDate("backup at 12am", friMorning),
                    2026, 7, 22, 0, 0)
    }

    function test_impossibleTimesAreNotTimes() {
        compare(DateParser.parseTrailingDate("burn 25:00 of fuel", friMorning), null)
        compare(DateParser.parseTrailingDate("wait 10:99", friMorning), null)
    }

    function test_dateOnlyQueryHasAnEmptySummary() {
        var r = DateParser.parseTrailingDate("tomorrow", friMorning)
        compare(r.summary, "")
        verifyAllDay(r, 2026, 7, 22)
    }

    function test_unusableClockLeavesTextAlone() {
        compare(DateParser.parseTrailingDate("gym tomorrow", NaN), null)
    }

    // The all-day wire format is what dcal itself writes: UTC midnight.
    function test_allDayDueIsUtcMidnightLiteral() {
        compare(DateParser.parseTrailingDate("gym aug 30", friMorning).due,
                "2026-08-30T00:00:00Z")
    }

    // A timed due carries a real offset, so it survives the round trip through
    // dcal into whatever zone reads it back.
    function test_timedDueCarriesAnExplicitOffset() {
        var due = DateParser.parseTrailingDate("gym aug 30 at 6pm", friMorning).due
        verify(/^2026-08-30T18:00:00[-+]\d{2}:\d{2}$/.test(due), "unexpected due: " + due)
    }

    // A bare hour is read as a 24-hour clock: 5 is 05:00, 17 is 17:00.
    function test_bareHourIsTwentyFourHour() {
        var r = DateParser.parseTrailingDate("test input tomorrow at 5", friMorning)
        compare(r.summary, "test input")
        verifyTimed(r, 2026, 7, 22, 5, 0)
    }

    function test_bareAfternoonHour() {
        verifyTimed(DateParser.parseTrailingDate("test input tomorrow at 17", friMorning),
                    2026, 7, 22, 17, 0)
    }

    function test_bareHourZeroIsMidnight() {
        verifyTimed(DateParser.parseTrailingDate("backup tomorrow at 0", friMorning),
                    2026, 7, 22, 0, 0)
    }

    function test_bareHourWithoutADateFollowsTheTodayOrTomorrowRule() {
        // 17:00 is still ahead of 10:00, so it is today.
        verifyTimed(DateParser.parseTrailingDate("standup at 17", friMorning),
                    2026, 7, 21, 17, 0)
        // 05:00 has gone, so it is tomorrow.
        verifyTimed(DateParser.parseTrailingDate("standup at 5", friMorning),
                    2026, 7, 22, 5, 0)
    }

    function test_bareHourAlongsideAWeekday() {
        verifyTimed(DateParser.parseTrailingDate("gym friday at 5", friMorning),
                    2026, 7, 21, 5, 0)
    }

    // "at" is required. Without it a trailing number is part of the title, or
    // every "buy 5" would sprout a due date.
    function test_trailingNumberWithoutAtIsNotATime() {
        compare(DateParser.parseTrailingDate("buy 5", friMorning), null)
        compare(DateParser.parseTrailingDate("order pizza 12", friMorning), null)
    }

    function test_bareHourOutOfRangeIsNotATime() {
        compare(DateParser.parseTrailingDate("wait at 24", friMorning), null)
        compare(DateParser.parseTrailingDate("wait at 99", friMorning), null)
    }

    // The am/pm and HH:MM forms still win over the bare-hour reading.
    function test_meridiemAndColonFormsAreUnaffected() {
        verifyTimed(DateParser.parseTrailingDate("standup tomorrow at 5pm", friMorning),
                    2026, 7, 22, 17, 0)
        verifyTimed(DateParser.parseTrailingDate("standup tomorrow at 5:45", friMorning),
                    2026, 7, 22, 5, 45)
    }
}
