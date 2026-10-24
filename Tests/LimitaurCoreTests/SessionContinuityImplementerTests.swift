import Foundation
import Synchronization
import Testing
@testable import LimitaurCore

// MARK: A6 runner (real SystemProcessRunner; /bin/sh, /bin/sleep, /usr/bin/env only; private registries)
private func sh(_ script: String, timeout: TimeInterval = 10, grace: TimeInterval = 1, output: OutputMode = .capture(limit: 2_097_154),
                registry: ProcessRegistry? = ProcessRegistry()) -> (result: ProcessResult, seconds: TimeInterval) {
    let start = Date()
    let result = SystemProcessRunner().run(executable: "/bin/sh", arguments: ["-c", script], environment: [:], workingDirectory: nil,
                                           timeout: timeout, graceAfterTerm: grace, output: output, registry: registry)
    return (result, Date().timeIntervalSince(start))
}
private func pidFile() -> String { NSTemporaryDirectory() + "limitaur-pid-" + UUID().uuidString }
private func pid(_ path: String) -> pid_t? {
    (try? String(contentsOfFile: path, encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
}
/// True while the leader is neither exited nor a zombie; the probe does not reap.
private func isRunning(_ pid: pid_t) -> Bool {
    var info = siginfo_t()
    return waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT | WNOHANG) == 0 && info.si_pid == 0
}
private func gone(_ pid: pid_t?) -> Bool {
    guard let pid else { return false }
    for _ in 0..<100 { if kill(pid, 0) != 0 && errno == ESRCH { return true }; usleep(50_000) }
    return false
}

@Suite(.serialized) struct IARunnerTests {
    @Test func capturesOutputAndExitCode() {
        let (r, _) = sh("printf abc")
        // Captured child output is compared into a Boolean so that a failure can never render it.
        let printed = String(decoding: r.output, as: UTF8.self) == "abc"
        #expect(r.exitCode == 0 && printed && !r.timedOut && !r.signaled)
        let env = SystemProcessRunner().run(executable: "/usr/bin/env", arguments: [], environment: ["X": "1"], workingDirectory: nil,
                                            timeout: 5, graceAfterTerm: 1, output: .capture(limit: 100), registry: nil)
        let environmentIsExact = String(decoding: env.output, as: UTF8.self).trimmingCharacters(in: .newlines) == "X=1"
        #expect(environmentIsExact)
        #expect(SystemProcessRunner().run(executable: "sh", arguments: [], environment: [:], workingDirectory: nil, timeout: 1,
                                          graceAfterTerm: 1, output: .discard, registry: nil).exitCode == nil)
        let leaks = ProcessResult(exitCode: 0, output: Data("secret".utf8)).description.contains("secret")
        #expect(!leaks)
    }
    @Test func timeoutKillsTheGroup() {
        for (script, registry) in [("/bin/sleep 30 & echo $! > F; wait", nil),
                                   (#"trap "" TERM; (trap "" TERM; /bin/sleep 30 & echo $! > F; wait) & wait"#, ProcessRegistry())] {
            let file = pidFile()
            let (r, seconds) = sh(script.replacingOccurrences(of: "F;", with: file + ";"), timeout: 0.5, grace: 0.5, registry: registry)
            #expect(r.timedOut && seconds < 3.5)
            #expect(gone(pid(file)))
        }
    }
    @Test func groupAfterExitFollowsTheRegistry() {
        for registered in [true, false] {
            let file = pidFile()
            let (r, seconds) = sh("/bin/sleep 30 >/dev/null 2>&1 & echo $! > \(file); exit 0", registry: registered ? ProcessRegistry() : nil)
            #expect(r.exitCode == 0 && seconds < 3)
            guard let leftover = pid(file), leftover > 0 else { Issue.record("no pid was written to the file"); return }
            #expect(registered ? gone(leftover) : kill(leftover, 0) == 0)
            if !registered { kill(leftover, SIGKILL) }
        }
    }
    @Test func unregisteredTimeoutEndsATermIgnoringDescendantEvenAfterTheLeaderExits() {
        // The leader dies on TERM while its descendant ignores it; the escalation must still end the descendant.
        let file = pidFile()
        let (r, seconds) = sh("(trap '' TERM; /bin/sleep 30 & echo $! > \(file); wait) & wait", timeout: 0.5, grace: 5, registry: nil)
        #expect(r.timedOut && seconds < 3)
        #expect(gone(pid(file)))
    }
    @Test func waitFailuresSignalNothingAndReturnNoExitCode() {
        let file = pidFile(), observed = Mutex<pid_t?>(nil)
        let observe = SystemProcessRunner(observeExit: { child, _ in observed.withLock { $0 = child }; errno = ECHILD; return -1 },
                                          reap: { waitpid($0, &$1, 0) })
        let r = observe.run(executable: "/bin/sh", arguments: ["-c", "echo $$ > \(file); exec /bin/sleep 30"], environment: [:],
                            workingDirectory: nil, timeout: 0.3, graceAfterTerm: 0.2, output: .capture(limit: 10), registry: ProcessRegistry())
        let silent = r.exitCode == nil && !r.signaled && r.output.isEmpty
        #expect(silent)
        for _ in 0..<100 where pid(file) == nil { usleep(50_000) }
        Thread.sleep(forTimeInterval: 1)   // past the timeout and the grace: any stray signal would have landed
        // The runner has no signal seam; a signal after the failure would have ended the sleeping child (a zombie, not a live process).
        let stillRunning = observed.withLock { $0 }.map(isRunning) ?? false
        // Cleanup runs whether or not the pid file was written: kill, then the real reap.
        var status: Int32 = 0
        if let child = observed.withLock({ $0 }) { kill(child, SIGKILL); waitpid(child, &status, 0) }
        if pid(file) == nil { Issue.record("no pid was written to the file") }
        #expect(stillRunning)

        // waitpid fails after the leader exited: the leader stays a zombie and holds the group, a grandchild stands in for a stray signal.
        let leaderFile = pidFile(), grandchildFile = pidFile()
        let leaderPid = Mutex<pid_t?>(nil)
        let second = SystemProcessRunner(observeExit: { child, info in leaderPid.withLock { $0 = child }; return waitid(P_PID, id_t(child), &info, WEXITED | WNOWAIT) },
                                         reap: { _, _ in errno = ECHILD; return -1 })
        let r2 = second.run(executable: "/bin/sh", arguments: ["-c", "echo $$ > \(leaderFile); /bin/sleep 30 >/dev/null 2>&1 & echo $! > \(grandchildFile); exit 3"],
                            environment: [:], workingDirectory: nil, timeout: 0.3, graceAfterTerm: 0.2, output: .discard, registry: nil)
        let unreported = r2.exitCode == nil && !r2.signaled
        #expect(unreported)
        Thread.sleep(forTimeInterval: 1)   // past the timeout and the grace
        let grandchild = pid(grandchildFile)
        let grandchildAlive = grandchild.map { $0 > 0 && kill($0, 0) == 0 } ?? false
        // Cleanup runs unconditionally: the zombie leader still holds the group, so a group kill ends a stray grandchild before the real reap.
        if let leader = leaderPid.withLock({ $0 }) { killpg(leader, SIGKILL); waitpid(leader, &status, 0) }
        if let grandchild, grandchild > 0 { kill(grandchild, SIGKILL) }
        if grandchild == nil { Issue.record("no pid was written to the file") }
        #expect(grandchildAlive)
    }
    @Test func aChildThatExitsBeforeTheDeadlineIsNotTimedOut() {
        // The observation is delayed past the 0.2 s timeout, so the deadline fires while the leader is an unreaped zombie.
        let delayed = SystemProcessRunner(observeExit: { let r = waitid(P_PID, id_t($0), &$1, WEXITED | WNOWAIT); Thread.sleep(forTimeInterval: 0.5); return r },
                                          reap: { waitpid($0, &$1, 0) })
        let r = delayed.run(executable: "/bin/sh", arguments: ["-c", "exit 3"], environment: [:], workingDirectory: nil, timeout: 0.2,
                            graceAfterTerm: 0.2, output: .capture(limit: 10), registry: nil)
        #expect(r.exitCode == 3 && !r.timedOut && !r.signaled)
    }
    @Test func shutdownWaitsForAnAdmittedSpawnToBeRegistered() {
        let registry = ProcessRegistry(), entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let admitted = Mutex<pid_t?>(nil), done = DispatchGroup(), terminated = DispatchSemaphore(value: 0)
        done.enter()
        DispatchQueue.global().async {
            let group = registry.admit {
                var attributes: posix_spawnattr_t?, child: pid_t = 0
                posix_spawnattr_init(&attributes); posix_spawnattr_setpgroup(&attributes, 0); posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
                var argv: [UnsafeMutablePointer<CChar>?] = [strdup("sleep"), strdup("30"), nil]
                defer { for p in argv { free(p) }; posix_spawnattr_destroy(&attributes) }
                guard posix_spawn(&child, "/bin/sleep", nil, &attributes, &argv, nil) == 0 else { return nil }
                entered.signal(); _ = release.wait(timeout: .now() + 10)
                return child
            }
            admitted.withLock { $0 = group }; done.leave()
        }
        #expect(entered.wait(timeout: .now() + 5) == .success)
        DispatchQueue.global().async { registry.terminateAll(); terminated.signal() }
        #expect(terminated.wait(timeout: .now() + 0.3) == .timedOut)   // blocked while the spawn is unregistered
        release.signal()
        #expect(done.wait(timeout: .now() + 5) == .success && terminated.wait(timeout: .now() + 5) == .success)
        var status: Int32 = 0
        if let child = admitted.withLock({ $0 }) { waitpid(child, &status, 0) }
        #expect(status & 0x7f == SIGKILL)
    }
    @Test func signalAndShutdown() {
        let file = pidFile(), registry = ProcessRegistry()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { if let p = pid(file) { kill(p, SIGKILL) } }
        let killed = sh("echo $$ > \(file); exec /bin/sleep 30", registry: registry).result
        #expect(killed.exitCode == nil && killed.signaled)
        let running = DispatchGroup(), box = Mutex<ProcessResult?>(nil)
        running.enter()
        DispatchQueue.global().async { box.withLock { $0 = sh("exec /bin/sleep 30", registry: registry).result }; running.leave() }
        usleep(400_000); registry.terminateAll()
        #expect(running.wait(timeout: .now() + 3) == .success && box.withLock { $0?.signaled } == true)
        #expect(sh("printf x", registry: registry).result.exitCode == nil)
        #expect(sh("printf x", registry: ProcessRegistry()).result.exitCode == 0)
    }
}

