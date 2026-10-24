import Foundation
import Darwin
import Testing
@testable import LimitaurCore

// Only the three executables authorized by the brief are launched. PID scratch
// files contain decimal PIDs only, live in this test directory, and are removed.
private final class SCPIDFile: @unchecked Sendable {
    private let cleanupDescendant: Bool
    init(cleanupDescendant: Bool = true) { self.cleanupDescendant = cleanupDescendant }
    let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("pid-" + UUID().uuidString).path
    func pid() -> pid_t? {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8), let pid = Int32(text), pid > 1 else { return nil }
        return pid
    }
    deinit {
        if cleanupDescendant, let pid = pid(), !scGone(pid) { _ = kill(pid, SIGKILL) }
        try? FileManager.default.removeItem(atPath: path)
    }
}
private func scRun(_ script: String, args: [String] = [], timeout: TimeInterval = 0.3,
                   grace: TimeInterval = 0.2, output: OutputMode = .capture(limit: 1024),
                   registry: ProcessRegistry? = ProcessRegistry(), directory: String? = nil) -> ProcessResult {
    SystemProcessRunner().run(executable: "/bin/sh", arguments: ["-c", script, "sc-test"] + args,
                              environment: [:], workingDirectory: directory, timeout: timeout,
                              graceAfterTerm: grace, output: output, registry: registry)
}
private func scGone(_ pid: pid_t) -> Bool { kill(pid, 0) == -1 && errno == ESRCH }

@Suite(.serialized) struct SessionContinuityProcessRunnerTests {
    // Preserves invariant A1: stdout is captured, stderr discarded, stdin EOF.
    @Test func capturesStdoutAndClosesStandardInputAndError() {
        let result = scRun("printf abc; printf hidden >&2; if read value; then exit 7; fi")
        #expect(result.exitCode == 0); #expect(result.output == Data("abc".utf8))
        #expect(!result.signaled && !result.timedOut && !result.oversized)
    }

    // Preserves invariant A1/A6: exact environment, no ambient HOME/PATH/credentials.
    @Test func environmentIsExactlySupplied() {
        let result = SystemProcessRunner().run(executable: "/usr/bin/env", arguments: [], environment: ["X": "1"],
            workingDirectory: nil, timeout: 1, graceAfterTerm: 0.1, output: .capture(limit: 1024), registry: ProcessRegistry())
        let exact = result.output == Data("X=1\n".utf8)
        #expect(exact); #expect(result.exitCode == 0)
    }

    // Preserves invariant A1: arguments are literal, never shell-expanded by runner.
    @Test func literalArgumentsAndWorkingDirectory() {
        let literal = "$(printf injected); `printf injected` * \" ' $HOME\nnext"
        let result = scRun("printf '%s' \"$1\"; printf '|'; pwd -P", args: [literal],
                           directory: "/private/tmp")
        let exact = result.output == Data((literal + "|/private/tmp\n").utf8)
        #expect(exact); #expect(result.exitCode == 0)
    }

    // Exercises new behaviour A1: invalid executable/directory return launch failure.
    @Test(arguments: ["relative", "directory"])
    func rejectsInvalidLaunch(_ variant: String) {
        let result = SystemProcessRunner().run(executable: variant == "relative" ? "bin/sh" : "/bin/sh",
            arguments: ["-c", "exit 0"], environment: [:],
            workingDirectory: variant == "directory" ? "/does-not-exist-sc-" + UUID().uuidString : nil,
            timeout: 0.2, graceAfterTerm: 0.1, output: .discard, registry: ProcessRegistry())
        #expect(result.exitCode == nil); #expect(!result.signaled)
    }

