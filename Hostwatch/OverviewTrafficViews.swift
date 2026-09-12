import Charts
import MapKit
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    private let columns = [GridItem(.adaptive(minimum: 185), spacing: 12)]

    var body: some View {
        if let value = model.overview {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: columns, spacing: 12) {
                    NavigationLink { ResourceDetailView(kind: .cpu) } label: { StatCard(title: "CPU", value: Format.percent(value.cpuPercent), detail: String(format: "load %.1f · %.1f · %.1f", value.load1, value.load5, value.load15), icon: "cpu") }
                    NavigationLink { ResourceDetailView(kind: .memory) } label: { StatCard(title: "Memory", value: Format.bytes(value.memory.used), detail: "\(Format.bytes(value.memory.available)) available", color: HW.amber, icon: "memorychip") }
                    NavigationLink { StorageInspectorView() } label: { StatCard(title: "Disk", value: Format.bytes(value.disk.used), detail: "\(Format.bytes(value.disk.free)) free of \(Format.bytes(value.disk.total))", icon: "internaldrive") }
                    NavigationLink { ResourceDetailView(kind: .network) } label: { StatCard(title: "Network egress", value: Format.rate(value.network.txBytesPerSecond), detail: "in \(Format.rate(value.network.rxBytesPerSecond)) · \(value.network.txPacketsPerSecond.formatted()) pkt/s", icon: "arrow.up.arrow.down") }
                }
                ResourceTimelineCard()
                HStack {
                    Label(value.nginxLogHealthy ? "Nginx analytics healthy" : "Nginx analytics unavailable", systemImage: value.nginxLogHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    Spacer()
                    Label(value.dockerHealthy ? "Docker healthy" : "Docker unavailable", systemImage: value.dockerHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                }
                .font(.footnote).foregroundStyle(HW.secondary).padding(16).panel()
            }
        } else { EmptyState(icon: "waveform.path.ecg", title: "No host snapshot", detail: "Pull to refresh after choosing a node.") }
    }
}

enum ResourceKind: String, Identifiable { case cpu = "CPU", memory = "Memory", network = "Network"; var id: String { rawValue } }

struct ResourceDetailView: View {
    @EnvironmentObject private var model: AppModel
    let kind: ResourceKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow(text: "Host resource inspector")
                Text(kind.rawValue).font(.largeTitle.bold())
                if let overview = model.overview {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                        ForEach(stats(overview), id: \.0) { StatCard(title: $0.0, value: $0.1, detail: $0.2, color: $0.3) }
                    }
                    ResourceTimelineCard(focus: kind)
                    detailRows(overview)
                }
            }
            .padding(20)
        }
        .background(HW.background).navigationTitle(kind.rawValue).navigationBarTitleDisplayMode(.inline)
    }

    private func stats(_ value: Overview) -> [(String, String, String, Color)] {
        switch kind {
        case .cpu:
            [("Current", Format.percent(value.cpuPercent), "Across all cores", HW.teal), ("Load 1m", value.load1.formatted(.number.precision(.fractionLength(2))), "5m \(value.load5.formatted())", HW.amber), ("Health", value.cpuPercent > 85 ? "Critical" : "Healthy", "Alert threshold 85%", value.cpuPercent > 85 ? HW.red : HW.teal)]
        case .memory:
            [("Used", Format.bytes(value.memory.used), "of \(Format.bytes(value.memory.total))", HW.amber), ("Available", Format.bytes(value.memory.available), "Immediately reclaimable", HW.teal), ("Swap", Format.bytes(value.memory.swapUsed), "of \(Format.bytes(value.memory.swapTotal))", value.memory.swapUsed > 0 ? HW.amber : HW.teal)]
        case .network:
            [("Egress", Format.rate(value.network.txBytesPerSecond), "\(value.network.txPacketsPerSecond.formatted()) packets/s", HW.teal), ("Ingress", Format.rate(value.network.rxBytesPerSecond), "\(value.network.rxPacketsPerSecond.formatted()) packets/s", HW.teal), ("Period egress", Format.bytes(value.network.txBytes), "Current counter", HW.amber)]
        }
    }

    @ViewBuilder private func detailRows(_ value: Overview) -> some View {
        VStack(spacing: 0) {
            metricRow("Host", value.hostname)
            metricRow("Collected", value.timestamp)
            metricRow("Uptime", Format.duration(value.uptimeSeconds))
            metricRow("Selected window", "\(model.hours) hours")
        }.padding(.horizontal, 16).panel()
    }

    private func metricRow(_ name: String, _ value: String) -> some View {
        HStack { Text(name).foregroundStyle(HW.secondary); Spacer(); Text(value).font(.system(.body, design: .monospaced)).multilineTextAlignment(.trailing) }
            .padding(.vertical, 14).overlay(alignment: .bottom) { Divider().overlay(HW.border) }
    }
}

