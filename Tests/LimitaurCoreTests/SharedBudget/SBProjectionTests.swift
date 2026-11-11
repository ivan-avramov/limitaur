import Foundation
import Testing
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes (baseline has no combined bar), I = preserves an invariant,
// N = exercises new behaviour. Criteria C6 (projectDisplay), C8 (provider codes) and I4 (monitor day).

private func candidate(_ row: ProfileDisplay, percent: Double) -> PresentationCandidate {
    let metric = UsageMetric(id: "spend", label: "Monthly spend", usedPercent: percent)
    var snapshot = row.snapshot!
    snapshot.metrics = [metric]
    return PresentationCandidate(metric: RankedMetric(snapshot: snapshot, metric: metric), freshnessDeadline: 190, snapshotGeneration: 1)
}
/// Projects the traced rows with Claude and Cursor candidates at the given percentages, ordered as the monitor orders them.
private func project(_ budget: SharedBudgetState?, claude: Double = 15, cursor: Double = 0.82, count: Int = 3,
                     wall: Date = sbWall, mono: TimeInterval = sbMono, rows: [ProfileDisplay] = sbTracedRows(),
                     passBudget: Bool = true) -> PresentationState {
    let candidates = [candidate(rows[0], percent: claude), candidate(rows[1], percent: cursor)]
        .sorted { ($0.metric.metric.usedPercent ?? 0) > ($1.metric.metric.usedPercent ?? 0) }
    let display = MonitorDisplay(profiles: rows, candidates: candidates, revision: 1, nextDisplayDeadline: nil)
    var observations: [Int: SnapshotExpirations] = [:]
    return passBudget
        ? projectDisplay(display, count: count, wallNow: wall, monotonicNow: mono, observations: &observations, budget: budget)
        : projectDisplay(display, count: count, wallNow: wall, monotonicNow: mono, observations: &observations)
}
private func providers(_ state: PresentationState) -> [String] { state.selected.map(\.providerID.rawValue) }

@Suite struct SBProjectionTests {
    // N, C6: the budget candidate ranks between the members by percent, with the specified identity and fields.
    @Test func budgetRanksBetweenTheMembers() throws {
        let budget = try #require(sbBudget(sbTracedRows()))
        let state = project(budget)
        #expect(providers(state) == ["claude", "budget", "cursor"])
        let ranked = try #require(state.selected.first { $0.providerID == "budget" })
        #expect(ranked.accountID == "shared" && ranked.accountLabel == "Shared budget" && ranked.fetchedAt == sbWall)
        #expect(ranked.metric.id == "spend:shared" && ranked.metric.label == "Shared budget")
        #expect(ranked.metric.usedPercent == budget.usedPercent && ranked.metric.resetsAt == sbCycleEnd)
    }
    // N, C6: it can lead the ranking, and ties sort by provider id ("budget" first), then the members stay in their order.
    @Test func orderingAtTheTopAndOnTies() throws {
        let budget = try #require(sbBudget(sbTracedRows()))
        #expect(providers(project(budget, claude: 5, cursor: 1)) == ["budget", "claude", "cursor"])
        #expect(providers(project(budget, claude: 90, cursor: 95)) == ["cursor", "claude", "budget"])
        let tied = try #require(sbBudget([sbRow("claude", spend: sbSummary(400, limit: 1000)), sbRow("cursor", spend: sbSummary(100, limit: 1000))],
                                         sbConfig(amount: 1000)))
        #expect(tied.usedPercent == 50)
        #expect(providers(project(tied, claude: 50, cursor: 50)) == ["budget", "claude", "cursor"])
    }
    // N, C6: the count cuts the merged list.
    @Test func countLimitsTheMergedRanking() throws {
        let budget = try #require(sbBudget(sbTracedRows()))
        #expect(providers(project(budget, count: 2)) == ["claude", "budget"])
        #expect(providers(project(budget, count: 1)) == ["claude"])
        #expect(providers(project(budget, claude: 5, count: 1)) == ["budget"])
        #expect(providers(project(budget, count: 4)) == ["claude", "budget", "cursor"])
        #expect(project(budget, count: 4).accessibilitySummary.contains("unavailable slot"))
    }
    // N, C6: the candidate leaves the bars at its freshness deadline (the earlier member's, 150), not before.
    @Test func leavesAtTheFreshnessDeadline() throws {
        let budget = try #require(sbBudget(sbTracedRows()))
        #expect(budget.freshnessDeadline == 150)
        #expect(providers(project(budget, mono: 149.9)).contains("budget"))
        for mono in [150, 151] as [TimeInterval] { #expect(!providers(project(budget, mono: mono)).contains("budget"), "\(mono)") }
    }
    // N, C6: the candidate leaves the bars at resetsAt: exactly then it is gone, a second earlier it is shown.
    @Test func leavesAtTheReset() throws {
        let budget = try #require(sbBudget(sbTracedRows()))
        #expect(providers(project(budget, wall: sbCycleEnd.addingTimeInterval(-1))).contains("budget"))
        #expect(!providers(project(budget, wall: sbCycleEnd)).contains("budget"))
        #expect(!providers(project(budget, wall: sbCycleEnd.addingTimeInterval(60))).contains("budget"))
    }
    // R, C6: a total that cannot be shown (mismatched period, stale member, no amount) never joins the ranking.
    @Test func unknownTotalNeverRanks() throws {
        let mismatch = [sbRow("claude", spend: sbSummary(410)), sbRow("cursor", spend: sbSummary(41, end: sbUTC(2023, 12, 15)))]
        let states = [sbBudget(mismatch), sbBudget(sbTracedRows(), sbConfig(amount: nil)),
                      sbBudget([sbRow("claude", health: .stale, spend: sbSummary(410)), sbRow("cursor", spend: sbSummary(41))])]
        for state in states {
            let projected = project(state)
            #expect(providers(projected) == ["claude", "cursor"] && !projected.accessibilitySummary.contains("Shared budget"))
        }
    }
    // N, C6: the accessibility summary names the budget like any other candidate.
    @Test func accessibilitySummaryMentionsTheBudget() throws {
        let budget = try #require(sbBudget(sbTracedRows()))
        let summary = project(budget).accessibilitySummary
        #expect(summary.contains("Shared budget") && summary.contains("9.02 percent") && summary.contains("budget, Shared budget"))
        #expect(!project(budget, count: 1).accessibilitySummary.contains("Shared budget"), "cut by the count")
    }
    // I, C6: without a budget nothing changes, whether it is omitted or nil; the members' candidates are untouched.
    @Test func withoutABudgetNothingChanges() throws {
        let omitted = project(nil, passBudget: false), explicit = project(nil)
        #expect(providers(omitted) == ["claude", "cursor"] && omitted.selected == explicit.selected)
        #expect(omitted.accessibilitySummary == explicit.accessibilitySummary && !omitted.accessibilitySummary.contains("Shared budget"))
        let budget = try #require(sbBudget(sbTracedRows()))
        let with = project(budget)
        #expect(with.selected.filter { $0.providerID != "budget" } == omitted.selected)
        #expect(with.profiles.map(\.health) == omitted.profiles.map(\.health) && with.providerWarning == omitted.providerWarning)
        #expect(with.unavailableProviders == omitted.unavailableProviders && with.signInProviders == omitted.signInProviders)
    }
}

