import Foundation
import Testing
@testable import LimitaurCore

private struct SCMonitorRig {
    // A4 leaves initializer parameter placement open: append reactiveRecheck to
    // baseline labels; where both additions are used below, terminateChildren follows it.
    let clock = SCClock(), files = SCFiles()
    let reader: SCReaderRig, transport: SCTransport, monitor: Monitor
    init(_ reads: [ProcessResult], responses: [HTTPResponse] = [], reactive: Bool = true) {
        reader = SCReaderRig(reads); transport = SCTransport(responses)
        monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: reader.reader()),
                          transport: transport, reactiveRecheck: reactive)
    }
    init(steps: [SCStep], responses: [HTTPResponse]) {
        reader = SCReaderRig(steps: steps); transport = SCTransport(responses)
        monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: reader.reader()),
                          transport: transport, reactiveRecheck: true)
    }
}

@Suite struct SessionContinuityMonitorTests {
    // Reproduces fixed failure A4/A9(a): server rejection notices rotation before 300s.
    @Test(arguments: [401, 403])
    func authFailureRechecksAtThirtySecondBoundaryAndResumes(_ status: Int) async {
        let rig = SCMonitorRig([scResult(data: scClaude(1)), scResult(data: scClaude(2))], responses: [scResponse(status)])
        let monitor = rig.monitor
        await monitor.setProfiles([scProfile()]); #expect(await monitor.settle())
        scExpectMessage(await scRow(monitor), scPaused)
        rig.clock.advance(29.999); await monitor.refresh(driver: .cycle); #expect(await monitor.settle())
        #expect(rig.reader.runner.count() == 1); #expect(await scCount(monitor, "credentialRechecks") == 0)
        rig.clock.advance(0.001); await monitor.refresh(driver: .cycle); #expect(await monitor.settle())
        #expect(rig.reader.runner.count() == 2); #expect(await scCount(monitor, "credentialRechecks") == 1)
        #expect(await scCount(monitor, "credentialResumes") == 1)
        #expect(await scCount(monitor, "credentialRotations") == 0)
        #expect(await rig.transport.count(token: 2) == 1)
        #expect((await scRow(monitor))?.health == .healthy)
        await monitor.stop()
    }

    // Reproduces fixed failure A4/A9(b): 429 rotates an unpaused token, retains only throttle.
    @Test func rateFailureRotatesWithoutSnapshotAndCarriesRetryDeadline() async {
        let rig = SCMonitorRig([scResult(data: scClaude(1)), scResult(data: scClaude(2))])
        let monitor = rig.monitor
        await monitor.setProfiles([scProfile()]); #expect(await monitor.settle())
        #expect((await scRow(monitor))?.snapshot != nil)
        await rig.transport.enqueue(scResponse(429, retry: "120"))
        rig.clock.advance(30); await monitor.refresh(); #expect(await monitor.settle())
        let deadline = await monitor.throttleDeadline(for: "a")
        #expect(deadline == rig.clock.monotonicNow() + 120)
        await monitor.refresh(driver: .cycle); #expect(await monitor.settle())
        #expect(await scCount(monitor, "credentialRotations") == 1)
        #expect(await scCount(monitor, "credentialResumes") == 0)
        #expect(await scCount(monitor, "credentialRechecks") == 1)
        #expect((await scRow(monitor))?.snapshot == nil)
        #expect(await monitor.throttleDeadline(for: "a") == deadline)
        #expect(await rig.transport.count(token: 2) == 0)
        rig.clock.advance(119.999); await monitor.manualRefresh(); #expect(await monitor.settle())
        #expect(await rig.transport.count(token: 2) == 0)
        rig.clock.advance(0.001); await monitor.refresh(); #expect(await monitor.settle())
        #expect(await rig.transport.count(token: 2) == 1)
        await monitor.stop()
    }

    // Preserves invariant A4: manual driver cannot bypass a healthy binding's reactive
    // load cooldown; issuing that load must not mark an unexpired token as expired.
    @Test func reactiveLoadCooldownAppliesToManualAndDoesNotPauseHealthyBinding() async {
        let gate = SCGate()
        defer { gate.release() }
        let rig = SCMonitorRig(steps: [SCStep(result: scResult(data: scClaude(1))),
            SCStep(result: scResult(data: scClaude(2)), gate: gate)], responses: [scResponse(429, retry: "120")])
        let monitor = rig.monitor
        await monitor.setProfiles([scProfile()]); #expect(await monitor.settle())
        rig.clock.advance(29.999); await monitor.manualRefresh(); #expect(await monitor.settle())
        #expect(rig.reader.runner.count() == 1)
        rig.clock.advance(0.001); await monitor.refresh()
        #expect(await scWait { rig.reader.runner.count() == 2 })
        #expect((await scRow(monitor))?.health == .throttled)
        #expect(await scCount(monitor, "credentialExpiries") == 0)
        gate.release(); #expect(await monitor.settle())
        #expect(await scCount(monitor, "credentialRotations") == 1); #expect(!gate.didExpire())
        await monitor.stop()
    }