// MARK: A7 reader and A8 store with a fake runner
private final class IARunner: ProcessRunning, @unchecked Sendable {
    typealias Call = (exe: String, args: [String], env: [String: String], dir: String?, timeout: TimeInterval, grace: TimeInterval,
                      output: OutputMode, registry: ProcessRegistry?)
    private let lock = NSLock(); private var log: [Call] = []
    let handler: @Sendable (Int) -> ProcessResult
    init(_ handler: @escaping @Sendable (Int) -> ProcessResult) { self.handler = handler }
    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return log }
    func run(executable: String, arguments: [String], environment: [String: String], workingDirectory: String?, timeout: TimeInterval,
             graceAfterTerm: TimeInterval, output: OutputMode, registry: ProcessRegistry?) -> ProcessResult {
        lock.lock(); log.append((executable, arguments, environment, workingDirectory, timeout, graceAfterTerm, output, registry))
        let n = log.count; lock.unlock()
        return handler(n)
    }
}
private func ok(_ text: String) -> ProcessResult { ProcessResult(exitCode: 0, output: Data(text.utf8)) }
private func hex(_ bytes: [UInt8], upper: Bool = false) -> String { bytes.map { String(format: upper ? "%02X" : "%02x", $0) }.joined() }
private func reader(_ runner: IARunner, service: String = "limitaur-test-" + UUID().uuidString,
                    suspensions: KeychainSuspensions = KeychainSuspensions(), registry: ProcessRegistry? = nil) -> SecurityToolKeychainReader {
    SecurityToolKeychainReader(runner: runner, service: service, account: "tester", registry: registry, suspensions: suspensions)
}
private func tag(_ o: KeychainReadOutcome) -> String {
    switch o.result {
    case .found(let d): return "found \(d.count) \(o.reason)"
    case .notFound: return "notFound \(o.reason)"
    case .denied: return "denied \(o.reason)"
    }
}
private let json7 = #"{"a":1}"#

