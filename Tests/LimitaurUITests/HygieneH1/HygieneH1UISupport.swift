import AppKit
import Foundation
import Testing
@testable import Limitaur
@testable import LimitaurCore

// Same isolated-defaults pattern as PresentationActionTests; no app launch or live profiles.
@MainActor func h1NudgeEventually(_ monitor: Monitor, _ expected: Bool) async -> Bool {
    let end = ContinuousClock.now.advanced(by: .seconds(2))
    while ContinuousClock.now < end {
        if await monitor.isNudgeEnabled() == expected { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await monitor.isNudgeEnabled() == expected
}
