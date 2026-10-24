import Foundation
import Darwin
import Synchronization

public enum OutputMode: Sendable, Equatable { case capture(limit: Int), discard }

public struct ProcessResult: Sendable, Equatable, CustomStringConvertible {
    public let exitCode: Int32?
    public let signaled: Bool
    public let output: Data
    public let timedOut: Bool
    public let oversized: Bool
    public init(exitCode: Int32?, signaled: Bool = false, output: Data = Data(), timedOut: Bool = false, oversized: Bool = false) {
        self.exitCode = exitCode; self.signaled = signaled; self.output = output
        self.timedOut = timedOut; self.oversized = oversized
    }
    public var description: String {
        "ProcessResult(exit: \(exitCode.map(String.init) ?? "nil"), signaled: \(signaled), timedOut: \(timedOut), "
            + "oversized: \(oversized), outputBytes: \(output.count))"
    }
}

public protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String], environment: [String: String], workingDirectory: String?,
             timeout: TimeInterval, graceAfterTerm: TimeInterval, output: OutputMode, registry: ProcessRegistry?) -> ProcessResult
}

public final class ProcessRegistry: Sendable {
    public static let shared = ProcessRegistry()
    private struct State { var groups = Set<pid_t>(); var shuttingDown = false }
    private let state = Mutex(State())
    public init() {}
    public func terminateAll() {
        state.withLock { $0.shuttingDown = true; for group in $0.groups { killpg(group, SIGKILL) } }
    }
    var isShuttingDown: Bool { state.withLock { $0.shuttingDown } }
    /// Checks the flag, spawns and registers under one lock hold, so `terminateAll()` cannot return between them.
    func admit(_ spawn: () -> pid_t?) -> pid_t? {
        state.withLock {
            guard !$0.shuttingDown, let group = spawn() else { return nil }
            $0.groups.insert(group)
            return group
        }
    }
    func remove(_ group: pid_t) { state.withLock { _ = $0.groups.remove(group) } }
}

private struct RunState { var exited = false, reaped = false, timedOut = false, oversized = false, stop = false; var data = Data() }