struct ResourceTimelineCard: View {
    @EnvironmentObject private var model: AppModel
    var focus: ResourceKind? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { VStack(alignment: .leading) { Eyebrow(text: "Last \(model.hours) hours"); Text(focus.map { "\($0.rawValue) history" } ?? "CPU, memory & load").font(.title3.bold()) }; Spacer(); Text("Drag to inspect").font(.caption).foregroundStyle(HW.secondary) }
            Chart(Array(model.traffic.enumerated()), id: \.offset) { index, point in
                LineMark(x: .value("Interval", index), y: .value("Requests", point.requests)).foregroundStyle(HW.teal).interpolationMethod(.catmullRom)
                if focus == nil || focus == .memory { LineMark(x: .value("Interval", index), y: .value("Latency", min(point.averageMs / 10, 100))).foregroundStyle(HW.amber).interpolationMethod(.catmullRom) }
            }
            .chartYScale(domain: 0...max(120, model.traffic.map(\.requests).max() ?? 120)).frame(height: 230)
        }
        .padding(18).panel()
    }
}

struct StorageInspectorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab = "Sites"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) { Eyebrow(text: "Host resource inspector"); Text("Disk").font(.largeTitle.bold()); Text("Space by project, data type and exact path").foregroundStyle(HW.secondary) }
                    Spacer(); Button("Rescan", systemImage: "arrow.clockwise") { Task { await model.scanStorage(refresh: true) } }.buttonStyle(.bordered)
                }
                if let storage = model.storage {
                    let ratio = storage.disk.total > 0 ? storage.disk.used / storage.disk.total : 0
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) { Text(Format.bytes(storage.disk.used)).font(.largeTitle.bold()); Text("used").foregroundStyle(HW.secondary); Spacer(); Text("\(Format.bytes(storage.disk.free)) free").foregroundStyle(HW.secondary) }
                        ProgressView(value: ratio).tint(ratio > 0.9 ? HW.red : ratio > 0.75 ? HW.amber : HW.teal)
                        Text(ratio > 0.9 ? "Critical · less than 10% free" : ratio > 0.75 ? "Watch · disk is over 75% full" : "Healthy · capacity available")
                            .font(.footnote.weight(.semibold)).foregroundStyle(ratio > 0.9 ? HW.red : ratio > 0.75 ? HW.amber : HW.teal)
                    }.padding(18).panel()

                    Picker("Breakdown", selection: $tab) { Text("Sites").tag("Sites"); Text("Types").tag("Types"); Text("Paths").tag("Paths") }.pickerStyle(.segmented)
                    if tab == "Sites" { groupList(storage.sites, hostBytes: storage.unattributedBytes) }
                    else if tab == "Types" { groupList(storage.categories, hostBytes: 0) }
                    else { entryList(storage.entries) }
                } else {
                    EmptyState(icon: "internaldrive", title: "Disk scan not loaded", detail: "Scan the host to attribute project, container, database, media and operating-system usage.")
                        .task { await model.scanStorage() }
                }
            }.padding(20)
        }
        .background(HW.background).navigationTitle("Disk").navigationBarTitleDisplayMode(.inline)
    }

    private func groupList(_ groups: [StorageGroup], hostBytes: Double) -> some View {
        VStack(spacing: 10) {
            ForEach(groups) { group in
                NavigationLink { StorageGroupDetail(group: group) } label: {
                    HStack { VStack(alignment: .leading) { Text(group.name).font(.headline); Text("\(group.items) storage areas · inspect exact files").font(.caption).foregroundStyle(HW.secondary) }; Spacer(); Text(Format.bytes(group.bytes)).font(.headline.monospacedDigit()); Image(systemName: "chevron.right").foregroundStyle(HW.secondary) }
                        .padding(16).panel()
                }
            }
            if hostBytes > 0 {
                Text("Host and shared data is included as a first-class group so the site totals reconcile with filesystem usage.").font(.footnote).foregroundStyle(HW.secondary).padding(12)
            }
        }
    }

    private func entryList(_ entries: [StorageEntry]) -> some View {
        VStack(spacing: 10) {
            ForEach(entries) { entry in
                NavigationLink { StoragePathDetail(entry: entry) } label: {
                    HStack { Image(systemName: entry.kind == "file" ? "doc" : "folder").foregroundStyle(HW.teal); VStack(alignment: .leading) { Text(entry.path).font(.system(.subheadline, design: .monospaced, weight: .semibold)).lineLimit(2); Text("\(entry.siteName ?? "Host & shared") · \(entry.category)").font(.caption).foregroundStyle(HW.secondary) }; Spacer(); Text(Format.bytes(entry.bytes)).font(.subheadline.bold()) }
                        .padding(15).panel()
                }
            }
        }
    }
}

