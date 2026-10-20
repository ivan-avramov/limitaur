import Foundation
import Testing
@testable import LimitaurCore

private final class BarsClock: MonitorClock, @unchecked Sendable {
    private let lock = NSLock()
    private var wall = Date(timeIntervalSince1970: 1_800_000_000)
    private var mono: TimeInterval = 100
    func wallNow() -> Date { lock.lock(); defer { lock.unlock() }; return wall }
    func monotonicNow() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return mono }
    func move(wall seconds: TimeInterval = 0, mono elapsed: TimeInterval = 0) {
        lock.lock(); wall.addTimeInterval(seconds); mono += elapsed; lock.unlock()
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func take() -> Bool { lock.lock(); defer { lock.unlock() }; if used { return false }; used = true; return true }
}

private struct BarsFiles: CredentialFileReading {
    func read(path: String) throws -> Data {
        Data(#"{"tokens":{"access_token":"invented","account_id":"selected"}}"#.utf8)
    }
}
private struct BarsKeychain: KeychainReading {
    func claudeCredential() -> KeychainResult { .denied }
}
private actor BarsTransport: HTTPTransport {
    private var replies: [HTTPResponse]
    private var calls = 0
    init(_ replies: [HTTPResponse]) { self.replies = replies }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        calls += 1
        guard !replies.isEmpty else { throw TransportFailure.network }
        return replies.removeFirst()
    }
    func count() -> Int { calls }
}
private actor PublicationRecorder {
    private var corrected = 0
    func record(_ value: MonitorDisplay) {
        if value.profiles.contains(where: { $0.snapshot != nil }) && value.selected.isEmpty {
            corrected += 1
        }
    }
    func count() -> Int { corrected }
}

@Test func compactRankingUsesProductionLimit() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshots = (0..<10).map { index in
        UsageSnapshot(providerID: index.isMultiple(of: 2) ? "codex" : "claude",
                      accountID: AccountID("a-\(index)"), accountLabel: "A", fetchedAt: now,
                      metrics: [UsageMetric(id: "m", label: "M", usedPercent: Double(index * 15))])
    }
    for count in [1, 3, 5, 8] {
        #expect(rankMetrics(snapshots, wallNow: now, maximumCount: count).count == count)
    }
    #expect(rankMetrics(snapshots, wallNow: now).count == 3)
    #expect(rankMetrics(snapshots, wallNow: now, maximumCount: -1).count == 3)
    #expect(rankMetrics(snapshots, wallNow: now, maximumCount: 9).count == 3)
    #expect(rankMetrics(snapshots, wallNow: now, maximumCount: 8).first?.metric.usedPercent == 135)
    #expect(indicatorCount(nil) == 3)
}

