import SwiftUI

struct IncidentsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab = "Incidents"
    var vulnerabilities: [(ProjectHealth, Vulnerability)] { model.projects.flatMap { project in (project.vulnerabilities ?? []).map { (project, $0) } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Issue type", selection: $tab) { Text("Incidents").tag("Incidents"); Text("Risks").tag("Risks"); Text("Vulnerabilities").tag("Vulnerabilities") }.pickerStyle(.segmented)
            if tab == "Vulnerabilities" {
                ForEach(vulnerabilities, id: \.1.id) { project, vulnerability in NavigationLink { VulnerabilityDetail(project: project, vulnerability: vulnerability) } label: { IncidentRow(title: "\(project.name): \(vulnerability.summary)", detail: "\(vulnerability.package) \(vulnerability.installedVersion) · fixed in \(vulnerability.fixedVersion)", severity: vulnerability.severity) } }.buttonStyle(.plain)
            } else if tab == "Risks" {
                riskRows
            } else {
                let affected = model.sites.filter { $0.errorRate > 1 || $0.p95Ms > 350 }
                if affected.isEmpty { EmptyState(icon: "checkmark.shield", title: "No active incidents", detail: "Traffic, resource and workload signals are within policy.") }
                ForEach(affected) { site in NavigationLink { WorkloadDetailView(site: site) } label: { IncidentRow(title: site.errorRate > 2 ? "Elevated errors on \(site.name)" : "Latency increase on \(site.name)", detail: "\(site.errorRate.formatted())% errors · p95 \(site.p95Ms.formatted()) ms", severity: site.errorRate > 2 ? "critical" : "high") } }.buttonStyle(.plain)
            }
        }
    }
    private var riskRows: some View {
        VStack(spacing: 10) {
            NavigationLink { TrafficPoliciesView() } label: { IncidentRow(title: "Traffic anomaly model", detail: "Observed request rate is inside the learned baseline. Open policy thresholds and signals.", severity: "normal") }.buttonStyle(.plain)
            ForEach(model.projects.filter { $0.completeness != "CURRENT" }) { project in NavigationLink { CodeProjectDetail(project: project) } label: { IncidentRow(title: "Partial evidence for \(project.name)", detail: "Some repository or runtime evidence is unavailable. Inspect coverage.", severity: "medium") } }.buttonStyle(.plain)
        }
    }
}

struct IncidentRow: View {
    let title: String; let detail: String; let severity: String
    var color: Color { severity.lowercased() == "critical" ? HW.red : severity.lowercased() == "normal" ? HW.teal : HW.amber }
    var body: some View { HStack(spacing: 14) { Circle().fill(color).frame(width: 10, height: 10).shadow(color: color, radius: 5); VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(HW.secondary) }; Spacer(); Text(severity.uppercased()).font(.caption2.bold()).padding(.horizontal, 9).padding(.vertical, 5).background(color.opacity(0.16)).foregroundStyle(color).clipShape(Capsule()); Image(systemName: "chevron.right").foregroundStyle(HW.secondary) }.padding(16).panel() }
}

struct VulnerabilityDetail: View {
    let project: ProjectHealth; let vulnerability: Vulnerability
    var body: some View {
        List {
            Section("Finding") { HWLabeled("Project", value: project.name); HWLabeled("Severity", value: vulnerability.severity.uppercased()); HWLabeled("Package", value: vulnerability.package); HWLabeled("Installed", value: vulnerability.installedVersion); HWLabeled("Fixed", value: vulnerability.fixedVersion) }
            Section("Description") { Text(vulnerability.summary) }
            Section("Markdown") { Text("- \(vulnerability.id) (\(vulnerability.severity)) `\(vulnerability.package)` \(vulnerability.installedVersion) → \(vulnerability.fixedVersion) — \(vulnerability.summary)").font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            if let url = URL(string: vulnerability.url), url.scheme == "https", url.host != "example.invalid" { Section { Link("Open advisory", destination: url) } }
        }.hwHiddenScrollBackground().background(HW.background).navigationTitle(vulnerability.id)
    }
}

struct TopologyView: View {
    @EnvironmentObject private var model: AppModel
    @State private var mode: TopologyMode = .traffic
    @State private var command = TopologyCommand(number: 0, action: .fit)
    @State private var selection: TopologySelection?
    @State private var focusedSiteID: String?
    @State private var focusedRoad: String?
    @State private var showLegend = true

