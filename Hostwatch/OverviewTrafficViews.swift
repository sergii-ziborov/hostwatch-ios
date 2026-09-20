import MapKit
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    private let columns = [GridItem(.adaptive(minimum: 155), spacing: 12)]

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
                    Label((value.runtimeHealthy ?? value.dockerHealthy) ? "Runtime healthy" : "Runtime unavailable", systemImage: (value.runtimeHealthy ?? value.dockerHealthy) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
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
    @State private var ports: NetworkPorts?
    @State private var portError: String?

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
                    if kind == .network { networkPortsCard }
                    detailRows(overview)
                }
            }
            .padding(20)
        }
        .background(HW.background).navigationTitle(kind.rawValue).navigationBarTitleDisplayMode(.inline)
        .task(id: model.selectedNode) { if kind == .network { await loadPorts() } }
        .refreshable { if kind == .network { await loadPorts() } }
    }

    private var networkPortsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { VStack(alignment: .leading) { Eyebrow(text: "Live socket snapshot"); Text("Ports in use").font(.title3.bold()) }
                Spacer(); Button("Refresh") { Task { await loadPorts() } }.font(.footnote) }
            Text("Local service ports and remote destination ports. Counts are active sockets at one instant; the chart above shows bytes for the entire host interface.")
                .font(.footnote).foregroundStyle(HW.secondary)
            if let portError { Text(portError).font(.footnote).foregroundStyle(HW.red) }
            if let ports {
                Text("\(ports.tcpConnections) TCP · \(ports.udpConnections) UDP connected · \(ports.interface)")
                    .font(.caption).foregroundStyle(HW.secondary)
                if let error = ports.error { Text("Partial inventory: \(error)").font(.caption).foregroundStyle(HW.amber) }
                portRows("Local ports", ports.localPorts)
                portRows("Remote ports", ports.remotePorts)
            } else if portError == nil { ProgressView("Reading active sockets…") }
            Text("Per-port byte totals require a flow collector and are not inferred from these socket counts.")
                .font(.caption).foregroundStyle(HW.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).panel()
    }

    private func portRows(_ title: String, _ items: [NetworkPort]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
            if items.isEmpty { Text("No sockets observed.").foregroundStyle(HW.secondary) }
            ForEach(Array(items.prefix(30))) { item in
                HStack { Text("\(item.protocolName) :\(item.port)").font(.system(.subheadline, design: .monospaced))
                    if item.listening == true { Text("LISTEN").font(.caption2.bold()).foregroundStyle(HW.teal) }
                    Spacer(); Text("\(item.connections) sockets").font(.caption).foregroundStyle(HW.secondary) }
                Divider()
            }
            if items.count > 30 { Text("Showing 30 of \(items.count) ports").font(.caption).foregroundStyle(HW.secondary) }
        }
    }

    private func loadPorts() async {
        do { ports = try await model.networkPorts(); portError = nil }
        catch { portError = error.localizedDescription }
    }

    private func stats(_ value: Overview) -> [(String, String, String, Color)] {
        switch kind {
        case .cpu:
            [("Current", Format.percent(value.cpuPercent), "Across all cores", HW.teal), ("Load 1m", value.load1.formatted(.number.precision(.fractionLength(2))), "5m \(value.load5.formatted())", HW.amber), ("Health", value.cpuPercent > 85 ? "Critical" : "Healthy", "Alert threshold 85%", value.cpuPercent > 85 ? HW.red : HW.teal)]
        case .memory:
            [("Used", Format.bytes(value.memory.used), "of \(Format.bytes(value.memory.total))", HW.amber), ("Available", Format.bytes(value.memory.available), "Immediately reclaimable", HW.teal), ("Swap", Format.bytes(value.memory.swapUsed), "of \(Format.bytes(value.memory.swapTotal))", value.memory.swapUsed > 0 ? HW.amber : HW.teal)]
        case .network:
            [("Egress", Format.rate(value.network.txBytesPerSecond), "\(value.network.txPacketsPerSecond.formatted()) packets/s", HW.teal), ("Ingress", Format.rate(value.network.rxBytesPerSecond), "\(value.network.rxPacketsPerSecond.formatted()) packets/s", HW.teal), ("Sent counter", Format.bytes(value.network.txBytes), "Since interface reset or host boot", HW.amber), ("Received counter", Format.bytes(value.network.rxBytes), "Since interface reset or host boot", HW.amber)]
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
    private var samples: [(date: Date, point: SystemPoint)] {
        model.history.compactMap { point in ChartTime.parse(point.time).map { (date: $0, point: point) } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { VStack(alignment: .leading) { Eyebrow(text: "Last \(model.hours) hours"); Text(focus.map { "\($0.rawValue) history" } ?? "CPU & memory").font(.title3.bold()) }; Spacer(); Text("Host samples").font(.caption).foregroundStyle(HW.secondary) }
            if samples.isEmpty {
                EmptyState(icon: "chart.xyaxis.line", title: "No host history", detail: "Samples will appear after the collector records host metrics.")
            } else {
                HWLineChart(
                    dates: samples.map(\.date),
                    series: [
                        focus == nil || focus == .cpu ? HWSeries(id: "CPU", color: HW.teal, values: samples.map(\.point.cpuPercent)) : nil,
                        focus == nil || focus == .memory ? HWSeries(id: "Memory", color: HW.amber, values: samples.map { $0.point.memoryBytes / max(1, model.overview?.memory.total ?? 1) * 100 }) : nil,
                        focus == .network ? HWSeries(id: "Egress", color: HW.teal, values: samples.map { $0.point.txBytesPerSecond / 1024 }) : nil
                    ].compactMap { $0 },
                    yMax: focus == .network ? nil : 100,
                    height: 220
                )
                if let first = samples.first?.date, let last = samples.last?.date {
                    Text("Time · \(ChartTime.range(first, last))")
                        .font(.caption2).foregroundStyle(HW.secondary)
                }
                HStack(spacing: 14) {
                    if focus != .memory { Label(focus == .network ? "Egress KB/s" : "CPU %", systemImage: "line.diagonal").foregroundStyle(HW.teal) }
                    if focus == nil || focus == .memory { Label("Memory %", systemImage: "line.diagonal").foregroundStyle(HW.amber) }
                }.font(.caption)
            }
        }
        .padding(18).panel()
    }
}

struct DestinationRow: View {
    let group: DestinationGroup
    let requests: [RequestSample]
    var body: some View {
        HStack(spacing: 10) {
            NavigationLink {
                ErrorFilteredView(title: group.path, requests: requests.filter { $0.path == group.path })
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.path).font(.system(.body, design: .monospaced)).lineLimit(2)
                    Text("\(group.count.formatted()) requests").font(.caption).foregroundStyle(HW.secondary)
                }
            }
            Spacer(minLength: 6)
            if let url = group.url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(HW.teal)
                }
                .accessibilityLabel("Open \(group.path)")
            }
        }
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
                    Spacer(); Button("Rescan", systemImage: "arrow.clockwise") { Task { await model.scanStorage(refresh: true) } }.buttonStyle(.bordered).disabled(model.storageLoading)
                }
                if model.storageLoading { ProgressView("Scanning host storage… this can take up to a minute").tint(HW.teal).frame(maxWidth: .infinity, alignment: .leading) }
                if let error = model.storageError {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Disk scan failed", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(HW.red)
                        Text(error).font(.footnote).foregroundStyle(HW.secondary).textSelection(.enabled)
                        Button("Retry scan") { Task { await model.scanStorage() } }.buttonStyle(.bordered)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panel()
                }
                if let storage = model.storage {
                    let ratio = storage.disk.total > 0 ? storage.disk.used / storage.disk.total : 0
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) { Text(Format.bytes(storage.disk.used)).font(.largeTitle.bold()); Text("used").foregroundStyle(HW.secondary); Spacer(); Text("\(Format.bytes(storage.disk.free)) free").foregroundStyle(HW.secondary) }
                        ProgressView(value: ratio).tint(ratio > 0.9 ? HW.red : ratio > 0.75 ? HW.amber : HW.teal)
                        Text(ratio > 0.9 ? "Critical · less than 10% free" : ratio > 0.75 ? "Watch · disk is over 75% full" : "Healthy · capacity available")
                            .font(.footnote.weight(.semibold)).foregroundStyle(ratio > 0.9 ? HW.red : ratio > 0.75 ? HW.amber : HW.teal)
                    }.padding(18).panel()

                    Picker("Breakdown", selection: $tab) { Text("Sites").tag("Sites"); Text("Types").tag("Types"); Text("Paths").tag("Paths"); Text("Reclaim").tag("Reclaim") }.pickerStyle(.segmented)
                    if tab == "Sites" { groupList(storage.sites, hostBytes: storage.unattributedBytes) }
                    else if tab == "Types" { groupList(storage.categories, hostBytes: 0) }
                    else if tab == "Reclaim" { ReclaimAdviceList(advice: storage.advice ?? ReclaimPolicy.advise(storage.entries)) }
                    else { entryList(storage.entries) }
                    NavigationLink { CleanupView() } label: { Label("Safe cleanup · preview cached files", systemImage: "sparkles.rectangle.stack") }
                        .buttonStyle(.bordered)
                } else {
                    if !model.storageLoading {
                        EmptyState(icon: "internaldrive", title: model.storageError == nil ? "Disk scan not loaded" : "Unable to load disk details", detail: "Scan the host to attribute project, container, database, media and operating-system usage.")
                        Button("Scan disk") { Task { await model.scanStorage() } }.buttonStyle(.borderedProminent)
                    }
                }
            }.padding(20)
        }
        .background(HW.background).navigationTitle("Disk").navigationBarTitleDisplayMode(.inline)
        .task { if model.storage == nil { await model.scanStorage() } }
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
                    HStack { Image(systemName: entry.kind == "file" ? "doc" : "folder").foregroundStyle(HW.teal); VStack(alignment: .leading) { Text(entry.path).font(.hw(.subheadline, design: .monospaced, weight: .semibold)).lineLimit(2); Text("\(entry.siteName ?? "Host & shared") · \(entry.category)").font(.caption).foregroundStyle(HW.secondary) }; Spacer(); Text(Format.bytes(entry.bytes)).font(.subheadline.bold()) }
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
            .hwHiddenScrollBackground().background(HW.background).navigationTitle(group.name)
    }
}

