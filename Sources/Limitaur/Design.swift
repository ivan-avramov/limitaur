import SwiftUI
import LimitaurCore

extension AccountStatus {
    var color: Color {
        switch self {
        case .healthy: .green
        case .partial: .yellow
        case .throttled, .unavailable, .failed: .orange
        case .signIn: .red
        case .stale, .off, .connecting: .gray
        }
    }
}

func percentText(_ value: Double?) -> String {
    guard let value = validatedPercent(value) else { return "—" }
    if value > 0 && value < 0.5 { return "<1%" }
    let rounded = value.rounded()
    if value < 100 && rounded >= 100 { return "99%" }
    return rounded < 1e15 ? "\(Int(rounded))%" : String(format: "%.0f%%", rounded)
}

func exactPercentText(_ value: Double?) -> String {
    value.map { String(format: "%.2f%%", $0) } ?? "unknown"
}

func amountText(_ amount: Decimal, currency: String, locale: Locale = .current) -> String {
    guard currency.count == 3, currency.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }) else {
        return "\(amount) \(currency)"
    }
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    formatter.locale = locale
    return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount) \(currency)"
}

func resetLabel(_ metric: UsageMetric, expired: Bool, now: Date) -> String {
    if expired { return "reset due" }
    guard let reset = metric.resetsAt else { return "reset unknown" }
    let text = resetCountdownText(resetAt: reset, now: now)
    return text == "reset due" || text == "reset time unavailable" ? text : "resets " + text
}

/// Warning text: system yellow in dark appearance, a darker amber that stays legible in light appearance.
let warningTextColor = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? .systemYellow : NSColor(srgbRed: 0.70, green: 0.50, blue: 0.00, alpha: 1)
})

/// Warning amber, critical red, otherwise the primary text colour.
func severityColor(_ percent: Double?) -> Color {
    switch severity(percent) {
    case .warning: warningTextColor
    case .critical: .red
    case .normal, .unknown: .primary
    }
}

/// The absolute reset date for a tooltip, as the dropdown has always shown it.
func absoluteDateText(_ date: Date?) -> String {
    date.flatMap(displayableResetDate).map {
        DateFormatter.localizedString(from: $0, dateStyle: .full, timeStyle: .long)
    } ?? ""
}

/// Shows the effective code it is given, override or default.
struct ProviderBadge: View {
    let code: String
    var body: some View {
        Text(code)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .frame(width: 26, height: 17)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.09)))
            .accessibilityHidden(true)
    }
}

struct StatusChip: View {
    let label: String
    let color: Color
    init(status: AccountStatus) { label = status.label; color = status.color }
    init(label: String, color: Color) { self.label = label; self.color = color }
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

struct UsageBar: View {
    let percent: Double?
    /// A stale bar fills in the secondary colour whatever its severity.
    var stale = false
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                if let fill = ringFill(percent) {
                    Capsule().fill(fillColor).frame(width: proxy.size.width * fill)
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
    private var fillColor: Color {
        if stale { return .secondary }
        return switch severity(percent) {
        case .warning: .yellow
        case .critical: .red
        case .normal, .unknown: Color.primary.opacity(0.65)
        }
    }
}

extension View {
    /// The card surface shared by dropdown accounts.
    func cardStyle() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
}
