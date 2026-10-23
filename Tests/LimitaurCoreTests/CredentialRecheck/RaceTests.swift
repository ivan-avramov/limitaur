import Foundation
import Testing
@testable import LimitaurCore

@Suite struct CredentialRecheckRaceTests {
    // Reproduces a failure fixed by R6: Connect supersedes a re-check and its pending entry survives the stale result.
    @Test func connectWinsAndLateRecheckDoesNotClearPendingConnect() async {
        let clock = CRClock(), keychain = CRKeychain(), transport = CRTransport()
        let recheckGate = CRGate(), connectGate = CRGate()
        keychain.at(2, CRRead(.found(crClaude(2)), gate: recheckGate))
        keychain.at(3, CRRead(.found(crClaude(3)), gate: connectGate))
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        clock.move(mono: 30)
        await monitor.refresh()
        #expect(await crWait { keychain.count() == 2 })
        await monitor.reconnect("a")
        #expect(await crWait { keychain.count() == 3 })
        #expect(keychain.interactions() == [false, false, true])
        recheckGate.release()
        #expect(await crWait { keychain.didFinish(2) })
        await crFlush()
        #expect(await transport.count() == 0)
        crExpectMessage(await crRow(monitor), "Connecting account")
        await monitor.reconnect("a") // Must see the still-pending explicit load.
        await monitor.refresh(driver: .manual)
        await crFlush()
        #expect(keychain.count() == 3)
        connectGate.release(); #expect(await monitor.settle())
        #expect(await transport.count(token: 2) == 0)
        #expect(await transport.count(token: 3) == 1)
        #expect(await crCount(monitor, "credentialResumes") == 0)
        #expect((await crRow(monitor))?.health == .healthy)
        #expect(!recheckGate.expired() && !connectGate.expired())
        await monitor.stop()
    }

