import AppKit
import LimitaurCore
import Darwin
import CoreFoundation

private func output(_ value: Any) {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else { return }
    print(text)
}
private func fail() -> Never {
    try? FileHandle.standardError.write(contentsOf: Data("Invalid diagnostic input\n".utf8))
    exit(2)
}
private func timestamp(_ date: Date?) -> Any { date?.timeIntervalSince1970 ?? NSNull() }
private func fixtureObject(_ snapshot: UsageSnapshot) -> [String: Any] {
    ["providerID": snapshot.providerID.rawValue,
     "metrics": snapshot.metrics.map { ["id": $0.id, "label": $0.label,
                                        "usedPercent": $0.usedPercent as Any? ?? NSNull(),
                                        "resetsAt": timestamp($0.resetsAt),
                                        "conflictingObservations": $0.conflictingObservations.map { observations in
                                            observations.map { ["usedPercent": $0.usedPercent, "resetsAt": timestamp($0.resetsAt)] }
                                        } as Any? ?? NSNull()] as [String: Any] },
     "balances": snapshot.balances.map { ["label": $0.label,
                                          "remaining": $0.remaining.map { "\($0)" } as Any? ?? NSNull(),
                                          "currency": $0.currency as Any? ?? NSNull(),
                                          "unlimited": $0.unlimited, "expiresAt": timestamp($0.expiresAt)] as [String: Any] },
     "informationalAmounts": snapshot.informationalAmounts.map {
         ["label": $0.label, "amount": "\($0.amount)", "currency": $0.currency]
     },
     "resetCredits": snapshot.resetCredits.map { summary in
         ["availableCount": summary.availableCount as Any? ?? NSNull(),
          "applicableCount": summary.applicableCount as Any? ?? NSNull(),
          "details": summary.details.map { $0.map { ["id": $0.id, "label": $0.label, "expiresAt": timestamp($0.expiresAt)] as [String: Any] } } as Any? ?? NSNull()] as [String: Any]
     } as Any? ?? NSNull(),
     "partial": snapshot.partial, "warnings": snapshot.warnings]
}

private final class LiveResults: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: [String: Any]] = [:]
    func put(_ provider: ProviderID, _ value: [String: Any]) {
        lock.lock(); values[provider.rawValue] = value; lock.unlock()
    }
    func get(_ provider: ProviderID) -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }; return values[provider.rawValue]
    }
}

private func unavailable(_ provider: ProviderID) -> [String: Any] {
    ["providerID": provider.rawValue, "status": "unavailable", "metricCount": NSNull(),
     "balanceCount": NSNull(), "resetMetadataAvailable": NSNull()]
}

private func checkLive() {
    let store = CredentialStore(), transport = NativeHTTPTransport()
    let profiles: [(ProviderID, CredentialSource)] = [
        ("codex", .codexFile(CredentialStore.defaultCodexPath)),
        ("claude", .claudeDefaultDiscovery)
    ]
    let group = DispatchGroup()
    let results = LiveResults()
    for (provider, source) in profiles {
        group.enter()
        Task.detached {
            defer { group.leave() }
            do {
                let credential = try store.load(source, now: Date())
                let response = try await transport.send(HTTPRequest(providerID: provider,
                                                                    bearer: credential.accessToken,
                                                                    accountID: credential.selectedAccountID))
                if response.status == 200 {
                    let snapshot = try UsageDecoder.decode(provider: provider, data: response.body)
                    results.put(provider, ["providerID": provider.rawValue,
                                           "status": snapshot.partial ? "partial" : "success",
                                           "metricCount": snapshot.metrics.count,
                                           "balanceCount": snapshot.balances.count,
                                           "resetMetadataAvailable": snapshot.resetCredits != nil])
                } else {
                    results.put(provider, ["providerID": provider.rawValue,
                                           "status": response.status == 401 || response.status == 403 ? "unauthenticated" :
                                           response.status == 429 ? "throttled" : "unavailable",
                                           "metricCount": NSNull(), "balanceCount": NSNull(),
                                           "resetMetadataAvailable": NSNull()])
                }
            } catch {
                results.put(provider, unavailable(provider))
            }
        }
    }
    _ = group.wait(timeout: .now() + 20)
    output(profiles.map { results.get($0.0) ?? unavailable($0.0) })
}

