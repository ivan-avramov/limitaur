import Foundation
import Darwin

public enum NudgeOutcome: Sendable, Equatable { case ran(exitCode: Int32), notFound, launchFailed, timedOut }
public protocol SessionNudging: Sendable { func nudge() async -> NudgeOutcome; func waitForCompletion(upTo: TimeInterval) }

public protocol NudgeFileChecking: Sendable {
    func access(_ path: String, _ mode: Int32) -> Int32
    func stat(_ path: String) -> Darwin.stat?    // follows symlinks; nil on failure
    func lstat(_ path: String) -> Darwin.stat?   // does not follow symlinks; nil on failure
    func realpath(_ path: String) -> String?
    func mkdir(_ path: String, _ mode: mode_t) -> Int32
    func chmod(_ path: String, _ mode: mode_t) -> Int32
    func exclusiveLock(_ path: String) -> Int32?  // nil when busy or unopenable; the caller closes the descriptor
}
extension NudgeFileChecking { public func exclusiveLock(_ path: String) -> Int32? { -1 } }  // placeholder: no lock taken
private func status(_ path: String, follow: Bool) -> stat? {
    var st = stat()
    return (follow ? stat(path, &st) : lstat(path, &st)) == 0 ? st : nil
}
public struct SystemNudgeFileChecks:NudgeFileChecking {
    public init() {}
    public func access(_ path: String, _ mode: Int32) -> Int32 { Darwin.access(path, mode) }
    public func stat(_ path: String) -> Darwin.stat? { status(path, follow: true) }
    public func lstat(_ path: String) -> Darwin.stat? { status(path, follow: false) }
    public func realpath(_ path: String) -> String? { Darwin.realpath(path, nil).map { defer { free($0) }; return String(cString: $0) } }
    public func mkdir(_ path: String, _ mode: mode_t) -> Int32 { Darwin.mkdir(path, mode) }
    public func chmod(_ path: String, _ mode: mode_t) -> Int32 { Darwin.chmod(path, mode) }
    public func exclusiveLock(_ path: String) -> Int32? {
        let fd = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        if fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 { return fd }
        if fd >= 0 { Darwin.close(fd) }; return nil
    }
}

public struct ClaudeCLINudger: SessionNudging {
    public static let defaultCandidates: [String] = [NSHomeDirectory() + "/.local/bin/claude", "/opt/homebrew/bin/claude",
                                                     "/usr/local/bin/claude", NSHomeDirectory() + "/.claude/local/claude"]
    private let runner: any ProcessRunning, candidates: [String], workDirectory: String, home: String, user: String
    private let fileChecks: any NudgeFileChecking, running = DispatchGroup()
    public init(runner: any ProcessRunning = SystemProcessRunner(), candidates: [String] = defaultCandidates,
                workDirectory: String = NSHomeDirectory() + "/Library/Application Support/Limitaur/nudge",
                home: String = NSHomeDirectory(), user: String = NSUserName(), fileChecks: any NudgeFileChecking = SystemNudgeFileChecks()) {
        self.runner = runner; self.candidates = candidates; self.workDirectory = workDirectory
        self.home = home; self.user = user; self.fileChecks = fileChecks
    }
    public func nudge() async -> NudgeOutcome {
        running.enter()
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { let outcome = run(); running.leave(); continuation.resume(returning: outcome) }
        }
    }
    public func waitForCompletion(upTo bound: TimeInterval) { _ = running.wait(timeout: .now() + bound) }

    private func trusted(_ path: String, directory: Bool) -> Bool {
        guard let st = fileChecks.stat(path), st.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG) else { return false }
        return (st.st_uid == getuid() || st.st_uid == 0) && st.st_mode & 0o002 == 0 && (st.st_mode & 0o020 == 0 || (directory && st.st_gid == 80))   // admin (gid 80) can become root anyway
    }
    private func prepared(_ path: String) -> Bool {   // created at 0700 if absent; a real directory of the user at 0700 after correction
        if fileChecks.lstat(path) == nil, fileChecks.mkdir(path, 0o700) != 0 { return false }
        guard var st = fileChecks.lstat(path), st.st_mode & S_IFMT == S_IFDIR, st.st_uid == getuid() else { return false }
        if st.st_mode & 0o777 != 0o700 {
            guard fileChecks.chmod(path, 0o700) == 0, let again = fileChecks.lstat(path) else { return false }
            st = again
        }
        return st.st_mode & 0o777 == 0o700
    }
    private func run() -> NudgeOutcome {
        let directory = { (path: String) in (path as NSString).deletingLastPathComponent }
        var found: (candidate: String, resolved: String)?
        for path in candidates where fileChecks.access(path, X_OK) == 0 {
            if let resolved = fileChecks.realpath(path), trusted(resolved, directory: false), ![path, resolved].contains(where: { directory($0).contains(":") }),
               trusted(directory(path), directory: true), trusted(directory(resolved), directory: true) { found = (path, resolved); break }
        }
        guard let (candidate, resolved) = found else { return .notFound }
        let tmp = workDirectory + "/tmp"
        guard [directory(workDirectory), workDirectory, tmp].allSatisfy(prepared),
              let lock = fileChecks.exclusiveLock(workDirectory + "/lock") else { return .launchFailed }
        defer { Darwin.close(lock) }   // the lock is held until the runner returns
        let path = ["/usr/bin", "/bin", "/usr/sbin", "/sbin", directory(candidate), directory(resolved)].joined(separator: ":")
        let result = runner.run(
            executable: resolved, arguments: ["-p", "hi", "--model", "haiku", "--safe-mode", "--no-session-persistence", "--strict-mcp-config", "--tools", ""],
            environment: ["HOME": home, "USER": user, "LOGNAME": user, "PATH": path, "LANG": "en_US.UTF-8",
                          "TMPDIR": tmp + "/", "DISABLE_AUTOUPDATER": "1", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"],
            workingDirectory: workDirectory, timeout: 60, graceAfterTerm: 10, output: .discard, registry: nil)
        if result.timedOut { return .timedOut }
        return result.exitCode.map { .ran(exitCode: $0) } ?? .launchFailed
    }
}
