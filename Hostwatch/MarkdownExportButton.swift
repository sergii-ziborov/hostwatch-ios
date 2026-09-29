import SwiftUI
import UniformTypeIdentifiers

struct MarkdownExportButton: View {
    @EnvironmentObject private var model: AppModel
    var kind = "error"
    var site: String? = nil
    @State private var file: URL?
    @State private var sharing = false
    @State private var busy = false
    var body: some View {
        Button { Task { await export() } } label: {
            Label(busy ? "Exporting…" : "Export .md", systemImage: "square.and.arrow.up")
        }.disabled(busy)
        .sheet(isPresented: $sharing, onDismiss: {
            if let file { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            file = nil
        }) { if let file { HWActivitySheet(items: [file]) } }
    }
    private func export() async {
        busy = true; defer { busy = false }
        guard let text = await model.exportMarkdown(kind: kind, site: site) else { return }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("hostwatch-\(kind)-\(model.hours)h.md")
            try text.write(to: url, atomically: true, encoding: .utf8)
            file = url; sharing = true
        } catch { model.errorMessage = error.localizedDescription }
    }
}
