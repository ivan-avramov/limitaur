import Foundation
import Testing
@testable import LimitaurCore

@Suite struct SessionContinuityBEventTests {
    // New behaviour B6: only a decoded, stored cycle success earns a clean poll.
    @Test func currentCycleSuccessCountsAndCanReduce() async throws {
        var p = try bPolicy(change: -86_400); bPrime(&p)
        try await bWithRig { rig in
            try await rig.start(policies: ["codex": p])
            #expect(try await rig.policy().consecutiveClean == 4)
            try await rig.reply(at: 48.5, index: 1, response: bSuccess())
            #expect(try await rig.policy().interval == 40)
            #expect(try await rig.policy().consecutiveClean == 0)
            #expect(try await rig.policy().lastChange == bDate(48.5))
        }
    }

    // Invariant B2/B6: forced successes neither increment nor reset an existing streak.
    @Test(arguments: [0, 1, 2, 3]) func forcedSuccessDoesNotCountOrReset(_ variant: Int) async throws {
        var p = try bPolicy(change: -86_400); bPrime(&p)
        try await bWithRig { rig in
            try await rig.start(policies: ["codex": p])
            rig.clock.set(10)
            switch variant {
            case 0: await rig.monitor.manualRefresh()
            case 1: await rig.monitor.dropdownOpened()
            case 2: await rig.monitor.refresh(force: true, driver: .internal)
            default: await rig.monitor.sleep(); await rig.monitor.wake()
            }
            try #require(await bWait { await rig.transport.count() == 2 })
            await rig.transport.answer(1, bSuccess()); #expect(await rig.monitor.settle())
            #expect(try await rig.policy().consecutiveClean == 4)
            #expect(try await rig.policy().interval == 50)
            try await rig.reply(at: 60, index: 2, response: bSuccess())
            #expect(try await rig.policy().interval == 40)
        }
    }

    // Invariant B2: a request sent before activation is not retroactively called clean.
    @Test func preActivationCycleSuccessDoesNotCountOrReset() async throws {
        try await bWithRig { rig in
            try await rig.start(policies: nil)
            try await rig.request(at: 30, index: 1)
            var p = try bPolicy(change: -86_400); bPrime(&p)
            await rig.monitor.setPolling(["codex": p])
            await rig.transport.answer(1, bSuccess()); #expect(await rig.monitor.settle())
            #expect(try await rig.policy().consecutiveClean == 4)
            #expect(try await rig.policy().interval == 50)
        }
    }

    // Invariant B2/B6: all non-429 failures break the streak, even for forced requests.
    @Test(arguments: Array(0..<8)) func failuresResetCleanStreak(_ variant: Int) async throws {
        var p = try bPolicy(change: -86_400); bPrime(&p)
        try await bWithRig { rig in
            try await rig.start(policies: ["codex": p])
            try await rig.request(at: 50, index: 1, driver: .manual, force: true)
            let replies = [bResponse(200, body: "{invalid"), bResponse(401), bResponse(403),
                           bResponse(500), bResponse(503), bResponse(404), bResponse(200),
                           bResponse(200, body: "{\"account_id\":\"wrong\",\"rate_limit\":{\"primary_window\":{\"used_percent\":30}}}")]
            if variant == 6 { await rig.transport.fail(1) }
            else { await rig.transport.answer(1, replies[variant]) }
            #expect(await rig.monitor.settle())
            #expect(try await rig.policy().consecutiveClean == 0)
            #expect(try await rig.policy().interval == 50)
            #expect(try await rig.policy().lastChange == bDate(-86_400))
        }
    }

    // Reproduces B6's fixed failure: receipt alone must not erase clean history or learn a 429.
    @Test func sameTokenRecordsOnlyAfterReadAndUsesReceiptTime() async throws {
        var p = try bPolicy(change: -100); bPrime(&p)
        try await bWithRig { rig in
            try await rig.start(policies: ["codex": p])
            try await rig.reply(at: 50, index: 1, response: bResponse(429, retry: "95"))
            #expect(try await rig.policy().interval == 50)
            #expect(try await rig.policy().consecutiveClean == 4)
            let gate = BGate(); defer { gate.release() }
            rig.files.enqueue(bPath(), BRead(value: bToken(), gate: gate))
            await rig.monitor.refresh()
            try #require(await bWait { rig.files.count(bPath()) == 2 })
            #expect(try await rig.policy().interval == 50)
            rig.clock.set(70); gate.release(); #expect(await rig.monitor.settle())
            #expect(try await rig.policy().interval == 100)
            #expect(try await rig.policy().lastChange == bDate(50))
            #expect(try await rig.policy().consecutiveClean == 0); #expect(!gate.didExpire())
        }
    }