    // Preserves an invariant (R4/R6): pending explicit load suppresses all re-check drivers and another Connect.
    @Test func pendingExplicitLoadSuppressesRechecks() async {
        let clock = CRClock(), keychain = CRKeychain(), gate = CRGate()
        keychain.at(1, CRRead(.found(crClaude(1)), gate: gate))
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: CRTransport(), recheckInterval: 30)
        await monitor.setProfiles([crProfile()])
        #expect(await crWait { keychain.count() == 1 })
        clock.move(mono: 3000)
        await monitor.refresh(); await monitor.dropdownOpened(); await monitor.manualRefresh()
        await monitor.reconnect("a"); await crFlush()
        #expect(keychain.count() == 1)
        #expect(await crCount(monitor, "credentialRechecks") == 0)
        gate.release(); #expect(await monitor.settle())
        #expect((await crRow(monitor))?.health == .healthy)
        #expect(!gate.expired())
        await monitor.stop()
    }

    // New behaviour (R4): an in-flight re-check is cancelled at sleep, never replayed, and remains interval-bounded.
    @Test func sleepingCancelsRecheckWithoutShortSleepReplay() async {
        let clock = CRClock(), keychain = CRKeychain(), transport = CRTransport(), gate = CRGate()
        keychain.at(2, CRRead(.found(crClaude(2)), gate: gate))
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        clock.move(mono: 30); await monitor.refresh()
        #expect(await crWait { keychain.count() == 2 })
        await monitor.sleep()
        clock.move(mono: 10)
        await monitor.refresh(); await monitor.manualRefresh(); await monitor.dropdownOpened()
        #expect(keychain.count() == 2)
        await monitor.wake(); await crFlush()
        #expect(keychain.count() == 2)
        gate.release(); #expect(await crWait { keychain.didFinish(2) }); await crFlush()
        #expect(await transport.count() == 0)
        keychain.set(.found(crClaude(3)))
        clock.move(mono: 19.75)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == 2)
        clock.move(mono: 0.25)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == 3)
        #expect(await transport.count(token: 2) == 0)
        #expect(await transport.count(token: 3) == 1)
        #expect(await crCount(monitor, "credentialRechecks") == 2)
        #expect(!gate.expired())
        await monitor.stop()
    }

    // New behaviour (R1/R4): continuous time counts sleep; wake denial never introduces the denied message.
    @Test(arguments: [false, true])
    func longSleepWakeDenialIsSilentForBindingAndFailure(_ existingBinding: Bool) async {
        let clock = CRClock(), keychain = CRKeychain(), transport = CRTransport([crResponse(401)])
        if existingBinding { keychain.set(.found(crClaude(1))) }
        else { keychain.set(.found(crClaude(1, expires: clock.wallNow()))) }
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        crExpectMessage(await crRow(monitor), crPause)
        let before = await crRow(monitor)
        let failures = await crCount(monitor, "credentialFailures")
        keychain.set(.denied)
        await monitor.sleep(); clock.move(wall: 3600, mono: 3600)
        await monitor.wake(); #expect(await monitor.settle())
        #expect(keychain.count() == 2)
        crExpectMessage(await crRow(monitor), crPause)
        #expect((await crRow(monitor))?.health == before?.health)
        #expect(await crCount(monitor, "credentialFailures") == failures)
        #expect(keychain.interactions() == [false, false])
        clock.move(mono: 30)
        await monitor.refresh(); #expect(await monitor.settle())
        crExpectMessage(await crRow(monitor), crDenied)
        #expect(await crCount(monitor, "credentialRechecks") == 2)
        await monitor.stop()
    }

    // Reproduces a failure fixed by R9: labels are not credential identity, for initial, Connect and re-check loads.
    @Test(arguments: [0, 1, 2])
    func labelEditKeepsPendingLoadAndOrigin(_ mode: Int) async {
        let clock = CRClock(), keychain = CRKeychain(), transport = CRTransport(), gate = CRGate()
        if mode == 1 { keychain.set(.found(crClaude(1))) }
        let ordinal = mode == 0 ? 1 : 2
        keychain.at(ordinal, CRRead(.found(crClaude(2)), gate: gate))
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile()])
        if mode != 0 {
            #expect(await monitor.settle())
            if mode == 1 { await monitor.reconnect("a") }
            else { clock.move(mono: 30); await monitor.refresh() }
        }
        #expect(await crWait { keychain.count() == ordinal })
        await monitor.setProfiles([crProfile(label: "Renamed")]); await crFlush()
        #expect(keychain.count() == ordinal)
        gate.release(); #expect(await monitor.settle())
        #expect(keychain.count() == ordinal)
        #expect((await crRow(monitor))?.profile.label == "Renamed")
        #expect((await crRow(monitor))?.snapshot?.accountLabel == "Renamed")
        #expect(await transport.count(token: 2) == 1)
        #expect(await crCount(monitor, "credentialResumes") == (mode == 2 ? 1 : 0))
        #expect(!gate.expired())
        await monitor.stop()
    }

    // Preserves an invariant (R9): label reconciliation of a failing re-check retains its silent origin and old cache.
    @Test func labelEditDoesNotTurnRecheckFailureIntoExplicitFailure() async {
        let clock = CRClock(), keychain = CRKeychain(.found(crClaude(1))), gate = CRGate()
        keychain.at(2, CRRead(.denied, gate: gate))
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: CRTransport([crResponse(401)]), recheckInterval: 30)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        clock.move(mono: 30); await monitor.refresh()
        #expect(await crWait { keychain.count() == 2 })
        await monitor.setProfiles([crProfile(label: "Renamed")])
        gate.release(); #expect(await monitor.settle())
        #expect(keychain.count() == 2)
        #expect((await crRow(monitor))?.profile.label == "Renamed")
        crExpectMessage(await crRow(monitor), crDenied)
        #expect(await crCount(monitor, "credentialFailures") == 0)
        #expect(await crCount(monitor, "credentialRechecks") == 1)
        await monitor.stop()
    }

    // Reproduces a failure fixed by R9: explicit sleep replay survives a label edit and stamps a new load instant.
    @Test(arguments: [false, true])
    func explicitSleepReplayKeepsNewLabelAndResetsCadence(_ existingBinding: Bool) async {
        let clock = CRClock(), keychain = CRKeychain(), gate = CRGate(), transport = CRTransport()
        if existingBinding { keychain.set(.found(crClaude(1))) }
        let ordinal = existingBinding ? 2 : 1
        keychain.at(ordinal, CRRead(.found(crClaude(2)), gate: gate))
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile()])
        if existingBinding { #expect(await monitor.settle()); await monitor.reconnect("a") }
        #expect(await crWait { keychain.count() == ordinal })
        await monitor.sleep()
        await monitor.setProfiles([crProfile(label: "After sleep")])
        clock.move(mono: 1000)
        gate.release(); #expect(await crWait { keychain.didFinish(ordinal) }); await crFlush()
        keychain.set(.denied)
        await monitor.wake(); #expect(await monitor.settle())
        #expect(keychain.count() == ordinal + 1)
        #expect((await crRow(monitor))?.profile.label == "After sleep")
        #expect(await crCount(monitor, "credentialRechecks") == 0)
        clock.move(mono: 29.75)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == ordinal + 1)
        clock.move(mono: 0.25)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == ordinal + 2)
        #expect(keychain.interactions().last == false)
        #expect(!gate.expired())
        await monitor.stop()
    }

    // New behaviour (R9): expiry must be checked at completion, for explicit and re-check origins.
    @Test(arguments: [false, true])
    func credentialExpiringDuringReadIsNeverBound(_ recheck: Bool) async {
        let clock = CRClock(), keychain = CRKeychain(), transport = CRTransport(), gate = CRGate()
        let expires = clock.wallNow().addingTimeInterval(1)
        let ordinal = recheck ? 2 : 1
        keychain.at(ordinal, CRRead(.found(crClaude(2, expires: expires)), gate: gate,
                                   afterRead: { clock.move(wall: 1) }))
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile()])
        if recheck { #expect(await monitor.settle()); clock.move(mono: 30); await monitor.refresh() }
        #expect(await crWait { keychain.count() == ordinal })
        gate.release(); #expect(await monitor.settle())
        #expect(await transport.count() == 0)
        #expect((await crRow(monitor))?.snapshot == nil)
        #expect((await crRow(monitor))?.health == .unauthenticated)
        crExpectMessage(await crRow(monitor), crPause)
        #expect(await crCount(monitor, "credentialResumes") == 0)
        #expect(await crCount(monitor, "credentialFailures") == 1)
        #expect(await crCount(monitor, "credentialRechecks") == (recheck ? 1 : 0))
        #expect(!gate.expired())
        await monitor.stop()
    }

    // Preserves an invariant (R8): expiry during an HTTP request waits for completion and retains the result.
    @Test func requestInFlightDefersExpiryPauseButKeepsCompletedSnapshot() async {
        let clock = CRClock(), keychain = CRKeychain(.found(crClaude(1, expires: Date(timeIntervalSince1970: 1_800_000_001))))
        let transport = CRTransport(deferred: true)
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile()])
        #expect(await crWait { await transport.count() == 1 })
        clock.move(wall: 1, mono: 30)
        await monitor.refresh(driver: .cycle)
        #expect(keychain.count() == 1)
        #expect((await crRow(monitor))?.health != .unauthenticated)
        await transport.answer(0, crResponse(percent: 67)); #expect(await monitor.settle())
        await monitor.refresh(driver: .internal)
        #expect((await crRow(monitor))?.health == .unauthenticated)
        #expect(crCachedPercent(await crRow(monitor)) == 67)
        crExpectMessage(await crRow(monitor), crPause)
        #expect(keychain.count() == 1)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(keychain.count() == 2)
        #expect(crCachedPercent(await crRow(monitor)) == 67)
        await monitor.stop(); await transport.finish()
    }
}
