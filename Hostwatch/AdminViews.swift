import SwiftUI

struct EnvironmentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAdd = false
    @State private var deleteVariable: EnvironmentVariable?
    private var site: Site? { model.sites.first(where: { $0.id == model.selectedSite }) ?? model.sites.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { VStack(alignment: .leading) { Eyebrow(text: "Project configuration"); Text(site.map { "\($0.name) environment" } ?? "Environment").font(.title2.bold()); Text("Secret values are never returned after they are saved.").font(.caption).foregroundStyle(HW.secondary) }; Spacer(); Button("Add variable", systemImage: "plus") { showAdd = true }.buttonStyle(.borderedProminent).disabled(site == nil) }
            if model.environment?.managed == false { Label(model.environment?.error ?? "Environment management is unavailable for this project.", systemImage: "exclamationmark.triangle").foregroundStyle(HW.amber).padding(14).panel() }
            ForEach(model.environment?.variables ?? []) { variable in
                HStack(spacing: 14) {
                    Image(systemName: variable.secret ? "lock.fill" : "textformat").foregroundStyle(variable.secret ? HW.amber : HW.teal)
                    VStack(alignment: .leading) { Text(variable.name).font(.system(.headline, design: .monospaced)); Text(variable.secret ? "Secret · value hidden" : "Configuration value").font(.caption).foregroundStyle(HW.secondary) }
                    Spacer(); Button("Replace") { showAdd = true }.buttonStyle(.bordered); Button(role: .destructive) { deleteVariable = variable } label: { Image(systemName: "trash") }
                }.padding(15).panel()
            }
            if model.environment?.variables.isEmpty != false { EmptyState(icon: "key.horizontal", title: "No variables", detail: "Add the first variable for this project.") }
        }
        .sheet(isPresented: $showAdd) { AddEnvironmentVariableView() }
        .confirmationDialog("Delete \(deleteVariable?.name ?? "variable")?", isPresented: Binding(get: { deleteVariable != nil }, set: { if !$0 { deleteVariable = nil } })) { if let variable = deleteVariable { Button("Delete", role: .destructive) { Task { await model.deleteEnvironment(name: variable.name) }; deleteVariable = nil } } } message: { Text("The project may fail to start if it requires this value.") }
    }
}

struct AddEnvironmentVariableView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var value = ""; @State private var reveal = false
    var body: some View {
        HWStackNavigation {
            Form {
                TextField("NAME", text: $name).textInputAutocapitalization(.characters).autocorrectionDisabled().font(.hw(.body, design: .monospaced))
                if reveal { TextField("Value", text: $value).font(.hw(.body, design: .monospaced)) } else { SecureField("Value", text: $value).font(.hw(.body, design: .monospaced)) }
                Toggle("Show while editing", isOn: $reveal)
                Section { Text("Saving replaces an existing variable with the same name. The control plane returns only its name and secret classification afterward.").font(.caption).foregroundStyle(HW.secondary) }
            }.navigationTitle("Environment variable").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await model.setEnvironment(name: name, value: value); dismiss() } }.disabled(name.isEmpty || value.isEmpty) } }
        }
    }
}

