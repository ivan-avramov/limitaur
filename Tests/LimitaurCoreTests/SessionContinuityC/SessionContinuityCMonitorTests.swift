import Foundation
import Testing
@testable import LimitaurCore

@Suite struct SessionContinuityCMonitorTests {
    // Reproduces a failure the specification fixes (C5): an expired default session stays paused without a renewal attempt.
    @Test func expiryConfirmingRecheckStartsOneNudge() async throws {
        try await cnWithRig { rig in
            try await rig.start()
            #expect(rig.nudger.count() == 0)
            try await rig.tick(299.999)
            #expect(rig.keychain.count() == 1); #expect(rig.nudger.count() == 0)
            try await rig.tick(300)
            try #require(await cnWait { rig.nudger.count() == 1 })
            cnExpectMessage(await cnRow(rig.monitor), cnNudging)
            #expect(await cnCount(rig.monitor, "nudges") == 1)
            #expect(await cnCount(rig.monitor, "nudgeFailures") == 0)
            #expect((await rig.monitor.display()).nudgeAttempts == [cnSource: cnDate(300)])
            #expect(rig.keychain.interactions() == [false, false])
            try await rig.tick(330)
            #expect(rig.nudger.count() == 1)
        }
    }

    // Exercises new behaviour (C5): launch expiry is eligible only at its first scheduled re-check, without a binding.
    @Test func unboundLaunchExpiryNudgesAtThreeHundredSeconds() async throws {
        try await cnWithRig { rig in
            try await rig.start(unbound: true)
            #expect(await rig.monitor.isAttached("a") == false)
            #expect(rig.nudger.count() == 0); #expect(await rig.transport.count() == 0)
            try await rig.tick(299.999)
            #expect(rig.keychain.count() == 1)
            try await rig.tick(300)
            try #require(await cnWait { rig.nudger.count() == 1 })
            #expect((await cnRow(rig.monitor))?.message == cnNudging)
            #expect(rig.keychain.count() == 2)
        }
    }

    // Preserves an invariant (C2/C5): the attempted date/message must be published before a child can be invoked.
    @Test func attemptIsInPublishedDisplayBeforeNudgerInvocation() async throws {
        try await cnWithRig { rig in
            try await rig.start(unbound: true)
            let stream = await rig.monitor.changes(), observed = CNBool()
            rig.nudger.observe {
                // Leave the stream unread until invocation: its newest buffered value is the last actual publish.
                var iterator = stream.makeAsyncIterator()
                if let value = await iterator.next() {
                    observed.set(value.nudgeAttempts == [cnSource: cnDate(300)] &&
                        value.profiles.first { $0.profile.id == "a" }?.message == cnNudging)
                }
            }
            try await rig.tick(300)
            try #require(await cnWait { rig.nudger.count() == 1 })
            #expect(observed.get())
        }
    }

    // Preserves an invariant (C5): aliases of one source share one child and one failure counter.
    @Test func aliasesShareOneAttemptAndFailure() async throws {
        try await cnWithRig { rig in
            try await rig.start(profiles: [cnProfile("a"), cnProfile("b")])
            try await rig.tick(300)
            try #require(await cnWait { rig.nudger.count() == 1 })
            cnExpectMessage(await cnRow(rig.monitor, "a"), cnNudging)
            cnExpectMessage(await cnRow(rig.monitor, "b"), cnNudging)
            try await rig.tick(330) // the other alias can now re-read, while the first child remains active
            #expect(rig.nudger.count() == 1); #expect(rig.nudger.peak() == 1)
            try await rig.complete(.ran(exitCode: 1), expectedMessage: cnFailed)
            cnExpectMessage(await cnRow(rig.monitor, "b"), cnFailed)
            #expect(await cnCount(rig.monitor, "nudges") == 1)
            #expect(await cnCount(rig.monitor, "nudgeFailures") == 1)
        }
    }

    // Exercises new behaviour (C2/C5): all outcomes have exact wording and only notFound omits the reactive re-read.
    @Test(arguments: CNOutcome.allCases)
    func outcomeMessageCountersAndNextTickRead(_ outcome: CNOutcome) async throws {
        try await cnWithRig { rig in
            try await rig.trigger(unbound: true)
            try await rig.complete(outcome.value, expectedMessage: outcome.message)
            #expect((await cnRow(rig.monitor))?.message == outcome.message)
            #expect(await cnCount(rig.monitor, "nudgeFailures") == (outcome == .success ? 0 : 1))
            #expect(rig.keychain.count() == 2)
            try await rig.tick(330)
            #expect(rig.keychain.count() == (outcome == .missing ? 2 : 3))
            #expect(rig.nudger.count() == 1) // no second attempt inside the hour
            #expect((await rig.monitor.display()).nudgeAttempts == [cnSource: cnDate(300)])
        }
    }

