import SwiftUI
import UniformTypeIdentifiers

struct ErrorsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var importing = false
    @State private var importKind = "error"
    @State private var importProject = ""
    @State private var importingFile = false
    @State private var draft = ""
    @State private var exportText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "HTTP failures by project")
                    Text("Errors").font(.title2.bold())
                    Text("Open an error to see the project, earlier matches, and nearby container logs when the agent can attribute a service.").font(.footnote).foregroundStyle(HW.secondary)
                    NavigationLink { ErrorExplorerView() } label: { Text("Status and path aggregates").font(.caption).foregroundStyle(HW.teal) }
                }
                Spacer()
                Menu("Import / export") {
                    Button("Import error Markdown") { importKind = "error"; importProject = model.selectedSite; importing = true }
                    Button("Import vulnerability Markdown") { importKind = "vulnerability"; importProject = model.selectedSite; importing = true }
                    Button("Copy error Markdown") { Task { if let value = await model.exportMarkdown(kind: "error") { exportText = value } } }
                    Button("Copy vulnerability Markdown") { Task { if let value = await model.exportMarkdown(kind: "vulnerability") { exportText = value } } }
                }.buttonStyle(.bordered)
            }
            if let notice = model.importNotice {
                Label(notice, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(HW.teal)
            }
            if !exportText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Markdown ready to copy").font(.headline)
                    Text(exportText).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(12)
                }.padding(14).panel()
            }
            let groups = model.groupedErrors()
            if groups.isEmpty {
                EmptyState(icon: "exclamationmark.octagon", title: "No retained project errors", detail: "New 4xx/5xx requests appear here as the live buffer fills. Imported Markdown notes stay below.")
            } else {
                ForEach(groups) { group in
                    NavigationLink { ErrorProjectDetail(group: group) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(group.projectName).font(.headline)
                                Spacer()
                                Text("\(group.count) errors").font(.subheadline.bold()).foregroundStyle(HW.red)
                            }
                            Text(statusSummary(group)).font(.caption).foregroundStyle(HW.secondary)
                            Text("Open project history →").font(.caption2).foregroundStyle(HW.teal)
                        }.padding(16).panel()
                    }.buttonStyle(.plain)
                }
            }
            if !model.importedNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Imported notes").font(.headline)
                    ForEach(model.importedNotes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title).font(.subheadline.bold())
                            Text("\(note.kind) · \(note.projectId ?? "unscoped") · \(note.severity ?? "")").font(.caption).foregroundStyle(HW.secondary)
                            if let detail = note.detail { Text(detail).font(.caption).foregroundStyle(HW.secondary) }
                        }.padding(12).panel()
                    }
                }
            }
        }
        .task { await model.refreshErrors() }
        .sheet(isPresented: $importing) {
            HWStackNavigation {
                Form {
                    Picker("Kind", selection: $importKind) { Text("Errors").tag("error"); Text("Vulnerabilities").tag("vulnerability") }
                    Picker("Project", selection: $importProject) {
                        Text("Unscoped").tag("")
                        ForEach(model.sites) { site in Text(site.name).tag(site.id) }
                        ForEach(model.projects.filter { project in !model.sites.contains { $0.id == project.id } }) { project in Text(project.name).tag(project.id) }
                    }
                    Button("Open .md file") { importingFile = true }
                    TextEditor(text: $draft).font(.system(.caption, design: .monospaced)).frame(minHeight: 220)
                    Section { Text("Paste Hostwatch Markdown or lines such as `502 GET /api` and `CVE-2026-1142 (critical)`.").font(.caption).foregroundStyle(HW.secondary) }
                }
                .navigationTitle("Import Markdown")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { importing = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") { Task { await model.importMarkdown(kind: importKind, project: importProject, markdown: draft); importing = false; draft = "" } }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.utf8.count > 12_000)
                    }
                }
            }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText, .plainText]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                guard data.count <= 12_000, let body = String(data: data, encoding: .utf8) else {
                    model.errorMessage = "Markdown must be UTF-8 and at most 12 KB."
                    return
                }
                draft = body
            } catch { model.errorMessage = error.localizedDescription }
        }
    }

    private func statusSummary(_ group: ErrorProjectGroup) -> String {
        let parts = (group.statuses ?? [:]).sorted { $0.value > $1.value }.map { "HTTP \($0.key) × \($0.value)" }
        return parts.isEmpty ? "\(group.count) retained failures" : parts.joined(separator: " · ")
    }
}

struct ErrorProjectDetail: View {
    let group: ErrorProjectGroup
    var body: some View {
        List {
            Section("Project") {
                HWLabeled("Name", value: group.projectName)
                HWLabeled("Retained errors", value: group.count.formatted())
            }
            Section("Retained failures") {
                PagedRows(items: group.requests) { request in
                    NavigationLink { RequestDetailView(request: request) } label: { RequestRow(request: request) }
                }
            }
        }
        .hwHiddenScrollBackground()
        .background(HW.background)
        .navigationTitle(group.projectName)
    }
}

struct RequestErrorContextCard: View {
    let context: ErrorContext?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Project and nearby logs").font(.headline)
            if let context {
                HWLabeled("Project", value: context.projectName)
                if let hint = context.crashHint, !hint.isEmpty {
                    Label(hint, systemImage: "exclamationmark.octagon.fill").font(.footnote).foregroundStyle(HW.red)
                }
                if let source = context.logSource { Text("Log source · \(source)").font(.caption).foregroundStyle(HW.secondary) }
                if let error = context.logError, !error.isEmpty { Text(error).font(.caption).foregroundStyle(HW.amber) }
                if !context.logs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(context.logs) { line in
                            Text("\(line.stream)  \(line.text)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.crash == true ? HW.red : HW.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                if !context.previous.isEmpty {
                    Text("Previous matches").font(.subheadline.bold())
                    ForEach(context.previous) { item in
                        NavigationLink { RequestDetailView(request: item) } label: { RequestRow(request: item) }
                    }
                }
            } else {
                ProgressView("Loading project, previous errors and container logs…").tint(HW.teal)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panel()
    }
}
