import AppKit
import SwiftUI
import LimitaurCore

struct SettingsAccount: Identifiable, Equatable { let id: String; var label: String; var enabled: Bool
    var source: CredentialSource; var status: AccountStatus; var message: String? }
struct SettingsSection: Identifiable, Equatable { let provider: ProviderID; var main: SettingsAccount?
    var others: [SettingsAccount]; var id: String { provider.rawValue } }

@MainActor final class SettingsModel: ObservableObject {
    static let providers: [ProviderID] = ["claude", "codex", "cursor"]
    @Published private(set) var sections: [SettingsSection] = []
    @Published private(set) var indicatorCount: Int
    @Published private(set) var nudgeEnabled: Bool
    @Published private(set) var claudeResetDay: MonthlyResetDay
    @Published private(set) var budget: SharedBudgetConfig
    let editable: Bool
    private(set) var profiles: [AccountProfile]
    private var statuses: [String: (AccountStatus, String?)] = [:]
    /// Each provider main account's last reported spend limit and currency, for the budget pre-fill.
    private var reportedLimits: [ProviderID: (Decimal, String)] = [:]
    private let onProfiles: ([AccountProfile]) -> Void, onIndicatorCount: (Int) -> Void, onNudge: (Bool) -> Void
    private let onConnect: (String) -> Void, onAbout: () -> Void
    private let onClaudeResetDay: (MonthlyResetDay) -> Void, onBudget: (SharedBudgetConfig) -> Void

    static let budgetProviders: [ProviderID] = ["claude", "cursor"]
    static let defaultBudget = SharedBudgetConfig(enabled: false, amount: nil, currency: "USD",
                                                  members: budgetProviders, resetDay: .default)

    init(profiles: [AccountProfile], indicatorCount: Int, nudgeEnabled: Bool, editable: Bool,
         claudeResetDay: MonthlyResetDay = .default, budget: SharedBudgetConfig = SettingsModel.defaultBudget,
         onProfiles: @escaping ([AccountProfile]) -> Void, onIndicatorCount: @escaping (Int) -> Void,
         onNudge: @escaping (Bool) -> Void, onConnect: @escaping (String) -> Void, onAbout: @escaping () -> Void,
         onClaudeResetDay: @escaping (MonthlyResetDay) -> Void = { _ in },
         onBudget: @escaping (SharedBudgetConfig) -> Void = { _ in }) {
        self.profiles = profiles; self.indicatorCount = indicatorCount; self.nudgeEnabled = nudgeEnabled
        self.claudeResetDay = claudeResetDay; self.budget = budget.validated
        self.editable = editable; self.onProfiles = onProfiles; self.onIndicatorCount = onIndicatorCount
        self.onNudge = onNudge; self.onConnect = onConnect; self.onAbout = onAbout
        self.onClaudeResetDay = onClaudeResetDay; self.onBudget = onBudget
        rebuild()
    }

    /// Enabled main accounts by provider, as the shared budget reads them.
    var mainProfileIDs: [ProviderID: String] {
        Dictionary(uniqueKeysWithValues: sections.compactMap { section in
            section.main.flatMap { $0.enabled ? (section.provider, $0.id) : nil }
        })
    }

    /// `<provider>-default`, else the provider's first profile in saved order.
    private func mainIndex(_ provider: ProviderID) -> Int? {
        profiles.firstIndex { $0.id == provider.rawValue + "-default" && $0.providerID == provider }
            ?? profiles.firstIndex { $0.providerID == provider }
    }

    private func rebuild() {
        func account(_ profile: AccountProfile) -> SettingsAccount {
            let status: AccountStatus, message: String?
            if !profile.enabled { status = .off; message = nil }
            else if let (known, text) = statuses[profile.id] { status = known; message = text }
            else { status = .connecting; message = nil }
            return SettingsAccount(id: profile.id, label: profile.label, enabled: profile.enabled,
                                   source: profile.source, status: status, message: message)
        }
        let next = Self.providers.map { provider in
            let main = mainIndex(provider)
            return SettingsSection(provider: provider, main: main.map { account(profiles[$0]) },
                                   others: profiles.indices.filter { $0 != main && profiles[$0].providerID == provider }
                                       .map { account(profiles[$0]) })
        }
        if next != sections { sections = next }
    }

    /// Applies `change` to a copy; reports and republishes only when the list differs.
    private func mutate(_ change: (inout [AccountProfile]) -> Void) {
        guard editable else { return }
        var next = profiles
        change(&next)
        guard next != profiles else { return }
        profiles = next
        rebuild()
        onProfiles(next)
    }

