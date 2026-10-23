import Testing
import LimitaurCore

@Suite struct ThrottleFreshnessLifecycle {
    // Invariant, R2: neither force nor UI refresh can bypass Retry-After; equality is due.
    @Test func requestSchedulingIsUnchanged() async throws {
        let rig = TFRig(); try await rig.retained()
        for age in [75.0, 90, 99.999] {
            rig.clock.set(age)
            await rig.monitor.refresh()
            await rig.monitor.manualRefresh()
            await rig.monitor.dropdownOpened()
            #expect(await rig.monitor.settle())
            #expect(await rig.transport.count() == 2)
        }
        rig.clock.set(100); await rig.monitor.refresh()
        #expect(await rig.transport.wait(3))
        await rig.monitor.refresh(); await rig.monitor.manualRefresh()
        await rig.transport.answer(2, tfSuccess(42))
        #expect(await rig.monitor.settle())
        #expect(await rig.transport.count() == 3)
        await rig.close()
    }

    // New behaviour, R6: a phased request bridges retention expiry and success renews it.
    @Test func inFlightAcrossRetentionThenSuccess() async throws {
        let rig = TFRig(); try await rig.retained()
        rig.clock.set(148); await rig.monitor.refresh()
        try #require(await rig.transport.wait(3))
        let pending = await rig.display(at: 152)
        #expect(pending.selected.count == 1)
        #expect(pending.profiles.first?.freshnessDeadline == TFClock.origin + 300)
        #expect(pending.nextDisplayDeadline == TFClock.origin + 300)
        #expect(pending.profiles.first?.health == .throttled)
        rig.clock.set(154); await rig.transport.answer(2, tfSuccess(42))
        #expect(await rig.monitor.settle())
        let renewed = await rig.monitor.display()
        #expect(renewed.selected.first?.metric.usedPercent == 42)
        #expect(renewed.profiles.first?.health == .healthy)
        #expect(renewed.profiles.first?.fetchedAge == 0)
        #expect(renewed.profiles.first?.freshnessDeadline == TFClock.origin + 244)
        #expect(renewed.profiles.first?.message == nil)
        #expect((await rig.display(at: 243.999)).selected.count == 1)
        #expect((await rig.display(at: 244)).selected.isEmpty)
        await rig.close()
    }

    // New behaviour, R6: once a late transport failure completes, the bridge ends immediately.
    @Test func inFlightAcrossRetentionThenFailure() async throws {
        let rig = TFRig(); try await rig.retained()
        rig.clock.set(148); await rig.monitor.refresh()
        try #require(await rig.transport.wait(3))
        #expect((await rig.display(at: 152)).selected.count == 1)
        rig.clock.set(154); await rig.transport.fail(2)
        #expect(await rig.monitor.settle())
        let failed = await rig.monitor.display()
        #expect(failed.selected.isEmpty)
        #expect(failed.profiles.first?.health == .failed)
        #expect(failed.profiles.first?.message?.contains("Cached usage stale") == true)
        await rig.close()
    }

    // New behaviour, failure path line 66: an early failure keeps only the original allowance.
    @Test func earlyFailureKeepsLatchedDeadline() async throws {
        let rig = TFRig(); try await rig.retained()
        try await rig.reply(at: 135, index: 2, nil)
        let before = await rig.display(at: 148)
        #expect(before.selected.count == 1)
        #expect(before.profiles.first?.health == .failed)
        #expect(before.profiles.first?.message?.contains("Cached usage stale") == false)
        #expect(before.nextDisplayDeadline == TFClock.origin + 148.5)
        #expect((await rig.display(at: 148.5)).selected.isEmpty)
        await rig.close()
    }

    // New behaviour, R7: repeated provider throttles extend only to the original success cap.
    @Test func secondThrottleBeforeRenewalUsesOriginalCap() async throws {
        let rig = TFRig(); try await rig.retained()
        try await rig.reply(at: 135, index: 2, tfResponse(429, retry: "300"))
        #expect((await rig.display(at: 299.999)).selected.count == 1)
        let due = await rig.display(at: 300)
        #expect(due.selected.isEmpty)
        #expect(due.profiles.first?.freshnessDeadline == TFClock.origin + 300)
        rig.clock.set(434.999); await rig.monitor.manualRefresh()
        #expect(await rig.monitor.settle())
        #expect(await rig.transport.count() == 3)
        rig.clock.set(435); await rig.monitor.refresh()
        #expect(await rig.transport.wait(4))
        await rig.transport.fail(3); #expect(await rig.monitor.settle())
        await rig.close()
    }

