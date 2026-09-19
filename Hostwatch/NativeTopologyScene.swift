import SceneKit
import SwiftUI
import UIKit

struct TopologySnapshot {
    let node: ManagedNode
    let overview: Overview
    let sites: [Site]
    let projects: [ProjectHealth]
    let routes: [InternalRoute]
    let services: [DataService]
}

struct TopologyLayer {
    let title: String
    let detail: String
    let color: UIColor
    let container: ContainerInfo?

    static func layers(for site: Site, project: ProjectHealth?) -> [TopologyLayer] {
        let healthy = UIColor(red: 0.23, green: 0.87, blue: 0.78, alpha: 1)
        let warning = UIColor(red: 1, green: 0.68, blue: 0.31, alpha: 1)
        let critical = UIColor(red: 1, green: 0.34, blue: 0.42, alpha: 1)
        var result = site.containers.map { container in
            TopologyLayer(title: container.name, detail: "\(container.state) · \(Format.bytes(container.memoryBytes)) · \(Format.percent(container.cpuPercent)) CPU",
                          color: container.state == "running" ? healthy : critical, container: container)
        }
        if result.isEmpty {
            result.append(.init(title: "Runtime", detail: "\(site.requestsPerMinute.formatted()) requests/min · \(Format.percent(site.errorRate)) errors",
                                color: site.errorRate >= 3 ? critical : site.errorRate >= 1 ? warning : healthy, container: nil))
        }
        if let project {
            let graph = project.graph
            let graphReady = (graph?.nodes ?? 0) > 0 && graph?.status == "CURRENT"
            result.append(.init(title: "Code graph", detail: "\((graph?.nodes ?? 0).formatted()) nodes · \((graph?.edges ?? 0).formatted()) edges · \(project.completeness) evidence",
                                color: graphReady ? healthy : warning, container: nil))
            let criticalCount = (project.vulnerabilities ?? []).filter { $0.severity.lowercased() == "critical" }.count
            let highCount = (project.vulnerabilities ?? []).filter { $0.severity.lowercased() == "high" }.count
            let codeColor = criticalCount > 0 ? critical : highCount > 0 ? warning : healthy
            result.append(.init(title: "Code scan", detail: "\(criticalCount) critical · \(highCount) high · \((project.findings ?? []).count) findings",
                                color: codeColor, container: nil))
            let git = project.git
            result.append(.init(title: "Git evidence", detail: git?.head.map { "\(git?.branch ?? "detached") @ \($0.prefix(12)) · \(git?.dirty == true ? "dirty" : "clean")" } ?? "Git metadata unavailable",
                                color: git?.head == nil || git?.dirty == true ? warning : healthy, container: nil))
        }
        return result
    }
}

struct TopologySelection: Identifiable {
    let siteID: String
    let layer: Int?
    var id: String { "\(siteID):\(layer.map(String.init) ?? "all")" }
}

enum TopologyMode: String, CaseIterable {
    case towers = "Towers"
    case traffic = "Traffic"
}

enum TopologyCameraAction {
    case fit, zoomIn, zoomOut, top, isometric, focus, elevate
}

struct TopologyCommand {
    let number: Int
    let action: TopologyCameraAction
}