    func setProviderEnabled(_ provider: ProviderID, _ enabled: Bool) {
        guard Self.providers.contains(provider) else { return }
        let main = mainIndex(provider)
        mutate { list in
            if let main { list[main].enabled = enabled; return }
            guard enabled else { return }
            let source: CredentialSource = switch provider.rawValue {
            case "claude": .claudeDefaultDiscovery
            case "codex": .codexFile(CredentialStore.defaultCodexPath)
            default: .cursorDefaultDiscovery
            }
            list.append(AccountProfile(id: provider.rawValue + "-default", providerID: provider, label: "Default",
                                       source: source, enabled: true))
        }
    }

    func setClaudeUsesKeychain(_ keychain: Bool) {
        guard let main = mainIndex("claude") else { return }
        mutate { list in
            if keychain { list[main].source = .claudeDefaultDiscovery }
            else if case .claudeFile = list[main].source {}
            else { list[main].source = .claudeFile(CredentialStore.defaultClaudePath) }
        }
    }

    @discardableResult func setSourcePath(_ accountID: String, _ path: String) -> Bool {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard editable, path.hasPrefix("/"), let index = profiles.firstIndex(where: { $0.id == accountID }) else { return false }
        let source: CredentialSource
        switch profiles[index].providerID.rawValue {
        case "codex": source = .codexFile(path)
        case "claude": source = .claudeFile(path)
        default: return false
        }
        mutate { $0[index].source = source }
        return true
    }

    func setLabel(_ accountID: String, _ label: String) {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, let index = profiles.firstIndex(where: { $0.id == accountID }) else { return }
        mutate { $0[index].label = label }
    }

    func setAccountEnabled(_ accountID: String, _ enabled: Bool) {
        guard let index = profiles.firstIndex(where: { $0.id == accountID }) else { return }
        mutate { $0[index].enabled = enabled }
    }

    func addAccount(_ provider: ProviderID) -> String? {
        guard editable else { return nil }
        let source: CredentialSource
        switch provider.rawValue {
        case "codex": source = .codexFile(CredentialStore.defaultCodexPath)
        case "claude": source = .claudeFile(CredentialStore.defaultClaudePath)
        default: return nil
        }
        let used = Set(profiles.filter { $0.providerID == provider }.map(\.label))
        let n = (2...).first { !used.contains("Account \($0)") }!
        let id = UUID().uuidString
        mutate { $0.append(AccountProfile(id: id, providerID: provider, label: "Account \(n)", source: source, enabled: false)) }
        return id
    }

    func removeAccount(_ accountID: String) {
        guard let index = profiles.firstIndex(where: { $0.id == accountID }),
              mainIndex(profiles[index].providerID) != index else { return }
        mutate { $0.remove(at: index) }
    }

    /// Works in demo too: the count is presentation only.
    func setIndicatorCount(_ count: Int) {
        guard (1...8).contains(count), count != indicatorCount else { return }
        indicatorCount = count
        onIndicatorCount(count)
    }

    func setNudge(_ enabled: Bool) {
        guard editable, enabled != nudgeEnabled else { return }
        nudgeEnabled = enabled
        onNudge(enabled)
    }

    // The reset day and the shared budget are local display settings: they apply in demo too.
    func setClaudeResetDay(_ day: MonthlyResetDay) {
        guard day != claudeResetDay else { return }
        claudeResetDay = day
        onClaudeResetDay(day)
    }

    /// Turning on with no amount pre-fills the members' reported limit when they all report the same one.
    func setBudgetEnabled(_ enabled: Bool) {
        var next = budget
        next.enabled = enabled
        if enabled, next.amount == nil {
            let limits = next.members.map { reportedLimits[$0] }
            if let first = limits.first ?? nil, limits.allSatisfy({ $0?.0 == first.0 && $0?.1 == first.1 }) {
                next.amount = first.0
            }
        }
        changeBudget(next)
    }

    /// A positive decimal in the current locale, with or without its currency symbol.
    func setBudgetAmount(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = [NumberFormatter.Style.currency, .decimal].lazy.compactMap { style -> Decimal? in
            let formatter = NumberFormatter()
            formatter.numberStyle = style; formatter.locale = .current; formatter.generatesDecimalNumbers = true
            if style == .currency { formatter.currencyCode = self.budget.currency }
            return (formatter.number(from: text) as? NSDecimalNumber)?.decimalValue
        }.first
        guard let amount = parsed, amount > 0, amount.isFinite else { return false }
        var next = budget
        next.amount = amount
        changeBudget(next)
        return true
    }