@Test func readerBuildsTheExactCommand() {
    let registry = ProcessRegistry(), runner = IARunner { _ in ok("x") }
    _ = reader(runner, service: "svc-a", registry: registry).claudeCredentialDetailed(interactive: false)
    _ = reader(runner, service: "svc-b", registry: registry).claudeCredentialDetailed(interactive: true)
    let (a, b) = (runner.calls[0], runner.calls[1])
    #expect(a.exe == "/usr/bin/security" && a.args == ["find-generic-password", "-a", "tester", "-s", "svc-a", "-w"])
    #expect(a.env.isEmpty && a.dir == nil && a.output == .capture(limit: 2_097_154) && a.registry === registry)
    #expect(a.timeout == 5 && a.grace == 1 && b.timeout == 600 && b.grace == 5)
}

@Test func readerClassifiesResults() {
    var timedOutZero = ok(json7); timedOutZero = ProcessResult(exitCode: 0, timedOut: true)
    let table: [(ProcessResult, String)] = [
        (ProcessResult(exitCode: 44), "notFound notFound"), (ok(json7 + "\n"), "found 7 found"),
        (ok(hex(Array(json7.utf8)) + "\n"), "found 7 found"), (ok(hex(Array(json7.utf8), upper: true) + "\n"), "found 7 found"),
        (ok("abc"), "found 3 found"), (ok("\n"), "denied oversized"), (ok(String(repeating: "x", count: 1_048_577)), "denied oversized"),
        (ok(String(repeating: "4a", count: 1_048_576) + "\n"), "found 1048576 found"),
        (ok(String(repeating: "4a", count: 1_048_577) + "\n"), "denied oversized"),
        (ProcessResult(exitCode: 0, oversized: true), "denied oversized"), (ProcessResult(exitCode: 36), "denied exit(36)"),
        (ProcessResult(exitCode: 51), "denied exit(51)"), (ProcessResult(exitCode: 128), "denied exit(128)"),
        (ProcessResult(exitCode: 1), "denied exit(1)"), (ProcessResult(exitCode: 300), "denied exit(300)"),
        (ProcessResult(exitCode: nil, signaled: true), "denied signaled"), (ProcessResult(exitCode: nil), "denied launch"),
        (timedOutZero, "denied timeout"), (ProcessResult(exitCode: nil, signaled: true, timedOut: true), "denied timeout")]
    for (result, expected) in table { #expect(tag(reader(IARunner { _ in result }).claudeCredentialDetailed(interactive: false)) == expected) }
    if case .found(let data) = reader(IARunner { _ in ok("abc") }).claudeCredential() { #expect(data == Data("abc".utf8)) } else { Issue.record("abc") }
}

@Test func suspensionRules() {
    for (trigger, suspends) in [(ProcessResult(exitCode: 0, timedOut: true), true), (ProcessResult(exitCode: nil, signaled: true, timedOut: true), true), (ProcessResult(exitCode: 51), true),
                                (ProcessResult(exitCode: 128), true), (ProcessResult(exitCode: 36), false)] {
        let runner = IARunner { _ in trigger }, r = reader(runner)
        _ = r.claudeCredentialDetailed(interactive: false)
        #expect(tag(r.claudeCredentialDetailed(interactive: false)) == (suspends ? "denied suspended" : "denied exit(36)"))
        #expect(runner.calls.count == (suspends ? 1 : 2))
    }
    // a Connect clears the suspension only when it ends found or notFound (r6)
    for (finish, clears) in [(ok(json7), true), (ProcessResult(exitCode: 44), true), (ProcessResult(exitCode: 1), false),
                             (ProcessResult(exitCode: 0, timedOut: true), false)] {
        let runner = IARunner { $0 == 1 ? ProcessResult(exitCode: 51) : finish }, r = reader(runner)
        _ = r.claudeCredentialDetailed(interactive: false)
        _ = r.claudeCredentialDetailed(interactive: true)
        #expect(runner.calls.count == 2)
        _ = r.claudeCredentialDetailed(interactive: false)
        #expect(runner.calls.count == (clears ? 3 : 2))
    }
    let shared = KeychainSuspensions(), a = reader(IARunner { _ in ProcessResult(exitCode: 51) }, suspensions: shared)
    let other = IARunner { _ in ok(json7) }
    _ = a.claudeCredentialDetailed(interactive: false)
    #expect(tag(reader(other, suspensions: shared).claudeCredentialDetailed(interactive: false)) == "found 7 found")
}

@Test func admissionSerialisesReadsOfOneService() {
    let gate = DispatchSemaphore(value: 0), entered = DispatchSemaphore(value: 0)
    let shared = KeychainSuspensions(), service = "limitaur-test-" + UUID().uuidString
    let runner = IARunner { n in
        if n == 1 { entered.signal(); _ = gate.wait(timeout: .now() + 10) }
        return n == 1 ? ProcessResult(exitCode: 51) : ok(json7)
    }
    let r = reader(runner, service: service, suspensions: shared), group = DispatchGroup(), tags = Mutex<[String]>([])
    for _ in 0..<2 { group.enter(); DispatchQueue.global().async { let t = tag(r.claudeCredentialDetailed(interactive: false)); tags.withLock { $0.append(t) }; group.leave() } }
    #expect(entered.wait(timeout: .now() + 5) == .success); gate.signal()
    #expect(group.wait(timeout: .now() + 8) == .success && tags.withLock { $0.sorted() } == ["denied exit(51)", "denied suspended"])
    #expect(runner.calls.count == 1)
    // interactive read in flight: a background read is busy, and a background read that timed out earlier does not suspend
    let slowFirst = DispatchSemaphore(value: 0), slowSecond = DispatchSemaphore(value: 0), spawned = DispatchSemaphore(value: 0)
    let s2 = "limitaur-test-" + UUID().uuidString
    let blocked = IARunner { n in
        spawned.signal()
        _ = (n == 1 ? slowFirst : slowSecond).wait(timeout: .now() + 10)
        return n == 1 ? ProcessResult(exitCode: 0, timedOut: true) : ok(json7)
    }
    let r2 = reader(blocked, service: s2, suspensions: shared)
    group.enter(); DispatchQueue.global().async { _ = r2.claudeCredentialDetailed(interactive: false); group.leave() }
    #expect(spawned.wait(timeout: .now() + 5) == .success)
    group.enter(); DispatchQueue.global().async { _ = r2.claudeCredentialDetailed(interactive: true); group.leave() }
    usleep(200_000)   // the interactive request has no observable hook before it is admitted; it only has to precede the release
    slowFirst.signal()
    #expect(spawned.wait(timeout: .now() + 5) == .success)
    #expect(blocked.calls.count == 2 && !shared.isSuspended(s2))
    #expect(tag(r2.claudeCredentialDetailed(interactive: false)) == "denied busy" && blocked.calls.count == 2)
    slowSecond.signal(); #expect(group.wait(timeout: .now() + 8) == .success)
}

@Test func aSuspensionCausedWhileAnInteractiveReadRunsIsDeferredUntilItEnds() {
    for (finish, applies) in [(ok(json7), false), (ProcessResult(exitCode: 44), false), (ProcessResult(exitCode: 1), true),
                              (ProcessResult(exitCode: 0, timedOut: true), true)] {
        let shared = KeychainSuspensions(), service = "limitaur-test-" + UUID().uuidString
        let slowFirst = DispatchSemaphore(value: 0), slowSecond = DispatchSemaphore(value: 0), spawned = DispatchSemaphore(value: 0)
        let runner = IARunner { n in
            spawned.signal()
            _ = (n == 1 ? slowFirst : slowSecond).wait(timeout: .now() + 10)
            return n == 1 ? ProcessResult(exitCode: 51) : finish
        }
        let r = reader(runner, service: service, suspensions: shared), group = DispatchGroup()
        let background = Mutex<KeychainReadOutcome?>(nil)
        group.enter(); DispatchQueue.global().async { let o = r.claudeCredentialDetailed(interactive: false); background.withLock { $0 = o }; group.leave() }
        #expect(spawned.wait(timeout: .now() + 5) == .success)
        group.enter(); DispatchQueue.global().async { _ = r.claudeCredentialDetailed(interactive: true); group.leave() }
        usleep(200_000)   // the interactive request has no observable hook before it is admitted; it only has to precede the release
        slowFirst.signal()
        #expect(spawned.wait(timeout: .now() + 5) == .success)
        #expect(!shared.isSuspended(service) && background.withLock { $0?.suspendedNow } == false)   // deferred, not applied
        slowSecond.signal(); #expect(group.wait(timeout: .now() + 8) == .success)
        #expect(shared.isSuspended(service) == applies)
    }
}

@Test func aBackgroundReadWaitsForAnActiveBackgroundReadBeyondSixSeconds() {
    let shared = KeychainSuspensions(), service = "limitaur-test-" + UUID().uuidString
    let spawned = DispatchSemaphore(value: 0), group = DispatchGroup(), second = Mutex<String?>(nil)
    let runner = IARunner { n in if n == 1 { spawned.signal(); Thread.sleep(forTimeInterval: 7) }; return ok(json7) }
    let r = reader(runner, service: service, suspensions: shared)
    group.enter(); DispatchQueue.global().async { _ = r.claudeCredentialDetailed(interactive: false); group.leave() }
    #expect(spawned.wait(timeout: .now() + 5) == .success)
    group.enter(); DispatchQueue.global().async { let t = tag(r.claudeCredentialDetailed(interactive: false)); second.withLock { $0 = t }; group.leave() }
    #expect(group.wait(timeout: .now() + 12) == .success)
    #expect(second.withLock { $0 } == "found 7 found" && runner.calls.count == 2)   // waited, then read; never busy
}

@Test func connectDeniedLeavesTheSourceSuspendedAndConnectFoundClearsIt() {
    for (answer, clears) in [(ProcessResult(exitCode: 1), false), (ProcessResult(exitCode: 0, timedOut: true), false),
                             (ProcessResult(exitCode: 44), true), (ok(json7), true)] {
        let shared = KeychainSuspensions(), service = "limitaur-test-" + UUID().uuidString
        let runner = IARunner { $0 == 1 ? ProcessResult(exitCode: 51) : answer }
        let r = reader(runner, service: service, suspensions: shared)
        let causing = r.claudeCredentialDetailed(interactive: false)
        #expect(causing.suspendedNow && causing.reason == .exit(51) && shared.isSuspended(service))
        _ = r.claudeCredentialDetailed(interactive: true)
        #expect(shared.isSuspended(service) == !clears)
        // the interactive mark is always cleared: a background read is refused as suspended, never as busy
        let after = tag(r.claudeCredentialDetailed(interactive: false))
        #expect(clears ? !after.contains("suspended") && !after.contains("busy") : after == "denied suspended")
    }
}

private struct IAFiles: CredentialFileReading {
    let data: Data?
    func read(path: String) throws -> Data { guard let data else { throw CredentialFailure.unreadable }; return data }
}
private func claudeJSON(_ token: String) -> String { #"{"claudeAiOauth":{"accessToken":"\#(token)","expiresAt":1800003600000}}"# }

@Test func storeReportsProvenance() {
    #expect(CredentialStore().keychain is SecurityToolKeychainReader)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func load(_ files: Data?, _ results: [ProcessResult])
        -> (result: Result<Credential, CredentialFailure>, viaKeychain: Bool, suspended: Bool, busy: Bool) {
        CredentialStore(files: IAFiles(data: files), keychain: reader(IARunner { results[min($0, results.count) - 1] }))
            .loadDetailed(.claudeDefaultDiscovery, now: now)
    }
    let found = load(nil, [ok(claudeJSON("tok-a"))])
    #expect(found.viaKeychain && !found.suspended && (try? found.result.get()) != nil)
    let missing = load(Data(claudeJSON("tok-f").utf8), [ProcessResult(exitCode: 44)])
    #expect(!missing.viaKeychain && !missing.suspended && (try? missing.result.get())?.accessToken == "tok-f")
    let denied = load(nil, [ProcessResult(exitCode: 51)])
    // the read that itself suspends the service reports it at once
    #expect(!denied.viaKeychain && denied.suspended && !denied.busy && { if case .failure(.keychainDenied) = denied.result { return true }; return false }())
    let plain = load(nil, [ProcessResult(exitCode: 36)])
    #expect(!plain.suspended && !plain.busy)
    let store = CredentialStore(files: IAFiles(data: nil), keychain: reader(IARunner { _ in ProcessResult(exitCode: 51) }))
    _ = store.loadDetailed(.claudeDefaultDiscovery, now: now)
    let refused = store.loadDetailed(.claudeDefaultDiscovery, now: now)
    #expect(refused.suspended && !refused.busy)
}

@Test func storeReportsBusyWithoutCallingItADenialOfTheSource() {
    let shared = KeychainSuspensions(), service = "limitaur-test-" + UUID().uuidString
    let entered = DispatchSemaphore(value: 0), hold = DispatchSemaphore(value: 0), done = DispatchGroup()
    let slow = reader(IARunner { _ in entered.signal(); _ = hold.wait(timeout: .now() + 10); return ok(json7) }, service: service, suspensions: shared)
    done.enter(); DispatchQueue.global().async { _ = slow.claudeCredentialDetailed(interactive: true); done.leave() }
    #expect(entered.wait(timeout: .now() + 5) == .success)
    let store = CredentialStore(files: IAFiles(data: nil), keychain: reader(IARunner { _ in ok(json7) }, service: service, suspensions: shared))
    let busy = store.loadDetailed(.claudeDefaultDiscovery, now: Date())
    #expect(busy.busy && !busy.suspended && !busy.viaKeychain)
    hold.signal(); #expect(done.wait(timeout: .now() + 5) == .success)
}

// MARK: A9 monitor
private final class IAClock: MonitorClock, @unchecked Sendable {
    private let lock = NSLock(); private var mono: TimeInterval = 100
    func wallNow() -> Date { lock.lock(); defer { lock.unlock() }; return Date(timeIntervalSince1970: 1_800_000_000 + mono - 100) }
    func monotonicNow() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return mono }
    func move(_ seconds: TimeInterval) { lock.lock(); mono += seconds; lock.unlock() }
}
private final class IAKeychain: KeychainReading, @unchecked Sendable {
    private let lock = NSLock(); private var token = "tok-one"; private var gate: DispatchSemaphore?; private(set) var reads = 0
    func claudeCredential() -> KeychainResult {
        lock.lock(); reads += 1; let blocker = gate, value = token; lock.unlock()
        _ = blocker?.wait(timeout: .now() + 10)
        return .found(Data(claudeJSON(value).utf8))
    }
    func set(_ value: String) { lock.lock(); token = value; lock.unlock() }
    func block() { lock.lock(); gate = DispatchSemaphore(value: 0); lock.unlock() }
    func release() { lock.lock(); let blocker = gate; gate = nil; lock.unlock(); blocker?.signal() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
}
private actor IATransport: HTTPTransport {
    private var bearers: [String] = []; private let first: Int, later: Int
    /// `tok-one` answers `first` once, then `later`; any other token answers 200.
    init(first: Int, later: Int? = nil) { self.first = first; self.later = later ?? first }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        bearers.append(request.bearer)
        let status = request.bearer == "tok-one" ? (bearers.count == 1 ? first : later) : 200
        return HTTPResponse(status: status, headers: ["retry-after": "120"], body: Data(#"{"limits":[{"kind":"session","percent":30}]}"#.utf8))
    }
    func seen() -> [String] { bearers }
}
private final class Counter: @unchecked Sendable { let lock = NSLock(); var value = 0; func bump() { lock.lock(); value += 1; lock.unlock() } }
private let claudeProfile = AccountProfile(id: "c", providerID: "claude", label: "Claude", source: .claudeDefaultDiscovery)
private func rig(_ status: Int, then later: Int? = nil, reactive: Bool = true,
                 hook: (@Sendable () -> Void)? = nil) async -> (Monitor, IAClock, IAKeychain, IATransport) {
    let clock = IAClock(), keychain = IAKeychain(), transport = IATransport(first: status, later: later)
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: IAFiles(data: nil), keychain: keychain), transport: transport,
                          reactiveRecheck: reactive, terminateChildren: hook)
    await monitor.setProfiles([claudeProfile]); _ = await monitor.settle()
    return (monitor, clock, keychain, transport)
}
private func signalled(_ semaphore: DispatchSemaphore) -> Bool { semaphore.wait(timeout: .now() + 5) == .success }
private func stat(_ monitor: Monitor, _ name: String) async -> Int { await monitor.statistics()["__eligibility"]?[name] ?? 0 }
private func tick(_ monitor: Monitor, _ clock: IAClock, _ seconds: TimeInterval) async { clock.move(seconds); await monitor.refresh(); _ = await monitor.settle() }
private func shownMessage(_ monitor: Monitor) async -> String? { await monitor.display().profiles.first?.message }

@Test func a401ReReadsAtThirtySecondsAndResumes() async {
    let (monitor, clock, keychain, transport) = await rig(401)
    keychain.set("tok-two")
    await tick(monitor, clock, 10)
    #expect(keychain.count == 1)
    await tick(monitor, clock, 20)
    let (rechecks, resumes) = (await stat(monitor, "credentialRechecks"), await stat(monitor, "credentialResumes"))
    #expect(keychain.count == 2 && rechecks == 1 && resumes == 1)
    #expect(await transport.seen() == ["tok-one", "tok-two"])
    let stats = await monitor.statistics()
    let texts = await monitor.display().profiles.compactMap(\.message) + stats.keys + stats.values.flatMap { $0.keys }
    #expect(!texts.contains { $0.contains("tok-") })
}

@Test func a429RotationCarriesTheThrottleWithoutASnapshot() async {
    let (monitor, clock, keychain, transport) = await rig(429)
    keychain.set("tok-two")
    await tick(monitor, clock, 30)
    let (rotations, resumes) = (await stat(monitor, "credentialRotations"), await stat(monitor, "credentialResumes"))
    let (seen, snapshot) = (await transport.seen(), await monitor.display().profiles.first?.snapshot)
    #expect(rotations == 1 && resumes == 0 && seen == ["tok-one"] && snapshot == nil)
    await tick(monitor, clock, 100)
    #expect(await transport.seen() == ["tok-one", "tok-two"])
}

@Test func aRotationAfterASuccessfulPollCarriesTheThrottleButNoSnapshot() async {
    let (monitor, clock, keychain, transport) = await rig(200, then: 429)
    let before = await monitor.display().profiles.first?.snapshot
    #expect(before != nil)
    for _ in 0..<10 where await transport.seen().count < 2 { await tick(monitor, clock, 60) }
    #expect(await transport.seen() == ["tok-one", "tok-one"])
    #expect(await monitor.display().profiles.first?.snapshot != nil)   // the old token's snapshot stays until the rebind
    keychain.set("tok-two")
    await tick(monitor, clock, 30)
    let (rotations, resumes) = (await stat(monitor, "credentialRotations"), await stat(monitor, "credentialResumes"))
    #expect(rotations == 1 && resumes == 0)
    let (after, requests) = (await monitor.display().profiles.first?.snapshot, await transport.seen())
    #expect(after == nil && requests == ["tok-one", "tok-one"])
}

@Test func anUnpaused429SuspensionShowsItsWordingOnceAndALaterReadRestoresNil() async {
    let runner = IARunner { n in n == 2 ? ProcessResult(exitCode: 51) : ok(claudeJSON(n >= 3 ? "tok-two" : "tok-one")) }
    let clock = IAClock(), transport = IATransport(first: 429)
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: IAFiles(data: nil), keychain: reader(runner)),
                          transport: transport, reactiveRecheck: true)
    await monitor.setProfiles([claudeProfile]); _ = await monitor.settle()
    let wording = "Keychain read did not finish; answer any Keychain dialog, then choose Connect / Authorize"
    await tick(monitor, clock, 30)
    let (shown, suspensions, failures) = (await shownMessage(monitor), await stat(monitor, "keychainSuspensions"),
                                          await stat(monitor, "credentialFailures"))
    #expect(runner.calls.count == 2 && shown == wording && suspensions == 1 && failures == 0)
    await tick(monitor, clock, 30)
    #expect(await stat(monitor, "keychainSuspensions") == 1)
    // a later 429 makes the binding due again; the suspension is in force, so the refused read repeats the wording without a recount
    for _ in 0..<10 where await transport.seen().count < 2 { await tick(monitor, clock, 60) }
    await tick(monitor, clock, 30)
    let (finalShown, finalCount) = (await shownMessage(monitor), await stat(monitor, "keychainSuspensions"))
    #expect(finalCount == 1 && finalShown == wording)
    // a Connect that finds the item clears the suspension, and the later read restores the nil message
    await monitor.reconnect("c"); _ = await monitor.settle()
    // (the Connect reads a new token, which the provider answers 200 once the carried throttle has passed)
    for _ in 0..<5 where await shownMessage(monitor) != nil { await tick(monitor, clock, 60) }
    let (restored, later) = (await shownMessage(monitor), await monitor.isAttached("c"))
    #expect(runner.calls.count == 3 && runner.calls[2].timeout == 600)
    #expect(later && restored == nil)
}