struct CodeHealthView: View {
    @EnvironmentObject private var model: AppModel
    @State private var importing = false
    @State private var importProject = ""
    @State private var draft = ""
    @State private var exportText = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) { Eyebrow(text: "Repository evidence"); Text("Code intelligence, Git & vulnerabilities").font(.title2.bold()) }
                Spacer()
                Menu("Markdown") {
                    Button("Import advisories") { importProject = model.selectedSite; importing = true }
                    Button("Copy vulnerability Markdown") { Task { if let value = await model.exportMarkdown(kind: "vulnerability") { exportText = value } } }
                }.buttonStyle(.bordered)
            }
            if !exportText.isEmpty {
                Text(exportText).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(10).padding(12).panel()
            }
            ForEach(model.projects) { project in NavigationLink { CodeProjectDetail(project: project) } label: { CodeProjectRow(project: project) }.buttonStyle(.plain) }
        }
        .sheet(isPresented: $importing) {
            HWStackNavigation {
                Form {
                    Picker("Project", selection: $importProject) {
                        Text("Unscoped").tag("")
                        ForEach(model.sites) { site in Text(site.name).tag(site.id) }
                        ForEach(model.projects.filter { project in !model.sites.contains { $0.id == project.id } }) { project in Text(project.name).tag(project.id) }
                    }
                    TextEditor(text: $draft).font(.system(.caption, design: .monospaced)).frame(minHeight: 220)
                    Section { Text("Paste Hostwatch vulnerability Markdown or lines such as `CVE-2026-1142 (critical)`.").font(.caption).foregroundStyle(HW.secondary) }
                }
                .navigationTitle("Import advisories")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { importing = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") { Task { await model.importMarkdown(kind: "vulnerability", project: importProject, markdown: draft); importing = false; draft = "" } }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.utf8.count > 12_000)
                    }
                }
            }
        }
    }
}

struct CodeProjectRow: View {
    let project: ProjectHealth
    var critical: Int { (project.vulnerabilities ?? []).filter { $0.severity.lowercased() == "critical" }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { VStack(alignment: .leading) { Text(project.name).font(.title3.bold()); Text(project.root).font(.caption).foregroundStyle(HW.secondary).lineLimit(1) }; Spacer(); Text(project.completeness).font(.caption2.bold()).foregroundStyle(project.completeness == "CURRENT" ? HW.teal : HW.amber).padding(.horizontal, 9).padding(.vertical, 5).background((project.completeness == "CURRENT" ? HW.teal : HW.amber).opacity(0.15)).clipShape(Capsule()) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], alignment: .leading, spacing: 10) {
                mini("Code graph", "\(project.graph?.nodes ?? 0) nodes"); mini("Modules", (project.analysis?.modules?.count ?? 0).formatted()); mini("Critical", critical.formatted()); mini("Findings", (project.findings?.count ?? 0).formatted())
            }
            HStack { Text("Inspect graph, Git, quality, packages and vulnerabilities").font(.caption).foregroundStyle(HW.teal); Spacer(); Image(systemName: "chevron.right").foregroundStyle(HW.secondary) }
        }.padding(16).panel()
    }
    private func mini(_ title: String, _ value: String) -> some View { VStack(alignment: .leading) { Text(title).font(.caption2).foregroundStyle(HW.secondary); Text(value).font(.subheadline.bold()) } }
}