@MainActor private func png(_ view: NSView, path: String, appearance: NSAppearance) throws {
    let window = NSWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = appearance
    window.contentView = view
    view.appearance = appearance
    view.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    bitmap.size = view.bounds.size
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

@MainActor private func renderDemo(_ directory: String) throws {
    _ = NSApplication.shared
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var sample = [
        UsageSnapshot(providerID: "codex", accountID: "demo-a", accountLabel: "Demo", fetchedAt: now,
                      metrics: [UsageMetric(id: "session", label: "Session", usedPercent: 25, resetsAt: now.addingTimeInterval(3600)),
                                UsageMetric(id: "weekly", label: "Weekly", usedPercent: 85, resetsAt: now.addingTimeInterval(86400))],
                      balances: [CreditBalance(label: "Provider credits", remaining: Decimal(4))],
                      resetCredits: ResetCreditSummary(availableCount: 2, applicableCount: 1, details: nil)),
        UsageSnapshot(providerID: "claude", accountID: "demo-b", accountLabel: "Demo", fetchedAt: now,
                      metrics: [UsageMetric(id: "weekly_scoped:fable", label: "Fable", usedPercent: 98, resetsAt: now.addingTimeInterval(7200))])
    ]
    for index in 0..<6 {
        sample.append(UsageSnapshot(providerID: index.isMultiple(of: 2) ? "codex" : "claude",
                                    accountID: AccountID("demo-extra-\(index)"), accountLabel: "Demo \(index + 1)", fetchedAt: now,
                                    metrics: [UsageMetric(id: "extra-\(index)", label: "Window \(index + 1)",
                                                          usedPercent: Double(10 + index * 7), resetsAt: now.addingTimeInterval(7200))]))
    }
    let selected = rankMetrics(sample, wallNow: now, maximumCount: 8)
    let rows = sample.enumerated().map { index, snapshot in
        ProfileDisplay(profile: AccountProfile(id: snapshot.accountID.rawValue, providerID: snapshot.providerID,
                                               label: snapshot.accountLabel, source: snapshot.providerID == "codex" ? .codexFile("/demo") : .claudeFile("/demo")),
                       snapshot: snapshot, health: .healthy, message: nil, fetchedAge: 0,
                       freshnessDeadline: 190, snapshotGeneration: index + 1)
    }
    let identities = Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (String, Int)? in
        guard let snapshot = row.snapshot, let generation = row.snapshotGeneration else { return nil }
        return (snapshot.providerID.rawValue + "\u{1f}" + snapshot.accountID.rawValue, generation)
    })
    let candidates = selected.compactMap { metric -> PresentationCandidate? in
        guard let generation = identities[metric.providerID.rawValue + "\u{1f}" + metric.accountID.rawValue] else { return nil }
        return PresentationCandidate(metric: metric, freshnessDeadline: 190, snapshotGeneration: generation)
    }
    let display = MonitorDisplay(profiles: rows, candidates: candidates, revision: 1, nextDisplayDeadline: nil)
    for theme in ["light", "dark"] {
        let appearance = NSAppearance(named: theme == "light" ? .aqua : .darkAqua)!
        for count in [1, 3, 5, 8] {
            var observed: [Int: SnapshotExpirations] = [:]
            let projection = projectDisplay(display, count: count, wallNow: now, monotonicNow: 100,
                                            observations: &observed)
            let bars = RingView(frame: NSRect(x: 0, y: 0, width: RingView.statusWidth(for: count), height: 24))
            bars.count = count; bars.selected = projection.selected
            try png(bars, path: directory + "/bars-\(count)-\(theme).png", appearance: appearance)
            if count == 3 {
                let current = RingView.layout
                defer { RingView.layout = current }
                for (layout, name) in [(RingView.Layout.jar, "jar"), (.beside, "beside"), (.logo, "logo")] {
                    RingView.layout = layout
                    for (backdrop, white) in [("plain", theme == "light" ? 0.93 : 0.13), ("highlighted", theme == "light" ? 0.72 : 0.5)] {
                        let preview = RingView(frame: NSRect(x: 0, y: 0, width: RingView.statusWidth(for: 3), height: 24))
                        preview.count = 3; preview.selected = projection.selected
                        let container = NSView(frame: preview.frame)
                        container.wantsLayer = true
                        container.layer?.backgroundColor = NSColor(calibratedWhite: white, alpha: 1).cgColor
                        container.addSubview(preview)
                        try png(container, path: directory + "/layout-\(name)-\(backdrop)-\(theme).png", appearance: appearance)
                    }
                }
            }
            if count == 3 { try png(bars, path: directory + "/rings-\(theme).png", appearance: appearance) }
            let empty = RingView(frame: NSRect(x: 0, y: 0, width: RingView.statusWidth(for: count), height: 24))
            empty.count = count; empty.unavailableProviders = ["claude", "codex"]
            try png(empty, path: directory + "/bars-\(count)-empty-stale-\(theme).png", appearance: appearance)
            if count == 3 { try png(empty, path: directory + "/empty-stale-\(theme).png", appearance: appearance) }
            let zeroSnapshot = UsageSnapshot(providerID: "codex", accountID: "demo-zero", accountLabel: "Demo",
                                             fetchedAt: now, metrics: [UsageMetric(id: "zero", label: "Known zero", usedPercent: 0)])
            let zero = RingView(frame: NSRect(x: 0, y: 0, width: RingView.statusWidth(for: count), height: 24))
            zero.count = count; zero.selected = [RankedMetric(snapshot: zeroSnapshot, metric: zeroSnapshot.metrics[0])]
            try png(zero, path: directory + "/bars-\(count)-zero-\(theme).png", appearance: appearance)
        }
        let dropdown = DropdownView(frame: NSRect(x: 0, y: 0, width: 340, height: 420))
        dropdown.renderNow = now
        let groupedRows = rows.sorted {
            ($0.profile.providerID.rawValue, $0.profile.id) <
            ($1.profile.providerID.rawValue, $1.profile.id)
        }
        dropdown.update(groupedRows, demo: true)
        try png(dropdown, path: directory + "/dropdown-\(theme).png", appearance: appearance)
        let staleRow = ProfileDisplay(profile: AccountProfile(id: "codex-stale", providerID: "codex", label: "Demo",
                                                            source: .codexFile("/demo")),
                                      snapshot: sample[0], health: .stale, message: "Connection unavailable", fetchedAge: 120)
        let unavailableRow = ProfileDisplay(profile: AccountProfile(id: "claude-unavailable", providerID: "claude", label: "Demo",
                                                                  source: .claudeFile("/demo")),
                                            snapshot: nil, health: .unavailable, message: "Provider unavailable", fetchedAge: nil)
        let emptyDropdown = DropdownView(frame: NSRect(x: 0, y: 0, width: 340, height: 420))
        emptyDropdown.renderNow = now
        emptyDropdown.update([staleRow, unavailableRow], demo: true)
        try png(emptyDropdown, path: directory + "/dropdown-empty-stale-\(theme).png", appearance: appearance)
    }
}