/// Busy while an interactive read is in flight, then free; the token it returns can change.
private final class IAWindow: KeychainReading, @unchecked Sendable {
    private let lock = NSLock(); private var busy: Bool, token = "tok-one"
    init(busy: Bool) { self.busy = busy }
    func claudeCredential() -> KeychainResult { .denied }
    func set(busy value: Bool, token newToken: String? = nil) { lock.lock(); busy = value; if let newToken { token = newToken }; lock.unlock() }
    func claudeCredentialDetailed(interactive: Bool) -> KeychainReadOutcome {
        lock.lock(); defer { lock.unlock() }
        if busy { return KeychainReadOutcome(result: .denied, reason: .busy) }
        return KeychainReadOutcome(result: .found(Data(claudeJSON(token).utf8)), reason: .found)
    }
}

@Test func aBusyLoadOfAnUnboundProfileCompletesOnceTheInteractiveReadFinishes() async {
    let clock = IAClock(), keychain = IAWindow(busy: true)
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: IAFiles(data: nil), keychain: keychain),
                          transport: IATransport(first: 200), reactiveRecheck: true)
    await monitor.setProfiles([claudeProfile]); _ = await monitor.settle()
    // no failure and no binding is the in-flight display, exactly as for a load that has not returned
    let (first, firstAttached) = (await shownMessage(monitor), await monitor.isAttached("c"))
    #expect(first == "Connecting account" && !firstAttached)
    for name in ["credentialFailures", "keychainSuspensions"] { #expect(await stat(monitor, name) == 0) }
    keychain.set(busy: false)
    await tick(monitor, clock, 10)
    let early = await monitor.isAttached("c")
    #expect(!early)   // not before 30 s after the busy load
    await tick(monitor, clock, 20)
    let (attached, shown, failures) = (await monitor.isAttached("c"), await shownMessage(monitor), await stat(monitor, "credentialFailures"))
    #expect(attached && shown == nil && failures == 0)
}