struct StoragePathDetail: View {
    @EnvironmentObject private var model: AppModel
    let entry: StorageEntry
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow(text: entry.kind); Text(entry.path).font(.hw(.title2, design: .monospaced, weight: .bold)).textSelection(.enabled)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                    StatCard(title: "Size", value: Format.bytes(entry.bytes), icon: "internaldrive")
                    StatCard(title: "Owner", value: entry.siteName ?? "Host & shared", detail: entry.siteId ?? "Operating system, containers or shared data", color: HW.amber, icon: "person.crop.square")
                    StatCard(title: "Type", value: entry.category, detail: entry.kind, icon: "folder")
                    let reclaim = (model.storage?.advice ?? ReclaimPolicy.advise([entry])).first { $0.path == entry.path } ?? ReclaimPolicy.advise([entry])[0]
                    StatCard(title: "Reclaim", value: reclaim.className.capitalized, detail: reclaim.reason, color: ReclaimPolicy.color(for: reclaim.className), icon: "trash.slash")
                }
                if entry.direct != true {
                    Button("Open directory contents", systemImage: "folder.badge.gearshape") { Task { await model.browseStorage(path: entry.category == "Unclassified host space" ? "unclassified:\(entry.path)" : entry.path) } }
                        .buttonStyle(.borderedProminent).disabled(model.storageLoading)
                } else { Text("This is a direct file; there are no deeper directories.").font(.footnote).foregroundStyle(HW.secondary) }
                if model.storageLoading { ProgressView("Inspecting directory…") }
                if let error = model.storageError { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(HW.red).font(.footnote) }
                if let storage = model.storageBrowse, storage.path == entry.path {
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
    private var historicalErrors: Int {
        Int(model.traffic.reduce(0) { $0 + $1.errors4xx + $1.errors5xx })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TrafficChart()
            InternalTrafficSection()
            TrafficMapCard(requests: model.requests)
            HStack(spacing: 12) {
                NavigationLink { RequestExplorerView() } label: { StatCard(title: "Retained requests", value: model.requests.count.formatted(), detail: "IP, location, destination and full trace", icon: "list.bullet.rectangle") }
                NavigationLink { ErrorsView() } label: { StatCard(title: "Errors", value: historicalErrors.formatted(), detail: "By project · logs and previous matches", color: HW.red, icon: "exclamationmark.triangle") }
            }
            .buttonStyle(.plain)
            AttributionGrid()
        }
    }
}

