import SwiftUI

struct SiteMemoryGauge: View {
    let site: Site

    private var tone: Color {
        switch site.memoryPressure {
        case .nearPeak: return HW.red
        case .overflow, .approachingNormal: return HW.amber
        case .normal, .unavailable: return HW.teal
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if site.peakMemoryLimit > 0 {
                GeometryReader { geometry in
                    let width = max(1, geometry.size.width)
                    ZStack(alignment: .leading) {
                        Capsule().fill(HW.border)
                        Capsule().fill(tone)
                            .frame(width: width * min(1, max(0, site.memoryBytes / site.peakMemoryLimit)))
                        if site.peakMemoryLimit > site.normalMemoryLimit {
                            Rectangle().fill(.white)
                                .frame(width: 2)
                                .offset(x: width * site.normalMemoryLimit / site.peakMemoryLimit)
                        }
                    }
                }
                .frame(height: 8)
                HStack {
                    Text("Normal \(Format.bytes(site.normalMemoryLimit))")
                    Spacer()
                    Text("Peak \(Format.bytes(site.peakMemoryLimit))")
                }
                .font(.caption2)
                .foregroundStyle(HW.secondary)
            }
            Text(site.memoryStatus).font(.caption.bold()).foregroundStyle(tone)
            if let note = site.memoryNote, !note.isEmpty, site.memoryPressure != .normal {
                Text(note).font(.caption2).foregroundStyle(HW.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(site.name) memory: \(Format.bytes(site.memoryBytes)). \(site.memoryStatus). Normal \(Format.bytes(site.normalMemoryLimit)), peak \(Format.bytes(site.peakMemoryLimit)).")
    }
}

struct SiteMemoryLimitEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let site: Site

    @State private var limits: SiteLimits?
    @State private var normalMiB: Int64 = 0
    @State private var peakMiB: Int64 = 0
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    private var update: SiteLimitUpdate? {
        guard let limits else { return nil }
        return try? SiteLimitUpdate(limits: limits, normalMiB: normalMiB, peakMiB: peakMiB)
    }

    var body: some View {
        HWStackNavigation {
            Form {
                Section("Current policy") {
                    HWLabeled("Normal", value: Format.bytes(Double(limits?.normal ?? Int64(site.normalMemoryLimit))))
                    HWLabeled("Peak", value: Format.bytes(Double(limits?.peak ?? Int64(site.peakMemoryLimit))))
                    HWLabeled("Mode", value: site.memoryMode == "overflow" ? "Peak active" : "Normal")
                    Text("Peak memory is granted automatically near 80% of normal usage only when the host has free capacity and attack mitigation is inactive.")
                        .font(.footnote).foregroundStyle(HW.secondary)
                }
                Section("Memory limits in MiB") {
                    TextField("Normal", value: $normalMiB, format: .number).keyboardType(.numberPad)
                        .accessibilityIdentifier("normalMemoryMiB")
                    TextField("Peak", value: $peakMiB, format: .number).keyboardType(.numberPad)
                        .accessibilityIdentifier("peakMemoryMiB")
                    Text("Peak equal to normal disables automatic overflow. Existing request-rate, CPU and process limits are preserved.")
                        .font(.footnote).foregroundStyle(HW.secondary)
                }
                if loading { Section { ProgressView("Loading limits…") } }
                if let error { Section { Text(error).foregroundStyle(HW.red) } }
            }
            .navigationTitle("Memory limits")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(saving || update == nil || loading)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let current = try await model.siteLimits(site)
            limits = current
            normalMiB = Int64((Double(current.normal) / 1_048_576).rounded())
            peakMiB = Int64((Double(current.peak) / 1_048_576).rounded())
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        guard let update else { error = SiteLimitInputError.invalidMemory.localizedDescription; return }
        saving = true
        defer { saving = false }
        do {
            limits = try await model.setSiteLimits(site, update: update)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
