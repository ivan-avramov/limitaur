import AppKit
import Foundation
import Testing
@testable import Limitaur

@Test func appVersionIsValidSemVer() {
    #expect(AppVersion.isValidSemVer(AppVersion.string))
}

@Test func semVerValidationAcceptsAndRejectsVectors() {
    for valid in ["0.0.0", "1.2.3", "0.1.0-alpha", "1.0.0-alpha.1", "1.0.0-0.3.7", "1.0.0-x-y-z.--",
                  "1.0.0+20130313144700", "1.0.0-beta+exp.sha.5114f85", "1.0.0+21AF26D3----117B344092BD",
                  "1.0.0+001", "10.20.30"] {
        #expect(AppVersion.isValidSemVer(valid), "\(valid) should be valid")
    }
    for invalid in ["", "1", "1.0", "1.0.0.0", "01.0.0", "1.00.0", "v1.0.0", " 1.0.0", "1.0.0\n", "1.0.0-",
                    "1.0.0-01", "1.0.0-alpha..1", "1.0.0+", "1.0.0-al pha", "1.0.0-é", "1.0.0-alpha_1", "-1.0.0"] {
        #expect(!AppVersion.isValidSemVer(invalid), "\(invalid.debugDescription) should be invalid")
    }
}

@Test func versionFlagRespondsOnlyToExactArguments() {
    #expect(AppVersion.commandLineResponse(["Limitaur", "--version"]) == AppVersion.string + "\n")
    #expect(AppVersion.commandLineResponse(["Limitaur"]) == nil)
    #expect(AppVersion.commandLineResponse(["Limitaur", "--version", "extra"]) == nil)
    #expect(AppVersion.commandLineResponse(["Limitaur", "--demo"]) == nil)
}

@Test func aboutOptionsCarryVersionAndOmitBuildOutsideAppBundle() {
    let options = AppVersion.aboutPanelOptions(bundle: Bundle(for: BundleAnchor.self))
    #expect(options[.applicationName] as? String == "Limitaur")
    #expect(options[.applicationVersion] as? String == AppVersion.string)
    #expect(options[.version] == nil)
}

private final class BundleAnchor {}

@Test func aboutOptionsIncludeBuildNumberInsideAppBundle() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("limitaur-about-\(UUID().uuidString)").appendingPathComponent("Limitaur.app")
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": "local.limitaur.app", "CFBundleVersion": "42",
                                "CFBundleShortVersionString": AppVersion.string, "CFBundleExecutable": "Limitaur"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: root.appendingPathComponent("Contents/Info.plist"))
    let bundle = try #require(Bundle(url: root))
    let options = AppVersion.aboutPanelOptions(bundle: bundle)
    #expect(options[.applicationVersion] as? String == AppVersion.string)
    #expect(options[.version] as? String == "42")
}

/// Runs the real executable built beside the test bundle. Exercises the dispatch in main,
/// which the pure `commandLineResponse` test cannot: a wrong fallthrough would start AppKit.
@Test(arguments: [(["--version"], 0, AppVersion.string + "\n"), (["--version", "extra"], 2, ""),
                  (["--version", "--demo"], 2, "")])
func executableVersionDispatch(arguments: [String], status: Int32, stdout: String) throws {
    let executable = Bundle(for: BundleAnchor.self).bundleURL.deletingLastPathComponent().appendingPathComponent("Limitaur")
    try #require(FileManager.default.isExecutableFile(atPath: executable.path), "built Limitaur executable missing")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = executable; process.arguments = arguments
    process.standardOutput = output; process.standardError = errors
    process.environment = ["HOME": FileManager.default.temporaryDirectory.path, "PATH": "/usr/bin:/bin"]
    try process.run()
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    if finished.wait(timeout: .now() + 10) == .timedOut {
        process.terminate()
        Issue.record("executable did not exit within 10 s for \(arguments)")
        return
    }
    #expect(process.terminationStatus == status)
    #expect(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == stdout)
    let diagnostic = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(status == 0 ? diagnostic.isEmpty : diagnostic == "Invalid diagnostic input\n")
}

@MainActor private final class RouterProbe {
    var refreshes = 0, connections = 0, accounts = 0, quits = 0
    func router(demo: Bool) -> AppActionRouter {
        AppActionRouter(demo: demo, refresh: { self.refreshes += 1 }, connect: { _ in self.connections += 1 },
                        accounts: { self.accounts += 1 }, quit: { self.quits += 1 })
    }
}

@MainActor private final class StoreProbe: IndicatorPreferenceStore {
    var writes = 0
    func loadCount() -> Int { 3 }
    func saveCount(_ count: Int) { writes += 1 }
}

@MainActor @Test(arguments: [false, true]) func aboutMenuItemPresentsOptionsWithoutOtherActions(demo: Bool) {
    _ = NSApplication.shared
    let probe = RouterProbe(), store = StoreProbe()
    let controller = AppController(demo: demo, countStore: store, actionRouter: probe.router(demo: demo))
    var presented: [[NSApplication.AboutPanelOptionKey: Any]] = []
    controller.aboutPresenter = { presented.append($0) }
    let menu = controller.settingsMenu()
    #expect(menu.item(at: 0)?.title == "Indicators")
    #expect(menu.item(at: 1)?.isSeparatorItem == true)
    #expect(menu.item(at: 2)?.title == "Accounts…")
    let about = menu.item(at: 3)!
    #expect(about.title == "About Limitaur…")
    #expect(about.isEnabled)
    #expect(menu.numberOfItems == 4)
    #expect(NSApp.sendAction(about.action!, to: about.target, from: about))
    #expect(presented.count == 1)
    #expect(presented.first?[.applicationVersion] as? String == AppVersion.string)
    #expect(probe.refreshes == 0 && probe.connections == 0 && probe.accounts == 0 && probe.quits == 0)
    #expect(store.writes == 0)
}