struct TrafficChart: View {
    @EnvironmentObject private var model: AppModel
    private var samples: [(date: Date, point: TrafficPoint)] {
        model.traffic.compactMap { point in ChartTime.parse(point.time).map { (date: $0, point: point) } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { VStack(alignment: .leading) { Eyebrow(text: "Nginx HTTP · last \(model.hours)h"); Text("Request volume").font(.title2.bold()); Text("Each point counts HTTP requests received by Nginx in five minutes, including internal calls. This is not host-wide network RPS.").font(.caption).foregroundStyle(HW.secondary) }; Spacer(); Text(model.traffic.reduce(0) { $0 + Int($1.requests) }.formatted()).font(.title3.bold()) }
            if samples.isEmpty {
                EmptyState(icon: "chart.xyaxis.line", title: "No traffic history", detail: "Request samples will appear after the collector records HTTP traffic.")
            } else {
            HWLineChart(
                dates: samples.map(\.date),
                series: [
                    HWSeries(id: "Requests", color: HW.teal, values: samples.map(\.point.requests), filled: true),
                    HWSeries(id: "Errors", color: HW.amber, values: samples.map { $0.point.errors4xx + $0.point.errors5xx })
                ],
                height: 280
            )
            if let first = samples.first?.date, let last = samples.last?.date {
                Text("Time · \(ChartTime.range(first, last))")
                    .font(.caption2).foregroundStyle(HW.secondary)
            }
            HStack(spacing: 14) {
                Label("Requests / 5 min", systemImage: "line.diagonal").foregroundStyle(HW.teal)
                Label("Errors / 5 min", systemImage: "line.diagonal").foregroundStyle(HW.amber)
            }.font(.caption)
            }
        }.padding(18).panel()
    }
}

struct AttributionGrid: View {
    @EnvironmentObject private var model: AppModel
    let columns = [GridItem(.adaptive(minimum: 245), spacing: 12)]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "HTTP attribution"); Text("Referrers, not callers").font(.title2.bold())
            Text("These names are Referer/UTM campaigns. They do not say whether the caller is a public client or one of our services. Origin is the split above: External vs Our services. “Direct” only means no usable referrer was sent.")
                .font(.caption).foregroundStyle(HW.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                metricGroup("Referrers & campaigns", items: model.sources.sources, kind: "source")
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
                        HStack { Text(item.name).lineLimit(1); Spacer(); Text(item.requests.formatted(.number.precision(.fractionLength(0)))).font(.body.weight(.bold)); Image(systemName: "chevron.right").font(.caption).foregroundStyle(HW.secondary) }
                        ProgressView(value: item.requests, total: max(1, items.first?.requests ?? 1)).tint(HW.teal)
                        HStack { Text(Format.bytes(item.bytes)); Spacer(); Text("Inspect destinations & requests") }.font(.caption2).foregroundStyle(HW.secondary)
                    }
                }.buttonStyle(.plain)
            }
        }.padding(16).frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading).panel()
    }
}

