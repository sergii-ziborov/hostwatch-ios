import SwiftUI

struct CleanupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirming = false
    @State private var pendingKind = ""

    private var canClean: Bool { ["platform_owner", "owner", "admin"].contains(model.session.role ?? "") && !model.fixtures }
    private var available: [CleanupTarget] { model.cleanupPreview?.targets.filter { $0.available && $0.items > 0 } ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Host maintenance")
                    Text("Safe cleanup").font(.title2.bold())
                    Text("Preview fixed, allowlisted caches before removing them.").font(.footnote).foregroundStyle(HW.secondary)
                }
                Spacer()
                Button { Task { await model.refreshCleanup() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.bordered).disabled(model.cleanupLoading)
                    .accessibilityLabel("Refresh cleanup preview")
            }
            if model.cleanupLoading { ProgressView("Checking eligible cache files…").tint(HW.teal) }
            if let error = model.cleanupError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(HW.red)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).panel()
            }
            if let notice = model.cleanupNotice {
                Label(notice, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(HW.teal)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).panel()
            }
            if let preview = model.cleanupPreview {
                let fileBytes = preview.targets.filter { $0.kind != "docker-build-cache" && $0.available }.reduce(0.0) { $0 + $1.bytes }
                StatCard(title: "Eligible package & manual caches", value: Format.bytes(fileBytes), detail: "Docker virtual layer sizes are excluded from this total", icon: "internaldrive")
                ForEach(preview.targets) { target in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(target.name).font(.headline)
                                Text(target.kind == "docker-build-cache" ? "Docker build records" : target.path)
                                    .font(.caption.monospaced()).foregroundStyle(HW.teal).textSelection(.enabled)
                            }
                            Spacer(minLength: 8)
                            Text(Format.bytes(target.bytes)).font(.headline.monospacedDigit())
                        }
                        Text("\(target.items) \(target.kind == "docker-build-cache" ? "records · virtual size" : "files")")
                            .font(.caption).foregroundStyle(HW.secondary)
                        Text(target.description).font(.footnote)
                        Text(target.consequence).font(.caption).foregroundStyle(HW.secondary)
                        if let error = target.error { Text("Preview unavailable: \(error)").font(.caption).foregroundStyle(HW.red) }
                        Button("Clean this cache") { pendingKind = target.kind; confirming = true }
                            .buttonStyle(.bordered).disabled(!canClean || model.cleanupLoading || !target.available || target.items == 0)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panel()
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Protected data").font(.headline)
                    Text("Running containers, images, volumes, databases, backups, logs and arbitrary paths are never removed. APT packages may need to be downloaded again; Docker builds may take longer. Shared Docker layer sizes are not a promise of freed space.")
                        .font(.footnote).foregroundStyle(HW.secondary)
                    Button("Clean all eligible caches", role: .destructive) { pendingKind = "all"; confirming = true }
                        .buttonStyle(.bordered).disabled(!canClean || model.cleanupLoading || available.isEmpty)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panel()
                if !canClean { Text("This account has read-only access to cleanup.").font(.footnote).foregroundStyle(HW.secondary) }
            } else if !model.cleanupLoading {
                EmptyState(icon: "sparkles.rectangle.stack", title: "Cleanup preview unavailable", detail: "Refresh to inspect safe cache targets on the selected node.")
            }
        }
        .confirmationDialog("Clean \(pendingKind == "all" ? "all eligible caches" : "this cache")?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Clean approved cache", role: .destructive) { Task { await model.cleanCache(pendingKind) } }
        } message: {
            Text("Only old package/manual caches and unused Docker build records are eligible. This can slow later downloads or builds.")
        }
        .task { if model.cleanupPreview == nil && !model.cleanupLoading { await model.refreshCleanup() } }
    }
}
