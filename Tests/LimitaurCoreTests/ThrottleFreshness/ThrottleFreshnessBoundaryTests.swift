import Testing
import LimitaurCore

@Suite struct ThrottleFreshnessBoundaries {
    // Invariant, R1: no provider deadline means exactly 90 seconds, including projection.
    @Test func nominalEquality() async throws {
        let rig = TFRig(); try await rig.start()
        let before = await rig.display(at: 89.999)
        #expect(before.selected.count == 1)
        #expect(before.nextDisplayDeadline == TFClock.origin + 90)
        let due = await rig.display(at: 90)
        #expect(due.selected.isEmpty)
        #expect(due.profiles.first?.health == .stale)
        #expect(due.profiles.first?.message?.contains("Cached usage stale") == true)
        var seen: [Int: SnapshotExpirations] = [:]
        #expect(rig.project(before, at: 90, observations: &seen).selected.isEmpty)
        #expect(await rig.transport.count() == 1)
        await rig.close()
    }

    // Failure reproducer, R2: provider-paced data must survive the nominal cutoff.
    @Test func providerPacedRetention() async throws {
        let rig = TFRig(); try await rig.retained()
        for age in [90.0, 100, 120, 148] {
            let display = await rig.display(at: age)
            #expect(display.selected.count == 1)
            #expect(display.profiles.first?.health == .throttled)
            #expect(display.profiles.first?.message?.contains("Retry after") == true)
            #expect(display.profiles.first?.message?.contains("Cached usage stale") == false)
            #expect(display.profiles.first?.fetchedAge == age)
        }
        await rig.close()
    }

    // New behaviour, R2/R8: retention is exclusive at 148.5, never rounded to a tick.
    @Test func retentionEqualityAndNextDeadline() async throws {
        let rig = TFRig(); try await rig.retained()
        let before = await rig.display(at: 148.499)
        #expect(before.selected.count == 1)
        #expect(before.nextDisplayDeadline == TFClock.origin + 148.5)
        #expect(before.profiles.first?.freshnessDeadline == TFClock.origin + 148.5)
        #expect(before.candidates.first?.freshnessDeadline == TFClock.origin + 148.5)
        let due = await rig.display(at: 148.5)
        #expect(due.selected.isEmpty)
        #expect(due.profiles.first?.health == .throttled)
        #expect(due.profiles.first?.message?.contains("Cached usage stale") == true)
        #expect(due.nextDisplayDeadline == nil)
        var seen: [Int: SnapshotExpirations] = [:]
        #expect(rig.project(before, at: 148.5, observations: &seen).selected.isEmpty)
        await rig.close()
    }

    // New behaviour, R3: a far-future numeric Retry-After cannot outlive the cap.
    @Test func numericFarFutureCapEquality() async throws {
        let rig = TFRig(); try await rig.retained(retry: "3600", at: 30)
        let before = await rig.display(at: 299.999)
        #expect(before.selected.count == 1)
        #expect(before.nextDisplayDeadline == TFClock.origin + 300)
        let due = await rig.display(at: 300)
        #expect(due.selected.isEmpty)
        #expect(due.profiles.first?.health == .throttled)
        #expect(due.profiles.first?.message?.contains("Cached usage stale") == true)
        #expect(due.profiles.first?.fetchedAge == 300)
        var seen: [Int: SnapshotExpirations] = [:]
        #expect(rig.project(before, at: 300, observations: &seen).selected.isEmpty)
        await rig.close()
    }

    // Invariant, R4: absent Retry-After never promotes exponential backoff to retention.
    @Test func absentRetryAfter() async throws {
        try await noExtension(retry: nil)
    }

    // Invariant, R4: malformed Retry-After never promotes exponential backoff to retention.
    @Test func unparseableRetryAfter() async throws {
        try await noExtension(retry: "definitely-not-a-deadline")
    }

    // Invariant, design line 29: negative numeric Retry-After does not parse.
    @Test func negativeRetryAfter() async throws {
        try await noExtension(retry: "-1")
    }

    // New behaviour, design lines 29-30: zero parses; its +48.5 allowance can exceed 90.
    @Test func zeroRetryAfterIsProviderDeclared() async throws {
        let rig = TFRig(); try await rig.retained(retry: "0", at: 70)
        let before = await rig.display(at: 118.499)
        #expect(before.selected.count == 1)
        #expect(before.profiles.first?.freshnessDeadline == TFClock.origin + 118.5)
        #expect((await rig.display(at: 118.5)).selected.isEmpty)
        await rig.close()
    }

    // New behaviour, R2: HTTP-date Retry-After produces the same monotonic retention.
    @Test func dateRetryAfter() async throws {
        let rig = TFRig(); try await rig.retained(retry: tfHTTPDate(100))
        let display = await rig.display(at: 120)
        #expect(display.selected.count == 1)
        #expect(display.profiles.first?.freshnessDeadline == TFClock.origin + 148.5)
        #expect(display.profiles.first?.fetchedAge == 120)
        await rig.close()
    }

    // New behaviour, R3: date-form Retry-After shares the absolute 300-second cap.
    @Test func dateFarFutureCapEquality() async throws {
        let rig = TFRig(); try await rig.retained(retry: tfHTTPDate(3600), at: 30)
        #expect((await rig.display(at: 299.999)).selected.count == 1)
        #expect((await rig.display(at: 300)).selected.isEmpty)
        await rig.close()
    }