struct StorageGroupDetail: View {
    @EnvironmentObject private var model: AppModel
    let group: StorageGroup
    var entries: [StorageEntry] { model.storage?.entries.filter { $0.siteId == group.id || $0.siteName == group.name || (group.id == "host" && $0.siteId == nil) || $0.category == group.name } ?? [] }
    var body: some View {
        List(entries) { entry in NavigationLink { StoragePathDetail(entry: entry) } label: { VStack(alignment: .leading) { Text(entry.path).font(.system(.body, design: .monospaced)); Text("\(entry.category) · \(Format.bytes(entry.bytes))").foregroundStyle(HW.secondary) } } }
            .scrollContentBackground(.hidden).background(HW.background).navigationTitle(group.name)
    }
}

struct StoragePathDetail: View {
    @EnvironmentObject private var model: AppModel
    let entry: StorageEntry
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow(text: entry.kind); Text(entry.path).font(.system(.title2, design: .monospaced, weight: .bold)).textSelection(.enabled)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                    StatCard(title: "Size", value: Format.bytes(entry.bytes), icon: "internaldrive")
                    StatCard(title: "Owner", value: entry.siteName ?? "Host & shared", detail: entry.siteId ?? "Operating system, containers or shared data", color: HW.amber, icon: "person.crop.square")
                    StatCard(title: "Type", value: entry.category, detail: entry.kind, icon: "folder")
                }
                Button("Open directory contents", systemImage: "folder.badge.gearshape") { Task { await model.browseStorage(path: entry.path) } }.buttonStyle(.borderedProminent)
                if let storage = model.storage, storage.mode == "browse", storage.path == entry.path {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Directory contents").font(.headline)
                        ForEach(storage.entries) { child in
                            NavigationLink { StoragePathDetail(entry: child) } label: { HStack { Text(child.path).font(.system(.caption, design: .monospaced)); Spacer(); Text(Format.bytes(child.bytes)) } }.padding(12).panel()
                        }
                        if storage.entries.isEmpty { Text("No deeper entries were returned by the bounded scanner.").foregroundStyle(HW.secondary) }
                    }
                }
            }.padding(20)
        }.background(HW.background).navigationTitle("Storage path").navigationBarTitleDisplayMode(.inline)
    }
}

