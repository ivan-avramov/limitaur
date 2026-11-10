import Foundation
import Testing
@testable import LimitaurCore

// Classes: R = reproduces a failure the specification fixes (baseline reports "Credential source unavailable" for a
// Cursor profile), I = preserves an invariant, N = exercises new behaviour.

private struct CPRig {
    let clock = CPClock(), files = CPFiles(), nudger = CPNudger()
    let cursor: CPKeychain, claude: CPKeychain, transport: CPTransport, monitor: Monitor
    init(cursor: KeychainReadOutcome, claude: KeychainReadOutcome = cpNotFound, reactive: Bool = false,
         handler: @escaping @Sendable (HTTPRequest, Int) -> Result<HTTPResponse, Error> = cpMonitorAnswers()) {
        self.cursor = CPKeychain(cursor); self.claude = CPKeychain(claude); transport = CPTransport(handler)
        monitor = Monitor(clock: clock, credentials: CredentialStore(files: files, keychain: self.claude, cursorKeychain: self.cursor),
                          transport: transport, recheckInterval: 30, reactiveRecheck: reactive, nudger: nudger)
    }
    func start(_ profiles: [AccountProfile] = [cpProfile]) async {
        await monitor.setProfiles(profiles); #expect(await monitor.settle())
    }
    /// Moves past the re-check interval, then runs a refresh cycle.
    func recheck() async {
        clock.move(mono: 30); await monitor.refresh(); #expect(await monitor.settle())
    }
    func bearers() async -> [String] { await transport.requests().map(\.bearer) }
}
private func cpPaused(_ row: ProfileDisplay?) -> Bool {
    row?.message == cpPause || row?.message == cpPause + "; Cached usage stale"
}
private func cpHandler(rejecting token: String) -> @Sendable (HTTPRequest, Int) -> Result<HTTPResponse, Error> {
    let healthy = cpMonitorAnswers()
    return { request, index in request.bearer == token ? .success(cpResponse(401)) : healthy(request, index) }
}

