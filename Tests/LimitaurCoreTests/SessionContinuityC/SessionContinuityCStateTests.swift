import Foundation
import Testing
@testable import LimitaurCore

@Suite struct SessionContinuityCStateTests {
    // Preserves an invariant (C5): spending an attempt starts an inclusive one-hour gate, not a half-hour retry loop.
    @Test(arguments: [3_600.0, 3_660.0])
    func hourlyGateRejectsThirtyMinutesAndAllowsAnHour(_ delay: Double) async throws {
        try await cnWithRig { rig in
            try await rig.trigger(unbound: true)
            try await rig.complete(.ran(exitCode: 1), expectedMessage: cnFailed)
            try await rig.tick(2_100)
            #expect(rig.nudger.count() == 1)
            try await rig.tick(3_899.999, driver: .manual)
            #expect(rig.nudger.count() == 1)
            // Manual refresh still produces origin .recheck; it avoids conflating the 300 s read gate with the hour gate.
            try await rig.tick(300 + delay, driver: .manual)
            try #require(await cnWait { rig.nudger.count() == 2 })
            #expect(await cnCount(rig.monitor, "nudges") == 2)
            #expect((await rig.monitor.display()).nudgeAttempts == [cnSource: cnDate(300 + delay)])
        }
    }

    // Preserves an invariant (C2/C5): wall jumps cannot spend monotonic time; wall rollback cannot shorten the wall hour either.
    @Test func bothClockGatesMustPassAfterForwardAndBackwardWallJumps() async throws {
        try await cnWithRig { rig in
            try await rig.trigger(unbound: true)
            try await rig.complete(.ran(exitCode: 1), expectedMessage: cnFailed)
            try await rig.tick(7_500, mono: 2_100) // two wall hours, only thirty monotonic minutes
            #expect(rig.nudger.count() == 1)
            try await rig.tick(100, mono: 4_000) // enough monotonic time, but wall time is before the first attempt
            #expect(rig.nudger.count() == 1)
            try await rig.tick(3_900, mono: 4_300, driver: .manual)
            try #require(await cnWait { rig.nudger.count() == 2 })
            #expect((await rig.monitor.display()).nudgeAttempts == [cnSource: cnDate(3_900)])
        }
    }

    // Exercises new behaviour (C5): a persisted attempt twenty minutes old defers the first child by forty minutes.
    @Test func restoreTwentyMinutesAgoDefersFortyMinutes() async throws {
        try await cnWithRig { rig in
            await rig.monitor.restoreNudgeAttempts([cnSource: cnDate(-1_200)])
            try await rig.start(unbound: true)
            try await rig.tick(300); #expect(rig.nudger.count() == 0)
            try await rig.tick(2_399.999, driver: .manual); #expect(rig.nudger.count() == 0)
            try await rig.tick(2_400, driver: .manual)
            try #require(await cnWait { rig.nudger.count() == 1 })
            #expect((await rig.monitor.display()).nudgeAttempts == [cnSource: cnDate(2_400)])
        }
    }

    // Preserves an invariant (C2/C5): restoring stale state cannot erase or move an in-memory attempt.
    @Test func restoreAfterInMemoryAttemptChangesNothing() async throws {
        try await cnWithRig { rig in
            try await rig.trigger(unbound: true)
            try await rig.complete(.ran(exitCode: 1), expectedMessage: cnFailed)
            await rig.monitor.restoreNudgeAttempts([cnSource: cnDate(-86_400), "claude:unrelated": cnDate(0)])
            #expect((await rig.monitor.display()).nudgeAttempts == [cnSource: cnDate(300)])
            try await rig.tick(2_100)
            #expect(rig.nudger.count() == 1)
        }
    }

    // Preserves an invariant (C2): future persisted dates are clamped, preserving a bounded hour rather than an indefinite lockout.
    @Test func futureRestoreClampsToNowAndThenExpiresAtOneHour() async throws {
        try await cnWithRig { rig in
            await rig.monitor.restoreNudgeAttempts([cnSource: cnDate(86_400)])
            #expect((await rig.monitor.display()).nudgeAttempts == [cnSource: cnDate(0)])
            try await rig.start(unbound: true)
            try await rig.tick(300); #expect(rig.nudger.count() == 0)
            try await rig.tick(3_599.999, driver: .manual); #expect(rig.nudger.count() == 0)
            try await rig.tick(3_600, driver: .manual)
            try #require(await cnWait { rig.nudger.count() == 1 })
        }
    }

    // Preserves an invariant (C2): restoration is applied only while the entire map is empty, not per individual missing source.
    @Test func secondRestoreDoesNotMergeIntoNonemptyMap() async throws {
        try await cnWithRig { rig in
            let first = ["claude:other-source": cnDate(-10)]
            await rig.monitor.restoreNudgeAttempts(first)
            await rig.monitor.restoreNudgeAttempts([cnSource: cnDate(-20)])
            #expect((await rig.monitor.display()).nudgeAttempts == first)
        }
    }

    // Preserves an invariant (C2): callers using the old display initializer get an empty attempt map.
    @Test func compatibilityDisplayInitializerHasNoAttempts() {
        let display = MonitorDisplay(profiles: [], selected: [], nextDisplayDeadline: nil)
        #expect(display.nudgeAttempts.isEmpty)
    }

