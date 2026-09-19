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
    var links: [TopologyLink] = []
    var projectScope = false
}

struct TopologySelection: Identifiable {
    let siteID: String
    let layer: Int?
    var id: String { "\(siteID):\(layer.map(String.init) ?? "all")" }
}

enum TopologyMode: String, CaseIterable {
    case towers = "Towers"
    case traffic = "Traffic"

    var showsPackets: Bool { self == .traffic }
    var showsArchitecture: Bool { self == .towers }
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
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 30
        view.autoenablesDefaultLighting = false
        view.scene = SCNScene()
        view.delegate = context.coordinator
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Runtime cyberboard. Drag to orbit, two fingers to pan, pinch to zoom, tap a tower to frame it from the right."

        let orbit = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.orbit(_:)))
        orbit.maximumNumberOfTouches = 1
        let slide = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.slide(_:)))
        slide.minimumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        [orbit, slide, pinch, tap, doubleTap].forEach(view.addGestureRecognizer)
        context.coordinator.attach(view)
        context.coordinator.render(snapshot: snapshot, mode: mode)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.focusedSiteID = $focusedSiteID
        context.coordinator.focusedRoad = $focusedRoad
        view.rendersContinuously = true
        context.coordinator.render(snapshot: snapshot, mode: mode)
        context.coordinator.applyHighlight()
        if context.coordinator.lastCommand != command.number {
            context.coordinator.lastCommand = command.number
            context.coordinator.apply(command.action)
        }
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        weak var view: SCNView?
        var selection: Binding<TopologySelection?>
        var focusedSiteID: Binding<String?>
        var focusedRoad: Binding<String?>
        var lastCommand = 0
        private var structureKey = ""
        private var pose = TopologyCamera.Pose(target: SCNVector3(0, 1.2, 0), yaw: 0.55, pitch: 0.62, distance: 18)
        private var fitDistance: Float = 18
        private let camera = SCNNode()
        private let labels = TopologyLabelCanvas()
        private var anchors: [LabelAnchor] = []
        private var towerBases: [String: SCNVector3] = [:]
        private var towerHeights: [String: Float] = [:]
        private var towerGroups: [String: SCNNode] = [:]
        private var towerBaseHeights: [String: Float] = [:]
        private var roads: [(from: String, to: String, kind: String, nodes: [SCNNode])] = []
        private var packets: [LivePacket] = []
        private var layerMids: [String: [Float]] = [:]
        private var mode: TopologyMode = .traffic
        private var labelsPending = false

        init(selection: Binding<TopologySelection?>, focusedSiteID: Binding<String?>, focusedRoad: Binding<String?>) {
            self.selection = selection
            self.focusedSiteID = focusedSiteID
            self.focusedRoad = focusedRoad
        }

        func attach(_ view: SCNView) {
            self.view = view
            labels.frame = view.bounds
            labels.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            labels.isUserInteractionEnabled = false
            view.addSubview(labels)
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            if mode.showsPackets {
                for packet in packets { packet.advance(at: time, busy: true) }
            }
            guard !labelsPending else { return }
            labelsPending = true
            DispatchQueue.main.async { [weak self] in
                self?.labelsPending = false
                self?.syncLabels()
            }
        }

        func render(snapshot: TopologySnapshot, mode: TopologyMode) {
            guard let view, let scene = view.scene else { return }
            self.mode = mode
            let next = snapshot.sites.map(\.id).joined() + "|" + snapshot.services.map(\.id).joined()
                + "|" + snapshot.routes.map { "\($0.caller)-\($0.targetService ?? $0.destinationHost)" }.joined()
                + "|" + snapshot.projects.map { "\($0.id):\($0.analysis?.modules?.count ?? 0):\($0.analysis?.communities?.count ?? 0)" }.joined()
                + "|\(snapshot.projectScope)|\(snapshot.links.map { "\($0.from)-\($0.to)" }.joined())"
            if structureKey != next {
                let scopeChanged = structureKey.split(separator: "|").first != next.split(separator: "|").first
                structureKey = next
                rebuild(snapshot: snapshot, mode: mode, in: scene)
                if scopeChanged {
                    pose = TopologyCamera.Pose(target: SCNVector3(0, 1.2, 0), yaw: 0.55, pitch: 0.62, distance: fitDistance)
                    TopologyCamera.apply(camera, pose: pose)
                }
            } else {
                pulse(snapshot: snapshot, mode: mode)
            }
            applyHighlight()
            applyPresentation()
            syncLabels()
        }

        private func rebuild(snapshot: TopologySnapshot, mode: TopologyMode, in scene: SCNScene) {
            scene.rootNode.childNodes.forEach { if $0 !== camera { $0.removeFromParentNode() } }
            roads.removeAll(); packets.removeAll(); anchors.removeAll(); layerMids.removeAll()
            towerBases.removeAll(); towerHeights.removeAll(); towerGroups.removeAll(); towerBaseHeights.removeAll()
            if camera.parent == nil {
                let lens = SCNCamera()
                lens.fieldOfView = 52
                lens.zNear = 0.05
                lens.zFar = 250
                camera.camera = lens
                scene.rootNode.addChildNode(camera)
                view?.pointOfView = camera
            }
            addLights(to: scene)
            addFloor(to: scene, radius: max(9, Float(snapshot.sites.count) * 1.2 + 2))

            let hub = TopologyLayout.hubPosition()
            let hubNode = SCNNode(geometry: SCNCylinder(radius: 0.62, height: 0.55))
            hubNode.geometry?.firstMaterial = material(red: 0.13, green: 0.36, blue: 0.39, emission: 0.22)
            hubNode.position = SCNVector3(hub.x, 0.28, hub.z)
            hubNode.name = "host"
            scene.rootNode.addChildNode(hubNode)
            addRing(at: SCNVector3(hub.x, 0.04, hub.z), radius: 0.95, color: TopologyLayer.healthy, to: scene)
            towerBases["host"] = SCNVector3(hub.x, 0, hub.z)
            towerHeights["host"] = 0.8
            anchors.append(.init(id: "host", siteID: "host", world: SCNVector3(hub.x + 0.9, 0.7, hub.z),
                                 text: snapshot.node.name, detail: "public edge", color: TopologyLayer.healthy, rank: .name))

            let count = snapshot.sites.count
            let rows = Int(ceil(Double(count) / Double(TopologyLayout.columns(for: count))))
            fitDistance = max(17, Float(rows) * 5.0 + Float(snapshot.services.count) * 0.5)
            pose.distance = max(pose.distance, fitDistance * 0.92)
            let maxEgress = max(1, snapshot.sites.map(\.bytesPerMinute).max() ?? 1)
            var bases: [String: TopologyPoint] = [:]
            for (index, site) in snapshot.sites.enumerated() {
                let placed = TopologyLayout.gridPosition(index: index, count: count)
                let height = TopologyLayer.towerHeight(bytes: site.bytesPerMinute, maxBytes: maxEgress)
                let project = snapshot.projects.first { site.id == $0.id || site.id.hasPrefix($0.id + "/") }
                bases[site.id] = placed
                towerBases[site.id] = SCNVector3(placed.x, 0, placed.z)
                towerHeights[site.id] = height
                addPlate(at: placed, to: scene)
                addTower(site, project: project, position: placed, height: height, routes: snapshot.routes, to: scene)
            }
            let siteXs = bases.values.map(\.x) + [hub.x]
            let siteZs = bases.values.map(\.z) + [hub.z]
            if snapshot.projectScope {
                addLinks(snapshot.links, bases: bases, hub: hub, siteXs: siteXs, siteZs: siteZs, to: scene)
            } else {
                for site in snapshot.sites {
                    guard let base = bases[site.id] else { continue }
                    addRoad(from: "host", to: site.id, start: hub, end: base, kind: .feeder,
                            volume: max(10, site.requestsPerMinute), siteXs: siteXs, siteZs: siteZs, to: scene, animated: true)
                }
                addObservedRoads(snapshot.routes, bases: bases, siteXs: siteXs, siteZs: siteZs, to: scene)
                addExternalTowers(snapshot.services, bases: bases, siteXs: siteXs, siteZs: siteZs, to: scene)
            }
            TopologyCamera.apply(camera, pose: pose)
        }

        private func pulse(snapshot: TopologySnapshot, mode: TopologyMode) {
            let maxEgress = max(1, snapshot.sites.map(\.bytesPerMinute).max() ?? 1)
            for site in snapshot.sites {
                let height = TopologyLayer.towerHeight(bytes: site.bytesPerMinute, maxBytes: maxEgress)
                towerHeights[site.id] = height
                if let group = towerGroups[site.id], let base = towerBaseHeights[site.id], base > 0.15 {
                    group.scale.y = height / base
                }
            }
            for packet in packets {
                let volume = snapshot.sites.first { $0.id == packet.to || $0.id == packet.from }?.requestsPerMinute ?? packet.volume
                packet.retune(volume: max(10, volume))
            }
        }

        private func addPlate(at position: TopologyPoint, to scene: SCNScene) {
            let plate = SCNNode(geometry: SCNBox(width: 3.2, height: 0.08, length: 3.2, chamferRadius: 0.04))
            plate.geometry?.firstMaterial = material(red: 0.08, green: 0.16, blue: 0.2, emission: 0.08)
            plate.position = SCNVector3(position.x, -0.02, position.z)
            scene.rootNode.addChildNode(plate)
        }

        private func addLinks(_ links: [TopologyLink], bases: [String: TopologyPoint], hub: TopologyPoint, siteXs: [Float], siteZs: [Float], to scene: SCNScene) {
            for link in links {
                let start = link.from == "host" ? hub : bases[link.from]
                let end = link.to == "host" ? hub : bases[link.to]
                guard let start, let end else { continue }
                addRoad(from: link.from, to: link.to, start: start, end: end, kind: link.kind,
                        volume: max(10, link.volume), siteXs: siteXs, siteZs: siteZs, to: scene, animated: true)
            }
        }

        private func addObservedRoads(_ routes: [InternalRoute], bases: [String: TopologyPoint], siteXs: [Float], siteZs: [Float], to scene: SCNScene) {
            let ids = Set(bases.keys)
            for route in routes {
                let from = TopologyLayout.resolveSite(route.caller, in: ids)
                let to = TopologyLayout.resolveSite(route.targetService ?? route.destinationHost, in: ids)
                guard let from, let to, from != to, let start = bases[from], let end = bases[to] else { continue }
                addRoad(from: from, to: to, start: start, end: end, kind: .call, volume: max(12, route.requests),
                        siteXs: siteXs, siteZs: siteZs, to: scene, animated: true)
            }
        }

        private func addExternalTowers(_ services: [DataService], bases: [String: TopologyPoint], siteXs: [Float], siteZs: [Float], to scene: SCNScene) {
            let xs = bases.values.map(\.x)
            let zs = bases.values.map(\.z)
            for (index, service) in services.enumerated() {
                let placed = TopologyLayout.externalPosition(index: index, count: services.count, siteXs: xs, siteZs: zs)
                let cache = service.type.lowercased().contains("redis") || service.role.lowercased().contains("cache")
                let color = cache ? UIColor(red: 0.85, green: 0.42, blue: 0.78, alpha: 1) : UIColor(red: 0.35, green: 0.82, blue: 0.62, alpha: 1)
                let height: Float = 1.45
                let pillar = SCNNode(geometry: cache
                    ? SCNBox(width: 0.9, height: CGFloat(height), length: 0.9, chamferRadius: 0.04)
                    : SCNCylinder(radius: 0.42, height: CGFloat(height)))
                pillar.geometry?.firstMaterial = material(color, emission: 0.32)
                pillar.position = SCNVector3(placed.x, height / 2, placed.z)
                pillar.name = "ext:\(service.id)"
                scene.rootNode.addChildNode(pillar)
                addRing(at: SCNVector3(placed.x, 0.04, placed.z), radius: 0.68, color: color, to: scene)
                let key = pillar.name ?? service.id
                towerBases[key] = SCNVector3(placed.x, 0, placed.z)
                towerHeights[key] = height
                anchors.append(.init(id: key, siteID: key, world: SCNVector3(placed.x + 0.85, height * 0.55, placed.z),
                                     text: service.type, detail: service.role, color: color, rank: .name))
                if let siteID = service.siteId, let base = bases[siteID] {
                    addRoad(from: siteID, to: key, start: base, end: placed, kind: .io,
                            volume: 18, siteXs: siteXs + [placed.x], siteZs: siteZs + [placed.z], to: scene, animated: true)
                }
            }
        }

        private func addTower(_ site: Site, project: ProjectHealth?, position: TopologyPoint, height: Float, routes: [InternalRoute], to scene: SCNScene) {
            let layers = TopologyLayer.layers(for: site, project: project)
            let heights = TopologyLayer.fitHeights(weights: layers.map(\.weight), total: height)
            let group = SCNNode()
            group.name = "tower:\(site.id)"
            var cursor: Float = 0
            var mids: [Float] = []
            for (index, layer) in layers.enumerated() {
                let slabHeight = heights.indices.contains(index) ? heights[index] : 0.24
                let midY = cursor + slabHeight * 0.5
                let slab: SCNNode
                if layer.kind == .runtime {
                    let cylinder = SCNCylinder(radius: 0.52, height: CGFloat(max(0.16, slabHeight - 0.04)))
                    cylinder.radialSegmentCount = 28
                    slab = SCNNode(geometry: cylinder)
                } else {
                    slab = SCNNode(geometry: SCNBox(width: 1.05, height: CGFloat(max(0.16, slabHeight - 0.04)), length: 1.05, chamferRadius: 0.03))
                }
                slab.geometry?.firstMaterial = material(layer.color, emission: 0.24)
                slab.position = SCNVector3(0, midY, 0)
                slab.name = "site:\(site.id):\(index):\(layer.kind.rawValue)"
                group.addChildNode(slab)
                addSegment(from: SCNVector3(position.x + 0.54, midY, position.z),
                           to: SCNVector3(position.x + 1.22, midY, position.z),
                           radius: 0.012, color: layer.color, name: nil, to: scene)
                let rank: LabelAnchor.Rank
                switch layer.kind {
                case .runtime: rank = .runtime
                case .module, .community, .hotspot: rank = .analysis
                default: rank = .name
                }
                if rank != .name {
                    anchors.append(.init(id: "site:\(site.id):\(index)", siteID: site.id,
                                         world: SCNVector3(position.x + 1.28, midY, position.z),
                                         text: layer.title, detail: layer.kind == .runtime ? layer.detail : String(layer.detail.prefix(42)),
                                         color: layer.color, rank: rank))
                }
                mids.append(midY)
                cursor += slabHeight + 0.08
            }
            group.position = SCNVector3(position.x, 0, position.z)
            scene.rootNode.addChildNode(group)
            towerGroups[site.id] = group
            towerBaseHeights[site.id] = max(height, cursor)
            layerMids[site.id] = mids
            addRing(at: SCNVector3(position.x, 0.04, position.z), radius: 0.86, color: layers.first?.color ?? .cyan, to: scene)
            anchors.append(.init(id: "name:\(site.id)", siteID: site.id,
                                 world: SCNVector3(position.x + 1.28, max(0.8, height * 0.55), position.z),
                                 text: site.name, detail: "\(Int(site.requestsPerMinute))/min", color: TopologyLayer.healthy, rank: .name))
            addIntraService(site: site, project: project, position: position, mids: mids, routes: routes, to: scene)
        }

        private func addIntraService(site: Site, project: ProjectHealth?, position: TopologyPoint, mids: [Float], routes: [InternalRoute], to scene: SCNScene) {
            let hops = TopologyLayer.hops(for: site, project: project, routes: routes)
            let railX = position.x + 1.22
            for hop in hops {
                guard mids.indices.contains(hop.fromLayer), mids.indices.contains(hop.toLayer) else { continue }
                let start = SCNVector3(railX, mids[hop.fromLayer], position.z)
                let end = SCNVector3(railX, mids[hop.toLayer], position.z)
                let color = hop.weavatrix ? TopologyLayer.moduleColor : TopologyLayer.warning
                let name = "road:\(site.id):inside:\(hop.fromLayer)-\(hop.toLayer)"
                let node = addSegment(from: start, to: end, radius: 0.02, color: color, name: name, to: scene)
                roads.append((site.id, site.id, "inside", [node]))
                let packet = LivePacket(from: site.id, to: site.id, volume: hop.volume, points: [start, end], color: color)
                packet.attach(to: scene, phase: hop.weavatrix ? 0.35 : 0.0)
                packets.append(packet)
            }
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

        private func color(for kind: TopologyRoadKind) -> UIColor {
            switch kind {
            case .feeder: TopologyLayer.healthy
            case .call: TopologyLayer.warning
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
            guard animated, volume > 0, vectors.count > 1 else { return }
            let count = max(1, min(4, Int(volume / 35)))
            for index in 0..<count {
                let packet = LivePacket(from: from, to: to, volume: volume, points: vectors,
                                        color: index.isMultiple(of: 2) ? color : TopologyLayer.warning)
                packet.attach(to: scene, phase: Double(index) / Double(count))
                packets.append(packet)
            }
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
                    } else if name.hasPrefix("site:") || name.hasPrefix("tower:") {
                        connected = name.contains(":\(focus)") || name.hasPrefix("site:\(focus):") || name == "tower:\(focus)"
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
            applyPresentation(connectedFocus: focus != nil || road != nil)
        }

        private func applyPresentation(connectedFocus: Bool = false) {
            let traffic = mode.showsPackets
            for packet in packets {
                packet.node.isHidden = !traffic
                packet.node.scale = SCNVector3(traffic ? 1.2 : 0.01, traffic ? 1.2 : 0.01, traffic ? 1.2 : 0.01)
            }
            guard let scene = view?.scene else { return }
            scene.rootNode.enumerateChildNodes { node, _ in
                guard let name = node.name, let material = node.geometry?.firstMaterial else { return }
                if name.hasPrefix("packet") {
                    node.isHidden = !traffic
                    return
                }
                let inside = name.contains(":inside:")
                if name.hasPrefix("road:") {
                    node.isHidden = traffic && inside
                    let glow: CGFloat = traffic ? (inside ? 0.12 : 0.72) : (inside ? 0.42 : 0.14)
                    if let color = material.diffuse.contents as? UIColor {
                        material.emission.contents = color.withAlphaComponent(glow)
                    }
                    if !connectedFocus {
                        material.transparency = traffic ? (inside ? 0.2 : 1) : (inside ? 0.95 : 0.34)
                    }
                    return
                }
                let kind = name.split(separator: ":").last.map(String.init) ?? ""
                let architecture = ["module", "community", "hotspot", "graph", "scan", "git"].contains(kind)
                if architecture {
                    node.isHidden = traffic
                    material.transparency = traffic ? 0.08 : material.transparency
                }
            }
        }

        private func syncLabels() {
            guard let view else { return }
            let focus = focusedSiteID.wrappedValue
            let chips = anchors.compactMap { anchor -> TopologyLabelCanvas.Item? in
                let projected = view.projectPoint(anchor.world)
                let maxX = Float(view.bounds.maxX), maxY = Float(view.bounds.maxY)
                let onScreen = projected.z >= 0
                    && projected.x > 8 && projected.y > 8
                    && projected.x < maxX - 8 && projected.y < maxY - 8
                let visible: Bool
                switch anchor.rank {
                case .name:
                    visible = focus == nil || anchor.siteID == focus
                case .runtime, .analysis:
                    visible = mode.showsArchitecture && focus == anchor.siteID
                }
                guard onScreen, visible else { return nil }
                return .init(id: anchor.id, text: anchor.text, detail: "",
                             point: CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y)), color: anchor.color)
            }
            labels.render(chips)
        }

        private func moveCamera(animated: Bool) {
            if animated { SCNTransaction.begin(); SCNTransaction.animationDuration = 0.45 }
            TopologyCamera.apply(camera, pose: pose)
            if animated { SCNTransaction.commit() }
            syncLabels()
        }

        func apply(_ action: TopologyCameraAction) {
            switch action {
            case .fit:
                pose = TopologyCamera.Pose(target: SCNVector3(0, 1.2, 0), yaw: 0.55, pitch: 0.62, distance: fitDistance)
                focusedSiteID.wrappedValue = nil
                focusedRoad.wrappedValue = nil
                applyHighlight()
                applyPresentation()
            case .zoomIn: pose.distance = max(TopologyCamera.minDistance, pose.distance * 0.76)
            case .zoomOut: pose.distance = min(TopologyCamera.maxDistance, pose.distance * 1.31)
            case .top: pose.target = SCNVector3(0, 0, 0); pose.pitch = TopologyCamera.maxPitch
            case .isometric: pose.pitch = 0.78; pose.yaw = 0.42
            case .focus:
                if let id = focusedSiteID.wrappedValue, let base = towerBases[id] {
                    pose = TopologyCamera.lock(base: base, height: towerHeights[id] ?? 2)
                }
            case .elevate:
                if let id = focusedSiteID.wrappedValue, let base = towerBases[id] {
                    var next = TopologyCamera.lock(base: base, height: towerHeights[id] ?? 2)
                    next.distance = max(TopologyCamera.minDistance, next.distance * 0.78)
                    next.target.y += 0.6
                    pose = next
                }
            }
            moveCamera(animated: true)
        }

        private func lock(_ id: String, elevate: Bool) {
            focusedSiteID.wrappedValue = id
            focusedRoad.wrappedValue = nil
            applyHighlight()
            apply(elevate ? .elevate : .focus)
        }

        @objc func orbit(_ gesture: UIPanGestureRecognizer) {
            guard let view, gesture.numberOfTouches < 2 else { return }
            let movement = gesture.translation(in: view)
            pose.yaw -= Float(movement.x) * 0.0036
            pose.pitch += Float(movement.y) * 0.0028
            pose = TopologyCamera.clamp(pose)
            gesture.setTranslation(.zero, in: view)
            moveCamera(animated: false)
        }

        @objc func slide(_ gesture: UIPanGestureRecognizer) {
            guard let view else { return }
            TopologyCamera.pan(&pose, translation: gesture.translation(in: view), in: view.bounds.size)
            gesture.setTranslation(.zero, in: view)
            moveCamera(animated: false)
        }

        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            pose.distance = min(TopologyCamera.maxDistance, max(TopologyCamera.minDistance, pose.distance / Float(gesture.scale)))
            gesture.scale = 1
            moveCamera(animated: false)
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let name = pickName(in: gesture) else { return }
            if name.hasPrefix("site:") || name.hasPrefix("tower:") {
                let parts = name.split(separator: ":")
                guard parts.count >= 2 else { return }
                lock(String(parts[1]), elevate: false)
                return
            }
            if name == "host" { lock("host", elevate: false); return }
            if name.hasPrefix("ext:") { lock(name, elevate: false); return }
            if name.hasPrefix("road:") {
                focusedRoad.wrappedValue = name
                let parts = name.split(separator: ":")
                if parts.count >= 3 { focusedSiteID.wrappedValue = String(parts[1]) }
                applyHighlight()
                syncLabels()
            }
        }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let name = pickName(in: gesture) else {
                apply(.fit)
                return
            }
            if name.hasPrefix("site:") {
                let parts = name.split(separator: ":")
                if parts.count >= 2 {
                    focusedSiteID.wrappedValue = String(parts[1])
                    if parts.count == 3, let layer = Int(parts[2]) {
                        selection.wrappedValue = TopologySelection(siteID: String(parts[1]), layer: layer)
                    }
                    lock(String(parts[1]), elevate: true)
                    return
                }
            }
            if name.hasPrefix("ext:") || name == "host" { lock(name, elevate: true); return }
            apply(.fit)
        }

        private func pickName(in gesture: UITapGestureRecognizer) -> String? {
            guard let view else { return nil }
            let hits = view.hitTest(gesture.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            let names = hits.compactMap(\.node.name).filter { !$0.hasPrefix("packet") }
            return names.first { $0.hasPrefix("site:") || $0.hasPrefix("tower:") || $0.hasPrefix("ext:") || $0 == "host" }
                ?? names.first { $0.hasPrefix("road:") }
        }
    }
}

