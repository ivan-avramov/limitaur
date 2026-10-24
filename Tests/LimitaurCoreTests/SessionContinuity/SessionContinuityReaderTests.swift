import Foundation
import Testing
@testable import LimitaurCore

@Suite struct SessionContinuityReaderTests {
    // Preserves credential boundary A2/A7: exact argv, empty env, one child, no -a retry.
    @Test(arguments: [false, true])
    func exactInvocationAndLiteralAccountService(_ interactive: Bool) {
        let rig = SCReaderRig([scResult(44)])
        let account = "-a; $(printf injected) `printf injected` \" \n --help"
        // Service prefixes are not restricted in A2 (only the A3 diagnostic is).
        let service = rig.service + "; $(printf injected)\n-w"
        let reader = SecurityToolKeychainReader(runner: rig.runner, service: service, account: account,
                                               registry: rig.registry, suspensions: rig.suspensions)
        let outcome = reader.claudeCredentialDetailed(interactive: interactive)
        #expect(outcome.reason == .notFound); scExpectMissing(outcome.result)
        #expect(rig.runner.matches(service, account: account, interactive: interactive, registry: rig.registry))
    }

    // Exercises new behaviour A2/A7: raw/hex transport, decode once, strip exactly one LF.
    @Test(arguments: [0, 1, 2, 3, 4, 5, 6, 7])
    func decodingAndSingleTrailingNewline(_ variant: Int) {
        let json = Data("{\"a\":1}".utf8)
        let cases: [(Data, Data)] = [
            (json + Data([10]), json), (scHex(json) + Data([10]), json),
            (scHex(json, uppercase: true) + Data([10]), json),
            (Data("abc".utf8), Data("abc".utf8)),
            (Data("abc\n\n".utf8), Data("abc\n".utf8)),
            (Data("abc\r\n".utf8), Data("abc\r".utf8)),
            (Data("3431\n".utf8), Data("41".utf8)),
            (Data(" aB \n".utf8), Data(" aB ".utf8))]
        let rig = SCReaderRig([scResult(data: cases[variant].0)])
        let outcome = rig.reader().claudeCredentialDetailed(interactive: false)
        #expect(outcome.reason == .found); scExpectFound(outcome.result, cases[variant].1)
    }

    // Exercises new behaviour A2: case-insensitive even-length hex only, including binary.
    @Test(arguments: ["abCD", "00", "f", "0x41", "4g", "123"])
    func hexRecognitionBoundaries(_ value: String) {
        let expected = value == "abCD" ? Data([0xab, 0xcd]) : value == "00" ? Data([0]) : Data(value.utf8)
        let rig = SCReaderRig([scResult(text: value + "\n")])
        let outcome = rig.reader().claudeCredentialDetailed(interactive: false)
        #expect(outcome.reason == .found); scExpectFound(outcome.result, expected)
    }

