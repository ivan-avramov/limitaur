import AppKit
import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

// Same isolated-defaults/menu-action pattern as PresentationActionTests; no app launch or live profiles.
@MainActor func h1MenuItem(_ controller: AppController) throws -> NSMenuItem {
    try #require(controller.settingsMenu().items.first { $0.title == "Run claude when the Claude session has expired" })
}
@MainActor func h1NudgeEventually(_ monitor: Monitor, _ expected: Bool) async -> Bool {
    let end = ContinuousClock.now.advanced(by: .seconds(2))
    while ContinuousClock.now < end {
        if await monitor.isNudgeEnabled() == expected { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await monitor.isNudgeEnabled() == expected
}
