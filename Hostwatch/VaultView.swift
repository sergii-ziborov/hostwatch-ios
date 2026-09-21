import SwiftUI
import UIKit

struct VaultView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let site: Site

    @State private var secrets: [VaultSecret] = []
    @State private var grants: [VaultGrant] = []
    @State private var events: [VaultEvent] = []
    @State private var name = ""
    @State private var value = ""
    @State private var detail = ""
    @State private var secretMinutes = 0
    @State private var grantLabel = ""
    @State private var grantMinutes = 60
    @State private var maxReads = 0
    @State private var allowedIPs = ""
    @State private var selected: Set<String> = []
    @State private var issuedToken: String?
    @State private var deleteName: String?
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?

    var body: some View {
        HWStackNavigation {
            Form {
                Section {
                    Text("Secrets are encrypted on \(site.name)'s Hostwatch node. The control plane routes requests but does not store their values or application tokens.")
                        .font(.caption).foregroundStyle(HW.secondary)
                }
                Section("Stored secrets") {
                    if secrets.isEmpty { Text("No managed secrets yet.").foregroundStyle(HW.secondary) }
                    ForEach(secrets) { secret in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(secret.name).font(.system(.headline, design: .monospaced))
                            Text("Version \(secret.version) · \(secret.description.isEmpty ? "No description" : secret.description)")
                                .font(.caption).foregroundStyle(HW.secondary)
                            Text(secret.expiresAt.map { "Expires \($0)" } ?? "No expiry")
                                .font(.caption2).foregroundStyle(HW.secondary)
                            HStack {
                                Button("Rotate") { name = secret.name; detail = secret.description; value = "" }
                                Button("Apply to .env") { Task { await apply(secret.name) } }
                                Button("Delete", role: .destructive) { deleteName = secret.name }
                            }.buttonStyle(.bordered).disabled(busy)
                        }.padding(.vertical, 4)
                    }
                }
                Section("Create or rotate") {
                    TextField("NAME", text: $name).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    TextField("Description", text: $detail)
                    SecureField("New value", text: $value).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Lifetime in minutes (0 = until deleted)", value: $secretMinutes, format: .number).keyboardType(.numberPad)
                    Button(busy ? "Saving…" : "Save encrypted secret") { Task { await save() } }
                        .disabled(busy || name.isEmpty || value.isEmpty || secretMinutes < 0 || secretMinutes > 527_040)
                }
                Section("Application grants") {
                    Text("Issue a scoped token for a server application. It is shown once. Keep it in the application's private runtime configuration.")
                        .font(.caption).foregroundStyle(HW.secondary)
                    TextField("Application label", text: $grantLabel)
                    ForEach(secrets) { secret in
                        Toggle(secret.name, isOn: Binding(get: { selected.contains(secret.name) }, set: { enabled in
                            if enabled { selected.insert(secret.name) } else { selected.remove(secret.name) }
                        }))
                    }
                    TextField("Token lifetime in minutes", value: $grantMinutes, format: .number).keyboardType(.numberPad)
                    TextField("Allowed IPs/CIDRs (optional)", text: $allowedIPs).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Maximum reads (0 = unlimited)", value: $maxReads, format: .number).keyboardType(.numberPad)
                    Button(busy ? "Issuing…" : "Issue token") { Task { await issue() } }
                        .disabled(busy || selected.isEmpty || grantLabel.isEmpty || grantMinutes < 1 || grantMinutes > 129_600 || maxReads < 0)
                }
                if let issuedToken {
                    Section("Copy token now") {
                        Text(issuedToken).font(.system(.caption2, design: .monospaced)).textSelection(.enabled).privacySensitive()
                        Button("Copy token") { UIPasteboard.general.string = issuedToken }
                        Button("Clear from screen") { self.issuedToken = nil }
                    }
                }
                if !grants.isEmpty {
                    Section("Issued grants") {
                        ForEach(grants) { grant in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(grant.label).font(.headline)
                                Text(grant.names.joined(separator: ", ")).font(.caption.monospaced()).foregroundStyle(HW.secondary)
                                Text("\(grant.reads)\(grant.maxReads > 0 ? "/\(grant.maxReads)" : "") reads · expires \(grant.expiresAt)")
                                    .font(.caption2).foregroundStyle(HW.secondary)
                                if !grant.allowedCidrs.isEmpty { Text(grant.allowedCidrs.joined(separator: ", ")).font(.caption2).foregroundStyle(HW.secondary) }
                                if grant.revokedAt == nil { Button("Revoke", role: .destructive) { Task { await revoke(grant.id) } }.disabled(busy) }
                                else { Text("Revoked").font(.caption).foregroundStyle(HW.amber) }
                            }.padding(.vertical, 4)
                        }
                    }
                }
                if !events.isEmpty {
                    Section("Recent access and changes") {
                        ForEach(Array(events.prefix(30).indices), id: \.self) { index in
                            let event = events[index]
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(event.action) · \(event.name ?? event.grantId ?? "")")
                                Text("\(event.time) · \(event.allowed ? "allowed" : "denied") \(event.clientIp ?? "")")
                                    .font(.caption2).foregroundStyle(HW.secondary)
                            }
                        }
                    }
                }
                if let notice { Section { Text(notice).foregroundStyle(HW.teal) } }
                if let error { Section { Text(error).foregroundStyle(HW.red) } }
            }
            .navigationTitle("Managed secrets")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await refresh() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in issuedToken = nil; value = "" }
            .confirmationDialog("Delete \(deleteName ?? "secret")?", isPresented: Binding(get: { deleteName != nil }, set: { if !$0 { deleteName = nil } })) {
                if let deleteName { Button("Delete", role: .destructive) { Task { await remove(deleteName) }; self.deleteName = nil } }
            }
        }
    }

    private func refresh() async {
        do {
            async let a = model.vaultSecrets(site: site.id)
            async let b = model.vaultGrants(site: site.id)
            async let c = model.vaultEvents(site: site.id)
            secrets = try await a; grants = try await b; events = try await c; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        busy = true; error = nil; notice = nil
        do {
            let expiry = secretMinutes == 0 ? "" : ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(secretMinutes * 60)))
            _ = try await model.putVaultSecret(site: site.id, name: name, value: value, description: detail, expiresAt: expiry)
            notice = "Secret saved on the node."; name = ""; value = ""; detail = ""
            await refresh()
        } catch { self.error = error.localizedDescription }
        busy = false
    }
    private func issue() async {
        busy = true; error = nil; notice = nil
        do {
            let ips = allowedIPs.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
            let result = try await model.createVaultGrant(site: site.id, label: grantLabel, names: selected.sorted(), minutes: grantMinutes, allowedCidrs: ips, maxReads: maxReads)
            issuedToken = result.token; grantLabel = ""; selected = []
            notice = "Copy this token now. It cannot be shown again."
            await refresh()
        } catch { self.error = error.localizedDescription }
        busy = false
    }
    private func revoke(_ id: String) async {
        busy = true; error = nil
        do { try await model.revokeVaultGrant(id); notice = "Grant revoked."; await refresh() }
        catch { self.error = error.localizedDescription }
        busy = false
    }
    private func remove(_ name: String) async {
        busy = true; error = nil
        do { try await model.deleteVaultSecret(site: site.id, name: name); notice = "Secret deleted."; await refresh() }
        catch { self.error = error.localizedDescription }
        busy = false
    }
    private func apply(_ name: String) async {
        busy = true; error = nil
        do { try await model.applyVaultSecret(site: site.id, name: name); notice = "Secret applied to .env and project recreated."; await refresh() }
        catch { self.error = error.localizedDescription }
        busy = false
    }
}
