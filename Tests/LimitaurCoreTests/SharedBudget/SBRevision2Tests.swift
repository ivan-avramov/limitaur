import Foundation
import Testing
@testable import LimitaurCore

// Revision 2 (H1-H3, H6, H7). Classes: R = reproduces a failure the revision fixes, I = preserves an invariant, N = new behaviour.

private func r2Row(_ provider: ProviderID, id: String? = nil, health: Health = .healthy, spend: SpendSummary?, fetchedAt: Date = sbWall,
                   deadline: TimeInterval? = 190, aliasOf: String? = nil, snapshot: Bool = true) -> ProfileDisplay {
    let id = id ?? provider.rawValue + "-default"
    let profile = AccountProfile(id: id, providerID: provider, label: "Default",
                                 source: provider == "cursor" ? .cursorDefaultDiscovery : .claudeDefaultDiscovery)
    let metric = UsageMetric(id: "spend", label: "Monthly spend", usedPercent: 10, resetsAt: sbCycleEnd)
    let snap = snapshot ? UsageSnapshot(providerID: provider, accountID: AccountID(id), accountLabel: "Default", fetchedAt: fetchedAt,
                                        metrics: [metric], spend: spend) : nil
    return ProfileDisplay(profile: profile, snapshot: snap, health: health, message: aliasOf == nil ? nil : "Alias of Work", fetchedAge: 0,
                          freshnessDeadline: deadline, snapshotGeneration: 1, aliasOf: aliasOf)
}
private func r2Candidate(_ row: ProfileDisplay, percent: Double, nominal: TimeInterval?) -> PresentationCandidate {
    let metric = UsageMetric(id: "spend", label: "Monthly spend", usedPercent: percent)
    var snapshot = row.snapshot!
    snapshot.metrics = [metric]
    return PresentationCandidate(metric: RankedMetric(snapshot: snapshot, metric: metric), freshnessDeadline: 190,
                                 snapshotGeneration: 1, nominalDeadline: nominal)
}
private func r2Project(_ rows: [ProfileDisplay], _ candidates: [PresentationCandidate], wall: Date, mono: TimeInterval,
                       config: SharedBudgetConfig = sbConfig()) -> (PresentationState, SharedBudgetState?) {
    let budget = sharedBudget(config, rows: rows, mainProfileIDs: sbMains, wallNow: wall, monotonicNow: mono)
    var observations: [Int: SnapshotExpirations] = [:]
    let display = MonitorDisplay(profiles: rows, candidates: candidates, revision: 1, nextDisplayDeadline: nil)
    return (projectDisplay(display, count: 3, wallNow: wall, monotonicNow: mono, observations: &observations, budget: budget), budget)
}

@Suite struct SBRevision2Tests {
    // H7 (amends healthLabels): a fresh throttled member counts; a throttled one at or past its deadline does not.
    @Test func throttledCountsOnlyWhileFresh() throws {
        let fresh = try #require(sbBudget([sbRow("claude", health: .throttled, spend: sbSummary(410)), sbRow("cursor", spend: sbSummary(41))]))
        #expect(fresh.total == 451 && fresh.members.map(\.problem) == [nil, nil] && fresh.members.first?.spent == 410)
        for mono in [150, 190, 250] as [TimeInterval] {
            let rows = [sbRow("claude", health: .throttled, spend: sbSummary(410), deadline: 150), sbRow("cursor", spend: sbSummary(41), deadline: 300)]
            let stale = try #require(sbBudget(rows, mono: mono))
            #expect(stale.members.first?.spent == nil && stale.members.first?.problem != nil && stale.total == nil && stale.usedPercent == nil, "\(mono)")
            #expect(stale.warning?.hasPrefix("Total unavailable: Claude") == true)
        }
        let none = [sbRow("claude", health: .throttled, spend: sbSummary(410), deadline: nil), sbRow("cursor", spend: sbSummary(41))]
        #expect(sbBudget(none)?.total == nil, "no deadline is not fresh")
    }

    // R, H1: projections over unchanged rows with advancing clocks give an equal `selected`; the candidate is dated by the
    // earliest member snapshot, not by the wall clock.
    @Test func candidateTimeIsStable() throws {
        let early = sbWall.addingTimeInterval(-3600), late = sbWall.addingTimeInterval(-60)
        let rows = [r2Row("claude", spend: sbSummary(410), fetchedAt: late), r2Row("cursor", spend: sbSummary(41), fetchedAt: early, deadline: 190)]
        let candidates = [r2Candidate(rows[0], percent: 15, nominal: 190), r2Candidate(rows[1], percent: 0.8, nominal: 190)]
        let first = r2Project(rows, candidates, wall: sbWall, mono: 100)
        let second = r2Project(rows, candidates, wall: sbWall.addingTimeInterval(30), mono: 130)
        let third = r2Project(rows, candidates, wall: sbWall.addingTimeInterval(80), mono: 180)
        #expect(first.0.selected.map(\.providerID.rawValue) == ["claude", "budget", "cursor"])
        #expect(first.0.selected == second.0.selected && second.0.selected == third.0.selected)
        let ranked = try #require(first.0.selected.first { $0.providerID == "budget" })
        #expect(ranked.fetchedAt == early)
    }
    // R, H1: the date follows the earliest of the members, whichever provider holds it.
    @Test func candidateTimeIsTheEarliestMember() throws {
        let early = sbWall.addingTimeInterval(-500), late = sbWall.addingTimeInterval(-5)
        let rows = [r2Row("claude", spend: sbSummary(410), fetchedAt: early), r2Row("cursor", spend: sbSummary(41), fetchedAt: late)]
        let state = r2Project(rows, [], wall: sbWall, mono: 100).0
        #expect(state.selected.first { $0.providerID == "budget" }?.fetchedAt == early)
    }