@Suite struct CPMonitorTests {
    // R, C6/I6/Traced success: a Cursor profile becomes healthy, ranks, and uses only the Cursor keychain.
    @Test func cursorProfileBecomesHealthyAndRanks() async throws {
        let token = cpFutureJWT("healthy")
        let rig = CPRig(cursor: cpFound(token))
        await rig.start()
        let row = try #require(await cpDisplayRow(rig.monitor))
        #expect(row.health == .healthy)
        let metric = try #require(row.snapshot?.metrics.first)
        let percent = try #require(metric.usedPercent)
        #expect(metric.id == "spend" && abs(percent - 0.82) < 1e-9)
        let display = await rig.monitor.display()
        #expect(display.selected.map(\.providerID) == ["cursor"] && display.selected.first?.metric.id == "spend")
        #expect(await rig.transport.requests().map(\.cursorOperation).count == 2)
        #expect(await rig.transport.requests().first?.cursorOperation == .currentBillingCycle)
        if case .dailySpend = await rig.transport.requests().last?.cursorOperation {} else { Issue.record("expected the spend request second") }
        #expect(await rig.bearers() == [token, token])
        #expect(rig.cursor.count() == 1 && rig.claude.count() == 0 && rig.files.count() == 0)
        // Threat: the token reaches neither the snapshot, nor the message, nor the statistics.
        let encoded = String(decoding: try JSONEncoder().encode(row.snapshot), as: UTF8.self) + (row.message ?? "")
            + String(describing: await rig.monitor.statistics())
        for part in token.split(separator: ".") { #expect(!encoded.contains(part)) }
        await rig.monitor.stop()
    }

    // R, C6/Traced failure: a 401 on the first request pauses the profile with no second request;
    // the same token stays paused on re-check and a new token resumes it, without any nudge or Claude read.
    @Test func rejectedTokenPausesAndNewTokenResumes() async throws {
        let old = cpFutureJWT("old"), new = cpFutureJWT("new")
        let rig = CPRig(cursor: cpFound(old), reactive: true, handler: cpHandler(rejecting: old))
        await rig.monitor.setNudgeEnabled(true)
        await rig.start()
        var row = await cpDisplayRow(rig.monitor)
        #expect(row?.health == .unauthenticated && cpPaused(row) && row?.snapshot == nil)
        #expect(await rig.transport.count() == 1)
        await rig.recheck()
        let still = await cpDisplayRow(rig.monitor), sent = await rig.transport.count()
        #expect(cpPaused(still) && rig.cursor.count() == 2 && sent == 1)
        rig.cursor.set(cpFound(new))
        await rig.recheck()
        row = await cpDisplayRow(rig.monitor)
        #expect(row?.health == .healthy && row?.snapshot?.metrics.count == 1)
        #expect(await cpStat(rig.monitor, "credentialResumes") == 1)
        #expect(await rig.bearers() == [old, new, new])
        try await Task.sleep(for: .milliseconds(100))
        #expect(rig.nudger.count() == 0 && rig.claude.count() == 0 && rig.files.count() == 0)
        await rig.monitor.stop()
    }
    // N, C6: a 403 pauses like a 401 (R4); any other unexpected status fails without a second request or a pause.
    @Test func forbiddenPausesAndServerErrorFailsAfterOneRequest() async throws {
        let forbidden = CPRig(cursor: cpFound(cpFutureJWT()), handler: { _, _ in .success(cpResponse(403)) })
        await forbidden.start()
        let blocked = await cpDisplayRow(forbidden.monitor), blockedSent = await forbidden.transport.count()
        #expect(blocked?.health == .unauthenticated && blockedSent == 1)
        await forbidden.monitor.stop()
        let broken = CPRig(cursor: cpFound(cpFutureJWT()), handler: { _, _ in .success(cpResponse(500)) })
        await broken.start()
        let row = await cpDisplayRow(broken.monitor)
        let brokenSent = await broken.transport.count()
        #expect(row?.health != .healthy && row?.health != .unauthenticated && row?.snapshot == nil && brokenSent == 1)
        await broken.monitor.stop()
    }

    // R, C6: an expired token pauses without any request; a re-check after a new token resumes.
    @Test func expiredTokenPausesAndNewTokenResumes() async throws {
        let expired = cpJWT(exp: 1_799_999_999), fresh = cpFutureJWT("fresh")
        let rig = CPRig(cursor: cpFound(expired))
        await rig.start()
        let row = await cpDisplayRow(rig.monitor)
        #expect(row?.health == .unauthenticated && cpPaused(row))
        #expect(await rig.transport.count() == 0)
        await rig.recheck()
        let still = await cpDisplayRow(rig.monitor), sent = await rig.transport.count()
        #expect(cpPaused(still) && sent == 0)
        rig.cursor.set(cpFound(fresh))
        await rig.recheck()
        #expect((await cpDisplayRow(rig.monitor))?.health == .healthy)
        #expect(await cpStat(rig.monitor, "credentialResumes") == 1)
        #expect(await rig.bearers() == [fresh, fresh])
        await rig.monitor.stop()
    }
    // I, C6/S6: no nudge ever runs for an expired Cursor session, and the Claude nudge still runs for Claude.
    @Test func cursorExpiryNeverNudgesButClaudeStillDoes() async throws {
        let cursor = CPRig(cursor: cpFound(cpJWT(exp: 1_799_999_990)), reactive: true)
        await cursor.monitor.setNudgeEnabled(true)
        await cursor.start()
        cursor.clock.move(wall: 301, mono: 301)
        await cursor.monitor.refresh(driver: .cycle); #expect(await cursor.monitor.settle())
        #expect(await cpStat(cursor.monitor, "credentialRechecks") >= 1)
        try await Task.sleep(for: .milliseconds(150))
        let nudges = await cpStat(cursor.monitor, "nudges")
        #expect(cursor.nudger.count() == 0 && nudges == 0)
        #expect(cursor.claude.count() == 0)
        await cursor.monitor.stop()

        let expiredClaude = KeychainReadOutcome(result: .found(cpClaudeData(token: "invented-claude", expiresAt: cpNow.addingTimeInterval(-10))), reason: .found)
        let claude = CPRig(cursor: cpFound(cpFutureJWT("unused")), claude: expiredClaude, reactive: true)
        await claude.monitor.setNudgeEnabled(true)
        await claude.start([AccountProfile(id: "cl", providerID: "claude", label: "Claude", source: .claudeDefaultDiscovery)])
        claude.clock.move(wall: 301, mono: 301)
        await claude.monitor.refresh(driver: .cycle); #expect(await claude.monitor.settle())
        #expect(await cpEventually { claude.nudger.count() == 1 })
        #expect(claude.cursor.count() == 0)
        await claude.monitor.stop()
    }
    // N, C6: two Cursor profiles with the same token alias to one entity (one request pair); different tokens do not.
    @Test func sameTokenAliasesToOneEntity() async throws {
        let token = cpFutureJWT("shared")
        let second = AccountProfile(id: "cu2", providerID: "cursor", label: "Second", source: .cursorDefaultDiscovery)
        let alias = CPRig(cursor: cpFound(token))
        await alias.start([cpProfile, second])
        let aliasSent = await alias.transport.count()
        #expect(aliasSent == 2 && alias.cursor.count() == 2)
        var rows: [ProfileDisplay] = []
        for id in ["cu", "cu2"] { if let row = await cpDisplayRow(alias.monitor, id) { rows.append(row) } }
        #expect(rows.count == 2 && rows.allSatisfy { $0.health == .healthy })
        #expect(rows.filter { $0.snapshot?.metrics.count == 1 }.count == 1)
        #expect(rows.filter { $0.message?.hasPrefix("Alias of ") == true }.count == 1)
        #expect(rows.filter { $0.snapshot == nil }.allSatisfy { $0.message?.hasPrefix("Alias of ") == true })
        await alias.monitor.stop()

        // Control: two different tokens give two entities, so four requests.
        let different = CPKeychain(cpFound(cpFutureJWT("a")), cpFound(cpFutureJWT("b")))
        let transport = CPTransport(cpMonitorAnswers())
        let monitor = Monitor(clock: CPClock(), credentials: CredentialStore(files: CPFiles(), keychain: CPKeychain(cpNotFound), cursorKeychain: different),
                              transport: transport, recheckInterval: 30)
        await monitor.setProfiles([cpProfile, second]); #expect(await monitor.settle())
        #expect(await transport.count() == 4)
        await monitor.stop()
    }
    // I, C6/threat: Cursor and Claude profiles read only their own keychain, send only their own request kind,
    // and a rejected Cursor token does not pause Claude.
    @Test func providersStayIsolated() async throws {
        let healthy = cpMonitorAnswers()
        let claudeData = KeychainReadOutcome(result: .found(cpClaudeData(token: "invented-claude", expiresAt: cpNow.addingTimeInterval(3600))), reason: .found)
        let rig = CPRig(cursor: cpFound(cpFutureJWT("iso")), claude: claudeData) { request, index in
            request.providerID == "cursor" ? .success(cpResponse(401)) : healthy(request, index)
        }
        await rig.start([cpProfile, AccountProfile(id: "cl", providerID: "claude", label: "Claude", source: .claudeDefaultDiscovery)])
        #expect(rig.cursor.count() == 1 && rig.claude.count() == 1 && rig.files.count() == 0)
        let requests = await rig.transport.requests()
        #expect(requests.filter { $0.providerID == "cursor" }.map(\.cursorOperation) == [.currentBillingCycle])
        #expect(requests.filter { $0.providerID == "claude" }.allSatisfy { $0.cursorOperation == nil && $0.bearer == "invented-claude" })
        #expect(requests.count == 2)
        #expect((await cpDisplayRow(rig.monitor))?.health == .unauthenticated)
        #expect((await cpDisplayRow(rig.monitor, "cl"))?.health == .healthy)
        await rig.monitor.stop()
    }
    // I, I6: sourceMatches accepts only the pairing (cursor, cursorDefaultDiscovery); no keychain is read otherwise.
    @Test func mismatchedProviderAndSourceAreRejectedUnread() async throws {
        let rig = CPRig(cursor: cpFound(cpFutureJWT("mm")), claude: cpFound("invented-claude-mm"))
        await rig.start([AccountProfile(id: "a", providerID: "cursor", label: "A", source: .claudeDefaultDiscovery),
                         AccountProfile(id: "b", providerID: "claude", label: "B", source: .cursorDefaultDiscovery),
                         AccountProfile(id: "c", providerID: "codex", label: "C", source: .cursorDefaultDiscovery)])
        let sent = await rig.transport.count()
        #expect(rig.cursor.count() == 0 && rig.claude.count() == 0 && sent == 0)
        for id in ["a", "b", "c"] { #expect((await cpDisplayRow(rig.monitor, id))?.snapshot == nil) }
        await rig.monitor.stop()
    }
    // N, I6: reconnect reads the Cursor keychain interactively.
    @Test func reconnectReadsInteractively() async throws {
        let rig = CPRig(cursor: cpDenied())
        await rig.start()
        let denied = await cpDisplayRow(rig.monitor)
        #expect(denied?.health == .unauthenticated && rig.cursor.interactions() == [false])
        rig.cursor.set(cpFound(cpFutureJWT("rc")))
        await rig.monitor.reconnect("cu"); #expect(await rig.monitor.settle())
        #expect(rig.cursor.interactions() == [false, true])
        #expect((await cpDisplayRow(rig.monitor))?.health == .healthy)
        await rig.monitor.stop()
    }
    // N, Traced invalid period: an inverted cycle fails after one request and the last good snapshot is kept.
    @Test func invalidCycleFromServerFailsKeepingTheLastSnapshot() async throws {
        let healthy = cpMonitorAnswers()
        let bad = CPRig(cursor: cpFound(cpFutureJWT("bad")), handler: { _, _ in cpOK(cpCycle(cpEnd, cpStart)) })
        await bad.start()
        let first = await cpDisplayRow(bad.monitor)
        let badSent = await bad.transport.count()
        #expect(first?.snapshot == nil && first?.health != .healthy && badSent == 1)
        await bad.monitor.stop()

        let rig = CPRig(cursor: cpFound(cpFutureJWT("good"))) { request, index in
            index < 2 ? healthy(request, index) : cpOK(cpCycle(cpEnd, cpStart))
        }
        await rig.start()
        #expect((await cpDisplayRow(rig.monitor))?.health == .healthy)
        rig.clock.move(wall: 60, mono: 60)
        await rig.monitor.manualRefresh(); #expect(await rig.monitor.settle())
        let row = await cpDisplayRow(rig.monitor)
        #expect(await rig.transport.count() == 3)
        #expect(row?.health == .failed && abs((row?.snapshot?.metrics.first?.usedPercent ?? -1) - 0.82) < 1e-9)
        await rig.monitor.stop()
    }
}
