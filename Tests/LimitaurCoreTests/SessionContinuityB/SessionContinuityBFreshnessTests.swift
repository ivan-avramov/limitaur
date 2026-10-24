import Foundation
import Testing
@testable import LimitaurCore

@Suite struct SessionContinuityBFreshnessTests {
    // Reproduces B6's fixed failure: a 100 s poll interval must not expire data at 90 s.
    @Test(arguments: [30.0, 50, 100, 120])
    func successHorizonAndProjectionExpireAtEquality(_ interval: Double) async throws {
        try await bWithRig { rig in
            try await rig.start(policies: ["codex": bPolicy(interval)])
            let horizon = max(90, interval + 20)
            rig.clock.set(horizon - 0.001)
            let before = await rig.monitor.display()
            #expect(before.selected.count == 1); #expect(before.profiles.first?.health == .healthy)
            #expect(before.profiles.first?.freshnessDeadline == BClock.mono + horizon)
            #expect(before.candidates.first?.freshnessDeadline == BClock.mono + horizon)
            #expect(before.candidates.first?.nominalDeadline == BClock.mono + horizon)
            #expect(before.nextDisplayDeadline == BClock.mono + horizon)
            var seen: [Int: SnapshotExpirations] = [:]
            let projected = projectDisplay(before, count: 3, wallNow: bDate(horizon),
                monotonicNow: BClock.mono + horizon, observations: &seen)
            #expect(projected.selected.isEmpty)
            rig.clock.set(horizon)
            let due = await rig.monitor.display()
            #expect(due.selected.isEmpty); #expect(due.profiles.first?.health == .stale)
            #expect(due.profiles.first?.message?.contains("Cached usage stale") == true)
        }
    }

    // Invariant B2: a learned interval change cannot move an existing snapshot's horizon.
    @Test func intervalChangeDoesNotMoveOldHorizonButNextSuccessRenewsIt() async throws {
        try await bWithRig(BRig(reactive: false)) { rig in
            try await rig.start(policies: ["codex": bPolicy(100)])
            try await rig.reply(at: 98.5, index: 1, response: bResponse(429))
            #expect(try await rig.policy().interval == 110)
            rig.clock.set(119.999); #expect((await rig.monitor.display()).selected.count == 1)
            rig.clock.set(120)
            #expect((await rig.monitor.display()).selected.isEmpty)
            #expect((await rig.monitor.display()).profiles.first?.freshnessDeadline == BClock.mono + 120)
            try await rig.reply(at: 207, index: 2, response: bSuccess())
            #expect((await rig.monitor.display()).profiles.first?.freshnessDeadline == BClock.mono + 337)
        }
    }

    // New behaviour B2: horizon uses the policy at store time, while clean credit uses dispatch time.
    @Test func inFlightStoreUsesPolicyAtCompletion() async throws {
        try await bWithRig(BRig(reactive: false)) { rig in
            try await rig.start(policies: ["codex": bPolicy(100)],
                                profiles: [bProfile("a"), bProfile("b")], tokens: [1, 2])
            rig.clock.set(98.5); await rig.monitor.refresh()
            try #require(await bWait { await rig.transport.count() == 4 })
            await rig.transport.answer(2, bResponse(429))
            try #require(await bWait { (await rig.monitor.display()).polling["codex"]?.interval == 110 })
            rig.clock.set(99); await rig.transport.answer(3, bSuccess())
            #expect(await rig.monitor.settle())
            let rows = (await rig.monitor.display()).profiles
            let stored = try #require(rows.first { $0.fetchedAge == 0 })
            #expect(stored.freshnessDeadline == BClock.mono + 229)
            #expect(try await rig.policy().consecutiveClean == 0)
        }
    }

    // Invariant B2: a late 429 raising the policy never resurrects an expired snapshot.
    @Test func lateThrottleCannotResurrectAfterHorizonEquality() async throws {
        try await bWithRig(BRig(reactive: false)) { rig in
            try await rig.start(policies: ["codex": bPolicy(100)])
            try await rig.request(at: 98.5, index: 1)
            rig.clock.set(120); #expect((await rig.monitor.display()).selected.isEmpty)
            await rig.transport.answer(1, bResponse(429, retry: "400"))
            #expect(await rig.monitor.settle()); #expect(try await rig.policy().interval == 120)
            for age in [120.0, 140, 299.999] {
                rig.clock.set(age); #expect((await rig.monitor.display()).selected.isEmpty)
            }
        }
    }

