import Foundation
import Testing
@testable import LimitaurCore

@Suite struct SessionContinuityBGateTests {
    // New behaviour B5: cycle dispatches use interval minus tolerance, including equality.
    @Test(arguments: [30.0, 50, 120]) func exactCycleBoundary(_ interval: Double) async throws {
        try await bWithRig { rig in
            try await rig.start(policies: ["codex": bPolicy(interval)])
            let boundary = max(30, interval) - 1.5
            for time in [0, 10, boundary - 0.001] {
                rig.clock.set(time); await rig.monitor.refresh(driver: .cycle)
                #expect(await rig.monitor.settle()); #expect(await rig.transport.count() == 1)
            }
            try await rig.request(at: boundary, index: 1)
            await rig.transport.answer(1, bSuccess()); #expect(await rig.monitor.settle())
            #expect(await rig.transport.count() == 2)
        }
    }

    // Reproduces B5's fixed failure: a 10 s app tick must not poll every 30 s or miss the 50 s tick.
    @Test func tenSecondTicksAtDefaultInterval() async throws {
        try await bWithRig { rig in
            try await rig.start()
            for time in [0.0, 10, 20, 30, 40, 48] {
                rig.clock.set(time); await rig.monitor.refresh()
                #expect(await rig.monitor.settle()); #expect(await rig.transport.count() == 1)
            }
            try await rig.reply(at: 50, index: 1, response: bSuccess())
            #expect(await rig.transport.count() == 2)
        }
    }

    // Invariant B2/B5: an absent policy keeps the old 30 s gate, not the new 28.5 s floor.
    @Test func providerWithoutPolicyKeepsBaselineGate() async throws {
        try await bWithRig { rig in
            try await rig.start(policies: ["claude": PollingPolicy()])
            rig.clock.set(29.999); await rig.monitor.refresh()
            #expect(await rig.monitor.settle()); #expect(await rig.transport.count() == 1)
            try await rig.reply(at: 30, index: 1, response: bSuccess())
            #expect((await rig.monitor.display()).polling["codex"] == nil)
        }
    }

    // New behaviour B5: provider gates are independent even when profiles share an actor.
    @Test func twoProvidersUseIndependentIntervals() async throws {
        try await bWithRig { rig in
            try await rig.start(policies: ["claude": bPolicy(30), "codex": bPolicy(120)],
                                profiles: [bProfile("a", provider: "claude"), bProfile("b")])
            try await rig.request(at: 28.5, index: 2)
            #expect(await rig.transport.count("claude") == 2)
            #expect(await rig.transport.count("codex") == 1)
            await rig.transport.answer(2, bSuccess("claude")); #expect(await rig.monitor.settle())
            rig.clock.set(118.499); await rig.monitor.refresh()
            try #require(await bWait { await rig.transport.count("claude") == 3 })
            #expect(await rig.transport.count("codex") == 1)
            await rig.transport.answer(3, bSuccess("claude")); #expect(await rig.monitor.settle())
            try await rig.request(at: 118.5, index: 4)
            #expect(await rig.transport.count("codex") == 2)
            await rig.transport.answer(4, bSuccess()); #expect(await rig.monitor.settle())
        }
    }

    // Invariant B2: activation fills absent entries, never restores over learned state.
    @Test func setPollingIsInsertOnlyAndDisplayDefaultsEmpty() async throws {
        try await bWithRig { rig in
            #expect((await rig.monitor.display()).polling.isEmpty)
            let synthetic = MonitorDisplay(profiles: [], candidates: [], revision: 0, nextDisplayDeadline: nil)
            #expect(synthetic.polling.isEmpty)
            try await rig.start(policies: ["codex": bPolicy(120)])
            await rig.monitor.setPolling(["codex": PollingPolicy(), "claude": PollingPolicy()])
            #expect(try await rig.policy().interval == 120)
            #expect(try await rig.policy("claude").interval == 50)
        }
    }

    // Invariant B5: manual/dropdown/internal/wake retain the baseline forced semantics.
    @Test(arguments: [0, 1, 2, 3]) func forcedDriversBypassPolicyGate(_ variant: Int) async throws {
        try await bWithRig { rig in
            try await rig.start(policies: ["codex": bPolicy(120)])
            rig.clock.set(10)
            switch variant {
            case 0: await rig.monitor.manualRefresh()
            case 1: await rig.monitor.dropdownOpened()
            case 2: await rig.monitor.refresh(force: true, driver: .internal)
            default: await rig.monitor.sleep(); await rig.monitor.wake()
            }
            try #require(await bWait { await rig.transport.count() == 2 })
            await rig.transport.answer(1, bSuccess()); #expect(await rig.monitor.settle())
            #expect(try await rig.policy().consecutiveClean == 0)
        }
    }

    // Invariant B2/B5: throttle and single-flight precede every driver gate.
    @Test func throttleCannotBeBypassedAndOnlyOneRequestIsInFlight() async throws {
        try await bWithRig(BRig(reactive: false)) { rig in
            try await rig.start()
            try await rig.reply(at: 50, index: 1, response: bResponse(429, retry: "95"))
            for time in [100.0, 144.999] {
                rig.clock.set(time)
                await rig.monitor.refresh(); await rig.monitor.manualRefresh(); await rig.monitor.dropdownOpened()
                await rig.monitor.refresh(force: true, driver: .internal)
                #expect(await rig.monitor.settle()); #expect(await rig.transport.count() == 2)
            }
            try await rig.request(at: 148.5, index: 2)
            await rig.monitor.manualRefresh(); await rig.monitor.dropdownOpened(); await rig.monitor.refresh()
            #expect(await rig.transport.count() == 3)
            await rig.transport.answer(2, bSuccess()); #expect(await rig.monitor.settle())
        }
    }

    // Invariant B3: compatibility constants must not be repurposed as the 10 s UI tick.
    @Test func legacyCadenceConstantsStayUnchanged() {
        #expect(nominalPollInterval == 45); #expect(cadenceTolerance == 1)
        #expect(pollInterval(jitter: 0) == 45); #expect(pollInterval(jitter: 1.5) == 46.5)
    }
}