    // New behaviour, design line 29: a past HTTP date parses as zero, not as absent.
    @Test func pastDateRetryAfter() async throws {
        let rig = TFRig(); try await rig.retained(retry: tfHTTPDate(60), at: 70)
        #expect((await rig.display(at: 118)).selected.count == 1)
        #expect((await rig.display(at: 118.5)).selected.isEmpty)
        await rig.close()
    }

    // Invariant, R4: short provider allowance must not inherit the longer local backoff.
    @Test func shortRetryAfterDoesNotUseBackoffDeadline() async throws {
        let rig = TFRig(); try await rig.start()
        try await rig.reply(at: 40, tfResponse(500))
        try await rig.reply(at: 70, index: 2, tfResponse(429, retry: "5"))
        // The second failure enforces 60 s (until 130); provider retention is only 123.5.
        #expect((await rig.display(at: 123.5)).selected.isEmpty)
        rig.clock.set(129.999); await rig.monitor.manualRefresh()
        #expect(await rig.monitor.settle())
        #expect(await rig.transport.count() == 3)
        rig.clock.set(130); await rig.monitor.refresh()
        #expect(await rig.transport.wait(4))
        await rig.transport.fail(3); #expect(await rig.monitor.settle())
        await rig.close()
    }

    // New behaviour, r4/R4: short Retry-After retains through its allowance, excluding backoff.
    @Test func shortRetryAfterRetainsOnlyProviderAllowance() async throws {
        let rig = TFRig(); try await rig.start()
        try await rig.reply(at: 40, tfResponse(500))
        try await rig.reply(at: 70, index: 2, tfResponse(429, retry: "5"))
        // Provider allowance ends at 123.5; local backoff ends at 130, not 75.
        #expect((await rig.display(at: 123.499)).selected.count == 1)
        #expect((await rig.display(at: 123.5)).selected.isEmpty)
        #expect((await rig.display(at: 130)).selected.isEmpty)
        #expect((await rig.display(at: 178.499)).selected.isEmpty)
        #expect(await rig.transport.count() == 3)
        await rig.close()
    }

    // Invariant, helper line 40: a latched deadline below nominal never shortens freshness.
    @Test func shortEarlyRetryAfterCannotShortenFreshness() async throws {
        let rig = TFRig(); try await rig.retained(retry: "5", at: 30)
        #expect((await rig.display(at: 89.999)).selected.count == 1)
        #expect((await rig.display(at: 90)).selected.isEmpty)
        await rig.close()
    }

    // Invariant, R4: other error classes do not extend a previously ordinary snapshot.
    @Test func nonThrottleFailuresKeepNinetySeconds() async throws {
        for status in [401, 500, 503, -1] {
            let rig = TFRig(); try await rig.start()
            try await rig.reply(at: 45, status == -1 ? nil : tfResponse(status))
            let expected: Health = status == 401 ? .unauthenticated : status == -1 ? .failed : .unavailable
            #expect((await rig.display(at: 89.999)).selected.count == 1)
            let due = await rig.display(at: 90)
            #expect(due.selected.isEmpty)
            #expect(due.profiles.first?.health == expected)
            #expect(due.profiles.first?.message?.contains("Cached usage stale") == true)
            await rig.close()
        }
    }

    // Invariant, R5: a late 429 cannot resurrect a snapshot removed at nominal equality.
    @Test func lateThrottleCannotResurrect() async throws {
        let rig = TFRig(); try await rig.start()
        try await rig.reply(at: 45, tfResponse(500))
        rig.clock.set(90); await rig.monitor.refresh()
        try #require(await rig.transport.wait(3))
        #expect((await rig.monitor.display()).selected.isEmpty)
        rig.clock.set(90.4)
        await rig.transport.answer(2, tfResponse(429, retry: "100"))
        #expect(await rig.monitor.settle())
        for age in [90.4, 120, 200] {
            #expect((await rig.display(at: age)).selected.isEmpty)
        }
        await rig.close()
    }

    // Invariant, latch rule: equality at nominal expiry is already too late to latch.
    @Test func throttleAtNominalEqualityCannotLatch() async throws {
        let rig = TFRig(); try await rig.start()
        rig.clock.set(60); await rig.monitor.refresh()
        try #require(await rig.transport.wait(2))
        rig.clock.set(90)
        await rig.transport.answer(1, tfResponse(429, retry: "100"))
        #expect(await rig.monitor.settle())
        #expect((await rig.display(at: 90)).selected.isEmpty)
        #expect((await rig.display(at: 120)).selected.isEmpty)
        await rig.close()
    }

    private func noExtension(retry: String?) async throws {
        let rig = TFRig(); try await rig.start()
        try await rig.reply(at: 70, tfResponse(429, retry: retry))
        #expect((await rig.display(at: 89.999)).selected.count == 1)
        let due = await rig.display(at: 90)
        #expect(due.selected.isEmpty)
        #expect(due.profiles.first?.health == .throttled)
        #expect(due.profiles.first?.message?.contains("Cached usage stale") == true)
        await rig.close()
    }
}
