import UIKit

enum TopologyLayerKind: String {
    case runtime, module, community, hotspot, graph, scan, git, host, service
}

enum TopologyServiceRole: String {
    case frontend, backend, worker, database, cache

    var title: String {
        switch self {
        case .frontend: "Frontend"
        case .backend: "Backend"
        case .worker: "Worker"
        case .database: "Database"
        case .cache: "Cache"
        }
    }

    static func of(siteID: String) -> TopologyServiceRole? {
        guard siteID.contains("/"), let last = siteID.split(separator: "/").last else { return nil }
        let token = last.split(separator: "-").first.map(String.init) ?? String(last)
        return TopologyServiceRole(rawValue: token)
    }

    static func classify(_ container: ContainerInfo) -> TopologyServiceRole {
        classify(name: container.name, image: container.image)
    }

    static func classify(service: DataService) -> TopologyServiceRole {
        classify(name: "\(service.type) \(service.role) \(service.container.name)", image: service.container.image)
    }

    static func classify(name: String, image: String) -> TopologyServiceRole {
        let hay = "\(name) \(image)".lowercased()
        if hay.contains("postgres") || hay.contains("mysql") || hay.contains("mariadb")
            || hay.contains("mongo") || hay.contains("sqlite") || hay.contains("database") { return .database }
        if hay.contains("redis") || hay.contains("valkey") || hay.contains("memcache") || hay.contains("cache") { return .cache }
        if hay.contains("worker") || hay.contains("relay") || hay.contains("queue") || hay.contains("ingest") { return .worker }
        if hay.contains("front") || hay.contains("web") || hay.contains("-ui") || hay.contains("next")
            || hay.contains("vite") || (hay.contains("nginx") && !hay.contains("app")) { return .frontend }
        return .backend
    }

    func matches(module path: String) -> Bool {
        let value = path.lowercased()
        switch self {
        case .frontend: return value.contains("web") || value.contains("ui") || value.contains("front")
        case .backend: return value.contains("api") || value.contains("server") || value.contains("back")
        case .worker: return value.contains("work") || value.contains("job") || value.contains("ingest")
        case .database, .cache: return false
        }
    }
}

struct TopologyLayer {
    let title: String
    let detail: String
    let color: UIColor
    let kind: TopologyLayerKind
    let weight: Float
    let container: ContainerInfo?

    static let healthy = UIColor(red: 0.23, green: 0.87, blue: 0.78, alpha: 1)
    static let warning = UIColor(red: 1, green: 0.68, blue: 0.31, alpha: 1)
    static let critical = UIColor(red: 1, green: 0.34, blue: 0.42, alpha: 1)
    static let moduleColor = UIColor(red: 0.71, green: 0.55, blue: 1, alpha: 1)
    static let communityColor = UIColor(red: 0.40, green: 0.66, blue: 1, alpha: 1)

    struct Hop: Identifiable {
        var id: String { "\(siteID):\(fromLayer):\(toLayer):\(title)" }
        let siteID: String
        let fromLayer: Int
        let toLayer: Int
        let title: String
        let volume: Double
        let weavatrix: Bool
    }

    static func hops(for site: Site, project: ProjectHealth?, routes: [InternalRoute] = []) -> [Hop] {
        let stack = layers(for: site, project: project)
        var result: [Hop] = []
        let runtime = stack.enumerated().filter { $0.element.kind == .runtime }.map(\.offset)
        for index in 0..<max(0, runtime.count - 1) {
            result.append(Hop(
                siteID: site.id, fromLayer: runtime[index], toLayer: runtime[index + 1],
                title: "\(stack[runtime[index]].title) → \(stack[runtime[index + 1]].title)",
                volume: max(16, site.requestsPerMinute), weavatrix: false
            ))
        }
        let modules = stack.enumerated().filter { $0.element.kind == .module }.map(\.offset)
        if let firstRuntime = runtime.first, let firstModule = modules.first {
            result.append(Hop(
                siteID: site.id, fromLayer: firstRuntime, toLayer: firstModule,
                title: "\(stack[firstRuntime].title) → Weavatrix \(stack[firstModule].title)",
                volume: max(11, site.requestsPerMinute * 0.45), weavatrix: true
            ))
        }
        for index in 0..<max(0, modules.count - 1) {
            result.append(Hop(
                siteID: site.id, fromLayer: modules[index], toLayer: modules[index + 1],
                title: "\(stack[modules[index]].title) → \(stack[modules[index + 1]].title)",
                volume: 13, weavatrix: true
            ))
        }
        if let lastModule = modules.last, let community = stack.firstIndex(where: { $0.kind == .community }) {
            result.append(Hop(
                siteID: site.id, fromLayer: lastModule, toLayer: community,
                title: "\(stack[lastModule].title) → \(stack[community].title)",
                volume: 10, weavatrix: true
            ))
        }
        let intra = routes.contains { route in
            let ids = Set([site.id])
            return TopologyLayout.resolveSite(route.caller, in: ids) != nil
                && TopologyLayout.resolveSite(route.targetService ?? route.destinationHost, in: ids) != nil
        }
        if intra, let first = result.first {
            result[0] = Hop(siteID: first.siteID, fromLayer: first.fromLayer, toLayer: first.toLayer,
                            title: first.title, volume: first.volume + 18, weavatrix: first.weavatrix)
        }
        return result
    }