    // New behaviour B6: short Retry-After uses the policy dispatch allowance, not the old +48.5.
    @Test func policyRetentionUsesDispatchIntervalAndThirteenPointFiveSlack() async throws {
        try await bWithRig { rig in
            try await rig.start(policies: ["codex": bPolicy(110)])
            try await rig.reply(at: 108.5, index: 1, response: bResponse(429, retry: "5"))
            // Pending attribution leaves interval 110: max(113.5, 108.5+108.5)+13.5 = 230.5.
            #expect(try await rig.policy().interval == 110)
            rig.clock.set(230.499)
            let before = await rig.monitor.display()
            #expect(before.selected.count == 1)
            #expect(before.profiles.first?.freshnessDeadline == BClock.mono + 230.5)
            #expect(before.nextDisplayDeadline == BClock.mono + 230.5)
            rig.clock.set(230.5); #expect((await rig.monitor.display()).selected.isEmpty)
        }
    }

    // Invariant B2: active retention still has an exclusive 300 s absolute cap.
    @Test func policyRetentionCapAndProjection() async throws {
        try await bWithRig { rig in
            try await rig.start(policies: ["codex": bPolicy(110)])
            try await rig.reply(at: 108.5, index: 1, response: bResponse(429, retry: "400"))
            rig.clock.set(299.999); let before = await rig.monitor.display()
            #expect(before.selected.count == 1)
            #expect(before.profiles.first?.freshnessDeadline == BClock.mono + 300)
            var seen: [Int: SnapshotExpirations] = [:]
            #expect(projectDisplay(before, count: 3, wallNow: bDate(300), monotonicNow: BClock.mono + 300,
                                  observations: &seen).selected.isEmpty)
            rig.clock.set(300); #expect((await rig.monitor.display()).selected.isEmpty)
        }
    }

    // Invariant B2/B6: no activation keeps both nominal 90 and the frozen retry+48.5 formula.
    @Test func inactivePolicyKeepsThrottleFreshnessExpectations() async throws {
        try await bWithRig(BRig(reactive: false)) { rig in
            try await rig.start(policies: nil)
            try await rig.reply(at: 45, index: 1, response: bResponse(429, retry: "55"))
            for age in [90.0, 120, 148.499] {
                rig.clock.set(age)
                let value = await rig.monitor.display()
                #expect(value.selected.count == 1)
                #expect(value.profiles.first?.freshnessDeadline == BClock.mono + 148.5)
                #expect(value.polling.isEmpty)
            }
            rig.clock.set(148.5); #expect((await rig.monitor.display()).selected.isEmpty)
        }
    }

    // Invariant B2: absent policy and absent Retry-After still mean exactly 90 s freshness.
    @Test func inactiveNominalHorizonRemainsNinety() async throws {
        try await bWithRig { rig in
            try await rig.start(policies: nil)
            rig.clock.set(89.999); #expect((await rig.monitor.display()).selected.count == 1)
            rig.clock.set(90); #expect((await rig.monitor.display()).selected.isEmpty)
        }
    }

    // Invariant B2/B6: a verified merge carries the horizon of the newer surviving snapshot.
    @Test func verifiedMergeCarriesSurvivingSnapshotHorizon() async throws {
        try await bWithRig(BRig(reactive: false)) { rig in
            try await rig.start(policies: ["codex": bPolicy(80)], verified: true)
            try await rig.request(at: 10, index: 1, driver: .internal, force: true)
            await rig.transport.answer(1, bResponse(429)); #expect(await rig.monitor.settle())
            #expect(try await rig.policy().interval == 90)
            // New token/source produces an unverified entity; its newer success then merges into a.
            rig.files.set(bPath("b"), bToken(2)); rig.clock.set(20)
            await rig.monitor.setProfiles([bProfile("a"), bProfile("b")])
            #expect(await rig.monitor.settle())
            rig.clock.set(40); await rig.monitor.reconnect("b")
            try #require(await bWait { await rig.transport.count() == 3 })
            await rig.transport.answer(2, bSuccess(percent: 77, verified: true))
            #expect(await rig.monitor.settle())
            let merged = await rig.monitor.display()
            #expect(merged.selected.count == 1); #expect(merged.selected.first?.metric.usedPercent == 77)
            #expect(merged.profiles.allSatisfy { $0.freshnessDeadline == BClock.mono + 150 })
            rig.clock.set(149.999); #expect((await rig.monitor.display()).selected.count == 1)
            rig.clock.set(150); #expect((await rig.monitor.display()).selected.isEmpty)
        }
    }
}
