import SwiftUI
import LimitaurCore

@MainActor final class DropdownModel: ObservableObject {
    @Published var rows: [ProfileDisplay] = []
    @Published var budget: SharedBudgetState?
    @Published var now = Date()
    @Published var polling: [String: PollingPolicy] = [:]
    @Published var demo = false
    @Published var refresh: () -> Void = {}
    @Published var settings: () -> Void = {}
    @Published var quit: () -> Void = {}
    @Published var connect: (String) -> Void = { _ in }

    /// Accessibility titles of the offered actions, in visual order.
    func actionTitles() -> [String] {
        var titles = ["Refresh", "Settings"]
        if !demo {
            titles += rows.filter { $0.health == .unauthenticated }.map { "Connect / Authorize \($0.profile.label)" }
            if rows.isEmpty { titles.append("Open Settings") }
        }
        return titles + ["Quit"]
    }

    func perform(_ title: String) {
        guard actionTitles().contains(title) else { return }
        switch title {
        case "Refresh": refresh()
        case "Settings", "Open Settings": settings()
        case "Quit": quit()
        default:
            if let row = rows.first(where: { $0.health == .unauthenticated && "Connect / Authorize \($0.profile.label)" == title }) {
                connect(row.profile.id)
            }
        }
    }
}

struct DropdownPanel: View {
    @ObservedObject var model: DropdownModel
    private enum Focus { case refresh, list }
    @FocusState private var focus: Focus?
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var geometry = ScrollMetrics()
    /// 560 less the padding, the fixed 22-point header and footer, two dividers and four 10-point gaps.
    private static let maxListHeight: CGFloat = 560 - 28 - 44 - 2 - 40

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            if model.rows.isEmpty {
                if let budget = model.budget { BudgetCard(budget: budget, now: model.now) }
                emptyState
            } else { cards }
            Divider()
            HStack {
                Spacer()
                Button("Quit") { model.perform("Quit") }.buttonStyle(.borderless)
                    .keyboardShortcut("q", modifiers: .command)
            }.frame(height: 22)
        }
        .padding(14)
        .frame(width: 360)
        .defaultFocus($focus, .refresh)
        .onAppear { focus = .refresh }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Limitaur").font(.system(size: 13, weight: .bold))
            if model.demo {
                Text("Demo").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.09)))
            }
            Spacer()
            iconButton("arrow.clockwise", "Refresh", key: "r").focused($focus, equals: .refresh)
            iconButton("gearshape", "Settings", key: ",")
        }.frame(height: 22)
    }

    private func iconButton(_ symbol: String, _ title: String, key: KeyEquivalent) -> some View {
        Button { model.perform(title) } label: { Image(systemName: symbol).font(.system(size: 13)) }
            .buttonStyle(.borderless)
            .keyboardShortcut(key, modifiers: .command)
            .help(title)
            .accessibilityLabel(title)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No enabled accounts").font(.system(size: 12)).foregroundStyle(.secondary)
            if !model.demo { Button("Open Settings") { model.perform("Open Settings") } }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// The list takes its content's height up to the cap in the same layout pass, so the popover
    /// opens at its final size; beyond the cap it scrolls, by keyboard too once focused.
    private var cards: some View {
        CappedHeight(maximum: Self.maxListHeight) {
            ScrollView {
                VStack(spacing: 10) {
                    if let budget = model.budget { BudgetCard(budget: budget, now: model.now) }
                    ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                        AccountCard(row: row, now: model.now, interval: model.polling[row.profile.providerID.rawValue]?.interval,
                                    demo: model.demo) { model.connect(row.profile.id) }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollPosition($scroll)
            .onScrollGeometryChange(for: ScrollMetrics.self) {
                ScrollMetrics(offset: $0.contentOffset.y, viewport: $0.containerSize.height, content: $0.contentSize.height)
            } action: { _, value in geometry = value }
            .focusable()
            .focused($focus, equals: .list)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .pageUp, .pageDown, .home, .end]) { press in
                let page = max(geometry.viewport - 40, 40)
                let target: CGFloat = switch press.key {
                case .upArrow: geometry.offset - 40
                case .downArrow: geometry.offset + 40
                case .pageUp: geometry.offset - page
                case .pageDown: geometry.offset + page
                case .home: 0
                default: .greatestFiniteMagnitude
                }
                scroll.scrollTo(y: min(max(0, target), max(0, geometry.content - geometry.viewport)))
                return .handled
            }
        }
    }
}