    // Preserves an invariant (C2): notFound suppresses a reactive read, but does not disable the normal five-minute re-check.
    @Test func missingCLILeavesNormalRecheckCadenceIntact() async throws {
        try await cnWithRig { rig in
            try await rig.trigger(unbound: true)
            try await rig.complete(.notFound, expectedMessage: cnMissing)
            try await rig.tick(599.999); #expect(rig.keychain.count() == 2)
            try await rig.tick(600); #expect(rig.keychain.count() == 3)
            #expect(rig.nudger.count() == 1)
        }
    }

    // Preserves an invariant (C5): merely having an expired binding is insufficient; opt-in defaults off and can be disabled.
    @Test(arguments: [false, true])
    func settingOffPreventsNudge(_ explicitlyOff: Bool) async throws {
        try await cnWithRig { rig in
            try await rig.start(unbound: true, enabled: explicitlyOff ? false : nil)
            try await rig.tick(300)
            #expect(rig.keychain.count() == 2); #expect(rig.nudger.count() == 0)
            #expect((await rig.monitor.display()).nudgeAttempts.isEmpty)
            await rig.monitor.setNudgeEnabled(true)
            try await rig.tick(301, driver: .manual)
            try #require(await cnWait { rig.nudger.count() == 1 })
        }
    }

    // Preserves an invariant (C5): an explicitly selected credential file is never a target for default-session nudging.
    @Test func explicitClaudeFileNeverNudges() async throws {
        try await cnWithRig { rig in
            let path = "/virtual/continuity-c/explicit-credential"
            rig.files.set(path, cnCredential(expiry: -1))
            try await rig.start(profiles: [cnProfile(source: .claudeFile(path))])
            try await rig.tick(300)
            #expect(rig.nudger.count() == 0); #expect(rig.keychain.count() == 0)
            #expect((await rig.monitor.display()).nudgeAttempts.isEmpty)
        }
    }

    // Preserves an invariant (C5): discovery fallback expiry has viaKeychain == false and cannot authorize a CLI run.
    @Test func expiredDiscoveryFallbackNeverNudges() async throws {
        try await cnWithRig { rig in
            rig.keychain.set(KeychainReadOutcome(result: .notFound, reason: .notFound))
            rig.files.set(CredentialStore.defaultClaudePath, cnCredential(expiry: -1))
            try await rig.start()
            try await rig.tick(300)
            #expect(rig.keychain.count() == 2); #expect(rig.nudger.count() == 0)
            #expect((await rig.monitor.display()).nudgeAttempts.isEmpty)
        }
    }

    // Preserves an invariant (C5): denial/suspension never proves expiry, even when the previously bound token has expired.
    @Test(arguments: [false, true])
    func deniedOrSuspendedRecheckNeverNudges(_ suspended: Bool) async throws {
        try await cnWithRig { rig in
            try await rig.start()
            rig.keychain.set(KeychainReadOutcome(result: .denied, reason: suspended ? .suspended : .exit(1)))
            try await rig.tick(300)
            cnExpectMessage(await cnRow(rig.monitor), suspended ? cnSuspended : cnDenied)
            #expect(rig.nudger.count() == 0); #expect(await cnCount(rig.monitor, "nudges") == 0)
        }
    }

    // Preserves an invariant (C5): a wake re-check is excluded even when its result proves Keychain expiry.
    @Test func wakeRecheckDoesNotNudgeButLaterOrdinaryRecheckDoes() async throws {
        try await cnWithRig { rig in
            try await rig.start(unbound: true)
            await rig.monitor.sleep(); rig.clock.set(300)
            await rig.monitor.wake(); try #require(await rig.monitor.settle())
            #expect(rig.keychain.count() == 2); #expect(rig.nudger.count() == 0)
            try await rig.tick(600)
            try #require(await cnWait { rig.nudger.count() == 1 })
        }
    }

    // Exercises new behaviour (C2): HTTP rejection alone never nudges, but a reactive re-read proving expiry does.
    @Test func rejectedBindingCanNudgeOnlyAfterExpiryIsConfirmed() async throws {
        try await cnWithRig { rig in
            await rig.transport.setStatus(401)
            try await rig.start()
            #expect(rig.nudger.count() == 0)
            try await rig.tick(29.999)
            #expect(rig.keychain.count() == 1); #expect(rig.nudger.count() == 0)
            try await rig.tick(30)
            try #require(await cnWait { rig.nudger.count() == 1 })
            cnExpectMessage(await cnRow(rig.monitor), cnNudging)
        }
    }