struct InternalTrafficSection: View {
    @EnvironmentObject private var model: AppModel
    private var classified: Int { Int(model.sources.classifiedRequests ?? 0) }
    private var total: Int { Int(model.sources.totalRequests ?? Double(model.traffic.reduce(0) { $0 + Int($1.requests) })) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Where traffic comes from")
            Text("External clients vs our services").font(.title2.bold())
            HStack(spacing: 10) {
                StatCard(title: "External clients", value: Int(model.sources.externalRequests ?? 0).formatted(), detail: "Public internet · not our services", icon: "globe")
                StatCard(title: "Our services", value: Int(model.sources.internalRequests ?? 0).formatted(), detail: "Private IP matched to a container", color: HW.amber, icon: "point.3.connected.trianglepath.dotted")
            }
            if total > classified {
                Text("\((total - classified).formatted()) older Nginx requests have no internal/external classification. Service identity was not recorded then.")
                    .font(.caption).foregroundStyle(HW.amber)
            }
            Text("Counts are Nginx HTTP entries for the selected window. Host network traffic and calls that bypass Nginx are separate; divide an interval count by 300 for its average requests/second.")
                .font(.caption).foregroundStyle(HW.secondary)
            if (model.sources.internalRoutes ?? []).isEmpty {
                Text(classified == 0 ? "Internal service routes will appear after the upgraded collector receives requests." : "No internal calls reached Nginx in the classified interval.")
                    .font(.caption).foregroundStyle(HW.secondary)
            } else {
                ForEach(model.sources.internalRoutes ?? []) { route in
                    NavigationLink { InternalRouteDetail(route: route) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                OriginBadge(origin: .ourService)
                                Text(route.caller).font(.subheadline.bold())
                                Spacer()
                                Text(Int(route.requests).formatted()).font(.body.weight(.bold))
                            }
                            Text("Our service → \(route.destinationHost)\(route.targetService.map { " · upstream \($0)" } ?? " · upstream unverified")")
                                .font(.caption).foregroundStyle(HW.secondary)
                            Text("\(Format.bytes(route.bytes)) · inspect retained requests →")
                                .font(.caption2).foregroundStyle(HW.teal)
                        }.padding(12).panel()
                    }.buttonStyle(.plain)
                }
            }
        }.padding(16).panel()
    }
}

struct InternalRouteDetail: View {
    @EnvironmentObject private var model: AppModel
    let route: InternalRoute
    private var matching: [RequestSample] {
        model.requests.filter { row in
            row.internalRequest == true && (row.clientService ?? "Unidentified private peer") == route.caller &&
            row.host.lowercased() == route.destinationHost && (row.targetService ?? "") == (route.targetService ?? "")
        }
    }
    var body: some View {
        List {
            Section("Observed at Nginx") {
                HWLabeled("Caller", value: route.caller)
                HWLabeled("Requested host", value: route.destinationHost)
                HWLabeled("Upstream container", value: route.targetService ?? "Not identified from upstream address")
                HWLabeled("Requests", value: Int(route.requests).formatted())
                HWLabeled("Response bytes", value: Format.bytes(route.bytes))
            }
            Section("Evidence") {
                Text("A Docker service is named only when the log IP uniquely matches a running container. Nginx does not observe direct container-to-container calls. Older or expired individual requests cannot be reconstructed.")
                    .font(.footnote).foregroundStyle(HW.secondary)
                PagedRows(items: matching) { request in NavigationLink { RequestDetailView(request: request) } label: { RequestRow(request: request) } }
                if matching.isEmpty { Text("No matching individual request remains in the bounded live buffer.").foregroundStyle(HW.secondary) }
            }
        }.hwHiddenScrollBackground().background(HW.background).navigationTitle(route.caller)
    }
}

struct RequestExplorerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var status = "All"
    @State private var origin = "All"
    private var filtered: [RequestSample] {
        model.requests.filter { row in
            (query.isEmpty || [row.path, row.clientIp, row.country, row.host, row.source, row.clientService ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(query)) &&
            (status == "All" || (status == "Errors" ? row.status >= 400 : row.status < 400)) &&
            (origin == "All" || (origin == "Our services" ? row.origin == .ourService : row.origin == .external))
        }
    }
    var body: some View {
        List {
            Section {
                TextField("Search IP, path, host, country, service…", text: $query)
                Picker("Status", selection: $status) { Text("All").tag("All"); Text("Successful").tag("Successful"); Text("Errors").tag("Errors") }.pickerStyle(.segmented)
                Picker("Origin", selection: $origin) { Text("All").tag("All"); Text("External").tag("External"); Text("Our services").tag("Our services") }.pickerStyle(.segmented)
            }
            Section("\(filtered.count) retained requests") {
                PagedRows(items: filtered) { request in NavigationLink { RequestDetailView(request: request) } label: { RequestRow(request: request) } }
            }
        }.hwHiddenScrollBackground().background(HW.background).navigationTitle("Requests")
    }
}

struct OriginBadge: View {
    let origin: TrafficOrigin
    var body: some View {
        Text(origin.badge)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(origin == .ourService ? HW.amber : HW.teal)
            .background((origin == .ourService ? HW.amber : HW.teal).opacity(0.16))
            .clipShape(Capsule())
    }
}

struct RequestRow: View {
    let request: RequestSample
    private var unparsed: Bool { request.method == "UNKNOWN" && !RequestEvidence.usableHost(request.host) }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                OriginBadge(origin: request.origin)
                Text(unparsed ? "UNPARSED" : request.method).font(.caption.bold()).foregroundStyle(unparsed ? HW.amber : HW.teal)
                Text(unparsed ? "Request target unavailable" : request.path).font(.hw(.body, design: .monospaced, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(String(request.status)).font(.body.weight(.bold)).foregroundStyle(request.status >= 400 ? HW.red : HW.teal)
            }
            Text("\(request.origin.title): \(request.origin.sourceLabel(for: request)) → \(unparsed ? "Unmapped host" : request.host) · \(request.durationMs.formatted()) ms").font(.caption).foregroundStyle(HW.secondary).lineLimit(1)
        }.padding(.vertical, 5)
    }
}

