import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes, I = preserves an invariant, N = exercises new behaviour.
// Criterion C7 (SettingsModel rules, I8).

/// Records the two new callbacks; the profile list is the Claude, Codex and Cursor mains.
@MainActor final class SBSettingsProbe {
    var days: [MonthlyResetDay] = [], budgets: [SharedBudgetConfig] = [], lists = 0
    func model(editable: Bool = true) -> SettingsModel {
        SettingsModel(profiles: [rdClaudeDefault, rdCodexDefault, rdProfile("cursor-default", "cursor", "Default", .cursorDefaultDiscovery)],
                      indicatorCount: 3, nudgeEnabled: true, editable: editable,
                      onProfiles: { _ in self.lists += 1 }, onIndicatorCount: { _ in }, onNudge: { _ in }, onConnect: { _ in }, onAbout: {},
                      onClaudeResetDay: { self.days.append($0) }, onBudget: { self.budgets.append($0) })
    }
}
/// A main-account row reporting a spend limit (and currency); `id` defaults to the provider's main account.
func sbuRow(_ provider: ProviderID, limit: Decimal?, currency: String = "USD", id: String? = nil) -> ProfileDisplay {
    let id = id ?? provider.rawValue + "-default"
    let profile = AccountProfile(id: id, providerID: provider, label: "Default",
                                 source: provider == "cursor" ? .cursorDefaultDiscovery : .claudeDefaultDiscovery)
    let spend = SpendSummary(spent: 41, limit: limit, currency: currency, periodEnd: nil)
    return ProfileDisplay(profile: profile, snapshot: UsageSnapshot(providerID: provider, accountID: AccountID(id), accountLabel: "Default",
                                                                    fetchedAt: Date(timeIntervalSince1970: 1_700_000_000), metrics: [], spend: spend),
                          health: .healthy, message: nil, fetchedAge: 0)
}