    private var parentSites: [Site] {
        model.selectedSite.isEmpty ? model.sites : model.sites.filter { $0.id == model.selectedSite }
    }

    private var projectScope: Bool { !model.selectedSite.isEmpty }

    private var sites: [Site] {
        guard projectScope, let site = parentSites.first else { return model.sites }
        return TopologyLayer.explode(site, project: model.projects.first { $0.id == site.id }, services: model.dataServices)
    }

    private var projects: [ProjectHealth] {
        let ids = Set(parentSites.map(\.id))
        return model.projects.filter { ids.contains($0.id) }
    }

    private func project(for site: Site) -> ProjectHealth? {
        projects.first { site.id.hasPrefix($0.id) || $0.id == site.id }
    }

    private var componentLinks: [TopologyLink] {
        guard projectScope, let parent = parentSites.first else { return [] }
        return TopologyLayer.componentRoads(parent: parent, components: sites, routes: model.sources.internalRoutes ?? [])
    }

    private var node: ManagedNode {
        model.nodes.first(where: { $0.id == model.selectedNode })
            ?? ManagedNode(id: "primary", name: "Primary node", url: "", local: true, createdAt: "")
    }

    var body: some View {
        Group {
            if let overview = model.overview, !sites.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Picker("Runtime view", selection: $mode) {
                            ForEach(TopologyMode.allCases, id: \.self) { value in Text(value.rawValue).tag(value) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)
                        Spacer(minLength: 0)
                        Button("TOP") { send(.top) }
                        Button("ISO") { send(.isometric) }
                        Button("RESET") { send(.fit); focusedSiteID = nil; focusedRoad = nil }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    ZStack(alignment: .topLeading) {
                        NativeTopologyScene(snapshot: .init(node: node, overview: overview, sites: sites, projects: projects,
                                                            routes: model.sources.internalRoutes ?? [],
                                                            services: projectScope ? [] : model.dataServices,
                                                            links: componentLinks, projectScope: projectScope),
                                            mode: mode, command: command, selection: $selection,
                                            focusedSiteID: $focusedSiteID, focusedRoad: $focusedRoad)
                        HStack(alignment: .top, spacing: 8) {
                            dossier
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        VStack {
                            Spacer()
                            HStack(alignment: .bottom) {
                                legend
                                Spacer()
                                VStack(spacing: 8) {
                                    Button { send(.zoomIn) } label: { Image(systemName: "plus.magnifyingglass") }
                                        .accessibilityLabel("Zoom in")
                                    Button { send(.zoomOut) } label: { Image(systemName: "minus.magnifyingglass") }
                                        .accessibilityLabel("Zoom out")
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(10)
                        }
                    }
                    .frame(minHeight: 440)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(sites) { site in
                                Button {
                                    focusedSiteID = site.id
                                    focusedRoad = nil
                                    send(.focus)
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle().fill(site.errorRate >= 3 ? HW.red : HW.teal).frame(width: 7, height: 7)
                                        Text(site.name).lineLimit(1)
                                        Text("\(Int(site.requestsPerMinute))/min").foregroundStyle(HW.secondary)
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .sheet(item: $selection) { picked in
                    if let site = sites.first(where: { $0.id == picked.siteID }) {
                        TopologyTowerInspector(site: site,
                                               project: projects.first(where: { picked.siteID.hasPrefix($0.id) || $0.id == site.id }),
                                               layer: picked.layer)
                    }
                }
                .onChange(of: model.selectedSite) { _ in
                    focusedSiteID = nil
                    focusedRoad = nil
                    send(.fit)
                }
            } else {
                EmptyState(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: "Topology is unavailable",
                    detail: "Host metrics and workload data are required to build the runtime scene."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HW.background)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(HW.border))
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.environment["HOSTWATCH_MODE"] == "towers" {
                mode = .towers
            }
            if ProcessInfo.processInfo.environment["HOSTWATCH_FOCUS"] == "1", focusedSiteID == nil, let first = sites.first {
                focusedSiteID = first.id
                send(.focus)
            }
        }
        #endif
    }

    @ViewBuilder private var dossier: some View {
        if let focusedSiteID {
            VStack(alignment: .leading, spacing: 8) {
                Text("TARGET LOCKED").font(.caption2.bold()).kerning(1.6).foregroundStyle(HW.teal)
                if let flow = focusedRoad.flatMap({ TopologyFlow.parse(roadName: $0) }) {
                    originPip(flow.origin)
                    Text("\(boardTitle(flow.from)) → \(boardTitle(flow.to))")
                        .font(.caption.bold())
                    Text(flowCaption(flow))
                        .font(.caption2).foregroundStyle(HW.secondary)
                }
                if let site = sites.first(where: { $0.id == focusedSiteID }) {
                    if focusedRoad == nil {
                        originPip(.ourService)
                        Text(site.name).font(.headline)
                    }
                    Text(projectScope
                         ? "\(parentSites.first?.name ?? site.name) · \(TopologyServiceRole.of(siteID: site.id)?.title ?? "service")"
                         : site.domains.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(HW.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6)], alignment: .leading, spacing: 6) {
                        pip("REQ/MIN", Int(site.requestsPerMinute).formatted())
                        pip("ERRORS", Format.percent(site.errorRate))
                        pip("LAYERS", "\(TopologyLayer.layers(for: site, project: project(for: site)).count)")
                    }
                    HStack(spacing: 6) {
                        Button("Details") { selection = TopologySelection(siteID: site.id, layer: nil) }
                        Button("Release") { send(.fit) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                } else if focusedSiteID == "host" {
                    if focusedRoad == nil { originPip(.external) }
                    Text(focusedRoad == nil ? "Public clients" : node.name).font(.headline)
                    Text("External traffic enters here. Teal roads are public clients, not our services.")
                        .font(.caption2).foregroundStyle(HW.secondary)
                    Button("Release") { send(.fit) }.buttonStyle(.bordered).controlSize(.small)
                } else if focusedSiteID.hasPrefix("ext:"), let service = model.dataServices.first(where: { "ext:\($0.id)" == focusedSiteID }) {
                    if focusedRoad == nil { originPip(.ourData) }
                    Text(service.type).font(.headline)
                    Text("Our data · \(service.role) · \(service.siteName ?? "host")").font(.caption2).foregroundStyle(HW.secondary)
                    pip("STATE", service.container.state)
                    Button("Release") { send(.fit) }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            .padding(8)
            .frame(maxWidth: 176, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func boardTitle(_ id: String) -> String {
        if id == "host" { return "Public clients" }
        if id.hasPrefix("ext:"), let service = model.dataServices.first(where: { "ext:\($0.id)" == id }) {
            return service.type
        }
        return sites.first { $0.id == id }?.name ?? id
    }

    private func flowCaption(_ flow: TopologyFlow) -> String {
        switch flow.origin {
        case .external: return "Public clients enter through the edge"
        case .ourService: return "One of our services calling another"
        case .ourData: return "Our service talking to our data"
        }
    }

    private func originPip(_ origin: TopologyOrigin) -> some View {
        Text(origin.title.uppercased())
            .font(.caption2.bold())
            .kerning(0.8)
            .foregroundStyle(origin == .external ? HW.teal : origin == .ourData ? Color(red: 0.35, green: 0.82, blue: 0.62) : HW.amber)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { showLegend.toggle() } label: {
                HStack { Text("LEGEND").font(.caption2.bold()).kerning(1.4); Spacer(); Text(showLegend ? "▾" : "▸") }
            }.buttonStyle(.plain)
            if showLegend {
                if mode == .traffic {
                    legendRow(HW.teal, TopologyOrigin.external.legend)
                    legendRow(HW.amber, TopologyOrigin.ourService.legend)
                    legendRow(Color(red: 0.35, green: 0.82, blue: 0.62), TopologyOrigin.ourData.legend)
                    Text("Teal starts at PUBLIC. Amber is our services. Green is our data. Packets keep the color of their source.")
                        .font(.caption2).foregroundStyle(HW.secondary)
                } else {
                    legendRow(HW.teal, "RUNTIME · CONTAINERS")
                    legendRow(Color(red: 0.71, green: 0.55, blue: 1), "WEAVATRIX · MODULES")
                    legendRow(HW.amber, "STRUCTURE · ROADS ONLY")
                    Text(projectScope
                         ? "Towers show frontend, backend and data as separate pillars. Packets stay off."
                         : "Towers show stacked services and Weavatrix. Roads are structure, not live flow.")
                        .font(.caption2).foregroundStyle(HW.secondary)
                }
                Text("DRAG orbit · TWO FINGERS pan · PINCH zoom · TAP a tower")
                    .font(.caption2).foregroundStyle(HW.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: 220, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func pip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(HW.secondary)
            Text(value).font(.caption.bold())
        }
    }

    private func legendRow(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 12, height: 4)
            Text(text).font(.caption2)
        }
    }

    private func send(_ action: TopologyCameraAction) {
        command = TopologyCommand(number: command.number + 1, action: action)
    }
}

struct TopologyTowerInspector: View {
    @Environment(\.dismiss) private var dismiss
    let site: Site
    let project: ProjectHealth?
    let layer: Int?

    private var selectedContainer: ContainerInfo? {
        guard let layer, layers.indices.contains(layer) else { return nil }
        return layers[layer].container
    }

    private var layers: [TopologyLayer] { TopologyLayer.layers(for: site, project: project) }

    var body: some View {
        HWStackNavigation {
            List {
                Section {
                    HWLabeled("Project", value: site.name)
                    HWLabeled("Domains", value: site.domains.joined(separator: ", "))
                    HWLabeled("Requests", value: "\(site.requestsPerMinute.formatted())/min")
                    HWLabeled("Errors", value: Format.percent(site.errorRate))
                    HWLabeled("p95 latency", value: "\(site.p95Ms.formatted()) ms")
                }
                Section("Resources") {
                    HWLabeled("CPU", value: Format.percent(site.cpuPercent))
                    HWLabeled("Memory", value: "\(Format.bytes(site.memoryBytes)) of \(Format.bytes(site.memoryLimit))")
                    HWLabeled("Traffic", value: "\(Format.bytes(site.bytesPerMinute))/min")
                }
                if let layer, layers.indices.contains(layer) {
                    Section("Selected layer · \(layer + 1) of \(layers.count)") {
                        HWLabeled("Name", value: layers[layer].title)
                        Text(layers[layer].detail).foregroundStyle(HW.secondary)
                    }
                }
                if let container = selectedContainer {
                    Section("Container details") {
                        HWLabeled("State", value: container.state)
                        HWLabeled("Image", value: container.image)
                        HWLabeled("CPU", value: Format.percent(container.cpuPercent))
                        HWLabeled("Memory", value: Format.bytes(container.memoryBytes))
                        HWLabeled("Processes", value: container.pids.formatted())
                    }
                }
                Section("Services inside") {
                    ForEach(Array(layers.filter { $0.kind == .runtime }.enumerated()), id: \.offset) { index, layer in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(index + 1) · \(layer.title)")
                            Text(layer.detail).font(.caption).foregroundStyle(HW.secondary)
                        }
                    }
                }
                let hops = TopologyLayer.hops(for: site, project: project)
                if !hops.isEmpty {
                    Section("Inside the tower") {
                        ForEach(hops) { hop in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(hop.title)
                                Text(hop.weavatrix ? "Weavatrix hop" : "Runtime hop").font(.caption).foregroundStyle(HW.secondary)
                            }
                        }
                    }
                }
                if layers.contains(where: { $0.kind == .module || $0.kind == .community || $0.kind == .hotspot }) {
                    Section("Weavatrix inside") {
                        ForEach(Array(layers.filter { $0.kind == .module || $0.kind == .community || $0.kind == .hotspot }.enumerated()), id: \.offset) { _, layer in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(layer.title)
                                Text(layer.detail).font(.caption).foregroundStyle(HW.secondary)
                            }
                        }
                    }
                }
                Section("Tower layers") {
                    ForEach(Array(layers.enumerated()), id: \.offset) { index, layer in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Layer \(index + 1) · \(layer.title)")
                                Text(layer.detail)
                                    .font(.caption).foregroundStyle(HW.secondary)
                            }
                    }
                }
                if let project {
                    Section("Code evidence") {
                        HWLabeled("Coverage", value: project.completeness)
                        HWLabeled("Revision", value: project.revision)
                        HWLabeled("Modules", value: (project.analysis?.modules?.count ?? 0).formatted())
                        HWLabeled("Communities", value: (project.analysis?.communities?.count ?? 0).formatted())
                        NavigationLink("Inspect code health") { CodeProjectDetail(project: project) }
                    }
                }
                Section { NavigationLink("Open workload") { WorkloadDetailView(site: site) } }
            }
            .hwHiddenScrollBackground()
            .background(HW.background)
            .navigationTitle(site.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .hwSheetDetents()
    }
}

struct TowerLayersView: View {
    @Environment(\.dismiss) private var dismiss
    let project: ProjectHealth
    var body: some View {
        HWStackNavigation {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow(text: "Runtime tower layers"); Text(project.name).font(.largeTitle.bold())
                    ForEach(Array((project.analysis?.modules ?? []).enumerated()), id: \.element.id) { index, module in
                        HStack { ZStack { Circle().stroke(index.isMultiple(of: 2) ? HW.teal : HW.amber, lineWidth: 7).frame(width: CGFloat(84 + index * 28), height: CGFloat(34 + index * 10)); Text("L\(index + 1)").font(.caption.bold()) }; VStack(alignment: .leading) { Text(module.path).font(.headline); Text("\(module.files) files · \(module.symbols) symbols").foregroundStyle(HW.secondary) }; Spacer() }.padding(16).panel()
                    }
                    NavigationLink("Open complete code health evidence") { CodeProjectDetail(project: project) }.buttonStyle(.borderedProminent)
                }.padding(20)
            }.background(HW.background).toolbar { Button("Done") { dismiss() } }
        }.hwSheetDetents()
    }
}

struct WorkloadsView: View {
    @EnvironmentObject private var model: AppModel
    var filtered: [Site] { model.selectedSite.isEmpty ? model.sites : model.sites.filter { $0.id == model.selectedSite } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
            ForEach(filtered) { site in NavigationLink { WorkloadDetailView(site: site) } label: { VStack(alignment: .leading, spacing: 13) { HStack { VStack(alignment: .leading) { Text(site.name).font(.title3.bold()); Text(site.domains.joined(separator: ", ")).font(.caption).foregroundStyle(HW.secondary) }; Spacer(); Text(site.errorRate > 2 ? "AT RISK" : "HEALTHY").font(.caption2.bold()).foregroundStyle(site.errorRate > 2 ? HW.red : HW.teal) }; HStack { mini("Requests", "\(site.requestsPerMinute.formatted())/min"); mini("CPU", Format.percent(site.cpuPercent)); mini("Memory", Format.bytes(site.memoryBytes)) }; ProgressView(value: site.memoryBytes, total: max(1, site.memoryLimit)).tint(site.memoryBytes / max(1, site.memoryLimit) > 0.85 ? HW.red : HW.teal); HStack { Text("Open requests, processes, storage & limits").font(.caption).foregroundStyle(HW.teal); Spacer(); Image(systemName: "chevron.right") } }.padding(16).panel() }.buttonStyle(.plain) }
        }
        }
    }
    private func mini(_ name: String, _ value: String) -> some View { VStack(alignment: .leading) { Text(name).font(.caption2).foregroundStyle(HW.secondary); Text(value).font(.caption.bold()) }.frame(maxWidth: .infinity, alignment: .leading) }
}

struct WorkloadDetailView: View {
    @EnvironmentObject private var model: AppModel
    let site: Site
    @State private var tab = "Requests"
    @State private var pendingAction: String?
    var body: some View {
        List {
            Section { LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 10) { StatCard(title: "Requests", value: "\(site.requestsPerMinute.formatted())/min"); StatCard(title: "CPU", value: Format.percent(site.cpuPercent)); StatCard(title: "Memory", value: Format.bytes(site.memoryBytes), color: HW.amber); StatCard(title: "p95", value: "\(site.p95Ms.formatted()) ms") }.listRowInsets(EdgeInsets()) }
            Section { Picker("Detail", selection: $tab) { Text("Requests").tag("Requests"); Text("Processes").tag("Processes"); Text("Storage").tag("Storage"); Text("Limits").tag("Limits") }.pickerStyle(.segmented) }
            if tab == "Requests" { Section { PagedRows(items: model.requests.filter { $0.site == site.id }) { row in NavigationLink { RequestDetailView(request: row) } label: { RequestRow(request: row) } } } }
            else if tab == "Processes" { Section { if site.containers.isEmpty { Text("No container process snapshot is available yet.").foregroundStyle(HW.secondary) }; ForEach(site.containers) { item in VStack(alignment: .leading) { Text(item.name).font(.headline); Text("\(item.image) · \(Format.percent(item.cpuPercent)) CPU · \(Format.bytes(item.memoryBytes))").foregroundStyle(HW.secondary) } } } }
            else if tab == "Storage" { Section { NavigationLink("Inspect files, databases, images and container layers") { StorageInspectorView() } } }
            else { Section { HWLabeled("Memory limit", value: Format.bytes(site.memoryLimit)); HWLabeled("Shared Nginx", value: site.sharedNginx ? "Yes" : "No"); Text("Limit editing is restricted to operators and owners.").font(.caption).foregroundStyle(HW.secondary) } }
            Section("Controls") { Button("Restart", systemImage: "arrow.clockwise") { pendingAction = "restart" }; Button("Stop", systemImage: "stop.fill", role: .destructive) { pendingAction = "stop" } }
        }.hwHiddenScrollBackground().background(HW.background).navigationTitle(site.name)
        .confirmationDialog("\((pendingAction ?? "Action").capitalized) \(site.name)?", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })) { if let action = pendingAction { Button(action.capitalized, role: action == "stop" ? .destructive : nil) { Task { await model.runSiteAction(site, action: action) }; pendingAction = nil } } } message: { Text("This changes the running service on the selected node.") }
    }
}

struct TrafficPoliciesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var policy: TrafficGuardPolicy?
    @State private var showAddRule = false

