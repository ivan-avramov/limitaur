import Foundation
import Synchronization
import Testing
@testable import LimitaurCore

// Part C implementer tests (C4-C6, core side). Synthetic tokens only; no real claude, security or network.
// The nudger tests reuse the frozen suite's POSIX fake (CNNudgeFiles) and runner (CNRunner).
private let nudging = "Running claude to renew the session"
private let failedText = "claude exited without renewing the session; run claude to sign in"
private let missingText = "claude command not found; run claude to sign in"
private let parent = "/virtual/continuity-c"
private func parentDirectory(_ path: String) -> String { (path as NSString).deletingLastPathComponent }
/// r12: the four system directories first, then the unresolved candidate's directory and the resolved file's.
private func systemFirst(_ candidate: String, _ resolved: String) -> [String: String] {
    var environment = cnEnvironment()
    environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:" + parentDirectory(candidate) + ":" + parentDirectory(resolved)
    environment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"   // r16: the eighth key; the frozen helper still has seven
    return environment
}
/// A symlink candidate whose target lives in `/virtual/continuity-c/lib`, whose mode is the parameter.
private func linked(_ files: CNNudgeFiles, libraryMode: mode_t) -> String {
    let target = parent + "/lib/cli.js"
    files.put(cnCandidate, CNNode(mode: mode_t(S_IFLNK) | 0o755, target: target))
    files.put(parentDirectory(cnCandidate), CNNode(mode: mode_t(S_IFDIR) | 0o755))
    files.put(target, CNNode(mode: mode_t(S_IFREG) | 0o755))
    files.put(parent + "/lib", CNNode(mode: mode_t(S_IFDIR) | libraryMode))
    return target
}

