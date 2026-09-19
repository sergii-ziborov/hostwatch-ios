import SwiftUI

struct FleetView: View {
    @EnvironmentObject private var model: AppModel
    @State private var settings: HybridSettings?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Hybrid fleet")
                Text("Edge, home compute, freshness").font(.title2.bold())
                Text("Home jobs wait for a fresh heartbeat. A public IP change is recorded; work stays off until the node is current, has disk, and has a free slot.")
                    .font(.caption).foregroundStyle(HW.secondary)
            }.padding(18).panel()

            if let admission = model.hybridAdmission {
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(admission.accept ? HW.teal : HW.amber).frame(width: 10, height: 10).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(admission.accept ? "Home can accept deferred work" : "Home is not admitting work")
                            .font(.headline)
                        Text(admission.reason).font(.caption).foregroundStyle(HW.secondary)
                        Text("Leases \(admission.activeLeases)/\(admission.maxJobs) · \(admission.homeFresh ? "fresh" : "stale")")
                            .font(.caption2).foregroundStyle(HW.secondary)
                    }
                    Spacer()
                }.padding(16).panel()
            }

            if model.hybridPeers.isEmpty && model.fleetLinks.isEmpty && model.hybridError != nil {
                EmptyState(icon: "laptopcomputer.and.iphone", title: "Fleet API unavailable", detail: model.hybridError ?? "This node does not expose hybrid peers yet.")
            } else if model.hybridPeers.isEmpty {
                EmptyState(icon: "laptopcomputer.and.iphone", title: "No home node announced", detail: "Configure a home-compute peer on the agent. Heartbeats keep its public IP, disk and load current.")
            }

            ForEach(model.hybridPeers) { peer in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(peer.id).font(.headline)
                            Text(peer.kind).font(.caption).foregroundStyle(HW.secondary)
                        }
                        Spacer()
                        Text(peer.fresh ? "FRESH" : "STALE")
                            .font(.caption2.bold())
                            .foregroundStyle(peer.fresh ? HW.teal : HW.amber)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background((peer.fresh ? HW.teal : HW.amber).opacity(0.16))
                            .clipShape(Capsule())
                    }
                    if peer.ipChanged, let from = peer.previousIp, let to = peer.publicIp {
                        Label("Public IP changed \(from) → \(to)", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption).foregroundStyle(HW.amber)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                        mini("Public IP", peer.publicIp ?? "—")
                        mini("Tunnel", peer.tunnelIp ?? "—")
                        mini("CPU", peer.cpuPercent.map(Format.percent) ?? "—")
                        mini("Disk free", peer.diskFreeBytes.map { Format.bytes($0) } ?? "—")
                        mini("Running jobs", (peer.runningJobs ?? 0).formatted())
                        mini("Last seen", ChartTime.parse(peer.lastSeen ?? "")?.formatted(date: .omitted, time: .shortened) ?? "never")
                    }
                }.padding(16).panel()
            }

            if !model.fleetLinks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Link layers").font(.headline)
                    ForEach(model.fleetLinks) { link in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(link.id).font(.subheadline.bold())
                            ForEach(link.layers, id: \.name) { layer in
                                HStack {
                                    Circle().fill(layer.status == "ok" ? HW.teal : layer.status == "not_applicable" ? HW.secondary : HW.red)
                                        .frame(width: 7, height: 7)
                                    Text(layer.name).font(.caption)
                                    Spacer()
                                    Text(layer.detail?.isEmpty == false ? layer.detail! : layer.status)
                                        .font(.caption2).foregroundStyle(HW.secondary).lineLimit(1)
                                }
                            }
                        }.padding(12).background(HW.panelRaised).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }.padding(16).panel()
            }

            if let value = settings ?? model.hybridSettings {
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow(text: "Home admission")
                    Text("Load scaling").font(.title3.bold())
                    stepper("Max concurrent home jobs", value: Binding(
                        get: { Double(value.homeMaxJobs) },
                        set: { settings?.homeMaxJobs = Int($0) }
                    ), range: 1...8)
                    slider("Reserved free disk", value: Binding(
                        get: { Double(value.homeMinDiskBytes) / 1_073_741_824 },
                        set: { settings?.homeMinDiskBytes = Int($0 * 1_073_741_824) }
                    ), range: 5...200, suffix: "GB")
                    slider("Stale after", value: Binding(
                        get: { Double(value.homeStaleAfterSeconds) },
                        set: { settings?.homeStaleAfterSeconds = Int($0) }
                    ), range: 15...300, suffix: "s")
                    slider("Keep-alive", value: Binding(
                        get: { Double(value.keepAliveSeconds) },
                        set: { settings?.keepAliveSeconds = Int($0) }
                    ), range: 5...120, suffix: "s")
                    Button("Apply home settings") {
                        if let settings { Task { await model.saveHybridSettings(settings) } }
                    }.buttonStyle(.borderedProminent)
                }
                .padding(18).panel()
                .onAppear { if settings == nil { settings = model.hybridSettings } }
            }
        }
    }

    private func mini(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption2).foregroundStyle(HW.secondary)
            Text(value).font(.caption.bold()).lineLimit(1)
        }
    }

    private func stepper(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue))").monospacedDigit().foregroundStyle(HW.teal) }
            Slider(value: value, in: range, step: 1)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue)) \(suffix)").monospacedDigit().foregroundStyle(HW.teal) }
            Slider(value: value, in: range)
        }
    }
}