@Test func delayedPresentationExpiresAccountsOutsideEightAndKeepsSnapshotLatches() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let old = UsageSnapshot(providerID: "codex", accountID: "old", accountLabel: "Old", fetchedAt: now,
                            metrics: [UsageMetric(id: "reset", label: "Reset", usedPercent: 90,
                                                  resetsAt: now.addingTimeInterval(5))],
                            balances: [CreditBalance(label: "Balance", remaining: Decimal(4),
                                                     expiresAt: now.addingTimeInterval(5))],
                            resetCredits: ResetCreditSummary(availableCount: 2, applicableCount: nil,
                                                             details: [ResetCredit(id: "one", label: "One",
                                                                                   expiresAt: now.addingTimeInterval(5))]))
    let fresh = (0..<8).map { index in
        UsageSnapshot(providerID: "claude", accountID: AccountID("fresh-\(index)"), accountLabel: "Fresh",
                      fetchedAt: now, metrics: [UsageMetric(id: "m", label: "M", usedPercent: Double(100 + index))])
    }
    let rows = [ProfileDisplay(profile: AccountProfile(id: "old", providerID: "codex", label: "Old",
                                                       source: .codexFile("/invented")), snapshot: old,
                               health: .healthy, message: nil, fetchedAge: 0,
                               freshnessDeadline: 190, snapshotGeneration: 1)] +
        fresh.enumerated().map { index, snapshot in
            ProfileDisplay(profile: AccountProfile(id: "fresh-\(index)", providerID: "claude", label: "Fresh",
                                                   source: .claudeFile("/invented")), snapshot: snapshot,
                           health: .healthy, message: nil, fetchedAge: 0,
                           freshnessDeadline: 300, snapshotGeneration: index + 2)
        }
    let selected = rankMetrics([old] + fresh, wallNow: now, maximumCount: 8)
    let candidates = selected.map { metric in
        PresentationCandidate(metric: metric, freshnessDeadline: 300,
                              snapshotGeneration: Int(metric.accountID.rawValue.replacingOccurrences(of: "fresh-", with: ""))! + 2)
    }
    let delayed = MonitorDisplay(profiles: rows, candidates: candidates, revision: 1, nextDisplayDeadline: nil)
    var observations: [Int: SnapshotExpirations] = [:]
    let crossed = projectDisplay(delayed, count: 5, wallNow: now.addingTimeInterval(5),
                                 monotonicNow: 190, observations: &observations)
    #expect(crossed.selected.count == 5)
    #expect(crossed.profiles[0].health == .stale)
    #expect(crossed.profiles[0].expirations.metrics.contains("reset"))
    #expect(crossed.profiles[0].expirations.balances.contains(0))
    #expect(crossed.profiles[0].expirations.credits.contains(0))
    #expect(crossed.providerWarning)
    #expect(crossed.accessibilitySummary.contains("cached quota reset due"))
    let backwards = projectDisplay(delayed, count: 8, wallNow: now, monotonicNow: 190,
                                   observations: &observations)
    #expect(backwards.profiles[0].expirations.metrics.contains("reset"))
    #expect(backwards.profiles[0].expirations.balances.contains(0))
    #expect(backwards.profiles[0].expirations.credits.contains(0))
    let replacement = MonitorDisplay(profiles: [ProfileDisplay(profile: rows[0].profile, snapshot: old,
                                      health: .healthy, message: nil, fetchedAge: 0,
                                      freshnessDeadline: 290, snapshotGeneration: 20)],
                                     candidates: [PresentationCandidate(metric: RankedMetric(snapshot: old, metric: old.metrics[0]),
                                                                         freshnessDeadline: 290, snapshotGeneration: 20)],
                                     revision: 2, nextDisplayDeadline: nil)
    let renewed = projectDisplay(replacement, count: 1, wallNow: now, monotonicNow: 200,
                                 observations: &observations)
    #expect(renewed.selected.count == 1)
    #expect(observations[1] == nil)
}

@Test func presentationNamesEveryAffectedAccountWhenOtherProviderFillsBars() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let healthy = UsageSnapshot(providerID: "claude", accountID: "healthy", accountLabel: "Ready", fetchedAt: now,
                                metrics: (0..<5).map { index in
                                    UsageMetric(id: "metric-\(index)", label: "Metric \(index)",
                                                usedPercent: Double(90 - index))
                                })
    let good = ProfileDisplay(profile: AccountProfile(id: "good", providerID: "claude", label: "Ready",
                                                      source: .claudeFile("/invented")), snapshot: healthy,
                              health: .healthy, message: nil, fetchedAge: 0,
                              freshnessDeadline: 190, snapshotGeneration: 1)
    let failed = ProfileDisplay(profile: AccountProfile(id: "failed", providerID: "codex", label: "Work",
                                                        source: .codexFile("/invented")), snapshot: nil,
                                health: .failed, message: "Connection unavailable", fetchedAge: nil)
    let partial = ProfileDisplay(profile: AccountProfile(id: "partial", providerID: "claude", label: "Other",
                                                         source: .claudeFile("/invented")), snapshot: nil,
                                 health: .partial, message: "Incomplete provider data", fetchedAge: nil)
    let candidates = rankMetrics([healthy], wallNow: now, maximumCount: 8).map {
        PresentationCandidate(metric: $0, freshnessDeadline: 190, snapshotGeneration: 1)
    }
    let display = MonitorDisplay(profiles: [good, failed, partial], candidates: candidates,
                                 revision: 1, nextDisplayDeadline: 190)
    var observations: [Int: SnapshotExpirations] = [:]
    let projected = projectDisplay(display, count: 3, wallNow: now, monotonicNow: 100,
                                   observations: &observations)
    #expect(projected.selected.count == 3)
    #expect(projected.providerWarning)
    #expect(projected.accessibilitySummary.contains("codex, Work, failed"))
    #expect(projected.accessibilitySummary.contains("claude, Other, partial"))
    #expect(!projected.accessibilitySummary.contains("/invented"))
}