    static func layers(for site: Site, project: ProjectHealth?) -> [TopologyLayer] {
        var result: [TopologyLayer] = []
        let containers = site.containers.isEmpty
            ? [ContainerInfo(id: site.id, name: "shared nginx", project: site.id, state: "running", status: "up",
                             image: "", imageId: "", cpuPercent: site.cpuPercent, memoryBytes: site.memoryBytes,
                             memoryLimit: site.memoryLimit, networkRxBytes: 0, networkTxBytes: 0, pids: 0)]
            : site.containers
        for container in containers {
            let down = container.state != "running"
            result.append(.init(
                title: container.name.replacingOccurrences(of: "-1", with: ""),
                detail: "\(container.state) · \(Format.bytes(container.memoryBytes)) · \(Format.percent(container.cpuPercent)) CPU",
                color: down ? critical : healthy, kind: .runtime,
                weight: memoryWeight(container.memoryBytes), container: container
            ))
        }
        let role = TopologyServiceRole.of(siteID: site.id)
        if let project {
            let modules = (project.analysis?.modules ?? []).filter { role == nil || role?.matches(module: $0.path) == true }
            for module in modules.prefix(8) {
                result.append(.init(
                    title: module.path,
                    detail: "Weavatrix · \(module.files) files · \(module.symbols) symbols",
                    color: moduleColor, kind: .module,
                    weight: max(18, Float(module.symbols) / 8), container: nil
                ))
            }
            if role == nil || role == .backend || role == .frontend {
                for community in (project.analysis?.communities ?? []).prefix(role == nil ? 4 : 2) {
                    let sample = (community.sample ?? []).prefix(2).joined(separator: ", ")
                    if let role, !sample.isEmpty, !role.matches(module: sample) { continue }
                    result.append(.init(
                        title: "community \(community.id)",
                        detail: "Weavatrix · \(community.nodes) nodes\(sample.isEmpty ? "" : " · \(sample)")",
                        color: communityColor, kind: .community,
                        weight: max(16, Float(community.nodes) / 12), container: nil
                    ))
                }
                if let hot = project.analysis?.hotPaths?.first, role == nil || role?.matches(module: hot.file) == true {
                    result.append(.init(
                        title: hot.label,
                        detail: "hot path · \(hot.file):\(hot.line)",
                        color: warning, kind: .hotspot, weight: 16, container: nil
                    ))
                }
            }
            if role == nil || role == .backend {
                let graph = project.graph
                let graphReady = (graph?.nodes ?? 0) > 0 && graph?.status == "CURRENT"
                result.append(.init(
                    title: "Code graph",
                    detail: "\((graph?.nodes ?? 0).formatted()) nodes · \((graph?.edges ?? 0).formatted()) edges · \(project.completeness)",
                    color: graphReady ? healthy : warning, kind: .graph,
                    weight: max(20, log2(1 + Float(graph?.nodes ?? 0)) * 7), container: nil
                ))
                let criticalCount = (project.vulnerabilities ?? []).filter { $0.severity.lowercased() == "critical" }.count
                let highCount = (project.vulnerabilities ?? []).filter { $0.severity.lowercased() == "high" }.count
                result.append(.init(
                    title: "Code scan",
                    detail: "\(criticalCount) critical · \(highCount) high · \((project.findings ?? []).count) findings",
                    color: criticalCount > 0 ? critical : highCount > 0 ? warning : healthy, kind: .scan,
                    weight: 18, container: nil
                ))
                let git = project.git
                result.append(.init(
                    title: "Git evidence",
                    detail: git?.head.map { "\(git?.branch ?? "detached") @ \($0.prefix(12)) · \(git?.dirty == true ? "dirty" : "clean")" } ?? "Git metadata unavailable",
                    color: git?.head == nil || git?.dirty == true ? warning : healthy, kind: .git,
                    weight: 16, container: nil
                ))
            }
        }
        return result
    }