private final class IAGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0), hold = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
}

/// A 401-paused binding (so `recheckDue` is set) whose Connect child is in flight across a sleep; the wake replay meets the
/// real reader's interactive mark and answers busy. The child is then released, so the reader is free again.
/// Reads: 1 initial, 2 the Connect (held, 600 s), 3 and later answer `retryToken`.
private func busyReplayRig(retryToken: String) async -> (Monitor, IAClock, IARunner, IATransport) {
    let gate = IAGate()
    let runner = IARunner { n in
        if n == 2 { gate.entered.signal(); _ = gate.hold.wait(timeout: .now() + 20); gate.done.signal() }
        return ok(claudeJSON(n == 1 || n == 2 ? "tok-one" : retryToken))
    }
    let clock = IAClock(), transport = IATransport(first: 401, later: 200)
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: IAFiles(data: nil), keychain: reader(runner)),
                          transport: transport, reactiveRecheck: true)
    await monitor.setProfiles([claudeProfile]); _ = await monitor.settle()
    let paused = await shownMessage(monitor)
    #expect(paused?.hasPrefix("Session expired") == true)
    await monitor.reconnect("c")
    #expect(signalled(gate.entered))
    await monitor.sleep()
    await monitor.wake()
    _ = await monitor.settle()
    let (parked, parkedShown) = (await monitor.isAttached("c"), await shownMessage(monitor))
    #expect(runner.calls.count == 2 && !parked && parkedShown == "Connecting account")   // busy: the replay issued no child
    gate.hold.signal()
    #expect(signalled(gate.done))
    usleep(200_000)   // the child's result is discarded; the reader releases its interactive mark just after the read returns
    return (monitor, clock, runner, transport)
}