@Test func enabledMalformedSpendIsPartialAndAmountOnlyDoesNotInventUsage() throws {
    for source in [#"{"limits":[],"spend":{"enabled":true,"percent":"bad"}}"#,
                   #"{"limits":[],"extra_usage":{"is_enabled":true,"utilization":"bad"}}"#,
                   #"{"limits":[{"kind":"session","percent":25}],"spend":{"enabled":true,"used":{"amount_minor":12,"currency":"ZZZ","exponent":1}}}"#] {
        let snapshot = try UsageDecoder.decode(provider: "claude", data: Data(source.utf8))
        #expect(snapshot.partial)
        #expect(!snapshot.warnings.isEmpty)
        #expect(!snapshot.metrics.contains(where: { $0.usedPercent == 0 }))
    }
    let disabled = try UsageDecoder.decode(provider: "claude", data: Data(#"{"limits":[],"spend":{"enabled":false,"percent":"bad"}}"#.utf8))
    #expect(!disabled.partial)
}

@Test func crossedDeadlinePublishesWithoutAnotherEventOrFetch() async {
    let clock = BarsClock(), once = Once(), recorder = PublicationRecorder()
    let body = #"{"rate_limit":{"primary_window":{"used_percent":85,"reset_at":1800000005}}}"#
    let transport = BarsTransport([HTTPResponse(status: 200, headers: [:], body: Data(body.utf8))])
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: BarsFiles(), keychain: BarsKeychain()),
                          transport: transport, beforeDisplayArm: {
                              if once.take() { clock.move(wall: 5, mono: 5) }
                          })
    let stream = await monitor.changes()
    let observer = Task { for await value in stream { await recorder.record(value) } }
    await monitor.setProfiles([AccountProfile(id: "one", providerID: "codex", label: "One", source: .codexFile("/invented"))])
    #expect(await monitor.settle())
    var published = false
    for _ in 0..<500 {
        if await recorder.count() > 0 { published = true; break }
        try? await Task.sleep(for: .milliseconds(2))
    }
    #expect(published)
    #expect(await transport.count() == 1)
    #expect((await monitor.display()).nextDisplayDeadline == 190)
    observer.cancel(); await monitor.stop()
}

@Test func hugeRetryAfterKeepsThrottleAndShowsFixedUnavailableDate() async {
    let clock = BarsClock()
    let transport = BarsTransport([HTTPResponse(status: 429, headers: ["retry-after": "1e308"], body: Data())])
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: BarsFiles(), keychain: BarsKeychain()),
                          transport: transport)
    await monitor.setProfiles([AccountProfile(id: "one", providerID: "codex", label: "One", source: .codexFile("/invented"))])
    #expect(await monitor.settle())
    #expect((await monitor.display()).profiles.first?.message == "Retry time unavailable")
    #expect((await monitor.throttleDeadline(for: "one") ?? 0) > 1e307)
    clock.move(mono: 10_000)
    await monitor.manualRefresh()
    #expect(await transport.count() == 1)
    await monitor.stop()
}

@Test func monitorResetLatchSurvivesBackwardClockUntilReplacementFetch() async {
    let clock = BarsClock()
    let first = #"{"rate_limit":{"primary_window":{"used_percent":95,"reset_at":1800000005}}}"#
    let second = #"{"rate_limit":{"primary_window":{"used_percent":40,"reset_at":1800000100}}}"#
    let transport = BarsTransport([HTTPResponse(status: 200, headers: [:], body: Data(first.utf8)),
                                   HTTPResponse(status: 200, headers: [:], body: Data(second.utf8))])
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: BarsFiles(), keychain: BarsKeychain()),
                          transport: transport)
    await monitor.setProfiles([AccountProfile(id: "one", providerID: "codex", label: "One", source: .codexFile("/invented"))])
    #expect(await monitor.settle())
    #expect((await monitor.display()).selected.first?.metric.usedPercent == 95)
    clock.move(wall: 5)
    await monitor.clockChanged()
    #expect((await monitor.display()).selected.isEmpty)
    clock.move(wall: -5)
    await monitor.clockChanged()
    #expect((await monitor.display()).selected.isEmpty)
    clock.move(mono: 30)
    await monitor.refresh()
    #expect(await monitor.settle())
    #expect((await monitor.display()).selected.first?.metric.usedPercent == 40)
    #expect(await transport.count() == 2)
    await monitor.stop()
}