    func setBudgetMember(_ provider: ProviderID, _ included: Bool) {
        guard Self.budgetProviders.contains(provider) else { return }
        var next = budget
        if included { if !next.members.contains(provider) { next.members.append(provider) } }
        else { next.members.removeAll { $0 == provider } }
        changeBudget(next)
    }

    func setBudgetResetDay(_ day: MonthlyResetDay) {
        var next = budget
        next.resetDay = day
        changeBudget(next)
    }

    private func changeBudget(_ next: SharedBudgetConfig) {
        let next = next.validated
        guard next != budget else { return }
        budget = next
        onBudget(next)
    }

    func updateReportedLimits(_ rows: [ProfileDisplay]) {
        for provider in Self.providers {
            guard let main = mainIndex(provider) else { reportedLimits[provider] = nil; continue }
            guard let snapshot = rows.first(where: { $0.profile.id == profiles[main].id })?.snapshot else { continue }
            reportedLimits[provider] = snapshot.spend.flatMap { spend in spend.limit.map { ($0, spend.currency) } }
        }
    }

    func connect(_ accountID: String) { if editable { onConnect(accountID) } }
    func showAbout() { onAbout() }

    func updateStatuses(_ rows: [ProfileDisplay]) {
        statuses = Dictionary(rows.map { row in
            let status = AccountStatus(row: row)
            return (row.profile.id, (status, status == .connecting ? nil : row.message))
        }, uniquingKeysWith: { first, _ in first })
        rebuild()
    }
}

// MARK: - Views

/// Secondary footnote text used under Settings controls.
private func footnote(_ text: String) -> some View {
    Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
}

private func sourcePath(_ source: CredentialSource) -> String? {
    switch source {
    case .codexFile(let path), .claudeFile(let path): path
    case .claudeDefaultDiscovery, .cursorDefaultDiscovery: nil
    }
}

/// A file-only, single-selection open panel starting in the current path's directory.
@MainActor private func chooseFile(_ model: SettingsModel, _ account: SettingsAccount) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true; panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
    if let path = sourcePath(account.source) {
        panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
    }
    if panel.runModal() == .OK, let url = panel.url { model.setSourcePath(account.id, url.path) }
}

/// A credential path, or "Keychain item" for Claude discovery, with its "Choose…" button.
private struct PathRow: View {
    @ObservedObject var model: SettingsModel
    let provider: ProviderID
    let account: SettingsAccount
    var body: some View {
        let path = sourcePath(account.source) ?? "Keychain item"
        HStack {
            Text(path).font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).help(path)
            Spacer(minLength: 8)
            Button("Choose…") { chooseFile(model, account) }
                .accessibilityLabel("Choose file for \(providerName(provider)) \(account.label)")
        }
    }
}

@MainActor private func enableToggle(_ model: SettingsModel, _ provider: ProviderID, _ account: SettingsAccount) -> some View {
    Toggle(account.label, isOn: Binding(get: { account.enabled }, set: { model.setAccountEnabled(account.id, $0) }))
        .toggleStyle(.switch).labelsHidden().controlSize(.small)
        .accessibilityLabel("\(providerName(provider)) \(account.label) enabled")
}

@MainActor private func removeButton(_ model: SettingsModel, _ account: SettingsAccount) -> some View {
    Button { model.removeAccount(account.id) } label: { Image(systemName: "trash") }
        .buttonStyle(.borderless)
        .help("Remove \(account.label)")
        .accessibilityLabel("Remove \(account.label)")
}

struct ProvidersSettingsView: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            if !model.editable { Section { footnote("Demo data; provider settings are read-only.") } }
            ForEach(model.sections) { ProviderSectionView(model: model, section: $0) }
        }
        .formStyle(.grouped)
        .disabled(!model.editable)
        .frame(width: 560)
        .frame(minHeight: 420, maxHeight: 640)
    }
}

private struct ProviderSectionView: View {
    @ObservedObject var model: SettingsModel
    let section: SettingsSection
    private var name: String { providerName(section.provider) }
    private var on: Bool { section.main?.enabled ?? false }