    // New behaviour B6: attribution delay must not move a 59-minute signal outside the revert window.
    @Test(arguments: [false, true]) func delayedReadStillRevertsUsingReceiptTime(_ withRetry: Bool) async throws {
        try await bWithRig { rig in
            try await rig.start(policies: ["codex": bReduced()])
            try await rig.reply(at: 3_540, index: 1, response: bResponse(429, retry: withRetry ? "95" : nil))
            let gate = BGate(); defer { gate.release() }
            rig.files.enqueue(bPath(), BRead(value: bToken(), gate: gate))
            await rig.monitor.refresh(); try #require(await bWait { rig.files.count(bPath()) == 2 })
            rig.clock.set(3_610); gate.release(); #expect(await rig.monitor.settle())
            let p = try await rig.policy()
            #expect(p.interval == (withRetry ? 100 : 50)); #expect(p.lastChange == bDate(3_540))
            #expect(p.blockedUntil[40] == bDate(3_540 + 604_800)); #expect(p.lastReduction == nil)
            #expect(!gate.didExpire())
        }
    }

    // Reproduces B6's fixed failure: stale-token throttles must not ratchet provider cadence.
    @Test func rotationDiscardsThrottleButKeepsProviderDeadline() async throws {
        var p = try bPolicy(change: -100); bPrime(&p)
        try await bWithRig { rig in
            try await rig.start(policies: ["codex": p])
            try await rig.reply(at: 50, index: 1, response: bResponse(429, retry: "95"))
            let deadline = await rig.monitor.throttleDeadline(for: "a")
            rig.files.set(bPath(), bToken(2)); await rig.monitor.refresh()
            #expect(await rig.monitor.settle())
            #expect(try await rig.policy().interval == 50); #expect(try await rig.policy().lastChange == bDate(-100))
            #expect(try await rig.policy().consecutiveClean == 4)
            #expect(await rig.monitor.throttleDeadline(for: "a") == deadline)
            #expect(await rig.transport.count() == 2)
            rig.clock.set(144.999); await rig.monitor.manualRefresh()
            #expect(await rig.monitor.settle()); #expect(await rig.transport.count() == 2)
        }
    }

    // New behaviour B2: a failed re-read is an attribution decision, not an indefinite deferral.
    @Test func missingCredentialRecordsPendingThrottle() async throws {
        try await bWithRig { rig in
            try await rig.start()
            try await rig.reply(at: 50, index: 1, response: bResponse(429, retry: "95"))
            rig.files.enqueue(bPath(), BRead(value: nil))
            await rig.monitor.refresh(); #expect(await rig.monitor.settle())
            #expect(try await rig.policy().interval == 100)
            #expect(try await rig.policy().lastChange == bDate(50))
        }
    }

    // New behaviour B6: completion order, not profile order, decides a shared-fingerprint signal once.
    @Test(arguments: [false, true]) func firstCompletingSubscriberDecides(_ rotationFirst: Bool) async throws {
        try await bWithRig { rig in
            try await rig.start(profiles: [bProfile("a"), bProfile("b")], tokens: [1, 1])
            try await rig.reply(at: 50, index: 1, response: bResponse(429, retry: "95"))
            let same = BGate(), rotated = BGate(); defer { same.release(); rotated.release() }
            rig.files.enqueue(bPath("a"), BRead(value: bToken(), gate: same))
            rig.files.enqueue(bPath("b"), BRead(value: bToken(2), gate: rotated))
            await rig.monitor.refresh()
            try #require(await bWait { rig.files.count(bPath("a")) == 2 && rig.files.count(bPath("b")) == 2 })
            if rotationFirst {
                rotated.release()
                try #require(await bWait { (await rig.monitor.statistics())["__eligibility"]?["credentialRotations"] == 1 })
            } else {
                same.release()
                try #require(await bWait { (await rig.monitor.display()).polling["codex"]?.interval == 100 })
            }
            #expect(try await rig.policy().interval == (rotationFirst ? 50 : 100))
            same.release(); rotated.release(); #expect(await rig.monitor.settle())
            #expect(try await rig.policy().interval == (rotationFirst ? 50 : 100))
            #expect(!same.didExpire()); #expect(!rotated.didExpire())
        }
    }

    // New behaviour B6: replacement commits the older pending receipt before retaining the newer one.
    @Test func replacementRecordsOldPendingWithItsOwnReceipt() async throws {
        try await bWithRig { rig in
            try await rig.start()
            try await rig.request(at: 10, index: 1, driver: .internal, force: true)
            await rig.transport.answer(1, bResponse(429)); #expect(await rig.monitor.settle())
            #expect(try await rig.policy().interval == 50)
            try await rig.request(at: 40, index: 2, driver: .internal, force: true)
            await rig.transport.answer(2, bResponse(429)); #expect(await rig.monitor.settle())
            #expect(try await rig.policy().interval == 60)
            #expect(try await rig.policy().lastChange == bDate(10))
            await rig.monitor.refresh(); #expect(await rig.monitor.settle())
            #expect(try await rig.policy().interval == 70)
            #expect(try await rig.policy().lastChange == bDate(40))
        }
    }

