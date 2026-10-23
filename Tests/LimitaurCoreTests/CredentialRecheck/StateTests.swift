import Foundation
import Testing
@testable import LimitaurCore

@Suite struct CredentialRecheckStateTests {
    // New behaviour (R1/R3): initial denial recovers without Connect and the failed read isn't a credential failure.
    @Test func initialDenialSilentlyRetriesThenResumes() async {
        let clock = CRClock(), keychain = CRKeychain(), transport = CRTransport()
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        #expect((await crRow(monitor))?.health == .unauthenticated)
        #expect(await crCount(monitor, "credentialFailures") == 1)
        clock.move(mono: 30)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await crCount(monitor, "credentialFailures") == 1)
        #expect(await transport.count() == 0)
        keychain.set(.found(crClaude(2)))
        clock.move(mono: 30)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect((await crRow(monitor))?.health == .healthy)
        #expect(crCachedPercent(await crRow(monitor)) == 25)
        #expect(await crCount(monitor, "credentialRechecks") == 2)
        #expect(await crCount(monitor, "credentialResumes") == 1)
        #expect(await transport.count(token: 2) == 1)
        #expect(keychain.interactions() == [false, false, false])
        await monitor.stop()
    }

    // New behaviour (R1/R11): denied/other results toggle only the two specified messages on a binding.
    @Test func denialAndOtherFailuresOnlyChangePauseMessage() async {
        let clock = CRClock(), keychain = CRKeychain(.found(crClaude(1))), transport = CRTransport([crResponse(403)])
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        crExpectMessage(await crRow(monitor), crPause)
        let before = await crRow(monitor)
        let failures = await crCount(monitor, "credentialFailures")
        keychain.set(.denied)
        clock.move(mono: 30)
        await monitor.refresh(); #expect(await monitor.settle())
        let denied = await crRow(monitor)
        crExpectMessage(denied, crDenied)
        #expect(denied?.health == before?.health)
        #expect(denied?.snapshotGeneration == before?.snapshotGeneration)
        // Malformed, missing, and expired are non-resuming and must restore the shared wording.
        keychain.set(.found(Data("malformed invented payload".utf8)))
        clock.move(mono: 30)
        await monitor.refresh(); #expect(await monitor.settle())
        crExpectMessage(await crRow(monitor), crPause)
        #expect(await crCount(monitor, "credentialFailures") == failures)
        #expect(await crCount(monitor, "credentialResumes") == 0)
        #expect(await transport.count() == 1)
        await monitor.stop()
    }

    // New behaviour (R1/R3): the same two-message transition applies when there is no binding/cache.
    @Test func unboundFailureMessagesTransitionWithoutChangingHealth() async {
        let clock = CRClock(), keychain = CRKeychain()
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: CRTransport(), recheckInterval: 30)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        crExpectMessage(await crRow(monitor), crDenied)
        keychain.set(.found(Data("malformed".utf8)))
        await monitor.manualRefresh(); #expect(await monitor.settle())
        crExpectMessage(await crRow(monitor), crPause)
        keychain.set(.denied)
        await monitor.manualRefresh(); #expect(await monitor.settle())
        crExpectMessage(await crRow(monitor), crDenied)
        #expect((await crRow(monitor))?.health == .unauthenticated)
        #expect((await crRow(monitor))?.snapshot == nil)
        #expect(await crCount(monitor, "credentialFailures") == 1)
        await monitor.stop()
    }

    // Reproduces a failure fixed by R2: a different token resumes once, immediately, without a <30s cycle duplicate.
    @Test func differentTokenResumesExactlyOnceAndRespectsNominalCadence() async {
        let clock = CRClock(), keychain = CRKeychain(.found(crClaude(1))), transport = CRTransport([crResponse(401)])
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        keychain.set(.found(crClaude(2)))
        clock.move(mono: 30)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await transport.count(token: 2) == 1)
        #expect(await crCount(monitor, "credentialResumes") == 1)
        #expect((await crRow(monitor))?.health == .healthy)
        for elapsed in [0.0, 29.0] {
            clock.move(mono: elapsed)
            await monitor.refresh(); #expect(await monitor.settle())
            #expect(await transport.count(token: 2) == 1)
        }
        clock.move(mono: 1)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await transport.count(token: 2) == 2)
        #expect(await crCount(monitor, "credentialResumes") == 1)
        await monitor.stop()
    }

    // Preserves an invariant (R5/R7): unchanged Codex token is never resent after 401, including manual refresh.
    @Test func sameCodexTokenStaysPausedThenDifferentTokenResumes() async {
        let clock = CRClock(), files = CRFiles(), transport = CRTransport([crResponse(401, codex: true)])
        files.set(crPath(1), crCodex(1))
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: CRKeychain()),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile(source: .codexFile(crPath(1)))]); #expect(await monitor.settle())
        files.set(crPath(1), crCodex(1)) // Rewrite bytes without changing access-token identity.
        clock.move(mono: 30)
        await monitor.refresh(); #expect(await monitor.settle())
        await monitor.manualRefresh(); #expect(await monitor.settle())
        #expect(await transport.count() == 1)
        #expect((await crRow(monitor))?.health == .unauthenticated)
        #expect(await crCount(monitor, "credentialResumes") == 0)
        files.set(crPath(1), crCodex(2))
        await monitor.manualRefresh(); #expect(await monitor.settle())
        #expect(await transport.count(token: 2) == 1)
        #expect(await crCount(monitor, "credentialResumes") == 1)
        await monitor.stop()
    }

    // Preserves an invariant (R5/R7, r5): changing the selected account cannot reuse a 401-rejected token.
    @Test func sameTokenWithDifferentSelectedAccountStaysPausedAfter401() async {
        let clock = CRClock(), files = CRFiles(), transport = CRTransport([crResponse(401, codex: true)])
        files.set(crPath(1), crCodex(1))
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: CRKeychain()),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile(source: .codexFile(crPath(1)))]); #expect(await monitor.settle())
        files.set(crPath(1), crCodex(1, account: "different-selected-account"))
        clock.move(mono: 30)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await transport.count(token: 1) == 1)
        #expect(await crCount(monitor, "credentialResumes") == 0)
        #expect((await crRow(monitor))?.health == .unauthenticated)
        await monitor.stop()
    }

    // New behaviour (R5): a loadFailed pause lifts on the same valid credential, without an immediate fetch.
    @Test func sameCredentialLiftsFailedLoadPause() async {
        let clock = CRClock(), keychain = CRKeychain(.found(crClaude(1))), transport = CRTransport()
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        keychain.set(.denied)
        await monitor.reconnect("a"); #expect(await monitor.settle())
        #expect((await crRow(monitor))?.health == .unauthenticated)
        keychain.set(.found(crClaude(1)))
        clock.move(mono: 30)
        let before = await transport.count()
        await monitor.refresh(); #expect(await monitor.settle())
        #expect((await crRow(monitor))?.health != .unauthenticated)
        #expect(await transport.count() == before)
        #expect(await crCount(monitor, "credentialResumes") == 0)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await transport.count() == before + 1)
        await monitor.stop()
    }

    // Preserves an invariant (R3): a local selected-account mismatch keeps old cache/binding intact.
    @Test func localExpectedAccountMismatchOnRecheckIsSilent() async {
        let clock = CRClock(), files = CRFiles(), transport = CRTransport([crResponse(codex: true), crResponse(401, codex: true)])
        files.set(crPath(1), crCodex(1))
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: CRKeychain()),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile(source: .codexFile(crPath(1)), expected: "selected")])
        #expect(await monitor.settle())
        clock.move(mono: 30)
        await monitor.refresh(); #expect(await monitor.settle())
        let old = await crRow(monitor)
        files.set(crPath(1), crCodex(2, account: "other"))
        clock.move(mono: 30)
        await monitor.refresh(); #expect(await monitor.settle())
        let next = await crRow(monitor)
        #expect(next?.health == old?.health)
        crExpectSameMessage(next, old)
        #expect(next?.snapshotGeneration == old?.snapshotGeneration)
        #expect(crCachedPercent(next) == 25)
        #expect(await transport.count() == 2)
        #expect(await crCount(monitor, "credentialFailures") == 0)
        #expect(await crCount(monitor, "credentialResumes") == 0)
        await monitor.stop()
    }

    // New behaviour (R7): a rejected server fingerprint is remembered for every removed subscriber.
    @Test(arguments: [false, true])
    func rejectedFingerprintIsSuppressedForEverySubscriber(_ expectedMismatch: Bool) async {
        let clock = CRClock(), files = CRFiles(), transport = CRTransport(deferred: true)
        files.set(crPath(1), crCodex(1))
        let expected: AccountID? = expectedMismatch ? "selected" : nil
        let profiles = [crProfile("a", source: .codexFile(crPath(1)), expected: expected),
                        crProfile("b", source: .codexFile(crPath(1)), expected: expected)]
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: CRKeychain()),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles(profiles)
        guard await crWait({ await transport.count() == 1 }) else {
            Issue.record("Initial request did not start"); await monitor.stop(); await transport.finish(); return
        }
        // A label update has no load side effect; wait until both profiles have left Connecting.
        #expect(await crWait {
            let rows = await monitor.display()
            return rows.profiles.count == 2 && rows.profiles.allSatisfy { $0.message != "Connecting account" }
        })
        await transport.answer(0, crResponse(verified: "wrong-account", codex: true))
        #expect(await monitor.settle())
        let rejectedRows = (await monitor.display()).profiles
        let allRejected = rejectedRows.allSatisfy { $0.health == Health.unauthenticated && $0.snapshot == nil }
        #expect(allRejected)
        clock.move(mono: 30)
        await monitor.refresh(); #expect(await monitor.settle())
        await monitor.refresh(); #expect(await monitor.settle()) // Other subscriber follows on the next pass.
        #expect(await transport.count() == 1)
        #expect(await crCount(monitor, "credentialRechecks") == 2)
        #expect(await crCount(monitor, "credentialResumes") == 0)
        files.set(crPath(1), crCodex(2))
        await monitor.manualRefresh()
        guard await crWait({ await transport.count(token: 2) == 1 }) else {
            Issue.record("Replacement credential did not request"); await monitor.stop(); await transport.finish(); return
        }
        await transport.answer(1, crResponse(verified: "selected", codex: true))
        #expect(await monitor.settle())
        #expect(await crCount(monitor, "credentialResumes") == 1)
        await monitor.stop(); await transport.finish()
    }

    // Preserves explicit-load behaviour (R6/R7): Connect can deliberately reuse a rejected fingerprint.
    @Test func connectCanBindRejectedFingerprint() async {
        let clock = CRClock(), files = CRFiles()
        files.set(crPath(1), crCodex(1))
        let transport = CRTransport([crResponse(verified: "wrong", codex: true), crResponse(verified: "selected", codex: true)])
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: CRKeychain()),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile(source: .codexFile(crPath(1)))]); #expect(await monitor.settle())
        await monitor.reconnect("a"); #expect(await monitor.settle())
        #expect(await transport.count(token: 1) == 2)
        #expect((await crRow(monitor))?.health == .healthy)
        #expect(await crCount(monitor, "credentialResumes") == 0)
        // Explicit binding must also clear rejected memory for future non-HTTP pauses.
        files.set(crPath(1), Data("malformed".utf8))
        await monitor.reconnect("a"); #expect(await monitor.settle())
        files.set(crPath(1), crCodex(1))
        await monitor.manualRefresh(); #expect(await monitor.settle())
        #expect((await crRow(monitor))?.health != .unauthenticated)
        #expect(await transport.count(token: 1) == 2)
        clock.move(mono: 30)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await transport.count(token: 1) == 3)
        await monitor.stop()
    }

    // New behaviour (R7): found-to-absent discovery uses exactly the fixed fallback path, noninteractively.
    @Test func keychainDisappearanceUsesFixedFallbackFile() async {
        let clock = CRClock(), files = CRFiles(), keychain = CRKeychain(.found(crClaude(1)))
        let transport = CRTransport([crResponse(401)])
        files.set(CredentialStore.defaultClaudePath, crClaude(2))
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: keychain),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        keychain.set(.notFound); clock.move(mono: 30)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(files.count() == 1)
        let onlyFallback = files.onlyRead(CredentialStore.defaultClaudePath)
        #expect(onlyFallback)
        #expect(keychain.interactions() == [false, false])
        #expect(await transport.count(token: 2) == 1)
        #expect(await crCount(monitor, "credentialResumes") == 1)
        await monitor.stop()
    }

    // Preserves an invariant (R4): a non-rebinding re-check cannot force another healthy subscriber to fetch.
    @Test func unchangedRecheckDoesNotForceHealthyAliasFetch() async {
        let clock = CRClock(), files = CRFiles(), keychain = CRKeychain(.found(crClaude(1)))
        files.set(crPath(2), crClaude(1))
        let transport = CRTransport()
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: keychain),
                              transport: transport, recheckInterval: 30)
        let profiles = [crProfile(), crProfile("b", source: .claudeFile(crPath(2)))]
        await monitor.setProfiles(profiles); #expect(await monitor.settle())
        keychain.set(.denied)
        await monitor.reconnect("a"); #expect(await monitor.settle())
        keychain.set(.found(crClaude(1)))
        // Put the healthy alias's ordinary request at t=129, re-check becomes due at t=130.
        clock.move(mono: 29)
        await monitor.dropdownOpened(); #expect(await monitor.settle())
        let before = await transport.count()
        clock.move(mono: 1)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await transport.count() == before)
        #expect(await crCount(monitor, "credentialRechecks") == 1)
        #expect(await crCount(monitor, "credentialResumes") == 0)
        await monitor.stop()
    }

    // Preserves an invariant (R10/R11): presentation is local and messages/statistics never expose credential material.
    @Test func presentationAndDiagnosticsRemainSanitized() async {
        let clock = CRClock(), files = CRFiles(), keychain = CRKeychain(.found(crClaude(17)))
        let transport = CRTransport([crResponse(401)])
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: keychain),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile("private-profile", source: .claudeDefaultDiscovery)])
        #expect(await monitor.settle())
        keychain.set(.denied); clock.move(mono: 30)
        await monitor.refresh(); #expect(await monitor.settle())
        let before = keychain.count(), requests = await transport.count()
        for count in [1, 3, 8] {
            let display = await monitor.displayOnly()
            var observations: [Int: SnapshotExpirations] = [:]
            _ = projectDisplay(display, count: count, wallNow: clock.wallNow(), monotonicNow: clock.monotonicNow(),
                               observations: &observations)
        }
        #expect(keychain.count() == before)
        #expect(await transport.count() == requests)
        let display = await monitor.display()
        let statistics = await monitor.statistics()
        let text = display.profiles.compactMap(\.message).joined(separator: " ") + String(describing: statistics)
        let fingerprint = Credential(accessToken: crToken(17), selectedAccountID: nil, expiresAt: nil).fingerprint
        let safe = ![crToken(17), fingerprint, crPath(17), CredentialStore.defaultClaudePath,
                     "private-profile", "claude:default"].contains { text.contains($0) }
        #expect(safe)
        // A configured path must also stay out of credential-load failure messages and aggregate keys.
        await monitor.setProfiles([crProfile(source: .claudeFile(crPath(17)))])
        #expect(await monitor.settle())
        let fileText = (await monitor.display()).profiles.compactMap(\.message).joined() + String(describing: await monitor.statistics())
        let fileSafe = !fileText.contains(crPath(17))
        #expect(fileSafe)
        await monitor.stop()
    }
}
