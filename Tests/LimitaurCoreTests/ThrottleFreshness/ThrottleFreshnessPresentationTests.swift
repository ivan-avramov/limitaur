import Foundation
import Testing
import LimitaurCore

@Suite struct ThrottleFreshnessPresentation {
    // New behaviour, R2: reprojecting an earlier display preserves true age and throttle text.
    @Test func projectedDropdownUsesFetchAge() async throws {
        let rig = TFRig(); try await rig.retained()
        let display = await rig.monitor.display()
        var seen: [Int: SnapshotExpirations] = [:]
        let projected = rig.project(display, at: 120, observations: &seen)
        #expect(projected.selected.count == 1)
        #expect(projected.profiles.first?.fetchedAge == 120)
        #expect(projected.profiles.first?.health == .throttled)
        #expect(projected.profiles.first?.message?.contains("Retry after") == true)
        #expect(projected.profiles.first?.message?.contains("Cached usage stale") == false)
        #expect(await rig.transport.count() == 2)
        let expired = rig.project(display, at: 148.5, observations: &seen)
        #expect(expired.selected.isEmpty)
        #expect(expired.profiles.first?.fetchedAge == 148.5)
        #expect(expired.profiles.first?.message?.contains("Cached usage stale") == true)
        await rig.close()
    }

    // New behaviour, R2/line 53: retained metrics become "cached" at nominal equality.
    @Test func accessibilityChangesAtNominalEquality() async throws {
        let rig = TFRig(); try await rig.retained()
        let display = await rig.monitor.display()
        var seen: [Int: SnapshotExpirations] = [:]
        let before = rig.project(display, at: 89.999, observations: &seen)
        #expect(before.selected.count == 1)
        #expect(before.accessibilitySummary.contains(", fresh"))
        let due = rig.project(display, at: 90, observations: &seen)
        #expect(due.selected.count == 1)
        #expect(due.accessibilitySummary.contains("88.00 percent"))
        #expect(due.accessibilitySummary.contains(", cached"))
        #expect(!due.accessibilitySummary.contains(", fresh"))
        #expect(due.accessibilitySummary.contains("throttled"))
        await rig.close()
    }

    // New behaviour, R8: metric reset is earlier than retention, exclusive at equality.
    @Test func metricResetDuringRetention() async throws {
        let rig = TFRig(); try await rig.retained(response: tfSuccess(resetAge: 120))
        let before = await rig.display(at: 119.999)
        #expect(before.selected.count == 1)
        #expect(before.nextDisplayDeadline.map { abs($0 - (TFClock.origin + 120)) < 0.001 } == true)
        let due = await rig.display(at: 120)
        #expect(due.selected.isEmpty)
        #expect(due.profiles.first?.health == .throttled)
        #expect(due.profiles.first?.message?.contains("Cached usage stale") == false)
        #expect(due.nextDisplayDeadline == TFClock.origin + 148.5)
        // A wall rollback must not revive a reset that display() already observed.
        rig.clock.set(121, wallOffset: -60); await rig.monitor.clockChanged()
        #expect((await rig.monitor.display()).selected.isEmpty)
        await rig.close()
    }

    // Invariant, R8: projection's reset latch survives a wall rollback and actor handoff.
    @Test func projectedResetDoesNotResurrect() async throws {
        let rig = TFRig(); try await rig.retained(response: tfSuccess(resetAge: 120))
        let display = await rig.monitor.display()
        var seen: [Int: SnapshotExpirations] = [:]
        let reset = rig.project(display, at: 120, observations: &seen)
        #expect(reset.selected.isEmpty)
        #expect(reset.profiles.first?.expirations.metrics.isEmpty == false)
        let rollback = projectDisplay(display, count: 3,
                                      wallNow: TFClock.wallOrigin.addingTimeInterval(119),
                                      monotonicNow: TFClock.origin + 121, observations: &seen)
        #expect(rollback.selected.isEmpty)
        await rig.monitor.observePresentationExpirations(seen)
        rig.clock.set(121, wallOffset: -2)
        #expect((await rig.monitor.display()).selected.isEmpty)
        await rig.close()
    }

