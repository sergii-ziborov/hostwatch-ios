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
    @State private var mode = "Towers"
    @State private var zoom = 1.0
    @State private var selected: ProjectHealth?
    @State private var elevated: ProjectHealth?

    var filtered: [ProjectHealth] {
        model.selectedSite.isEmpty ? model.projects : model.projects.filter { $0.id == model.selectedSite }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Topology mode", selection: $mode) { Text("Towers").tag("Towers"); Text("Connections").tag("Connections") }.pickerStyle(.segmented).frame(maxWidth: 330)
                Spacer()
                Button { zoom = max(0.6, zoom - 0.2) } label: { Image(systemName: "minus.magnifyingglass") }.buttonStyle(.bordered)
                Button { zoom = min(2.2, zoom + 0.2) } label: { Image(systemName: "plus.magnifyingglass") }.buttonStyle(.bordered)
                Button("Fit") { zoom = 1 }.buttonStyle(.bordered)
            }
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [HW.background, HW.panel], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                TopologyGrid().opacity(0.55)
                if mode == "Connections" { connections }
                else { towers }
                VStack(alignment: .leading, spacing: 4) { Label("LIVE DATA", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(HW.teal); Text("Tap a tower to inspect · double tap for layers · pinch controls remain available").foregroundStyle(HW.secondary) }.font(.caption.bold()).padding(12).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 10)).padding(12)
            }
            .frame(minHeight: 500).panel().clipped()
            .simultaneousGesture(MagnifyGesture().onChanged { value in zoom = min(2.2, max(0.6, value.magnification)) })
            if let selected { topologyInspector(selected) }
        }
        .sheet(item: $elevated) { project in TowerLayersView(project: project) }
    }

    private var towers: some View {
        GeometryReader { proxy in
            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, project in
                let cols = max(1, min(3, filtered.count)); let row = index / cols; let col = index % cols
                let x = proxy.size.width * (Double(col + 1) / Double(cols + 1)); let y = 150 + Double(row) * 190
                Button { selected = project } label: {
                    VStack(spacing: 7) {
                        ZStack(alignment: .bottom) {
                            Ellipse().stroke(HW.teal.opacity(0.65), lineWidth: 8).frame(width: 130 * zoom, height: 45 * zoom)
                            RoundedRectangle(cornerRadius: 18).fill(towerColor(project)).frame(width: 72 * zoom, height: CGFloat(80 + min(130, (project.graph?.nodes ?? 0) / 50)) * zoom).overlay(alignment: .top) { Capsule().fill(.white.opacity(0.24)).frame(height: 2).padding(.top, 8) }
                        }
                        Text(project.name).font(.system(.caption, design: .monospaced, weight: .bold)).foregroundStyle(.white)
                    }
                }.buttonStyle(.plain).position(x: x, y: y).onTapGesture(count: 2) { elevated = project }
            }
        }
    }

    private var connections: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let count = max(1, filtered.count)
                for index in 0..<max(0, count - 1) {
                    let a = CGPoint(x: size.width * Double(index + 1) / Double(count + 1), y: size.height * (index.isMultiple(of: 2) ? 0.42 : 0.62))
                    let b = CGPoint(x: size.width * Double(index + 2) / Double(count + 1), y: size.height * ((index + 1).isMultiple(of: 2) ? 0.42 : 0.62))
                    var line = Path(); line.move(to: a); line.addLine(to: b); context.stroke(line, with: .color(index.isMultiple(of: 2) ? HW.teal : HW.amber), lineWidth: 5 * zoom)
                }
            }
            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, project in
                Button { selected = project } label: { VStack { Circle().fill(towerColor(project)).frame(width: 74 * zoom, height: 74 * zoom).overlay(Image(systemName: "server.rack").foregroundStyle(HW.background)); Text(project.name).font(.caption.bold()) } }.buttonStyle(.plain)
                    .position(x: proxy.size.width * Double(index + 1) / Double(max(1, filtered.count) + 1), y: proxy.size.height * (index.isMultiple(of: 2) ? 0.42 : 0.62))
            }
        }
    }

    private func towerColor(_ project: ProjectHealth) -> Color { (project.vulnerabilities ?? []).contains { $0.severity.lowercased() == "critical" } ? HW.red : project.completeness == "CURRENT" ? HW.teal : HW.amber }
    private func topologyInspector(_ project: ProjectHealth) -> some View { HStack { VStack(alignment: .leading) { Eyebrow(text: "Selected workload"); Text(project.name).font(.headline); Text("\(project.graph?.nodes ?? 0) nodes · \(project.graph?.edges ?? 0) links · \((project.vulnerabilities ?? []).count) vulnerabilities").font(.caption).foregroundStyle(HW.secondary) }; Spacer(); NavigationLink("Open details") { CodeProjectDetail(project: project) }.buttonStyle(.borderedProminent); Button("Layers") { elevated = project }.buttonStyle(.bordered) }.padding(16).panel() }
}

struct TopologyGrid: View {
    var body: some View { Canvas { context, size in for x in stride(from: 0.0, through: size.width, by: 44) { var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); context.stroke(path, with: .color(HW.border.opacity(0.35)), lineWidth: 0.5) }; for y in stride(from: 0.0, through: size.height, by: 44) { var path = Path(); path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); context.stroke(path, with: .color(HW.border.opacity(0.35)), lineWidth: 0.5) } } }
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
            ForEach(filtered) { site in NavigationLink { WorkloadDetailView(site: site) } label: { VStack(alignment: .leading, spacing: 13) { HStack { VStack(alignment: .leading) { Text(site.name).font(.title3.bold()); Text(site.domains.joined(separator: ", ")).font(.caption).foregroundStyle(HW.secondary) }; Spacer(); Text(site.errorRate > 2 ? "AT RISK" : "HEALTHY").font(.caption2.bold()).foregroundStyle(site.errorRate > 2 ? HW.red : HW.teal) }; HStack { mini("Requests", "\(site.requestsPerMinute.formatted())/min"); mini("CPU", Format.percent(site.cpuPercent)); mini("Memory", Format.bytes(site.memoryBytes)) }; ProgressView(value: site.memoryBytes, total: max(1, site.memoryLimit)).tint(site.memoryBytes / max(1, site.memoryLimit) > 0.85 ? HW.red : HW.teal); HStack { Text("Open requests, processes, storage & limits").font(.caption).foregroundStyle(HW.teal); Spacer(); Image(systemName: "chevron.right") } }.padding(16).panel() }.buttonStyle(.plain) }
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
