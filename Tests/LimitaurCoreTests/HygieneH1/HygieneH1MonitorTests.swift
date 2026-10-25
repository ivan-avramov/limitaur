import Foundation
import Testing
@testable import LimitaurCore

@Suite struct HygieneH1MonitorTests {
    // AC1: reproduces fixed eligibility/deadline failure; no-policy case preserves the 90 s invariant.
    @Test(arguments: [true, false]) func statisticsHorizon(_ policy: Bool) async throws {
        try await h1WithRig { r in
            r.files.set(CredentialStore.defaultCodexPath, h1Credential())
            if policy { var p = PollingPolicy(); _ = p.recordThrottle(now: r.clock.wallNow(), retryAfter: 120); await r.monitor.setPolling(["claude": p, "codex": p]) }
            await r.monitor.setProfiles([AccountProfile(id: "codex-default", providerID: "codex", label: "Codex", source: .codexFile(CredentialStore.defaultCodexPath)), AccountProfile(id: "claude-default", providerID: "claude", label: "Claude", source: .claudeDefaultDiscovery)])
            try await r.answer(0); try #require(await h1Wait { (await r.monitor.statistics()).values.reduce(0) { $0 + $1["success", default: 0] } == 1 })
            r.clock.set(1); try await r.answer(1); try #require(await r.monitor.settle())
            let initial = await r.monitor.statistics()["__eligibility"] ?? [:]
            #expect(initial["eligible"] == 1)
            #expect(initial["validUntilContinuousNanoseconds"] == (policy ? 1_140 : 1_090) * 1_000_000_000)
            for cycle in 0..<2 {
                r.clock.set(Double(cycle * 120 + (policy ? 101 : 89)))
                let stats = await r.monitor.statistics()["__eligibility"] ?? [:]
                #expect(stats["eligible"] == 1)
                #expect(stats["validUntilContinuousNanoseconds"] == (1_000 + cycle * 120 + (policy ? 140 : 90)) * 1_000_000_000)
                #expect(stats["violations", default: 0] == initial["violations", default: 0])
                if !policy { r.clock.set(90); #expect((await r.monitor.statistics())["__eligibility"]?["eligible"] == 0); break }
                r.clock.set(Double((cycle + 1) * 120)); await r.monitor.refresh()
                try await r.answer(2 + cycle * 2); try #require(await h1Wait { (await r.monitor.statistics()).values.reduce(0) { $0 + $1["success", default: 0] } == 3 + cycle * 2 })
                r.clock.set(Double((cycle + 1) * 120 + 1)); try await r.answer(3 + cycle * 2)
                try #require(await r.monitor.settle())
            }
            if policy { #expect((await r.monitor.statistics())["__eligibility"]?["violations", default: 0] == initial["violations", default: 0]) }
        }
    }
    // AC4: reproduces retained bars after rejection, inside and outside the nominal horizon.
    @Test(arguments: [401, 403], [85.0, 100.0]) func rejectionCutsRetention(_ status: Int, _ age: Double) async throws {
        try await h1WithRig { r in
            try await r.retained(); r.clock.set(age); await r.monitor.refresh(); try await r.answer(2, status); try #require(await r.monitor.settle())
            let d = await r.monitor.display(); #expect(d.selected.count == (age < 90 ? 1 : 0)); #expect(d.profiles.first?.freshnessDeadline == 1_090)
            #expect(d.profiles.first?.health == .unauthenticated); #expect((await r.monitor.presentationActionState(for: "a"))?.authPaused == true)
            if age < 90 { #expect((await r.display(89.999)).selected.count == 1); #expect((await r.display(90)).selected.isEmpty) }
        }
    }
    // AC4: reproduces expiry retention; expiry is a binding event even while throttle blocks HTTP.
    @Test(arguments: [85, 100]) func expiryCutsRetention(_ age: Int) async throws {
        try await h1WithRig { r in
            r.files.set("/h1/a", h1Credential(age)); try await r.retained(); r.clock.set(Double(age)); await r.monitor.refresh()
            try #require(await r.monitor.settle()); #expect((await r.monitor.presentationActionState(for: "a"))?.authPaused == true)
            #expect((await r.monitor.display()).selected.count == (age < 90 ? 1 : 0))
            #expect((await r.display(max(90, Double(age)))).selected.isEmpty); #expect(await r.transport.count() == 2)
        }
    }
    // AC4: reproduces state-based detach failure; a still-active alias preserves retention until removed.
    @Test func detachLeavesOnlyPausedSubscribers() async throws {
        try await h1WithRig { r in
            r.files.set("/h1/a", h1Credential(70)); r.files.set("/h1/b", h1Credential())
            try await r.retained([h1Profile(), h1Profile("b")]); r.clock.set(70); await r.monitor.refresh()
            #expect((await r.monitor.presentationActionState(for: "a"))?.authPaused == true)
            #expect((await r.monitor.presentationActionState(for: "b"))?.authPaused == false)
            #expect((await r.display(100)).selected.count == 1); await r.monitor.setProfiles([h1Profile()])
            #expect((await r.monitor.display()).selected.isEmpty); #expect((await r.monitor.display()).profiles.first?.freshnessDeadline == 1_090)
        }
    }
    // AC4: reproduces late-429 extension; loadFailed also suppresses the in-flight 300 s allowance.
    @Test func lateThrottleCannotLatchWhileAllPaused() async throws {
        try await h1WithRig { r in
            try await r.retained(); r.clock.set(85); await r.monitor.refresh(); try #require(await h1Wait { await r.transport.count() == 3 })
            r.clock.set(100); r.files.set("/h1/a", nil); await r.monitor.reconnect("a")
            try #require(await h1Wait { (await r.monitor.display()).profiles.first?.message != "Connecting account" })
            #expect((await r.monitor.presentationActionState(for: "a"))?.authPaused == true)
            #expect((await r.monitor.display()).selected.isEmpty)
            try await r.answer(2, 429, retry: "400"); try #require(await r.monitor.settle()); #expect((await r.monitor.display()).selected.isEmpty)
            r.files.set("/h1/a", h1Credential()); r.clock.set(101); await r.monitor.reconnect("a"); try #require(await r.monitor.settle())
            #expect((await r.monitor.presentationActionState(for: "a"))?.authPaused == false)
            #expect((await r.monitor.display()).profiles.first?.freshnessDeadline == 1_133.5)
            #expect((await r.display(133.5)).selected.isEmpty)
        }
    }
    // AC4: invariant, both ordinary retention and Connect's cause-less loading pause retain today's deadline.
    @Test(arguments: [false, true]) func retentionWithoutAuthenticationFailure(_ connecting: Bool) async throws {
        try await h1WithRig { r in
            try await r.retained(); r.clock.set(100)
            if connecting { r.files.block(DispatchSemaphore(value: 0)); await r.monitor.reconnect("a"); try #require(await h1Wait { r.files.count() == 2 }); #expect((await r.monitor.display()).profiles.first?.message == "Connecting account") }
            #expect((await r.monitor.display()).selected.count == 1); #expect((await r.monitor.display()).profiles.first?.freshnessDeadline == 1_133.5)
            #expect((await r.display(133.499)).selected.count == 1); #expect((await r.display(133.5)).selected.isEmpty)
        }
    }
    // AC5: new accessor behaviour in the core target.
    @Test func nudgeAccessorTracksBothDirections() async {
        let m = Monitor(); #expect(await m.isNudgeEnabled() == false)
        await m.setNudgeEnabled(true); #expect(await m.isNudgeEnabled()); await m.setNudgeEnabled(false); #expect(await m.isNudgeEnabled() == false); await m.stop()
    }
    // AC6: invariant, both statuses satisfy the same binding/entity/message/counter and delayed reread assertions.
    @Test(arguments: [401, 403]) func rejectionAndReactiveReread(_ status: Int) async throws {
        try await h1WithRig(reactive: true) { r in
            await r.monitor.setProfiles([h1Profile()]); try await r.answer(0, status); try #require(await r.monitor.settle())
            let state = try #require(await r.monitor.presentationActionState(for: "a"))
            #expect(state.authPaused && state.health == .unauthenticated && !state.hasInFlightRequest && !state.hasCachedSnapshot)
            #expect((await r.monitor.display()).profiles.first?.health == .unauthenticated)
            #expect((await r.monitor.display()).profiles.first?.message == "Session expired or rejected; resumes automatically after the provider app signs in again")
            #expect((await r.monitor.statistics())["claude"] == ["unauthenticated": 1])
            r.clock.set(29.999); await r.monitor.refresh(); #expect(r.files.count() == 1)
            #expect((await r.monitor.statistics())["__eligibility"]?["credentialRechecks", default: 0] == 0)
            r.clock.set(30); await r.monitor.refresh(); try #require(await r.monitor.settle())
            #expect(r.files.count() == 2); #expect((await r.monitor.statistics())["__eligibility"]?["credentialRechecks"] == 1)
            #expect(await r.monitor.presentationActionState(for: "a") == state); #expect(await r.transport.count() == 1)
        }
    }
}
