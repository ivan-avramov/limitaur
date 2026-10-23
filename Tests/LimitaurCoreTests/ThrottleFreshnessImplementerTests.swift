import Foundation
import Testing
@testable import LimitaurCore

private final class Clk: MonitorClock, @unchecked Sendable {
    private let lock = NSLock()
    private var offset: TimeInterval = 0
    func at(_ t: TimeInterval) { lock.lock(); offset = t; lock.unlock() }
    func wallNow() -> Date { lock.lock(); defer { lock.unlock() }; return Date(timeIntervalSince1970: 1_800_000_000 + offset) }
    func monotonicNow() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return 100 + offset }
}
private struct Files: CredentialFileReading {
    func read(path: String) throws -> Data {
        Data(#"{"tokens":{"access_token":"\#(path.dropFirst())","account_id":"shared"}}"#.utf8)
    }
}
private struct NoKeychain: KeychainReading { func claudeCredential() -> KeychainResult { .notFound } }
private enum Step { case reply(HTTPResponse), fail, hold }
private func httpReply(_ status: Int, _ retry: String? = nil, reset: Int? = nil) -> HTTPResponse {
    let window = reset.map { #""used_percent":40,"reset_at":\#($0)"# } ?? #""used_percent":40"#
    return HTTPResponse(status: status, headers: retry.map { ["retry-after": $0] } ?? [:],
                        body: Data(#"{"account_id":"shared","rate_limit":{"primary_window":{\#(window)}}}"#.utf8))
}
private func reply(_ status: Int, _ retry: String? = nil, reset: Int? = nil) -> Step {
    .reply(httpReply(status, retry, reset: reset))
}
private actor Script: HTTPTransport {
    var steps: [String: [Step]]
    var held: [String: CheckedContinuation<Result<HTTPResponse, Error>, Never>] = [:]
    var calls = 0
    init(_ steps: [String: [Step]]) { self.steps = steps }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        calls += 1
        var queue = steps[request.bearer] ?? []
        let step = queue.isEmpty ? Step.fail : queue.removeFirst()
        steps[request.bearer] = queue
        switch step {
        case .reply(let response): return response
        case .fail: throw TransportFailure.network
        case .hold: return try await withCheckedContinuation { held[request.bearer] = $0 }.get()
        }
    }
    @discardableResult func waitHeld(_ bearer: String) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while held[bearer] == nil {
            if ContinuousClock.now >= deadline { Issue.record("request for \(bearer) was never held"); return false }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return true
    }
    func release(_ bearer: String, _ result: Result<HTTPResponse, Error>) async {
        guard await waitHeld(bearer) else { return }
        held.removeValue(forKey: bearer)?.resume(returning: result)
    }
    func releaseAll() {
        for (_, continuation) in held { continuation.resume(returning: .failure(TransportFailure.network)) }
        held.removeAll()
    }
    func count() -> Int { calls }
}
private struct Rig {
    let clock = Clk(), transport: Script, monitor: Monitor
    init(_ steps: [Step], ids: [String] = ["a"], more: [String: [Step]] = [:]) async {
        transport = Script(["a": steps].merging(more) { $1 })
        monitor = Monitor(clock: clock, credentials: CredentialStore(files: Files(), keychain: NoKeychain()), transport: transport)
        await monitor.setProfiles(ids.map { AccountProfile(id: $0, providerID: "codex", label: $0, source: .codexFile("/" + $0)) })
        if more.isEmpty { await monitor.settle() } else { await transport.waitHeld("b") }
    }
    func poll(_ t: TimeInterval) async { clock.at(t); await monitor.refresh(); await monitor.settle() }
    func shown(_ t: TimeInterval) async -> Int { clock.at(t); return await monitor.display().selected.count }
    func row(_ t: TimeInterval) async -> ProfileDisplay? { clock.at(t); return await monitor.display().profiles.first }
    func cleanup() async { await transport.releaseAll(); await monitor.settle(); await monitor.stop() }
}
private let T: TimeInterval = 0

@Test func r1NominalWindowEndsAtNinety() async {
    let rig = await Rig([reply(200)])
    #expect(await rig.shown(T + 89.9) == 1)
    #expect(await rig.shown(T + 90) == 0)
    #expect(await rig.row(T + 90)?.message?.contains("Cached usage stale") == true)
}

@Test func r2RetryAfterKeepsSnapshotWithTrueAge() async {
    let rig = await Rig([reply(200), reply(429, "55"), reply(200)])
    await rig.poll(T + 45)
    #expect(await rig.shown(T + 100) == 1)
    #expect(await rig.shown(T + 146) == 1)
    rig.clock.at(T + 99); await rig.monitor.refresh(force: true); await rig.monitor.settle()
    #expect(await rig.transport.count() == 2)
    let row = await rig.row(T + 120)
    #expect(row?.health == .throttled && row?.message?.contains("Retry after") == true)
    #expect(row?.message?.contains("Cached usage stale") == false && row?.fetchedAge == 120)
    var seen: [Int: SnapshotExpirations] = [:]
    let late = projectDisplay(await rig.monitor.display(), count: 1, wallNow: rig.clock.wallNow(),
                              monotonicNow: 100 + 120, observations: &seen)
    #expect(late.profiles.first?.fetchedAge == 120 && late.accessibilitySummary.contains("cached"))
    let early = projectDisplay(await rig.monitor.display(), count: 1, wallNow: rig.clock.wallNow(),
                               monotonicNow: 100 + 89, observations: &seen)
    #expect(early.accessibilitySummary.contains("fresh"))
    #expect(await rig.row(T + 148.5)?.message?.contains("Cached usage stale") == true)
}

@Test func r3LongRetryAfterIsCappedAtThreeHundred() async {
    let rig = await Rig([reply(200), reply(429, "3600")])
    await rig.poll(T + 30)
    #expect(await rig.shown(T + 299.9) == 1)
    #expect(await rig.shown(T + 300) == 0)
}

@Test func r4NoExtensionWithoutProviderDeadline() async {
    let cases: [(TimeInterval, Step)] = [(30, reply(429, "5")), (45, reply(429)), (45, reply(429, "soon")),
                                         (45, reply(401)), (45, reply(500)), (45, .fail)]
    for (at, step) in cases {
        let rig = await Rig([reply(200), step])
        await rig.poll(T + at)
        #expect(await rig.shown(T + 89.9) == 1)
        #expect(await rig.shown(T + 90) == 0)
    }
}

@Test func r4ShortRetryAfterLatchesPastNominalWindow() async {
    let backoff = await Rig([reply(200), reply(500), reply(429, "5")])
    await backoff.poll(T + 40)
    backoff.clock.at(T + 70); await backoff.monitor.refresh(force: true); await backoff.monitor.settle()
    #expect(await backoff.transport.count() == 3)
    #expect(await backoff.shown(T + 89.9) == 1)
    #expect(await backoff.shown(T + 123.499) == 1)
    #expect(await backoff.shown(T + 123.5) == 0)
    #expect(await backoff.shown(T + 178.5) == 0)
    let zero = await Rig([reply(200), reply(429, "0")])
    await zero.poll(T + 70)
    #expect(await zero.shown(T + 118.499) == 1)
    #expect(await zero.shown(T + 118.5) == 0)
}

@Test func r5LateRequestNeverRevivesDroppedSnapshot() async {
    for retryAgain in [false, true] {
        let rig = await Rig([reply(200), reply(429, "55"), .hold])
        await rig.poll(T + 45)
        #expect(await rig.shown(T + 146.4) == 1)
        rig.clock.at(T + 150); await rig.monitor.refresh(); await rig.transport.waitHeld("a")
        #expect(await rig.shown(T + 151) == 0)
        if retryAgain {
            rig.clock.at(T + 152)
            await rig.transport.release("a", .success(httpReply(429, "55")))
            await rig.monitor.settle()
            #expect(await rig.shown(T + 153) == 0)
            #expect(await rig.shown(T + 200) == 0)
        }
    }
}

@Test func r5SnapshotNeverReturns() async {
    let rig = await Rig([reply(200), reply(500), reply(429, "100")])
    await rig.poll(T + 45)
    #expect(await rig.shown(T + 90) == 0)
    await rig.poll(T + 90.4)
    #expect(await rig.transport.count() == 3)
    #expect(await rig.shown(T + 91) == 0)
    #expect(await rig.shown(T + 140) == 0)
}

@Test func r6InFlightRequestKeepsSnapshotAcrossPhasing() async {
    for succeed in [true, false] {
        let rig = await Rig([reply(200), reply(429, "55"), .hold])
        await rig.poll(T + 45)
        rig.clock.at(T + 146); await rig.monitor.refresh(); await rig.transport.waitHeld("a")
        #expect(await rig.shown(T + 150) == 1)
        rig.clock.at(T + 152)
        await rig.transport.release("a", succeed ? .success(httpReply(200)) : .failure(TransportFailure.network))
        await rig.monitor.settle()
        #expect(await rig.shown(T + 152) == (succeed ? 1 : 0))
        #expect(await rig.shown(T + 241) == (succeed ? 1 : 0))
        #expect(await rig.shown(T + 242) == 0)
    }
}

@Test func r7SecondThrottleCappedBySuccess() async {
    let twice = await Rig([reply(200), reply(429, "55"), reply(429, "300")])
    await twice.poll(T + 45); await twice.poll(T + 135)
    #expect(await twice.shown(T + 299.9) == 1)
    #expect(await twice.shown(T + 300) == 0)
    let renewed = await Rig([reply(200), reply(429, "55"), reply(200), reply(429, "3600")])
    await renewed.poll(T + 45); await renewed.poll(T + 135); await renewed.poll(T + 180)
    #expect(await renewed.shown(T + 434.9) == 1)
    #expect(await renewed.shown(T + 435) == 0)
}

@Test func r8NextDeadlineFollowsHelperAndMetricReset() async {
    let plain = await Rig([reply(200), reply(429, "55")])
    await plain.poll(T + 45); plain.clock.at(T + 60)
    #expect(await plain.monitor.display().nextDisplayDeadline == 100 + 148.5)
    let reset = await Rig([reply(200, reset: 1_800_000_120), reply(429, "55")])
    await reset.poll(T + 45); reset.clock.at(T + 60)
    #expect(await reset.monitor.display().nextDisplayDeadline == 100 + 120)
    #expect(await reset.shown(T + 119) == 1)
    #expect(await reset.shown(T + 120) == 0)
}

@Test func r9MergeKeepsNewerSnapshotAndLatchesRetention() async {
    let rig = await Rig([reply(200), reply(429, "210")], ids: ["a", "b"], more: ["b": [.hold]])
    await rig.poll(T + 30)
    rig.clock.at(T + 60)
    await rig.transport.release("b", .success(httpReply(200)))
    await rig.monitor.settle()
    #expect(await rig.shown(T + 150) >= 1)
    #expect(await rig.shown(T + 288) >= 1)
    #expect(await rig.shown(T + 288.5) == 0)
}

@Test func r5ThrottleReceivedWhileShownLatchesAfterNominalDeadline() async {
    let rig = await Rig([reply(200), reply(429, "55"), .hold, reply(200)])
    await rig.poll(T + 45)
    rig.clock.at(T + 148); await rig.monitor.refresh(); await rig.transport.waitHeld("a")
    rig.clock.at(T + 149)
    await rig.transport.release("a", .success(httpReply(429, "55")))
    await rig.monitor.settle()
    #expect(await rig.shown(T + 149) == 1)
    #expect(await rig.shown(T + 252.4) == 1)
    #expect(await rig.shown(T + 252.5) == 0)
    await rig.cleanup()
}

@Test func r6AlternateCredentialInFlightDoesNotHoldSnapshot() async {
    let rig = await Rig([reply(200), reply(429, "55"), .hold], ids: ["a", "b"], more: ["b": [.hold, .hold]])
    await rig.transport.release("b", .success(httpReply(200)))
    await rig.monitor.settle()
    await rig.poll(T + 45)
    rig.clock.at(T + 148); await rig.monitor.refresh(); await rig.transport.waitHeld("a")
    #expect(await rig.shown(T + 148.4) == 1)
    rig.clock.at(T + 150)
    await rig.transport.release("a", .success(httpReply(401)))
    await rig.transport.waitHeld("b")
    #expect(await rig.shown(T + 150) == 0)
    await rig.cleanup()
}

@Test func stopClearsThrottleRetentionState() async {
    let rig = await Rig([reply(200), reply(429, "55"), reply(200), reply(200)])
    await rig.poll(T + 45)
    #expect(await rig.shown(T + 100) == 1)
    await rig.monitor.stop()
    await rig.monitor.setProfiles([AccountProfile(id: "a", providerID: "codex", label: "a", source: .codexFile("/a"))])
    await rig.monitor.wake(); await rig.monitor.settle()
    #expect(await rig.shown(T + 200) == 0)
    rig.clock.at(T + 300); await rig.monitor.refresh(force: true); await rig.monitor.settle()
    #expect(await rig.shown(T + 389.9) == 1)
    #expect(await rig.shown(T + 390) == 0)
    await rig.cleanup()
}
