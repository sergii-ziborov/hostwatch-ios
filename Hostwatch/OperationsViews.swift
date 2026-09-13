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
            Section("Finding") { LabeledContent("Project", value: project.name); LabeledContent("Severity", value: vulnerability.severity.uppercased()); LabeledContent("Package", value: vulnerability.package); LabeledContent("Installed", value: vulnerability.installedVersion); LabeledContent("Fixed", value: vulnerability.fixedVersion) }
            Section("Description") { Text(vulnerability.summary) }
            if let url = URL(string: vulnerability.url), url.scheme == "https", url.host != "example.invalid" { Section { Link("Open advisory", destination: url) } }
        }.scrollContentBackground(.hidden).background(HW.background).navigationTitle(vulnerability.id)
    }
}

struct TopologyView: View {
    @EnvironmentObject private var model: AppModel
    @State private var mode: TopologyMode = .towers
    @State private var command = TopologyCommand(number: 0, action: .fit)
    @State private var selection: TopologySelection?

    private var sites: [Site] {
        model.selectedSite.isEmpty ? model.sites : model.sites.filter { $0.id == model.selectedSite }
    }

    private var projects: [ProjectHealth] {
        let ids = Set(sites.map(\.id))
        return model.projects.filter { ids.contains($0.id) }
    }

    private var node: ManagedNode {
        model.nodes.first(where: { $0.id == model.selectedNode })
            ?? ManagedNode(id: "primary", name: "Primary node", url: "", local: true, createdAt: "")
    }