    private var explanation: String {
        let trafficGuard = model.overview?.trafficGuard ?? model.guardState
        let attack = trafficGuard?.attackStage ?? "normal"
        let day = trafficGuard?.dailyStage ?? "healthy"
        let month = trafficGuard?.monthlyStage ?? "healthy"
        let meter = trafficGuard?.meterStage ?? "unknown"
        if attack != "normal" && day == "healthy" && month == "healthy" {
            return "Attack mitigation is active. Day and month budgets are healthy."
        }
        if day != "healthy" && attack == "normal" {
            return "Restriction is from the day budget. An attack is not the current reason."
        }
        if month != "healthy" && attack == "normal" {
            return "Restriction is from the monthly cutoff. An attack is not the current reason."
        }
        if meter == "unknown" || meter == "stale" {
            return "The usage meter is \(meter). Safe finite policy stays on until the ledger is verified."
        }
        return trafficGuard?.reason ?? "Independent attack, day, month, and meter states are shown separately."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Why traffic is limited")
                Text(explanation).font(.headline)
                if let trafficGuard = model.overview?.trafficGuard ?? model.guardState {
                    Text("Attack \(trafficGuard.attackStage ?? "n/a") · Day \(trafficGuard.dailyStage ?? "n/a") · Month \(trafficGuard.monthlyStage ?? "n/a") · Meter \(trafficGuard.meterStage ?? "n/a")")
                        .font(.caption).foregroundStyle(HW.secondary)
                }
            }.padding(18).panel()
            if let value = policy ?? model.guardState?.policy {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { VStack(alignment: .leading) { Eyebrow(text: "Cost and attack boundary"); Text("Traffic guard").font(.title2.bold()) }; Spacer(); Toggle("Enabled", isOn: Binding(get: { value.enabled }, set: { policy?.enabled = $0 })).labelsHidden() }
                    Picker("Mode", selection: Binding(get: { value.mode }, set: { policy?.mode = $0 })) { Text("Automatic").tag("automatic"); Text("Normal").tag("normal"); Text("Emergency").tag("emergency") }.pickerStyle(.segmented)
                    slider("Global egress cap", value: Binding(get: { value.normalMbps }, set: { policy?.normalMbps = $0 }), range: 1...1000, suffix: "Mbit/s")
                    slider("Warning cap", value: Binding(get: { value.warningMbps }, set: { policy?.warningMbps = $0 }), range: 1...200, suffix: "Mbit/s")
                    slider("Emergency cap", value: Binding(get: { value.emergencyMbps }, set: { policy?.emergencyMbps = $0 }), range: 1...50, suffix: "Mbit/s")
                    Toggle("Anomaly response", isOn: Binding(get: { value.anomalyEnabled }, set: { policy?.anomalyEnabled = $0 }))
                    slider("Anomaly risk threshold", value: Binding(get: { value.riskThreshold }, set: { policy?.riskThreshold = $0 }), range: 1...100, suffix: "%")
                    Button("Apply traffic policy") { if let policy { Task { await model.saveGuard(policy) } } }.buttonStyle(.borderedProminent)
                }.padding(18).panel().onAppear { if policy == nil { policy = model.guardState?.policy } }
            } else { EmptyState(icon: "shield.slash", title: "Policy is unavailable", detail: "Select a managed node and refresh.") }