    // Exercises new behaviour A2/A7: decoded limit inclusive, transport not confused with item size.
    @Test(arguments: [0, 1, 2, 3, 4])
    func emptyAndDecodedSizeBoundaries(_ variant: Int) {
        let data: Data
        switch variant {
        case 0: data = Data()
        case 1: data = Data([10])
        case 2: data = Data(repeating: 0x7a, count: 1_048_577)
        case 3: data = scHex(Data(repeating: 0x7a, count: 1_048_576)) + Data([10])
        default: data = Data(repeating: 0x7a, count: 1_048_576) + Data([10])
        }
        let rig = SCReaderRig([scResult(data: data)])
        let outcome = rig.reader().claudeCredentialDetailed(interactive: false)
        if variant < 3 { #expect(outcome.reason == .oversized); scExpectDenied(outcome.result) }
        else {
            #expect(outcome.reason == .found)
            scExpectFound(outcome.result, Data(repeating: 0x7a, count: 1_048_576))
        }
    }

    // Preserves invariant A2/A7: only 44 enables fallback; other exits never bind output.
    @Test(arguments: [Int32(44), 51, 36, 128, 1, 300])
    func exitClassificationAndNoAccountlessRetry(_ code: Int32) {
        let rig = SCReaderRig([scResult(code, data: scClaude(1))])
        let outcome = rig.reader().claudeCredentialDetailed(interactive: false)
        #expect(outcome.reason == (code == 44 ? .notFound : .exit(code)))
        let classified = code == 44 ? scMissing(outcome.result) : scDenied(outcome.result)
        #expect(classified)
        #expect(rig.runner.count() == 1)
    }

    // Exercises new behaviour A2/A7: revision 5 puts timeout before nil-code;
    // a signaled timeout with nil exit code is .timeout and suspends the service.
    @Test(arguments: [0, 1, 2, 3, 4, 5, 6])
    func classificationPrecedence(_ variant: Int) {
        let results = [scResult(nil), scResult(nil, signal: true), scResult(0, timeout: true),
                       scResult(44, timeout: true, oversized: true), scResult(44, oversized: true),
                       scResult(nil, signal: true, timeout: true), scResult(nil, oversized: true)]
        let reasons: [KeychainReadReason] = [.launch, .signaled, .timeout, .timeout, .oversized, .timeout, .launch]
        let rig = SCReaderRig([results[variant]])
        let outcome = rig.reader().claudeCredentialDetailed(interactive: false)
        scExpectDenied(outcome.result); #expect(outcome.reason == reasons[variant])
        if variant == 5 { #expect(rig.suspensions.isSuspended(rig.service)) }
    }

    // Reproduces fixed failure A2/A7: one background timeout/deny per service per launch.
    @Test(arguments: [0, 1, 2, 3])
    func backgroundSuspensionAndNonSuspendingExit(_ variant: Int) {
        let result = variant == 0 ? scResult(0, timeout: true) : scResult([Int32(0), 51, 128, 36][variant])
        let rig = SCReaderRig([result, scResult(text: "abc")]), reader = rig.reader()
        _ = reader.claudeCredentialDetailed(interactive: false)
        #expect(rig.suspensions.isSuspended(rig.service) == (variant != 3))
        let second = reader.claudeCredentialDetailed(interactive: false)
        if variant != 3 { #expect(second.reason == .suspended); scExpectDenied(second.result); #expect(rig.runner.count() == 1) }
        else { #expect(second.reason == .found); #expect(rig.runner.count() == 2) }
    }

    // Exercises new behaviour A2/A7: Connect clears only at completion, on found or notFound.
    @Test(arguments: [0, 1, 2, 3])
    func interactiveCompletionClearsSuspension(_ variant: Int) async {
        let gate = SCGate()
        let result = variant == 0 ? scResult(text: "abc") : variant == 1 ? scResult(51) : variant == 2 ? scResult(0, timeout: true) : scResult(44)
        let rig = SCReaderRig(steps: [SCStep(result: scResult(51)), SCStep(result: result, gate: gate),
                                      SCStep(result: scResult(text: "abc"))])
        let reader = rig.reader()
        _ = reader.claudeCredentialDetailed(interactive: false)
        let connect = Task.detached { reader.claudeCredentialDetailed(interactive: true) }
        defer { gate.release() }
        #expect(await scWait { rig.runner.count() == 2 })
        #expect(rig.suspensions.isSuspended(rig.service))
        gate.release(); _ = await connect.value
        #expect(rig.suspensions.isSuspended(rig.service) == (variant == 1 || variant == 2))
        #expect(reader.claudeCredentialDetailed(interactive: false).reason == (variant == 0 || variant == 3 ? .found : .suspended))
        #expect(rig.runner.interactiveFlags() == (variant == 0 || variant == 3 ? [false, true, false] : [false, true])); #expect(!gate.didExpire())
    }

    // Exercises new behaviour A2/A7: background cannot run behind an active Connect.
    @Test func backgroundDuringInteractiveReturnsBusyWithoutSpawn() async {
        let gate = SCGate(), rig = SCReaderRig(steps: [SCStep(result: scResult(text: "abc"), gate: gate)])
        let reader = rig.reader()
        let connect = Task.detached { reader.claudeCredentialDetailed(interactive: true) }
        defer { gate.release() }
        #expect(await scWait { rig.runner.count() == 1 })
        let background = Task.detached { reader.claudeCredentialDetailed(interactive: false) }
        // Observe completion before releasing Connect: waiting for it would violate .busy.
        let finished = SCFlag()
        let observer = Task { let value = await background.value; finished.set(); return value }
        #expect(await scWait { finished.get() })
        gate.release(); let outcome = await observer.value; _ = await connect.value
        #expect(outcome.reason == .busy); scExpectDenied(outcome.result); #expect(rig.runner.count() == 1)
        #expect(!gate.didExpire())
    }

    // Exercises new behaviour A2/A7: serialization rechecks suspension under the lock.
    @Test func queuedBackgroundSeesFirstReadsSuspension() async {
        let gate = SCGate(), entered = SCFlag()
        let rig = SCReaderRig(steps: [SCStep(result: scResult(0, timeout: true), gate: gate)])
        let reader = rig.reader()
        let first = Task.detached { reader.claudeCredentialDetailed(interactive: false) }
        defer { gate.release() }
        #expect(await scWait { rig.runner.count() == 1 })
        let second = Task.detached { entered.set(); return reader.claudeCredentialDetailed(interactive: false) }
        #expect(await scWait { entered.get() }); await scFlush()
        #expect(rig.runner.count() == 1)
        gate.release(); _ = await first.value; let outcome = await second.value
        #expect(outcome.reason == .suspended); #expect(rig.runner.maxActive() == 1)
        #expect(rig.runner.count() == 1); #expect(!gate.didExpire())
    }

    // Preserves invariant A2 admission: two Connect callers still run one child at a time.
    @Test func concurrentInteractiveReadsSerialize() async {
        let gate = SCGate(), entered = SCFlag()
        let rig = SCReaderRig(steps: [SCStep(result: scResult(text: "abc"), gate: gate),
                                      SCStep(result: scResult(text: "abc"))])
        let reader = rig.reader()
        let first = Task.detached { reader.claudeCredentialDetailed(interactive: true) }
        defer { gate.release() }
        #expect(await scWait { rig.runner.count() == 1 })
        let second = Task.detached { entered.set(); return reader.claudeCredentialDetailed(interactive: true) }
        #expect(await scWait { entered.get() }); await scFlush()
        #expect(rig.runner.count() == 1)
        gate.release(); _ = await first.value; let result = await second.value
        #expect(result.reason == .found); #expect(rig.runner.maxActive() == 1)
        #expect(rig.runner.count() == 2); #expect(!gate.didExpire())
    }

    // Exercises new behaviour A2/A7: an admitted Connect shields the outgoing timeout.
    // A2 also says Connect waits. Read "admitted" as reservation while waiting,
    // not merely starting its child; otherwise this explicitly required race is impossible.
    @Test func interactiveAdmissionShieldsOutgoingBackgroundTimeout() async {
        let backgroundGate = SCGate(), connectGate = SCGate(), requested = SCFlag(), observedSuspension = SCFlag()
        let suspensions = KeychainSuspensions(), registry = ProcessRegistry()
        let service = "limitaur-test-" + UUID().uuidString
        let runner = SCRunner(steps: [SCStep(result: scResult(0, timeout: true), gate: backgroundGate),
            SCStep(result: scResult(text: "abc"), gate: connectGate,
                   onStart: { if suspensions.isSuspended(service) { observedSuspension.set() } })])
        let reader = SecurityToolKeychainReader(runner: runner, service: service, registry: registry, suspensions: suspensions)
        let background = Task.detached { reader.claudeCredentialDetailed(interactive: false) }
        defer { backgroundGate.release(); connectGate.release() }
        #expect(await scWait { runner.count() == 1 })
        let connect = Task.detached { requested.set(); return reader.claudeCredentialDetailed(interactive: true) }
        #expect(await scWait { requested.get() }); await scFlush()
        #expect(runner.count() == 1)
        backgroundGate.release(); _ = await background.value
        #expect(await scWait { runner.count() == 2 })
        #expect(!observedSuspension.get()); #expect(!suspensions.isSuspended(service))
        connectGate.release(); _ = await connect.value
        #expect(runner.maxActive() == 1); #expect(!backgroundGate.didExpire() && !connectGate.didExpire())
    }

    // Preserves invariant A2: service key and suspension instance independently isolate state.
    @Test func suspensionIsPerServiceAndPerInstance() {
        let rig = SCReaderRig([scResult(51), scResult(text: "abc"), scResult(text: "abc")])
        _ = rig.reader().claudeCredential()
        let other = SecurityToolKeychainReader(runner: rig.runner, service: rig.service + "-other",
                                               registry: rig.registry, suspensions: rig.suspensions)
        scExpectFound(other.claudeCredential(), Data("abc".utf8))
        let relaunched = SecurityToolKeychainReader(runner: rig.runner, service: rig.service,
                                                    registry: rig.registry, suspensions: KeychainSuspensions())
        scExpectFound(relaunched.claudeCredential(interactive: false), Data("abc".utf8))
        #expect(rig.suspensions.isSuspended(rig.service))
    }
}

final class SCFlag: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    func set() { lock.withLock { value = true } }
    func get() -> Bool { lock.withLock { value } }
}
