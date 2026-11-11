import AppKit
import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes, I = preserves an invariant, N = exercises new behaviour.
// Criterion C6 (controller loads, persists and applies provider codes). The controller gets an injected UserDefaults suite
// (key `providerCodes`); `profiles` stays in UserDefaults.standard and is restored after each launching test.

private let pcClock = Date(timeIntervalSince1970: 1_800_000_000)
private final class PCClock: MonitorClock, @unchecked Sendable {
    func wallNow() -> Date { pcClock }
    func monotonicNow() -> TimeInterval { 100 }
}
private struct PCNoFiles: CredentialFileReading {
    func read(path: String) throws -> Data { throw CredentialFailure.missing }
}
private struct PCNoKeychain: KeychainReading {
    func claudeCredential() -> KeychainResult { .notFound }
}
private struct PCOffline: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse { throw TransportFailure.network }
}
private func pcSuite() -> (UserDefaults, () -> Void) {
    let name = "limitaur-synthetic-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    return (defaults, { defaults.removePersistentDomain(forName: name) })
}
private func pcStored(_ defaults: UserDefaults) -> [String: String]? { defaults.dictionary(forKey: "providerCodes") as? [String: String] }

/// Launches the controller against no credentials; the returned closure tears it down and restores `profiles`.
@MainActor private func pcLaunch(defaults: UserDefaults) throws -> (AppController, () async -> Void) {
    _ = NSApplication.shared
    let monitor = Monitor(clock: PCClock(), credentials: CredentialStore(files: PCNoFiles(), keychain: PCNoKeychain(), cursorKeychain: PCNoKeychain()),
                          transport: PCOffline())
    let previous = UserDefaults.standard.data(forKey: "profiles")
    UserDefaults.standard.set(try JSONEncoder().encode([rdClaudeDefault, rdProfile("cursor-default", "cursor", "Default", .cursorDefaultDiscovery)]),
                              forKey: "profiles")
    let controller = AppController(monitor: monitor, presentationClock: PCClock(), countStore: RDCountStore(), defaults: defaults, nudger: nil)
    controller.settingsPresenter = { _ in }
    controller.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    return (controller, {
        controller.terminateProcesses = {}
        controller.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        await monitor.stop()
        if let previous { UserDefaults.standard.set(previous, forKey: "profiles") } else { UserDefaults.standard.removeObject(forKey: "profiles") }
    })
}