    // Preserves invariant A4: a late result from an old binding cannot queue a read
    // against the replacement fingerprint, nor disturb Connect's successful result.
    @Test func lateOldFingerprintFailureDoesNotScheduleNewBindingRead() async {
        let clock = SCClock(), reader = SCReaderRig([scResult(data: scClaude(1)), scResult(data: scClaude(2))])
        let transport = SCTransport(deferred: true)
        let monitor = Monitor(clock: clock, credentials: CredentialStore(files: SCFiles(), keychain: reader.reader()),
                              transport: transport, reactiveRecheck: true)
        await monitor.setProfiles([scProfile()])
        #expect(await scWait { await transport.count() == 1 })
        await monitor.reconnect("a")
        #expect(await scWait { await transport.count() == 2 })
        await transport.answer(1, scResponse()); await transport.answer(0, scResponse(401))
        #expect(await monitor.settle())
        clock.advance(31); await transport.enqueue(scResponse()); await monitor.refresh()
        #expect(await monitor.settle())
        #expect(reader.runner.count() == 2); #expect(await scCount(monitor, "credentialRechecks") == 0)
        #expect((await scRow(monitor))?.health == .healthy)
        await transport.finish(); await monitor.stop()
    }

    // Preserves invariant A4/A9(c): same-token reread cannot clear rejection or invent rotation.
    @Test(arguments: [401, 429])
    func sameTokenConsumesDueEntryWithoutRepeatedReads(_ status: Int) async {
        let rig = SCMonitorRig([scResult(data: scClaude(1)), scResult(data: scClaude(1))],
                               responses: [scResponse(status, retry: "120")])
        let monitor = rig.monitor
        await monitor.setProfiles([scProfile()]); #expect(await monitor.settle())
        let before = await scRow(monitor)
        rig.clock.advance(30); await monitor.refresh(); #expect(await monitor.settle())
        let unchanged = (await scRow(monitor))?.message == before?.message
        #expect(unchanged)
        rig.clock.advance(29.999); await monitor.refresh(); #expect(await monitor.settle())
        #expect(rig.reader.runner.count() == 2); #expect(await scCount(monitor, "credentialRechecks") == 1)
        #expect(await scCount(monitor, "credentialRotations") == 0)
        #expect(await scCount(monitor, "credentialResumes") == 0)
        #expect(await rig.transport.count() == 1)
        await monitor.stop()
    }

    // Preserves baseline A4/A9(g): omitted flag keeps automatic rereads at 300s.
    @Test(arguments: [401, 429])
    func defaultFlagDoesNotReactivelyReread(_ status: Int) async {
        let clock = SCClock(), reader = SCReaderRig([scResult(data: scClaude(1)), scResult(data: scClaude(2))])
        let transport = SCTransport([scResponse(status, retry: "600")])
        let monitor = Monitor(clock: clock, credentials: CredentialStore(files: SCFiles(), keychain: reader.reader()), transport: transport)
        await monitor.setProfiles([scProfile()]); #expect(await monitor.settle())
        clock.advance(30); await monitor.refresh(); #expect(await monitor.settle())
        clock.advance(269.999); await monitor.refresh(); #expect(await monitor.settle())
        #expect(reader.runner.count() == 1); #expect(await scCount(monitor, "credentialRechecks") == 0)
        await monitor.stop()
    }

    // Preserves invariant A4/A9(d): internal driver and sleep never spend due entries.
    @Test func internalAndSleepingDriversDoNotConsumeReactiveRecheck() async {
        let rig = SCMonitorRig([scResult(data: scClaude(1)), scResult(data: scClaude(2))], responses: [scResponse(429, retry: "120")])
        let monitor = rig.monitor
        await monitor.setProfiles([scProfile()]); #expect(await monitor.settle())
        rig.clock.advance(30); await monitor.refresh(driver: .internal); #expect(await monitor.settle())
        #expect(rig.reader.runner.count() == 1)
        await monitor.sleep(); rig.clock.advance(30)
        await monitor.refresh(); await monitor.manualRefresh(); await monitor.dropdownOpened()
        #expect(rig.reader.runner.count() == 1)
        await monitor.wake(); #expect(await monitor.settle())
        #expect(rig.reader.runner.count() == 2); #expect(await scCount(monitor, "credentialRotations") == 1)
        await monitor.stop()
    }