struct TrafficView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TrafficChart()
            HStack(spacing: 12) {
                NavigationLink { RequestExplorerView() } label: { StatCard(title: "Retained requests", value: model.requests.count.formatted(), detail: "IP, location, destination and full trace", icon: "list.bullet.rectangle") }
                NavigationLink { ErrorExplorerView() } label: { StatCard(title: "Errors", value: model.errorEvidence?.retainedErrors.formatted() ?? "0", detail: "Status, method, path and request evidence", color: HW.red, icon: "exclamationmark.triangle") }
            }
            .buttonStyle(.plain)
            AttributionGrid()
        }
    }
}

struct TrafficChart: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { VStack(alignment: .leading) { Eyebrow(text: "HTTP traffic · last \(model.hours)h"); Text("Request volume").font(.title2.bold()); Text("Tap Requests or Errors below for complete evidence.").font(.caption).foregroundStyle(HW.secondary) }; Spacer(); Text(model.traffic.reduce(0) { $0 + Int($1.requests) }.formatted()).font(.title3.bold()) }
            Chart(Array(model.traffic.enumerated()), id: \.offset) { index, point in
                AreaMark(x: .value("Interval", index), y: .value("Requests", point.requests)).foregroundStyle(LinearGradient(colors: [HW.teal.opacity(0.34), .clear], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Interval", index), y: .value("Requests", point.requests)).foregroundStyle(HW.teal).interpolationMethod(.catmullRom)
                LineMark(x: .value("Interval", index), y: .value("Errors", point.errors4xx + point.errors5xx)).foregroundStyle(HW.amber)
            }.frame(height: 280)
        }.padding(18).panel()
    }
}

struct AttributionGrid: View {
    @EnvironmentObject private var model: AppModel
    let columns = [GridItem(.adaptive(minimum: 245), spacing: 12)]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Attribution"); Text("Where requests come from").font(.title2.bold())
            LazyVGrid(columns: columns, spacing: 12) {
                metricGroup("Sources & referrers", items: model.sources.sources, kind: "source")
                metricGroup("Countries", items: model.sources.countries, kind: "country")
                metricGroup("Bots", items: model.sources.bots, kind: "bot")
            }
        }
    }

    private func metricGroup(_ title: String, items: [SourceMetric], kind: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if items.isEmpty { Text("No retained attribution").foregroundStyle(HW.secondary).frame(maxWidth: .infinity, minHeight: 90) }
            ForEach(items.prefix(6)) { item in
                NavigationLink { SourceDetailView(kind: kind, source: item) } label: {
                    VStack(spacing: 7) {
                        HStack { Text(item.name).lineLimit(1); Spacer(); Text(item.requests.formatted(.number.precision(.fractionLength(0)))).bold(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(HW.secondary) }
                        ProgressView(value: item.requests, total: max(1, items.first?.requests ?? 1)).tint(HW.teal)
                        HStack { Text(Format.bytes(item.bytes)); Spacer(); Text("Inspect destinations & requests") }.font(.caption2).foregroundStyle(HW.secondary)
                    }
                }.buttonStyle(.plain)
            }
        }.padding(16).frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading).panel()
    }
}

struct RequestExplorerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var status = "All"
    private var filtered: [RequestSample] {
        model.requests.filter { row in
            (query.isEmpty || [row.path, row.clientIp, row.country, row.host, row.source].joined(separator: " ").localizedCaseInsensitiveContains(query)) &&
            (status == "All" || (status == "Errors" ? row.status >= 400 : row.status < 400))
        }
    }
    var body: some View {
        List {
            Section { TextField("Search IP, path, host, country…", text: $query); Picker("Status", selection: $status) { Text("All").tag("All"); Text("Successful").tag("Successful"); Text("Errors").tag("Errors") }.pickerStyle(.segmented) }
            Section("\(filtered.count) retained requests") {
                ForEach(filtered) { request in NavigationLink { RequestDetailView(request: request) } label: { RequestRow(request: request) } }
            }
        }.scrollContentBackground(.hidden).background(HW.background).navigationTitle("Requests")
    }
}