@Suite(.serialized) @MainActor struct PCControllerTests {
    // N, C6: with nothing stored, there are no overrides anywhere and nothing is written.
    @Test func noStoredValueMeansNoOverrides() {
        _ = NSApplication.shared
        let (defaults, cleanup) = pcSuite(); defer { cleanup() }
        let controller = AppController(countStore: RDCountStore(), defaults: defaults, nudger: nil)
        #expect(controller.providerCodes.isEmpty && controller.settings.providerCodes.isEmpty)
        #expect(controller.statusDrawingView.providerCodes.isEmpty && controller.dropdownModel.providerCodes.isEmpty)
        #expect(defaults.object(forKey: "providerCodes") == nil)
    }
    // N, C6 success trace: a change is written, and applied to the controller, the status view, the dropdown model and Settings.
    @Test func changeIsPersistedAndApplied() {
        _ = NSApplication.shared
        let (defaults, cleanup) = pcSuite(); defer { cleanup() }
        let controller = AppController(countStore: RDCountStore(), defaults: defaults, nudger: nil)
        #expect(controller.settings.setProviderCode("cursor", "cr") == .saved("CR"))
        #expect(pcStored(defaults) == ["cursor": "CR"])
        #expect(controller.providerCodes == ["cursor": "CR"] && controller.settings.providerCodes == ["cursor": "CR"])
        #expect(controller.statusDrawingView.providerCodes == ["cursor": "CR"] && controller.dropdownModel.providerCodes == ["cursor": "CR"])
        #expect(controller.settings.setProviderCode("budget", "7") == .saved("7"))
        #expect(pcStored(defaults) == ["cursor": "CR", "budget": "7"])
        #expect(controller.statusDrawingView.providerCodes == ["cursor": "CR", "budget": "7"])
        #expect(controller.dropdownModel.providerCodes == ["cursor": "CR", "budget": "7"])
    }
    // N, C6: clearing removes the override from storage and from every place.
    @Test func resetRemovesTheStoredOverride() {
        _ = NSApplication.shared
        let (defaults, cleanup) = pcSuite(); defer { cleanup() }
        let controller = AppController(countStore: RDCountStore(), defaults: defaults, nudger: nil)
        controller.settings.setProviderCode("cursor", "CR"); controller.settings.setProviderCode("codex", "ZZ")
        #expect(controller.settings.setProviderCode("cursor", "") == .reset)
        #expect(pcStored(defaults) == ["codex": "ZZ"])
        #expect(controller.providerCodes == ["codex": "ZZ"] && controller.statusDrawingView.providerCodes == ["codex": "ZZ"]
                && controller.dropdownModel.providerCodes == ["codex": "ZZ"])
        controller.settings.setProviderCode("codex", "")
        #expect((pcStored(defaults) ?? [:]).isEmpty && controller.providerCodes.isEmpty)
    }
    // N, C6: the status item redraws at once, with no poll: the view is marked for display by the change.
    @Test func changeRedrawsTheStatusViewAtOnce() {
        _ = NSApplication.shared
        let (defaults, cleanup) = pcSuite(); defer { cleanup() }
        let controller = AppController(countStore: RDCountStore(), defaults: defaults, nudger: nil)
        let view = controller.statusDrawingView
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSView(frame: view.frame); window.contentView = host; host.addSubview(view)
        defer { window.close() }
        view.needsDisplay = false
        controller.settings.setProviderCode("cursor", "CR")
        #expect(view.needsDisplay)
        // The "no redraw on unchanged or refused" half was removed by designer ruling: needsDisplay is always true off-screen.
    }
    // R, C6: a refused or invalid change writes nothing and applies nothing.
    @Test func refusedChangesNeverReachStorageOrViews() {
        _ = NSApplication.shared
        let (defaults, cleanup) = pcSuite(); defer { cleanup() }
        let controller = AppController(countStore: RDCountStore(), defaults: defaults, nudger: nil)
        #expect(controller.settings.setProviderCode("cursor", "CL") == .duplicate("claude"))
        #expect(controller.settings.setProviderCode("cursor", "C?") == .invalid)
        #expect(controller.settings.setProviderCode("cursor", "ABC") == .invalid)
        #expect(controller.settings.setProviderCode("gemini", "ZZ") == .invalid)
        #expect(controller.settings.setProviderCode("cursor", "") == .unchanged)
        #expect(defaults.object(forKey: "providerCodes") == nil)
        #expect(controller.providerCodes.isEmpty && controller.statusDrawingView.providerCodes.isEmpty && controller.dropdownModel.providerCodes.isEmpty)
    }
    // N, C6: what was saved is in force for a second controller on the same defaults (relaunch), normalized again.
    @Test func survivesARelaunch() {
        _ = NSApplication.shared
        let (defaults, cleanup) = pcSuite(); defer { cleanup() }
        let first = AppController(countStore: RDCountStore(), defaults: defaults, nudger: nil)
        first.settings.setProviderCode("cursor", "cr"); first.settings.setProviderCode("budget", "b2")
        let second = AppController(countStore: RDCountStore(), defaults: defaults, nudger: nil)
        #expect(second.providerCodes == ["cursor": "CR", "budget": "B2"] && second.settings.providerCodes == ["cursor": "CR", "budget": "B2"])
        #expect(second.settings.code(for: "cursor") == "CR" && second.settings.code(for: "budget") == "B2")
    }
    // N, C6: stored values are in force after launch in every place; the stored form is validated, not trusted.
    @Test func storedValuesLoadThroughValidation() async throws {
        let (defaults, cleanup) = pcSuite(); defer { cleanup() }
        defaults.set(["cursor": "cr", "gemini": "ZZ", "codex": "é"], forKey: "providerCodes")
        let (controller, teardown) = try pcLaunch(defaults: defaults)
        #expect(controller.providerCodes == ["cursor": "CR"] && controller.settings.providerCodes == ["cursor": "CR"])
        #expect(controller.statusDrawingView.providerCodes == ["cursor": "CR"] && controller.dropdownModel.providerCodes == ["cursor": "CR"])
        await teardown()
    }
    // R, C6 failure trace: the tampered value {cursor: CL, codex: ??} loads as no overrides at all, in every place.
    @Test func tamperedStoredValueLoadsEmpty() async throws {
        let (defaults, cleanup) = pcSuite(); defer { cleanup() }
        defaults.set(["cursor": "CL", "codex": "??"], forKey: "providerCodes")
        let (controller, teardown) = try pcLaunch(defaults: defaults)
        #expect(controller.providerCodes.isEmpty && controller.settings.providerCodes.isEmpty)
        #expect(controller.statusDrawingView.providerCodes.isEmpty && controller.dropdownModel.providerCodes.isEmpty)
        #expect(controller.settings.code(for: "cursor") == "CU")
        await teardown()
    }
    // R, C6: values of the wrong shape under the key are ignored rather than crashing.
    @Test(arguments: [0, 1, 2, 3])
    func wrongShapeLoadsEmpty(_ shape: Int) {
        let stored: Any = [("not a dictionary" as Any), ([1, 2] as Any), (["cursor": 5] as Any), (Data("x".utf8) as Any)][shape]
        _ = NSApplication.shared
        let (defaults, cleanup) = pcSuite(); defer { cleanup() }
        defaults.set(stored, forKey: "providerCodes")
        let controller = AppController(countStore: RDCountStore(), defaults: defaults, nudger: nil)
        #expect(controller.providerCodes.isEmpty && controller.settings.providerCodes.isEmpty)
    }
    // N, C6: a change after launch is applied at once without waiting for a poll or a model update.
    @Test func changeAfterLaunchApplies() async throws {
        let (defaults, cleanup) = pcSuite(); defer { cleanup() }
        let (controller, teardown) = try pcLaunch(defaults: defaults)
        controller.settings.setProviderCode("claude", "k9")
        #expect(pcStored(defaults) == ["claude": "K9"])
        #expect(controller.statusDrawingView.providerCodes == ["claude": "K9"] && controller.dropdownModel.providerCodes == ["claude": "K9"])
        await teardown()
    }
    // I, C6: demo neither reads nor writes the key, in the injected suite or in standard defaults; its Settings stays read-only.
    @Test func demoNeitherReadsNorWrites() {
        _ = NSApplication.shared
        let (defaults, cleanup) = pcSuite(); defer { cleanup() }
        let before = UserDefaults.standard.object(forKey: "providerCodes") as? NSObject
        defer { if let before { UserDefaults.standard.set(before, forKey: "providerCodes") } else { UserDefaults.standard.removeObject(forKey: "providerCodes") } }
        defaults.set(["cursor": "ZZ"], forKey: "providerCodes")
        let demo = AppController(demo: true, countStore: RDCountStore(), defaults: defaults)
        #expect(demo.providerCodes.isEmpty && demo.settings.providerCodes.isEmpty)
        #expect(demo.statusDrawingView.providerCodes.isEmpty && demo.dropdownModel.providerCodes.isEmpty)
        #expect(!demo.settings.editable)
        for (provider, raw) in [("cursor", "QQ"), ("claude", ""), ("codex", "??")] as [(ProviderID, String)] {
            #expect(demo.settings.setProviderCode(provider, raw) == .readOnly)
        }
        #expect(pcStored(defaults) == ["cursor": "ZZ"], "the suite still holds only what was put there")
        #expect(UserDefaults.standard.object(forKey: "providerCodes") as? NSObject == before)
        #expect(demo.providerCodes.isEmpty && demo.statusDrawingView.providerCodes.isEmpty && demo.dropdownModel.providerCodes.isEmpty)
    }
    // I, C6: a demo controller on empty defaults writes nothing either.
    @Test func demoOnEmptyDefaultsWritesNothing() {
        _ = NSApplication.shared
        let (defaults, cleanup) = pcSuite(); defer { cleanup() }
        let demo = AppController(demo: true, countStore: RDCountStore(), defaults: defaults)
        demo.settings.setProviderCode("cursor", "QQ")
        #expect(defaults.object(forKey: "providerCodes") == nil)
    }
}