    // Preserves Connect precedence A4/A9(d): stale completion cannot erase explicit load.
    @Test func connectWinsOverPendingReactiveResultAndSuppressesFurtherLoads() async {
        let backgroundGate = SCGate(), connectGate = SCGate()
        defer { backgroundGate.release(); connectGate.release() }
        let rig = SCMonitorRig(steps: [SCStep(result: scResult(data: scClaude(1))),
            SCStep(result: scResult(data: scClaude(2)), gate: backgroundGate),
            SCStep(result: scResult(data: scClaude(3)), gate: connectGate)], responses: [scResponse(401)])
        let monitor = rig.monitor
        await monitor.setProfiles([scProfile()]); #expect(await monitor.settle())
        rig.clock.advance(30); await monitor.refresh()
        #expect(await scWait { rig.reader.runner.count() == 2 })
        await monitor.reconnect("a"); await scFlush()
        backgroundGate.release()
        #expect(await scWait { rig.reader.runner.count() == 3 })
        await scFlush()
        scExpectMessage(await scRow(monitor), "Connecting account")
        rig.clock.advance(31); await monitor.refresh(); await monitor.reconnect("a"); await monitor.manualRefresh()
        #expect(rig.reader.runner.count() == 3)
        connectGate.release(); #expect(await monitor.settle())
        #expect(await rig.transport.count(token: 2) == 0); #expect(await rig.transport.count(token: 3) == 1)
        #expect(rig.reader.runner.interactiveFlags() == [false, false, true])
        #expect(await scCount(monitor, "credentialRotations") == 0)
        #expect(await scCount(monitor, "credentialResumes") == 0)
        #expect(!backgroundGate.didExpire() && !connectGate.didExpire())
        await monitor.stop()
    }

    // Preserves invariant A4: dropping/disable removes due entries; restoring same ID starts fresh.
    @Test(arguments: [false, true])
    func removedOrDisabledProfileCannotIssueQueuedRead(_ disabled: Bool) async {
        let rig = SCMonitorRig([scResult(data: scClaude(1)), scResult(data: scClaude(2))], responses: [scResponse(429, retry: "120")])
        let monitor = rig.monitor
        await monitor.setProfiles([scProfile()]); #expect(await monitor.settle())
        await monitor.setProfiles(disabled ? [scProfile(enabled: false)] : [])
        rig.clock.advance(31); await monitor.refresh(); #expect(await monitor.settle())
        #expect(rig.reader.runner.count() == 1); #expect(await scCount(monitor, "credentialRechecks") == 0)
        await monitor.setProfiles([scProfile()]); #expect(await monitor.settle())
        rig.clock.advance(31); await monitor.refresh(); #expect(await monitor.settle())
        #expect(rig.reader.runner.count() == 2); #expect(await scCount(monitor, "credentialRechecks") == 0)
        await monitor.stop()
    }

