import Foundation
import Darwin
import Testing
@testable import LimitaurCore

enum CNRejectedCandidate: String, CaseIterable, Sendable {
    case accessDenied, directory, fifo, groupWritable, otherWritable, foreignOwner
    case groupWritableParent, otherWritableParent, foreignParent, missing
}
enum CNBadWork: String, CaseIterable, Sendable {
    case workSymlink, tmpSymlink, workFile, tmpFile, workChmod, tmpChmod, workMkdir, tmpMkdir
}

@Suite struct SessionContinuityCNudgerTests {
    // Exercises new behaviour (C1): the documented preference order expands ~ only in the default list.
    @Test func defaultCandidateOrderAndHomeExpansion() {
        let matches = ClaudeCLINudger.defaultCandidates == [NSHomeDirectory() + "/.local/bin/claude",
            "/opt/homebrew/bin/claude", "/usr/local/bin/claude", NSHomeDirectory() + "/.claude/local/claude"]
        #expect(matches)
    }

    // Exercises new behaviour (C4): a later accepted executable must never replace the first one.
    @Test func firstAcceptedCandidateWins() async {
        let files = CNNudgeFiles(), runner = CNRunner()
        let later = "/virtual/continuity-c/later/claude"
        files.candidate(); files.candidate(later)
        let result = await cnCLI(runner, files, candidates: [cnCandidate, later]).nudge()
        #expect(result == .ran(exitCode: 0)); #expect(runner.count() == 1)
        let choseFirst = runner.chose(cnCandidate); #expect(choseFirst)
    }

    // Preserves an invariant (C1/C4): each failed trust check independently skips the candidate.
    @Test(arguments: CNRejectedCandidate.allCases)
    func rejectedCandidateIsSkipped(_ reason: CNRejectedCandidate) async {
        let files = CNNudgeFiles(), runner = CNRunner()
        switch reason {
        case .accessDenied: files.candidate(executable: false)
        case .directory: files.candidate(mode: mode_t(S_IFDIR) | 0o755)
        case .fifo: files.candidate(mode: mode_t(S_IFIFO) | 0o755)
        case .groupWritable: files.candidate(mode: mode_t(S_IFREG) | 0o775)
        case .otherWritable: files.candidate(mode: mode_t(S_IFREG) | 0o757)
        case .foreignOwner: files.candidate(owner: geteuid() + 1)
        case .groupWritableParent: files.candidate(parentMode: mode_t(S_IFDIR) | 0o775)
        case .otherWritableParent: files.candidate(parentMode: mode_t(S_IFDIR) | 0o757)
        case .foreignParent: files.candidate(parentOwner: geteuid() + 1)
        case .missing: break
        }
        let good = "/virtual/continuity-c/trusted/claude"
        files.candidate(good)
        let result = await cnCLI(runner, files, candidates: [cnCandidate, good]).nudge()
        #expect(result == .ran(exitCode: 0))
        let skipped = runner.chose(good); #expect(skipped); #expect(runner.count() == 1)
    }

    // Exercises new behaviour (C1): root ownership is accepted for both executable and its directory.
    @Test func rootOwnedCandidateAndParentAreAccepted() async {
        let files = CNNudgeFiles(), runner = CNRunner()
        files.candidate(owner: 0, parentOwner: 0)
        #expect(await cnCLI(runner, files).nudge() == .ran(exitCode: 0))
        #expect(runner.count() == 1)
    }

    // Preserves an invariant (C4): discovery failure spawns nothing, including an empty candidate list.
    @Test(arguments: [false, true])
    func noAcceptedCandidateReturnsNotFound(_ empty: Bool) async {
        let files = CNNudgeFiles(), runner = CNRunner()
        files.candidate(executable: false)
        let outcome = await cnCLI(runner, files, candidates: empty ? [] : [cnCandidate]).nudge()
        #expect(outcome == .notFound); #expect(runner.count() == 0)
    }