struct CodeProjectDetail: View {
    let project: ProjectHealth
    @State private var tab = "Overview"
    var body: some View {
        List {
            Section { Picker("Evidence", selection: $tab) { Text("Overview").tag("Overview"); Text("Graph").tag("Graph"); Text("Git").tag("Git"); Text("Risks").tag("Risks") }.pickerStyle(.segmented) }
            if tab == "Overview" {
                Section("Evidence quality") { HWLabeled("Status", value: project.status); HWLabeled("Completeness", value: project.completeness); HWLabeled("Scanner", value: project.scanner); HWLabeled("Scanned", value: project.scannedAt) }
                Section("Modules") { ForEach(project.analysis?.modules ?? []) { module in VStack(alignment: .leading) { Text(module.path).font(.headline); Text("\(module.files) files · \(module.symbols) symbols").foregroundStyle(HW.secondary) } } }
            } else if tab == "Graph" {
                Section("Code graph") { HWLabeled("Status", value: project.graph?.status ?? "Unavailable"); HWLabeled("Nodes", value: (project.graph?.nodes ?? 0).formatted()); HWLabeled("Edges", value: (project.graph?.edges ?? 0).formatted()); HWLabeled("Build", value: "\((project.graph?.buildMs ?? 0).formatted()) ms") }
                Section("Hot paths") { ForEach(project.analysis?.hotPaths ?? []) { path in VStack(alignment: .leading) { Text(path.label).font(.headline); Text("\(path.file):\(path.line) · score \(path.score.formatted())").foregroundStyle(HW.secondary) } } }
            } else if tab == "Git" {
                Section("Repository") { HWLabeled("Branch", value: project.git?.branch ?? "Unknown"); HWLabeled("Revision", value: project.git?.head ?? project.revision); HWLabeled("Working tree", value: project.git?.dirty == true ? "Dirty" : "Clean"); HWLabeled("Changed files", value: (project.git?.dirtyFiles ?? 0).formatted()); HWLabeled("Last message", value: project.git?.lastMessage ?? "Unavailable") }
            } else {
                Section("Vulnerabilities") { ForEach(project.vulnerabilities ?? []) { vulnerability in NavigationLink { VulnerabilityDetail(project: project, vulnerability: vulnerability) } label: { VStack(alignment: .leading) { Text(vulnerability.id).font(.body.weight(.bold)).foregroundStyle(vulnerability.severity.lowercased() == "critical" ? HW.red : HW.amber); Text("\(vulnerability.package) · \(vulnerability.summary)").font(.caption).foregroundStyle(HW.secondary) } } } }
                Section("Findings") { ForEach(project.findings ?? []) { finding in VStack(alignment: .leading) { Text(finding.message).font(.headline); Text("\(finding.severity.uppercased()) · \(finding.file):\(finding.line)").font(.caption).foregroundStyle(HW.secondary) } } }
                Section("Dead-code candidates") { ForEach(project.analysis?.deadCode ?? []) { item in VStack(alignment: .leading) { Text(item.label).font(.headline); Text("\(item.confidence) confidence · \(item.file):\(item.line) · \(item.reason)").font(.caption).foregroundStyle(HW.secondary) } } }
            }
        }.hwHiddenScrollBackground().background(HW.background).navigationTitle(project.name)
    }
}

struct AutomationsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var runJob: JobState?
    var body: some View {
        VStack(spacing: 12) {
            ForEach(model.jobs) { job in
                HStack(spacing: 14) { Image(systemName: job.lastResult == "success" ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(job.lastResult == "success" ? HW.teal : HW.red); VStack(alignment: .leading, spacing: 5) { Text(job.name).font(.headline); Text("\(job.timerUnit) · next \(job.nextRun) · last \(job.lastResult)").font(.caption).foregroundStyle(HW.secondary) }; Spacer(); Text(job.activeState.uppercased()).font(.caption2.bold()).foregroundStyle(job.activeState == "active" ? HW.teal : HW.amber); Button("Run") { runJob = job }.buttonStyle(.bordered) }.padding(16).panel()
            }
        }.confirmationDialog("Run \(runJob?.name ?? "automation") now?", isPresented: Binding(get: { runJob != nil }, set: { if !$0 { runJob = nil } })) { if let job = runJob { Button("Run now") { Task { await model.runJob(job) }; runJob = nil } } }
    }
}

struct AccessView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAdd = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { VStack(alignment: .leading) { Eyebrow(text: "Company access"); Text("Users and roles").font(.title2.bold()) }; Spacer(); Button("Add user", systemImage: "person.badge.plus") { showAdd = true }.buttonStyle(.borderedProminent) }
            ForEach(model.members) { member in HStack { Circle().fill(HW.panelRaised).frame(width: 44, height: 44).overlay(Text(String(member.user.name.prefix(1))).font(.body.weight(.bold)).foregroundStyle(HW.teal)); VStack(alignment: .leading) { Text(member.user.name).font(.headline); Text(member.user.email).font(.caption).foregroundStyle(HW.secondary) }; Spacer(); Text(member.role.replacingOccurrences(of: "_", with: " ").uppercased()).font(.caption2.bold()).foregroundStyle(HW.amber).padding(.horizontal, 9).padding(.vertical, 5).background(HW.amber.opacity(0.14)).clipShape(Capsule()) }.padding(15).panel() }
            Text("Role changes and removals are audited by the control plane.").font(.footnote).foregroundStyle(HW.secondary)
        }.sheet(isPresented: $showAdd) { AddUserView() }
    }
}