struct RequestRow: View {
    let request: RequestSample
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(request.method).font(.caption.bold()).foregroundStyle(HW.teal); Text(request.path).font(.system(.body, design: .monospaced, weight: .semibold)).lineLimit(1); Spacer(); Text(String(request.status)).foregroundStyle(request.status >= 400 ? HW.red : HW.teal).bold() }
            Text("\(request.host) · \(request.clientIp) · \(request.city ?? request.country) · \(request.durationMs.formatted()) ms").font(.caption).foregroundStyle(HW.secondary).lineLimit(1)
        }.padding(.vertical, 5)
    }
}

struct RequestDetailView: View {
    @EnvironmentObject private var model: AppModel
    let request: RequestSample
    @State private var confirmBlock = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow(text: "Individual HTTP request")
                Text("\(request.method) \(request.path)").font(.system(.title2, design: .rounded, weight: .bold)).textSelection(.enabled)
                Text("\(request.time) · \(request.host)").foregroundStyle(HW.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210))], spacing: 12) {
                    StatCard(title: "Response", value: String(request.status), detail: "\(request.durationMs.formatted()) ms · \(Format.bytes(request.bytes))", color: request.status >= 400 ? HW.red : HW.teal, icon: "arrow.left.arrow.right")
                    StatCard(title: "Client", value: request.clientIp, detail: "\(request.city ?? "Unknown"), \(request.country)", icon: "network")
                    StatCard(title: "Attribution", value: request.source, detail: request.referrerPath ?? "No usable referrer or UTM source", color: HW.amber, icon: "arrow.triangle.branch")
                    StatCard(title: "Agent", value: request.bot ?? "Browser / service", detail: request.userAgent, icon: "person.text.rectangle")
                }
                trace
                Button("Block this IP for \(siteName)", systemImage: "hand.raised.fill", role: .destructive) { confirmBlock = true }.buttonStyle(.borderedProminent).tint(HW.red)
            }.padding(20)
        }.background(HW.background).navigationTitle("Request").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Block \(request.clientIp)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block IP", role: .destructive) { Task { await model.block(site: request.site, kind: "ip", value: request.clientIp) } }
        } message: { Text("A project-scoped access rule will be applied to \(siteName).") }
    }
    private var siteName: String { model.sites.first(where: { $0.id == request.site })?.name ?? request.site }
    private var trace: some View {
        VStack(spacing: 0) {
            traceRow("Request ID", request.id); traceRow("Destination", "\(request.scheme ?? "https")://\(request.host)\(request.path)")
            traceRow("Protocol", [request.protocolName, request.tlsProtocol, request.tlsCipher].compactMap { $0 }.joined(separator: " · "))
            traceRow("Upstream", [request.upstreamAddr, request.upstreamStatus, request.upstreamMs.map { "\($0.formatted()) ms" }].compactMap { $0 }.joined(separator: " · "))
            traceRow("Cache", request.cacheStatus ?? "Not reported"); traceRow("Request bytes", request.requestBytes.map(Format.bytes) ?? "Not reported")
            traceRow("User agent", request.userAgent)
        }.padding(.horizontal, 16).panel()
    }
    private func traceRow(_ title: String, _ value: String) -> some View { HStack(alignment: .top) { Text(title).foregroundStyle(HW.secondary); Spacer(); Text(value.isEmpty ? "Not reported" : value).font(.system(.caption, design: .monospaced)).multilineTextAlignment(.trailing).textSelection(.enabled) }.padding(.vertical, 12).overlay(alignment: .bottom) { Divider().overlay(HW.border) } }
}

