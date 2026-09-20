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
            .kerning(2)
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
                Text(title.uppercased()).font(.caption.weight(.bold)).kerning(1.4).foregroundStyle(HW.secondary)
                Spacer()
                if let icon { Image(systemName: icon).foregroundStyle(color) }
            }
            Text(value).font(.hw(.title2, design: .rounded, weight: .bold)).foregroundStyle(color)
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
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle)
            Text(title).font(.headline)
            Text(detail).font(.footnote).multilineTextAlignment(.center)
        }
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

enum ChartTime {
    private static let plain = ISO8601DateFormatter()
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        fractional.date(from: value) ?? plain.date(from: value)
    }

    static func range(_ first: Date, _ last: Date) -> String {
        "\(first.formatted(.dateTime.month(.abbreviated).day().hour().minute())) – \(last.formatted(.dateTime.month(.abbreviated).day().hour().minute())) · device time"
    }
}

enum IPAddressSafety {
    static func isInternal(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { UInt8($0) }
        if parts.count == 4 {
            return parts[0] == 10 || parts[0] == 127 ||
                (parts[0] == 172 && (16...31).contains(parts[1])) ||
                (parts[0] == 192 && parts[1] == 168) ||
                (parts[0] == 169 && parts[1] == 254)
        }
        let lower = address.lowercased()
        return lower == "::1" || lower.hasPrefix("fc") || lower.hasPrefix("fd") || lower.hasPrefix("fe8") || lower.hasPrefix("fe9") || lower.hasPrefix("fea") || lower.hasPrefix("feb")
    }
}

enum RequestEvidence {
    static func usableHost(_ host: String) -> Bool {
        let value = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value == "_" || value == "-" || value == "localhost" || IPAddressSafety.isInternal(value) { return false }
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
                label.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains($0) }
        }
    }

    static func diagnosis(status: Int, host: String, method: String, path: String, upstream: String?) -> String {
        if status == 400 && method == "UNKNOWN" && !usableHost(host) && (path == "/" || !path.hasPrefix("/")) {
            return "Nginx rejected a request with no parsed HTTP method or usable Host. No application or destination page is identified. For older samples, “/” may be a collector fallback rather than a requested page. The incoming bytes and exact parser error were not retained."
        }
        if !usableHost(host) {
            return "The recorded host is “\(host.isEmpty ? "missing" : host)”, not a usable website domain. Nginx could not associate this request with a configured site; no destination URL can be reconstructed."
        }
        switch status {
        case 400: return "Bad Request: the proxy rejected this HTTP request. The exact parser reason is not retained; correlate the request ID and time with the Nginx error log."
        case 404: return "Not Found: the requested path did not resolve on the observed host. Check the route and upstream application logs."
        case 408: return "Request Timeout: the client did not complete the request in time."
        case 499: return "Client Closed Request: the client disconnected before the server finished responding."
        case 502...504 where upstream != nil: return "Gateway failure involving upstream \(upstream!). Correlate the upstream status, request ID and time with the application logs."
        case 502...504: return "Gateway failure with no upstream address recorded. Check the proxy error log using the request ID and time."
        default: return status >= 400 ? "HTTP error recorded. Response bodies are not collected; use the request ID, time and upstream details to find the exact cause in server logs." : "Request completed without an HTTP error."
        }
    }

    static func destinationURL(host: String, path: String, scheme: String?, method: String = "GET") -> URL? {
        guard ["GET", "HEAD"].contains(method.uppercased()), usableHost(host), path.hasPrefix("/") else { return nil }
        var components = URLComponents()
        components.scheme = scheme == "http" ? "http" : "https"
        components.host = host
        components.path = path
        return components.url
    }

    static func destinationURL(for request: RequestSample) -> URL? {
        destinationURL(host: request.host, path: request.path, scheme: request.scheme, method: request.method)
    }
}

struct DestinationGroup: Identifiable {
    let path: String
    let count: Int
    let sample: RequestSample
    var id: String { path }
    var url: URL? { RequestEvidence.destinationURL(for: sample) }

    static func groups(from requests: [RequestSample]) -> [DestinationGroup] {
        Dictionary(grouping: requests, by: \.path).map { path, rows in
            let sample = rows.first(where: { RequestEvidence.destinationURL(for: $0) != nil }) ?? rows[0]
            return DestinationGroup(path: path, count: rows.count, sample: sample)
        }.sorted { $0.count > $1.count }
    }
}

struct PagedRows<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var pageSize: Int = 24
    @ViewBuilder var content: (Item) -> Content
    @State private var visibleCount = 24

    var body: some View {
        let limit = min(items.count, max(pageSize, visibleCount))
        let shown = Array(items.prefix(limit))
        ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
            content(item)
                .onAppear {
                    if index == shown.count - 1, shown.count < items.count {
                        visibleCount = min(items.count, shown.count + pageSize)
                    }
                }
        }
        if limit < items.count {
            Button {
                visibleCount = min(items.count, limit + pageSize)
            } label: {
                Label("Show more · \(items.count - limit) remaining", systemImage: "arrow.down.circle")
            }
        }
    }
}

struct PageLoadingOverlay: View {
    let hasContent: Bool
    var body: some View {
        if hasContent {
            HStack(spacing: 8) {
                ProgressView().tint(HW.teal)
                Text("Updating…").font(.caption.bold()).foregroundStyle(HW.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(HW.panelRaised)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(HW.border))
            .padding(12)
        } else {
            ZStack {
                HW.background.opacity(0.94)
                VStack(spacing: 14) {
                    ProgressView().tint(HW.teal)
                    Text("Loading…").font(.subheadline.bold())
                    Text("Waiting for this page so the rest of the app stays responsive.")
                        .font(.caption)
                        .foregroundStyle(HW.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(22)
                .frame(maxWidth: 280)
                .panel()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