private struct LabelAnchor {
    enum Rank { case name, runtime, analysis }
    let id: String
    let siteID: String
    let world: SCNVector3
    let text: String
    let detail: String
    let color: UIColor
    let rank: Rank
}

private final class LivePacket {
    let from: String
    let to: String
    var volume: Double
    let points: [SCNVector3]
    let node: SCNNode
    private var phase: Double = 0
    private var lengths: [Float] = []
    private var total: Float = 0

    init(from: String, to: String, volume: Double, points: [SCNVector3], color: UIColor) {
        self.from = from
        self.to = to
        self.volume = volume
        self.points = points
        node = SCNNode(geometry: SCNSphere(radius: 0.22))
        node.name = "packet"
        node.geometry?.firstMaterial = {
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.emission.contents = color.withAlphaComponent(0.85)
            return material
        }()
        node.position = points.first ?? SCNVector3Zero
        measure()
    }

    func attach(to scene: SCNScene, phase: Double) {
        self.phase = phase
        scene.rootNode.addChildNode(node)
        advance(at: 0, busy: true)
    }

    func retune(volume: Double) {
        self.volume = volume
    }

    func advance(at time: TimeInterval, busy: Bool) {
        guard total > 0.001 else { return }
        let speed = Float((busy ? 1.35 : 0.72) + min(2.8, volume / 70))
        let travelled = (Float(time) * speed + Float(phase) * total).truncatingRemainder(dividingBy: total)
        node.position = point(at: travelled)
        node.isHidden = false
    }

