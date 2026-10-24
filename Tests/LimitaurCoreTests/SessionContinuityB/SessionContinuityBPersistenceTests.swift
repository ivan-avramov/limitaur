import Foundation
import Testing
@testable import LimitaurCore

@Suite struct SessionContinuityBPersistenceTests {
    // New behaviour B7, policy/storage boundary only: real isolated defaults round-trip.
    // B3 names no app store initializer/protocol; this does not claim to exercise
    // AppController's private launch/apply wiring (see COVERAGE.md).
    @Test func isolatedDefaultsRoundTripKeepsProvidersSeparate() throws {
        let name = "limitaur-session-continuity-b-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var claude = try bReduced()
        _ = claude.recordThrottle(now: bDate(1_800), retryAfter: nil)
        let codex = try bPolicy(110)
        defaults.set(try bEncoding(claude), forKey: "polling.claude")
        defaults.set(try bEncoding(codex), forKey: "polling.codex")
        let reopened = try #require(UserDefaults(suiteName: name))
        let restoredClaude = PollingPolicy.decode(try #require(reopened.data(forKey: "polling.claude")), now: bDate(1_800))
        let restoredCodex = PollingPolicy.decode(try #require(reopened.data(forKey: "polling.codex")), now: bDate(1_800))
        #expect(restoredClaude == claude); #expect(restoredCodex == codex)
        #expect(restoredClaude.blockedUntil[40] == bDate(606_600))
    }

    // Invariant B7, policy/storage boundary only: corrupt stored bytes decode to defaults.
    @Test func corruptDefaultsDataDecodesToInitialPolicy() throws {
        let name = "limitaur-session-continuity-b-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("{invalid".utf8), forKey: "polling.codex")
        let data = try #require(defaults.data(forKey: "polling.codex"))
        #expect(PollingPolicy.decode(data, now: bDate(0)) == PollingPolicy())
        #expect(defaults.data(forKey: "polling.claude") == nil)
    }
}
