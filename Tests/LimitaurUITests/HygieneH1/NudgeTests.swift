import AppKit
import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

@Suite @MainActor struct HygieneH1NudgeTests {
    // AC2: NO/0/false strings reproduce the bug; absent/Bool/integer/YES preserve defaults semantics.
    @Test(arguments: 0..<10) func defaultsUseFoundationBoolSemantics(_ index: Int) async throws {
        _ = NSApplication.shared
        let suite = "hygiene-h1-" + UUID().uuidString, values: [Any?] = [nil, true, false, 0, 1, "NO", "YES", "0", "false", "true"]
        let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        if let value = values[index] { defaults.set(value, forKey: "claudeNudgeEnabled") }
        let expected = [true, true, false, false, true, false, true, false, false, true][index]
        let monitor = Monitor(), controller = AppController(monitor: monitor, countStore: MemoryIndicatorStore(), defaults: defaults, nudger: nil)
        #expect(controller.settings.nudgeEnabled == expected)
        await controller.restoreNudge(); #expect(await monitor.isNudgeEnabled() == expected); await monitor.stop()
    }
    // AC5: invariant in production action routing, new accessor proves delivery to the actor both ways.
    @Test func settingsToggleReachesMonitorBothWays() async throws {
        _ = NSApplication.shared
        let suite = "hygiene-h1-" + UUID().uuidString, defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = Monitor(), controller = AppController(monitor: monitor, countStore: MemoryIndicatorStore(), defaults: defaults, nudger: nil)
        await controller.restoreNudge(); try #require(await monitor.isNudgeEnabled())
        for expected in [false, true] {
            #expect(controller.settings.nudgeEnabled == !expected); #expect(controller.settings.editable)
            controller.settings.setNudge(expected)
            #expect(await h1NudgeEventually(monitor, expected)); #expect(defaults.bool(forKey: "claudeNudgeEnabled") == expected)
            #expect(controller.settings.nudgeEnabled == expected)
        }
        await monitor.stop()
    }
}
