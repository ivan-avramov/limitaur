import Foundation
import Testing
@testable import LimitaurCore

@Suite struct CredentialRecheckThrottleCapacityTests {
    // Reproduces a failure fixed by R8/R2: expiry pausing precedes throttle/backoff guards; rotation carries the deadline.
    @Test(arguments: [429, 500])
    func idleExpiryIsNotHiddenByThrottleOrBackoff(_ status: Int) async {
        let clock = CRClock(), keychain = CRKeychain(.found(crClaude(1, expires: Date(timeIntervalSince1970: 1_800_000_001))))
        let transport = CRTransport([crResponse(), crResponse(status, retry: status == 429 ? "600" : nil)])
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: CRFiles(), keychain: keychain),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([crProfile()]); #expect(await monitor.settle())
        clock.move(mono: 30)
        await monitor.refresh(driver: .internal); #expect(await monitor.settle())
        #expect(await transport.count() == 2)
        clock.move(wall: 1)
        await monitor.refresh(driver: .internal)
        #expect((await crRow(monitor))?.health == .unauthenticated)
        crExpectMessage(await crRow(monitor), crPause)
        #expect(crCachedPercent(await crRow(monitor)) == 25)
        #expect(keychain.count() == 1) // Expiry pausing also runs for an internal driver.
        keychain.set(.found(crClaude(2)))
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await crCount(monitor, "credentialResumes") == 1)
        #expect(await transport.count(token: 2) == 0)
        let delay = status == 429 ? 600.0 : 30.0
        clock.move(mono: delay - 0.25)
        await monitor.manualRefresh(); #expect(await monitor.settle())
        #expect(await transport.count(token: 2) == 0)
        clock.move(mono: 0.25)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await transport.count(token: 2) == 1)
        await monitor.stop()
    }

    // Reproduces a failure fixed by R2: attachment keeps the later deadline regardless of which entity supplied it.
    @Test(arguments: [false, true])
    func attachmentUsesLaterOfBothThrottleDeadlines(_ oldIsLater: Bool) async {
        let clock = CRClock(), files = CRFiles()
        let keychain = CRKeychain(.found(crClaude(1, expires: clock.wallNow().addingTimeInterval(1))))
        files.set(crPath(2), crClaude(2))
        let transport = CRTransport([crResponse(429, retry: oldIsLater ? "600" : "120"),
                                     crResponse(429, retry: oldIsLater ? "120" : "600")])
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: keychain),
                              transport: transport, recheckInterval: 30)
        let a = crProfile(), b = crProfile("b", source: .claudeFile(crPath(2)))
        await monitor.setProfiles([a]); #expect(await monitor.settle())
        await monitor.setProfiles([a, b]); #expect(await monitor.settle())
        keychain.set(.found(crClaude(2))); clock.move(wall: 1, mono: 30)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await crCount(monitor, "credentialResumes") == 1)
        #expect(await transport.count() == 2)
        // Both original requests were at t=100; the later deadline is exactly t=700.
        clock.move(mono: 569.75)
        await monitor.manualRefresh(); #expect(await monitor.settle())
        #expect(await transport.count() == 2)
        clock.move(mono: 0.25)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await transport.count() == 3)
        await monitor.stop()
    }

    // Reproduces a failure fixed by R2: attach to in-flight entity sends nothing and its success cannot erase new throttle.
    @Test func attachmentDuringNormalRequestProtectsCarriedThrottle() async {
        let clock = CRClock(), files = CRFiles(), transport = CRTransport([crResponse(429, retry: "120")], deferred: true)
        let keychain = CRKeychain(.found(crClaude(1, expires: clock.wallNow().addingTimeInterval(1))))
        files.set(crPath(2), crClaude(2))
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: keychain),
                              transport: transport, recheckInterval: 30)
        let a = crProfile(), b = crProfile("b", source: .claudeFile(crPath(2)))
        await monitor.setProfiles([a]); #expect(await monitor.settle())
        await monitor.setProfiles([a, b])
        #expect(await crWait { await transport.count() == 2 })
        clock.move(wall: 1, mono: 30); keychain.set(.found(crClaude(2)))
        await monitor.refresh()
        #expect(await crWait { await crCount(monitor, "credentialResumes") == 1 })
        #expect(await transport.count() == 2)
        await transport.answer(1, crResponse()); #expect(await monitor.settle())
        let retryVisible = (await crRow(monitor))?.message?.contains("Retry after") == true
        #expect(retryVisible)
        await monitor.manualRefresh(); #expect(await monitor.settle())
        #expect(await transport.count() == 2)
        clock.move(mono: 89.75)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await transport.count() == 2)
        clock.move(mono: 0.25); await monitor.refresh()
        #expect(await crWait { await transport.count() == 3 })
        await transport.answer(2, crResponse()); #expect(await monitor.settle())
        await monitor.stop(); await transport.finish()
    }

    // Preserves an invariant (R2): joining a recently successful entity does not cause a duplicate request.
    @Test func attachmentWithinTenSecondsDoesNotFetchAgain() async {
        let clock = CRClock(), files = CRFiles(), keychain = CRKeychain(.found(crClaude(1)))
        files.set(crPath(2), crClaude(2))
        let transport = CRTransport([crResponse(401), crResponse()])
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: keychain),
                              transport: transport, recheckInterval: 30)
        let a = crProfile(), b = crProfile("b", source: .claudeFile(crPath(2)))
        await monitor.setProfiles([a]); #expect(await monitor.settle())
        clock.move(mono: 30)
        await monitor.setProfiles([a, b]); #expect(await monitor.settle())
        keychain.set(.found(crClaude(2)))
        clock.move(mono: 9.75)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await crCount(monitor, "credentialResumes") == 1)
        #expect(await transport.count(token: 2) == 1)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await transport.count(token: 2) == 1)
        await monitor.stop()
    }

    // Reproduces a failure fixed by R2: the alternate-credential dispatch protects a deadline carried in after dispatch.
    @Test func attachmentDuring401AlternateRequestProtectsCarriedThrottle() async {
        let clock = CRClock(), files = CRFiles(), transport = CRTransport(deferred: true)
        let keychain = CRKeychain(.found(crClaude(3, expires: clock.wallNow().addingTimeInterval(1))))
        files.set(crPath(1), crClaude(1)); files.set(crPath(2), crClaude(2))
        let a = crProfile("a", source: .claudeFile(crPath(1)))
        let b = crProfile("b", source: .claudeFile(crPath(2))), c = crProfile("c")
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: keychain),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([a])
        #expect(await crWait { await transport.count() == 1 })
        await transport.answer(0, crResponse(verified: "shared")); #expect(await monitor.settle())
        await monitor.setProfiles([a, b])
        #expect(await crWait { await transport.count() == 2 })
        await transport.answer(1, crResponse(verified: "shared")); #expect(await monitor.settle())
        await monitor.setProfiles([a, b, c])
        #expect(await crWait { await transport.count() == 3 })
        await transport.answer(2, crResponse(429, retry: "600")); #expect(await monitor.settle())
        clock.move(mono: 30)
        await monitor.refresh(driver: .internal)
        #expect(await crWait { await transport.count() == 4 })
        #expect(await transport.count(token: 1) == 2)
        await transport.answer(3, crResponse(401))
        #expect(await crWait { await transport.count() == 5 })
        #expect(await transport.count(token: 2) == 2)
        clock.move(wall: 1); keychain.set(.found(crClaude(2)))
        await monitor.refresh()
        #expect(await crWait { await crCount(monitor, "credentialResumes") == 1 })
        #expect(await transport.count() == 5)
        await transport.answer(4, crResponse(verified: "shared")); #expect(await monitor.settle())
        await monitor.manualRefresh(); #expect(await monitor.settle())
        #expect(await transport.count() == 5)
        clock.move(mono: 569.75)
        await monitor.refresh(); #expect(await monitor.settle())
        #expect(await transport.count() == 5)
        clock.move(mono: 0.25); await monitor.refresh()
        #expect(await crWait { await transport.count() == 6 })
        await transport.answer(5, crResponse(verified: "shared")); #expect(await monitor.settle())
        await monitor.stop(); await transport.finish()
    }

    // Reproduces a failure fixed by R2: merge preserves the resumed request's later last-attempt instant.
    @Test func resumedMergeJustBeforeTickDoesNotDispatchTwice() async {
        let clock = CRClock(), files = CRFiles(), keychain = CRKeychain(.found(crClaude(2)))
        files.set(crPath(1), crClaude(1))
        let transport = CRTransport(deferred: true)
        let a = crProfile("a", source: .claudeFile(crPath(1))), b = crProfile("b")
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: keychain),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([a])
        #expect(await crWait { await transport.count() == 1 })
        await transport.answer(0, crResponse(verified: "shared")); #expect(await monitor.settle())
        await monitor.setProfiles([a, b])
        #expect(await crWait { await transport.count() == 2 })
        await transport.answer(1, crResponse(401)); #expect(await monitor.settle())
        clock.move(mono: 30); await monitor.refresh(driver: .internal)
        #expect(await crWait { await transport.count() == 3 })
        await transport.answer(2, crResponse(verified: "shared")); #expect(await monitor.settle())
        clock.move(mono: 29); keychain.set(.found(crClaude(3)))
        await monitor.refresh()
        #expect(await crWait { await transport.count(token: 3) == 1 })
        await transport.answer(3, crResponse(verified: "shared")); #expect(await monitor.settle())
        clock.move(mono: 1); await monitor.refresh(); #expect(await monitor.settle())
        #expect(await transport.count() == 4)
        #expect(await crCount(monitor, "credentialResumes") == 1)
        clock.move(mono: 29); await monitor.refresh()
        #expect(await crWait { await transport.count() == 5 })
        await transport.answer(4, crResponse(verified: "shared")); #expect(await monitor.settle())
        await monitor.stop(); await transport.finish()
    }

    // New behaviour (R3/R10): capacity preflight counts a freed sole-owner slot; a retained throttle prevents freeing it.
    @Test(arguments: [false, true])
    func capacityBoundaryPreservesOldBindingOrFreesItsSlot(_ retainThrottle: Bool) async {
        let clock = CRClock(), files = CRFiles(), transport = CRTransport()
        let keychain = CRKeychain(.found(crClaude(1, expires: clock.wallNow().addingTimeInterval(1))))
        let monitor: Monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: keychain),
                              transport: transport, recheckInterval: 30)
        var profiles = [crProfile()]
        for index in 0..<255 {
            files.set(crPath(1000 + index), crClaude(1000 + index))
            profiles.append(crProfile("filler-\(index)", source: .claudeFile(crPath(1000 + index))))
        }
        await monitor.setProfiles(profiles); #expect(await monitor.settle())
        #expect((await monitor.display()).profiles.count == 256)
        #expect(await transport.count() == 256)
        if retainThrottle {
            await transport.reply(token: 1, with: [crResponse(429, retry: "600")])
            clock.move(mono: 30)
            await monitor.refresh(driver: .internal); #expect(await monitor.settle())
        } else { clock.move(mono: 30) }
        clock.move(wall: 1)
        await monitor.refresh(driver: .internal); #expect(await monitor.settle())
        let old = await crRow(monitor)
        #expect(old?.health == .unauthenticated)
        #expect(crCachedPercent(old) == 25)
        keychain.set(.found(crClaude(2)))
        await monitor.refresh(); #expect(await monitor.settle())
        if retainThrottle {
            let after = await crRow(monitor)
            #expect(after?.health == old?.health)
            crExpectSameMessage(after, old)
            #expect(after?.snapshotGeneration == old?.snapshotGeneration)
            #expect(crCachedPercent(after) == 25)
            #expect(await crCount(monitor, "credentialResumes") == 0)
            #expect(await transport.count(token: 2) == 0)
            // A distinct profile failing for capacity is .unavailable and must never join re-check cadence.
            files.set(crPath(9999), crClaude(9999))
            profiles.append(crProfile("overflow", source: .claudeFile(crPath(9999))))
            await monitor.setProfiles(profiles); #expect(await monitor.settle())
            #expect((await crRow(monitor, "overflow"))?.health == .unavailable)
            clock.move(mono: 30)
            await monitor.manualRefresh(); #expect(await monitor.settle())
            #expect(files.count(crPath(9999)) == 1)
        } else {
            #expect((await crRow(monitor))?.health == .healthy)
            #expect(await crCount(monitor, "credentialResumes") == 1)
            #expect(await transport.count(token: 2) == 1)
        }
        #expect(await crCount(monitor, "credentialFailures") == 0)
        await monitor.stop()
    }
}
