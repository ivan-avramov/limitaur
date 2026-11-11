import Foundation
import Testing
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes (baseline has no reset day, so Claude spend never resets),
// I = preserves an invariant, N = exercises new behaviour. Criterion C2.

@Suite struct SBMonthlyResetDayTests {
    // N: the default is the 1st.
    @Test func defaultIsTheFirst() { #expect(MonthlyResetDay.default == .day(1)) }

    // N: storage round-trips for every valid value and is the documented text.
    @Test func storageRoundTrip() {
        for n in 1...28 {
            #expect(MonthlyResetDay.day(n).storage == String(n))
            #expect(MonthlyResetDay(storage: String(n)) == .day(n))
        }
        #expect(MonthlyResetDay.lastDay.storage == "last" && MonthlyResetDay(storage: "last") == .lastDay)
    }
    // N: anything else is nil.
    @Test func invalidStorageIsNil() {
        for text in ["0", "29", "31", "-1", "", " ", "abc", "Last", "1.5", "1 ", "٣"] { #expect(MonthlyResetDay(storage: text) == nil, "\(text)") }
    }
    // N: the type is Codable for the controller's persistence.
    @Test func codableRoundTrip() throws {
        for day in [MonthlyResetDay.day(1), .day(15), .day(28), .lastDay] {
            #expect(try JSONDecoder().decode(MonthlyResetDay.self, from: JSONEncoder().encode(day)) == day)
        }
    }

    // N: day 1 across a month and the December rollover.
    @Test func dayOne() {
        let day = MonthlyResetDay.day(1)
        #expect(day.nextReset(after: sbUTC(2026, 11, 10, 12)) == sbUTC(2026, 12, 1))
        #expect(day.periodStart(containing: sbUTC(2026, 11, 10, 12)) == sbUTC(2026, 11, 1))
        #expect(day.nextReset(after: sbUTC(2026, 12, 15)) == sbUTC(2027, 1, 1))
        #expect(day.nextReset(after: sbUTC(2026, 12, 31, 23, 59, 59)) == sbUTC(2027, 1, 1))
        #expect(day.periodStart(containing: sbUTC(2026, 12, 31, 23, 59, 59)) == sbUTC(2026, 12, 1))
        #expect(day.periodStart(containing: sbUTC(2027, 1, 15)) == sbUTC(2027, 1, 1))
    }
    // N: day 15 and day 28, before and after the day, across the year boundary.
    @Test func dayFifteenAndTwentyEight() {
        let fifteen = MonthlyResetDay.day(15)
        #expect(fifteen.nextReset(after: sbUTC(2026, 11, 10)) == sbUTC(2026, 11, 15))
        #expect(fifteen.nextReset(after: sbUTC(2026, 11, 20)) == sbUTC(2026, 12, 15))
        #expect(fifteen.nextReset(after: sbUTC(2026, 12, 20)) == sbUTC(2027, 1, 15))
        #expect(fifteen.periodStart(containing: sbUTC(2026, 11, 10)) == sbUTC(2026, 10, 15))
        #expect(fifteen.periodStart(containing: sbUTC(2027, 1, 10)) == sbUTC(2026, 12, 15))
        let last = MonthlyResetDay.day(28)
        #expect(last.nextReset(after: sbUTC(2027, 2, 10)) == sbUTC(2027, 2, 28))
        #expect(last.nextReset(after: sbUTC(2027, 2, 28, 0, 0, 1)) == sbUTC(2027, 3, 28))
        #expect(last.periodStart(containing: sbUTC(2027, 3, 1)) == sbUTC(2027, 2, 28))
        #expect(last.nextReset(after: sbUTC(2028, 2, 10)) == sbUTC(2028, 2, 28), "leap years do not move day 28")
    }
    // N: the last day resolves per month: 31, 30, 28 and 29 (leap), and the century rules.
    @Test func lastDayResolvesPerMonth() {
        let day = MonthlyResetDay.lastDay
        #expect(day.nextReset(after: sbUTC(2026, 1, 15)) == sbUTC(2026, 1, 31))
        #expect(day.nextReset(after: sbUTC(2026, 4, 10)) == sbUTC(2026, 4, 30))
        #expect(day.nextReset(after: sbUTC(2027, 2, 10)) == sbUTC(2027, 2, 28))
        #expect(day.nextReset(after: sbUTC(2028, 2, 10)) == sbUTC(2028, 2, 29))
        #expect(day.nextReset(after: sbUTC(2100, 2, 10)) == sbUTC(2100, 2, 28), "2100 is not a leap year")
        #expect(day.nextReset(after: sbUTC(2000, 2, 10)) == sbUTC(2000, 2, 29), "2000 is a leap year")
        #expect(day.nextReset(after: sbUTC(2026, 12, 15)) == sbUTC(2026, 12, 31))
    }
    // N: the last day across Jan 31 -> Feb 28/29 and Dec 31 -> Jan 31, in both directions.
    @Test func lastDayAcrossMonthBoundaries() {
        let day = MonthlyResetDay.lastDay
        #expect(day.nextReset(after: sbUTC(2027, 1, 31)) == sbUTC(2027, 2, 28), "exactly at Jan 31 moves to Feb 28")
        #expect(day.nextReset(after: sbUTC(2028, 1, 31)) == sbUTC(2028, 2, 29))
        #expect(day.nextReset(after: sbUTC(2027, 2, 28)) == sbUTC(2027, 3, 31))
        #expect(day.nextReset(after: sbUTC(2026, 12, 31)) == sbUTC(2027, 1, 31))
        #expect(day.periodStart(containing: sbUTC(2027, 3, 15)) == sbUTC(2027, 2, 28))
        #expect(day.periodStart(containing: sbUTC(2028, 3, 15)) == sbUTC(2028, 2, 29))
        #expect(day.periodStart(containing: sbUTC(2027, 1, 15)) == sbUTC(2026, 12, 31))
        #expect(day.periodStart(containing: sbUTC(2027, 2, 10)) == sbUTC(2027, 1, 31))
    }
    // N: at exactly a reset instant periodStart is that instant and nextReset is the following month's.
    @Test func exactlyAtResetInstant() {
        for (day, at, next) in [(MonthlyResetDay.day(1), sbUTC(2026, 11, 1), sbUTC(2026, 12, 1)),
                                (.day(15), sbUTC(2026, 12, 15), sbUTC(2027, 1, 15)),
                                (.day(28), sbUTC(2027, 2, 28), sbUTC(2027, 3, 28)),
                                (.lastDay, sbUTC(2028, 2, 29), sbUTC(2028, 3, 31))] {
            #expect(day.periodStart(containing: at) == at)
            #expect(day.nextReset(after: at) == next)
            #expect(day.nextReset(after: at.addingTimeInterval(-0.5)) == at, "just before the instant")
            #expect(day.periodStart(containing: at.addingTimeInterval(-0.5)) < at)
        }
    }
    // N: .day values outside 1...28 behave as the 1st.
    @Test func outOfRangeDaysAreTheFirst() {
        for n in [0, -3, 29, 31, 100] {
            for instant in [sbUTC(2026, 11, 10, 12), sbUTC(2026, 11, 1), sbUTC(2026, 12, 31, 23, 59, 59), sbUTC(2028, 2, 29)] {
                #expect(MonthlyResetDay.day(n).nextReset(after: instant) == MonthlyResetDay.day(1).nextReset(after: instant))
                #expect(MonthlyResetDay.day(n).periodStart(containing: instant) == MonthlyResetDay.day(1).periodStart(containing: instant))
            }
        }
    }
    // I: for every day setting and every day across three years, the period is a half-open interval that starts and ends at
    // 00:00 UTC and consecutive periods tile with no gap or overlap.
    @Test func periodsTileAtMidnightUTC() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var days: [MonthlyResetDay] = [.lastDay, .day(0), .day(29)]
        days += (1...28).map { .day($0) }
        for day in days {
            var instant = sbUTC(2027, 12, 20, 6, 30)
            for _ in 0..<1100 {
                let start = day.periodStart(containing: instant), end = day.nextReset(after: instant)
                #expect(start <= instant && instant < end, "\(day) \(instant)")
                #expect(day.nextReset(after: start) == end && day.periodStart(containing: end) == end, "\(day) \(instant)")
                for edge in [start, end] {
                    let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: edge)
                    #expect(parts.hour == 0 && parts.minute == 0 && parts.second == 0 && (parts.nanosecond ?? 0) == 0, "\(day) \(edge)")
                }
                let length = end.timeIntervalSince(start) / 86_400
                #expect((28...31).contains(length.rounded()) && length == length.rounded(), "\(day) \(instant)")
                instant = instant.addingTimeInterval(86_400)
            }
        }
    }
}