    // Exercises new behaviour (C4): follow the file symlink while preserving launcher-first PATH order.
    @Test func acceptedSymlinkUsesResolvedExecutableAndBothPathDirectories() async {
        let files = CNNudgeFiles(), runner = CNRunner()
        let target = "/virtual/continuity-c/node/bin/claude"
        files.candidate(); files.candidate(target)
        files.put(cnCandidate, CNNode(mode: mode_t(S_IFLNK) | 0o777, target: target))
        #expect(await cnCLI(runner, files).nudge() == .ran(exitCode: 0))
        let resolved = runner.chose(target), environment = runner.envMatches(cnEnvironment(resolved: target))
        #expect(resolved); #expect(environment)
    }

    // Preserves an invariant (C1/C4): no inherited keys/CLAUDECODE, no captured output, no registry admission.
    @Test func exactInvocationAndEnvironmentAreIsolated() async {
        let files = CNNudgeFiles(), runner = CNRunner(); files.candidate()
        #expect(await cnCLI(runner, files).nudge() == .ran(exitCode: 0))
        let args = runner.argsMatch(cnArguments), env = runner.envMatches(cnEnvironment())
        let options = runner.optionsMatch()
        #expect(args); #expect(env); #expect(options)
    }

    // Preserves an invariant (C1): metacharacters stay literal executable/environment values, never shell text.
    @Test func metacharactersDoNotBecomeArgumentsOrShellCommands() async {
        let files = CNNudgeFiles(), runner = CNRunner()
        let candidate = "/virtual/continuity-c/bin odd/claude;$(inert)\nname"
        let home = "/virtual/continuity-c/home '$inert'", user = "synthetic;$(inert)"
        files.candidate(candidate)
        let outcome = await cnCLI(runner, files, candidates: [candidate], home: home, user: user).nudge()
        #expect(outcome == .ran(exitCode: 0))
        let path = runner.chose(candidate), args = runner.argsMatch(cnArguments)
        let env = runner.envMatches(cnEnvironment(candidate: candidate, resolved: candidate, home: home, user: user))
        #expect(path); #expect(args); #expect(env)
    }

    // Preserves an invariant (C1/C4): workspace redirects, non-directories and permission failures fail closed.
    @Test(arguments: CNBadWork.allCases)
    func unsafeWorkDirectoryFailsWithoutSpawn(_ bad: CNBadWork) async {
        let files = CNNudgeFiles(), runner = CNRunner(); files.candidate()
        let directory = CNNode(mode: mode_t(S_IFDIR) | 0o755)
        let link = CNNode(mode: mode_t(S_IFLNK) | 0o777, target: "/virtual/continuity-c/elsewhere")
        files.put("/virtual/continuity-c/elsewhere", directory)
        switch bad {
        case .workSymlink: files.put(cnWork, link)
        case .tmpSymlink: files.put(cnWork, directory); files.put(cnWork + "/tmp", link)
        case .workFile: files.put(cnWork, CNNode(mode: mode_t(S_IFREG) | 0o700))
        case .tmpFile: files.put(cnWork, directory); files.put(cnWork + "/tmp", CNNode(mode: mode_t(S_IFREG) | 0o700))
        case .workChmod: files.put(cnWork, directory); files.denyChmod(cnWork)
        case .tmpChmod: files.put(cnWork, directory); files.put(cnWork + "/tmp", directory); files.denyChmod(cnWork + "/tmp")
        case .workMkdir: files.denyMkdir(cnWork)
        case .tmpMkdir: files.put(cnWork, directory); files.denyMkdir(cnWork + "/tmp")
        }
        let outcome = await cnCLI(runner, files).nudge()
        #expect(outcome == .launchFailed); #expect(runner.count() == 0)
    }

    // Preserves an invariant (C1): both directories are private before the child exists, even when previously permissive.
    @Test(arguments: [false, true])
    func directoriesAreCreatedOrCorrectedBeforeSpawn(_ existing: Bool) async {
        let files = CNNudgeFiles(), prepared = CNBool(); files.candidate()
        if existing {
            files.put(cnWork, CNNode(mode: mode_t(S_IFDIR) | 0o777))
            files.put(cnWork + "/tmp", CNNode(mode: mode_t(S_IFDIR) | 0o755))
        }
        let runner = CNRunner(onRun: { prepared.set(files.privateDirectory(cnWork) && files.privateDirectory(cnWork + "/tmp")) })
        #expect(await cnCLI(runner, files).nudge() == .ran(exitCode: 0)); #expect(prepared.get())
        if !existing {
            #expect(files.madeWithPrivateMode(cnWork)); #expect(files.madeWithPrivateMode(cnWork + "/tmp"))
        }
    }