    // New behaviour B2/B6: the 60 s fallback is inclusive and records exactly once without a read completing.
    @Test func pendingFallbackAtSixtySeconds() async throws {
        try await bWithRig { rig in
            try await rig.start()
            try await rig.reply(at: 50, index: 1, response: bResponse(429, retry: "95"))
            let gate = BGate(); defer { gate.release() }
            rig.files.enqueue(bPath(), BRead(value: bToken(), gate: gate))
            await rig.monitor.refresh(); try #require(await bWait { rig.files.count(bPath()) == 2 })
            rig.clock.set(109.999); await rig.monitor.refresh()
            #expect(try await rig.policy().interval == 50)
            rig.clock.set(110); await rig.monitor.refresh()
            #expect(try await rig.policy().interval == 100)
            #expect(try await rig.policy().lastChange == bDate(50))
            rig.clock.set(111); gate.release(); #expect(await rig.monitor.settle())
            await rig.monitor.refresh(); #expect(await rig.monitor.settle())
            #expect(try await rig.policy().interval == 100)
            #expect(try await rig.policy().lastChange == bDate(50)); #expect(!gate.didExpire())
        }
    }

    // Invariant B2: baseline mode learns immediately; an inactive provider never gains a policy.
    @Test(arguments: [false, true]) func immediateAttributionOrNoPolicy(_ active: Bool) async throws {
        try await bWithRig(BRig(reactive: false)) { rig in
            try await rig.start(policies: active ? ["codex": PollingPolicy()] : nil)
            try await rig.reply(at: 50, index: 1, response: bResponse(429, retry: "95"))
            if active {
                #expect(try await rig.policy().interval == 100)
                #expect(try await rig.policy().lastChange == bDate(50))
            } else { #expect((await rig.monitor.display()).polling.isEmpty) }
        }
    }

    // Invariant B2/B6: any pending entity prevents a provider-wide reduction, but preserves the count.
    @Test func fifthCleanWhileAnotherEntityHasPendingThrottleCannotReduce() async throws {
        var p = try bPolicy(change: -86_400); bPrime(&p)
        try await bWithRig { rig in
            try await rig.start(policies: ["codex": p], profiles: [bProfile("a"), bProfile("b")], tokens: [1, 2])
            rig.clock.set(50); await rig.monitor.refresh()
            try #require(await bWait { await rig.transport.count() == 4 })
            // Either request may be the throttled entity; both belong to the same provider.
            await rig.transport.answer(2, bResponse(429, retry: "95"))
            try #require(await bWait { (await rig.monitor.statistics())["codex"]?["throttled"] == 1 })
            await rig.transport.answer(3, bSuccess()); #expect(await rig.monitor.settle())
            #expect(try await rig.policy().interval == 50)
            #expect(try await rig.policy().consecutiveClean == 5)
        }
    }

    // Invariant B2: a sibling's interval change invalidates an older in-flight cycle's clean credit.
    @Test func oldDispatchIntervalSuccessNeitherCountsNorResets() async throws {
        try await bWithRig(BRig(reactive: false)) { rig in
            try await rig.start(profiles: [bProfile("a"), bProfile("b"), bProfile("c")], tokens: [1, 2, 3])
            rig.clock.set(50); await rig.monitor.refresh()
            try #require(await bWait { await rig.transport.count() == 6 })
            await rig.transport.answer(3, bResponse(429))
            try #require(await bWait { (await rig.monitor.display()).polling["codex"]?.interval == 60 })
            // Only the throttled entity is free to send under the new interval;
            // the other two remain in flight under 50. Build a nonzero new streak.
            try await rig.request(at: 108.5, index: 6)
            await rig.transport.answer(6, bSuccess())
            try #require(await bWait { (await rig.monitor.display()).polling["codex"]?.consecutiveClean == 1 })
            await rig.transport.answer(4, bSuccess()); await rig.transport.answer(5, bSuccess())
            #expect(await rig.monitor.settle())
            #expect(try await rig.policy().interval == 60); #expect(try await rig.policy().consecutiveClean == 1)
        }
    }

    // Invariant B6: a 401 alternate request is forced and earns no clean credit.
    @Test func alternateCredentialSuccessDoesNotCount() async throws {
        try await bWithRig { rig in
            try await rig.start(profiles: [bProfile("a"), bProfile("b")], tokens: [1, 2], verified: true)
            try await rig.request(at: 50, index: 2)
            await rig.transport.answer(2, bResponse(401))
            try #require(await bWait { await rig.transport.count() == 4 })
            await rig.transport.answer(3, bSuccess(verified: true)); #expect(await rig.monitor.settle())
            #expect(try await rig.policy().consecutiveClean == 0)
            #expect(try await rig.policy().interval == 50)
        }
    }
}