struct ErrorExplorerView: View {
    @EnvironmentObject private var model: AppModel
    private var errors: [RequestSample] { model.errorEvidence?.requests.filter { $0.status >= 400 } ?? [] }
    private var statuses: [(Int, Int)] { Dictionary(grouping: errors, by: \.status).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 } }
    private var methods: [(String, Int)] { Dictionary(grouping: errors, by: \.method).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 } }
    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 10) {
                    StatCard(title: "Retained errors", value: errors.count.formatted(), detail: model.errorEvidence?.capped == true ? "Buffer limit reached" : "Complete current RAM evidence", color: HW.red)
                    StatCard(title: "Client", value: errors.filter { (400..<500).contains($0.status) }.count.formatted(), detail: "HTTP 4xx", color: HW.red)
                    StatCard(title: "Server", value: errors.filter { $0.status >= 500 }.count.formatted(), detail: "HTTP 5xx", color: HW.red)
                }.listRowInsets(EdgeInsets())
            }
            Section("Response status") { ForEach(statuses, id: \.0) { item in NavigationLink { ErrorFilteredView(title: "HTTP \(item.0)", requests: errors.filter { $0.status == item.0 }) } label: { LabeledContent("HTTP \(item.0)", value: item.1.formatted()) } } }
            Section("Methods") { ForEach(methods, id: \.0) { item in NavigationLink { ErrorFilteredView(title: item.0, requests: errors.filter { $0.method == item.0 }) } label: { LabeledContent(item.0, value: item.1.formatted()) } } }
            Section("Affected paths") {
                ForEach(model.paths.filter { $0.errors4xx + $0.errors5xx > 0 }) { path in NavigationLink { PathDetailView(path: path) } label: { VStack(alignment: .leading) { HStack { Text(path.path).font(.system(.body, design: .monospaced)); Spacer(); Text("\(Int(path.errors4xx + path.errors5xx)) errors").foregroundStyle(HW.red) }; Text("\(Int(path.requests)) requests · \(path.averageMs.formatted()) ms average").font(.caption).foregroundStyle(HW.secondary) } } }
            }
            if errors.isEmpty { Section { EmptyState(icon: "clock.badge.questionmark", title: "No retained error requests", detail: "Historical aggregates remain valid, but old individual URLs and IPs cannot be reconstructed. New requests appear here as the bounded buffer fills.") } }
        }.scrollContentBackground(.hidden).background(HW.background).navigationTitle("Errors")
    }
}

struct ErrorFilteredView: View {
    let title: String; let requests: [RequestSample]
    var body: some View { List(requests) { request in NavigationLink { RequestDetailView(request: request) } label: { RequestRow(request: request) } }.scrollContentBackground(.hidden).background(HW.background).navigationTitle(title) }
}

struct PathDetailView: View {
    @EnvironmentObject private var model: AppModel
    let path: RequestPath
    var rows: [RequestSample] { path.path == "Other paths" ? model.requests.filter { sample in !model.paths.map(\.path).contains(sample.path) } : model.requests.filter { $0.path == path.path } }
    var body: some View {
        List {
            Section { StatCard(title: "Path", value: path.path, detail: "\(Int(path.requests)) requests · \(Int(path.errors4xx + path.errors5xx)) errors · \(path.averageMs.formatted()) ms", color: path.errors4xx + path.errors5xx > 0 ? HW.red : HW.teal) }
            if path.path.lowercased().contains("other") { Section { Text("This is a historical overflow bucket. Low-volume names that were already combined cannot be reconstructed. Current retained requests remain individually visible below.").foregroundStyle(HW.amber) } }
            Section("Retained requests") { ForEach(rows) { request in NavigationLink { RequestDetailView(request: request) } label: { RequestRow(request: request) } } }
        }.scrollContentBackground(.hidden).background(HW.background).navigationTitle("Path details")
    }
}