struct RequestDetailView: View {
    @EnvironmentObject private var model: AppModel
    let request: RequestSample
    @State private var confirmBlock = false
    @State private var context: ErrorContext?
    private var mappedSite: Site? { model.sites.first { $0.id == request.site } }
    private var hasObservedHost: Bool { RequestEvidence.usableHost(request.host) }
    private var observedPath: String {
        request.method == "UNKNOWN" && !hasObservedHost && request.path == "/"
            ? "Not recorded (older collector used / as fallback)" : request.path
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow(text: "Individual HTTP request")
                Text(request.method == "UNKNOWN" ? "Unparsed HTTP request" : "\(request.method) \(request.path)")
                    .font(.hw(.title2, design: .rounded, weight: .bold)).textSelection(.enabled)
                Text("\(ChartTime.parse(request.time)?.formatted(date: .abbreviated, time: .standard) ?? request.time) · \(hasObservedHost ? request.host : "unmapped host")")
                    .foregroundStyle(HW.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210))], spacing: 12) {
                    StatCard(title: "Origin", value: request.origin.title, detail: "\(request.origin.detail) · \(request.origin.sourceLabel(for: request))", color: request.origin == .ourService ? HW.amber : HW.teal, icon: request.origin == .ourService ? "point.3.connected.trianglepath.dotted" : "globe")
                    StatCard(title: "Response", value: "\(request.status) \(HTTPURLResponse.localizedString(forStatusCode: request.status).capitalized)", detail: "\(request.durationMs.formatted()) ms · \(Format.bytes(request.bytes))", color: request.status >= 400 ? HW.red : HW.teal, icon: "arrow.left.arrow.right")
                    StatCard(title: "Client", value: request.clientIp, detail: "\(request.city ?? "Unknown"), \(request.country)", icon: "network")
                    if request.origin == .ourService { StatCard(title: "Calling service", value: request.clientService ?? "Unknown private peer", detail: "Docker IP match when available", color: HW.amber, icon: "point.3.connected.trianglepath.dotted") }
                    StatCard(title: "Referrer", value: request.source, detail: request.referrerPath ?? "Campaign / Referer — not the calling service", color: HW.amber, icon: "arrow.triangle.branch")
                    StatCard(title: "Agent", value: request.bot ?? "Browser / service", detail: request.userAgent, icon: "person.text.rectangle")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(request.status >= 400 ? "What this error tells us" : "Observed destination")
                        .font(.headline)
                    Text(RequestEvidence.diagnosis(status: request.status, host: request.host, method: request.method, path: request.path, upstream: request.upstreamAddr))
                        .font(.subheadline).foregroundStyle(request.status >= 400 ? HW.amber : HW.secondary)
                    Text("Project: \(siteName) · target: \(observedPath) · upstream: \(request.upstreamAddr.flatMap { $0 == "-" ? nil : $0 } ?? "not recorded")")
                        .font(.caption.monospaced()).foregroundStyle(HW.secondary).textSelection(.enabled)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panel()
                if request.status >= 400 { RequestErrorContextCard(context: context) }
                trace
                if let destinationURL {
                    Link(destination: destinationURL) { Label("Open destination in browser", systemImage: "arrow.up.right.square") }
                        .buttonStyle(.bordered)
                    Text("Opens outside Hostwatch. Query strings are not retained, and a fresh response may differ from the recorded request.")
                        .font(.caption).foregroundStyle(HW.secondary)
                }
                if mappedSite == nil {
                    Label("This request is not mapped to a project, so a project-scoped IP rule cannot be created here.", systemImage: "questionmark.shield")
                        .font(.footnote).foregroundStyle(HW.amber)
                } else if IPAddressSafety.isInternal(request.clientIp) || request.internalRequest == true {
                    Label("Internal service address · blocking it may interrupt your applications", systemImage: "exclamationmark.shield")
                        .font(.footnote).foregroundStyle(HW.amber)
                } else {
                    Button("Block this IP for \(siteName)", systemImage: "hand.raised.fill", role: .destructive) { confirmBlock = true }.buttonStyle(.borderedProminent).tint(HW.red)
                }
            }.padding(20)
        }.background(HW.background).navigationTitle("Request").navigationBarTitleDisplayMode(.inline)
        .task { if request.status >= 400 { context = await model.errorContext(for: request) } }
        .confirmationDialog("Block \(request.clientIp)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block IP", role: .destructive) { Task { await model.block(site: request.site, kind: "ip", value: request.clientIp) } }
        } message: { Text("A project-scoped access rule will be applied to \(siteName).") }
    }
    private var siteName: String { mappedSite?.name ?? "Unmapped traffic" }
    private var destinationURL: URL? { RequestEvidence.destinationURL(for: request) }
    private var trace: some View {
        VStack(spacing: 0) {
            traceRow("Request ID", request.id)
            traceRow("Project", siteName)
            if request.internalRequest == true { traceRow("Calling service", request.clientService ?? "Unidentified private peer") }
            traceRow("Upstream service", request.targetService ?? "Not identified")
            traceRow("Destination", hasObservedHost && request.path.hasPrefix("/") ? "\(request.scheme ?? "https")://\(request.host)\(request.path)" : "Unmapped · target \(observedPath)")
            traceRow("Recorded Host", hasObservedHost ? request.host : "\(request.host.isEmpty ? "Missing" : request.host) · fallback / unmapped")
            traceRow("HTTP status", "\(request.status) \(HTTPURLResponse.localizedString(forStatusCode: request.status).capitalized)")
            traceRow("Protocol", [request.protocolName, request.tlsProtocol, request.tlsCipher].compactMap { $0 }.joined(separator: " · "))
            traceRow("Upstream", [request.upstreamAddr, request.upstreamStatus, request.upstreamMs.map { "\($0.formatted()) ms" }].compactMap { $0 }.joined(separator: " · "))
            traceRow("Cache", request.cacheStatus ?? "Not reported"); traceRow("Request bytes", request.requestBytes.map(Format.bytes) ?? "Not reported")
            traceRow("Response bytes sent", Format.bytes(request.bytes))
            traceRow("User agent", request.userAgent)
        }.padding(.horizontal, 16).panel()
    }
    private func traceRow(_ title: String, _ value: String) -> some View { HStack(alignment: .top) { Text(title).foregroundStyle(HW.secondary); Spacer(); Text(value.isEmpty ? "Not reported" : value).font(.system(.caption, design: .monospaced)).multilineTextAlignment(.trailing).textSelection(.enabled) }.padding(.vertical, 12).overlay(alignment: .bottom) { Divider().overlay(HW.border) } }
}