private struct ScrollMetrics: Equatable { var offset: CGFloat = 0, viewport: CGFloat = 0, content: CGFloat = 0 }

/// Sizes its single child to the child's ideal height, capped at `maximum`.
private struct CappedHeight: Layout {
    let maximum: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? ideal.width, height: min(ideal.height, maximum))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// The user's shared budget: the members' summed spend against the configured amount, or why it is unknown.
private struct BudgetCard: View {
    let budget: SharedBudgetState
    let now: Date

    var body: some View {
        let currency = budget.config.currency
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ProviderBadge(provider: "budget")
                Text("Shared budget").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 6)
                StatusChip(label: "Your budget", color: .gray)
            }
            let metric = UsageMetric(id: "spend:shared", label: "This month", usedPercent: budget.usedPercent, resetsAt: budget.resetsAt)
            let reset = resetLabel(metric, expired: now >= budget.resetsAt, now: now)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(metric.label).font(.system(size: 12)).lineLimit(1).layoutPriority(1)
                    Spacer(minLength: 8)
                    Text(reset).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                        .help(absoluteDateText(budget.resetsAt))
                    Text(percentText(budget.usedPercent))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(severityColor(budget.usedPercent))
                        .help(exactPercentText(budget.usedPercent))
                        .padding(.leading, 8)
                        .layoutPriority(2)
                }
                UsageBar(percent: budget.usedPercent)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Shared budget this month, \(percentText(budget.usedPercent)), \(reset)")
            if let warning = budget.warning {
                Label(warning, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(.orange)
            } else if let total = budget.total, let amount = budget.config.amount {
                Text("\(amountText(total, currency: currency)) of \(amountText(amount, currency: currency))")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(budget.members.enumerated()), id: \.offset) { _, member in
                    HStack(spacing: 6) {
                        ProviderBadge(provider: member.provider)
                        Text(providerName(member.provider))
                        Spacer(minLength: 6)
                        Text(member.spent.map { amountText($0, currency: currency) } ?? member.problem ?? "")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.system(size: 11))
                    .accessibilityElement(children: .combine)
                }
            }
            Text("Your budget across providers, not a provider limit. Reported spend can lag.")
                .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }
}