    // New behaviour, R8: a credential expiry still takes priority over retained freshness.
    @Test func credentialExpiryPrecedesRetentionDeadline() async throws {
        let credential = Data(#"{"claudeAiOauth":{"accessToken":"synthetic-only","expiresAt":1800000120000}}"#.utf8)
        let rig = TFRig(sources: ["/tf/claude": credential])
        let profile = AccountProfile(id: "one", providerID: "claude", label: "One", source: .claudeFile("/tf/claude"))
        try await rig.start([profile], response: tfResponse(200, body: #"{"limits":[{"kind":"session","percent":25}]}"#))
        try await rig.reply(at: 45, tfResponse(429, retry: "55"))
        let display = await rig.display(at: 100)
        #expect(display.selected.count == 1)
        #expect(display.profiles.first?.freshnessDeadline == TFClock.origin + 148.5)
        #expect(display.nextDisplayDeadline == TFClock.origin + 120)
        await rig.close()
    }

    // New behaviour, alias rule: one retained entity produces one metric and consistent rows.
    @Test func aliasesShareRetentionAndOnlyOneRequest() async throws {
        let rig = TFRig()
        let a = tfProfile("a"), b = tfProfile("b")
        await rig.monitor.setProfiles([a, b])
        try #require(await rig.transport.wait(1))
        await rig.transport.answer(0, tfSuccess())
        try #require(await rig.monitor.settle())
        #expect(await rig.transport.count() == 1)
        try await rig.reply(at: 45, tfResponse(429, retry: "55"))
        let display = await rig.display(at: 95)
        #expect(display.selected.count == 1)
        #expect(display.profiles.count == 2)
        #expect(display.profiles.filter { $0.snapshot != nil }.count == 1)
        for row in display.profiles {
            #expect(row.health == .throttled)
            #expect(row.fetchedAge == 95)
            #expect(row.freshnessDeadline == TFClock.origin + 148.5)
            #expect(row.message?.contains("Cached usage stale") == false)
        }
        var seen: [Int: SnapshotExpirations] = [:]
        let projected = rig.project(display, at: 130, observations: &seen)
        #expect(projected.profiles.allSatisfy { $0.fetchedAge == 130 })
        await rig.monitor.setProfiles([b])
        let survivor = await rig.monitor.display()
        #expect(survivor.selected.first?.accountLabel == "b")
        #expect(survivor.profiles.first?.snapshot != nil)
        #expect(await rig.transport.count() == 2)
        await rig.close()
    }

    // Invariant, state clearing rule: last-subscriber detach discards retained snapshot age.
    @Test func lastAliasDetachClearsRetention() async throws {
        let rig = TFRig(); try await rig.retained()
        rig.clock.set(60); await rig.monitor.setProfiles([])
        await rig.monitor.setProfiles([tfProfile()])
        #expect(await rig.monitor.settle())
        let rebound = await rig.display(at: 95)
        #expect(rebound.selected.isEmpty)
        #expect(rebound.profiles.first?.snapshot == nil)
        #expect(rebound.profiles.first?.fetchedAge == nil)
        #expect(rebound.profiles.first?.freshnessDeadline == nil)
        #expect(await rig.transport.count() == 2)
        await rig.close()
    }

    // New behaviour, r5/R12: stopped aliases cannot retain an extended presentation deadline.
    @Test func stopDoesNotLeaveRetentionOnReconfiguredAliases() async throws {
        let rig = TFRig()
        let profiles = [tfProfile("a"), tfProfile("b")]
        try await rig.start(profiles)
        try await rig.reply(at: 45, tfResponse(429, retry: "55"))
        rig.clock.set(60); await rig.monitor.stop()
        rig.clock.set(95); await rig.monitor.setProfiles(profiles)
        #expect(await rig.monitor.settle())
        let stopped = await rig.monitor.display()
        #expect(stopped.profiles.count == 2)
        #expect(stopped.selected.isEmpty)
        #expect(stopped.candidates.isEmpty)
        #expect(stopped.profiles.allSatisfy { $0.snapshot == nil })
        // Alias rows expose the helper even without a snapshot; nil also permits full clearing.
        #expect(stopped.profiles.allSatisfy {
            $0.freshnessDeadline.map { $0 <= TFClock.origin + 90 } ?? true
        })
        #expect(await rig.transport.count() == 2)
        await rig.close()
    }

    // New behaviour, R9: merge must latch against the surviving newer snapshot, not A's age.
    @Test func mergeRetainedEntityWithNewerSnapshot() async throws {
        let rig = TFRig(sources: ["/tf/a": tfToken("a"), "/tf/b": tfToken("b")])
        let a = tfProfile("a", path: "/tf/a"), b = tfProfile("b", path: "/tf/b")
        try await rig.start([a], response: tfSuccess(88, verified: true))
        // Attach B before A is eligible for the setProfiles minimum-success-age refresh.
        rig.clock.set(5); await rig.monitor.setProfiles([a, b])
        try #require(await rig.transport.wait(2), "B must have an independent request before merging")
        rig.clock.set(30)
        await rig.monitor.refresh()
        try #require(await rig.transport.wait(3), "A must be polled while B is in flight")
        await rig.transport.answer(2, tfResponse(429, retry: "210"))
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        var throttled = false
        while ContinuousClock.now < deadline {
            if (await rig.monitor.display()).profiles.first(where: { $0.profile.id == "a" })?.health == .throttled {
                throttled = true; break
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
        try #require(throttled, "A's Retry-After must be stored before B completes")
        rig.clock.set(60); await rig.transport.answer(1, tfSuccess(42, verified: true))
        try #require(await rig.monitor.settle())
        let merged = await rig.display(at: 151)
        #expect(merged.selected.map(\.metric.usedPercent) == [42])
        #expect(merged.profiles.count == 2)
        #expect(merged.profiles.filter { $0.snapshot != nil }.count == 1)
        #expect(merged.profiles.allSatisfy { $0.fetchedAge == 91 })
        #expect(merged.profiles.allSatisfy { $0.freshnessDeadline == TFClock.origin + 288.5 })
        rig.clock.set(239.999); await rig.monitor.manualRefresh()
        #expect(await rig.monitor.settle())
        #expect(await rig.transport.count() == 3)
        #expect((await rig.display(at: 288.499)).selected.first?.metric.usedPercent == 42)
        #expect((await rig.display(at: 288.5)).selected.isEmpty)
        await rig.close()
    }

    // Invariant, R10: retained bars never qualify throttled or nominally stale workloads.
    @Test func statisticsEligibilityRemainsStrict() async throws {
        let claude = Data(#"{"claudeAiOauth":{"accessToken":"synthetic-only","expiresAt":1800010000000}}"#.utf8)
        let rig = TFRig(sources: [CredentialStore.defaultCodexPath: tfToken()], keychain: .found(claude))
        let profiles = [AccountProfile(id: "codex-default", providerID: "codex", label: "Codex",
                                       source: .codexFile(CredentialStore.defaultCodexPath)),
                        AccountProfile(id: "claude-default", providerID: "claude", label: "Claude",
                                       source: .claudeDefaultDiscovery)]
        await rig.monitor.setProfiles(profiles)
        try #require(await rig.transport.wait(2))
        for index in 0..<2 {
            let response = await rig.transport.provider(at: index) == "codex" ? tfSuccess() :
                tfResponse(200, body: #"{"limits":[{"kind":"session","percent":25}]}"#)
            await rig.transport.answer(index, response)
        }
        try #require(await rig.monitor.settle())
        let initial = await rig.monitor.statistics()
        #expect(initial["__eligibility"]?["eligible"] == 1)
        #expect(initial["__eligibility"]?["validUntilContinuousNanoseconds"] == 1_090_000_000_000)
        rig.clock.set(45); await rig.monitor.refresh()
        try #require(await rig.transport.wait(4))
        for index in 2..<4 { await rig.transport.answer(index, tfResponse(429, retry: "55")) }
        try #require(await rig.monitor.settle())
        // Before 90 both bars already exist on the baseline, yet throttling disqualifies them.
        #expect((await rig.monitor.display()).selected.count == 2)
        for age in [45.0, 100, 120] {
            rig.clock.set(age)
            let stats = await rig.monitor.statistics()
            #expect(stats["__eligibility"]?["eligible"] == 0)
            #expect(stats["__eligibility"]?["validUntilContinuousNanoseconds"] == 0)
            #expect(stats["__eligibility"]?["violations"] == 1)
        }
        #expect((await rig.monitor.statistics())["codex"]?["throttled"] == 1)
        #expect((await rig.monitor.statistics())["claude"]?["throttled"] == 1)
        await rig.close()
    }
}