@Test func nudgerCreatesMissingParentThenSpawnsCheckedPathWithSystemDirectoriesFirst() async {
    let files = CNNudgeFiles(), runner = CNRunner()
    files.candidate()
    #expect(await cnCLI(runner, files).nudge() == .ran(exitCode: 0))
    for path in [parent, cnWork, cnWork + "/tmp"] { #expect(files.privateDirectory(path) && files.madeWithPrivateMode(path), Comment(rawValue: path)) }
    #expect(runner.chose(cnCandidate) && runner.envMatches(systemFirst(cnCandidate, cnCandidate)) && runner.optionsMatch())
    let denied = CNNudgeFiles(), refused = CNRunner()
    denied.candidate(); denied.denyMkdir(parent)
    #expect(await cnCLI(refused, denied).nudge() == .launchFailed && refused.count() == 0)
}

@Test func nudgerChecksResolvedFileDirectoryAndSpawnsTheResolvedFile() async {
    let files = CNNudgeFiles(), runner = CNRunner()
    let target = linked(files, libraryMode: mode_t(S_IFDIR) | 0o755)
    #expect(await cnCLI(runner, files).nudge() == .ran(exitCode: 0))
    #expect(runner.chose(target) && runner.envMatches(systemFirst(cnCandidate, target)))
    let writable = CNNudgeFiles(), skipped = CNRunner()
    _ = linked(writable, libraryMode: mode_t(S_IFDIR) | 0o775)   // the resolved file's directory is group-writable
    #expect(await cnCLI(skipped, writable).nudge() == .notFound && skipped.count() == 0)
}

@Test func nudgerWaitsForTheChildAndSystemChecksForwardToDarwin() async throws {
    let files = CNNudgeFiles(), runner = CNRunner(blocked: true)
    files.candidate()
    let slow = cnCLI(runner, files), task = Task { await slow.nudge() }
    #expect(await cnWait { runner.count() == 1 })
    var start = Date(); slow.waitForCompletion(upTo: 0.1); #expect(Date().timeIntervalSince(start) < 1)
    runner.release()
    start = Date(); slow.waitForCompletion(upTo: 5); #expect(Date().timeIntervalSince(start) < 2)
    #expect(await task.value == .ran(exitCode: 0))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("nudge-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: root) }
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let system = SystemNudgeFileChecks()
    #expect(system.mkdir(root + "/d", 0o700) == 0 && (system.lstat(root + "/d")?.st_mode ?? 0) & 0o777 == 0o700)
    #expect(system.chmod(root + "/d", 0o755) == 0 && (system.stat(root + "/d")?.st_mode ?? 0) & 0o777 == 0o755)
    try FileManager.default.createSymbolicLink(atPath: root + "/link", withDestinationPath: root + "/d")
    #expect((system.lstat(root + "/link")?.st_mode ?? 0) & S_IFMT == S_IFLNK && (system.stat(root + "/link")?.st_mode ?? 0) & S_IFMT == S_IFDIR)
    #expect(system.realpath(root + "/link") == system.realpath(root + "/d") && system.realpath(root + "/d") != nil)
    #expect(system.access(root + "/d", X_OK) == 0 && system.access(root + "/none", X_OK) != 0 && system.stat(root + "/none") == nil)
    // Whole policy on real files: a fresh tree without the `Limitaur` parent.
    try FileManager.default.createDirectory(atPath: root + "/bin", withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
    #expect(FileManager.default.createFile(atPath: root + "/bin/claude", contents: Data(), attributes: [.posixPermissions: 0o755]))
    let real = CNRunner(), work = root + "/Limitaur/nudge"
    let nudger = ClaudeCLINudger(runner: real, candidates: [root + "/bin/claude"], workDirectory: work, home: root, user: "u", fileChecks: system)
    #expect(await nudger.nudge() == .ran(exitCode: 0) && real.chose(system.realpath(root + "/bin/claude")!))
    for path in [root + "/Limitaur", work, work + "/tmp"] { #expect((system.lstat(path)?.st_mode ?? 0) & 0o777 == 0o700, Comment(rawValue: path)) }
}

// MARK: monitor rig
private final class NClock: MonitorClock, @unchecked Sendable {
    private let lock = NSLock(); private var wall = Date(timeIntervalSince1970: 1_800_000_000), mono: TimeInterval = 100
    func wallNow() -> Date { lock.withLock { wall } }
    func monotonicNow() -> TimeInterval { lock.withLock { mono } }
    func advance(_ seconds: TimeInterval, wall change: TimeInterval? = nil) { lock.withLock { mono += seconds; wall.addTimeInterval(change ?? seconds) } }
}
private final class NKeychain: KeychainReading, @unchecked Sendable {
    let state = Mutex<(value: KeychainResult, reads: Int)>((.notFound, 0))
    func claudeCredential() -> KeychainResult { state.withLock { $0.reads += 1; return $0.value } }
}
private final class NNudger: SessionNudging, @unchecked Sendable {
    let state = Mutex<(calls: Int, hold: Bool, outcome: NudgeOutcome)>((0, false, .ran(exitCode: 0)))
    let order = Mutex<[String]>([])
    func nudge() async -> NudgeOutcome {
        state.withLock { $0.calls += 1 }
        order.withLock { $0.append("nudge") }
        while state.withLock({ $0.hold }) { try? await Task.sleep(for: .milliseconds(2)) }
        return state.withLock { $0.outcome }
    }
    func waitForCompletion(upTo: TimeInterval) {}
}
private final class NStores: Sendable {
    private let maps = Mutex<[[String: Date]]>([])
    func append(_ map: [String: Date]) { maps.withLock { $0.append(map) } }
    func withLock<T>(_ body: ([[String: Date]]) -> T) -> T { maps.withLock { body($0) } }
}
private struct Rig {
    let clock = NClock(), kc = NKeychain(), files = SCFiles(), nudger = NNudger(), stores = NStores(), monitor: Monitor
    let source = CredentialSource.claudeDefaultDiscovery.stableID
    init(expired: Bool = true, enabled: Bool = true, hold: Bool = true, profile: AccountProfile = scProfile(), restored: [String: Date]? = nil) async {
        let expiry = clock.wallNow().addingTimeInterval(expired ? -10 : 400)
        kc.state.withLock { $0.value = .found(scClaude(1, expiry: expiry)) }
        nudger.state.withLock { $0.hold = hold }
        let fake = nudger, recorded = stores
        monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: kc), transport: SCTransport(), reactiveRecheck: true, nudger: nudger,
                          attemptStore: { map in fake.order.withLock { $0.append("store") }; recorded.append(map) })
        await monitor.setNudgeEnabled(enabled)
        if let restored { await monitor.restoreNudgeAttempts(restored) }
        await monitor.setProfiles([profile]); _ = await monitor.settle(); await scFlush()
    }
    func step(_ seconds: TimeInterval, _ driver: RefreshDriver = .cycle) async { clock.advance(seconds); await monitor.refresh(driver: driver); _ = await monitor.settle(); await scFlush() }
    func calls() -> Int { nudger.state.withLock { $0.calls } }
    /// Polls (under load the detached nudge task and its follow-up re-read need scheduling time) until the nudger was called `n` times and messages settled.
    func called(_ n: Int, message text: String? = nil) async -> Bool {
        await scWait { [self] in
            let shown = await scRow(monitor)
            return calls() == n && (text == nil || scMessage(shown, text!))
        }
    }
    func finish(_ outcome: NudgeOutcome) async { nudger.state.withLock { ($0.hold, $0.outcome) = (false, outcome) }; await scFlush() }
    func message() async -> String? { await scRow(monitor)?.message }
}

@Test func nudgeLifecycleAndHourlyGate() async {
    let rig = await Rig(), seen = Mutex<[MonitorDisplay]>([])
    let reader = Task { for await value in await rig.monitor.changes() { seen.withLock { $0.append(value) } } }
    await rig.step(299); #expect(rig.calls() == 0)
    await rig.step(2); let first = rig.clock.wallNow()
    #expect(await rig.called(1, message: nudging)); #expect(await scCount(rig.monitor, "nudges") == 1)
    #expect(seen.withLock { $0.first { $0.profiles.first?.message == nudging }?.nudgeAttempts[rig.source] } == first)
    reader.cancel()
    await rig.monitor.restoreNudgeAttempts([rig.source: .distantPast])
    #expect(await rig.monitor.display().nudgeAttempts == [rig.source: first])
    await rig.finish(.ran(exitCode: 1))
    #expect(await rig.message() == failedText); #expect(await scCount(rig.monitor, "nudgeFailures") == 1)
    await rig.step(31); #expect(rig.kc.state.withLock { $0.reads } == 3 && rig.calls() == 1)
    await rig.step(1800); #expect(rig.calls() == 1)
    rig.clock.advance(300, wall: 7_200); await rig.step(0); #expect(rig.calls() == 1)   // wall jumped forward: monotonic gate holds
    rig.clock.advance(1500, wall: -10_000); await rig.step(0); #expect(rig.calls() == 1)   // wall moved back: it does not shorten the hour
    await rig.step(4600); #expect(await rig.called(2)); #expect(await scCount(rig.monitor, "nudges") == 2)
    await rig.monitor.stop()
}

@Test func restoreDefersAndResumeClears() async {
    let rig = await Rig(hold: false)
    await rig.monitor.restoreNudgeAttempts([rig.source: rig.clock.wallNow().addingTimeInterval(-1200)])
    await rig.step(301); #expect(rig.calls() == 0)
    await rig.step(2098); #expect(rig.calls() == 0)   // 59:59 after the restored attempt
    await rig.step(300); #expect(await rig.called(1))
    #expect(await rig.message() == scPaused); #expect(await scCount(rig.monitor, "nudgeFailures") == 0)   // .ran(0): paused again, re-check due
    rig.kc.state.withLock { $0.value = .found(scClaude(2, expiry: rig.clock.wallNow().addingTimeInterval(400))) }
    await rig.step(31); #expect(await scCount(rig.monitor, "credentialResumes") == 1); #expect(await rig.called(1))
    #expect(await rig.monitor.display().nudgeAttempts.isEmpty); #expect(await rig.message() == nil)
    await rig.step(401); await rig.step(301); #expect(await rig.called(2))   // expiry after the resume nudges at once
    let future = await Rig(hold: false)
    await future.monitor.restoreNudgeAttempts([future.source: .distantFuture])
    #expect(await future.monitor.display().nudgeAttempts == [future.source: future.clock.wallNow()])
    await rig.monitor.stop(); await future.monitor.stop()
}

@Test func missingClaudeAndGuards() async {
    let missing = await Rig(hold: false); missing.nudger.state.withLock { $0.outcome = .notFound }
    await missing.step(301)
    #expect(await missing.called(1, message: missingText)); #expect(await scCount(missing.monitor, "nudgeFailures") == 1)
    let reads = missing.kc.state.withLock { $0.reads }   // the re-read that proved the expiry has happened
    await missing.step(31); #expect(missing.kc.state.withLock { $0.reads } == reads)
    let off = await Rig(enabled: false); await off.step(301); #expect(off.calls() == 0)
    let file = await Rig(profile: scProfile(source: .claudeFile("/f"))); await file.step(301); #expect(file.calls() == 0)
    let fallback = await Rig(); fallback.kc.state.withLock { $0.value = .notFound }
    fallback.files.set(CredentialStore.defaultClaudePath, scClaude(1, expiry: fallback.clock.wallNow().addingTimeInterval(-10)))
    await fallback.step(301); #expect(fallback.calls() == 0)
    let wake = await Rig(); await wake.step(301, .wake); #expect(wake.calls() == 0)
    let denied = await Rig(); denied.kc.state.withLock { $0.value = .denied }; await denied.step(301); #expect(denied.calls() == 0)
    for rig in [missing, off, file, fallback, wake, denied] { await rig.monitor.stop() }
}

@Test func nudgeInteractionsWithConnectDenialAndSleep() async {
    let connect = await Rig(); await connect.step(301); #expect(await connect.called(1))
    connect.kc.state.withLock { $0.value = .found(scClaude(2, expiry: connect.clock.wallNow().addingTimeInterval(4000))) }
    await connect.monitor.reconnect("a"); await scFlush(); #expect(await connect.message() == nil)
    await connect.finish(.ran(exitCode: 0)); #expect(await connect.message() == nil)
    let denial = await Rig(); await denial.step(301)
    denial.kc.state.withLock { $0.value = .denied }; await denial.step(301)
    #expect(await denial.message() == scDeniedMessage)
    await denial.finish(.ran(exitCode: 0)); #expect(await denial.message() == scDeniedMessage)
    let asleep = await Rig(); await asleep.step(301); await asleep.monitor.sleep()
    await asleep.finish(.ran(exitCode: 0)); #expect(scMessage(await scRow(asleep.monitor), scPaused))
    for rig in [connect, denial, asleep] { await rig.monitor.stop() }
}

// r12 additions
@Test(arguments: [NudgeOutcome.notFound, .ran(exitCode: 1)])
func secondHourlyAttemptAfterFailureMarksTheRowAndRestoresOnSuccess(_ first: NudgeOutcome) async {
    let rig = await Rig(hold: false); rig.nudger.state.withLock { $0.outcome = first }
    await rig.step(301); #expect(await rig.called(1, message: first == .notFound ? missingText : failedText))
    rig.nudger.state.withLock { ($0.hold, $0.outcome) = (true, .ran(exitCode: 0)) }
    await rig.step(3700); #expect(await rig.called(2, message: nudging))   // a failure message is in the paused family
    await rig.finish(.ran(exitCode: 0)); #expect(await rig.called(2, message: scPaused))
    let reads = rig.kc.state.withLock { $0.reads }
    await rig.step(31); #expect(rig.kc.state.withLock { $0.reads } > reads)   // the re-read is scheduled
    await rig.monitor.stop()
}

@Test func explicitConnectThatRotatesTheTokenClearsTheAttempts() async {
    let rig = await Rig(); await rig.step(301); #expect(await rig.called(1))
    #expect(await rig.monitor.display().nudgeAttempts[rig.source] != nil)
    rig.kc.state.withLock { $0.value = .found(scClaude(2, expiry: rig.clock.wallNow().addingTimeInterval(4000))) }
    await rig.monitor.reconnect("a"); await scFlush()
    #expect(await rig.monitor.display().nudgeAttempts.isEmpty)
    await rig.finish(.ran(exitCode: 0)); await rig.monitor.stop()
}

@Test func attemptStoreIsCalledBeforeTheNudgerRuns() async {
    let rig = await Rig(); await rig.step(301); #expect(await rig.called(1))
    #expect(rig.nudger.order.withLock { $0 } == ["store", "nudge"])
    await rig.finish(.ran(exitCode: 0)); await rig.monitor.stop()
}

// MARK: r13 and r14 additions
/// The frozen fake with group ids (it reports gid 0) and a lock that records its requests and can be refused.
private final class GroupFiles: NudgeFileChecking, @unchecked Sendable {
    let base = CNNudgeFiles(), groups: [String: gid_t], refuseLock: Bool
    let lockRequests = Mutex<[String]>([])
    init(groups: [String: gid_t] = [:], refuseLock: Bool = false) { self.groups = groups; self.refuseLock = refuseLock }
    func access(_ path: String, _ mode: Int32) -> Int32 { base.access(path, mode) }
    func stat(_ path: String) -> Darwin.stat? { base.stat(path).map { var copy = $0; copy.st_gid = groups[path] ?? 0; return copy } }
    func lstat(_ path: String) -> Darwin.stat? { base.lstat(path) }
    func realpath(_ path: String) -> String? { base.realpath(path) }
    func mkdir(_ path: String, _ mode: mode_t) -> Int32 { base.mkdir(path, mode) }
    func chmod(_ path: String, _ mode: mode_t) -> Int32 { base.chmod(path, mode) }
    func exclusiveLock(_ path: String) -> Int32? { lockRequests.withLock { $0.append(path) }; return refuseLock ? nil : -1 }
}
private func outcome(_ files: GroupFiles, candidates: [String] = [cnCandidate]) async -> (NudgeOutcome, CNRunner) {
    let runner = CNRunner()
    return (await ClaudeCLINudger(runner: runner, candidates: candidates, workDirectory: cnWork, home: cnHome, user: cnUser, fileChecks: files).nudge(), runner)
}
private let directoryMode = mode_t(S_IFDIR)

@Test func directoriesGroupWritableByAdminAreAcceptedAndNothingElseIs() async {
    let candidateDirectory = parentDirectory(cnCandidate)
    for (mode, group, accepted) in [(mode_t(0o775), gid_t(80), true), (0o775, 20, false), (0o775, 0, false), (0o777, 80, false), (0o757, 80, false), (0o755, 80, true)] {
        let files = GroupFiles(groups: [candidateDirectory: group]); files.base.candidate(parentMode: directoryMode | mode)
        let (result, runner) = await outcome(files)
        #expect(result == (accepted ? .ran(exitCode: 0) : .notFound) && runner.count() == (accepted ? 1 : 0), Comment(rawValue: "candidate directory \(String(mode, radix: 8)) gid \(group)"))
    }
    for (mode, group, accepted) in [(mode_t(0o775), gid_t(80), true), (0o775, 20, false), (0o777, 80, false)] {
        let files = GroupFiles(groups: [parent + "/lib": group]), target = linked(files.base, libraryMode: directoryMode | mode)
        let (result, runner) = await outcome(files)
        #expect(result == (accepted ? .ran(exitCode: 0) : .notFound) && runner.chose(accepted ? target : ""), Comment(rawValue: "resolved directory \(String(mode, radix: 8)) gid \(group)"))
    }
    let file = GroupFiles(groups: [cnCandidate: 80, candidateDirectory: 80])   // a group-writable file stays rejected, even for admin
    file.base.candidate(mode: mode_t(S_IFREG) | 0o775)
    let (result, runner) = await outcome(file)
    #expect(result == .notFound && runner.count() == 0)
}

@Test func aColonInEitherPathDirectorySkipsTheCandidate() async {
    let colon = parent + "/a:b/claude"
    let first = GroupFiles(); first.base.candidate(colon); first.base.candidate()
    let (one, runnerOne) = await outcome(first, candidates: [colon, cnCandidate])
    #expect(one == .ran(exitCode: 0) && runnerOne.chose(cnCandidate))
    let second = GroupFiles(), target = parent + "/li:b/cli.js"   // the resolved file's directory
    second.base.put(cnCandidate, CNNode(mode: mode_t(S_IFLNK) | 0o755, target: target))
    second.base.put(parentDirectory(cnCandidate), CNNode(mode: directoryMode | 0o755))
    second.base.put(target, CNNode(mode: mode_t(S_IFREG) | 0o755)); second.base.put(parentDirectory(target), CNNode(mode: directoryMode | 0o755))
    let (two, runnerTwo) = await outcome(second)
    #expect(two == .notFound && runnerTwo.count() == 0)
}

@Test func theLockIsTakenAfterTheDirectoriesAndRefusalIsLaunchFailedWithoutSpawning() async {
    let granted = GroupFiles(); granted.base.candidate()
    let (ran, spawned) = await outcome(granted)
    #expect(ran == .ran(exitCode: 0) && spawned.count() == 1 && granted.lockRequests.withLock { $0 } == [cnWork + "/lock"])
    let refused = GroupFiles(refuseLock: true); refused.base.candidate()
    let (result, runner) = await outcome(refused)
    #expect(result == .launchFailed && runner.count() == 0)
    #expect(refused.base.privateDirectory(cnWork) && refused.base.privateDirectory(cnWork + "/tmp"))   // prepared before the lock was asked for
    let failed = GroupFiles(); failed.base.candidate(); failed.base.denyMkdir(cnWork)
    let (none, idle) = await outcome(failed)
    #expect(none == .launchFailed && idle.count() == 0 && failed.lockRequests.withLock { $0 }.isEmpty)
    let plain = CNNudgeFiles(); plain.candidate()   // the frozen fake has no lock of its own: the default lets it run
    #expect(plain.exclusiveLock(cnWork + "/lock") != nil)
}

@Test func twoNudgersOnOneWorkDirectoryNeverRunTheChildTogether() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("nudge-lock-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: root) }
    try FileManager.default.createDirectory(atPath: root + "/bin", withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    #expect(FileManager.default.createFile(atPath: root + "/bin/claude", contents: Data(), attributes: [.posixPermissions: 0o755]))
    let work = root + "/Limitaur/nudge", system = SystemNudgeFileChecks()
    func nudger(_ runner: CNRunner) -> ClaudeCLINudger {
        ClaudeCLINudger(runner: runner, candidates: [root + "/bin/claude"], workDirectory: work, home: root, user: "u", fileChecks: system)
    }
    let first = CNRunner(blocked: true), second = CNRunner(), holder = Task { await nudger(first).nudge() }
    #expect(await cnWait { first.count() == 1 })
    #expect(await nudger(second).nudge() == .launchFailed && second.count() == 0)   // the lock is held until the first runner returns
    first.release()
    #expect(await holder.value == .ran(exitCode: 0))
    #expect(await nudger(second).nudge() == .ran(exitCode: 0) && second.count() == 1)   // and released then
    #expect((system.lstat(work + "/lock")?.st_mode ?? 0) & 0o777 == 0o600)
    // The real lock itself: busy refuses, a symlink at the lock path is not followed, closing releases.
    let held = try #require(system.exclusiveLock(root + "/probe"))
    #expect(system.exclusiveLock(root + "/probe") == nil)
    Darwin.close(held)
    let again = try #require(system.exclusiveLock(root + "/probe")); Darwin.close(again)
    try FileManager.default.createSymbolicLink(atPath: root + "/linked-lock", withDestinationPath: root + "/probe")
    #expect(system.exclusiveLock(root + "/linked-lock") == nil)
}

@Test func aCandidateDirectoryThatIsASymlinkIsCheckedResolvedAndEntersPathUnresolved() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("nudge-link-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: root) }
    try FileManager.default.createDirectory(atPath: root + "/real/bin", withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    #expect(FileManager.default.createFile(atPath: root + "/real/bin/claude", contents: Data(), attributes: [.posixPermissions: 0o755]))
    try FileManager.default.createSymbolicLink(atPath: root + "/link", withDestinationPath: root + "/real/bin")
    let system = SystemNudgeFileChecks(), runner = CNRunner(), candidate = root + "/link/claude"
    let result = await ClaudeCLINudger(runner: runner, candidates: [candidate], workDirectory: root + "/Limitaur/nudge", home: root, user: "u", fileChecks: system).nudge()
    let resolved = try #require(system.realpath(candidate))
    var environment = cnEnvironment(candidate: candidate, resolved: resolved, home: root, user: "u")
    environment["TMPDIR"] = root + "/Limitaur/nudge/tmp/"
    environment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
    #expect(environment.count == 8)
    #expect(result == .ran(exitCode: 0) && runner.chose(resolved) && runner.envMatches(environment))
    #expect(environment["PATH"]!.contains(":" + root + "/link:"))
}

// Monitor: the attempt map has one writer, the monitor's attemptStore.
@Test func restoreStoresTheClampedMapOnlyWhenClampingChangedADate() async {
    let future = await Rig(hold: false, restored: [CredentialSource.claudeDefaultDiscovery.stableID: .distantFuture, "other": .distantPast])
    #expect(future.stores.withLock { $0 } == [[future.source: future.clock.wallNow(), "other": .distantPast]])
    let past = await Rig(hold: false, restored: [CredentialSource.claudeDefaultDiscovery.stableID: Date(timeIntervalSince1970: 1_700_000_000)])
    #expect(past.stores.withLock { $0 }.isEmpty)
    for rig in [future, past] { await rig.monitor.stop() }
}

@Test func everyUnexpiredBindClearsTheClocksAndStoresOnlyWhenSomethingWasRemoved() async {
    let rig = await Rig(expired: false, hold: false)   // nothing to clear: nothing stored, also for an explicit Connect with a new token
    rig.kc.state.withLock { $0.value = .found(scClaude(2, expiry: rig.clock.wallNow().addingTimeInterval(800))) }
    await rig.monitor.reconnect("a"); await scFlush()
    #expect(rig.stores.withLock { $0 }.isEmpty)
    // the same token with a new expiry, through an explicit Connect
    let old = rig.clock.wallNow().addingTimeInterval(-60)
    await rig.monitor.restoreNudgeAttempts([rig.source: old, "other": old])
    rig.kc.state.withLock { $0.value = .found(scClaude(2, expiry: rig.clock.wallNow().addingTimeInterval(1600))) }
    await rig.monitor.reconnect("a"); await scFlush()
    #expect(await rig.monitor.display().nudgeAttempts == ["other": old] && rig.stores.withLock { $0 } == [["other": old]])   // the full normalised map
    await rig.monitor.stop()
    // the first bind at launch with an unexpired token clears a restored attempt
    let launch = await Rig(expired: false, hold: false, restored: [CredentialSource.claudeDefaultDiscovery.stableID: old])
    #expect(await launch.monitor.display().nudgeAttempts.isEmpty && launch.stores.withLock { $0 } == [[:]])
    // a launch whose load is expired keeps them and stores nothing
    let expired = await Rig(hold: false, restored: [CredentialSource.claudeDefaultDiscovery.stableID: old])
    #expect(await expired.monitor.display().nudgeAttempts == [expired.source: old] && expired.stores.withLock { $0 }.isEmpty)
    await launch.monitor.stop(); await expired.monitor.stop()
}

@Test func recordAndClearStoreTheFullMapEachTime() async {
    let source = CredentialSource.claudeDefaultDiscovery.stableID
    let rig = await Rig(restored: [source: Date(timeIntervalSince1970: 1_700_000_000), "other": Date(timeIntervalSince1970: 1_700_000_100)])
    await rig.step(301); #expect(await rig.called(1))
    #expect(rig.stores.withLock { $0 } == [[source: rig.clock.wallNow(), "other": Date(timeIntervalSince1970: 1_700_000_100)]])
    rig.kc.state.withLock { $0.value = .found(scClaude(2, expiry: rig.clock.wallNow().addingTimeInterval(4000))) }
    await rig.monitor.reconnect("a"); await scFlush()
    #expect(rig.stores.withLock { $0 }.last == ["other": Date(timeIntervalSince1970: 1_700_000_100)])
    await rig.finish(.ran(exitCode: 0)); await rig.monitor.stop()
}

// r15/r16 additions (third fix round)
@Test(arguments: [ProcessResult(exitCode: nil, timedOut: true), ProcessResult(exitCode: nil)])
func theLockIsReleasedAfterATimeoutAndAfterANilExitCode(_ result: ProcessResult) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("nudge-release-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: root) }
    try FileManager.default.createDirectory(atPath: root + "/bin", withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    #expect(FileManager.default.createFile(atPath: root + "/bin/claude", contents: Data(), attributes: [.posixPermissions: 0o755]))
    let work = root + "/Limitaur/nudge", system = SystemNudgeFileChecks(), runner = CNRunner(result)
    let outcome = await ClaudeCLINudger(runner: runner, candidates: [root + "/bin/claude"], workDirectory: work, home: root, user: "u", fileChecks: system).nudge()
    #expect(outcome == (result.timedOut ? .timedOut : .launchFailed) && runner.count() == 1)
    let again = try #require(system.exclusiveLock(work + "/lock"))   // the lock was released on the way out
    Darwin.close(again)
}

@Test func theRealLockDescriptorIsCloseOnExec() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("nudge-cloexec-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: root) }
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let fd = try #require(SystemNudgeFileChecks().exclusiveLock(root + "/lock"))
    defer { Darwin.close(fd) }
    #expect(fcntl(fd, F_GETFD) & FD_CLOEXEC != 0)
}

@Test func aMonitorWithTheSettingOffNeverCallsTheStoreAcrossAnExpiredRecheckAndAnUnexpiredBind() async {
    let rig = await Rig(enabled: false, hold: false)
    await rig.step(301)
    #expect(rig.calls() == 0 && rig.stores.withLock { $0 }.isEmpty)   // expired re-check
    rig.kc.state.withLock { $0.value = .found(scClaude(2, expiry: rig.clock.wallNow().addingTimeInterval(4000))) }
    await rig.monitor.reconnect("a"); await scFlush()
    #expect(rig.calls() == 0 && rig.stores.withLock { $0 }.isEmpty && rig.nudger.order.withLock { $0 }.isEmpty)   // unexpired bind
    await rig.monitor.stop()
}