    // Preserves an invariant (C2/C6): an enabled setting without a nudger keeps the accepted re-check cadence and messages.
    @Test(arguments: [false, true])
    func noNudgerPreservesAcceptedRigBehaviour(_ reactive: Bool) async throws {
        try await cnWithRig(CNRig(installNudger: false, reactive: reactive)) { rig in
            try await rig.start(unbound: true)
            try await rig.tick(299.999); #expect(rig.keychain.count() == 1)
            try await rig.tick(300); #expect(rig.keychain.count() == 2)
            cnExpectMessage(await cnRow(rig.monitor), cnPaused)
            #expect(await cnCount(rig.monitor, "nudges") == 0)
            #expect(await cnCount(rig.monitor, "nudgeFailures") == 0)
            #expect((await rig.monitor.display()).nudgeAttempts.isEmpty)
            #expect(await rig.transport.count() == 0)
        }
    }

    // Preserves an invariant (C2): stopped is a separate trigger guard, even if a caller subsequently wakes the monitor.
    @Test func stoppedMonitorCannotStartAnotherNudgeWhenWoken() async throws {
        try await cnWithRig { rig in
            try await rig.trigger(unbound: true)
            try await rig.complete(.ran(exitCode: 1), expectedMessage: cnFailed)
            await rig.monitor.stop()
            rig.clock.set(3_960); await rig.monitor.wake()
            try #require(await rig.monitor.settle())
            #expect(rig.nudger.count() == 1)
        }
    }

    // Preserves an invariant (C2): expiry while asleep issues neither the proof read nor a nudge.
    @Test func sleepingMonitorDoesNotReadOrNudge() async throws {
        try await cnWithRig { rig in
            try await rig.start(unbound: true)
            await rig.monitor.sleep()
            try await rig.tick(3_960)
            #expect(rig.keychain.count() == 1); #expect(rig.nudger.count() == 0)
            #expect((await rig.monitor.display()).nudgeAttempts.isEmpty)
        }
    }

    // Preserves an invariant (C2): turning the setting off affects later attempts without cancelling a child already running.
    @Test func disablingSettingDoesNotCancelCurrentAttempt() async throws {
        try await cnWithRig { rig in
            try await rig.trigger(unbound: true)
            await rig.monitor.setNudgeEnabled(false)
            #expect(rig.nudger.pending() == 1)
            try await rig.complete(.ran(exitCode: 1), expectedMessage: cnFailed)
            try await rig.tick(3_960)
            #expect(rig.nudger.count() == 1)
            await rig.monitor.setNudgeEnabled(true)
            try await rig.tick(3_961, driver: .manual)
            try #require(await cnWait { rig.nudger.count() == 2 })
        }
    }
}

@Suite struct SessionContinuityCPersistenceTests {
    // Exercises new behaviour (C3/C6): the specified JSON Date dictionary survives an isolated preferences suite and gates a fresh monitor.
    // C3 exposes no core persistence helper. This tests the wire keys + restore API, not AppUI.apply or a guessed helper type.
    @Test func isolatedDefaultsRoundTripRestoresHourlyGate() async throws {
        let name = "Limitaur.SessionContinuityC." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(defaults.bool(forKey: "claudeNudgeEnabled") == false)
        defaults.set(true, forKey: "claudeNudgeEnabled")
        defaults.set(try JSONEncoder().encode([cnSource: cnDate(-1_200)]), forKey: "nudge.lastAttempts")
        let reopened = try #require(UserDefaults(suiteName: name))
        let data = try #require(reopened.data(forKey: "nudge.lastAttempts"))
        // The spec says JSON [String: Date], with no custom date strategy; use Codable's default Date strategy.
        let attempts = try JSONDecoder().decode([String: Date].self, from: data)
        try await cnWithRig { rig in
            await rig.monitor.restoreNudgeAttempts(attempts)
            try await rig.start(unbound: true, enabled: reopened.bool(forKey: "claudeNudgeEnabled"))
            try await rig.tick(300); #expect(rig.nudger.count() == 0)
            try await rig.tick(2_400)
            try #require(await cnWait { rig.nudger.count() == 1 })
            let published = (await rig.monitor.display()).nudgeAttempts
            defaults.set(try JSONEncoder().encode(published), forKey: "nudge.lastAttempts")
            let saved = try JSONDecoder().decode([String: Date].self, from: #require(defaults.data(forKey: "nudge.lastAttempts")))
            #expect(saved == [cnSource: cnDate(2_400)])
        }
    }

    // Preserves an invariant (C2/C6): future JSON attempts are clamped by the monitor, not trusted as an arbitrary delay.
    @Test func isolatedFutureAttemptIsClampedOnRestore() async throws {
        let name = "Limitaur.SessionContinuityC." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(try JSONEncoder().encode([cnSource: cnDate(172_800)]), forKey: "nudge.lastAttempts")
        let stored = try JSONDecoder().decode([String: Date].self, from: #require(defaults.data(forKey: "nudge.lastAttempts")))
        try await cnWithRig { rig in
            await rig.monitor.restoreNudgeAttempts(stored)
            let attempts = (await rig.monitor.display()).nudgeAttempts
            #expect(attempts == [cnSource: cnDate(0)])
            let safe = !String(decoding: try JSONEncoder().encode(attempts), as: UTF8.self).contains(cnToken(1))
            #expect(safe)
        }
    }
}