@Suite struct SBProviderCodeTests {
    // N, C8: the budget has its own code, SB, and every pair of codes is still distinguishable.
    @Test func budgetCodeIsSB() {
        #expect(providerCodes["budget"] == "SB" && providerGlyph(for: "budget") == "SB")
        let codes = providerCodes.sorted { $0.key < $1.key }
        for (i, a) in codes.enumerated() {
            for b in codes[(i + 1)...] {
                #expect(a.value != b.value && providerCodesAreDistinguishable(a.value, b.value), "\(a.key) \(a.value) vs \(b.key) \(b.value)")
            }
        }
        #expect(providerCodes["claude"] == "CL" && providerCodes["codex"] == "CX" && providerCodes["cursor"] == "CU", "existing codes are unchanged")
    }
}

// I4: the monitor stores a reset day per provider and decodes Claude with it from the next successful fetch.
@Suite struct SBMonitorTests {
    private static let claudeProfile = AccountProfile(id: "claude-default", providerID: "claude", label: "Default", source: .claudeDefaultDiscovery)
    private func makeMonitor(_ clock: CPClock) -> Monitor {
        let keychain = CPKeychain(cpFound(#"{"claudeAiOauth":{"accessToken":"invented-claude-token"}}"#))
        let transport = CPTransport { _, _ in cpOK(try! JSONSerialization.jsonObject(with: sbClaudeBody())) }
        return Monitor(clock: clock, credentials: CredentialStore(files: CPFiles(), keychain: keychain, cursorKeychain: CPKeychain(cpNotFound)),
                       transport: transport, recheckInterval: 30, reactiveRecheck: false, nudger: CPNudger())
    }
    private func periodEnd(_ monitor: Monitor) async -> Date? {
        await (monitor.display()).profiles.first { $0.profile.id == "claude-default" }?.snapshot?.spend?.periodEnd
    }
    // N, I4: a day set before the first fetch applies to it; the default is the 1st.
    @Test func dayAppliesToTheFetch() async {
        let defaulted = makeMonitor(CPClock())
        await defaulted.setProfiles([Self.claudeProfile]); #expect(await defaulted.settle())
        #expect(await periodEnd(defaulted) == sbUTC(2027, 2, 1))   // CPClock's wall time is 2027-01-15
        await defaulted.stop()
        let monitor = makeMonitor(CPClock())
        await monitor.setSpendResetDay(.day(20), for: "claude")
        await monitor.setProfiles([Self.claudeProfile]); #expect(await monitor.settle())
        #expect(await periodEnd(monitor) == sbUTC(2027, 1, 20))
        await monitor.stop()
    }
    // N, I4: a day for another provider does not change Claude's; a change leaves the cached snapshot until the next fetch.
    @Test func changeTakesEffectOnTheNextFetch() async {
        let clock = CPClock(), monitor = makeMonitor(clock)
        await monitor.setSpendResetDay(.day(20), for: "cursor")
        await monitor.setProfiles([Self.claudeProfile]); #expect(await monitor.settle())
        #expect(await periodEnd(monitor) == sbUTC(2027, 2, 1))
        await monitor.setSpendResetDay(.lastDay, for: "claude")
        #expect(await periodEnd(monitor) == sbUTC(2027, 2, 1), "cached snapshot is not re-applied")
        clock.move(mono: 120); await monitor.refresh()
        #expect(await cpEventually { await periodEnd(monitor) == sbUTC(2027, 1, 31) })
        await monitor.stop()
    }
}
