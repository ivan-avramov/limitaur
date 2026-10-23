import Foundation
import Testing
@testable import LimitaurCore

@Suite struct CredentialRecheckCadenceTests {
    // New behaviour (R1/R4): exact interval equality, silent expired read, no background prompt.
    @Test func expiryRechecksAtExactBoundaryAndKeepsCache() async {
        let clock = CRClock(), files = CRFiles(), keychain = CRKeychain()
        keychain.set(.found(crClaude(1, expires: clock.wallNow().addingTimeInterval(1))))
        let transport = CRTransport()
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: keychain),
                              transport: transport, recheckInterval: 300)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        clock.move(wall: 1, mono: 299)
        await monitor.refresh(driver: .internal)
        let before = await crRow(monitor)
        let failures = await crCount(monitor, "credentialFailures")
        #expect(before?.health == .unauthenticated)
        crExpectMessage(before, crPause)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == 1)
        clock.move(mono: 1)
        await monitor.refresh(); #expect(await monitor.settle())
        let after = await crRow(monitor)
        #expect(keychain.count() == 2)
        #expect(keychain.interactions() == [false, false])
        #expect(after?.health == before?.health)
        crExpectSameMessage(after, before)
        #expect(crCachedPercent(after) == crCachedPercent(before))
        #expect(after?.snapshotGeneration == before?.snapshotGeneration)
        #expect(await crCount(monitor, "credentialFailures") == failures)
        #expect(await crCount(monitor, "credentialRechecks") == 1)
        #expect(await crCount(monitor, "credentialResumes") == 0)
        #expect(await transport.count() == 1)
        await monitor.stop()
    }

    // New behaviour (R4/R11): invalid values fall back to 300; finite values >=30 remain exact.
    @Test(arguments: [0.0, -1.0, Double.nan, 10.0, Double.infinity, -Double.infinity, 29.999])
    func invalidIntervalsUseThreeHundred(_ interval: Double) async {
        let clock = CRClock(), keychain = CRKeychain(), transport = CRTransport()
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: transport, recheckInterval: interval)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        clock.move(mono: 299.999)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == 1)
        clock.move(mono: 0.001)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == 2)
        #expect(await crCount(monitor, "credentialRechecks") == 1)
        await monitor.stop()
    }

    // New behaviour (R4/R11): 30 is valid and the boundary is inclusive.
    @Test(arguments: [30.0, 30.5, 600.0])
    func validIntervalsAreNotClamped(_ interval: Double) async {
        let clock = CRClock(), keychain = CRKeychain()
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: CRTransport(), recheckInterval: interval)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        clock.move(mono: interval - 0.25)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == 1)
        clock.move(mono: 0.25)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == 2)
        await monitor.stop()
    }

    // New behaviour (R4): the default initializer and default refresh driver implement the 300s cycle.
    @Test func defaultIntervalAndDefaultDriver() async {
        let clock = CRClock(), keychain = CRKeychain()
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: CRTransport())
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        clock.move(mono: 299)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == 1)
        clock.move(mono: 1)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == 2)
        await monitor.stop()
    }

    // New behaviour (R4): the public driver's internal value suppresses re-checks even with force/minimumSuccessAge.
    @Test func explicitRefreshDriverContract() async {
        let clock = CRClock(), keychain = CRKeychain()
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: CRTransport())
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        clock.move(mono: 300)
        let driver: RefreshDriver = .internal
        await monitor.refresh(force: true, minimumSuccessAge: 0, driver: driver)
        #expect(await monitor.settle())
        #expect(keychain.count() == 1)
        await monitor.refresh(force: false, minimumSuccessAge: nil, driver: .cycle)
        #expect(await monitor.settle())
        #expect(keychain.count() == 2)
        #expect(await crCount(monitor, "credentialRechecks") == 1)
        await monitor.stop()
    }

    // Preserves an invariant (R4): wall jumps cannot spend a monotonic re-check interval.
    @Test func wallJumpsDoNotAdvanceRecheckCadence() async {
        let clock = CRClock(), keychain = CRKeychain(.found(crClaude(1, expires: Date(timeIntervalSince1970: 1_800_000_010))))
        let transport = CRTransport()
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: transport, recheckInterval: 300)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        clock.move(wall: 3600)
        await monitor.clockChanged(); await monitor.refresh(); #expect(await monitor.settle())
        #expect((await crRow(monitor))?.health == .unauthenticated)
        #expect(keychain.count() == 1)
        clock.move(wall: -7200, mono: 299)
        await monitor.clockChanged(); await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == 1)
        clock.move(mono: 1)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == 2)
        #expect((await crRow(monitor))?.health != .unauthenticated)
        #expect(await transport.count() == 1) // Same now-unexpired token lifts expiry pause, fetch waits for a later cycle.
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await transport.count() == 2)
        await monitor.stop()
    }

    // New behaviour (R4): every actually issued explicit load restarts the interval, even on failure.
    @Test func connectFailureStampsLastLoad() async {
        let clock = CRClock(), keychain = CRKeychain()
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: CRTransport(), recheckInterval: 300)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        clock.move(mono: 20)
        await monitor.reconnect("a"); #expect(await monitor.settle())
        #expect(keychain.interactions() == [false, true])
        clock.move(mono: 280)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == 2)
        clock.move(mono: 20)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.interactions() == [false, true, false])
        await monitor.stop()
    }

    // New behaviour (R4): detach/rebind keeps the instant of the re-check that performed the bind.
    @Test func resumeDoesNotEraseLastLoadInstant() async {
        let clock = CRClock(), keychain = CRKeychain()
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: CRTransport(), recheckInterval: 300)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        keychain.set(.found(crClaude(2, expires: clock.wallNow().addingTimeInterval(1))))
        clock.move(mono: 300)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await crCount(monitor, "credentialResumes") == 1)
        clock.move(wall: 1, mono: 299)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == 2)
        clock.move(mono: 1)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == 3)
        await monitor.stop()
    }

    // New behaviour (R5): dropdown obeys the interval; manual bypasses it for each distinct source.
    @Test func dropdownWaitsAndManualReadsEveryCredentiallessSource() async {
        let clock = CRClock(), files = CRFiles(), keychain = CRKeychain()
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: keychain),
                              transport: CRTransport(), recheckInterval: 300)
        let profiles = [crProfile(), crProfile("b", source: .claudeFile(crPath(2)))]
        await monitor.setProfiles(profiles); #expect(await monitor.settle())
        await monitor.dropdownOpened(); #expect(await monitor.settle())
        #expect(keychain.count() == 1)
        #expect(files.count() == 1)
        await monitor.manualRefresh(); #expect(await monitor.settle())
        #expect(keychain.interactions() == [false, false])
        #expect(files.count() == 2)
        #expect(await crCount(monitor, "credentialRechecks") == 2)
        await monitor.stop()
    }

    // New behaviour (R4): internal public refresh, configuration, load and HTTP completions cannot re-check.
    @Test func internalPathsDoNotRecheckDuePausedProfile() async {
        let clock = CRClock(), keychain = CRKeychain(.found(crClaude(1)))
        let files = CRFiles(), transport = CRTransport([crResponse(401), crResponse()])
        files.set(crPath(2), crClaude(2))
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: keychain),
                              transport: transport, recheckInterval: 300)
        let a = crProfile(), b = crProfile("b", source: .claudeFile(crPath(2)))
        await monitor.setProfiles([a]); #expect(await monitor.settle())
        clock.move(mono: 300)
        await monitor.refresh(force: true, minimumSuccessAge: 0, driver: .internal)
        await monitor.setProfiles([a, b]); #expect(await monitor.settle())
        #expect(keychain.count() == 1)
        #expect(await crCount(monitor, "credentialRechecks") == 0)
        await monitor.refresh(driver: .cycle); #expect(await monitor.settle())
        #expect(keychain.count() == 2)
        #expect(await crCount(monitor, "credentialRechecks") == 1)
        await monitor.stop()
    }

    // Preserves an invariant (R4): the abandoned-subscriber HTTP completion path is internal too.
    @Test func abandonedSubscriberCompletionDoesNotTriggerDueRecheck() async {
        let clock = CRClock(), files = CRFiles(), keychain = CRKeychain(.found(crClaude(1)))
        let gate = CRGate(), transport = CRTransport(deferred: true)
        files.set(crPath(2), crClaude(2))
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: keychain),
                              transport: transport, recheckInterval: 30)
        let a = crProfile(), b = crProfile("b", source: .claudeFile(crPath(2)))
        await monitor.setProfiles([a])
        #expect(await crWait { await transport.count() == 1 })
        await transport.answer(0, crResponse(401)); #expect(await monitor.settle())
        await monitor.setProfiles([a, b])
        #expect(await crWait { await transport.count() == 2 })
        files.block(2, on: gate)
        await monitor.reconnect("b")
        #expect(await crWait { files.count() == 2 })
        clock.move(mono: 30)
        await transport.answer(1, crResponse())
        await crFlush()
        #expect(keychain.count() == 1)
        #expect(await crCount(monitor, "credentialRechecks") == 0)
        // Stop cancels the pending explicit epoch before the gated read is released.
        await monitor.stop(); gate.release(); await transport.finish()
        #expect(!gate.expired())
    }

    // New behaviour (R4): sorted profiles sharing a source get one read per pass; completions don't recurse.
    @Test func sharedSourceReadsOncePerPassInSortedProfileOrder() async {
        let clock = CRClock(), keychain = CRKeychain()
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: CRTransport(), recheckInterval: 300)
        await monitor.setProfiles([crProfile("b"), crProfile("a")]); #expect(await monitor.settle())
        let initial = keychain.count()
        keychain.set(.found(crClaude(2)))
        clock.move(mono: 300)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == initial + 1)
        #expect((await crRow(monitor, "a"))?.health == .healthy)
        #expect((await crRow(monitor, "b"))?.health == .unauthenticated)
        #expect(await crCount(monitor, "credentialRechecks") == 1)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == initial + 2)
        #expect((await crRow(monitor, "b"))?.health == .healthy)
        #expect(await crCount(monitor, "credentialRechecks") == 2)
        await monitor.stop()
    }

    // Preserves an invariant (R3/R4): unavailable provider/source, disabled and removed profiles aren't candidates.
    @Test func unavailableDisabledAndRemovedProfilesAreNotRechecked() async {
        let clock = CRClock(), keychain = CRKeychain(), files = CRFiles()
        var disabled = crProfile("disabled"); disabled.enabled = false
        let unavailable = AccountProfile(id: "bad", providerID: "codex", label: "Unavailable",
                                         source: .claudeDefaultDiscovery)
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: keychain),
                              transport: CRTransport(), recheckInterval: 30)
        await monitor.setProfiles([unavailable, disabled, crProfile()]); #expect(await monitor.settle())
        await monitor.setProfiles([unavailable, disabled]); #expect(await monitor.settle())
        let initial = keychain.count()
        clock.move(mono: 3000)
        await monitor.refresh(); await monitor.manualRefresh(); #expect(await monitor.settle())
        #expect(keychain.count() == initial)
        #expect(files.count() == 0)
        #expect(await crCount(monitor, "credentialRechecks") == 0)
        await monitor.stop()
    }
}