    // Exercises new behaviour (C4): timeout dominates nil exit (the real runner's timeout has no normal exit code).
    // C1's arrows are not numbered classification steps; C4 explicitly requires runner timeout -> timedOut.
    @Test(arguments: [0, 1, 2, 3, 4, 5, 6])
    func runnerOutcomeMapping(_ variant: Int) async {
        let files = CNNudgeFiles(); files.candidate()
        let result: ProcessResult, expected: NudgeOutcome
        switch variant {
        case 0: result = ProcessResult(exitCode: 0); expected = .ran(exitCode: 0)
        case 1: result = ProcessResult(exitCode: 3); expected = .ran(exitCode: 3)
        case 2: result = ProcessResult(exitCode: nil); expected = .launchFailed
        case 3: result = ProcessResult(exitCode: nil, signaled: true); expected = .launchFailed
        case 4: result = ProcessResult(exitCode: nil, signaled: true, timedOut: true); expected = .timedOut
        case 5: result = ProcessResult(exitCode: 3, timedOut: true); expected = .timedOut
        default: result = ProcessResult(exitCode: -1); expected = .ran(exitCode: -1)
        }
        let runner = CNRunner(result)
        let outcome = await cnCLI(runner, files).nudge()
        #expect(outcome == expected); #expect(runner.count() == 1)
    }

    // Exercises new behaviour (C4): waiting is tied to child completion, not nudge dispatch or an idle queue.
    @Test func waitReturnsWhenCurrentChildCompletes() async throws {
        let files = CNNudgeFiles(), runner = CNRunner(blocked: true); files.candidate()
        defer { runner.release() }
        let nudger = cnCLI(runner, files)
        let child = Task { await nudger.nudge() }
        try #require(await cnWait { runner.count() == 1 })
        let entered = CNBool(), returned = DispatchSemaphore(value: 0)
        let waiter = Task.detached {
            entered.set(true); nudger.waitForCompletion(upTo: 2); returned.signal()
        }
        try #require(await cnWait { entered.get() })
        // A deliberate negative observation window, not a sleep used as a readiness barrier.
        let early = await Task.detached { cnSignaled(returned, within: 0.05) }.value
        #expect(!early); #expect(runner.finished() == 0)
        runner.release(); await waiter.value
        let outcome = await child.value
        #expect(outcome == .ran(exitCode: 0)); #expect(!runner.didExpire())
    }

    // Preserves an invariant (C4): the quit bound does not wait for or terminate a slower child.
    @Test func waitBoundLeavesChildRunning() async throws {
        let files = CNNudgeFiles(), runner = CNRunner(blocked: true); files.candidate()
        defer { runner.release() }
        let nudger = cnCLI(runner, files), child = Task { await nudger.nudge() }
        try #require(await cnWait { runner.count() == 1 })
        let clock = ContinuousClock(), start = clock.now
        nudger.waitForCompletion(upTo: 0.08)
        let elapsed = start.duration(to: clock.now)
        #expect(elapsed >= .milliseconds(50)); #expect(elapsed < .seconds(2))
        #expect(runner.finished() == 0)
        runner.release(); _ = await child.value; #expect(!runner.didExpire())
    }

    // Preserves an invariant (C4): an idle nudger has no process to defer termination for.
    @Test func idleWaitDoesNotSpendTheBound() {
        let files = CNNudgeFiles(), runner = CNRunner(); files.candidate()
        let nudger = cnCLI(runner, files), clock = ContinuousClock(), start = clock.now
        nudger.waitForCompletion(upTo: 2)
        #expect(start.duration(to: clock.now) < .seconds(1)); #expect(runner.count() == 0)
    }
}
