import SceneKit
import SwiftUI
import UIKit

struct TopologySnapshot {
    let node: ManagedNode
    let overview: Overview
    let sites: [Site]
    let projects: [ProjectHealth]
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
    case fit, zoomIn, zoomOut, top, isometric
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

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = UIColor(red: 7 / 255, green: 13 / 255, blue: 20 / 255, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = mode == .traffic
        view.preferredFramesPerSecond = 30
        view.autoenablesDefaultLighting = false
        view.scene = SCNScene()
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Runtime towers. Drag to orbit, pinch to zoom, double tap a tower to focus, tap for details."

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
        view.rendersContinuously = mode == .traffic
        context.coordinator.render(snapshot: snapshot, mode: mode)
        if context.coordinator.lastCommand != command.number {
            context.coordinator.lastCommand = command.number
            context.coordinator.apply(command.action)
        }
    }

    final class Coordinator: NSObject {
        weak var view: SCNView?
        var selection: Binding<TopologySelection?>
        var lastCommand = 0
        private var signature = ""
        private var yaw: Float = 0.15
        private var pitch: Float = 0.72
        private var distance: Float = 17
        private var fitDistance: Float = 17
        private var target = SCNVector3(0, 1, 0)
        private let camera = SCNNode()
        private var towerPositions: [String: SCNVector3] = [:]

        init(selection: Binding<TopologySelection?>) { self.selection = selection }

        func render(snapshot: TopologySnapshot, mode: TopologyMode) {
            guard let view, let scene = view.scene else { return }
            let nextSignature = snapshot.node.id + mode.rawValue + snapshot.sites.map {
                "\($0.id):\($0.requestsPerMinute):\($0.bytesPerMinute):\($0.errorRate):\($0.containers.map { "\($0.name):\($0.state):\($0.memoryBytes):\($0.cpuPercent)" }.joined(separator: ","))"
            }.joined(separator: "|") + snapshot.projects.map {
                "\($0.id):\($0.completeness):\($0.graph?.nodes ?? 0):\($0.graph?.edges ?? 0):\($0.graph?.status ?? ""):\($0.vulnerabilities?.map(\.severity).joined(separator: ",") ?? ""):\($0.findings?.count ?? 0):\($0.git?.head ?? ""):\($0.git?.dirty == true)"
            }.joined(separator: "|")
            guard signature != nextSignature else { return }
            signature = nextSignature
            scene.rootNode.childNodes.forEach { if $0 !== camera { $0.removeFromParentNode() } }
            if camera.parent == nil {
                let lens = SCNCamera()
                lens.fieldOfView = 55
                lens.zNear = 0.05
                lens.zFar = 250
                camera.camera = lens
                scene.rootNode.addChildNode(camera)
                view.pointOfView = camera
            }
            addLights(to: scene)
            addFloor(to: scene, radius: max(8, Float(snapshot.sites.count) * 1.15))
            let hub = SCNNode(geometry: SCNCylinder(radius: 0.62, height: 0.55))
            hub.geometry?.firstMaterial = material(red: 0.13, green: 0.36, blue: 0.39, emission: 0.18)
            hub.position = SCNVector3(0, 0.28, 3.4)
            hub.name = "host"
            scene.rootNode.addChildNode(hub)
            addRing(at: SCNVector3(0, 0.04, 3.4), radius: 0.95, color: UIColor(red: 0.2, green: 0.78, blue: 0.72, alpha: 1), to: scene)
            addLabel(snapshot.node.name, at: SCNVector3(0, 0.85, 3.4), to: scene)

            let previousCount = towerPositions.count
            towerPositions.removeAll()
            let count = snapshot.sites.count
            let columns = min(3, max(1, count))
            let rows = Int(ceil(Double(count) / Double(columns)))
            fitDistance = max(17, Float(rows) * 4.5)
            if previousCount != count { distance = fitDistance; target = SCNVector3(0, 1, -1.2) }
            let maxEgress = max(1, snapshot.sites.map(\.bytesPerMinute).max() ?? 1)
            for (index, site) in snapshot.sites.enumerated() {
                let column = index % columns
                let row = index / columns
                let position = SCNVector3(Float(column) - Float(columns - 1) / 2, 0,
                                          Float(row) - Float(rows - 1) / 2)
                let placed = SCNVector3(position.x * 4.2, 0, position.z * 4.2 - 1.2)
                let height = Float(1.8 + 4.1 * log1p(max(0, site.bytesPerMinute)) / log1p(maxEgress))
                let project = snapshot.projects.first { $0.id == site.id }
                towerPositions[site.id] = SCNVector3(placed.x, height * 0.5, placed.z)
                addTower(site, project: project, position: placed, height: height, to: scene)
                if mode == .traffic {
                    addLink(from: SCNVector3(0, 0.4, 3.4), to: SCNVector3(placed.x, 0.5, placed.z),
                            volume: site.requestsPerMinute, to: scene)
                }
            }
            updateCamera(animated: false)
        }