    var body: some View {
        Group {
            if let overview = model.overview, !sites.isEmpty {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Picker("Runtime view", selection: $mode) {
                            ForEach(TopologyMode.allCases, id: \.self) { value in Text(value.rawValue).tag(value) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)
                        Spacer(minLength: 0)
                        Button { send(.top) } label: { Image(systemName: "square.3.layers.3d.top.filled") }
                            .accessibilityLabel("Top view")
                        Button { send(.fit) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                            .accessibilityLabel("Fit all towers")
                    }
                    .buttonStyle(.bordered)
                    ZStack(alignment: .bottomTrailing) {
                        NativeTopologyScene(snapshot: .init(node: node, overview: overview, sites: sites, projects: projects),
                                            mode: mode, command: command, selection: $selection)
                        VStack(spacing: 8) {
                            Button { send(.zoomIn) } label: { Image(systemName: "plus.magnifyingglass") }
                                .accessibilityLabel("Zoom in")
                            Button { send(.zoomOut) } label: { Image(systemName: "minus.magnifyingglass") }
                                .accessibilityLabel("Zoom out")
                        }
                        .buttonStyle(.bordered)
                        .padding(12)
                    }
                    .frame(minHeight: 330)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(mode == .traffic
                         ? "Lines show measured node-to-project traffic, not inferred service dependencies."
                         : "Drag to orbit · pinch to zoom · double tap a tower to focus · tap for details")
                        .font(.caption2).foregroundStyle(HW.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(sites) { site in
                                Button {
                                    selection = TopologySelection(siteID: site.id, layer: nil)
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
                                               project: projects.first(where: { $0.id == site.id }),
                                               layer: picked.layer)
                    }
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
        NavigationStack {
            List {
                Section {
                    LabeledContent("Project", value: site.name)
                    LabeledContent("Domains", value: site.domains.joined(separator: ", "))
                    LabeledContent("Requests", value: "\(site.requestsPerMinute.formatted())/min")
                    LabeledContent("Errors", value: Format.percent(site.errorRate))
                    LabeledContent("p95 latency", value: "\(site.p95Ms.formatted()) ms")
                }
                Section("Resources") {
                    LabeledContent("CPU", value: Format.percent(site.cpuPercent))
                    LabeledContent("Memory", value: "\(Format.bytes(site.memoryBytes)) of \(Format.bytes(site.memoryLimit))")
                    LabeledContent("Traffic", value: "\(Format.bytes(site.bytesPerMinute))/min")
                }
                if let layer, layers.indices.contains(layer) {
                    Section("Selected layer · \(layer + 1) of \(layers.count)") {
                        LabeledContent("Name", value: layers[layer].title)
                        Text(layers[layer].detail).foregroundStyle(HW.secondary)
                    }
                }
                if let container = selectedContainer {
                    Section("Container details") {
                        LabeledContent("State", value: container.state)
                        LabeledContent("Image", value: container.image)
                        LabeledContent("CPU", value: Format.percent(container.cpuPercent))
                        LabeledContent("Memory", value: Format.bytes(container.memoryBytes))
                        LabeledContent("Processes", value: container.pids.formatted())
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
                        LabeledContent("Coverage", value: project.completeness)
                        LabeledContent("Revision", value: project.revision)
                        NavigationLink("Inspect code health") { CodeProjectDetail(project: project) }
                    }
                }
                Section { NavigationLink("Open workload") { WorkloadDetailView(site: site) } }
            }
            .scrollContentBackground(.hidden)
            .background(HW.background)
            .navigationTitle(site.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct TowerLayersView: View {
    @Environment(\.dismiss) private var dismiss
    let project: ProjectHealth
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow(text: "Runtime tower layers"); Text(project.name).font(.largeTitle.bold())
                    ForEach(Array((project.analysis?.modules ?? []).enumerated()), id: \.element.id) { index, module in
                        HStack { ZStack { Circle().stroke(index.isMultiple(of: 2) ? HW.teal : HW.amber, lineWidth: 7).frame(width: CGFloat(84 + index * 28), height: CGFloat(34 + index * 10)); Text("L\(index + 1)").font(.caption.bold()) }; VStack(alignment: .leading) { Text(module.path).font(.headline); Text("\(module.files) files · \(module.symbols) symbols").foregroundStyle(HW.secondary) }; Spacer() }.padding(16).panel()
                    }
                    NavigationLink("Open complete code health evidence") { CodeProjectDetail(project: project) }.buttonStyle(.borderedProminent)
                }.padding(20)
            }.background(HW.background).toolbar { Button("Done") { dismiss() } }
        }.presentationDetents([.medium, .large])
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
        DataServicesView()
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
            if tab == "Requests" { Section { ForEach(model.requests.filter { $0.site == site.id }) { row in NavigationLink { RequestDetailView(request: row) } label: { RequestRow(request: row) } } } }
            else if tab == "Processes" { Section { if site.containers.isEmpty { Text("No container process snapshot is available yet.").foregroundStyle(HW.secondary) }; ForEach(site.containers) { item in VStack(alignment: .leading) { Text(item.name).font(.headline); Text("\(item.image) · \(Format.percent(item.cpuPercent)) CPU · \(Format.bytes(item.memoryBytes))").foregroundStyle(HW.secondary) } } } }
            else if tab == "Storage" { Section { NavigationLink("Inspect files, databases, images and container layers") { StorageInspectorView() } } }
            else { Section { LabeledContent("Memory limit", value: Format.bytes(site.memoryLimit)); LabeledContent("Shared Nginx", value: site.sharedNginx ? "Yes" : "No"); Text("Limit editing is restricted to operators and owners.").font(.caption).foregroundStyle(HW.secondary) } }
            Section("Controls") { Button("Restart", systemImage: "arrow.clockwise") { pendingAction = "restart" }; Button("Stop", systemImage: "stop.fill", role: .destructive) { pendingAction = "stop" } }
        }.scrollContentBackground(.hidden).background(HW.background).navigationTitle(site.name)
        .confirmationDialog("\((pendingAction ?? "Action").capitalized) \(site.name)?", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })) { if let action = pendingAction { Button(action.capitalized, role: action == "stop" ? .destructive : nil) { Task { await model.runSiteAction(site, action: action) }; pendingAction = nil } } } message: { Text("This changes the running service on the selected node.") }
    }
}

struct TrafficPoliciesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var policy: TrafficGuardPolicy?
    @State private var showAddRule = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
    var body: some View { NavigationStack { Form { Picker("Rule type", selection: $kind) { Text("IP address").tag("ip"); Text("Country code").tag("country") }; TextField(kind == "ip" ? "203.0.113.10" : "US", text: $value).textInputAutocapitalization(kind == "country" ? .characters : .never); Text("The rule applies to the selected project. Choose a site in the scope bar first.").font(.caption).foregroundStyle(HW.secondary) } .navigationTitle("New access rule").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Add") { Task { await model.block(site: model.selectedSite, kind: kind, value: value); dismiss() } }.disabled(value.isEmpty || model.selectedSite.isEmpty) } } } }
}