struct AddUserView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var email = ""; @State private var password = ""; @State private var role = "viewer"
    var body: some View { HWStackNavigation { Form { TextField("Name", text: $name); TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never); SecureField("Temporary password · 14+ characters", text: $password); Picker("Role", selection: $role) { Text("Viewer").tag("viewer"); Text("Operator").tag("operator"); Text("Company admin").tag("company_admin") }; Section { Text("The user signs in with this temporary password. Account creation is available only to authorized company owners and is recorded in the audit log.").font(.caption).foregroundStyle(HW.secondary) } }.navigationTitle("Add company user").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Add") { Task { await model.createUser(name: name, email: email, password: password, role: role); dismiss() } }.disabled(name.isEmpty || !email.contains("@") || password.count < 14) } } } }
}

struct OrganizationView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLicense = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { VStack(alignment: .leading) { Eyebrow(text: "Tenant boundary"); Text(model.session.organization?.name ?? "Organization").font(.title2.bold()); Text(model.baseURLText).font(.caption).foregroundStyle(HW.secondary) }; Spacer(); Image(systemName: "building.2.crop.circle.fill").font(.largeTitle).foregroundStyle(HW.teal) }
                .padding(18).panel()
            if let license = model.license {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("License & deployment").font(.title3.bold()); Spacer(); Text(license.state.uppercased()).font(.caption2.bold()).foregroundStyle(license.state == "active" ? HW.teal : HW.amber).padding(.horizontal, 9).padding(.vertical, 5).background((license.state == "active" ? HW.teal : HW.amber).opacity(0.14)).clipShape(Capsule()) }
                    HWLabeled("Mode", value: deploymentTitle(license.deploymentMode)); HWLabeled("Installation", value: license.installationId); HWLabeled("Enforced", value: license.enforced ? "Yes" : "No")
                    if let claims = license.claims { HWLabeled("Customer", value: claims.customer); HWLabeled("Expires", value: claims.expiresAt); HWLabeled("Limits", value: "\(claims.limits.nodes) nodes · \(claims.limits.users) users"); Text(claims.features.joined(separator: " · ")).font(.caption).foregroundStyle(HW.secondary) }
                    Text(license.message).font(.footnote).foregroundStyle(HW.secondary)
                    if model.session.role == "platform_owner" || model.session.role == "company_admin" { Button("Install signed enterprise license") { showLicense = true }.buttonStyle(.bordered) }
                }.padding(18).panel()
            }
            VStack(alignment: .leading, spacing: 10) { Text("Deployment options").font(.title3.bold()); deployment("Managed enterprise", "The complete control plane and collectors are operated for the customer.", "cloud.fill"); deployment("Customer-hosted collector", "The private Go service runs in the customer environment while the signed-in control plane remains managed.", "server.rack") }.padding(18).panel()
            Link("Contact sales and support", destination: URL(string: "mailto:serhii.ziborov@gmail.com")!).buttonStyle(.borderedProminent)
            Link("Privacy policy", destination: URL(string: "https://github.com/sergii-ziborov/hostwatch-ios/blob/codex/initial-product/PRIVACY.md")!)
        }.sheet(isPresented: $showLicense) { InstallLicenseView() }
    }
    private func deploymentTitle(_ value: String) -> String { value == "enterprise" ? "Licensed enterprise" : value == "hosted" ? "Managed enterprise" : value.capitalized }
    private func deployment(_ title: String, _ detail: String, _ icon: String) -> some View { HStack(alignment: .top, spacing: 12) { Image(systemName: icon).foregroundStyle(HW.teal).frame(width: 30); VStack(alignment: .leading) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(HW.secondary) } }.padding(.vertical, 6) }
}

struct InstallLicenseView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    var body: some View { HWStackNavigation { Form { TextEditor(text: $value).font(.system(.caption, design: .monospaced)).frame(minHeight: 240); Section { Text("Paste the signed license generated by the controller REST licensing workflow. The app does not generate or alter license claims.").font(.caption).foregroundStyle(HW.secondary) } }.navigationTitle("Enterprise license").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Install") { Task { await model.installLicense(value); dismiss() } }.disabled(value.isEmpty) } } } }
}
