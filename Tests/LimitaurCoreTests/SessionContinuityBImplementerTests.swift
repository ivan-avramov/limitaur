import Foundation
import Testing
@testable import LimitaurCore

// Part B implementer tests (B4-B7). Synthetic tokens only; the files-only credential sources never reach a Keychain.
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func day(_ d: Double) -> Date { t0.addingTimeInterval(d * 86_400) }
private func encoded(_ p: PollingPolicy) -> Data { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return try! e.encode(p) }
private func json(_ p: PollingPolicy) -> String { String(decoding: encoded(p), as: UTF8.self) }
private func at(_ interval: Int) -> PollingPolicy { PollingPolicy.decode(Data(#"{"interval":\#(interval),"blockedUntil":{}}"#.utf8), now: t0) }
/// A policy whose last change is old enough to probe, with a zero streak.
private func aged() -> PollingPolicy { var p = PollingPolicy(); _ = p.recordClean(now: t0, reductionAllowed: true); p.recordOther(); return p }
@discardableResult private func cleans(_ p: inout PollingPolicy, _ n: Int, at when: Date, allowed: Bool = true) -> Bool {
    var last = false; for _ in 0..<n { last = p.recordClean(now: when, reductionAllowed: allowed) }; return last
}

@Test func policyTable() {
    for (retry, expected) in [(nil, 60.0), (95, 100), (400, 120)] as [(Double?, Double)] {
        var p = PollingPolicy(); #expect(p.recordThrottle(now: t0, retryAfter: retry) && p.interval == expected)
    }
    var p = aged()
    #expect(!cleans(&p, 5, at: t0 + 3_600) && p.interval == 50)
    p = aged(); #expect(!cleans(&p, 4, at: day(1)) && p.interval == 50)
    #expect(cleans(&p, 1, at: day(1)) && p.interval == 40)
    var held = aged(); cleans(&held, 5, at: day(1), allowed: false)
    #expect(held.interval == 50 && held.consecutiveClean == 5 && cleans(&held, 1, at: day(1)) && held.interval == 40)
    for (minutes, retry, expected, blocked) in [(30.0, nil, 50.0, true), (30, 95, 100, true), (90, nil, 50, false)] as [(Double, Double?, Double, Bool)] {
        var q = aged(); cleans(&q, 5, at: day(1))
        _ = q.recordThrottle(now: day(1).addingTimeInterval(minutes * 60), retryAfter: retry)
        #expect(q.interval == expected && (q.blockedUntil[40] != nil) == blocked)
    }
    var b = aged(); cleans(&b, 5, at: day(1)); _ = b.recordThrottle(now: day(1).addingTimeInterval(1_800), retryAfter: nil)
    #expect(!cleans(&b, 5, at: day(3)) && b.interval == 50)
    #expect(cleans(&b, 1, at: day(9)) && b.interval == 40 && b.blockedUntil.isEmpty)
    var o = aged(); cleans(&o, 4, at: day(1)); o.recordOther()
    #expect(!cleans(&o, 1, at: day(1)))
    var many = aged(); cleans(&many, 5, at: day(1), allowed: false); let before = encoded(many)
    cleans(&many, 20, at: day(1), allowed: false)
    #expect(many.consecutiveClean == 5 && encoded(many) == before)
    var back = aged(); back.recordOther(); _ = back.recordClean(now: t0.addingTimeInterval(-3_600), reductionAllowed: true)
    #expect(back.consecutiveClean == 0 && back.lastChange == t0.addingTimeInterval(-3_600))
}

@Test func policyDecode() {
    let ref = t0.timeIntervalSinceReferenceDate
    for bad in [#"{"interval":47,"blockedUntil":{}}"#, #"{"interval":1e308,"blockedUntil":{}}"#, #"{"interval":-10,"blockedUntil":{}}"#,
                #"{"interval":50,"lastReduction":{"from":50,"to":30,"at":0},"blockedUntil":{}}"#, #"{"interval":50,"blockedUntil":{"25":\#(ref + 60)}}"#, "nope"] {
        #expect(PollingPolicy.decode(Data(bad.utf8), now: t0) == PollingPolicy())
    }
    let far = PollingPolicy.decode(Data(#"{"interval":60,"lastChange":\#(ref + 172_800),"blockedUntil":{"40":\#(ref + 8 * 86_400)}}"#.utf8), now: t0)
    #expect(far.interval == 60 && far.lastChange == t0 && far.blockedUntil[40] == day(7))
    var reduced = aged(); cleans(&reduced, 5, at: day(1))
    var reverted = reduced; _ = reverted.recordThrottle(now: day(1).addingTimeInterval(60), retryAfter: nil)
    for p in [reduced, reverted] { #expect(PollingPolicy.decode(encoded(p), now: day(2)) == p) }
}

// MARK: monitor rig
private struct NoKeychain: KeychainReading { func claudeCredential() -> KeychainResult { .notFound } }
private let path = "/b/a"
/// Polls the asserted state with yields until it holds or five seconds pass; unlike the fixed `scFlush()` sleep it does not depend on load.
private func bWait(_ predicate: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if await predicate() { return true }
        for _ in 0..<5 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return await predicate()
}
private struct Rig {
    let clock = SCClock(), files = SCFiles(), transport: SCTransport, monitor: Monitor
    init(_ replies: [HTTPResponse] = [], policy: PollingPolicy? = PollingPolicy(), reactive: Bool = false, deferred: Bool = false, paths: [String] = [path]) async {
        transport = SCTransport(replies, deferred: deferred)
        for (i, p) in paths.enumerated() { files.set(p, scClaude(i + 1)) }
        monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: NoKeychain()), transport: transport, reactiveRecheck: reactive)
        if let policy { await monitor.setPolling(["claude": policy]) }
        await monitor.setProfiles(paths.enumerated().map { scProfile("p\($0.offset)", source: .claudeFile($0.element)) })
        let expected = paths.count
        _ = await bWait { [transport] in await transport.count() >= expected }
        let initial = (0..<expected).map { $0 < replies.count ? replies[$0].status : (deferred ? 0 : 200) }
        if initial.allSatisfy({ $0 == 200 }) {
            for i in 0..<expected { _ = await bWait { [monitor] in await scRow(monitor, "p\(i)")?.snapshot != nil } }
        }
        await scFlush()
    }
    /// Without `until` the settling is the fixed flush (right for asserting that nothing changed); with it, the asserted state is awaited.
    func step(_ seconds: TimeInterval, _ driver: RefreshDriver = .cycle, until: (() async -> Bool)? = nil) async {
        clock.advance(seconds); await monitor.refresh(driver: driver)
        if let until { _ = await bWait(until) } else { await scFlush() }
    }
    func manual(until: () async -> Bool) async { await monitor.manualRefresh(); _ = await bWait(until) }
    func policy() async -> PollingPolicy? { await monitor.display().polling["claude"] }
    func row() async -> ProfileDisplay? { await scRow(monitor, "p0") }
}

@Test func cycleGate() async {
    for (interval, edge) in [(50, 48.5), (120, 118.5), (30, 28.5)] as [(Int, Double)] {
        let rig = await Rig(policy: at(interval))
        await rig.step(edge - 0.5); #expect(await rig.transport.count() == 1)
        await rig.step(0.5, until: { await rig.transport.count() >= 2 }); #expect(await rig.transport.count() == 2)
        await rig.step(edge - 0.5); #expect(await rig.transport.count() == 2)
        await rig.manual { await rig.transport.count() >= 3 }; #expect(await rig.transport.count() == 3)
        await rig.monitor.stop()
    }
    let plain = await Rig(policy: nil)
    await plain.step(29.5); #expect(await plain.transport.count() == 1)
    await plain.step(0.5, until: { await plain.transport.count() >= 2 }); #expect(await plain.transport.count() == 2)
    #expect(await plain.policy() == nil)
    let rig = await Rig([scResponse(), scResponse(429, retry: "200")])
    await rig.step(48.5); await rig.step(60); await rig.step(60)
    #expect(await rig.transport.count() == 2)
    await rig.monitor.setPolling(["claude": at(30), "codex": at(30)])
    let table = await rig.monitor.display().polling
    #expect(table["claude"]?.interval == 120 && table["codex"]?.interval == 30)
}

@Test func cleanPollsAndResets() async {
    let rig = await Rig([scResponse(), scResponse(), scResponse(), scResponse(), HTTPResponse(status: 200, headers: [:], body: Data("x".utf8))], reactive: true)
    #expect(await rig.policy()?.consecutiveClean == 0)
    await rig.step(48.5, until: { await rig.policy()?.consecutiveClean == 1 }); #expect(await rig.policy()?.consecutiveClean == 1)
    await rig.monitor.manualRefresh(); await scFlush(); #expect(await rig.policy()?.consecutiveClean == 1)
    await rig.step(50, until: { await rig.policy()?.consecutiveClean == 2 }); #expect(await rig.policy()?.consecutiveClean == 2)
    await rig.step(50, .manual, until: { await rig.policy()?.consecutiveClean == 0 }); #expect(await rig.policy()?.consecutiveClean == 0)
    let under = await Rig([scResponse(), scResponse(401)], reactive: true)
    await under.step(48.5); #expect(await under.policy()?.consecutiveClean == 0)
}

@Test func throttleClassification() async {
    let same = await Rig([scResponse(), scResponse(429, retry: "95")], reactive: true)
    await same.step(48.5); #expect(await same.policy()?.interval == 50)
    await same.step(30, until: { await same.policy()?.interval == 100 }); #expect(await same.policy()?.interval == 100)
    let rotated = await Rig([scResponse(), scResponse(429, retry: "95")], reactive: true)
    // settle(): the 429 and the re-read must land before the fake clock moves on (R-M3).
    await rotated.step(48.5); _ = await rotated.monitor.settle(); rotated.files.set(path, scClaude(2))
    await rotated.step(30); _ = await rotated.monitor.settle(); await rotated.step(61); _ = await rotated.monitor.settle()
    #expect(await rotated.policy()?.interval == 50)
    let timed = await Rig([scResponse(), scResponse(429)], reactive: true)
    await timed.step(48.5); #expect(await timed.policy()?.interval == 50)
    await timed.step(61, until: { await timed.policy()?.interval == 60 }); #expect(await timed.policy()?.interval == 60)
    let second = await Rig([scResponse(), scResponse(429), scResponse(429)], reactive: true)
    second.clock.advance(20); await second.monitor.manualRefresh(); await scFlush(); #expect(await second.policy()?.interval == 50)
    await second.step(31, .internal, until: { await second.policy()?.interval == 60 }); #expect(await second.policy()?.interval == 60)
    let direct = await Rig([scResponse(), scResponse(429, retry: "95")])
    await direct.step(48.5, until: { await direct.policy()?.interval == 100 }); #expect(await direct.policy()?.interval == 100)
}

@Test func pendingThrottleHoldsReduction() async {
    // Last change two days before the rig's wall clock: without the hold the fifth clean poll would reduce to 40.
    let old = PollingPolicy.decode(Data(#"{"interval":50,"lastChange":\#(t0.timeIntervalSinceReferenceDate - 172_800),"blockedUntil":{}}"#.utf8), now: t0)
    let rig = await Rig(Array(repeating: scResponse(), count: 6), policy: old, reactive: true, deferred: true, paths: [path, "/b/b"])
    for round in 1...2 {
        rig.clock.advance(50); await rig.monitor.refresh(driver: .cycle)
        #expect(await bWait { await rig.policy()?.consecutiveClean == round * 2 })
    }
    rig.clock.advance(50); await rig.monitor.refresh(driver: .cycle)
    #expect(await bWait { await rig.transport.count() == 8 })
    await rig.transport.answer(7, scResponse(429))
    let throttled = await bWait { await rig.monitor.display().profiles.contains { $0.health == .throttled } }
    #expect(throttled)
    await rig.transport.answer(6, scResponse())
    #expect(await bWait { await rig.policy()?.consecutiveClean == 5 })
    let held = await rig.policy()
    #expect(held?.consecutiveClean == 5 && held?.interval == 50)
    await rig.transport.finish(); await rig.monitor.stop()
}

private func span(_ r: ProfileDisplay?) -> TimeInterval? {
    guard let deadline = r?.freshnessDeadline, let fetched = r?.fetchedInstant else { return nil }
    return deadline - fetched
}
@Test func horizonAndRetention() async {
    let rig = await Rig([scResponse(), scResponse(429)], policy: at(100), reactive: true)
    #expect(await span(rig.row()) == 120)
    await rig.step(98.5); await rig.step(30, until: { await rig.policy()?.interval == 110 })
    let (interval, kept) = (await rig.policy()?.interval, await span(rig.row()))
    #expect(interval == 110 && kept == 120)
    let held = await Rig([scResponse(), scResponse(429, retry: "5")], policy: at(110))
    await held.step(108.5, until: { await span(held.row()) == 230.5 })
    #expect(await span(held.row()) == 230.5)
}

// MARK: app seams (B7)
private final class Store: PollingStorage, @unchecked Sendable {
    var values: [String: Data] = [:], writes = 0
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value as? Data; writes += 1 }
}

@Test func persistenceWritesOnlyChanges() {
    let store = Store(), persistence = PollingPersistence(store)
    var loaded = persistence.load(["claude", "codex"], now: t0)
    #expect(loaded["claude"] == PollingPolicy() && store.writes == 0)
    persistence.save(loaded); #expect(store.writes == 2)
    persistence.save(loaded); #expect(store.writes == 2)
    _ = loaded["claude"]?.recordThrottle(now: t0, retryAfter: nil)
    persistence.save(loaded); #expect(store.writes == 3)
    _ = loaded["claude"]?.recordClean(now: t0, reductionAllowed: true); persistence.save(loaded)
    let afterClean = store.writes
    for _ in 0..<20 { _ = loaded["claude"]?.recordClean(now: t0 + 60, reductionAllowed: true) }
    persistence.save(loaded); #expect(store.writes == afterClean)
    let reopened = PollingPersistence(store).load(["claude"], now: t0 + 60)
    #expect(reopened["claude"]?.interval == 60)
    let again = PollingPersistence(store); _ = again.load(["claude"], now: t0 + 60); again.save(reopened); #expect(store.writes == afterClean)
    store.values["polling.claude"] = Data("{".utf8)
    #expect(PollingPersistence(store).load(["claude"])["claude"] == PollingPolicy())
    let future = Data(#"{"interval":60,"lastChange":\#(t0.timeIntervalSinceReferenceDate + 172_800),"blockedUntil":{}}"#.utf8)
    store.values["polling.claude"] = future; store.writes = 0
    let normalising = PollingPersistence(store), policies = normalising.load(["claude"], now: t0)
    normalising.save(policies); #expect(store.writes == 1 && store.values["polling.claude"] != future)
    normalising.save(policies); #expect(store.writes == 1)
    let settled = PollingPersistence(store); settled.save(settled.load(["claude"], now: t0)); #expect(store.writes == 1)
    let unchanged = Store(); unchanged.values["polling.claude"] = encoded(PollingPolicy())
    let quiet = PollingPersistence(unchanged); quiet.save(quiet.load(["claude"], now: t0)); #expect(unchanged.writes == 0)
}

extension UserDefaults: PollingStorage {}

@Test func userDefaultsRoundTrip() {
    let name = "limitaur-b-" + UUID().uuidString
    let suite = UserDefaults(suiteName: name)!
    defer { suite.removePersistentDomain(forName: name) }
    var policy = PollingPolicy(); _ = policy.recordThrottle(now: t0, retryAfter: 95)
    PollingPersistence(suite).save(["claude": policy])
    let stored = suite.data(forKey: "polling.claude")
    #expect(stored == encoded(policy))
    let second = PollingPersistence(suite)
    #expect(second.load(["claude"], now: t0)["claude"] == policy)
    second.save(["claude": policy]); #expect(suite.data(forKey: "polling.claude") == stored)
    #expect(PollingPersistence(suite).load(["claude"], now: t0)["claude"]?.interval == 100)
}

@Test func tickAndDropdownLine() {
    #expect(cycleTick == 10 && cadenceTolerance == 1)
    #expect(fetchedLine(age: 12, interval: 50) == "  Fetched 12s ago · polls every 50s")
    #expect(fetchedLine(age: 12, interval: nil) == "  Fetched 12s ago")
    #expect(fetchedLine(age: -1, interval: 50) == "  Fetched time unavailable")
    #expect(fetchedLine(age: .nan, interval: 50) == "  Fetched time unavailable")
    #expect(fetchedLine(age: 5, interval: .infinity) == "  Fetched 5s ago" && fetchedLine(age: 5, interval: -10) == "  Fetched 5s ago")
}

@Test func dropdownSeams() {
    #expect(pollsLine(interval: 70) == "  Polls every 70s")
    #expect(demoPolling["claude"]?.interval == 50 && demoPolling["codex"]?.interval == 50 && demoPolling.count == 2)
    var changed = demoPolling
    #expect(!intervalsDiffer(demoPolling, changed))
    _ = changed["claude"]?.recordClean(now: t0, reductionAllowed: true)
    #expect(changed["claude"] != demoPolling["claude"] && !intervalsDiffer(demoPolling, changed))
    _ = changed["claude"]?.recordThrottle(now: t0, retryAfter: nil)
    #expect(intervalsDiffer(demoPolling, changed) && intervalsDiffer([:], demoPolling))
}

// MARK: review fixes (r9)
@Test func rankingHonoursHorizonAndRetention() async {
    let rig = await Rig([scResponse()], policy: at(100))
    func ranked(_ r: Rig) async -> Bool { !(await r.monitor.display()).candidates.isEmpty }
    #expect(await ranked(rig))
    rig.clock.advance(100); #expect(await ranked(rig))
    rig.clock.advance(19.5); #expect(await ranked(rig))
    rig.clock.advance(0.5); #expect(!(await ranked(rig)))
    let held = await Rig([scResponse(), scResponse(429, retry: "5")], policy: at(110))
    #expect(await bWait { await held.row()?.snapshot != nil })
    held.clock.advance(108.5); await held.monitor.refresh(driver: .cycle)
    #expect(await bWait { await held.transport.count() == 2 })
    #expect(await bWait { await held.row()?.health == .throttled })
    held.clock.advance(121.5); #expect(await ranked(held))
    held.clock.advance(0.5); #expect(!(await ranked(held)))
}

@Test func settlementIsPerEntityAndPublishes() async {
    let rig = await Rig(policy: PollingPolicy(), reactive: true, deferred: true, paths: [path, "/b/b"])
    #expect(await bWait { await rig.transport.count() == 2 })
    await rig.transport.answer(0, scResponse()); await rig.transport.answer(1, scResponse()); await scFlush()
    rig.clock.advance(50); await rig.monitor.refresh(driver: .cycle)
    #expect(await bWait { await rig.transport.count() == 4 })
    await rig.transport.answer(2, scResponse(429)); await rig.transport.answer(3, scResponse(429)); await scFlush()
    let stream = await rig.monitor.changes()
    let collector = Task { () -> Double? in
        var last: Double?
        for await value in stream { last = value.polling["claude"]?.interval }
        return last
    }
    rig.files.set(path, scClaude(11))
    await rig.step(30)
    #expect(await bWait { await rig.policy()?.interval == 60 })
    await scFlush()
    #expect(await rig.policy()?.interval == 60)
    collector.cancel()
    #expect(await collector.value == 60)
    await rig.transport.finish(); await rig.monitor.stop()
}

// MARK: receipt-settlement tests for the r10 fixes
@Test func revertNeverFallsBelowCurrentInterval() {
    var p = aged(); cleans(&p, 5, at: day(1))
    let reduced = day(1)
    #expect(p.interval == 40 && p.lastReduction?.at == reduced)
    // A throttle dated exactly at the window edge is outside it: a plain raise to the Retry-After.
    let raised = p.recordThrottle(now: reduced + 3_600, retryAfter: 95)
    #expect(raised && p.interval == 100)
    // A receipt settled late with its original time lands inside the window but must not lower the interval.
    let lowered = p.recordThrottle(now: reduced + 3_590, retryAfter: nil)
    #expect(!lowered)
    #expect(p.interval == 100 && p.lastReduction == nil && p.consecutiveClean == 0)
    #expect(p.blockedUntil == [40: reduced + 3_590 + 7 * 86_400])
}

/// Reactive monitor over the `CR*` fakes with a claude and a codex policy; waits are bounded by `settle` and `crWait`.
private struct Replay {
    let clock = CRClock(), files = CRFiles(), keychain: CRKeychain, transport: CRTransport, monitor: Monitor
    init(_ queued: [HTTPResponse] = [], keychain: CRKeychain = CRKeychain(.notFound), reader: (any CredentialFileReading)? = nil) {
        self.keychain = keychain; transport = CRTransport(queued)
        monitor = Monitor(clock: clock, credentials: CredentialStore(files: reader ?? files, keychain: keychain),
                          transport: transport, reactiveRecheck: true)
    }
    func start(_ profiles: [AccountProfile]) async {
        await monitor.setPolling(["claude": PollingPolicy(), "codex": PollingPolicy()])
        await monitor.setProfiles(profiles); #expect(await monitor.settle())
    }
    func policy(_ provider: String = "claude") async -> PollingPolicy? { await monitor.display().polling[provider] }
    /// Advances 50 s, runs one cycle and returns the wall time at which the 429 was received.
    func cycle(expecting requests: Int) async -> Date {
        clock.move(wall: 50, mono: 50); await monitor.refresh(driver: .cycle)
        let transport = transport
        let arrived = await crWait { await transport.count() == requests }
        #expect(arrived); #expect(await monitor.settle())
        return clock.wallNow()
    }
}
private func replayProfile(_ id: String = "p0", _ n: Int = 1) -> AccountProfile { crProfile(id, source: .claudeFile(crPath(n))) }

@Test func sameTokenSelectorRebindRecordsAtOnceWithAlias() async {
    let rig = Replay([crResponse(codex: true), crResponse(429, codex: true)])
    rig.files.set(crPath(1), crCodex(1, account: "A")); rig.files.set(crPath(2), crCodex(1, account: "A"))
    await rig.start([crProfile("p0", source: .codexFile(crPath(1))), crProfile("p1", source: .codexFile(crPath(2)))])
    #expect(await rig.monitor.retainedEntityCount() == 1) // p1 is an alias on p0's entity
    let receipt = await rig.cycle(expecting: 2)
    #expect(await rig.policy("codex")?.interval == 50)
    rig.clock.move(wall: 20, mono: 20)
    rig.files.set(crPath(1), crCodex(1, account: "B")) // same token bytes, different selector
    await rig.monitor.reconnect("p0"); #expect(await rig.monitor.settle())
    let policy = await rig.policy("codex")
    #expect(policy?.interval == 60 && policy?.lastChange == receipt)
    #expect(await rig.monitor.retainedEntityCount() == 2)
    await rig.monitor.stop()
}

@Test func capacityRejectedDifferentTokenConnectRecords() async {
    let rig = Replay()
    var profiles: [AccountProfile] = []
    for n in 1...256 { rig.files.set(crPath(n), crClaude(n)); profiles.append(replayProfile(n == 1 ? "p0" : "f\(n)", n)) }
    await rig.start(profiles)
    let (entities, requests) = (await rig.monitor.retainedEntityCount(), await rig.transport.count())
    #expect(entities == 256 && requests == 256)
    await rig.transport.reply(token: 1, with: [crResponse(429)])
    let receipt = await rig.cycle(expecting: 512)
    #expect(await rig.policy()?.interval == 50)
    rig.files.set(crPath(1), crClaude(9_000)) // a different token, with no free entity slot
    await rig.monitor.reconnect("p0"); #expect(await rig.monitor.settle())
    #expect((await crRow(rig.monitor, "p0"))?.health == .unavailable)
    let policy = await rig.policy()
    #expect(policy?.interval == 60 && policy?.lastChange == receipt)
    await rig.monitor.stop()
}

/// A throttled sole subscriber `p0` on file 1 whose configuration is about to be replaced; returns the receipt's wall time.
private func armedSoleSubscriber(_ rig: Replay) async -> Date {
    rig.files.set(crPath(1), crClaude(1))
    await rig.start([replayProfile()])
    await rig.transport.reply(token: 1, with: [crResponse(429)])
    let receipt = await rig.cycle(expecting: 2)
    #expect(await rig.policy()?.interval == 50)
    return receipt
}

@Test(arguments: [(2, 50.0), (1, 60.0)] as [(Int, Double)])
func replacementLoadClassifiesHeldReceipt(token: Int, expected: Double) async {
    let rig = Replay()
    let receipt = await armedSoleSubscriber(rig)
    rig.clock.move(wall: 5, mono: 5)
    rig.files.set(crPath(2), crClaude(token))
    await rig.monitor.setProfiles([replayProfile("p0", 2)]); #expect(await rig.monitor.settle())
    let policy = await rig.policy()
    #expect(policy?.interval == expected)
    if expected > 50 { #expect(policy?.lastChange == receipt) }
    // The held receipt is resolved either way: the 60 s fallback must not record it again.
    rig.clock.move(wall: 120, mono: 120); await rig.monitor.refresh(driver: .internal); await crFlush()
    #expect(await rig.policy()?.interval == expected)
    await rig.monitor.stop()
}

@Test(arguments: [false, true])
func replacementLoadThatNeverCompletesRecordsAtSixtySeconds(profileRemoved: Bool) async {
    let gate = CRGate(), keychain = CRKeychain(.notFound)
    keychain.at(1, CRRead(.notFound, gate: gate))
    let rig = Replay(keychain: keychain)
    let receipt = await armedSoleSubscriber(rig)
    // The replacement reads the blocked Keychain; the old binding is gone and its receipt is held aside.
    await rig.monitor.setProfiles([crProfile("p0")])
    #expect(await crWait { keychain.count() == 1 })
    if profileRemoved { await rig.monitor.setProfiles([]) }
    rig.clock.move(wall: 59, mono: 59); await rig.monitor.refresh(driver: .cycle); await crFlush()
    #expect(await rig.policy()?.interval == 50)
    rig.clock.move(wall: 1, mono: 1); await rig.monitor.refresh(driver: .cycle); await crFlush()
    let policy = await rig.policy()
    #expect(policy?.interval == 60 && policy?.lastChange == receipt)
    gate.release(); await rig.monitor.stop()
}

@Test func removingLastClassifierRecordsAtOnce() async {
    let rig = Replay([crResponse(verified: "X", codex: true), crResponse(verified: "X", codex: true)])
    rig.files.set(crPath(1), crCodex(1, account: "X")); rig.files.set(crPath(2), crCodex(2, account: "X"))
    let profiles = [crProfile("p0", source: .codexFile(crPath(1))), crProfile("p1", source: .codexFile(crPath(2)))]
    await rig.start(profiles)
    #expect(await rig.monitor.retainedEntityCount() == 1) // verified-account merge: two fingerprints, one entity
    await rig.transport.reply(token: 1, with: [crResponse(429, codex: true)])
    await rig.transport.reply(token: 2, with: [crResponse(429, codex: true)])
    let receipt = await rig.cycle(expecting: 3)
    let throttledIndex = await rig.transport.count(token: 1) == 2 ? 0 : 1
    #expect(await rig.policy("codex")?.interval == 50)
    rig.clock.move(wall: 10, mono: 10)
    await rig.monitor.setProfiles([profiles[1 - throttledIndex]]); #expect(await rig.monitor.settle())
    let policy = await rig.policy("codex")
    #expect(policy?.interval == 60 && policy?.lastChange == receipt)
    await rig.monitor.stop()
}

// MARK: third fix round
@Test(arguments: [true, false])
func ordinaryConnectWithSameTokenRecordsAtOnce(codex: Bool) async {
    let rig = Replay(), name = codex ? "codex" : "claude"
    rig.files.set(crPath(1), codex ? crCodex(1, account: "A") : crClaude(1))
    await rig.start([codex ? crProfile("p0", source: .codexFile(crPath(1))) : replayProfile()])
    await rig.transport.reply(token: 1, with: [crResponse(429, codex: codex)])
    let receipt = await rig.cycle(expecting: 2)
    #expect(await rig.policy(name)?.interval == 50)
    rig.clock.move(wall: 20, mono: 20)
    await rig.monitor.reconnect("p0"); #expect(await rig.monitor.settle())
    let policy = await rig.policy(name)
    #expect(policy?.interval == 60 && policy?.lastChange == receipt)
    await rig.monitor.stop()
}

/// Two profiles on one file share an entity; the 429 leaves a receipt on it, and `p0` is then to be pointed at another file.
private func aliasedClaude(_ rig: Replay, replacementToken: Int) async -> (receipt: Date, replaced: [AccountProfile]) {
    rig.files.set(crPath(1), crClaude(1)); rig.files.set(crPath(2), crClaude(replacementToken))
    await rig.start([replayProfile("p0"), replayProfile("p1")])
    #expect(await rig.monitor.retainedEntityCount() == 1)
    await rig.transport.reply(token: 1, with: [crResponse(429)])
    let receipt = await rig.cycle(expecting: 2)
    #expect(await rig.policy()?.interval == 50)
    rig.clock.move(wall: 5, mono: 5)
    return (receipt, [replayProfile("p0", 2), replayProfile("p1")])
}

@Test func sameTokenSourceReplacementWithAliasRecordsAtOnce() async {
    let rig = Replay()
    let (receipt, replaced) = await aliasedClaude(rig, replacementToken: 1)
    await rig.monitor.setProfiles(replaced); #expect(await rig.monitor.settle())
    let policy = await rig.policy()
    #expect(policy?.interval == 60 && policy?.lastChange == receipt)
    await rig.monitor.stop()
}

@Test func differentTokenSourceReplacementWithAliasDiscards() async {
    let rig = Replay()
    let (_, replaced) = await aliasedClaude(rig, replacementToken: 2)
    await rig.monitor.setProfiles(replaced); #expect(await rig.monitor.settle())
    #expect(await rig.policy()?.interval == 50)
    // The alias's own later re-read and the 60 s fallback find nothing left to record.
    rig.clock.move(wall: 5, mono: 5)
    await rig.monitor.reconnect("p1"); #expect(await rig.monitor.settle())
    rig.clock.move(wall: 120, mono: 120); await rig.monitor.refresh(driver: .internal); await crFlush()
    #expect(await rig.policy()?.interval == 50)
    await rig.monitor.stop()
}

@Test func heldReplacedReceiptBlocksReductionOnlyForItsProvider() async {
    let gate = CRGate(), keychain = CRKeychain(.notFound)
    keychain.at(1, CRRead(.notFound, gate: gate))
    let rig = Replay(keychain: keychain)
    var armed = PollingPolicy(); _ = armed.recordClean(now: t0 - 172_800, reductionAllowed: true); armed.recordOther()
    for _ in 0..<3 { _ = armed.recordClean(now: t0 - 172_800, reductionAllowed: true) }
    await rig.monitor.setPolling(["claude": armed, "codex": armed])
    rig.files.set(crPath(1), crClaude(1)); rig.files.set(crPath(2), crClaude(2)); rig.files.set(crPath(3), crCodex(3))
    let profiles = [replayProfile("p0"), replayProfile("p1", 2), crProfile("c0", source: .codexFile(crPath(3)))]
    await rig.start(profiles)
    await rig.transport.reply(token: 1, with: [crResponse(429)])
    _ = await rig.cycle(expecting: 6)
    // p0 is replaced by a load blocked on the Keychain: its receipt is held aside.
    await rig.monitor.setProfiles([crProfile("p0"), profiles[1], profiles[2]])
    #expect(await crWait { keychain.count() == 1 })
    let claudeBefore = await rig.policy()?.interval
    rig.clock.move(wall: 50, mono: 50); await rig.monitor.refresh(driver: .cycle)
    let transport = rig.transport
    #expect(await crWait { await transport.count() == 8 }); await crFlush()
    #expect(await rig.policy()?.interval == claudeBefore)
    #expect(await rig.policy("codex")?.interval == 40)
    gate.release(); await rig.monitor.stop()
}

@Test func accountMismatchRecordsReceiptWhenNoClassifierRemains() async {
    let rig = Replay([crResponse(verified: "X", codex: true), crResponse(verified: "X", codex: true)])
    rig.files.set(crPath(1), crCodex(1, account: "X")); rig.files.set(crPath(2), crCodex(2, account: "X"))
    await rig.start([crProfile("p0", source: .codexFile(crPath(1))), crProfile("p1", source: .codexFile(crPath(2)))])
    #expect(await rig.monitor.retainedEntityCount() == 1)
    // The first-sorted source (token 1, account X) carries both requests: a 429, then a decoded response for another account.
    await rig.transport.reply(token: 1, with: [crResponse(429, codex: true), crResponse(verified: "Y", codex: true)])
    let receipt = await rig.cycle(expecting: 3)
    #expect(await rig.policy("codex")?.interval == 50) // the receipt is still pending
    let readsBefore = rig.files.count(crPath(1))
    rig.clock.move(wall: 31, mono: 31) // past the 30 s backoff, inside the 60 s fallback
    // The internal driver issues no queued reactive re-read, so only the mismatch can classify the receipt.
    await rig.monitor.refresh(force: true, driver: .internal)
    let transport = rig.transport
    #expect(await crWait { await transport.count() == 4 }); #expect(await rig.monitor.settle())
    #expect((await crRow(rig.monitor, "p0"))?.health == .unauthenticated)
    #expect(readsBefore == 1 && rig.files.count(crPath(1)) == 1)
    let (attached, entities) = (await rig.monitor.isAttached("p1"), await rig.monitor.retainedEntityCount())
    #expect(attached && entities == 1)
    var policy = await rig.policy("codex")
    #expect(policy?.interval == 60 && policy?.lastChange == receipt)
    rig.clock.move(wall: 120, mono: 120); await rig.monitor.refresh(driver: .internal); await crFlush()
    policy = await rig.policy("codex")
    #expect(policy?.interval == 60 && policy?.lastChange == receipt) // no second increment
    await rig.monitor.stop()
}

// MARK: fourth fix round
/// Reads through `CRFiles`, holding every read of one path until the gate is released.
private final class HoldingFiles: CredentialFileReading, @unchecked Sendable {
    let inner: CRFiles, gate = CRGate()
    private let lock = NSLock()
    private var held: String?
    init(_ inner: CRFiles) { self.inner = inner }
    func hold(_ path: String) { lock.lock(); held = path; lock.unlock() }
    func read(path: String) throws -> Data {
        lock.lock(); let blocked = held == path; lock.unlock()
        let data = try inner.read(path: path)
        if blocked { gate.wait() }
        return data
    }
}

@Test func aliasReplacementDiscardsReceiptAfterItsEntityMerges() async {
    let files = CRFiles(), holding = HoldingFiles(files)
    let rig = Replay(reader: holding)
    // p0 and p1 share token 1; p2 (token 3, same verified account) already sits in the verified entity.
    files.set(crPath(1), crCodex(1, account: "X")); files.set(crPath(2), crCodex(2, account: "X")); files.set(crPath(3), crCodex(3, account: "X"))
    let profiles = [crProfile("p0", source: .codexFile(crPath(1))), crProfile("p1", source: .codexFile(crPath(1))),
                    crProfile("p2", source: .codexFile(crPath(3)))]
    await rig.transport.reply(token: 3, with: [crResponse(verified: "X", codex: true)])
    await rig.start(profiles)
    #expect(await rig.monitor.retainedEntityCount() == 2)
    await rig.transport.reply(token: 1, with: [crResponse(429, codex: true), crResponse(verified: "X", codex: true)])
    _ = await rig.cycle(expecting: 4)
    #expect(await rig.policy("codex")?.interval == 50)
    rig.clock.move(wall: 5, mono: 5)
    // p0 moves to a different token; its load stays open while p1's entity merges into the verified one, taking the receipt along.
    holding.hold(crPath(2))
    await rig.monitor.setProfiles([crProfile("p0", source: .codexFile(crPath(2))), profiles[1], profiles[2]])
    #expect(await crWait { files.count(crPath(2)) == 1 })
    rig.clock.move(wall: 26, mono: 26)
    await rig.monitor.refresh(force: true, driver: .internal)
    let transport = rig.transport
    #expect(await crWait { await transport.count(token: 1) == 3 }); await crFlush()
    #expect(await rig.monitor.retainedEntityCount() == 1) // p1 and p2 now share the verified entity
    #expect(await rig.policy("codex")?.interval == 50)
    holding.gate.release(); #expect(await rig.monitor.settle())
    #expect(await rig.monitor.isAttached("p0"))
    #expect(await rig.policy("codex")?.interval == 50)
    rig.clock.move(wall: 120, mono: 120); await rig.monitor.refresh(driver: .internal); await crFlush()
    let policy = await rig.policy("codex")
    #expect(policy?.interval == 50) // neither the load nor the 60 s fallback recorded the discarded receipt
    await rig.monitor.stop()
}

@Test(arguments: [true, false])
func aliasAssociationFollowsReceiptIntoSoleReplacementHold(sameTokenFirst: Bool) async {
    let files = CRFiles(), holding = HoldingFiles(files)
    let rig = Replay(reader: holding)
    files.set(crPath(1), crClaude(1)); files.set(crPath(2), crClaude(1)); files.set(crPath(3), crClaude(3))
    await rig.start([replayProfile("p0"), replayProfile("p1")])
    #expect(await rig.monitor.retainedEntityCount() == 1)
    await rig.transport.reply(token: 1, with: [crResponse(429)])
    let receipt = await rig.cycle(expecting: 2)
    #expect(await rig.policy()?.interval == 50)
    rig.clock.move(wall: 5, mono: 5)
    // One edit repoints both aliases: p0 to a copy of the same token (the alias case), p1 to another token (the sole-subscriber hold).
    let (first, second) = sameTokenFirst ? ("p0", "p1") : ("p1", "p0")
    let heldPath = crPath(sameTokenFirst ? 3 : 2)
    holding.hold(heldPath)
    await rig.monitor.setProfiles([replayProfile("p0", 2), replayProfile("p1", 3)])
    #expect(await crWait { files.count(heldPath) == 1 })
    let monitor = rig.monitor
    #expect(await crWait { await monitor.isAttached(first) })
    if sameTokenFirst {
        // The same-token load records the receipt although it now sits in the other profile's hold.
        let policy = await rig.policy()
        #expect(policy?.interval == 60 && policy?.lastChange == receipt)
    } else {
        #expect(await rig.policy()?.interval == 50) // the different-token load discarded it
    }
    holding.gate.release(); #expect(await rig.monitor.settle())
    #expect(await rig.monitor.isAttached(second))
    // The later load finds nothing to settle, and the 60 s fallback does not record again.
    let expected: Double = sameTokenFirst ? 60 : 50
    #expect(await rig.policy()?.interval == expected)
    rig.clock.move(wall: 120, mono: 120); await rig.monitor.refresh(driver: .internal); await crFlush()
    let policy = await rig.policy()
    #expect(policy?.interval == expected)
    if sameTokenFirst { #expect(policy?.lastChange == receipt) }
    await rig.monitor.stop()
}