    // R, H2: a member whose main row is an alias (no snapshot of its own) uses its owner's row.
    @Test func aliasMainUsesTheOwnersRow() throws {
        let alias = r2Row("claude", id: "claude-default", spend: nil, aliasOf: "claude-work", snapshot: false)
        let owner = r2Row("claude", id: "claude-work", spend: sbSummary(410))
        let cursor = r2Row("cursor", spend: sbSummary(41))
        for rows in [[alias, owner, cursor], [owner, alias, cursor]] {
            let state = try #require(sbBudget(rows))
            #expect(state.members.map(\.spent) == [410, 41] && state.total == 451 && state.warning == nil)
        }
    }
    // R, H2: the owner's health, freshness and spend decide; the alias row's own fields do not.
    @Test func aliasFollowsTheOwnersHealthAndFreshness() throws {
        let alias = r2Row("claude", id: "claude-default", health: .healthy, spend: nil, deadline: 190, aliasOf: "claude-work", snapshot: false)
        let cursor = r2Row("cursor", spend: sbSummary(41))
        let stale = try #require(sbBudget([alias, r2Row("claude", id: "claude-work", health: .stale, spend: sbSummary(410)), cursor]))
        #expect(stale.members.first?.spent == nil && stale.members.first?.problem == "Stale" && stale.total == nil)
        let expired = try #require(sbBudget([alias, r2Row("claude", id: "claude-work", spend: sbSummary(410), deadline: 120), cursor], mono: 130))
        #expect(expired.members.first?.spent == nil && expired.total == nil)
        let noSpend = try #require(sbBudget([alias, r2Row("claude", id: "claude-work", spend: nil), cursor]))
        #expect(noSpend.members.first?.problem == "No spend reported")
        let mismatch = try #require(sbBudget([alias, r2Row("claude", id: "claude-work", spend: sbSummary(410, end: sbUTC(2023, 12, 15))), cursor]))
        #expect(mismatch.members.first?.problem == "Different billing period")
    }
    // I, H2: a main row that is not an alias is read as before, and the owner's other rows stay ignored.
    @Test func nonAliasMainIsUnchanged() throws {
        let other = r2Row("claude", id: "claude-work", spend: sbSummary(999))
        #expect(sbBudget([other] + sbTracedRows())?.total == 451)
    }

    // R, H3: sharedBudget ignores duplicate members, so nothing is counted twice.
    @Test func duplicateMembersCountOnce() throws {
        let state = try #require(sbBudget(sbTracedRows(), sbConfig(members: ["claude", "cursor", "claude", "cursor", "claude"])))
        #expect(state.total == 451 && state.members.filter { $0.provider == "claude" }.count == 1)
        #expect(state.members.map(\.provider) == ["claude", "cursor"])
        let single = try #require(sbBudget(sbTracedRows(), sbConfig(amount: 1000, members: ["claude", "claude"])))
        #expect(single.total == 410)
    }

    // R, H6: the budget candidate is as fresh as its members' candidates: its nominal deadline is the minimum of theirs.
    @Test func nominalDeadlineIsTheMemberMinimum() throws {
        let rows = sbTracedRows()
        let candidates = [r2Candidate(rows[0], percent: 15, nominal: 170), r2Candidate(rows[1], percent: 0.8, nominal: 120)]
        func label(mono: TimeInterval) throws -> String {
            let summary = r2Project(rows, candidates, wall: sbWall, mono: mono).0.accessibilitySummary
            return try #require(summary.components(separatedBy: "; ").first { $0.hasPrefix("budget, Shared budget") })
        }
        #expect(try label(mono: 100).hasSuffix(", fresh"))
        #expect(try label(mono: 119.9).hasSuffix(", fresh"))
        #expect(try label(mono: 120).hasSuffix(", cached"), "the Cursor candidate's nominal deadline has passed")
        #expect(try label(mono: 125).hasSuffix(", cached"))
        let claude = r2Project(rows, candidates, wall: sbWall, mono: 125).0.accessibilitySummary
        #expect(claude.components(separatedBy: "; ").first { $0.hasPrefix("claude,") }?.hasSuffix(", fresh") == true)
    }
    // R, H6: with no matching member candidate, the nominal deadline is the budget's freshness deadline.
    @Test func nominalDeadlineFallsBackToTheFreshnessDeadline() throws {
        let rows = sbTracedRows()   // freshness deadline 150
        let other = r2Row("claude", id: "claude-other", spend: sbSummary(1))
        let unrelated = [r2Candidate(other, percent: 1, nominal: 105)]
        for candidates in [[], unrelated] {
            let at = { (mono: TimeInterval) -> String in
                r2Project(rows, candidates, wall: sbWall, mono: mono).0.accessibilitySummary
                    .components(separatedBy: "; ").first { $0.hasPrefix("budget, Shared budget") } ?? ""
            }
            #expect(at(149.9).hasSuffix(", fresh") && at(100).hasSuffix(", fresh"))
        }
    }
}