        private func addTower(_ site: Site, project: ProjectHealth?, position: SCNVector3, height: Float, to scene: SCNScene) {
            let layers = TopologyLayer.layers(for: site, project: project)
            let layerHeight = height / Float(layers.count)
            for (index, layer) in layers.enumerated() {
                let cylinder = SCNCylinder(radius: 0.55, height: CGFloat(max(0.2, layerHeight - 0.07)))
                cylinder.radialSegmentCount = 28
                cylinder.firstMaterial = material(layer.color, emission: 0.22)
                let node = SCNNode(geometry: cylinder)
                node.position = SCNVector3(position.x, layerHeight * (Float(index) + 0.5), position.z)
                node.name = "site:\(site.id):\(index)"
                scene.rootNode.addChildNode(node)
            }
            addRing(at: SCNVector3(position.x, 0.04, position.z), radius: 0.82, color: layers.first?.color ?? .cyan, to: scene)
            addLabel(site.name, at: SCNVector3(position.x, height + 0.42, position.z), to: scene)
            let glow = SCNNode(geometry: SCNSphere(radius: 0.12))
            glow.geometry?.firstMaterial = material(layers.last?.color ?? .cyan, emission: 0.8)
            glow.position = SCNVector3(position.x, height + 0.22, position.z)
            scene.rootNode.addChildNode(glow)
        }

        private func addFloor(to scene: SCNScene, radius: Float) {
            let size = CGFloat(radius * 2.5)
            let floor = SCNNode(geometry: SCNPlane(width: size, height: size))
            floor.geometry?.firstMaterial = material(red: 0.035, green: 0.065, blue: 0.085)
            floor.eulerAngles.x = -.pi / 2
            floor.position.y = -0.08
            scene.rootNode.addChildNode(floor)
            for index in -10...10 {
                let offset = Float(index) * radius / 8
                addLink(from: SCNVector3(-radius * 1.2, -0.055, offset), to: SCNVector3(radius * 1.2, -0.055, offset),
                        radius: 0.003, color: UIColor(red: 0.11, green: 0.24, blue: 0.28, alpha: 1), to: scene)
                addLink(from: SCNVector3(offset, -0.055, -radius * 1.2), to: SCNVector3(offset, -0.055, radius * 1.2),
                        radius: 0.003, color: UIColor(red: 0.11, green: 0.24, blue: 0.28, alpha: 1), to: scene)
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
            label.font = UIFont.systemFont(ofSize: 0.48, weight: .semibold)
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
            return result
        }

        private func material(red: CGFloat, green: CGFloat, blue: CGFloat, emission: CGFloat = 0) -> SCNMaterial {
            material(UIColor(red: red, green: green, blue: blue, alpha: 1), emission: emission)
        }

        private func addLink(from start: SCNVector3, to end: SCNVector3, volume: Double, to scene: SCNScene) {
            let color = UIColor(red: 0.25, green: 0.85, blue: 0.78, alpha: 1)
            addLink(from: start, to: end, radius: CGFloat(min(0.065, 0.018 + max(0, volume) / 3_000)), color: color, to: scene)
            guard volume > 0 else { return }
            let packet = SCNNode(geometry: SCNSphere(radius: 0.08))
            packet.geometry?.firstMaterial = material(color, emission: 0.85)
            packet.position = start
            scene.rootNode.addChildNode(packet)
            let travel = SCNAction.move(to: end, duration: max(1.2, 4 - min(2.4, volume / 100)))
            packet.runAction(.repeatForever(.sequence([travel, .move(to: start, duration: 0)])))
        }

        private func addLink(from start: SCNVector3, to end: SCNVector3, radius: CGFloat, color: UIColor, to scene: SCNScene) {
            let dx = end.x - start.x, dy = end.y - start.y, dz = end.z - start.z
            let length = sqrt(dx * dx + dy * dy + dz * dz)
            guard length > 0 else { return }
            let line = SCNNode(geometry: SCNCylinder(radius: radius, height: CGFloat(length)))
            line.geometry?.firstMaterial = material(color, emission: 0.2)
            line.position = SCNVector3((start.x + end.x) / 2, (start.y + end.y) / 2, (start.z + end.z) / 2)
            line.rotation = SCNVector4(-dz, 0, dx, acos(dy / length))
            scene.rootNode.addChildNode(line)
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
                target = SCNVector3(0, 1, -1.2)
                distance = fitDistance
                yaw = 0.15; pitch = 0.72
            case .zoomIn: distance = max(3.4, distance * 0.76)
            case .zoomOut: distance = min(60, distance * 1.31)
            case .top: target = SCNVector3(0, 0, 0); pitch = 1.52
            case .isometric: pitch = 0.72; yaw = 0.15
            }
            updateCamera(animated: true)
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
            guard let hit = view.hitTest(location, options: [.firstFoundOnly: true]).first,
                  let name = hit.node.name, name.hasPrefix("site:") else { return }
            let parts = name.split(separator: ":")
            guard parts.count == 3, let layer = Int(parts[2]) else { return }
            selection.wrappedValue = TopologySelection(siteID: String(parts[1]), layer: layer)
        }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let location = gesture.location(in: view)
            if let hit = view.hitTest(location, options: [.firstFoundOnly: true]).first,
               let name = hit.node.name, name.hasPrefix("site:") {
                let parts = name.split(separator: ":")
                if parts.count == 3, let point = towerPositions[String(parts[1])] {
                    target = point
                    distance = 5.5
                    updateCamera(animated: true)
                    return
                }
            }
            apply(.fit)
        }
    }
}