    // Reproduces fixed failure A6: timeout kills leader and its sleeping grandchild.
    @Test(arguments: [false, true])
    func timeoutKillsWholeGroupIncludingTermIgnoringChildren(_ ignoreTerm: Bool) async {
        let pidFile = SCPIDFile(), registry = ProcessRegistry()
        defer { registry.terminateAll() }
        let script = (ignoreTerm ? "trap '' TERM; " : "") +
            "( " + (ignoreTerm ? "trap '' TERM; " : "") +
            "exec /bin/sleep 30 ) & printf '%s' $! > \"$1\"; wait"
        let start = ContinuousClock.now
        let result = scRun(script, args: [pidFile.path], timeout: 0.5, grace: 0.5, registry: registry)
        #expect(start.duration(to: .now) < .seconds(ignoreTerm ? 4 : 3))
        #expect(result.timedOut)
        if let pid = pidFile.pid() { #expect(await scWait { scGone(pid) }) }
        else { Issue.record("Child PID was not recorded") }
    }

    // Reproduces fixed failure A1/A6: leader exit cleans registered descendants;
    // preserves the explicit nil-registry exception. Test kills the surviving child.
    @Test(arguments: [false, true])
    func exitedLeaderCleansOnlyRegisteredGrandchildren(_ registered: Bool) async {
        let file = SCPIDFile(), registry = ProcessRegistry()
        defer { registry.terminateAll() }
        let start = ContinuousClock.now
        let result = scRun("( /bin/sleep 30 >/dev/null 2>&1 & printf '%s' $! > \"$1\" ); exit 0",
                           args: [file.path], timeout: 1, registry: registered ? registry : nil)
        #expect(start.duration(to: .now) < .seconds(3)); #expect(result.exitCode == 0)
        if let pid = file.pid() {
            if registered { #expect(await scWait { scGone(pid) }) }
            else { #expect(kill(pid, 0) == 0); _ = kill(pid, SIGKILL) }
        } else { Issue.record("Grandchild PID was not recorded") }
    }

    // Exercises new behaviour A1: pipe EOF held by an unregistered descendant is bounded.
    @Test func inheritedPipeCannotHangAfterLeaderExit() {
        let file = SCPIDFile(), start = ContinuousClock.now
        let result = scRun("/bin/sleep 30 & printf '%s' $! > \"$1\"; exit 0", args: [file.path],
                           timeout: 1, registry: nil)
        #expect(start.duration(to: .now) < .seconds(3)); #expect(result.exitCode == 0)
        #expect(!result.timedOut)
    }

    // Exercises new behaviour A1/A6: limit is inclusive, overflow bounded, discard unbounded.
    // Shell builtins replace A6's yes/head so no other executable is invoked.
    @Test(arguments: [0, 1, 2])
    func captureBoundaryAndDiscardLargeOutput(_ variant: Int) {
        let chunk = String(repeating: "x", count: 1024)
        let script = "i=0; while [ $i -lt 5120 ]; do printf '%s' \"$1\"; i=$((i+1)); done"
        let start = ContinuousClock.now
        let result = variant == 0
            ? scRun("printf abc", output: .capture(limit: 3))
            : scRun(script, args: [chunk], timeout: 2, output: variant == 1 ? .capture(limit: 2_097_154) : .discard)
        #expect(start.duration(to: .now) < .seconds(3))
        if variant == 0 { #expect(result.exitCode == 0); #expect(!result.oversized); #expect(result.output.count == 3) }
        if variant == 1 { #expect(result.oversized); #expect(result.output.count <= 2_097_155) }
        if variant == 2 { #expect(result.exitCode == 0); #expect(result.output.isEmpty); #expect(!result.oversized) }
    }

    // Preserves invariant A1: descriptors without FD_CLOEXEC still do not leak.
    @Test func closesUnadvertisedParentDescriptor() throws {
        let original = open("/dev/null", O_RDONLY)
        #expect(original >= 0); guard original >= 0 else { return }; defer { close(original) }
        let descriptor = fcntl(original, F_DUPFD, 100)
        #expect(descriptor >= 100); guard descriptor >= 100 else { return }; defer { close(descriptor) }
        #expect(fcntl(descriptor, F_SETFD, 0) == 0)
        let result = scRun("if [ -e /dev/fd/\"$1\" ]; then exit 9; else exit 0; fi", args: [String(descriptor)])
        #expect(result.exitCode == 0)
    }

    // Preserves invariant A1: spawn resets the calling thread's inherited signal mask.
    @Test func resetsBlockedSignalMask() {
        var mask = sigset_t(), previous = sigset_t()
        sigemptyset(&mask); sigaddset(&mask, SIGUSR1)
        #expect(pthread_sigmask(SIG_BLOCK, &mask, &previous) == 0)
        defer { pthread_sigmask(SIG_SETMASK, &previous, nil) }
        let result = scRun("kill -USR1 $$; exit 9")
        #expect(result.exitCode == nil); #expect(result.signaled); #expect(!result.timedOut)
    }

    // Exercises new behaviour A1/A6: an external SIGKILL is not an exit status/timeout.
    @Test func externallyKilledLeaderReportsSignal() async {
        let file = SCPIDFile(cleanupDescendant: false), registry = ProcessRegistry()
        defer { registry.terminateAll() }
        let task = Task.detached { scRun("printf '%s' $$ > \"$1\"; exec /bin/sleep 30", args: [file.path],
                                        timeout: 2, registry: registry) }
        #expect(await scWait { file.pid() != nil })
        if let pid = file.pid() { _ = kill(pid, SIGKILL) }
        let result = await task.value
        #expect(result.exitCode == nil); #expect(result.signaled); #expect(!result.timedOut)
    }

    // Exercises new behaviour A1/A6: shutdown kills only its groups and closes admission.
    @Test func registryShutdownIsStickyAndIsolated() async {
        let file = SCPIDFile(cleanupDescendant: false), otherFile = SCPIDFile(cleanupDescendant: false)
        let registry = ProcessRegistry(), other = ProcessRegistry()
        defer { registry.terminateAll(); other.terminateAll() }
        let task = Task.detached { scRun("printf '%s' $$ > \"$1\"; exec /bin/sleep 30", args: [file.path],
                                        timeout: 2, registry: registry) }
        let survivor = Task.detached { scRun("printf '%s' $$ > \"$1\"; exec /bin/sleep 30", args: [otherFile.path],
                                            timeout: 2, registry: other) }
        #expect(await scWait { file.pid() != nil && otherFile.pid() != nil })
        registry.terminateAll(); registry.terminateAll()
        let result = await task.value
        #expect(result.exitCode == nil)
        if let pid = otherFile.pid() { #expect(kill(pid, 0) == 0) }
        #expect(scRun("exit 0", registry: registry).exitCode == nil)
        #expect(scRun("exit 0", registry: other).exitCode == 0)
        other.terminateAll(); _ = await survivor.value
    }

    // Exercises new behaviour A1: shutdown racing spawn leaves no admitted child alive.
    @Test func shutdownRacesSpawnAdmission() async {
        let registry = ProcessRegistry(), start = ContinuousClock.now
        let tasks = (0..<8).map { _ in Task.detached {
            SystemProcessRunner().run(executable: "/bin/sleep", arguments: ["30"], environment: [:],
                workingDirectory: nil, timeout: 1, graceAfterTerm: 0.1, output: .discard, registry: registry)
        } }
        registry.terminateAll()
        for task in tasks { let result = await task.value; #expect(result.exitCode == nil); #expect(!result.timedOut) }
        #expect(start.duration(to: .now) < .seconds(3))
    }

    // Preserves credential boundary A1/A6: description must never render captured bytes.
    @Test func resultDescriptionRedactsOutput() {
        let result = scResult(text: scToken(1))
        let safe = scSafe(result.description) && !scResult(text: "secret").description.contains("secret")
        #expect(safe)
    }
}
