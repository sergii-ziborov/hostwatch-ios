import SwiftUI

struct SharedVariable: Decodable, Identifiable {
    let id: String
    let nodeId: String
    let name: String
    let description: String
    let kind: String
    let siteIds: [String]
    let syncedVersions: [String: Int]
    let version: Int
}
struct SharedVariableChange: Encodable {
    var nodeId: String? = nil
    var name: String? = nil
    var kind: String? = nil
    var value: String? = nil
    var description: String
    var siteIds: [String]
}
struct SharedVariableResult: Decodable {
    struct Sync: Decodable { let siteId: String; let synced: Bool }
    let item: SharedVariable
    let sync: [Sync]
}

struct SharedVariablesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var items: [SharedVariable] = []
    @State private var editing: SharedVariable?
    @State private var adding = false
    @State private var error = ""
    @State private var deleting: SharedVariable?
    private var nodeID: String { model.selectedNode.isEmpty ? model.nodes.first?.id ?? "local" : model.selectedNode }
    var body: some View {
        List {
            Section {
                Text("Keep one encrypted value for several projects. Saving replaces the selected projects' values and recreates their services. Values are never returned by this screen.").font(.footnote)
                Button("Add shared variable", systemImage: "plus") { adding = true }
            }
            ForEach(items) { item in
                Section(item.name) {
                    Text("\(item.kind.capitalized) · v\(item.version)")
                    ForEach(item.siteIds, id: \.self) { id in
                        HStack {
                            Text(model.sites.first { $0.id == id }?.name ?? id)
                            Spacer()
                            Text(item.syncedVersions[id] == item.version ? "Synced" : "Needs sync")
                                .foregroundStyle(item.syncedVersions[id] == item.version ? HW.teal : HW.amber)
                        }
                    }
                    Button("Edit / rotate") { editing = item }
                    Button("Retry pending sync") { Task { await retry(item) } }
                    Button("Stop sharing", role: .destructive) { deleting = item }
                }
            }
            if !error.isEmpty { Section { Text(error).foregroundStyle(HW.red) } }
        }
        .navigationTitle("Shared variables")
        .task(id: nodeID) { await refresh() }
        .sheet(isPresented: $adding) { SharedVariableEditor(nodeID: nodeID, onSave: { await refresh() }).environmentObject(model) }
        .sheet(item: $editing) { item in SharedVariableEditor(nodeID: nodeID, item: item, onSave: { await refresh() }).environmentObject(model) }
        .confirmationDialog("Stop managing \(deleting?.name ?? "this variable")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Stop sharing", role: .destructive) {
                if let item = deleting { Task { do { try await model.deleteSharedVariable(item.id); await refresh() } catch { self.error = error.localizedDescription } } }
                deleting = nil
            }
        } message: { Text("Existing copies stay in each project's environment and vault. Delete them there if needed.") }
    }
    private func refresh() async { do { items = try await model.sharedVariables(nodeID: nodeID); error = "" } catch { self.error = error.localizedDescription } }
    private func retry(_ item: SharedVariable) async {
        do { let result = try await model.syncSharedVariable(item.id); await refresh(); error = result.sync.contains { !$0.synced } ? "Some projects could not be updated. They remain marked Needs sync." : "" }
        catch { self.error = error.localizedDescription }
    }
}

private struct SharedVariableEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let nodeID: String
    var item: SharedVariable? = nil
    let onSave: () async -> Void
    @State private var name = ""
    @State private var kind = "secret"
    @State private var value = ""
    @State private var description = ""
    @State private var sites: Set<String> = []
    @State private var busy = false
    @State private var error = ""
    var body: some View {
        HWStackNavigation {
            Form {
                Section("Variable") {
                    TextField("Name", text: $name).textInputAutocapitalization(.characters).autocorrectionDisabled().disabled(item != nil)
                    Picker("Type", selection: $kind) { Text("Secret").tag("secret"); Text("Text").tag("text") }.disabled(item != nil)
                    TextField("Description", text: $description)
                    SecureField(item == nil ? "Value" : "New value (empty keeps current)", text: $value).textContentType(.newPassword)
                }
                Section("Projects to update") {
                    ForEach(model.sites) { site in
                        Toggle(site.name, isOn: Binding(get: { sites.contains(site.id) }, set: { if $0 { sites.insert(site.id) } else { sites.remove(site.id) } }))
                    }
                }
                Section { Text("Save replaces existing values and recreates each selected service. Removing a project stops future updates; its current copy remains.").font(.footnote) }
                if !error.isEmpty { Section { Text(error).foregroundStyle(HW.red) } }
            }
            .navigationTitle(item == nil ? "Shared variable" : "Edit / rotate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button(busy ? "Syncing…" : "Save and sync") { Task { await save() } }.disabled(busy || sites.isEmpty || name.isEmpty || (item == nil && value.isEmpty)) }
            }
        }
        .onAppear { if let item { name = item.name; kind = item.kind; description = item.description; sites = Set(item.siteIds) } else if !model.selectedSite.isEmpty { sites = [model.selectedSite] } }
        .interactiveDismissDisabled(busy)
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            let change = SharedVariableChange(nodeId: item == nil ? nodeID : nil, name: item == nil ? name : nil, kind: item == nil ? kind : nil, value: value.isEmpty ? nil : value, description: description, siteIds: sites.sorted())
            let result = try await model.saveSharedVariable(id: item?.id, change: change)
            value = ""; await onSave()
            if result.sync.contains(where: { !$0.synced }) { error = "Saved, but some projects need another sync. Close this screen and retry those projects." }
            else { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}
