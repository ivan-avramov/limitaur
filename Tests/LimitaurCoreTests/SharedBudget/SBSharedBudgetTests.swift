import Foundation
import Testing
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes (baseline has no combined total, so a mismatched or partial sum
// cannot be refused), I = preserves an invariant, N = exercises new behaviour. Criterion C5.

private func problems(_ state: SharedBudgetState?) -> [String?] { state?.members.map(\.problem) ?? [] }

@Suite struct SBSharedBudgetTests {
    // N, C5, success trace: 410.00 + 41.00 = 451.00 of 5000 is 9.02 %, resets 2023-12-01, deadline is the earlier member's.
    @Test func successTrace() throws {
        let state = try #require(sbBudget(sbTracedRows()))
        #expect(state.members.map(\.provider) == ["claude", "cursor"] && state.members.map(\.spent) == [410, 41])
        #expect(problems(state) == [nil, nil] && state.total == 451 && state.warning == nil)
        #expect(abs(try #require(state.usedPercent) - 9.02) < 1e-9)
        #expect(state.resetsAt == sbUTC(2023, 12, 1) && state.freshnessDeadline == 150 && state.config == sbConfig())
    }
    // N, C5: the deadline is the minimum of the members' whichever order they come in.
    @Test func deadlineIsTheMinimum() throws {
        let rows = [sbRow("claude", spend: sbSummary(410), deadline: 120), sbRow("cursor", spend: sbSummary(41), deadline: 190)]
        #expect(sbBudget(rows)?.freshnessDeadline == 120)
        #expect(sbBudget(Array(rows.reversed()))?.freshnessDeadline == 120)
    }
    // N, C5: members follow the config's order, not the rows'.
    @Test func membersFollowConfigOrder() throws {
        let state = try #require(sbBudget(sbTracedRows(), sbConfig(members: ["cursor", "claude"])))
        #expect(state.members.map(\.provider) == ["cursor", "claude"] && state.members.map(\.spent) == [41, 410] && state.total == 451)
        let one = try #require(sbBudget(sbTracedRows(), sbConfig(amount: 1000, members: ["cursor"])))
        let onePercent = try #require(one.usedPercent)
        #expect(one.total == 41 && abs(onePercent - 4.1) < 1e-9)
    }
    // N, C5: a disabled config, or no members, gives nil.
    @Test func disabledOrMemberlessIsNil() {
        #expect(sbBudget(sbTracedRows(), sbConfig(enabled: false)) == nil)
        #expect(sbBudget(sbTracedRows(), sbConfig(members: [])) == nil)
    }
    // R, C5, failure trace (period mismatch): Cursor's cycle ends 2023-12-15, so no total, no percent and a named warning.
    @Test func periodMismatchRefusesTheTotal() throws {
        let rows = [sbRow("claude", spend: sbSummary(410)), sbRow("cursor", spend: sbSummary(41, end: sbUTC(2023, 12, 15)), deadline: 150)]
        let state = try #require(sbBudget(rows))
        #expect(problems(state) == [nil, "Different billing period"] && state.members.map(\.spent) == [410, nil])
        #expect(state.total == nil && state.usedPercent == nil && state.freshnessDeadline == nil)
        #expect(state.warning == "Total unavailable: Cursor Different billing period")
        #expect(state.resetsAt == sbUTC(2023, 12, 1), "the reset is still the configured day's")
    }
    // R, C5, failure trace (stale member): the Claude row is stale, so it names Claude and offers no total.
    @Test func staleMemberRefusesTheTotal() throws {
        let state = try #require(sbBudget([sbRow("claude", health: .stale, spend: sbSummary(410)), sbRow("cursor", spend: sbSummary(41))]))
        #expect(problems(state) == ["Stale", nil] && state.total == nil && state.usedPercent == nil)
        #expect(state.warning == "Total unavailable: Claude Stale")
    }
    // N, C5: each health maps to its AccountStatus label; healthy and partial rows count. H7: `.throttled` is no longer here:
    // a fresh throttled row counts (see SBRevision2Tests.throttledCountsOnlyWhileFresh).
    @Test func healthLabels() throws {
        for (health, label) in [(Health.unauthenticated, "Needs sign-in"), (.failed, "Connection failed"),
                                (.unavailable, "Unavailable"), (.stale, "Stale")] {
            let state = try #require(sbBudget([sbRow("claude", health: health, spend: sbSummary(410)), sbRow("cursor", spend: sbSummary(41))]))
            #expect(problems(state) == [label, nil] && state.members.first?.spent == nil && state.total == nil, "\(health)")
        }
        let partial = try #require(sbBudget([sbRow("claude", health: .partial, spend: sbSummary(410)), sbRow("cursor", spend: sbSummary(41))]))
        #expect(partial.total == 451 && problems(partial) == [nil, nil])
    }
    // N, C5: a row whose deadline is reached (or unknown) is unusable, so there is no spend and no total.
    @Test func freshnessDeadlineIsStrict() throws {
        #expect(sbBudget(sbTracedRows(), mono: 149.9)?.total == 451)
        for mono in [150, 190] as [TimeInterval] { #expect(sbBudget(sbTracedRows(), mono: mono)?.total == nil, "\(mono)") }
        let unknown = [sbRow("claude", spend: sbSummary(410), deadline: nil), sbRow("cursor", spend: sbSummary(41))]
        #expect(sbBudget(unknown)?.members.first?.spent == nil && sbBudget(unknown)?.total == nil)
    }
    // N, C5: problems are checked in order: health, no spend, currency, period.
    @Test func problemOrder() throws {
        let bad = sbSummary(1, currency: "EUR", end: sbUTC(2023, 12, 15))
        func problem(health: Health = .healthy, spend: SpendSummary?) throws -> String? {
            let state = try #require(sbBudget([sbRow("claude", health: health, spend: spend), sbRow("cursor", spend: sbSummary(41))]))
            return state.members.first?.problem
        }
        #expect(try problem(health: .failed, spend: nil) == "Connection failed")
        #expect(try problem(health: .stale, spend: bad) == "Stale")
        #expect(try problem(spend: nil) == "No spend reported")
        #expect(try problem(spend: bad) == "Different currency")
        #expect(try problem(spend: sbSummary(1, end: sbUTC(2023, 12, 15))) == "Different billing period")
        #expect(try problem(spend: sbSummary(1, end: nil)) == "Different billing period")
    }
    // N, C5: the period must match the configured reset exactly, to the instant.
    @Test func periodMatchesExactly() throws {
        for end in [sbCycleEnd.addingTimeInterval(1), sbCycleEnd.addingTimeInterval(-1), sbCycleEnd.addingTimeInterval(0.001)] {
            let state = try #require(sbBudget([sbRow("claude", spend: sbSummary(410, end: end)), sbRow("cursor", spend: sbSummary(41))]))
            #expect(state.members.first?.problem == "Different billing period" && state.total == nil, "\(end)")
        }
    }
    // N, C5: the configured reset day drives the expected period: a day-15 budget refuses rows ending on the 1st.
    @Test func configuredDayDecidesThePeriod() throws {
        let state = try #require(sbBudget(sbTracedRows(), sbConfig(day: .day(15))))
        #expect(problems(state) == ["Different billing period", "Different billing period"] && state.resetsAt == sbUTC(2023, 12, 15))
        #expect(state.warning == "Total unavailable: Claude Different billing period")
        // wallNow is exactly 2023-11-15 00:00, a reset instant: the expected period ends at the following month's 15th.
        let rows = [sbRow("claude", spend: sbSummary(1, end: sbUTC(2023, 12, 15))), sbRow("cursor", spend: sbSummary(2, end: sbUTC(2023, 12, 15)))]
        #expect(sbBudget(rows, sbConfig(day: .day(15)))?.total == 3)
    }
    // N, C5: a different configured currency refuses USD rows.
    @Test func configCurrencyMustMatch() throws {
        let state = try #require(sbBudget(sbTracedRows(), sbConfig(currency: "EUR")))
        #expect(problems(state) == ["Different currency", "Different currency"] && state.total == nil)
        #expect(state.warning == "Total unavailable: Claude Different currency")
    }
    // N, C5: the warning names the first failing member in config order.
    @Test func firstFailingMemberIsNamed() throws {
        let rows = [sbRow("claude", health: .failed, spend: nil), sbRow("cursor", spend: nil)]
        #expect(sbBudget(rows)?.warning == "Total unavailable: Claude Connection failed")
        #expect(sbBudget(rows, sbConfig(members: ["cursor", "claude"]))?.warning == "Total unavailable: Cursor No spend reported")
    }
    // N, C5: a missing row is a problem and refuses the total: absent from the main-account map is "Off";
    // otherwise "Off" or "Connecting…".
    @Test func missingRows() throws {
        let absent = try #require(sbBudget([sbRow("claude", spend: sbSummary(410))], mains: ["claude": "claude-default"]))
        #expect(problems(absent) == [nil, "Off"] && absent.total == nil && absent.warning == "Total unavailable: Cursor Off")
        let unmapped = try #require(sbBudget([sbRow("claude", spend: sbSummary(410))]))
        #expect(unmapped.members.last?.spent == nil && ["Off", "Connecting…"].contains(unmapped.members.last?.problem ?? ""))
        #expect(unmapped.total == nil && unmapped.usedPercent == nil && unmapped.freshnessDeadline == nil)
    }
    // N, C5: only each member's main account counts: another account of the same provider is ignored, whichever is listed first.
    @Test func onlyMainAccountsCount() throws {
        let other = sbRow("claude", id: "claude-work", spend: sbSummary(999))
        for rows in [[other] + sbTracedRows(), sbTracedRows() + [other]] {
            #expect(sbBudget(rows)?.total == 451)
        }
        let mains: [ProviderID: String] = ["claude": "claude-work", "cursor": "cursor-default"]
        #expect(sbBudget(sbTracedRows() + [other], mains: mains)?.total == 1040)
        #expect(sbBudget(sbTracedRows(), mains: mains)?.members.first?.spent == nil, "main row missing, default row ignored")
    }
    // N, C5: a nil, zero or negative amount has a total but no percent and says to set the amount; a positive one does not.
    @Test func amountRules() throws {
        for amount in [nil, 0, -5] as [Decimal?] {
            let state = try #require(sbBudget(sbTracedRows(), sbConfig(amount: amount)))
            #expect(state.total == 451 && state.usedPercent == nil && state.warning == "Set the budget amount in Settings", "\(String(describing: amount))")
            #expect(state.freshnessDeadline == 150 && state.members.allSatisfy { $0.problem == nil })
        }
        let over = try #require(sbBudget(sbTracedRows(), sbConfig(amount: 400)))
        #expect(abs(try #require(over.usedPercent) - 112.75) < 1e-9 && over.warning == nil, "a percentage above 100 stays raw")
        let zero = try #require(sbBudget([sbRow("claude", spend: sbSummary(0)), sbRow("cursor", spend: sbSummary(0))]))
        #expect(zero.total == 0 && zero.usedPercent == 0 && zero.warning == nil, "zero spend is a known 0 %, not unknown")
    }
}