@Test func dueWindowDoesNotStaleOtherWindowsInAccount() async {
    let clock = BarsClock()
    let body = #"{"rate_limit":{"primary_window":{"used_percent":95,"reset_at":1800000005},"secondary_window":{"used_percent":45,"reset_at":1800000100}}}"#
    let transport = BarsTransport([HTTPResponse(status: 200, headers: [:], body: Data(body.utf8))])
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: BarsFiles(), keychain: BarsKeychain()),
                          transport: transport)
    await monitor.setProfiles([AccountProfile(id: "one", providerID: "codex", label: "One", source: .codexFile("/invented"))])
    #expect(await monitor.settle())
    clock.move(wall: 5)
    await monitor.clockChanged()
    let due = await monitor.display()
    #expect(due.selected.map(\.metric.usedPercent) == [45])
    #expect(due.profiles.first?.health == .healthy)
    #expect(due.profiles.first?.expirations.metrics.contains("default:primary") == true)
    clock.move(wall: -5)
    await monitor.clockChanged()
    #expect((await monitor.display()).selected.map(\.metric.usedPercent) == [45])
    #expect(await transport.count() == 1)
    await monitor.stop()
}

@Test func extremeResetCreditExpiryUsesBoundedProductionWait() async throws {
    let clock = BarsClock()
    let body = #"{"rateLimitResetCredits":{"availableCount":1,"applicableAvailableCount":1,"credits":[{"id":"synthetic","expiresAt":1e30}]}}"#
    let transport = BarsTransport([HTTPResponse(status: 200, headers: [:], body: Data(body.utf8))])
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: BarsFiles(), keychain: BarsKeychain()),
                          transport: transport)
    await monitor.setProfiles([AccountProfile(id: "one", providerID: "codex", label: "One", source: .codexFile("/invented"))])
    #expect(await monitor.settle())
    let initial = await monitor.display()
    #expect(initial.profiles.first?.snapshot?.resetCredits?.availableCount == 1)
    #expect(initial.profiles.first?.snapshot?.resetCredits?.details?.count == 1)
    #expect(initial.nextDisplayDeadline == 190)
    clock.move(wall: 91, mono: 91)
    await monitor.clockChanged() // Production armTick previously trapped here.
    let stale = await monitor.display()
    #expect(stale.profiles.first?.health == .stale)
    #expect(stale.profiles.first?.snapshot?.resetCredits?.availableCount == 1)
    let expiry = try #require(stale.profiles.first?.snapshot?.resetCredits?.details?.first?.expiresAt)
    #expect(expiry.timeIntervalSince1970 > 1e29)
    let deadline = try #require(stale.nextDisplayDeadline)
    #expect(deadline > 1e29)
    #expect(DisplayWaitPolicy.interval(deadline: deadline, now: clock.monotonicNow()) == DisplayWaitPolicy.maximumInterval)
    #expect(await transport.count() == 1)
    await monitor.stop()
}

@Test func displayWaitPolicyBoundsFiniteSubtractionOverflow() {
    let maximum = Double.greatestFiniteMagnitude
    #expect(DisplayWaitPolicy.interval(deadline: maximum, now: -maximum) == DisplayWaitPolicy.maximumInterval)
    #expect(DisplayWaitPolicy.interval(deadline: 100, now: 100) == nil)
    #expect(DisplayWaitPolicy.interval(deadline: 99, now: 100) == nil)
    #expect(DisplayWaitPolicy.interval(deadline: 101, now: 100) == 1)
    let farDate = Date(timeIntervalSince1970: 1e308)
    let farPast = Date(timeIntervalSince1970: -1e308)
    #expect(absoluteDisplayDeadline(farDate, wallNow: farPast, monotonicNow: 100) == maximum)
}