    // Exercises new behaviour A4/A9(e): suspended wording/count is transition-based, bound or unbound.
    @Test(arguments: [false, true])
    func suspensionWordingCountsOnceUntilInteractiveConnect(_ bound: Bool) async {
        let results = bound ? [scResult(data: scClaude(1)), scResult(51), scResult(data: scClaude(2))]
                            : [scResult(51), scResult(data: scClaude(2))]
        let rig = SCMonitorRig(results, responses: bound ? [scResponse(401)] : [])
        let monitor = rig.monitor
        await monitor.setProfiles([scProfile()]); #expect(await monitor.settle())
        if bound { rig.clock.advance(30); await monitor.refresh(); #expect(await monitor.settle()) }
        scExpectMessage(await scRow(monitor), scSuspended)
        rig.clock.advance(300); await monitor.refresh(); #expect(await monitor.settle())
        scExpectMessage(await scRow(monitor), scSuspended)
        #expect(await scCount(monitor, "keychainSuspensions") == 1)
        rig.clock.advance(300); await monitor.refresh(); #expect(await monitor.settle())
        scExpectMessage(await scRow(monitor), scSuspended)
        #expect(await scCount(monitor, "keychainSuspensions") == 1)
        #expect(rig.reader.runner.count() == (bound ? 2 : 1))
        await monitor.reconnect("a"); #expect(await monitor.settle())
        #expect(rig.reader.runner.interactiveFlags().last == true)
        #expect(!rig.reader.suspensions.isSuspended(rig.reader.service))
        #expect((await scRow(monitor))?.health == .healthy)
        await monitor.stop()
    }

    // Preserves invariant A4: a non-denied reread restores suspended to paused wording.
    @Test func laterNonDeniedReadRestoresPausedFamily() async {
        let rig = SCMonitorRig([scResult(data: scClaude(1)), scResult(51),
                               scResult(data: scClaude(1, expiry: SCClock().wallNow()))], responses: [scResponse(401)])
        let monitor = rig.monitor
        await monitor.setProfiles([scProfile()]); #expect(await monitor.settle())
        rig.clock.advance(30); await monitor.refresh(); #expect(await monitor.settle())
        rig.clock.advance(300); await monitor.refresh(); #expect(await monitor.settle())
        scExpectMessage(await scRow(monitor), scSuspended)
        // An external explicit read on this private fake reader completes and clears suspension.
        _ = rig.reader.reader().claudeCredentialDetailed(interactive: true)
        rig.reader.runner.append(scResult(data: scClaude(1, expiry: rig.clock.wallNow())))
        rig.clock.advance(300); await monitor.refresh(); #expect(await monitor.settle())
        scExpectMessage(await scRow(monitor), scPaused)
        #expect(await scCount(monitor, "keychainSuspensions") == 1)
        await monitor.stop()
    }

    // Preserves invariant A4: aliases share at most one credential-source read in a pass.
    @Test func aliasesIssueOneReadPerSourcePerPass() async {
        let rig = SCMonitorRig([scResult(data: scClaude(1)), scResult(data: scClaude(1)),
                               scResult(data: scClaude(2))], responses: [scResponse(429, retry: "120")])
        let monitor = rig.monitor
        await monitor.setProfiles([scProfile("a"), scProfile("b")]); #expect(await monitor.settle())
        #expect(rig.reader.runner.count() == 2)
        rig.clock.advance(30); await monitor.refresh(); #expect(await monitor.settle())
        #expect(rig.reader.runner.count() == 3); #expect(await scCount(monitor, "credentialRechecks") == 1)
        await monitor.stop()
    }

    // Preserves invariant A4: expiry alone keeps 300s cadence even with reactive flag on.
    @Test func expiryWithoutHttpFailureDoesNotScheduleReactiveRead() async {
        let clock = SCClock(), reader = SCReaderRig([scResult(data: scClaude(1, expiry: Date(timeIntervalSince1970: 1_800_000_010)))])
        let monitor = Monitor(clock: clock, credentials: CredentialStore(files: SCFiles(), keychain: reader.reader()),
                              transport: SCTransport(), reactiveRecheck: true)
        await monitor.setProfiles([scProfile()]); #expect(await monitor.settle())
        clock.advance(30); await monitor.refresh(); #expect(await monitor.settle())
        #expect(reader.runner.count() == 1); #expect(await scCount(monitor, "credentialRechecks") == 0)
        scExpectMessage(await scRow(monitor), scPaused)
        await monitor.stop()
    }

    // Preserves credential boundary A4/A9(f): hostile token-shaped body is never diagnostics.
    @Test(arguments: [401, 403, 429, 500])
    func messagesStatisticsAndErrorsNeverContainTokenBytes(_ status: Int) async {
        let response = HTTPResponse(status: status, headers: [:], body: Data(scToken(1).utf8))
        let rig = SCMonitorRig([scResult(data: scClaude(1)), scResult(36, text: scToken(2))], responses: [response])
        let monitor = rig.monitor
        await monitor.setProfiles([scProfile()]); #expect(await monitor.settle())
        rig.clock.advance(30); await monitor.refresh(); #expect(await monitor.settle())
        let rows = (await monitor.display()).profiles
        let statistics = await monitor.statistics()
        let encoded = try? JSONSerialization.data(withJSONObject: statistics, options: [.sortedKeys])
        let safeRows = rows.allSatisfy { scSafe($0.message ?? "") }
        let safeStats = encoded.flatMap { String(data: $0, encoding: .utf8) }.map { scSafe($0) } ?? false
        let failure = CredentialStore(files: rig.files, keychain: rig.reader.reader())
            .loadDetailed(.claudeDefaultDiscovery, now: rig.clock.wallNow())
        let safeError: Bool
        if case .failure(let error) = failure.result { safeError = scSafe(String(describing: error)) }
        else { safeError = true }
        #expect(safeRows); #expect(safeStats); #expect(safeError)
        await monitor.stop()
    }

    // Exercises new behaviour A1/A9(h): stop invokes the injected child-termination hook once.
    @Test func stopCallsTerminationHookAndDropsDueReads() async {
        let calls = SCCounter(), clock = SCClock(), reader = SCReaderRig([scResult(data: scClaude(1))])
        let monitor = Monitor(clock: clock, credentials: CredentialStore(files: SCFiles(), keychain: reader.reader()),
                              transport: SCTransport([scResponse(429)]), reactiveRecheck: true,
                              terminateChildren: { calls.increment() })
        await monitor.setProfiles([scProfile()]); #expect(await monitor.settle())
        await monitor.stop(); #expect(calls.count() == 1)
        clock.advance(300); await monitor.refresh(); #expect(reader.runner.count() == 1)
    }
}

private final class SCCounter: @unchecked Sendable {
    private let lock = NSLock(); private var value = 0
    func increment() { lock.withLock { value += 1 } }
    func count() -> Int { lock.withLock { value } }
}