@Test func aBusyWakeReplayRetriesOnceAtThirtySecondsAlongsideADueReCheck() async {
    for retryToken in ["tok-one", "tok-two"] {
        let (monitor, clock, runner, transport) = await busyReplayRig(retryToken: retryToken)
        await tick(monitor, clock, 30)
        let (rechecks, resumes) = (await stat(monitor, "credentialRechecks"), await stat(monitor, "credentialResumes"))
        let (attached, shown) = (await monitor.isAttached("c"), await shownMessage(monitor))
        #expect(runner.calls.count == 3 && runner.calls[2].timeout == 5)   // exactly one read at the retry
        #expect(rechecks == 0 && resumes == 0)
        #expect(attached && shown == nil)
        #expect(await transport.seen().count == 2)
    }
}

@Test func aNewerConnectConsumesAnOlderBusyRetry() async {
    let (monitor, clock, runner, _) = await busyReplayRig(retryToken: "tok-one")
    clock.move(5)
    await monitor.reconnect("c"); _ = await monitor.settle()   // the same token again: a Connect resumes
    let (attached, shown, calls) = (await monitor.isAttached("c"), await shownMessage(monitor), runner.calls.count)
    #expect(attached && shown == nil && calls == 3 && runner.calls[2].timeout == 600)
    await tick(monitor, clock, 30)
    let (after, rechecks) = (runner.calls.count, await stat(monitor, "credentialRechecks"))
    // The stale re-check left by the 401 is the only read after the Connect; the old busy retry (an explicit load) was consumed.
    #expect(after == 4 && rechecks == 1)
    let (stillAttached, stillShown) = (await monitor.isAttached("c"), await shownMessage(monitor))
    #expect(stillAttached && stillShown == nil)
}