    var body: some View {
        Section {
            HStack(spacing: 8) {
                ProviderBadge(provider: section.provider)
                Text(name).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Toggle(name, isOn: Binding(get: { on }, set: { model.setProviderEnabled(section.provider, $0) }))
                    .toggleStyle(.switch).labelsHidden()
                    .accessibilityLabel("\(name) enabled")
            }
            if on, let main = section.main { rows(main) }
            else { footnote(offLine) }
            others
        }
    }

    /// Shown whatever the main switch says.
    @ViewBuilder private var others: some View {
        if section.provider == "cursor" {
            ForEach(section.others) { account in
                HStack(spacing: 8) {
                    Text(account.label)
                    Spacer()
                    StatusChip(status: account.status)
                    enableToggle(model, section.provider, account)
                    removeButton(model, account)
                }
            }
        } else if section.others.isEmpty {
            addButton("Add another account")
        } else {
            DisclosureGroup("Other accounts (\(section.others.count))") {
                ForEach(section.others) { OtherAccountRow(model: model, provider: section.provider, account: $0) }
                addButton("Add account")
            }
        }
    }

    private func addButton(_ title: String) -> some View {
        Button { _ = model.addAccount(section.provider) } label: { Label(title, systemImage: "plus") }
            .buttonStyle(.borderless)
    }

    private var offLine: String {
        switch section.provider.rawValue {
        case "claude": "Reads the Claude Code sign-in"
        case "codex": "Reads ~/.codex/auth.json"
        default: "Reads the cursor-agent sign-in"
        }
    }

    @ViewBuilder private func rows(_ main: SettingsAccount) -> some View {
        switch section.provider.rawValue {
        case "claude":
            Picker("Source", selection: Binding(get: { main.source == .claudeDefaultDiscovery },
                                                set: { model.setClaudeUsesKeychain($0) })) {
                Text("Keychain item").tag(true)
                Text("Credential file").tag(false)
            }.pickerStyle(.menu)
            if main.source != .claudeDefaultDiscovery { PathRow(model: model, provider: section.provider, account: main) }
        case "codex":
            LabeledContent("Source") { PathRow(model: model, provider: section.provider, account: main) }
        default:
            LabeledContent("Source") { Text("cursor-agent sign-in") }
        }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Status")
                Spacer()
                StatusChip(status: main.status)
                if main.status == .signIn {
                    Button("Connect / Authorize") { model.connect(main.id) }.controlSize(.small)
                }
            }
            if let message = main.message { footnote(message) }
        }
        if section.provider == "claude" {
            Toggle(isOn: Binding(get: { model.nudgeEnabled }, set: { model.setNudge($0) })) {
                Text("Renew an expired session by running claude")
                Text("Runs claude at most once an hour so Claude Code renews its sign-in. Turn off if Claude Code authenticates with an API key.")
            }
            ResetDayPicker(day: model.claudeResetDay, set: model.setClaudeResetDay) {
                Text("Spend resets")
                Text("Claude does not report this; the 1st matches the Claude app. Times are UTC.")
            }
        }
        if section.provider == "cursor" {
            footnote("Run cursor-agent login when the session expires; Limitaur picks it up within five minutes.")
        }
    }
}

private struct OtherAccountRow: View {
    @ObservedObject var model: SettingsModel
    let provider: ProviderID
    let account: SettingsAccount
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Label", text: $draft).labelsHidden().textFieldStyle(.roundedBorder)
                    .focused($focused).onSubmit(commit)
                    .accessibilityLabel("Label for \(providerName(provider)) \(account.label)")
                enableToggle(model, provider, account)
                removeButton(model, account)
            }
            PathRow(model: model, provider: provider, account: account)
            StatusChip(status: account.status)
        }
        .padding(.vertical, 2)
        .onAppear { draft = account.label }
        .onChange(of: account.label) { _, label in draft = label }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .onDisappear(perform: commit)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)
            .filter { $0.object is SettingsPanel }) { _ in commit() }
    }

    private func commit() {
        model.setLabel(account.id, draft)
        draft = model.profiles.first { $0.id == account.id }?.label ?? draft
    }
}