    // Preserves an invariant (C2): an unexpired re-read cannot authorize a CLI run.
    @Test func unexpiredRecheckDoesNotNudge() async throws {
        try await cnWithRig { rig in
            rig.keychain.set(cnFound(expiry: 10_000))
            await rig.transport.setStatus(401)
            try await rig.start()
            try await rig.tick(30)
            #expect(rig.keychain.count() == 2); #expect(rig.nudger.count() == 0)
            #expect((await rig.monitor.display()).nudgeAttempts.isEmpty)
        }
    }

    // Preserves an invariant (C2/C5): a live child blocks every additional proof, even after the hourly gate opens.
    @Test func anotherNudgeCannotStartWhileOneRuns() async throws {
        try await cnWithRig { rig in
            try await rig.trigger(unbound: true)
            try await rig.tick(3_960)
            #expect(rig.keychain.count() == 3)
            #expect(rig.nudger.count() == 1); #expect(rig.nudger.pending() == 1)
            #expect(rig.nudger.peak() == 1)
            try await rig.complete(.ran(exitCode: 1), expectedMessage: cnFailed)
            try await rig.tick(3_990)
            try #require(await cnWait { rig.nudger.count() == 2 })
        }
    }

    // Reproduces a failure the specification fixes (C5): a successful nudge is followed by a fresh credential read and resume.
    @Test func successfulNudgeResumesAndClearsBothAttemptClocks() async throws {
        try await cnWithRig { rig in
            try await rig.trigger(unbound: true)
            rig.keychain.set(cnFound(2, expiry: 340))
            try await rig.complete(.ran(exitCode: 0), expectedMessage: cnPaused)
            try await rig.tick(330)
            #expect(await cnCount(rig.monitor, "credentialResumes") == 1)
            #expect((await rig.monitor.display()).nudgeAttempts.isEmpty)
            #expect(await rig.monitor.isAttached("a"))
            try await rig.tick(630)
            try #require(await cnWait { rig.nudger.count() == 2 })
            #expect((await rig.monitor.display()).nudgeAttempts == [cnSource: cnDate(630)])
        }
    }

    // Preserves an invariant (C5): completion of an older CLI attempt cannot overwrite a successful interactive Connect.
    @Test(arguments: CNOutcome.allCases)
    func connectDuringNudgeKeepsHealthyRowUntouched(_ outcome: CNOutcome) async throws {
        try await cnWithRig { rig in
            try await rig.start(unbound: true, profiles: [cnProfile("a"), cnProfile("b")])
            try await rig.tick(300)
            try #require(await cnWait { rig.nudger.count() == 1 })
            rig.keychain.set(cnFound(2, expiry: 10_000))
            await rig.monitor.reconnect("a"); try #require(await rig.monitor.settle())
            let before = try #require(await cnRow(rig.monitor, "a"))
            #expect(before.health == .healthy); #expect(before.message == nil)
            let generation = before.snapshotGeneration
            rig.nudger.complete(outcome.value)
            // b still carries nudgingMessage. Its changed message acknowledges nudged(),
            // avoiding a fixed flush or assuming settle() tracks the detached nudge task.
            try #require(await cnWait { cnHasMessage(await cnRow(rig.monitor, "b"), outcome.message) })
            let after = try #require(await cnRow(rig.monitor, "a"))
            #expect(after.health == .healthy); #expect(after.message == nil)
            #expect(after.snapshotGeneration == generation)
            #expect((await rig.monitor.display()).nudgeAttempts.isEmpty)
        }
    }

    // Preserves an invariant (C2/C5): denied-family wording wins over a stale nudge result, including suspended wording.
    @Test(arguments: [false, true])
    func denialDuringNudgeKeepsDeniedWording(_ suspended: Bool) async throws {
        try await cnWithRig { rig in
            try await rig.start(unbound: true, profiles: [cnProfile("a"), cnProfile("b")])
            try await rig.tick(300)
            try #require(await cnWait { rig.nudger.count() == 1 })
            rig.keychain.set(KeychainReadOutcome(result: .denied, reason: suspended ? .suspended : .exit(1)))
            try await rig.tick(301, driver: .manual)
            let expected = suspended ? cnSuspended : cnDenied
            let rows = (await rig.monitor.display()).profiles
            let denied = try #require(rows.first { cnHasMessage($0, expected) })
            let other = try #require(rows.first { $0.profile.id != denied.profile.id })
            cnExpectMessage(other, cnNudging)
            rig.nudger.complete(.ran(exitCode: 1))
            // The other alias acknowledges completion; then verify the denied row was skipped.
            try #require(await cnWait { cnHasMessage(await cnRow(rig.monitor, other.profile.id), cnFailed) })
            cnExpectMessage(await cnRow(rig.monitor, denied.profile.id), expected)
            #expect(rig.nudger.count() == 1)
        }
    }