    private func measure() {
        lengths = []
        total = 0
        guard points.count > 1 else { return }
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            let length = sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) + (b.z - a.z) * (b.z - a.z))
            lengths.append(length)
            total += length
        }
    }

    private func point(at distance: Float) -> SCNVector3 {
        var remaining = distance
        for index in 0..<lengths.count {
            let length = lengths[index]
            if remaining <= length {
                let t = length > 0 ? remaining / length : 0
                let a = points[index], b = points[index + 1]
                return SCNVector3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
            }
            remaining -= length
        }
        return points.last ?? SCNVector3Zero
    }
}

private final class TopologyLabelCanvas: UIView {
    struct Item {
        let id: String
        let text: String
        let detail: String
        let point: CGPoint
        let color: UIColor
    }

    private var chips: [String: UILabel] = [:]

    func render(_ items: [Item]) {
        let keep = Set(items.map(\.id))
        chips.keys.filter { !keep.contains($0) }.forEach {
            chips[$0]?.removeFromSuperview()
            chips[$0] = nil
        }
        let ordered = items.sorted { $0.point.y < $1.point.y }
        var lastBottom: CGFloat = -1_000
        for item in ordered {
            let chip = chips[item.id] ?? makeChip()
            let text = item.detail.isEmpty ? "  \(item.text)  " : "  \(item.text)   \(item.detail)  "
            chip.text = text
            chip.textColor = item.color
            chip.sizeToFit()
            let width = min(168, chip.intrinsicContentSize.width + 14)
            let height = chip.intrinsicContentSize.height + 6
            var y = item.point.y - height / 2
            if y < lastBottom + 2 { y = lastBottom + 2 }
            lastBottom = y + height
            chip.frame = CGRect(x: item.point.x + 6, y: y, width: width, height: height)
            chip.isHidden = false
            if chip.superview == nil { addSubview(chip) }
            chips[item.id] = chip
        }
    }

    private func makeChip() -> UILabel {
        let chip = UILabel()
        chip.font = .systemFont(ofSize: 11, weight: .semibold)
        chip.textAlignment = .left
        chip.backgroundColor = UIColor(red: 0.04, green: 0.08, blue: 0.1, alpha: 0.78)
        chip.layer.cornerRadius = 5
        chip.layer.masksToBounds = true
        chip.layoutMargins = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        return chip
    }
}