/// The runner is the only reaper in the process: nothing else may `wait` on a child it spawned.
public struct SystemProcessRunner: ProcessRunning {
    typealias Observe = @Sendable (pid_t, inout siginfo_t) -> Int32
    typealias Reap = @Sendable (pid_t, inout Int32) -> Int32
    private let observeExit: Observe, reap: Reap
    public init() { self.init(observeExit: { waitid(P_PID, id_t($0), &$1, WEXITED | WNOWAIT) }, reap: { waitpid($0, &$1, 0) }) }
    /// Injection point for the kernel wait calls.
    init(observeExit: @escaping Observe, reap: @escaping Reap) { self.observeExit = observeExit; self.reap = reap }
    public func run(executable: String, arguments: [String], environment: [String: String], workingDirectory: String?,
                    timeout: TimeInterval, graceAfterTerm: TimeInterval, output: OutputMode, registry: ProcessRegistry?) -> ProcessResult {
        let failed = ProcessResult(exitCode: nil)
        guard executable.hasPrefix("/"), registry?.isShuttingDown != true else { return failed }
        var fds: [Int32] = [-1, -1]
        var limit: Int?
        if case .capture(let value) = output {
            guard pipe(&fds) == 0 else { return failed }
            _ = fcntl(fds[0], F_SETFD, FD_CLOEXEC); _ = fcntl(fds[0], F_SETFL, O_NONBLOCK)
            limit = value
        }
        var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        if limit != nil { posix_spawn_file_actions_adddup2(&actions, fds[1], 1) }
        else { posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0) }
        if let workingDirectory { posix_spawn_file_actions_addchdir(&actions, workingDirectory) }
        var defaults = sigset_t(), mask = sigset_t()
        sigfillset(&defaults); sigemptyset(&mask)
        posix_spawnattr_setsigdefault(&attributes, &defaults); posix_spawnattr_setsigmask(&attributes, &mask)
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) } + [nil]
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for pointer in argv + envp { free(pointer) } }
        let spawn: () -> pid_t? = {
            var spawned: pid_t = 0
            return posix_spawn(&spawned, executable, &actions, &attributes, &argv, &envp) == 0 ? spawned : nil
        }
        let admitted = registry.map { $0.admit(spawn) } ?? spawn()
        if limit != nil { close(fds[1]) }
        guard let pid = admitted else { if limit != nil { close(fds[0]) }; return failed }

        let state = Mutex(RunState())
        // Until the leader is reaped, its zombie still holds the group id, so signalling cannot reach a recycled group.
        let signalGroup: @Sendable (Int32) -> Void = { signal in
            state.withLock { if !$0.reaped { killpg(pid, signal) } }
        }
        let escalate = DispatchWorkItem { signalGroup(SIGKILL) }
        let expire = DispatchWorkItem {
            // A leader that already exited (still a zombie, so the group id is held) is not timed out.
            // A failed probe counts as still running; signalling stays guarded by the reaped flag.
            var probe = siginfo_t(), status: Int32
            repeat { probe = siginfo_t(); status = waitid(P_PID, id_t(pid), &probe, WEXITED | WNOWAIT | WNOHANG) }
            while status < 0 && errno == EINTR
            let running = status != 0 || probe.si_pid == 0
            let live = state.withLock { s -> Bool in if s.exited || !running { return false }; s.timedOut = true; return true }
            guard live else { return }
            signalGroup(SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + graceAfterTerm, execute: escalate)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: expire)

        let drained = DispatchSemaphore(value: 0)
        if let limit {
            let descriptor = fds[0]
            DispatchQueue.global(qos: .utility).async {
                var chunk = [UInt8](repeating: 0, count: 65_536)
                while !state.withLock({ $0.stop }) {
                    var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                    if poll(&poller, 1, 50) < 0 { if errno == EINTR { continue }; break }
                    if poller.revents == 0 { continue }
                    let count = read(descriptor, &chunk, chunk.count)
                    if count == 0 { break }
                    if count < 0 { if errno == EAGAIN || errno == EINTR { continue }; break }
                    let over = state.withLock { s -> Bool in
                        s.data.append(contentsOf: chunk.prefix(min(count, limit + 1 - s.data.count)))
                        if s.data.count > limit { s.oversized = true }
                        return s.oversized
                    }
                    if over { signalGroup(SIGKILL); break }
                }
                drained.signal()
            }
        }

        func finishDrain() {
            guard limit != nil else { return }
            if drained.wait(timeout: .now() + 2) == .timedOut { state.withLock { $0.stop = true }; drained.wait() }
            close(fds[0])
        }
        // When the kernel will not report the child, no signal is sent (the group id may be recycled).
        func abandon(drain: Bool) -> ProcessResult {
            state.withLock { $0.exited = true; $0.reaped = true; $0.stop = true }
            escalate.cancel()
            if drain { finishDrain() }
            registry?.remove(pid)
            return state.withLock { s in
                defer { s.data = Data() }
                return ProcessResult(exitCode: nil, timedOut: s.timedOut)
            }
        }

        var info = siginfo_t()
        while observeExit(pid, &info) < 0 { if errno != EINTR { return abandon(drain: true) } }
        let timedOut = state.withLock { s -> Bool in s.exited = true; return s.timedOut }
        expire.cancel()
        // A timed-out run completes its escalation here, so a TERM-ignoring descendant does not outlive it;
        // `escalate` itself stays armed until the reap.
        if registry != nil || timedOut { killpg(pid, SIGKILL) }
        finishDrain()
        registry?.remove(pid)
        state.withLock { $0.reaped = true }
        var reaped: Int32 = 0
        while reap(pid, &reaped) < 0 { if errno != EINTR { return abandon(drain: false) } }
        escalate.cancel()
        let normal = info.si_code == CLD_EXITED
        return state.withLock { s in
            defer { s.data = Data() }
            return ProcessResult(exitCode: normal ? info.si_status & 0xFF : nil, signaled: !normal, output: s.oversized ? Data() : s.data,
                                 timedOut: s.timedOut, oversized: s.oversized)
        }
    }
}