@main struct Main {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let version = AppVersion.commandLineResponse(args) {
            print(version, terminator: "")
            return
        }
        if args.count >= 2 {
            switch args[1] {
            case "--version": fail()
            case "--check-percent":
                guard args.count == 3 else { fail() }
                let value = Double(args[2])
                output(["severity": severity(value).rawValue, "fill": ringFill(value) as Any? ?? NSNull()])
                return
            case "--inspect-fixture":
                guard args.count == 4, let data = try? Data(contentsOf: URL(fileURLWithPath: args[3])) else { fail() }
                do { output(fixtureObject(try UsageDecoder.decode(provider: ProviderID(args[2]), data: data))) }
                catch { fail() }
                return
            case "--rank-fixture":
                guard (args.count == 5 || args.count == 7), args[3] == "--now", let now = Double(args[4]), now.isFinite else { fail() }
                let count: Int
                if args.count == 7 {
                    guard args[5] == "--count", let supplied = Int(args[6]), (1...8).contains(supplied) else { fail() }
                    count = supplied
                } else { count = 3 }
                guard
                      let data = try? Data(contentsOf: URL(fileURLWithPath: args[2])),
                      let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { fail() }
                var snapshots: [UsageSnapshot] = []
                var ages: [String: TimeInterval] = [:]
                for row in rows {
                    guard let provider = row["providerID"] as? String, let account = row["accountID"] as? String,
                          let fetched = row["fetchedAt"] as? NSNumber,
                          let metricRows = row["metrics"] as? [[String: Any]] else { fail() }
                    let metrics = metricRows.compactMap { metric -> UsageMetric? in
                        guard let id = metric["id"] as? String, let label = metric["label"] as? String else { return nil }
                        let raw = metric["usedPercent"] as? NSNumber
                        let percent = raw.flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.doubleValue }
                        let reset = (metric["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                        return UsageMetric(id: id, label: label, usedPercent: percent, resetsAt: reset)
                    }
                    let snapshot = UsageSnapshot(providerID: ProviderID(provider), accountID: AccountID(account),
                                                 accountLabel: row["accountLabel"] as? String ?? account,
                                                 fetchedAt: Date(timeIntervalSince1970: fetched.doubleValue), metrics: metrics)
                    snapshots.append(snapshot)
                    ages[provider + "\u{1f}" + account] = max(0, now - fetched.doubleValue)
                }
                output(rankMetrics(snapshots, wallNow: Date(timeIntervalSince1970: now), elapsedAges: ages,
                                   maximumCount: count).map {
                    ["providerID": $0.providerID.rawValue, "accountID": $0.accountID.rawValue,
                     "id": $0.metric.id, "usedPercent": $0.metric.usedPercent as Any? ?? NSNull()]
                })
                return
            case "--render-demo":
                guard args.count == 3 else { fail() }
                do { try renderDemo(args[2]) } catch { fail() }
                return
            case "--check-live":
                guard args.count == 2 else { fail() }
                checkLive()
                return
            case "--help":
                guard args.count == 2 else { fail() }
                output(["diagnostics": ["--version", "--demo", "--demo-open-popover", "--demo-light", "--demo-dark",
                                        "--render-demo DIRECTORY", "--check-percent VALUE",
                                        "--inspect-fixture PROVIDER FILE", "--rank-fixture FILE --now UNIX_SECONDS [--count 1...8]",
                                        "--check-live", "--stats FILE"]])
                return
            case "--demo", "--demo-open-popover", "--demo-light", "--demo-dark":
                guard args.count == 2 else { fail() }
            case "--stats": break
            default: fail()
            }
        }
        let app = NSApplication.shared
        if args.count > 1 && args[1] == "--stats" && args.count != 3 { fail() }
        let demoOptions = ["--demo", "--demo-open-popover", "--demo-light", "--demo-dark"]
        let demo = args.count == 2 && demoOptions.contains(args[1])
        let appearance: NSAppearance.Name? = args.count == 2 && args[1] == "--demo-light" ? .aqua :
            args.count == 2 && args[1] == "--demo-dark" ? .darkAqua : nil
        let controller = AppController(demo: demo, demoAppearance: appearance,
                                       statisticsPath: args.count == 3 && args[1] == "--stats" ? args[2] : nil)
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }
}
