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
