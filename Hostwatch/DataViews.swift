import SwiftUI

struct DataView: View {
    @EnvironmentObject private var model: AppModel
    private var services: [DataService] {
        model.selectedSite.isEmpty ? model.dataServices : model.dataServices.filter { $0.siteId == model.selectedSite }
    }
    private var files: [DataFile] {
        let scoped = model.selectedSite.isEmpty ? model.dataFiles : model.dataFiles.filter { $0.siteId == model.selectedSite }
        return scoped.filter { !$0.backup }
    }
    private var storedCopies: [DataFile] {
        let scoped = model.selectedSite.isEmpty ? model.dataFiles : model.dataFiles.filter { $0.siteId == model.selectedSite }
        return scoped.filter(\.backup)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Stateful infrastructure")
                    Text("Containers, files and tables").font(.title3.bold())
                }
                Spacer()
                Text("\(services.count) services · \(files.count) files")
                    .font(.caption.bold()).foregroundStyle(HW.teal).multilineTextAlignment(.trailing)
            }
            if let error = model.dataServicesError {
                Label("Service inventory unavailable: \(error)", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(HW.amber)
            } else if services.isEmpty && files.isEmpty && storedCopies.isEmpty {
                Text("No database container or data file was detected on scanned application mounts. Remote and managed databases need an exporter for query metrics. SQLite files found here can be opened table by table.")
                    .font(.footnote).foregroundStyle(HW.secondary)
            }
            if !services.isEmpty {
                Text("Running services").font(.headline)
                ForEach(services) { service in
                    NavigationLink { DataServiceDetailView(service: service) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: service.type.lowercased().contains("redis") || service.role.lowercased().contains("cache") ? "memorychip" : "cylinder.split.1x2")
                                .foregroundStyle(service.container.state == "running" ? HW.teal : HW.red)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(service.container.name).font(.subheadline.bold()).lineLimit(1)
                                Text("\(service.type) · \(service.siteName ?? "Host & shared")")
                                    .font(.caption).foregroundStyle(HW.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(Format.bytes(service.container.memoryBytes)).font(.caption.bold())
                                Text(Format.percent(service.container.cpuPercent)).font(.caption2).foregroundStyle(HW.secondary)
                            }
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(HW.secondary)
                        }
                        .padding(12)
                        .background(HW.panelRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            if !files.isEmpty {
                Text("Data files").font(.headline)
                Text("Open a SQLite file to list tables and preview rows. PostgreSQL and Redis stay at container evidence until an exporter is attached.")
                    .font(.caption).foregroundStyle(HW.secondary)
                ForEach(files) { file in
                    NavigationLink { DataFileDetailView(file: file) } label: { DataFileRow(file: file) }
                        .buttonStyle(.plain)
                }
            }
            if !storedCopies.isEmpty {
                Text("Stored copies").font(.headline)
                ForEach(storedCopies) { file in
                    NavigationLink { DataFileDetailView(file: file) } label: { DataFileRow(file: file) }
                        .buttonStyle(.plain)
                }
            }
            if let scanError = model.dataServicesScanError, !scanError.isEmpty {
                Label("File scan incomplete: \(scanError)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(HW.amber)
            }
            Text("Scanned at \(model.dataServicesScannedAt.flatMap(ChartTime.parse).map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "not reported"). Container CPU and memory are live. File sizes are disk evidence.")
                .font(.caption2).foregroundStyle(HW.secondary)
        }
        .padding(16)
        .panel()
    }
}

private struct DataFileRow: View {
    let file: DataFile
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.type.lowercased().contains("sqlite") ? "tablecells" : file.type.lowercased().contains("cache") ? "archivebox" : "externaldrive")
                .foregroundStyle(HW.teal).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.siteName ?? "Host & shared runtime").font(.subheadline.bold())
                Text(file.type).font(.caption).foregroundStyle(HW.secondary)
                Text(file.path).font(.caption2.monospaced()).foregroundStyle(HW.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Text(Format.bytes(file.sizeBytes)).font(.caption.bold())
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(HW.secondary)
        }
        .padding(12).background(HW.panelRaised).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct DataFileDetailView: View {
    @EnvironmentObject private var model: AppModel
    let file: DataFile
    @State private var tables: [DataTableInfo] = []
    @State private var loading = false
    @State private var error: String?
    private var site: Site? { model.sites.first { $0.id == file.siteId } }
    private var canInspect: Bool { file.type.lowercased().contains("sqlite") }

    var body: some View {
        List {
            Section("Observed file") {
                HWLabeled("Project", value: file.siteName ?? "Host & shared runtime")
                HWLabeled("Type", value: file.type)
                HWLabeled("Size", value: Format.bytes(file.sizeBytes))
                HWLabeled("Container", value: file.container ?? "Not reported")
                HWLabeled("Modified", value: ChartTime.parse(file.modifiedAt)?.formatted(date: .abbreviated, time: .shortened) ?? file.modifiedAt)
                HWLabeled("Stored copy", value: file.backup ? "Yes" : "No")
                Text(file.path).font(.footnote.monospaced()).textSelection(.enabled)
            }
            if canInspect {
                Section("Tables") {
                    if loading { ProgressView("Reading tables…") }
                    if let error { Text(error).foregroundStyle(HW.amber) }
                    if !loading && tables.isEmpty && error == nil {
                        Text("No user tables were found in this file.").foregroundStyle(HW.secondary)
                    }
                    ForEach(tables) { table in
                        NavigationLink { DataTableRowsView(file: file, table: table) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HWLabeled(table.name, value: table.rowCount.map { "\($0) rows" } ?? "Open")
                                if let columns = table.columns, !columns.isEmpty {
                                    Text(columns.joined(separator: " · ")).font(.caption2.monospaced()).foregroundStyle(HW.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                }
            } else {
                Section("Measurement") {
                    Text("Table preview is available for discovered SQLite files. This \(file.type.lowercased()) needs a dedicated exporter for query and connection metrics.")
                        .foregroundStyle(HW.secondary)
                }
            }
            if let site { Section { NavigationLink("Open \(site.name) workload") { WorkloadDetailView(site: site) } } }
        }
        .hwHiddenScrollBackground().background(HW.background)
        .navigationTitle(file.type)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: file.path) { await loadTables() }
        .refreshable { await loadTables() }
    }

    private func loadTables() async {
        guard canInspect else { return }
        loading = true; defer { loading = false }
        do {
            tables = try await model.dataTables(path: file.path).tables
            error = nil
        } catch {
            tables = []
            self.error = error.localizedDescription
        }
    }
}

struct DataTableRowsView: View {
    @EnvironmentObject private var model: AppModel
    let file: DataFile
    let table: DataTableInfo
    @State private var columns: [String] = []
    @State private var rows: [[String]] = []
    @State private var offset = 0
    @State private var total: Int?
    @State private var loading = false
    @State private var error: String?
    private let pageSize = 25

    var body: some View {
        List {
            Section {
                HWLabeled("File", value: file.path)
                HWLabeled("Rows shown", value: "\(rows.count)\(total.map { " of \($0)" } ?? "")")
                if let columns = table.columns, !columns.isEmpty {
                    Text(columns.joined(separator: " · ")).font(.caption.monospaced()).foregroundStyle(HW.secondary)
                }
            }
            if loading && rows.isEmpty {
                Section { ProgressView("Loading rows…") }
            }
            if let error { Section { Text(error).foregroundStyle(HW.amber) } }
            if !rows.isEmpty {
                Section("Preview") {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            headerRow
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                HStack(alignment: .top, spacing: 0) {
                                    ForEach(Array(displayColumns.enumerated()), id: \.offset) { columnIndex, _ in
                                        Text(columnIndex < row.count ? row[columnIndex] : "")
                                            .font(.system(.caption, design: .monospaced))
                                            .frame(width: 132, alignment: .leading)
                                            .padding(8)
                                    }
                                }
                                .background(index.isMultiple(of: 2) ? HW.panel : HW.panelRaised)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                }
            }
            if canLoadMore {
                Section {
                    Button("Load more rows") { Task { await loadMore() } }
                        .disabled(loading)
                        .onAppear { Task { await loadMore() } }
                    if loading { ProgressView() }
                }
            }
        }
        .hwHiddenScrollBackground().background(HW.background)
        .navigationTitle(table.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: table.name) { await resetAndLoad() }
    }

    private var displayColumns: [String] { columns.isEmpty ? (table.columns ?? []) : columns }
    private var canLoadMore: Bool {
        if let total { return rows.count < total }
        return !rows.isEmpty && rows.count % pageSize == 0
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(displayColumns, id: \.self) { column in
                Text(column).font(.caption.bold()).frame(width: 132, alignment: .leading).padding(8)
            }
        }
        .background(HW.panelRaised)
    }

    private func resetAndLoad() async {
        columns = table.columns ?? []
        rows = []
        offset = 0
        total = table.rowCount
        error = nil
        await loadMore()
    }

    private func loadMore() async {
        guard !loading else { return }
        if let total, rows.count >= total { return }
        loading = true; defer { loading = false }
        do {
            let page = try await model.dataRows(path: file.path, table: table.name, limit: pageSize, offset: offset)
            columns = page.columns
            rows.append(contentsOf: page.rows)
            offset += page.rows.count
            total = page.rowCount ?? total
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct DataServiceDetailView: View {
    @EnvironmentObject private var model: AppModel
    let service: DataService
    private var site: Site? { model.sites.first { $0.id == service.siteId } }
    private var relatedFiles: [DataFile] {
        model.dataFiles.filter { $0.siteId == service.siteId && $0.siteId != nil }
    }

    var body: some View {
        List {
            Section("Service") {
                HWLabeled("Type", value: service.type)
                HWLabeled("Role", value: service.role)
                HWLabeled("State", value: service.container.state)
                HWLabeled("Status", value: service.container.status)
                HWLabeled("Project", value: service.siteName ?? "Host & shared runtime")
            }
            Section("Load") {
                HWLabeled("CPU", value: Format.percent(service.container.cpuPercent))
                HWLabeled("Memory", value: Format.bytes(service.container.memoryBytes))
                HWLabeled("Memory limit", value: Format.bytes(service.container.memoryLimit))
                HWLabeled("Processes", value: service.container.pids.formatted())
                HWLabeled("Network received", value: Format.bytes(service.container.networkRxBytes))
                HWLabeled("Network sent", value: Format.bytes(service.container.networkTxBytes))
            }
            Section("Runtime evidence") {
                HWLabeled("Image", value: service.container.image)
                HWLabeled("Compose project", value: service.container.project)
                HWLabeled("Container ID", value: service.container.id)
            }
            if !relatedFiles.isEmpty {
                Section("Discovered files") {
                    ForEach(relatedFiles) { file in
                        NavigationLink { DataFileDetailView(file: file) } label: {
                            HWLabeled(file.type, value: Format.bytes(file.sizeBytes))
                        }
                    }
                }
            }
            Section { Text("Query rate, active connections and cache hit ratio require a database exporter. SQLite files attached to this project can be opened from the Database tab.")
                .font(.footnote).foregroundStyle(HW.secondary) }
            if let site { Section { NavigationLink("Open \(site.name) workload") { WorkloadDetailView(site: site) } } }
        }
        .hwHiddenScrollBackground()
        .background(HW.background)
        .navigationTitle(service.type)
        .navigationBarTitleDisplayMode(.inline)
    }
}
