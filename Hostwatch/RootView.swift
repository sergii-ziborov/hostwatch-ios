import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: SidebarPage?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    init() {
        let requested = ProcessInfo.processInfo.environment["HOSTWATCH_PAGE"]
        _selection = State(initialValue: requested.flatMap(SidebarPage.init(rawValue:)) ?? .overview)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section {
                    brand
                }
                .listRowBackground(Color.clear)

                Section("Observe") {
                    menu(.overview); menu(.traffic); menu(.incidents); menu(.topology); menu(.workloads)
                }
                Section("Control") {
                    menu(.policies); menu(.environment); menu(.automations)
                }
                Section("Analyze") { menu(.codeHealth) }
                Section("Company") { menu(.access); menu(.organization) }

                Section {
                    Button(role: .destructive) { Task { await model.signOut() } } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
                }
            }
            .scrollContentBackground(.hidden)
            .background(HW.background)
            .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 320)
        } detail: {
            NavigationStack {
                PageContainer(page: selection ?? .overview)
            }
            .background(HW.background)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selection) { _, next in
            guard let next else { return }
            Task { await model.reload(page: next) }
            if model.live { model.setLive(true, page: next) }
        }
    }

    private func menu(_ page: SidebarPage) -> some View {
        NavigationLink(value: page) { Label(page.title, systemImage: page.icon) }
            .tag(page)
    }

    private var brand: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).stroke(HW.teal).frame(width: 38, height: 38)
                Text("H").font(.headline.bold()).foregroundStyle(HW.teal)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("HOSTWATCH").font(.headline).tracking(1.5)
                Text(model.session.organization?.name ?? "Control plane").font(.caption).foregroundStyle(HW.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 8)
    }
}

struct PageContainer: View {
    @EnvironmentObject private var model: AppModel
    let page: SidebarPage

    var body: some View {
        Group {
            if page == .topology {
                VStack(alignment: .leading, spacing: 12) {
                    PageHeader(page: page)
                    ScopeBar(page: page)
                    errorBanner
                    pageContent
                        .opacity(model.loading ? 0.64 : 1)
                }
                .padding(20)
                .frame(maxWidth: 1500, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        PageHeader(page: page)
                        ScopeBar(page: page)
                        errorBanner
                        pageContent
                            .opacity(model.loading ? 0.64 : 1)
                    }
                    .padding(20)
                    .frame(maxWidth: 1500, alignment: .leading)
                }
            }
        }
        .background(HW.background)
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.reload(page: page) }
        .task(id: page) {
            await model.reload(page: page)
            if model.live { model.setLive(true, page: page) }
        }
    }

    @ViewBuilder private var errorBanner: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(HW.red).padding(12).frame(maxWidth: .infinity, alignment: .leading).panel()
        }
    }

    @ViewBuilder private var pageContent: some View {
        if model.fixtures, ProcessInfo.processInfo.environment["HOSTWATCH_DETAIL"] == "disk" { StorageInspectorView() }
        else if model.fixtures, ProcessInfo.processInfo.environment["HOSTWATCH_DETAIL"] == "errors" { ErrorExplorerView() }
        else if model.fixtures, ProcessInfo.processInfo.environment["HOSTWATCH_DETAIL"] == "request", let request = model.requests.first { RequestDetailView(request: request) }
        else {
            switch page {
            case .overview: OverviewView()
            case .traffic: TrafficView()
            case .incidents: IncidentsView()
            case .topology: TopologyView()
            case .workloads: WorkloadsView()
            case .policies: TrafficPoliciesView()
            case .environment: EnvironmentView()
            case .codeHealth: CodeHealthView()
            case .automations: AutomationsView()
            case .access: AccessView()
            case .organization: OrganizationView()
            }
        }
    }
}

struct PageHeader: View {
    @EnvironmentObject private var model: AppModel
    let page: SidebarPage
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Eyebrow(text: "\(model.session.organization?.name ?? "Infrastructure") · \(model.nodes.first(where: { $0.id == model.selectedNode })?.name ?? "Primary node")")
            Text(page.title).font(.system(.largeTitle, design: .rounded, weight: .bold))
            HStack(spacing: 7) {
                Circle().fill(model.live ? HW.teal : HW.amber).frame(width: 8, height: 8)
                Text(model.live ? "Live" : "Paused").foregroundStyle(model.live ? HW.teal : HW.amber)
                if let overview = model.overview { Text("· \(overview.hostname) · up \(Format.duration(overview.uptimeSeconds))").foregroundStyle(HW.secondary) }
            }
            .font(.subheadline)
        }
    }
}

struct ScopeBar: View {
    @EnvironmentObject private var model: AppModel
    let page: SidebarPage

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    model.setLive(!model.live, page: page)
                } label: {
                    Label(model.live ? "Live" : "Paused", systemImage: model.live ? "dot.radiowaves.left.and.right" : "pause.fill")
                        .frame(minWidth: 76)
                }
                .buttonStyle(.bordered).tint(model.live ? HW.teal : HW.amber)
                Menu {
                    ForEach(model.nodes) { node in Button(node.name) { Task { await model.changeNode(node.id) } } }
                } label: { scopeLabel(model.nodes.first(where: { $0.id == model.selectedNode })?.name ?? "Primary node", icon: "server.rack") }
                Menu {
                    Button("All sites") { model.selectedSite = ""; Task { await model.reload(page: page) } }
                    ForEach(model.sites) { site in Button(site.name) { model.selectedSite = site.id; Task { await model.reload(page: page) } } }
                } label: { scopeLabel(model.sites.first(where: { $0.id == model.selectedSite })?.name ?? "All sites", icon: "globe") }
                Menu {
                    ForEach([1, 6, 24, 168], id: \.self) { value in Button(value == 168 ? "7 days" : "\(value) hours") { model.hours = value; Task { await model.reload(page: page) } } }
                } label: { scopeLabel(model.hours == 168 ? "7 days" : "\(model.hours)h", icon: "clock") }
                Button { Task { await model.reload(page: page) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.bordered).accessibilityLabel("Refresh")
            }
            .padding(10)
        }
        .background(HW.panel.opacity(0.92)).clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(HW.border))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scopeLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).lineLimit(1).frame(minWidth: 88).padding(.horizontal, 3)
    }
}