    static func explode(_ site: Site, project: ProjectHealth?, services: [DataService]) -> [Site] {
        var counts: [TopologyServiceRole: Int] = [:]
        var result: [Site] = []
        var seen = Set<String>()

        func add(role: TopologyServiceRole, container: ContainerInfo, rpm: Double, bpm: Double) {
            let key = container.id + container.name
            guard seen.insert(key).inserted else { return }
            let index = counts[role, default: 0]
            counts[role] = index + 1
            let id = index == 0 ? "\(site.id)/\(role.rawValue)" : "\(site.id)/\(role.rawValue)-\(index + 1)"
            let name = index == 0 ? role.title : "\(role.title) \(index + 1)"
            result.append(Site(
                id: id, name: name, domains: site.domains, sharedNginx: site.sharedNginx,
                containers: [container], cpuPercent: container.cpuPercent, memoryBytes: container.memoryBytes,
                memoryLimit: container.memoryLimit, requestsPerMinute: rpm, bytesPerMinute: bpm,
                errorRate: site.errorRate, p95Ms: site.p95Ms
            ))
        }

        for container in site.containers {
            let role = TopologyServiceRole.classify(container)
            let share = Double(max(1, site.containers.count))
            add(role: role, container: container,
                rpm: role == .frontend || role == .backend ? site.requestsPerMinute : site.requestsPerMinute / share,
                bpm: max(32_000, site.bytesPerMinute * (role == .database || role == .cache ? 0.35 : 0.7)))
        }
        for service in services where service.siteId == site.id {
            let role = TopologyServiceRole.classify(service: service)
            if (role == .database || role == .cache), result.contains(where: { TopologyServiceRole.of(siteID: $0.id) == role }) {
                continue
            }
            if site.containers.contains(where: { $0.name == service.container.name || $0.id == service.container.id }) {
                continue
            }
            add(role: role, container: service.container, rpm: site.requestsPerMinute * 0.2, bpm: site.bytesPerMinute * 0.3)
        }
        let modules = project?.analysis?.modules ?? []
        if !result.contains(where: { TopologyServiceRole.of(siteID: $0.id) == .frontend }) {
            let web = modules.first { TopologyServiceRole.frontend.matches(module: $0.path) }
            if site.sharedNginx || web != nil {
                add(role: .frontend, container: ContainerInfo(
                    id: "\(site.id)-web", name: "\(site.id)-web", project: site.id, state: "running",
                    status: "edge", image: "shared-nginx", imageId: "edge-\(site.id)", cpuPercent: max(0.2, site.cpuPercent * 0.15),
                    memoryBytes: max(32_000_000, site.memoryBytes * 0.12), memoryLimit: site.memoryLimit,
                    networkRxBytes: 0, networkTxBytes: 0, pids: 4
                ), rpm: site.requestsPerMinute, bpm: site.bytesPerMinute)
            }
        }
        if result.isEmpty {
            add(role: .backend, container: ContainerInfo(
                id: site.id, name: site.name, project: site.id, state: "running", status: "up",
                image: "", imageId: "", cpuPercent: site.cpuPercent, memoryBytes: site.memoryBytes,
                memoryLimit: site.memoryLimit, networkRxBytes: 0, networkTxBytes: 0, pids: 0
            ), rpm: site.requestsPerMinute, bpm: site.bytesPerMinute)
        }
        return result.sorted { lhs, rhs in
            let order: [TopologyServiceRole] = [.frontend, .backend, .worker, .cache, .database]
            let a = order.firstIndex(of: TopologyServiceRole.of(siteID: lhs.id) ?? .worker) ?? 9
            let b = order.firstIndex(of: TopologyServiceRole.of(siteID: rhs.id) ?? .worker) ?? 9
            return a < b
        }
    }