@Test func aDefaultMonitorTreatsABusyLoadAsADenial() async {
    let clock = IAClock(), keychain = IAWindow(busy: true)
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: IAFiles(data: nil), keychain: keychain),
                          transport: IATransport(first: 200))
    await monitor.setProfiles([claudeProfile]); _ = await monitor.settle()
    #expect(await shownMessage(monitor) == "Keychain access unavailable; choose Connect / Authorize")
    #expect(await stat(monitor, "credentialFailures") == 1)
    keychain.set(busy: false)
    await tick(monitor, clock, 60)   // nothing was recorded for a retry
    let (attached, failures) = (await monitor.isAttached("c"), await stat(monitor, "credentialFailures"))
    #expect(!attached && failures == 1)
}

@Test func sleepDuringConnectThenWakeBindsOnceTheInteractiveReadFinishes() async {
    let entered = DispatchSemaphore(value: 0), gate = DispatchSemaphore(value: 0)
    let runner = IARunner { n in
        if n == 1 { return ProcessResult(exitCode: 1) }
        if n == 2 { entered.signal(); _ = gate.wait(timeout: .now() + 20) }
        return ok(claudeJSON("tok-s"))
    }
    let clock = IAClock()
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: IAFiles(data: nil), keychain: reader(runner)),
                          transport: IATransport(first: 200), reactiveRecheck: true)
    await monitor.setProfiles([claudeProfile]); _ = await monitor.settle()
    await monitor.reconnect("c")
    #expect(signalled(entered))   // the Connect's child is in flight
    await monitor.sleep()                                     // its task is cancelled; the child outlives it
    await monitor.wake()                                      // the replay meets the interactive read
    _ = await monitor.settle()
    let (parked, parkedShown) = (await monitor.isAttached("c"), await shownMessage(monitor))
    #expect(runner.calls.count == 2 && !parked && parkedShown == "Connecting account")
    gate.signal()
    for _ in 0..<10 {
        if await monitor.isAttached("c") { break }
        await tick(monitor, clock, 30); usleep(50_000)
    }
    let (attached, shown) = (await monitor.isAttached("c"), await shownMessage(monitor))
    #expect(attached && shown == nil && runner.calls.count == 3)
    #expect(runner.calls[1].timeout == 600 && runner.calls[2].timeout == 5)
}