struct SourceDetailView: View {
    @EnvironmentObject private var model: AppModel
    let kind: String; let source: SourceMetric
    @State private var mode = "Requests"
    @State private var confirmCountry = false
    var matching: [RequestSample] { model.requests.filter { row in kind == "country" ? row.country == source.name : kind == "bot" ? row.bot == source.name : row.source == source.name } }
    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $mode) { Text("Requests").tag("Requests"); Text("Map").tag("Map"); Text("Flow").tag("Flow") }.pickerStyle(.segmented).padding()
            if mode == "Map" { RequestMap(requests: matching) }
            else if mode == "Flow" { TrafficFlowView(requests: matching, source: source.name) }
            else {
                List {
                    if kind == "source", source.name == "Direct" { Section { Text("Direct means no usable referrer or UTM source was sent. Destinations, IPs, locations and user agents below identify what the traffic actually did.").foregroundStyle(HW.amber) } }
                    Section("Destinations") { ForEach(destinationGroups, id: \.0) { item in NavigationLink { ErrorFilteredView(title: item.0, requests: matching.filter { $0.path == item.0 }) } label: { LabeledContent(item.0, value: item.1.formatted()) } } }
                    Section("Individual requests") { ForEach(matching) { row in NavigationLink { RequestDetailView(request: row) } label: { RequestRow(request: row) } } }
                }.scrollContentBackground(.hidden).background(HW.background)
            }
        }.background(HW.background).navigationTitle(source.name).navigationBarTitleDisplayMode(.inline)
        .toolbar { if kind == "country" { Button("Block", systemImage: "hand.raised", role: .destructive) { confirmCountry = true } } }
        .confirmationDialog("Block \(source.name)?", isPresented: $confirmCountry) { Button("Block country", role: .destructive) { Task { await model.block(site: model.selectedSite, kind: "country", value: matching.first?.countryCode ?? source.name) } } } message: { Text("This creates a scoped traffic policy for the selected site.") }
    }
    private var destinationGroups: [(String, Int)] { Dictionary(grouping: matching, by: \.path).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 } }
}

struct RequestMap: View {
    let requests: [RequestSample]
    @State private var position: MapCameraPosition = .automatic
    var body: some View {
        Map(position: $position) {
            ForEach(requests.filter { $0.latitude != nil && $0.longitude != nil }) { row in
                Annotation(row.city ?? row.country, coordinate: CLLocationCoordinate2D(latitude: row.latitude!, longitude: row.longitude!)) {
                    NavigationLink { RequestDetailView(request: row) } label: { Image(systemName: row.status >= 400 ? "exclamationmark.circle.fill" : "circle.fill").foregroundStyle(row.status >= 400 ? HW.red : HW.teal).padding(8).background(.ultraThinMaterial).clipShape(Circle()) }
                }
            }
        }.mapStyle(.standard(elevation: .realistic)).overlay(alignment: .bottom) { Text("Tap a point for complete request evidence").font(.caption).padding(9).background(.ultraThinMaterial).clipShape(Capsule()).padding() }
    }
}

struct TrafficFlowView: View {
    let requests: [RequestSample]; let source: String
    var destinations: [(String, Int)] { Dictionary(grouping: requests, by: \.host).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 } }
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                HW.background
                Canvas { context, size in
                    let start = CGPoint(x: size.width * 0.18, y: size.height * 0.5)
                    for (index, _) in destinations.enumerated() {
                        let y = size.height * (Double(index + 1) / Double(destinations.count + 1))
                        var path = Path(); path.move(to: start); path.addCurve(to: CGPoint(x: size.width * 0.82, y: y), control1: CGPoint(x: size.width * 0.45, y: start.y), control2: CGPoint(x: size.width * 0.56, y: y))
                        context.stroke(path, with: .color(index % 2 == 0 ? HW.teal : HW.amber), lineWidth: CGFloat(2 + min(8, destinations[index].1 / 3)))
                    }
                }
                Text(source).font(.headline).padding(12).background(HW.panelRaised).clipShape(Capsule()).position(x: proxy.size.width * 0.18, y: proxy.size.height * 0.5)
                ForEach(Array(destinations.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 2) { Text(item.0).font(.caption.bold()).lineLimit(1); Text("\(item.1) req").font(.caption2).foregroundStyle(HW.secondary) }.padding(9).background(HW.panelRaised).clipShape(RoundedRectangle(cornerRadius: 9)).position(x: proxy.size.width * 0.82, y: proxy.size.height * (Double(index + 1) / Double(destinations.count + 1)))
                }
            }
        }
    }
}