    // Preserves an invariant (C2): denial may replace failed/missing nudge wording; a later non-denied read restores paused wording.
    @Test(arguments: [0, 1, 2, 3])
    func deniedFamilyCanReplaceAndRestoreFailedOrMissingNudgeMessages(_ variant: Int) async throws {
        try await cnWithRig { rig in
            try await rig.trigger(unbound: true)
            let outcome: CNOutcome = variant < 2 ? .failure : .missing
            try await rig.complete(outcome.value, expectedMessage: outcome.message)
            let suspended = variant % 2 == 1
            rig.keychain.set(KeychainReadOutcome(result: .denied, reason: suspended ? .suspended : .exit(1)))
            try await rig.tick(variant < 2 ? 330 : 301, driver: .manual)
            cnExpectMessage(await cnRow(rig.monitor), suspended ? cnSuspended : cnDenied)
            rig.keychain.set(cnFound(expiry: -1))
            try await rig.tick(variant < 2 ? 360 : 302, driver: .manual)
            cnExpectMessage(await cnRow(rig.monitor), cnPaused)
            #expect(rig.nudger.count() == 1)
        }
    }

    // Preserves an invariant (C2/C5): sleep defers reads, not completion messages or persistence of the attempt.
    @Test(arguments: CNOutcome.allCases)
    func outcomeWhileAsleepStillRestoresMessage(_ outcome: CNOutcome) async throws {
        try await cnWithRig { rig in
            try await rig.trigger(unbound: true)
            await rig.monitor.sleep()
            try await rig.complete(outcome.value, expectedMessage: outcome.message)
            #expect((await cnRow(rig.monitor))?.message == outcome.message)
            try await rig.tick(330)
            #expect(rig.keychain.count() == 2)
            rig.keychain.set(cnFound(2, expiry: 10_000))
            await rig.monitor.wake(); try #require(await rig.monitor.settle())
            #expect(rig.keychain.count() == (outcome == .missing ? 2 : 3))
        }
    }

    // Preserves an invariant (C2): neither sleep nor stop waits for, cancels, or launches a replacement child.
    @Test(arguments: [false, true])
    func sleepAndStopDoNotTouchRunningChild(_ stop: Bool) async throws {
        try await cnWithRig { rig in
            try await rig.trigger(unbound: true)
            if stop { await rig.monitor.stop() } else { await rig.monitor.sleep() }
            #expect(rig.nudger.pending() == 1); #expect(rig.nudger.waitCount() == 0)
            try await rig.tick(3_960)
            #expect(rig.nudger.count() == 1)
        }
    }

    // Preserves an invariant (C2): late completion cannot recreate a removed profile or affect an unrelated source.
    @Test func outcomeDoesNotRecreateRemovedProfile() async throws {
        try await cnWithRig { rig in
            try await rig.start(profiles: [cnProfile("a"), cnProfile("b")])
            try await rig.tick(300)
            try #require(await cnWait { rig.nudger.count() == 1 })
            await rig.monitor.setProfiles([cnProfile("b")])
            rig.nudger.complete(.notFound)
            try #require(await cnWait { cnHasMessage(await cnRow(rig.monitor, "b"), cnMissing) })
            let ids = (await rig.monitor.display()).profiles.map { $0.profile.id }
            #expect(ids == ["b"]); #expect(rig.nudger.count() == 1)
        }
    }

    // Preserves an invariant (credential boundary): nudge messages, counters and persisted dates never contain token bytes.
    @Test(arguments: CNOutcome.allCases)
    func nudgePresentationAndStatisticsContainNoTokenBytes(_ outcome: CNOutcome) async throws {
        try await cnWithRig { rig in
            try await rig.trigger(unbound: true)
            try await rig.complete(outcome.value, expectedMessage: outcome.message)
            let display = await rig.monitor.display(), statistics = await rig.monitor.statistics()
            let text = display.profiles.compactMap(\.message).joined() + String(describing: statistics) +
                String(describing: display.nudgeAttempts)
            let safe = (1...3).allSatisfy { !text.contains(cnToken($0)) }
            #expect(safe)
        }
    }
}