struct ErrorExplorerView: View {
    @EnvironmentObject private var model: AppModel
    private var errors: [RequestSample] { model.errorEvidence?.requests.filter { $0.status >= 400 } ?? [] }
    private var statuses: [(String, Double)] { dimensions(\.errorStatuses, fallback: Dictionary(grouping: errors, by: { String($0.status) }).mapValues { Double($0.count) }) }
    private var methods: [(String, Double)] { dimensions(\.errorMethods, fallback: Dictionary(grouping: errors, by: \.method).mapValues { Double($0.count) }) }
    private var aggregateErrors: Double { model.paths.reduce(0) { $0 + $1.errors4xx + $1.errors5xx } }
    private var clientErrors: Int { Int(model.paths.isEmpty ? Double(errors.filter { (400..<500).contains($0.status) }.count) : model.paths.reduce(0) { $0 + $1.errors4xx }) }
    private var serverErrors: Int { Int(model.paths.isEmpty ? Double(errors.filter { $0.status >= 500 }.count) : model.paths.reduce(0) { $0 + $1.errors5xx }) }

    private func dimensions(_ keyPath: KeyPath<RequestPath, [String: Double]?>, fallback: [String: Double]) -> [(String, Double)] {
        var totals: [String: Double] = [:]
        for path in model.paths {
            for (key, count) in path[keyPath: keyPath] ?? [:] { totals[key, default: 0] += count }
        }
        return (totals.isEmpty ? fallback : totals).map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }
    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 10) {
                    StatCard(title: "Retained errors", value: errors.count.formatted(), detail: model.errorEvidence?.capped == true ? "Buffer limit reached" : "Bounded live buffer", color: HW.red)
                    StatCard(title: "Client", value: clientErrors.formatted(), detail: "Historical HTTP 4xx", color: HW.red)
                    StatCard(title: "Server", value: serverErrors.formatted(), detail: "Historical HTTP 5xx", color: HW.red)
                }.listRowInsets(EdgeInsets())
            }
            if aggregateErrors > 0 { Section { HWLabeled("Historical errors", value: Int(aggregateErrors).formatted()); Text("Exact status and method coverage may be partial; older requests cannot be reconstructed.").font(.caption).foregroundStyle(HW.secondary) } }
            Section("Response status") { ForEach(statuses, id: \.0) { item in NavigationLink { ErrorAggregateDetailView(kind: "status", value: item.0, count: item.1) } label: { HWLabeled("HTTP \(item.0)", value: Int(item.1).formatted()) } } }
            Section("Methods") { ForEach(methods, id: \.0) { item in NavigationLink { ErrorAggregateDetailView(kind: "method", value: item.0, count: item.1) } label: { HWLabeled(item.0, value: Int(item.1).formatted()) } } }
            Section("Affected paths") {
                ForEach(model.paths.filter { $0.errors4xx + $0.errors5xx > 0 }) { path in NavigationLink { PathDetailView(path: path) } label: { VStack(alignment: .leading) { HStack { Text(path.path).font(.system(.body, design: .monospaced)); Spacer(); Text("\(Int(path.errors4xx + path.errors5xx)) errors").foregroundStyle(HW.red) }; Text("\(Int(path.requests)) requests · \(path.averageMs.formatted()) ms average").font(.caption).foregroundStyle(HW.secondary) } } }
            }
            if errors.isEmpty { Section { EmptyState(icon: "clock.badge.questionmark", title: "No retained error requests", detail: "Historical aggregates remain valid, but old individual URLs and IPs cannot be reconstructed. New requests appear here as the bounded buffer fills.") } }
        }.hwHiddenScrollBackground().background(HW.background).navigationTitle("Errors")
    }
}

struct ErrorAggregateDetailView: View {
    @EnvironmentObject private var model: AppModel
    let kind: String
    let value: String
    let count: Double

    private var paths: [RequestPath] {
        model.paths.filter { path in
            ((kind == "status" ? path.errorStatuses : path.errorMethods)?[value] ?? 0) > 0
        }
    }

    private var retained: [RequestSample] {
        model.errorEvidence?.requests.filter { request in
            request.status >= 400 && (kind == "status" ? String(request.status) == value : request.method == value)
        } ?? []
    }

    var body: some View {
        List {
            Section {
                HWLabeled("Exact-code evidence", value: Int(count).formatted())
                Text("These counts cover only intervals collected with this dimension. Individual requests below come from the bounded live buffer.")
                    .font(.footnote).foregroundStyle(HW.secondary)
            }
            Section("Affected URL paths") {
                ForEach(paths) { path in
                    NavigationLink { PathDetailView(path: path) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(path.path).font(.system(.subheadline, design: .monospaced)).lineLimit(2)
                            Text("\(Int((kind == "status" ? path.errorStatuses : path.errorMethods)?[value] ?? 0)) matching errors · \(Int(path.requests)) requests")
                                .font(.caption).foregroundStyle(HW.secondary)
                        }
                    }
                }
                if paths.isEmpty { Text("The retained sample has no matching historical path aggregate.").foregroundStyle(HW.secondary) }
            }
            Section("Retained requests · \(retained.count)") {
                PagedRows(items: retained) { request in NavigationLink { RequestDetailView(request: request) } label: { RequestRow(request: request) } }
                if retained.isEmpty { Text("No individual request remains in the live buffer.").foregroundStyle(HW.secondary) }
            }
        }
        .hwHiddenScrollBackground()
        .background(HW.background)
        .navigationTitle(kind == "status" ? "HTTP \(value)" : value)
    }
}