private struct AccountCard: View {
    let row: ProfileDisplay
    let now: Date
    let interval: TimeInterval?
    let demo: Bool
    let connect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ProviderBadge(provider: row.profile.providerID)
                Text("\(providerName(row.profile.providerID)) · \(Text(row.profile.label).foregroundStyle(.secondary))")
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 6)
                StatusChip(status: AccountStatus(row: row))
            }
            if let snapshot = row.snapshot {
                VStack(alignment: .leading, spacing: 8) {
                    if snapshot.metrics.isEmpty { secondary("Quota metrics unavailable") }
                    ForEach(Array(snapshot.metrics.enumerated()), id: \.offset) { _, metric in metricBlock(metric) }
                }
                details(snapshot)
            }
            if let line = footerLine {
                Text(line.trimmingCharacters(in: .whitespaces)).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            if let message = row.message, AccountStatus(row: row) != .connecting { secondary(message) }
            if row.health == .unauthenticated && !demo {
                Button("Connect / Authorize", action: connect)
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .accessibilityLabel("Connect / Authorize \(row.profile.label)")
            }
        }
        .cardStyle()
    }

    private var footerLine: String? {
        let age = row.fetchedAge.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        if row.snapshot != nil, let age { return fetchedLine(age: age, interval: interval) }
        if age == nil, let interval { return pollsLine(interval: interval) }
        return nil
    }

    private func secondary(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func metricTitle(_ metric: UsageMetric) -> String {
        metric.label + (metric.scopeLabel.map { " · " + $0 } ?? "")
    }

    @ViewBuilder private func metricBlock(_ metric: UsageMetric) -> some View {
        if let observations = metric.conflictingObservations {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(metricTitle(metric)).font(.system(size: 12))
                    Spacer()
                    Text("conflicted · usage unknown").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(Array(observations.enumerated()), id: \.offset) { _, observation in
                    let reset = observation.resetsAt.map { resetCountdownText(resetAt: $0, now: now) } ?? "reset unknown"
                    secondary("Observed \(exactPercentText(observation.usedPercent)) · \(reset)")
                        .help(absoluteDateText(observation.resetsAt))
                }
            }
        } else {
            let reset = resetLabel(metric, expired: row.expirations.metrics.contains(metric.id), now: now)
            let stale = row.health == .stale
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(metricTitle(metric)).font(.system(size: 12)).lineLimit(1).layoutPriority(1)
                    Spacer(minLength: 8)
                    Text(reset).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                        .help(absoluteDateText(metric.resetsAt))
                    Text(percentText(metric.usedPercent))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(stale ? Color.secondary : severityColor(metric.usedPercent))
                        .help(exactPercentText(metric.usedPercent))
                        .padding(.leading, 8)
                        .layoutPriority(2)
                }
                UsageBar(percent: metric.usedPercent, stale: stale)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(metricTitle(metric)), \(percentText(metric.usedPercent)), \(reset)")
        }
    }

    @ViewBuilder private func details(_ snapshot: UsageSnapshot) -> some View {
        let lines = detailLines(snapshot)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        // An empty symbol keeps a detail line aligned under its group's icon.
                        if let symbol = line.symbol {
                            if symbol.isEmpty { Color.clear.frame(width: 14, height: 1) }
                            else { Image(systemName: symbol).frame(width: 14) }
                        }
                        Text(line.label).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        if let value = line.value { Text(value).multilineTextAlignment(.trailing) }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(line.warning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private struct DetailLine { var symbol: String?; var label: String; var value: String?; var warning = false }

    private func detailLines(_ snapshot: UsageSnapshot) -> [DetailLine] {
        var lines: [DetailLine] = []
        for (index, balance) in snapshot.balances.enumerated() {
            let unknown = switch balance.state {
            case .known, .unknown: "unknown"
            case .unavailable: "unavailable"
            case .inapplicable: "not applicable"
            }
            let amount = balance.unlimited ? "unlimited"
                : balance.remaining.map { amountText($0, currency: balance.currency ?? "credits") } ?? unknown
            let expiry = row.expirations.balances.contains(index) ? "expired (cached amount)"
                : balance.expiresAt.map(expiryText) ?? "expiry unknown"
            lines.append(DetailLine(symbol: "creditcard", label: balance.label, value: "\(amount) · \(expiry)"))
        }
        for amount in snapshot.informationalAmounts {
            lines.append(DetailLine(symbol: "dollarsign.circle", label: amount.label,
                                    value: amountText(amount.amount, currency: amount.currency)))
        }
        if let credits = snapshot.resetCredits {
            let cached = row.expirations.credits.isEmpty ? "" : " (reported; some details expired)"
            lines.append(DetailLine(symbol: "arrow.counterclockwise", label: "Earned resets",
                                    value: "\(credits.availableCount.map(String.init) ?? "unknown") available\(cached)"))
            lines.append(DetailLine(symbol: "", label: "Applicable", value: credits.applicableCount.map(String.init) ?? "unknown"))
            if let details = credits.details {
                for (index, credit) in details.enumerated() {
                    let expiry = row.expirations.credits.contains(index) ? "expired (cached detail)"
                        : credit.expiresAt.map(expiryText) ?? "expiry unknown"
                    lines.append(DetailLine(symbol: "", label: credit.label, value: expiry))
                }
            } else { lines.append(DetailLine(symbol: "", label: "Reset detail and expiry unknown")) }
        }
        for capability in snapshot.capabilities { lines.append(DetailLine(symbol: nil, label: capability)) }
        for warning in snapshot.warnings {
            lines.append(DetailLine(symbol: "exclamationmark.triangle", label: warning, warning: true))
        }
        return lines
    }

    private func expiryText(_ date: Date) -> String {
        guard displayableResetDate(date) != nil else { return "expiry unknown" }
        let value = resetCountdownText(resetAt: date, now: now)
        return value == "reset due" ? "expired" : "expires \(value)"
    }
}