            HStack { Text("IP and country blocks").font(.title2.bold()); Spacer(); Button("Add rule", systemImage: "plus") { showAddRule = true }.buttonStyle(.bordered) }
            ForEach(model.accessRules.rules) { rule in HStack { Image(systemName: rule.kind == "country" ? "globe" : "network").foregroundStyle(HW.red); VStack(alignment: .leading) { Text(rule.value).font(.headline); Text("\(rule.kind.capitalized) · \(rule.label ?? "Manual block") · \(rule.site)").font(.caption).foregroundStyle(HW.secondary) }; Spacer(); Button(role: .destructive) { Task { await model.removeRule(rule) } } label: { Image(systemName: "trash") } }.padding(15).panel() }
        }.sheet(isPresented: $showAddRule) { AddRuleView() }
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View { VStack(alignment: .leading) { HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue)) \(suffix)").monospacedDigit().foregroundStyle(HW.teal) }; Slider(value: value, in: range) } }
}

struct AddRuleView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "ip"; @State private var value = ""
    var body: some View { HWStackNavigation { Form { Picker("Rule type", selection: $kind) { Text("IP address").tag("ip"); Text("Country code").tag("country") }; TextField(kind == "ip" ? "203.0.113.10" : "US", text: $value).textInputAutocapitalization(kind == "country" ? .characters : .never); Text("The rule applies to the selected project. Choose a site in the scope bar first.").font(.caption).foregroundStyle(HW.secondary) } .navigationTitle("New access rule").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Add") { Task { await model.block(site: model.selectedSite, kind: kind, value: value); dismiss() } }.disabled(value.isEmpty || model.selectedSite.isEmpty) } } } }
}