    // New behaviour, R7: renewal replaces both old snapshot age and its 300-second cap.
    @Test func secondThrottleAfterRenewalUsesNewCap() async throws {
        let rig = TFRig(); try await rig.retained()
        try await rig.reply(at: 100, index: 2, tfSuccess(42))
        try await rig.reply(at: 145, index: 3, tfResponse(429, retry: "3600"))
        #expect((await rig.display(at: 300)).selected.first?.metric.usedPercent == 42)
        let before = await rig.display(at: 399.999)
        #expect(before.selected.count == 1)
        #expect(before.profiles.first?.freshnessDeadline == TFClock.origin + 400)
        #expect((await rig.display(at: 400)).selected.isEmpty)
        await rig.close()
    }

    // Invariant, success path: success clears provider retention even before its old deadline.
    @Test func renewedSuccessDoesNotInheritOldRetention() async throws {
        let rig = TFRig(); try await rig.retained(retry: "150", at: 30)
        try await rig.reply(at: 180, index: 2, tfSuccess(42))
        let renewed = await rig.monitor.display()
        #expect(renewed.profiles.first?.freshnessDeadline == TFClock.origin + 270)
        #expect((await rig.display(at: 269.999)).selected.count == 1)
        await rig.monitor.refresh()
        try #require(await rig.transport.wait(4))
        // Old retention must not activate the in-flight bridge for this ordinary retry.
        #expect((await rig.display(at: 270)).selected.isEmpty)
        #expect((await rig.display(at: 271)).selected.isEmpty)
        await rig.transport.fail(3); #expect(await rig.monitor.settle())
        await rig.close()
    }

    // New behaviour, R3/helper line 39: even an outstanding retry cannot bridge the cap.
    @Test func inFlightAtCapEquality() async throws {
        let rig = TFRig(); try await rig.retained(retry: "200", at: 30)
        rig.clock.set(230); await rig.monitor.refresh()
        try #require(await rig.transport.wait(3))
        #expect((await rig.display(at: 299.999)).selected.count == 1)
        #expect((await rig.display(at: 300)).selected.isEmpty)
        rig.clock.set(301); await rig.transport.fail(2)
        #expect(await rig.monitor.settle())
        #expect((await rig.monitor.display()).selected.isEmpty)
        await rig.close()
    }

    // New behaviour, r5/R5: the pre-response in-flight hold allows a repeat 429 to re-latch.
    @Test func secondThrottleAtRetentionEqualityRelatches() async throws {
        let rig = TFRig(); try await rig.retained()
        rig.clock.set(135); await rig.monitor.refresh()
        try #require(await rig.transport.wait(3))
        #expect((await rig.display(at: 148.5)).selected.count == 1)
        await rig.transport.answer(2, tfResponse(429, retry: "55"))
        #expect(await rig.monitor.settle())
        let relatched = await rig.monitor.display()
        #expect(relatched.selected.count == 1)
        #expect(relatched.profiles.first?.health == .throttled)
        #expect(relatched.profiles.first?.message?.contains("Cached usage stale") == false)
        #expect(relatched.profiles.first?.freshnessDeadline == TFClock.origin + 252)
        #expect((await rig.display(at: 251.999)).selected.count == 1)
        #expect((await rig.display(at: 252)).selected.isEmpty)
        await rig.close()
    }

    // Invariant, r5/R5: without a pre-response hold, a late request's 429 cannot latch.
    @Test func secondThrottleAfterRetentionExpiryCannotLatch() async throws {
        let rig = TFRig(); try await rig.retained()
        #expect((await rig.display(at: 148.5)).selected.isEmpty)
        rig.clock.set(150); await rig.monitor.refresh()
        try #require(await rig.transport.wait(3))
        #expect((await rig.monitor.display()).selected.isEmpty)
        rig.clock.set(151); await rig.transport.answer(2, tfResponse(429, retry: "55"))
        #expect(await rig.monitor.settle())
        #expect((await rig.monitor.display()).selected.isEmpty)
        #expect((await rig.display(at: 254.499)).selected.isEmpty)
        #expect((await rig.display(at: 254.5)).selected.isEmpty)
        await rig.close()
    }

    // Invariant, r4/R5: a request dispatched after retention expires cannot restore the snapshot.
    @Test func requestAfterRetentionExpiryCannotResurrect() async throws {
        let rig = TFRig(); try await rig.retained()
        #expect((await rig.display(at: 148.5)).selected.isEmpty)
        rig.clock.set(152); await rig.monitor.refresh()
        try #require(await rig.transport.wait(3))
        #expect((await rig.display(at: 153)).selected.isEmpty)
        rig.clock.set(154); await rig.transport.answer(2, tfResponse(429, retry: "300"))
        #expect(await rig.monitor.settle())
        #expect((await rig.monitor.display()).selected.isEmpty)
        await rig.close()
    }