struct ErrorFilteredView: View {
    let title: String; let requests: [RequestSample]
    private var openURL: URL? { requests.compactMap(RequestEvidence.destinationURL(for:)).first }
    var body: some View {
        List {
            Section("\(requests.count) retained requests") {
                PagedRows(items: requests) { request in NavigationLink { RequestDetailView(request: request) } label: { RequestRow(request: request) } }
                if requests.isEmpty { Text("No matching individual request remains in the live buffer.").foregroundStyle(HW.secondary) }
            }
        }
        .hwHiddenScrollBackground().background(HW.background).navigationTitle(title)
        .toolbar {
            if let openURL {
                Link(destination: openURL) { Image(systemName: "arrow.up.right.square") }
                    .accessibilityLabel("Open destination")
            }
        }
    }
}

struct PathDetailView: View {
    @EnvironmentObject private var model: AppModel
    let path: RequestPath
    var rows: [RequestSample] { path.path == "Other paths" ? model.requests.filter { sample in !model.paths.map(\.path).contains(sample.path) } : model.requests.filter { $0.path == path.path } }
    var body: some View {
        List {
            Section { StatCard(title: "Path", value: path.path, detail: "\(Int(path.requests)) requests · \(Int(path.errors4xx + path.errors5xx)) errors · \(path.averageMs.formatted()) ms", color: path.errors4xx + path.errors5xx > 0 ? HW.red : HW.teal) }
            if path.path.lowercased().contains("other") { Section { Text("This is a historical overflow bucket. Low-volume names that were already combined cannot be reconstructed. Current retained requests remain individually visible below.").foregroundStyle(HW.amber) } }
            if let statuses = path.errorStatuses, !statuses.isEmpty {
                Section("HTTP error codes") {
                    ForEach(statuses.sorted(by: { $0.value > $1.value }), id: \.key) { item in
                        NavigationLink { PathErrorDimensionView(path: path, kind: "status", value: item.key, count: item.value, requests: rows.filter { String($0.status) == item.key }) } label: {
                            HWLabeled("HTTP \(item.key) · \(HTTPURLResponse.localizedString(forStatusCode: Int(item.key) ?? 0).capitalized)", value: Int(item.value).formatted())
                        }
                    }
                }
            }
            if let methods = path.errorMethods, !methods.isEmpty {
                Section("Methods that failed") {
                    ForEach(methods.sorted(by: { $0.value > $1.value }), id: \.key) { item in
                        NavigationLink { PathErrorDimensionView(path: path, kind: "method", value: item.key, count: item.value, requests: rows.filter { $0.method == item.key && $0.status >= 400 }) } label: {
                            HWLabeled(item.key, value: Int(item.value).formatted())
                        }
                    }
                }
            }
            Section("Retained requests") { PagedRows(items: rows) { request in NavigationLink { RequestDetailView(request: request) } label: { RequestRow(request: request) } } }
        }.hwHiddenScrollBackground().background(HW.background).navigationTitle("Path details")
    }
}

struct PathErrorDimensionView: View {
    let path: RequestPath
    let kind: String
    let value: String
    let count: Double
    let requests: [RequestSample]

    var body: some View {
        List {
            Section("Historical aggregate") {
                HWLabeled("Path", value: path.path)
                HWLabeled(kind == "status" ? "HTTP status" : "Method", value: value)
                HWLabeled("Matching errors", value: Int(count).formatted())
                Text("The aggregate is complete for the recorded dimension. Individual requests may have expired from the bounded live buffer.")
                    .font(.footnote).foregroundStyle(HW.secondary)
            }
            Section("Retained evidence · \(requests.count)") {
                PagedRows(items: requests) { request in NavigationLink { RequestDetailView(request: request) } label: { RequestRow(request: request) } }
                if requests.isEmpty { Text("No matching individual request remains in memory.").foregroundStyle(HW.secondary) }
            }
        }
        .hwHiddenScrollBackground()
        .background(HW.background)
        .navigationTitle(kind == "status" ? "HTTP \(value)" : value)
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
                    Section("Selected window") {
                        HWLabeled("Requests", value: Int(source.requests).formatted())
                        HWLabeled("Transfer", value: Format.bytes(source.bytes))
                        HWLabeled("Retained requests", value: matching.count.formatted())
                        HWLabeled("External clients", value: matching.filter { $0.origin == .external }.count.formatted())
                        HWLabeled("Our services", value: matching.filter { $0.origin == .ourService }.count.formatted())
                    }
                    if kind == "source", source.name == "Direct" { Section { Text("Direct means no usable referrer or UTM source was sent. Destinations, IPs, locations and user agents below identify what the traffic actually did.").foregroundStyle(HW.amber) } }
                    if kind == "country", model.selectedSite.isEmpty { Section { Text("Choose a site in the traffic scope before blocking a country. Country rules always apply to one project.").foregroundStyle(HW.amber) } }
                    if matching.isEmpty { Section { Text("The historical count is available, but no matching individual request remains in the bounded live buffer. Exact destinations and client IPs cannot be reconstructed for older traffic.").foregroundStyle(HW.amber) } }
                    Section("Destinations · \(destinationGroups.count)") {
                        PagedRows(items: destinationGroups) { group in
                            DestinationRow(group: group, requests: matching)
                        }
                    }
                    Section("Individual requests") { PagedRows(items: matching) { row in NavigationLink { RequestDetailView(request: row) } label: { RequestRow(request: row) } } }
                }.hwHiddenScrollBackground().background(HW.background)
            }
        }.background(HW.background).navigationTitle(source.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if kind == "country" {
                Button("Block", systemImage: "hand.raised", role: .destructive) { confirmCountry = true }
                    .disabled(model.selectedSite.isEmpty || matching.first?.countryCode.isEmpty != false)
            }
        }
        .confirmationDialog("Block \(source.name)?", isPresented: $confirmCountry) { Button("Block country", role: .destructive) { Task { await model.block(site: model.selectedSite, kind: "country", value: matching.first?.countryCode ?? source.name) } } } message: { Text("This creates a scoped traffic policy for the selected site.") }
    }
    private var destinationGroups: [DestinationGroup] { DestinationGroup.groups(from: matching) }
}

