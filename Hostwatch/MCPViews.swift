import SwiftUI

struct MCPView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let snap = model.mcpSnapshot {
            VStack(alignment: .leading, spacing: 18) {
                governanceCard(snap)
                computersCard(snap.clients)
                historyCard(snap.history)
            }
        } else {
            EmptyState(icon: "antenna.radiowaves.left.and.right", title: "MCP not loaded", detail: "Pull to refresh after choosing a node. Older agents do not report computers or history yet.")
        }
    }

    private func governanceCard(_ snap: MCPSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Company node")
            Text("What the AI may do").font(.title3.bold())
            Text("The node enforces these limits for Hostwatch MCP calls. Protect the agent administrator token: its holder can call the API directly.")
                .font(.caption).foregroundStyle(HW.secondary)
            Toggle("Allow MCP on this node", isOn: bind(\.enabled, snap.governance))
            Toggle("Allow reads", isOn: bind(\.allowObserve, snap.governance)).disabled(!snap.governance.enabled)
            Toggle("Allow changes", isOn: bind(\.allowMutate, snap.governance)).disabled(!snap.governance.enabled)
            Toggle("Allow secret insertion through MCP", isOn: bind(\.allowSecretInsertion, snap.governance))
                .disabled(!snap.governance.enabled || !snap.governance.allowMutate)
            Text("Off by default. Applies to local secret binding, publish and vault insertion. Hostwatch checks this on the node for every MCP call.")
                .font(.caption).foregroundStyle(HW.secondary)
            HStack {
                Text("Changes per hour").foregroundStyle(HW.secondary)
                Spacer()
                Stepper(snap.governance.maxMutationsPerHour == 0 ? "Unlimited" : "\(snap.governance.maxMutationsPerHour)", value: bind(\.maxMutationsPerHour, snap.governance), in: 0...200)
            }
            HStack {
                Text("Stale after").foregroundStyle(HW.secondary)
                Spacer()
                Stepper(staleLabel(snap.governance.staleAfterSeconds), value: bind(\.staleAfterSeconds, snap.governance), in: 60...86400, step: 60)
            }
            Text("Blocked tools").font(.headline)
            Text("On means the AI cannot call that tool on this node.")
                .font(.caption).foregroundStyle(HW.secondary)
            ForEach(snap.knownTools.filter { $0.kind == "mutate" }) { tool in
                Toggle(tool.title, isOn: deniedBinding(tool.name, snap.governance)).disabled(!snap.governance.enabled)
            }
        }
        .padding(16)
        .panel()
    }

    private func computersCard(_ clients: [MCPClientInfo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Connected computers")
            Text("PCs talking to this company through MCP").font(.title3.bold())
            if clients.isEmpty {
                Text("No MCP session has registered yet. The next Cursor connection will appear here.")
                    .font(.footnote).foregroundStyle(HW.secondary)
            }
            ForEach(clients) { client in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(client.hostname).font(.headline)
                        Spacer()
                        Text(client.stale ? "STALE" : "LIVE").font(.caption2.bold()).foregroundStyle(client.stale ? HW.amber : HW.teal)
                    }
                    Text("\(client.username) · \(client.app)\(client.remoteIp.map { " · \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(HW.secondary)
                    Text("Last \(client.lastTool ?? "session") · \(client.observeCalls) reads · \(client.mutateCalls) changes · seen \(ChartTime.parse(client.lastSeen)?.formatted(date: .omitted, time: .shortened) ?? client.lastSeen)")
                        .font(.caption2).foregroundStyle(HW.secondary)
                }
                .padding(12)
                .background(HW.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .panel()
    }

    private func historyCard(_ events: [MCPHistoryEvent]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "What the AI did")
            Text("Tool history").font(.title3.bold())
            if events.isEmpty {
                Text("No MCP tool call has been recorded on this node yet.")
                    .font(.footnote).foregroundStyle(HW.secondary)
            }
            PagedRows(items: events) { event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(event.tool).font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        Spacer()
                        Text(event.status.uppercased()).font(.caption2.bold()).foregroundStyle(event.status == "allowed" ? HW.teal : HW.red)
                    }
                    Text("\(event.hostname) · \(event.kind) · \(ChartTime.parse(event.time)?.formatted(date: .abbreviated, time: .standard) ?? event.time)")
                        .font(.caption).foregroundStyle(HW.secondary)
                    if let error = event.error, !error.isEmpty {
                        Text(error).font(.caption).foregroundStyle(HW.amber)
                    }
                    if let summary = event.summary, !summary.isEmpty {
                        Text(summary).font(.caption2.monospaced()).foregroundStyle(HW.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .panel()
    }

    private func bind(_ keyPath: WritableKeyPath<MCPGovernance, Bool>, _ current: MCPGovernance) -> Binding<Bool> {
        Binding(
            get: { model.mcpSnapshot?.governance[keyPath: keyPath] ?? current[keyPath: keyPath] },
            set: { value in
                guard var next = model.mcpSnapshot?.governance else { return }
                next[keyPath: keyPath] = value
                Task { await model.saveMCPGovernance(next) }
            }
        )
    }

    private func bind(_ keyPath: WritableKeyPath<MCPGovernance, Int>, _ current: MCPGovernance) -> Binding<Int> {
        Binding(
            get: { model.mcpSnapshot?.governance[keyPath: keyPath] ?? current[keyPath: keyPath] },
            set: { value in
                guard var next = model.mcpSnapshot?.governance else { return }
                next[keyPath: keyPath] = value
                Task { await model.saveMCPGovernance(next) }
            }
        )
    }

    private func staleLabel(_ seconds: Int) -> String {
        if seconds < 120 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return "\(seconds / 3600) h"
    }

    private func deniedBinding(_ tool: String, _ current: MCPGovernance) -> Binding<Bool> {
        Binding(
            get: { (model.mcpSnapshot?.governance.deniedTools ?? current.deniedTools).contains(tool) },
            set: { blocked in
                guard var next = model.mcpSnapshot?.governance else { return }
                if blocked {
                    if !next.deniedTools.contains(tool) { next.deniedTools.append(tool) }
                } else {
                    next.deniedTools.removeAll { $0 == tool }
                }
                Task { await model.saveMCPGovernance(next) }
            }
        )
    }
}
