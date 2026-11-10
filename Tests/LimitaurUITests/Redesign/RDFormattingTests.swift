import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

// Classes: N = exercises new behaviour (I4 formatting functions), R = reproduces a failure the specification fixes.
// Criterion C4.

private let rdUS = Locale(identifier: "en_US")
private let rdNow = Date(timeIntervalSince1970: 1_800_000_000)
private func rdMetric(reset: Date?) -> UsageMetric { UsageMetric(id: "m", label: "Window", usedPercent: 40, resetsAt: reset) }

@Suite struct RDFormattingTests {
    // N, S4: unknown values (nil, negative, not finite) show a dash.
    @Test(arguments: [nil, -1, -0.01, Double.nan, .infinity, -.infinity] as [Double?])
    func percentTextUnknownIsADash(_ value: Double?) { #expect(percentText(value) == "—") }

    // N, S4: percentages show as whole numbers, with the I4 edge rules.
    @Test(arguments: [(0.0, "0%"), (0.0001, "<1%"), (0.1, "<1%"), (0.49, "<1%"), (0.4999, "<1%"), (0.5, "1%"),
                      (1.0, "1%"), (1.49, "1%"), (1.5, "2%"), (25.0, "25%"), (80.0, "80%"), (84.6, "85%"),
                      (98.4, "98%"), (98.5, "99%"), (99.0, "99%"), (99.49, "99%"), (99.5, "99%"), (99.9, "99%"),
                      (99.999, "99%"), (100.0, "100%"), (100.4, "100%"), (100.5, "101%"), (120.0, "120%"),
                      (1000.0, "1000%")] as [(Double, String)])
    func percentTextRoundsToWholeNumbers(_ value: Double, _ expected: String) {
        #expect(percentText(value) == expected)
    }

    // R, F1: a huge finite percentage formats without trapping (the baseline-candidate converted to Int and crashed).
    @Test(arguments: [1e15, 1e18, 9.3e18, 1e30, Double.greatestFiniteMagnitude])
    func percentTextHugeValuesDoNotTrap(_ value: Double) {
        let text = percentText(value)
        #expect(text.hasSuffix("%") && text.count > 3)
        #expect(text.dropLast().allSatisfy { $0.isNumber })
    }
    // R, F1: at 1e15 and above the text is the whole number with no decimals.
    @Test func percentTextUsesFixedFormatAtOneE15() {
        #expect(percentText(1e15) == "1000000000000000%")
        #expect(percentText(999_999_999_999_999) == "999999999999999%")
    }

    // N, S4: the exact value is the tooltip text with two decimals, or "unknown".
    @Test(arguments: [(0.0, "0.00%"), (7.5, "7.50%"), (98.4, "98.40%"), (99.999, "100.00%"), (120.0, "120.00%")] as [(Double, String)])
    func exactPercentTextHasTwoDecimals(_ value: Double, _ expected: String) {
        #expect(exactPercentText(value) == expected)
        #expect(exactPercentText(value) == String(format: "%.2f%%", value))
    }
    @Test func exactPercentTextUnknown() { #expect(exactPercentText(nil) == "unknown") }

    // N: three uppercase ASCII letters format as a currency in the given locale.
    @Test(arguments: [("86.14", "USD", "$86.14"), ("5000", "USD", "$5,000.00"), ("0", "USD", "$0.00"),
                      ("1234567.5", "USD", "$1,234,567.50"), ("86.14", "EUR", "€86.14"), ("3", "GBP", "£3.00")])
    func amountTextFormatsCurrencyCodes(_ amount: String, _ currency: String, _ expected: String) throws {
        #expect(amountText(try #require(Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX"))), currency: currency, locale: rdUS) == expected)
    }
    // N: anything else is the amount and the currency text as written ("credits", lowercase, wrong length, non-ASCII).
    @Test(arguments: [("3", "credits", "3 credits"), ("5", "usd", "5 usd"), ("5", "Usd", "5 Usd"), ("5", "US", "5 US"),
                      ("5", "USDX", "5 USDX"), ("5", "", "5 "), ("5", "U5D", "5 U5D"), ("2.50", "points", "2.5 points"),
                      ("5", "ÄÖÜ", "5 ÄÖÜ")])
    func amountTextFallsBackToAmountAndCurrency(_ amount: String, _ currency: String, _ expected: String) throws {
        #expect(amountText(try #require(Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX"))), currency: currency, locale: rdUS) == expected)
    }
    // N: the locale parameter is honoured for currency formatting.
    @Test func amountTextUsesTheGivenLocale() {
        let german = amountText(Decimal(string: "5000")!, currency: "EUR", locale: Locale(identifier: "de_DE"))
        #expect(german != "€5,000.00" && german.contains("5.000,00"))
    }

    // N: an expired metric says "reset due" whatever its date.
    @Test(arguments: [nil, 3600.0, -3600.0] as [Double?])
    func resetLabelExpiredIsResetDue(_ offset: Double?) {
        let metric = rdMetric(reset: offset.map { rdNow.addingTimeInterval($0) })
        #expect(resetLabel(metric, expired: true, now: rdNow) == "reset due")
    }
    // N: a known future reset reads "resets " followed by the countdown text.
    @Test(arguments: [(2700.0, "resets in 45m"), (5400.0, "resets in 2h"), (3600.0 * 24, "resets in 1d"), (3600.0 * 27, "resets in 1d 3h"),
                      (1.0, "resets in 1m")] as [(Double, String)])
    func resetLabelFutureUsesTheCountdown(_ offset: Double, _ expected: String) {
        let date = rdNow.addingTimeInterval(offset)
        #expect(resetLabel(rdMetric(reset: date), expired: false, now: rdNow) == expected)
        #expect(resetLabel(rdMetric(reset: date), expired: false, now: rdNow) == "resets " + resetCountdownText(resetAt: date, now: rdNow))
    }
    // R: a reset time that has passed (not yet flagged expired) reads "reset due", not "resets reset due".
    @Test(arguments: [0.0, -1.0, -86_400.0])
    func resetLabelPassedDatePassesThroughResetDue(_ offset: Double) {
        #expect(resetLabel(rdMetric(reset: rdNow.addingTimeInterval(offset)), expired: false, now: rdNow) == "reset due")
    }
    // R: a date outside the displayable range reads "reset time unavailable", with no "resets " prefix.
    @Test func resetLabelUnrepresentableDatePassesThrough() {
        let far = Date(timeIntervalSince1970: 300_000_000_000)
        #expect(resetLabel(rdMetric(reset: far), expired: false, now: rdNow) == "reset time unavailable")
        #expect(resetLabel(rdMetric(reset: Date(timeIntervalSince1970: -70_000_000_000)), expired: false, now: rdNow) == "reset time unavailable")
    }
    // N: no reset time reads "reset unknown".
    @Test func resetLabelUnknown() {
        #expect(resetLabel(rdMetric(reset: nil), expired: false, now: rdNow) == "reset unknown")
    }

    // N: known providers have display names; others are capitalised raw values.
    @Test(arguments: [("claude", "Claude"), ("codex", "Codex"), ("cursor", "Cursor"), ("acme", "Acme"), ("openrouter", "Openrouter")])
    func providerNameMapping(_ raw: String, _ expected: String) {
        #expect(providerName(ProviderID(raw)) == expected)
        #expect(providerName(ProviderID(raw)) == (["claude", "codex", "cursor"].contains(raw) ? expected : raw.capitalized))
    }
}