    // New behaviour, r5/R6: a 401 ends the hold even while an alternate credential is fetching.
    @Test func alternateCredentialRequestDoesNotInheritHold() async throws {
        let rig = TFRig(sources: ["/tf/a": tfToken("a"), "/tf/b": tfToken("b")])
        let a = tfProfile("a", path: "/tf/a"), b = tfProfile("b", path: "/tf/b")
        try await rig.start([a], response: tfSuccess(88, verified: true))
        await rig.monitor.setProfiles([a, b])
        try #require(await rig.transport.wait(2))
        await rig.transport.answer(1, tfSuccess(88, verified: true))
        try #require(await rig.monitor.settle())
        try await rig.reply(at: 45, index: 2, tfResponse(429, retry: "55"))
        rig.clock.set(148); await rig.monitor.refresh()
        try #require(await rig.transport.wait(4))
        #expect((await rig.display(at: 150)).selected.count == 1)
        await rig.transport.answer(3, tfResponse(401))
        try #require(await rig.transport.wait(5), "The alternate credential must actually dispatch")
        let alternateInFlight = await rig.monitor.display()
        #expect(alternateInFlight.selected.isEmpty)
        #expect(alternateInFlight.profiles.allSatisfy { $0.message?.contains("Cached usage stale") == true })
        #expect((await rig.display(at: 151)).selected.isEmpty)
        rig.clock.set(152); await rig.transport.answer(4, tfSuccess(42, verified: true))
        #expect(await rig.monitor.settle())
        #expect((await rig.monitor.display()).selected.first?.metric.usedPercent == 42)
        #expect(await rig.transport.count() == 5)
        await rig.close()
    }

    // Invariant, clearing rule line 30: account mismatch cannot retain the old account's data.
    @Test func accountMismatchClearsRetainedSnapshot() async throws {
        let rig = TFRig(); try await rig.retained()
        try await rig.reply(at: 100, index: 2,
                            tfResponse(200, body: #"{"account_id":"different","rate_limit":{"primary_window":{"used_percent":99}}}"#))
        let rejected = await rig.monitor.display()
        #expect(rejected.selected.isEmpty)
        #expect(rejected.candidates.isEmpty)
        #expect(rejected.profiles.first?.snapshot == nil)
        #expect(rejected.profiles.first?.fetchedAge == nil)
        #expect(rejected.profiles.first?.freshnessDeadline == nil)
        #expect(rejected.profiles.first?.health == .unauthenticated)
        await rig.close()
    }

    // New behaviour, clock/sleep rules: sleep preserves the allowance; wake obeys throttle.
    @Test func sleepWakeDuringRetention() async throws {
        let rig = TFRig(); try await rig.retained()
        rig.clock.set(60); await rig.monitor.sleep()
        rig.clock.set(95); await rig.monitor.refresh(); await rig.monitor.wake()
        #expect(await rig.monitor.settle())
        #expect(await rig.transport.count() == 2)
        let awake = await rig.monitor.display()
        #expect(awake.selected.count == 1)
        #expect(awake.profiles.first?.health == .throttled)
        #expect(awake.profiles.first?.fetchedAge == 95)
        #expect(awake.profiles.first?.freshnessDeadline == TFClock.origin + 148.5)
        rig.clock.set(100); await rig.monitor.refresh()
        #expect(await rig.transport.wait(3))
        await rig.transport.answer(2, tfSuccess(42)); #expect(await rig.monitor.settle())
        await rig.close()
    }

    // Invariant, cap: time asleep counts toward continuous freshness, including equality.
    @Test func sleepAcrossCapCannotRenewAge() async throws {
        let rig = TFRig(); try await rig.retained(retry: "3600", at: 30)
        rig.clock.set(60); await rig.monitor.sleep()
        rig.clock.set(300); await rig.monitor.wake()
        #expect(await rig.monitor.settle())
        let awake = await rig.monitor.display()
        #expect(awake.selected.isEmpty)
        #expect(awake.profiles.first?.fetchedAge == 300)
        #expect(awake.profiles.first?.message?.contains("Cached usage stale") == true)
        #expect(await rig.transport.count() == 2)
        await rig.close()
    }

    // New behaviour, monotonic retention: wall jumps cannot extend or shorten the allowance.
    @Test func wallJumpsDuringRetention() async throws {
        for offset in [-3600.0, 3600] {
            let rig = TFRig(); try await rig.retained(retry: tfHTTPDate(240), at: 30)
            rig.clock.set(120, wallOffset: offset); await rig.monitor.clockChanged()
            await rig.monitor.manualRefresh(); #expect(await rig.monitor.settle())
            let retained = await rig.monitor.display()
            #expect(retained.selected.count == 1)
            #expect(retained.profiles.first?.fetchedAge == 120)
            #expect(retained.profiles.first?.freshnessDeadline == TFClock.origin + 288.5)
            #expect(await rig.transport.count() == 2)
            rig.clock.set(288.5, wallOffset: offset); await rig.monitor.clockChanged()
            #expect((await rig.monitor.display()).selected.isEmpty)
            await rig.close()
        }
    }
}