@Test func aWakeReCheckThatSuspendsShowsTheSuspendedWording() async {
    let runner = IARunner { $0 == 1 ? ok(claudeJSON("tok-one")) : ProcessResult(exitCode: 51) }
    let clock = IAClock()
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: IAFiles(data: nil), keychain: reader(runner)),
                          transport: IATransport(first: 401), reactiveRecheck: true)
    await monitor.setProfiles([claudeProfile]); _ = await monitor.settle()
    let paused = await shownMessage(monitor)
    #expect(paused?.hasPrefix("Session expired") == true)
    await monitor.sleep(); clock.move(60); await monitor.wake(); _ = await monitor.settle()
    let wording = "Keychain read did not finish; answer any Keychain dialog, then choose Connect / Authorize"
    let (shown, suspensions, failures) = (await shownMessage(monitor), await stat(monitor, "keychainSuspensions"), await stat(monitor, "credentialFailures"))
    #expect(runner.calls.count == 2 && shown == wording && suspensions == 1 && failures == 0)
}

@Test func aDefaultMonitorKeepsBaselineDenialHandling() async {
    let runner = IARunner { _ in ProcessResult(exitCode: 51) }
    let clock = IAClock()
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: IAFiles(data: nil), keychain: reader(runner)),
                          transport: IATransport(first: 200), recheckInterval: 60)
    await monitor.setProfiles([claudeProfile]); _ = await monitor.settle()
    await tick(monitor, clock, 60); await tick(monitor, clock, 60)
    #expect(await shownMessage(monitor) == "Keychain access unavailable; choose Connect / Authorize")
    #expect(await stat(monitor, "keychainSuspensions") == 0)
}

@Test func theSameTokenChangesNothingAndIsNotReReadEarly() async {
    let (monitor, clock, keychain, _) = await rig(429)
    await tick(monitor, clock, 10); #expect(keychain.count == 1)
    await tick(monitor, clock, 20); #expect(keychain.count == 2)
    await tick(monitor, clock, 5)
    let changes = await stat(monitor, "credentialRotations") + stat(monitor, "credentialResumes")
    #expect(keychain.count == 2 && changes == 0)
}

@Test func theDueReReadHonoursItsGuards() async {
    for scenario in 0..<4 {
        let (monitor, clock, keychain, _) = await rig(401)
        keychain.set("tok-two"); clock.move(60)
        switch scenario {
        case 0: await monitor.sleep(); await monitor.refresh()
        case 1: await monitor.refresh(force: true, driver: .internal)
        case 2: keychain.block(); await monitor.reconnect("c"); await monitor.refresh()
        default: var off = claudeProfile; off.enabled = false; await monitor.setProfiles([off]); await monitor.refresh()
        }
        #expect(await stat(monitor, "credentialRechecks") == 0)
        keychain.release(); _ = await monitor.settle()
        if scenario == 2 { #expect(await monitor.isAttached("c")) }
    }
    for (status, reactive) in [(401, false), (429, false)] {
        let (monitor, clock, keychain, _) = await rig(status, reactive: reactive)
        keychain.set("tok-two"); await tick(monitor, clock, 60)
        #expect(keychain.count == 1)
    }
}

@Test func suspendedReadShowsItsWordingOnceAndConnectIsInteractive() async {
    let runner = IARunner { $0 == 1 ? ProcessResult(exitCode: 51) : ok(claudeJSON("tok-s")) }
    let clock = IAClock(), suspensions = KeychainSuspensions()
    let monitor = Monitor(clock: clock, credentials: CredentialStore(files: IAFiles(data: nil), keychain: reader(runner, suspensions: suspensions)),
                          transport: IATransport(first: 200), recheckInterval: 60, reactiveRecheck: true)
    await monitor.setProfiles([claudeProfile]); _ = await monitor.settle()
    // the causing read already shows the suspended wording (r6)
    let wording = "Keychain read did not finish; answer any Keychain dialog, then choose Connect / Authorize"
    #expect(await shownMessage(monitor) == wording)
    await tick(monitor, clock, 60); await tick(monitor, clock, 60)
    #expect(await shownMessage(monitor) == wording)
    #expect(await stat(monitor, "keychainSuspensions") == 1 && runner.calls.count == 1)
    await monitor.reconnect("c"); _ = await monitor.settle()
    let attached = await monitor.isAttached("c")
    #expect(runner.calls.count == 2 && runner.calls[1].timeout == 600 && attached)
}

@Test func stopCallsTheChildHookOnce() async {
    let counter = Counter()
    let (monitor, _, _, _) = await rig(200, hook: { counter.bump() })
    await monitor.stop()
    #expect(counter.value == 1)
}