@Suite @MainActor struct SBSettingsModelTests {
    // N: defaults are the 1st and a disabled USD budget over Claude and Cursor with no amount.
    @Test func defaults() {
        let probe = SBSettingsProbe(), model = probe.model()
        #expect(model.claudeResetDay == .default)
        #expect(model.budget == SharedBudgetConfig(enabled: false, amount: nil, currency: "USD", members: ["claude", "cursor"], resetDay: .default))
        #expect(probe.days.isEmpty && probe.budgets.isEmpty)
    }
    // N: the Claude reset day changes once per change, and a repeated value is not a change.
    @Test func claudeResetDayCallsBackOncePerChange() {
        let probe = SBSettingsProbe(), model = probe.model()
        model.setClaudeResetDay(.day(15)); model.setClaudeResetDay(.day(15))
        #expect(model.claudeResetDay == .day(15) && probe.days == [.day(15)])
        model.setClaudeResetDay(.lastDay)
        #expect(model.claudeResetDay == .lastDay && probe.days == [.day(15), .lastDay] && probe.budgets.isEmpty)
        #expect(model.budget.resetDay == .default, "the budget's own day is separate")
    }
    // N: the budget's own reset day changes the budget only, once per change.
    @Test func budgetResetDay() {
        let probe = SBSettingsProbe(), model = probe.model()
        model.setBudgetResetDay(.day(28)); model.setBudgetResetDay(.day(28))
        #expect(model.budget.resetDay == .day(28) && probe.budgets.map(\.resetDay) == [.day(28)])
        #expect(model.claudeResetDay == .default && probe.days.isEmpty)
    }
    // N: turning the budget on and off reports the whole config once each; a repeat is not a change.
    @Test func enableToggleReportsTheConfig() {
        let probe = SBSettingsProbe(), model = probe.model()
        model.setBudgetEnabled(true); model.setBudgetEnabled(true)
        #expect(model.budget.enabled && probe.budgets == [model.budget])
        model.setBudgetEnabled(false)
        #expect(!model.budget.enabled && probe.budgets.count == 2 && probe.budgets.last == model.budget)
    }
    // N: only Claude and Cursor can be members; each change calls back once; the others are ignored.
    @Test func membership() {
        let probe = SBSettingsProbe(), model = probe.model()
        model.setBudgetMember("claude", false)
        #expect(model.budget.members == ["cursor"] && probe.budgets.count == 1)
        model.setBudgetMember("claude", false); model.setBudgetMember("codex", true); model.setBudgetMember("other", true)
        #expect(model.budget.members == ["cursor"] && probe.budgets.count == 1)
        model.setBudgetMember("claude", true)
        #expect(Set(model.budget.members) == ["claude", "cursor"] && model.budget.members.count == 2 && probe.budgets.count == 2)
        model.setBudgetMember("cursor", false); model.setBudgetMember("claude", false)
        #expect(model.budget.members.isEmpty && probe.budgets.count == 4)
    }
    // N: pre-fill takes the shared limit when every member's main account reports the same limit and currency.
    @Test func prefillWhenLimitsMatch() {
        let probe = SBSettingsProbe(), model = probe.model()
        model.updateReportedLimits([sbuRow("claude", limit: 5000), sbuRow("cursor", limit: 5000)])
        model.setBudgetEnabled(true)
        #expect(model.budget.amount == 5000 && model.budget.enabled)
        #expect(probe.budgets == [model.budget], "enabling and pre-filling are one change")
    }
    // N: no pre-fill when the limits, the currencies or the reports differ or are missing.
    @Test func noPrefillWhenLimitsDiffer() {
        let cases: [[ProfileDisplay]] = [
            [sbuRow("claude", limit: 5000), sbuRow("cursor", limit: 4000)],
            [sbuRow("claude", limit: 5000), sbuRow("cursor", limit: 5000, currency: "EUR")],
            [sbuRow("claude", limit: 5000), sbuRow("cursor", limit: nil)],
            [sbuRow("claude", limit: 5000)],
            []]
        for rows in cases {
            let model = SBSettingsProbe().model()
            model.updateReportedLimits(rows); model.setBudgetEnabled(true)
            #expect(model.budget.amount == nil && model.budget.enabled)
        }
    }
    // N: a member that is switched off no longer has to agree, and only main accounts' limits are used.
    @Test func prefillUsesMembersAndMainAccountsOnly() {
        let model = SBSettingsProbe().model()
        model.setBudgetMember("cursor", false)
        model.updateReportedLimits([sbuRow("claude", limit: 5000), sbuRow("cursor", limit: 1), sbuRow("claude", limit: 9, id: "claude-work")])
        model.setBudgetEnabled(true)
        #expect(model.budget.amount == 5000)
        let other = SBSettingsProbe().model()
        other.updateReportedLimits([sbuRow("claude", limit: 5000), sbuRow("cursor", limit: 5000), sbuRow("cursor", limit: 3, id: "cursor-other")])
        other.setBudgetEnabled(true)
        #expect(other.budget.amount == 5000)
    }
    // I: an amount the user already set is never replaced by a pre-fill.
    @Test func prefillKeepsAnExistingAmount() {
        let model = SBSettingsProbe().model()
        #expect(model.setBudgetAmount("1200"))
        model.updateReportedLimits([sbuRow("claude", limit: 5000), sbuRow("cursor", limit: 5000)])
        model.setBudgetEnabled(true); model.setBudgetEnabled(false); model.setBudgetEnabled(true)
        #expect(model.budget.amount == 1200)
    }
    // N: later reports update what pre-fill sees.
    @Test func reportedLimitsAreRemembered() {
        let model = SBSettingsProbe().model()
        model.updateReportedLimits([sbuRow("claude", limit: 4000), sbuRow("cursor", limit: 5000)])
        model.updateReportedLimits([sbuRow("claude", limit: 5000), sbuRow("cursor", limit: 5000)])
        model.setBudgetEnabled(true)
        #expect(model.budget.amount == 5000)
    }
    // N: amounts parse with the current locale as positive decimals, including the currency text the field displays.
    @Test func amountParsing() {
        let probe = SBSettingsProbe(), model = probe.model()
        let plain = NumberFormatter(); plain.numberStyle = .decimal; plain.locale = .current
        let text = plain.string(from: 1234.5)!
        #expect(model.setBudgetAmount(text) && model.budget.amount == Decimal(string: "1234.5"))
        #expect(model.setBudgetAmount(amountText(Decimal(string: "5000.25")!, currency: "USD")) && model.budget.amount == Decimal(string: "5000.25"))
        #expect(model.setBudgetAmount("750") && model.budget.amount == 750)
        let expected: [Decimal?] = [Decimal(string: "1234.5"), Decimal(string: "5000.25"), Decimal(750)]
        #expect(probe.budgets.map(\.amount) == expected)
    }
    // N: a non-positive or unparsable amount is refused with no change and no callback.
    @Test func amountRefusals() {
        let probe = SBSettingsProbe(), model = probe.model()
        #expect(model.setBudgetAmount("5000"))
        let before = model.budget, count = probe.budgets.count
        for text in ["", "  ", "0", "0.00", "-5", "abc", "12abc", "NaN", "∞", "--1"] {
            #expect(!model.setBudgetAmount(text), "\(text)")
            #expect(model.budget == before && probe.budgets.count == count, "\(text)")
        }
    }
    // I: these are local display settings: a read-only (demo) model still applies them and reports each change.
    @Test func applyWhateverEditableSays() {
        let probe = SBSettingsProbe(), model = probe.model(editable: false)
        model.setClaudeResetDay(.day(9)); model.setBudgetEnabled(true); model.setBudgetResetDay(.lastDay)
        model.setBudgetMember("cursor", false)
        #expect(model.setBudgetAmount("100"))
        #expect(!model.editable && model.claudeResetDay == .day(9) && model.budget.enabled && model.budget.resetDay == .lastDay)
        #expect(model.budget.members == ["claude"] && model.budget.amount == 100)
        #expect(probe.days == [.day(9)] && probe.budgets.count == 4 && probe.lists == 0)
    }
}
