import SwiftUI

struct TLSView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pendingLineage: String?

    private var selected: TLSSite? {
        guard let snapshot = model.tlsSite else { return nil }
        let site = model.selectedSite.isEmpty ? model.sites.first?.id : model.selectedSite
        return snapshot.siteId == site ? snapshot : nil
    }

    private var isOwner: Bool { ["owner", "platform_owner"].contains(model.session.role ?? "") }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Certificate files, origin HTTPS and public HTTPS are checked separately.")
                .font(.subheadline).foregroundStyle(HW.secondary)
            if let notice = model.tlsNotice {
                Label(notice, systemImage: "checkmark.circle")
                    .font(.subheadline).foregroundStyle(HW.teal).padding(14).frame(maxWidth: .infinity, alignment: .leading).panel()
            }
            if let site = selected {
                scheduler(site)
                if !site.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Needs attention", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(HW.amber)
                        ForEach(site.warnings, id: \.self) { warning in Text("• \(warning)").font(.subheadline) }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panel()
                }
                Text("Certificate files").font(.title3.bold())
                if site.certificates.isEmpty {
                    Text("No local Certbot certificate is bound to this site. Public HTTPS may be managed externally.")
                        .foregroundStyle(HW.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).panel()
                }
                ForEach(site.certificates) { certificate in certificateCard(certificate, siteID: site.siteId) }
                Text("Served HTTPS").font(.title3.bold())
                ForEach(site.observations) { observation in observationCard(observation) }
                Text("A successful timer check does not prove a certificate changed or was served. An unreachable probe does not prove a certificate is invalid.")
                    .font(.footnote).foregroundStyle(HW.secondary)
            } else if model.errorMessage != nil {
                Text("SSL / TLS inventory is unavailable on this node. The agent may need an update.")
                    .foregroundStyle(HW.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).panel()
            } else {
                ProgressView("Checking SSL / TLS…").frame(maxWidth: .infinity).padding(24).panel()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog("Check renewal when due?", isPresented: Binding(get: { pendingLineage != nil }, set: { if !$0 { pendingLineage = nil } }), titleVisibility: .visible) {
            if let lineage = pendingLineage, let site = selected {
                Button("Start Certbot check for \(lineage)") {
                    pendingLineage = nil
                    Task { await model.checkTLSRenewal(site: site.siteId, lineage: lineage) }
                }
            }
            Button("Cancel", role: .cancel) { pendingLineage = nil }
        } message: {
            Text("The existing Certbot configuration remains the renewal owner. Nginx is reloaded only if the certificate changes.")
        }
    }

    private func scheduler(_ site: TLSSite) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Renewal control", systemImage: "arrow.clockwise.shield").font(.headline)
            HWLabeled("Management", value: site.management == "certbot_existing" ? "Existing Certbot" : site.management)
            HWLabeled("Scheduler", value: site.scheduler.enabled ? "Timer enabled" : site.scheduler.configured ? "Timer inactive" : "Not verified")
            HWLabeled("Last result", value: site.scheduler.lastResult ?? "Unknown")
            HWLabeled("Next check", value: formatted(site.scheduler.nextCheck))
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panel()
    }

    private func certificateCard(_ certificate: TLSCertificate, siteID: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(certificate.lineage).font(.headline); Spacer(); status(certificate.status) }
            Text(certificate.domains.joined(separator: " · ")).font(.subheadline).foregroundStyle(HW.secondary)
            HWLabeled("Expires", value: formatted(certificate.notAfter))
            HWLabeled("Issuer", value: certificate.issuer)
            HWLabeled("File fingerprint", value: shortened(certificate.fingerprint))
            HWLabeled("Last renewal event", value: certificate.lastOperation.map { "\($0.result.replacingOccurrences(of: "_", with: " ")) · \(formatted($0.completedAt ?? $0.startedAt))" } ?? "None recorded")
            if isOwner && certificate.renewalOwner == "certbot" {
                Button("Check renewal when due") { pendingLineage = certificate.lineage }
                    .buttonStyle(.borderedProminent).tint(HW.teal)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panel()
    }

    private func observationCard(_ observation: TLSObservation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(observation.domain).font(.headline); Spacer(); status(observation.status) }
            Text(observation.boundary == "origin" ? "Origin · local Nginx" : "Public · visitor endpoint")
                .font(.caption).foregroundStyle(HW.secondary)
            HWLabeled("Expires", value: formatted(observation.notAfter))
            HWLabeled("Hostname", value: observation.hostnameMatch ? "Matches" : "Not verified")
            HWLabeled("Trust", value: observation.trusted ? "Publicly trusted" : "Not verified")
            HWLabeled("Served fingerprint", value: shortened(observation.fingerprint))
            if let error = observation.error { Text(error).font(.caption).foregroundStyle(HW.secondary) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panel()
    }

    private func status(_ value: String) -> some View {
        Text(value.replacingOccurrences(of: "_", with: " ")).font(.caption.bold())
            .foregroundStyle(value == "valid" ? HW.teal : HW.amber)
    }

    private func shortened(_ value: String?) -> String {
        guard let value, value.count > 24 else { return value ?? "Not observed" }
        return "\(value.prefix(16))…\(value.suffix(8))"
    }

    private func formatted(_ value: String?) -> String {
        guard let value, let date = ISO8601DateFormatter().date(from: value) else { return value ?? "Not recorded" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
