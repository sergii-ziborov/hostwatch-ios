import SwiftUI

enum HW {
    static let background = Color(red: 0.025, green: 0.045, blue: 0.065)
    static let panel = Color(red: 0.055, green: 0.090, blue: 0.125)
    static let panelRaised = Color(red: 0.070, green: 0.112, blue: 0.150)
    static let border = Color(red: 0.16, green: 0.27, blue: 0.34)
    static let teal = Color(red: 0.25, green: 0.90, blue: 0.82)
    static let amber = Color(red: 1.00, green: 0.68, blue: 0.31)
    static let red = Color(red: 1.00, green: 0.37, blue: 0.43)
    static let secondary = Color(red: 0.56, green: 0.65, blue: 0.75)
}

struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(HW.panel)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(HW.border, lineWidth: 1))
    }
}

extension View {
    func panel() -> some View { modifier(PanelModifier()) }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(2)
            .foregroundStyle(HW.secondary)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var detail: String = ""
    var color: Color = HW.teal
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased()).font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(HW.secondary)
                Spacer()
                if let icon { Image(systemName: icon).foregroundStyle(color) }
            }
            Text(value).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(color)
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(HW.secondary).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, minHeight: 105, alignment: .topLeading)
        .padding(16)
        .panel()
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(detail))
            .foregroundStyle(HW.secondary)
            .frame(maxWidth: .infinity, minHeight: 220)
    }
}

enum Format {
    static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var amount = max(0, value)
        var index = 0
        while amount >= 1024, index < units.count - 1 { amount /= 1024; index += 1 }
        let digits = amount >= 100 || index == 0 ? 0 : 1
        return "\(amount.formatted(.number.precision(.fractionLength(digits)))) \(units[index])"
    }

    static func rate(_ value: Double) -> String { "\(bytes(value))/s" }
    static func percent(_ value: Double) -> String { "\(value.formatted(.number.precision(.fractionLength(1))))%" }
    static func duration(_ seconds: Double) -> String {
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h"
    }
}