    static func componentRoads(parent: Site, components: [Site], routes: [InternalRoute]) -> [TopologyLink] {
        func ids(_ role: TopologyServiceRole) -> [String] {
            components.compactMap { TopologyServiceRole.of(siteID: $0.id) == role ? $0.id : nil }
        }
        func rpm(_ id: String) -> Double {
            components.first { $0.id == id }?.requestsPerMinute ?? parent.requestsPerMinute
        }
        var links: [TopologyLink] = []
        func join(_ from: [String], _ to: [String], kind: TopologyRoadKind, volume: Double) {
            for start in from {
                for end in to where start != end {
                    if !links.contains(where: { $0.from == start && $0.to == end }) {
                        links.append(TopologyLink(from: start, to: end, kind: kind, volume: volume))
                    }
                }
            }
        }
        let front = ids(.frontend), back = ids(.backend), workers = ids(.worker)
        let databases = ids(.database), caches = ids(.cache)
        let entry = front.isEmpty ? back + workers : front
        for id in entry {
            links.append(TopologyLink(from: "host", to: id, kind: .feeder, volume: max(10, rpm(id))))
        }
        join(front, back, kind: .call, volume: max(14, parent.requestsPerMinute))
        join(back, databases, kind: .io, volume: max(12, parent.requestsPerMinute * 0.6))
        join(back, caches, kind: .io, volume: max(10, parent.requestsPerMinute * 0.4))
        join(back, workers, kind: .call, volume: max(8, parent.requestsPerMinute * 0.3))
        if front.isEmpty { join(workers, databases, kind: .io, volume: 10) }
        for route in routes {
            guard let from = resolveComponent(route.caller, among: components),
                  let to = resolveComponent(route.targetService ?? route.destinationHost, among: components),
                  from != to else { continue }
            if let index = links.firstIndex(where: { $0.from == from && $0.to == to }) {
                links[index] = TopologyLink(from: from, to: to, kind: links[index].kind, volume: max(links[index].volume, route.requests))
            } else {
                links.append(TopologyLink(from: from, to: to, kind: .call, volume: max(8, route.requests)))
            }
        }
        return links
    }

    static func resolveComponent(_ raw: String, among components: [Site]) -> String? {
        let ids = Set(components.map(\.id))
        if let hit = TopologyLayout.resolveSite(raw, in: ids) { return hit }
        let value = raw.lowercased()
        let keys: [(TopologyServiceRole, [String])] = [
            (.frontend, ["web", "front", "ui", "nginx"]),
            (.database, ["postgres", "mysql", "mongo", "sqlite", "database"]),
            (.cache, ["redis", "valkey", "cache"]),
            (.worker, ["worker", "relay", "job"]),
            (.backend, ["api", "app", "back", "server"]),
        ]
        for (role, tokens) in keys where tokens.contains(where: { value.contains($0) }) {
            if let id = components.first(where: { TopologyServiceRole.of(siteID: $0.id) == role })?.id { return id }
        }
        return nil
    }

    static func towerHeight(bytes: Double, maxBytes: Double) -> Float {
        Float(1.9 + 4.2 * log1p(max(0, bytes)) / log1p(max(1, maxBytes)))
    }

    static func fitHeights(weights: [Float], total: Float, gap: Float = 0.08, minHeight: Float = 0.22) -> [Float] {
        guard !weights.isEmpty else { return [] }
        let available = max(minHeight * Float(weights.count), total - gap * Float(max(0, weights.count - 1)))
        let extras = weights.map { max(0, $0 - minHeight) }
        let sum = extras.reduce(0, +)
        if sum <= 0 { return weights.map { _ in available / Float(weights.count) } }
        let spare = max(0, available - minHeight * Float(weights.count))
        return extras.map { minHeight + spare * $0 / sum }
    }

    private static func memoryWeight(_ bytes: Double) -> Float {
        Float(max(28, min(145, 28 + log2(1 + bytes / 1_048_576) * 10)))
    }
}
