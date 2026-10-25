import Foundation
import Testing
@testable import LimitaurCore

private func umRow(_ provider: ProviderID, _ health: Health, _ id: String = "row", deadline: Double = 200) -> ProfileDisplay {
    ProfileDisplay(profile: AccountProfile(id: id, providerID: provider, label: id, source: .codexFile("/synthetic/\(id)")),
                   snapshot: deadline == 100 ? UsageSnapshot(providerID: provider, accountID: "a", accountLabel: id,
                       fetchedAt: Date(timeIntervalSince1970: 1_800_000_000), metrics: []) : nil,
                   health: health, message: nil, fetchedAge: nil, freshnessDeadline: deadline)
}
private func umProject(_ rows: [ProfileDisplay], count: Int = 8) -> PresentationState {
    var observations: [Int: SnapshotExpirations] = [:]
    return projectDisplay(MonitorDisplay(profiles: rows, candidates: [], revision: 7, nextDisplayDeadline: nil),
                          count: count, wallNow: Date(timeIntervalSince1970: 1_800_000_000), monotonicNow: 100, observations: &observations)
}
@Test(arguments: [Health.throttled, .failed, .unavailable, .partial, .stale])
func UnhealthyMarkerOtherCauses(health: Health) {
    // A healthy row reaches its freshness deadline exactly now: test projection, not a pre-labelled stale row.
    let result = umProject([umRow("codex", health == .stale ? .healthy : health, deadline: health == .stale ? 100 : 200)])
    #expect(result.profiles[0].health == health)
    #expect(result.unavailableProviders == ["codex"] && result.signInProviders.isEmpty)
    #expect(result.providerWarning && result.accessibilitySummary.hasSuffix("codex, row, \(health.rawValue)"))
}
@Test func UnhealthyMarkerDeduplicatesProfilesInUnhealthyRowOrder() {
    let rows = [umRow("codex", .healthy, "a"), umRow("gemini", .failed, "b"), umRow("claude", .unauthenticated, "c"),
                umRow("claude", .healthy, "d"), umRow("claude", .unauthenticated, "e"), umRow("codex", .unavailable, "f"), umRow("gemini", .unauthenticated, "g")]
    for count in [1, 8] {
        let result = umProject(rows, count: count)
        #expect(result.unavailableProviders == ["gemini", "claude", "codex"])
        #expect(result.signInProviders == Set<ProviderID>(["claude", "gemini"]))
        #expect(result.profiles.map(\.profile.id) == rows.map(\.profile.id) && result.count == count && result.revision == 7)
    }
}
@Test func UnhealthyMarkerAllHealthy() {
    let result = umProject([umRow("claude", .healthy, "a"), umRow("claude", .healthy, "b"), umRow("codex", .healthy, "c")], count: 1)
    #expect(result.unavailableProviders.isEmpty && result.signInProviders.isEmpty && !result.providerWarning)
    #expect(result.accessibilitySummary == "unavailable slot")
}