struct TrafficMapCard: View {
    let requests: [RequestSample]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Visitor map")
            Text("Where external clients come from").font(.title2.bold())
            RequestMap(requests: requests)
        }
        .padding(16)
        .panel()
    }
}

struct RequestMap: View {
    let requests: [RequestSample]
    @State private var selected: RequestSample?
    private var pins: [GeoPin] { GeoPlace.pins(from: requests) }
    private var located: Int { pins.reduce(0) { $0 + $1.count } }
    private var ours: Int { requests.filter { $0.origin == .ourService }.count }
    private var unknown: Int { max(0, requests.count - located - ours) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if pins.isEmpty {
                EmptyState(
                    icon: "map",
                    title: locatedTitle,
                    detail: emptyDetail
                )
                .frame(minHeight: 160)
            } else {
                RequestMapCanvas(pins: pins) { selected = $0 }
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Text("\(located.formatted()) located · \(ours.formatted()) our services · \(unknown.formatted()) no geo")
                .font(.caption)
                .foregroundStyle(HW.secondary)
        }
        .sheet(item: $selected) { request in
            HWStackNavigation { RequestDetailView(request: request) }
        }
    }

    private var locatedTitle: String {
        if requests.isEmpty { return "No retained requests" }
        if ours == requests.count { return "0 located · only our services" }
        return "0 located requests"
    }

    private var emptyDetail: String {
        if requests.isEmpty {
            return "Visitor coordinates appear after Nginx keeps a public client IP."
        }
        if ours == requests.count {
            return "These calls are our services. They have private addresses and are not placed on the visitor map."
        }
        return "Retained requests have no usable city coordinates yet. Country-only traffic is placed at the country center when the code is known."
    }
}

struct TrafficFlowView: View {
    let requests: [RequestSample]; let source: String
    var destinations: [(String, Int)] { Array(Dictionary(grouping: requests, by: \.host).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }.prefix(16)) }
    private var ourCount: Int { requests.filter { $0.origin == .ourService }.count }
    private var externalCount: Int { requests.count - ourCount }
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                HW.background
                Canvas { context, size in
                    let start = CGPoint(x: size.width * 0.18, y: size.height * 0.5)
                    for (index, dest) in destinations.enumerated() {
                        let y = size.height * (Double(index + 1) / Double(destinations.count + 1))
                        var path = Path(); path.move(to: start); path.addCurve(to: CGPoint(x: size.width * 0.82, y: y), control1: CGPoint(x: size.width * 0.45, y: start.y), control2: CGPoint(x: size.width * 0.56, y: y))
                        context.stroke(path, with: .color(lineColor(for: dest.0)), lineWidth: CGFloat(2 + min(8, dest.1 / 3)))
                    }
                }
                VStack(spacing: 4) {
                    Text(source).font(.headline)
                    Text(originCaption).font(.caption2).foregroundStyle(HW.secondary)
                }.padding(12).background(HW.panelRaised).clipShape(RoundedRectangle(cornerRadius: 12)).position(x: proxy.size.width * 0.18, y: proxy.size.height * 0.5)
                ForEach(Array(destinations.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 2) {
                        Text(item.0).font(.caption.bold()).lineLimit(1)
                        Text("\(item.1) req · \(lineCaption(for: item.0))").font(.caption2).foregroundStyle(HW.secondary)
                    }.padding(9).background(HW.panelRaised).clipShape(RoundedRectangle(cornerRadius: 9)).position(x: proxy.size.width * 0.82, y: proxy.size.height * (Double(index + 1) / Double(destinations.count + 1)))
                }
            }
        }
    }

    private var originCaption: String {
        if ourCount == 0 { return "External clients" }
        if externalCount == 0 { return "Our services" }
        return "External \(externalCount) · Our \(ourCount)"
    }

    private func rows(for host: String) -> [RequestSample] { requests.filter { $0.host == host } }

    private func lineColor(for host: String) -> Color {
        let items = rows(for: host)
        let ours = items.contains { $0.origin == .ourService }
        let external = items.contains { $0.origin == .external }
        if ours && !external { return HW.amber }
        if external && !ours { return HW.teal }
        return Color(red: 0.71, green: 0.55, blue: 1)
    }

    private func lineCaption(for host: String) -> String {
        let items = rows(for: host)
        let ours = items.contains { $0.origin == .ourService }
        let external = items.contains { $0.origin == .external }
        if ours && !external { return "our" }
        if external && !ours { return "ext" }
        return "mixed"
    }
}