/// "1st" … "28th", or "Last day of the month".
func resetDayTitle(_ day: MonthlyResetDay) -> String {
    guard case .day(let n) = MonthlyResetDay(storage: day.storage) else { return "Last day of the month" }
    let suffix = (11...13).contains(n) ? "th" : [1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th"
    return "\(n)\(suffix)"
}

/// A menu of the monthly reset days, labelled by `label`.
private struct ResetDayPicker<Label: View>: View {
    let day: MonthlyResetDay
    let set: (MonthlyResetDay) -> Void
    @ViewBuilder let label: Label
    var body: some View {
        Picker(selection: Binding(get: { day.storage }, set: { MonthlyResetDay(storage: $0).map(set) })) {
            ForEach(1...28, id: \.self) { Text(resetDayTitle(.day($0))).tag(String($0)) }
            Text(resetDayTitle(.lastDay)).tag(MonthlyResetDay.lastDay.storage)
        } label: { label }
        .pickerStyle(.menu)
    }
}

/// The budget amount as currency; a refused entry reverts to the current amount.
private struct BudgetAmountField: View {
    @ObservedObject var model: SettingsModel
    @State private var draft = ""
    @FocusState private var focused: Bool
    private var shown: String { model.budget.amount.map { amountText($0, currency: model.budget.currency) } ?? "" }

    var body: some View {
        LabeledContent("Amount") {
            TextField("Amount", text: $draft, prompt: Text(amountText(0, currency: model.budget.currency)))
                .labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 140)
                .focused($focused).onSubmit(commit)
                .accessibilityLabel("Shared budget amount")
        }
        .onAppear { draft = shown }
        .onChange(of: model.budget.amount) { _, _ in draft = shown }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .onDisappear(perform: commit)
    }

    private func commit() {
        if draft != shown { _ = model.setBudgetAmount(draft) }
        draft = shown
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        // The indicator count and About work in demo too.
        Form {
            Section {
                Picker("Indicators", selection: Binding(get: { model.indicatorCount }, set: { model.setIndicatorCount($0) })) {
                    ForEach(1...8, id: \.self) { Text("\($0)").tag($0) }
                }.pickerStyle(.segmented)
            } header: { Text("Menu bar") } footer: { footnote("Number of usage bars shown in the menu bar.") }
            Section {
                Toggle("Track a shared monthly budget", isOn: Binding(get: { model.budget.enabled }, set: { model.setBudgetEnabled($0) }))
                if model.budget.enabled {
                    BudgetAmountField(model: model)
                    LabeledContent("Includes") {
                        HStack(spacing: 12) {
                            ForEach(SettingsModel.budgetProviders, id: \.self) { provider in
                                Toggle(providerName(provider), isOn: Binding(get: { model.budget.members.contains(provider) },
                                                                             set: { model.setBudgetMember(provider, $0) }))
                                    .toggleStyle(.checkbox)
                                    .accessibilityLabel("Include \(providerName(provider)) in shared budget")
                            }
                        }
                    }
                    ResetDayPicker(day: model.budget.resetDay, set: model.setBudgetResetDay) { Text("Resets") }
                }
            } header: { Text("Shared budget") } footer: {
                if model.budget.enabled {
                    footnote("Limitaur adds each provider's reported spend for the month. This budget is yours; no provider enforces it.")
                }
            }
            Section("About") {
                LabeledContent("Version", value: AppVersion.string)
                Button("About Limitaur…") { model.showAbout() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Escape closes the window, as in other Settings windows.
private final class SettingsPanel: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

/// The single Settings window: General and Providers toolbar tabs, created lazily and reused.
@MainActor final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    static func show(_ model: SettingsModel) {
        let controller = shared ?? SettingsWindowController(model: model)
        shared = controller
        NSApp.activate()
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init(model: SettingsModel) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for (title, symbol, view) in [("General", "gearshape", AnyView(GeneralSettingsView(model: model))),
                                      ("Providers", "person.2", AnyView(ProvidersSettingsView(model: model)))] {
            let host = NSHostingController(rootView: view)
            host.sizingOptions = .preferredContentSize
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        let window = SettingsPanel(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.isReleasedWhenClosed = false
        // Centred the first time; afterwards at the top-left point the operator left it. The tab sets the size.
        let saved = UserDefaults.standard.string(forKey: Self.topLeftKey).map(NSPointFromString)
        if let saved, NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(saved) }) {
            window.setFrameTopLeftPoint(saved)
        } else { window.center() }
        super.init(window: window)
        window.delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static let topLeftKey = "settingsWindowTopLeft"
    private func saveTopLeft() {
        guard let frame = window?.frame else { return }
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: frame.minX, y: frame.maxY)), forKey: Self.topLeftKey)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) { saveTopLeft() }
    func windowWillClose(_ notification: Notification) { saveTopLeft() }
}