struct NativeTopologyScene: UIViewRepresentable {
    let snapshot: TopologySnapshot
    let mode: TopologyMode
    let command: TopologyCommand
    @Binding var selection: TopologySelection?
    @Binding var focusedSiteID: String?
    @Binding var focusedRoad: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, focusedSiteID: $focusedSiteID, focusedRoad: $focusedRoad)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = UIColor(red: 7 / 255, green: 13 / 255, blue: 20 / 255, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = mode == .traffic
        view.preferredFramesPerSecond = 30
        view.autoenablesDefaultLighting = false
        view.scene = SCNScene()
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Runtime cyberboard. Drag to orbit, pinch to zoom, tap a tower to lock the camera, tap a road to highlight it, double tap empty space to reset."

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        [pan, pinch, tap, doubleTap].forEach(view.addGestureRecognizer)
        context.coordinator.view = view
        context.coordinator.render(snapshot: snapshot, mode: mode)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.focusedSiteID = $focusedSiteID
        context.coordinator.focusedRoad = $focusedRoad
        view.rendersContinuously = mode == .traffic
        context.coordinator.render(snapshot: snapshot, mode: mode)
        context.coordinator.applyHighlight()
        if context.coordinator.lastCommand != command.number {
            context.coordinator.lastCommand = command.number
            context.coordinator.apply(command.action)
        }
    }

    final class Coordinator: NSObject {
        weak var view: SCNView?
        var selection: Binding<TopologySelection?>
        var focusedSiteID: Binding<String?>
        var focusedRoad: Binding<String?>
        var lastCommand = 0
        private var signature = ""
        private var yaw: Float = 0.42
        private var pitch: Float = 0.78
        private var distance: Float = 18
        private var fitDistance: Float = 18
        private var target = SCNVector3(0, 1.2, 0)
        private let camera = SCNNode()
        private var towerPositions: [String: SCNVector3] = [:]
        private var towerHeights: [String: Float] = [:]
        private var roads: [(from: String, to: String, kind: String, nodes: [SCNNode])] = []

        init(selection: Binding<TopologySelection?>, focusedSiteID: Binding<String?>, focusedRoad: Binding<String?>) {
            self.selection = selection
            self.focusedSiteID = focusedSiteID
            self.focusedRoad = focusedRoad
        }

        func render(snapshot: TopologySnapshot, mode: TopologyMode) {
            guard let view, let scene = view.scene else { return }
            let nextSignature = snapshot.node.id + mode.rawValue + snapshot.sites.map {
                "\($0.id):\($0.requestsPerMinute):\($0.bytesPerMinute):\($0.errorRate):\($0.containers.map { "\($0.name):\($0.state):\($0.memoryBytes):\($0.cpuPercent)" }.joined(separator: ","))"
            }.joined(separator: "|") + snapshot.projects.map {
                "\($0.id):\($0.completeness):\($0.graph?.nodes ?? 0):\($0.graph?.edges ?? 0):\($0.graph?.status ?? ""):\($0.vulnerabilities?.map(\.severity).joined(separator: ",") ?? ""):\($0.findings?.count ?? 0):\($0.git?.head ?? ""):\($0.git?.dirty == true)"
            }.joined(separator: "|") + snapshot.routes.map { "\($0.caller)-\($0.targetService ?? $0.destinationHost):\($0.requests)" }.joined()
                + snapshot.services.map(\.id).joined()
            guard signature != nextSignature else { return }
            signature = nextSignature
            scene.rootNode.childNodes.forEach { if $0 !== camera { $0.removeFromParentNode() } }
            roads.removeAll()
            if camera.parent == nil {
                let lens = SCNCamera()
                lens.fieldOfView = 52
                lens.zNear = 0.05
                lens.zFar = 250
                camera.camera = lens
                scene.rootNode.addChildNode(camera)
                view.pointOfView = camera
            }
            addLights(to: scene)
            addFloor(to: scene, radius: max(9, Float(snapshot.sites.count) * 1.2 + 2))

            let hub = TopologyLayout.hubPosition()
            let hubNode = SCNNode(geometry: SCNCylinder(radius: 0.62, height: 0.55))
            hubNode.geometry?.firstMaterial = material(red: 0.13, green: 0.36, blue: 0.39, emission: 0.22)
            hubNode.position = SCNVector3(hub.x, 0.28, hub.z)
            hubNode.name = "host"
            scene.rootNode.addChildNode(hubNode)
            addRing(at: SCNVector3(hub.x, 0.04, hub.z), radius: 0.95, color: UIColor(red: 0.2, green: 0.78, blue: 0.72, alpha: 1), to: scene)
            addLabel(snapshot.node.name, at: SCNVector3(hub.x, 0.85, hub.z), to: scene)

            let previousCount = towerPositions.count
            towerPositions.removeAll()
            towerHeights.removeAll()
            let count = snapshot.sites.count
            let rows = Int(ceil(Double(count) / Double(TopologyLayout.columns(for: count))))
            fitDistance = max(17, Float(rows) * 5.0 + Float(snapshot.services.count) * 0.5)
            if previousCount != count { distance = fitDistance; target = SCNVector3(0, 1.2, 0) }
            let maxEgress = max(1, snapshot.sites.map(\.bytesPerMinute).max() ?? 1)
            var bases: [String: TopologyPoint] = [:]
            for (index, site) in snapshot.sites.enumerated() {
                let placed = TopologyLayout.gridPosition(index: index, count: count)
                let height = Float(1.9 + 4.2 * log1p(max(0, site.bytesPerMinute)) / log1p(maxEgress))
                let project = snapshot.projects.first { $0.id == site.id }
                bases[site.id] = placed
                towerPositions[site.id] = SCNVector3(placed.x, height * 0.5, placed.z)
                towerHeights[site.id] = height
                addPlate(at: placed, to: scene)
                addTower(site, project: project, position: placed, height: height, to: scene)
            }
            towerPositions["host"] = SCNVector3(hub.x, 0.4, hub.z)
            towerHeights["host"] = 0.8
            let siteXs = bases.values.map(\.x) + [hub.x]
            let siteZs = bases.values.map(\.z) + [hub.z]
            for site in snapshot.sites {
                guard let base = bases[site.id] else { continue }
                addRoad(from: "host", to: site.id, start: hub, end: base, kind: .feeder,
                        volume: max(10, site.requestsPerMinute), siteXs: siteXs, siteZs: siteZs, to: scene, animated: mode == .traffic)
            }
            addObservedRoads(snapshot.routes, bases: bases, siteXs: siteXs, siteZs: siteZs, to: scene, animated: mode == .traffic)
            addExternalTowers(snapshot.services, bases: bases, siteXs: siteXs, siteZs: siteZs, to: scene, animated: mode == .traffic)
            updateCamera(animated: false)
            applyHighlight()
        }

        private func addPlate(at position: TopologyPoint, to scene: SCNScene) {
            let plate = SCNNode(geometry: SCNBox(width: 3.2, height: 0.08, length: 3.2, chamferRadius: 0.04))
            plate.geometry?.firstMaterial = material(red: 0.08, green: 0.16, blue: 0.2, emission: 0.08)
            plate.position = SCNVector3(position.x, -0.02, position.z)
            scene.rootNode.addChildNode(plate)
        }

        private func addObservedRoads(_ routes: [InternalRoute], bases: [String: TopologyPoint], siteXs: [Float], siteZs: [Float], to scene: SCNScene, animated: Bool) {
            let ids = Set(bases.keys)
            for route in routes {
                let from = TopologyLayout.resolveSite(route.caller, in: ids)
                let to = TopologyLayout.resolveSite(route.targetService ?? route.destinationHost, in: ids)
                guard let from, let to, from != to, let start = bases[from], let end = bases[to] else { continue }
                addRoad(from: from, to: to, start: start, end: end, kind: .call, volume: max(12, route.requests),
                        siteXs: siteXs, siteZs: siteZs, to: scene, animated: animated)
            }
        }

        private func addExternalTowers(_ services: [DataService], bases: [String: TopologyPoint], siteXs: [Float], siteZs: [Float], to scene: SCNScene, animated: Bool) {
            let xs = bases.values.map(\.x)
            let zs = bases.values.map(\.z)
            for (index, service) in services.enumerated() {
                let placed = TopologyLayout.externalPosition(index: index, count: services.count, siteXs: xs, siteZs: zs)
                let cache = service.type.lowercased().contains("redis") || service.role.lowercased().contains("cache")
                let color = cache ? UIColor(red: 0.85, green: 0.42, blue: 0.78, alpha: 1) : UIColor(red: 0.35, green: 0.82, blue: 0.62, alpha: 1)
                let height: Float = 1.45
                let pillar: SCNNode
                if cache {
                    pillar = SCNNode(geometry: SCNBox(width: 0.9, height: CGFloat(height), length: 0.9, chamferRadius: 0.04))
                } else {
                    pillar = SCNNode(geometry: SCNCylinder(radius: 0.42, height: CGFloat(height)))
                }
                pillar.geometry?.firstMaterial = material(color, emission: 0.32)
                pillar.position = SCNVector3(placed.x, height / 2, placed.z)
                pillar.name = "ext:\(service.id)"
                scene.rootNode.addChildNode(pillar)
                addRing(at: SCNVector3(placed.x, 0.04, placed.z), radius: 0.68, color: color, to: scene)
                addLabel(service.type, at: SCNVector3(placed.x, height + 0.38, placed.z), to: scene)
                towerPositions[pillar.name ?? service.id] = SCNVector3(placed.x, height * 0.5, placed.z)
                towerHeights[pillar.name ?? service.id] = height
                if let siteID = service.siteId, let base = bases[siteID] {
                    addRoad(from: siteID, to: pillar.name ?? service.id, start: base, end: placed, kind: .io,
                            volume: 18, siteXs: siteXs + [placed.x], siteZs: siteZs + [placed.z], to: scene, animated: animated)
                }
            }
        }

        private func addTower(_ site: Site, project: ProjectHealth?, position: TopologyPoint, height: Float, to scene: SCNScene) {
            let layers = TopologyLayer.layers(for: site, project: project)
            let layerHeight = height / Float(layers.count)
            for (index, layer) in layers.enumerated() {
                let slab = index > site.containers.count - 1 && !site.containers.isEmpty
                let node: SCNNode
                if slab {
                    node = SCNNode(geometry: SCNBox(width: 1.05, height: CGFloat(max(0.18, layerHeight - 0.07)), length: 1.05, chamferRadius: 0.03))
                } else {
                    let cylinder = SCNCylinder(radius: 0.52, height: CGFloat(max(0.18, layerHeight - 0.07)))
                    cylinder.radialSegmentCount = 28
                    node = SCNNode(geometry: cylinder)
                }
                node.geometry?.firstMaterial = material(layer.color, emission: 0.24)
                node.position = SCNVector3(position.x, layerHeight * (Float(index) + 0.5), position.z)
                node.name = "site:\(site.id):\(index)"
                scene.rootNode.addChildNode(node)
            }
            addRing(at: SCNVector3(position.x, 0.04, position.z), radius: 0.86, color: layers.first?.color ?? .cyan, to: scene)
            addLabel(site.name, at: SCNVector3(position.x, height + 0.42, position.z), to: scene)
            let glow = SCNNode(geometry: SCNSphere(radius: 0.11))
            glow.geometry?.firstMaterial = material(layers.last?.color ?? .cyan, emission: 0.8)
            glow.position = SCNVector3(position.x, height + 0.2, position.z)
            scene.rootNode.addChildNode(glow)
        }

        private func addFloor(to scene: SCNScene, radius: Float) {
            let size = CGFloat(radius * 2.6)
            let floor = SCNNode(geometry: SCNPlane(width: size, height: size))
            floor.geometry?.firstMaterial = material(red: 0.035, green: 0.065, blue: 0.085)
            floor.eulerAngles.x = -.pi / 2
            floor.position.y = -0.08
            scene.rootNode.addChildNode(floor)
            for index in -10...10 {
                let offset = Float(index) * radius / 8
                addSegment(from: SCNVector3(-radius * 1.2, -0.055, offset), to: SCNVector3(radius * 1.2, -0.055, offset),
                           radius: 0.003, color: UIColor(red: 0.11, green: 0.24, blue: 0.28, alpha: 1), name: nil, to: scene)
                addSegment(from: SCNVector3(offset, -0.055, -radius * 1.2), to: SCNVector3(offset, -0.055, radius * 1.2),
                           radius: 0.003, color: UIColor(red: 0.11, green: 0.24, blue: 0.28, alpha: 1), name: nil, to: scene)
            }
        }

        private func addRing(at point: SCNVector3, radius: CGFloat, color: UIColor, to scene: SCNScene) {
            let node = SCNNode(geometry: SCNTorus(ringRadius: radius, pipeRadius: 0.035))
            node.geometry?.firstMaterial = material(color, emission: 0.35)
            node.position = point
            scene.rootNode.addChildNode(node)
        }

        private func addLabel(_ text: String, at position: SCNVector3, to scene: SCNScene) {
            let label = SCNText(string: text, extrusionDepth: 0)
            label.font = UIFont.systemFont(ofSize: 0.42, weight: .semibold)
            label.flatness = 0.04
            label.firstMaterial = material(red: 0.72, green: 0.82, blue: 0.86, emission: 0.25)
            let node = SCNNode(geometry: label)
            let bounds = label.boundingBox
            node.pivot = SCNMatrix4MakeTranslation((bounds.max.x - bounds.min.x) / 2, 0, 0)
            node.position = position
            node.constraints = [SCNBillboardConstraint()]
            scene.rootNode.addChildNode(node)
        }

        private func addLights(to scene: SCNScene) {
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 450
            scene.rootNode.addChildNode(ambient)
            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .omni
            key.light?.intensity = 1_100
            key.position = SCNVector3(5, 12, 8)
            scene.rootNode.addChildNode(key)
        }

        private func material(_ color: UIColor, emission: CGFloat = 0) -> SCNMaterial {
            let result = SCNMaterial()
            result.diffuse.contents = color
            result.emission.contents = color.withAlphaComponent(emission)
            result.lightingModel = .physicallyBased
            result.isDoubleSided = true
            result.transparency = 1
            return result
        }

        private func material(red: CGFloat, green: CGFloat, blue: CGFloat, emission: CGFloat = 0) -> SCNMaterial {
            material(UIColor(red: red, green: green, blue: blue, alpha: 1), emission: emission)
        }

        private func color(for kind: TopologyRoadKind) -> UIColor {
            switch kind {
            case .feeder: UIColor(red: 0.25, green: 0.85, blue: 0.78, alpha: 1)
            case .call: UIColor(red: 1, green: 0.68, blue: 0.31, alpha: 1)
            case .io: UIColor(red: 0.35, green: 0.82, blue: 0.62, alpha: 1)
            }
        }

        private func addRoad(from: String, to: String, start: TopologyPoint, end: TopologyPoint, kind: TopologyRoadKind,
                             volume: Double, siteXs: [Float], siteZs: [Float], to scene: SCNScene, animated: Bool) {
            let points = TopologyLayout.manhattan(from: start, to: end, siteXs: siteXs, siteZs: siteZs)
            let color = color(for: kind)
            let radius = CGFloat(min(0.07, 0.018 + max(0, volume) / 3_200))
            var nodes: [SCNNode] = []
            let vectors = points.map { SCNVector3($0.x, TopologyLayout.roadY, $0.z) }
            for index in 1..<vectors.count {
                let name = "road:\(from):\(to):\(kind.rawValue)"
                nodes.append(addSegment(from: vectors[index - 1], to: vectors[index], radius: radius, color: color, name: name, to: scene))
            }
            roads.append((from, to, kind.rawValue, nodes))
            guard animated, volume > 0, let first = vectors.first else { return }
            let packet = SCNNode(geometry: SCNSphere(radius: 0.075))
            packet.geometry?.firstMaterial = material(color, emission: 0.85)
            packet.position = first
            scene.rootNode.addChildNode(packet)
            let slice = max(0.35, (4 - min(2.4, volume / 100)) / Double(max(1, vectors.count - 1)))
            var actions = vectors.dropFirst().map { SCNAction.move(to: $0, duration: slice) }
            actions.append(.move(to: first, duration: 0))
            packet.runAction(.repeatForever(.sequence(actions)))
        }

        @discardableResult
        private func addSegment(from start: SCNVector3, to end: SCNVector3, radius: CGFloat, color: UIColor, name: String?, to scene: SCNScene) -> SCNNode {
            let dx = end.x - start.x, dy = end.y - start.y, dz = end.z - start.z
            let length = sqrt(dx * dx + dy * dy + dz * dz)
            let line = SCNNode(geometry: SCNCylinder(radius: radius, height: CGFloat(max(0.001, length))))
            line.geometry?.firstMaterial = material(color, emission: 0.28)
            line.position = SCNVector3((start.x + end.x) / 2, (start.y + end.y) / 2, (start.z + end.z) / 2)
            if length > 0 { line.rotation = SCNVector4(-dz, 0, dx, acos(min(1, max(-1, dy / length)))) }
            line.name = name
            scene.rootNode.addChildNode(line)
            return line
        }

        func applyHighlight() {
            guard let scene = view?.scene else { return }
            let focus = focusedSiteID.wrappedValue
            let road = focusedRoad.wrappedValue
            scene.rootNode.enumerateChildNodes { node, _ in
                guard let name = node.name, let material = node.geometry?.firstMaterial else { return }
                let connected: Bool
                if let road, name.hasPrefix("road:") {
                    connected = name == road
                } else if let focus {
                    if name.hasPrefix("road:") {
                        connected = roads.contains { ($0.from == focus || $0.to == focus) && $0.nodes.contains(where: { $0 === node }) }
                    } else if name.hasPrefix("site:") {
                        connected = name.hasPrefix("site:\(focus):")
                    } else if name.hasPrefix("ext:") {
                        connected = name == focus || roads.contains { ($0.from == focus && $0.to == name) || ($0.to == focus && $0.from == name) }
                    } else {
                        connected = name == focus || (focus != "host" && name == "host" && roads.contains { $0.from == "host" && $0.to == focus })
                    }
                } else {
                    connected = true
                }
                material.transparency = connected ? 1 : 0.22
            }
        }

        private func updateCamera(animated: Bool) {
            let position = SCNVector3(target.x + distance * cos(pitch) * sin(yaw),
                                      target.y + distance * sin(pitch),
                                      target.z + distance * cos(pitch) * cos(yaw))
            if animated { SCNTransaction.begin(); SCNTransaction.animationDuration = 0.45 }
            camera.position = position
            camera.look(at: target)
            if animated { SCNTransaction.commit() }
        }

        func apply(_ action: TopologyCameraAction) {
            switch action {
            case .fit:
                target = SCNVector3(0, 1.2, 0)
                distance = fitDistance
                yaw = 0.42; pitch = 0.78
                focusedSiteID.wrappedValue = nil
                focusedRoad.wrappedValue = nil
                applyHighlight()
            case .zoomIn: distance = max(3.4, distance * 0.76)
            case .zoomOut: distance = min(60, distance * 1.31)
            case .top: target = SCNVector3(0, 0, 0); pitch = 1.52
            case .isometric: pitch = 0.78; yaw = 0.42
            case .focus, .elevate:
                if let id = focusedSiteID.wrappedValue, let point = towerPositions[id] {
                    let height = towerHeights[id] ?? 2
                    target = SCNVector3(point.x, action == .elevate ? height * 0.45 : point.y, point.z)
                    distance = action == .elevate ? max(4.2, height * 0.9 + 3.2) : 6.2
                    pitch = 0.82
                }
            }
            updateCamera(animated: true)
        }

        private func lock(_ id: String, elevate: Bool) {
            focusedSiteID.wrappedValue = id
            focusedRoad.wrappedValue = nil
            applyHighlight()
            if let point = towerPositions[id] {
                let height = towerHeights[id] ?? 2
                target = SCNVector3(point.x, elevate ? height * 0.45 : point.y, point.z)
                distance = elevate ? max(4.2, height * 0.9 + 3.2) : 6.2
                pitch = 0.82
                updateCamera(animated: true)
            }
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard let view else { return }
            let movement = gesture.translation(in: view)
            yaw -= Float(movement.x) * 0.008
            pitch = min(1.53, max(0.12, pitch + Float(movement.y) * 0.007))
            gesture.setTranslation(.zero, in: view)
            updateCamera(animated: false)
        }

        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            distance = min(60, max(3.4, distance / Float(gesture.scale)))
            gesture.scale = 1
            updateCamera(animated: false)
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let location = gesture.location(in: view)
            guard let hit = view.hitTest(location, options: [.firstFoundOnly: true]).first, let name = hit.node.name else { return }
            if name.hasPrefix("road:") {
                focusedRoad.wrappedValue = name
                let parts = name.split(separator: ":")
                if parts.count >= 3 { focusedSiteID.wrappedValue = String(parts[1]) }
                applyHighlight()
                return
            }
            if name == "host" { lock("host", elevate: false); return }
            if name.hasPrefix("ext:") { lock(name, elevate: false); return }
            if name.hasPrefix("site:") {
                let parts = name.split(separator: ":")
                guard parts.count == 3 else { return }
                lock(String(parts[1]), elevate: false)
            }
        }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let location = gesture.location(in: view)
            if let hit = view.hitTest(location, options: [.firstFoundOnly: true]).first, let name = hit.node.name {
                if name.hasPrefix("site:") {
                    let parts = name.split(separator: ":")
                    if parts.count == 3 { lock(String(parts[1]), elevate: true); return }
                }
                if name.hasPrefix("ext:") || name == "host" { lock(name, elevate: true); return }
            }
            apply(.fit)
        }
    }
}
