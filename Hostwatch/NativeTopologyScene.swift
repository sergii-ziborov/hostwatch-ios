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

struct TopologyLabelInfo: Identifiable {
    let id: String
    let title: String
    let detail: String
    let explanation: String
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
    @Binding var labelInfo: TopologyLabelInfo?
    @Binding var focusedSiteID: String?
    @Binding var focusedRoad: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, labelInfo: $labelInfo,
                    focusedSiteID: $focusedSiteID, focusedRoad: $focusedRoad)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = UIColor(red: 7 / 255, green: 13 / 255, blue: 20 / 255, alpha: 1)
        let constrained = ProcessInfo.processInfo.physicalMemory < 3_000_000_000
        view.antialiasingMode = constrained ? .none : .multisampling2X
        view.rendersContinuously = mode.showsPackets
        view.isPlaying = mode.showsPackets
        view.preferredFramesPerSecond = constrained ? 20 : 30
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
        context.coordinator.attach(view, orbit: orbit, tap: tap)
        context.coordinator.render(snapshot: snapshot, mode: mode)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.labelInfo = $labelInfo
        context.coordinator.focusedSiteID = $focusedSiteID
        context.coordinator.focusedRoad = $focusedRoad
        context.coordinator.updatePlayback(mode: mode)
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
        var labelInfo: Binding<TopologyLabelInfo?>
        var focusedSiteID: Binding<String?>
        var focusedRoad: Binding<String?>
        var lastCommand = 0
        private var structureKey = ""
        private var previousSiteIDs: [String] = []
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
        private var labelTrackingGeneration = 0
        private var trackingLabels = false

        init(selection: Binding<TopologySelection?>, labelInfo: Binding<TopologyLabelInfo?>,
             focusedSiteID: Binding<String?>, focusedRoad: Binding<String?>) {
            self.selection = selection
            self.labelInfo = labelInfo
            self.focusedSiteID = focusedSiteID
            self.focusedRoad = focusedRoad
        }

        func attach(_ view: SCNView, orbit: UIPanGestureRecognizer, tap: UITapGestureRecognizer) {
            self.view = view
            labels.frame = view.bounds
            labels.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            labels.isUserInteractionEnabled = true
            labels.onTapItem = { [weak self] id in self?.selectLabel(id) }
            labels.onScrollLayers = { [weak self] points in self?.scrollFocusedTower(by: points) }
            view.addSubview(labels)
            orbit.require(toFail: labels.scrollGesture)
            tap.require(toFail: labels.tapGesture)
        }

        func updatePlayback(mode: TopologyMode) {
            let active = mode.showsPackets || trackingLabels
            view?.rendersContinuously = active
            view?.isPlaying = active
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
            let siteStructure = snapshot.sites.map { site -> String in
                let project = snapshot.projects.first { site.id == $0.id || site.id.hasPrefix($0.id + "/") }
                let layers = TopologyLayer.layers(for: site, project: project)
                    .map { "\($0.kind.rawValue):\($0.title)" }.joined(separator: ",")
                return "\(site.id)[\(layers)]"
            }.joined(separator: ";")
            let next = siteStructure + "|" + snapshot.services.map(\.id).joined()
                + "|" + snapshot.routes.map { "\($0.caller)-\($0.targetService ?? $0.destinationHost)" }.joined()
                + "|" + snapshot.projects.map { "\($0.id):\($0.analysis?.modules?.count ?? 0):\($0.analysis?.communities?.count ?? 0)" }.joined()
                + "|\(snapshot.projectScope)|\(snapshot.links.map { "\($0.from)-\($0.to)" }.joined())"
            if structureKey != next {
                let siteIDs = snapshot.sites.map(\.id)
                let scopeChanged = previousSiteIDs != siteIDs
                previousSiteIDs = siteIDs
                structureKey = next
                rebuild(snapshot: snapshot, mode: mode, in: scene)
                if scopeChanged {
                    if let id = focusedSiteID.wrappedValue, let base = towerBases[id] {
                        pose = TopologyCamera.lock(base: base, height: towerHeights[id] ?? 2, aspect: viewAspect)
                    } else {
                        pose = TopologyCamera.Pose(target: SCNVector3(0, 1.2, 0), yaw: 0.55, pitch: 0.62, distance: fitDistance)
                    }
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
            anchors.append(.init(id: "host", siteID: "host", world: SCNVector3(hub.x, 0.7, hub.z),
                                 localY: 0.7, usesTower: false,
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
                addTower(site, project: project, position: placed, height: height, to: scene)
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
            var resized = false
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.24
            for site in snapshot.sites {
                let height = TopologyLayer.towerHeight(bytes: site.bytesPerMinute, maxBytes: maxEgress)
                towerHeights[site.id] = height
                let project = snapshot.projects.first { site.id == $0.id || site.id.hasPrefix($0.id + "/") }
                for (index, layer) in TopologyLayer.layers(for: site, project: project).enumerated() {
                    guard let anchorIndex = anchors.firstIndex(where: { $0.id == "site:\(site.id):\(index)" }) else { continue }
                    anchors[anchorIndex].detail = layer.kind == .runtime ? layer.detail : String(layer.detail.prefix(42))
                }
                if let group = towerGroups[site.id], let base = towerBaseHeights[site.id], base > 0.15 {
                    let nextScale = height / base
                    resized = resized || abs(group.scale.y - nextScale) > 0.002
                    group.scale.y = nextScale
                }
            }
            SCNTransaction.commit()
            for packet in packets {
                let volume = snapshot.sites.first { $0.id == packet.to || $0.id == packet.from }?.requestsPerMinute ?? packet.volume
                packet.retune(volume: max(10, volume))
            }
            if resized { trackLabels(for: 0.34) }
            view?.setNeedsDisplay()
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
                anchors.append(.init(id: key, siteID: key, world: SCNVector3(placed.x, height * 0.55, placed.z),
                                     localY: height * 0.55, usesTower: false,
                                     text: service.type, detail: service.role, color: color, rank: .name))
                if let siteID = service.siteId, let base = bases[siteID] {
                    addRoad(from: siteID, to: key, start: base, end: placed, kind: .io,
                            volume: 18, siteXs: siteXs + [placed.x], siteZs: siteZs + [placed.z], to: scene, animated: true)
                }
            }
        }

        private func addTower(_ site: Site, project: ProjectHealth?, position: TopologyPoint, height: Float, to scene: SCNScene) {
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
                let rank: LabelAnchor.Rank = layer.kind == .runtime ? .runtime : .analysis
                anchors.append(.init(id: "site:\(site.id):\(index)", siteID: site.id,
                                     world: SCNVector3(position.x, midY, position.z),
                                     localY: midY, usesTower: true,
                                     text: layer.title, detail: layer.kind == .runtime ? layer.detail : String(layer.detail.prefix(42)),
                                     color: layer.color, rank: rank))
                mids.append(midY)
                cursor += slabHeight + (index < layers.count - 1 ? 0.08 : 0)
            }
            let hit = SCNNode(geometry: SCNCylinder(radius: 0.95, height: CGFloat(max(1.1, cursor))))
            hit.geometry?.firstMaterial = {
                let clear = SCNMaterial()
                clear.diffuse.contents = UIColor.clear
                clear.transparency = 0
                clear.writesToDepthBuffer = false
                return clear
            }()
            hit.position = SCNVector3(0, max(0.55, cursor * 0.5), 0)
            hit.name = "hit:\(site.id)"
            group.addChildNode(hit)
            group.position = SCNVector3(position.x, 0, position.z)
            let baseHeight = max(0.16, cursor)
            group.scale.y = height / baseHeight
            scene.rootNode.addChildNode(group)
            towerGroups[site.id] = group
            towerBaseHeights[site.id] = baseHeight
            layerMids[site.id] = mids
            addRing(at: SCNVector3(position.x, 0.04, position.z), radius: 0.86, color: layers.first?.color ?? .cyan, to: scene)
            anchors.append(.init(id: "name:\(site.id)", siteID: site.id,
                                 world: SCNVector3(position.x, max(0.7, height), position.z),
                                 localY: max(0.7, cursor), usesTower: true,
                                 text: site.name, detail: "\(Int(site.requestsPerMinute))/min", color: TopologyLayer.healthy, rank: .name))
        }

        private func addFloor(to scene: SCNScene, radius: Float) {
            let size = CGFloat(radius * 2.6)
            let floor = SCNNode(geometry: SCNPlane(width: size, height: size))
            floor.geometry?.firstMaterial = material(red: 0.035, green: 0.065, blue: 0.085)
            floor.eulerAngles.x = -.pi / 2
            floor.position.y = -0.08
            scene.rootNode.addChildNode(floor)
            for index in -4...4 {
                let offset = Float(index) * radius / 4
                let ink = UIColor(red: 0.11, green: 0.24, blue: 0.28, alpha: 0.45)
                addSegment(from: SCNVector3(-radius * 1.2, -0.06, offset), to: SCNVector3(radius * 1.2, -0.06, offset),
                           radius: 0.002, color: ink, name: nil, to: scene)
                addSegment(from: SCNVector3(offset, -0.06, -radius * 1.2), to: SCNVector3(offset, -0.06, radius * 1.2),
                           radius: 0.002, color: ink, name: nil, to: scene)
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
            addSourceMarker(from: from, to: to, kind: kind, along: vectors, to: scene)
            if let mid = flowLabelPoint(vectors) {
                anchors.append(.init(id: "flow:\(from):\(to):\(kind.rawValue)", siteID: from,
                                     world: mid, localY: mid.y, usesTower: false,
                                     text: flowLabel(from: from, to: to, kind: kind),
                                     detail: "\(kind.origin.title) · \(Int(volume))/min", color: color, rank: .flow))
            }
            guard animated, volume > 0, vectors.count > 1 else { return }
            let count = max(1, min(4, Int(volume / 35)))
            for index in 0..<count {
                let packet = LivePacket(from: from, to: to, volume: volume, points: vectors, color: color)
                packet.attach(to: scene, phase: Double(index) / Double(count))
                packets.append(packet)
            }
        }

        private func flowLabel(from: String, to: String, kind: TopologyRoadKind) -> String {
            let source = from == "host" ? "Public" : shortBoardName(from)
            let dest = to.hasPrefix("ext:") ? shortBoardName(to) : shortBoardName(to)
            return "\(source) → \(dest)"
        }

        private func shortBoardName(_ id: String) -> String {
            if id == "host" { return "Public" }
            if id.hasPrefix("ext:") { return String(id.dropFirst(4)).split(separator: "-").first.map(String.init) ?? id }
            return id.split(separator: "/").last.map(String.init) ?? id
        }

        private func flowLabelPoint(_ points: [SCNVector3]) -> SCNVector3? {
            guard points.count > 1 else { return points.first }
            let a = points[0], b = points[1]
            return SCNVector3((a.x * 2 + b.x) / 3, TopologyLayout.roadY + 0.28, (a.z * 2 + b.z) / 3)
        }

        private func addSourceMarker(from: String, to: String, kind: TopologyRoadKind, along points: [SCNVector3], to scene: SCNScene) {
            guard points.count > 1 else { return }
            let start = points[0], next = points[1]
            let marker = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.13, height: 0.34))
            marker.geometry?.firstMaterial = material(color(for: kind), emission: 0.78)
            marker.position = SCNVector3(start.x, TopologyLayout.roadY + 0.24, start.z)
            marker.name = "src:\(from):\(to):\(kind.rawValue)"
            let dx = next.x - start.x, dz = next.z - start.z
            marker.eulerAngles.x = .pi / 2
            marker.eulerAngles.y = atan2(dx, dz)
            scene.rootNode.addChildNode(marker)
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
                guard let name = node.name, let material = node.geometry?.firstMaterial, !name.hasPrefix("hit:") else { return }
                let connected: Bool
                if let road, name.hasPrefix("road:") || name.hasPrefix("src:") {
                    connected = TopologyFlow.parse(roadName: name.hasPrefix("src:") ? "road:" + String(name.dropFirst(4)) : name)
                        .map { flow in TopologyFlow.parse(roadName: road).map { $0.from == flow.from && $0.to == flow.to && $0.kind == flow.kind } ?? false }
                        ?? (name == road)
                } else if let focus {
                    if name.hasPrefix("road:") || name.hasPrefix("src:") {
                        connected = roads.contains { ($0.from == focus || $0.to == focus) && ($0.nodes.contains(where: { $0 === node }) || name.contains(":\($0.from):\($0.to):")) }
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
                guard let name = node.name, let material = node.geometry?.firstMaterial, !name.hasPrefix("hit:") else { return }
                if name.hasPrefix("packet") || name.hasPrefix("src:") {
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
                if name == "host", traffic {
                    material.emission.contents = TopologyLayer.healthy.withAlphaComponent(0.55)
                }
            }
        }

        private func resolvedWorld(_ anchor: LabelAnchor) -> SCNVector3 {
            guard anchor.usesTower, let group = towerGroups[anchor.siteID] else { return anchor.world }
            return group.presentation.convertPosition(SCNVector3(0, anchor.localY, 0), to: nil)
        }

        private func syncLabels() {
            guard let view else { return }
            let focus = focusedSiteID.wrappedValue
            let chips = anchors.compactMap { anchor -> TopologyLabelCanvas.Item? in
                let world = resolvedWorld(anchor)
                let projected = view.projectPoint(world)
                let onScreen = projected.z >= 0
                    && projected.x > -40 && projected.y > 8
                    && projected.x < Float(view.bounds.maxX) + 40
                    && projected.y < Float(view.bounds.maxY) - 8
                let visible: Bool
                switch anchor.rank {
                case .name:
                    visible = focus == nil || anchor.siteID == focus
                case .flow:
                    visible = mode.showsPackets && flowLabelVisible(anchor, focus: focus)
                case .runtime, .analysis:
                    visible = mode.showsArchitecture && focus == anchor.siteID
                }
                let focusedLayer = (anchor.rank == .runtime || anchor.rank == .analysis) && focus == anchor.siteID
                guard projected.z >= 0, visible, onScreen || focusedLayer else { return nil }
                let titled = titledAnchor(anchor)
                return .init(id: anchor.id, text: titled.text, detail: titled.detail,
                             point: calloutOrigin(for: world), color: titled.color, rank: anchor.rank)
            }
            let names = chips.filter { $0.rank == .name || $0.rank == .flow }
            let layers = chips.filter { $0.rank == .runtime || $0.rank == .analysis }
            var band: ClosedRange<CGFloat>?
            if let focus {
                let topLocal = towerBaseHeights[focus] ?? towerHeights[focus] ?? 2
                let topWorld: SCNVector3
                let bottomWorld: SCNVector3
                if let group = towerGroups[focus] {
                    topWorld = group.presentation.convertPosition(SCNVector3(0, topLocal, 0), to: nil)
                    bottomWorld = group.presentation.convertPosition(SCNVector3(0, 0.12, 0), to: nil)
                } else if let base = towerBases[focus] {
                    topWorld = SCNVector3(base.x, topLocal, base.z)
                    bottomWorld = SCNVector3(base.x, 0.12, base.z)
                } else {
                    topWorld = SCNVector3Zero
                    bottomWorld = SCNVector3Zero
                }
                let top = calloutOrigin(for: topWorld).y
                let bottom = calloutOrigin(for: bottomWorld).y
                let lo = max(10, min(top, bottom))
                let hi = min(labels.bounds.maxY - 10, max(top, bottom))
                if hi - lo > 12 { band = lo...hi }
            }
            labels.render(names: names, layers: layers, band: band, focusID: focus)
        }

        private func titledAnchor(_ anchor: LabelAnchor) -> (text: String, detail: String, color: UIColor) {
            let focus = focusedSiteID.wrappedValue
            if anchor.rank == .flow {
                return (anchor.text, focus == nil ? "" : anchor.detail, anchor.color)
            }
            if mode.showsPackets, anchor.rank == .name {
                if anchor.siteID == "host" {
                    return ("PUBLIC", focus == nil ? "" : "external clients", TopologyLayer.healthy)
                }
                if anchor.siteID.hasPrefix("ext:") {
                    return (anchor.text, focus == nil ? "" : "our data", UIColor(red: 0.35, green: 0.82, blue: 0.62, alpha: 1))
                }
                return (anchor.text, focus == nil ? "" : "our service", TopologyLayer.warning)
            }
            let detail = focus == anchor.siteID ? anchor.detail : ""
            return (anchor.text, detail, anchor.color)
        }

        private func flowLabelVisible(_ anchor: LabelAnchor, focus: String?) -> Bool {
            if let road = focusedRoad.wrappedValue, let selected = TopologyFlow.parse(roadName: road) {
                return anchor.id == "flow:\(selected.from):\(selected.to):\(selected.kind.rawValue)"
            }
            if let focus {
                return anchor.id.hasPrefix("flow:\(focus):") || anchor.id.contains(":\(focus):")
            }
            return false
        }

        private func calloutOrigin(for world: SCNVector3) -> CGPoint {
            guard let view else { return .zero }
            let center = view.projectPoint(world)
            var right = center.x
            let radius: Float = 0.62
            for step in 0..<12 {
                let angle = Float(step) * (.pi / 6)
                let sample = view.projectPoint(SCNVector3(world.x + cos(angle) * radius, world.y, world.z + sin(angle) * radius))
                if sample.z >= 0 { right = max(right, sample.x) }
            }
            return CGPoint(x: CGFloat(right), y: CGFloat(center.y))
        }

        private func moveCamera(animated: Bool) {
            if animated { SCNTransaction.begin(); SCNTransaction.animationDuration = 0.45 }
            TopologyCamera.apply(camera, pose: pose)
            if animated { SCNTransaction.commit() }
            if animated { trackLabels(for: 0.55) }
            view?.setNeedsDisplay()
            syncLabels()
        }

        private func trackLabels(for duration: TimeInterval) {
            guard let view else { return }
            labelTrackingGeneration += 1
            let generation = labelTrackingGeneration
            trackingLabels = true
            updatePlayback(mode: mode)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak view] in
                guard let self, let view, generation == self.labelTrackingGeneration else { return }
                self.trackingLabels = false
                self.updatePlayback(mode: self.mode)
                view.setNeedsDisplay()
                self.syncLabels()
            }
        }

        func apply(_ action: TopologyCameraAction) {
            switch action {
            case .fit:
                pose = TopologyCamera.Pose(target: SCNVector3(0, 1.2, 0), yaw: 0.55, pitch: 0.62, distance: fitDistance)
                focusedSiteID.wrappedValue = nil
                focusedRoad.wrappedValue = nil
                labels.resetWindow()
                applyHighlight()
                applyPresentation()
            case .zoomIn: pose.distance = max(TopologyCamera.minDistance, pose.distance * 0.76)
            case .zoomOut: pose.distance = min(TopologyCamera.maxDistance, pose.distance * 1.31)
            case .top: pose.target = SCNVector3(0, 0, 0); pose.pitch = TopologyCamera.maxPitch
            case .isometric: pose.pitch = 0.78; pose.yaw = 0.42
            case .focus:
                if let id = focusedSiteID.wrappedValue, let base = towerBases[id] {
                    pose = TopologyCamera.lock(base: base, height: towerHeights[id] ?? 2, aspect: viewAspect)
                }
            case .elevate:
                if let id = focusedSiteID.wrappedValue, let base = towerBases[id] {
                    var next = TopologyCamera.lock(base: base, height: towerHeights[id] ?? 2, aspect: viewAspect)
                    next.distance = max(TopologyCamera.minDistance, next.distance * 0.78)
                    next.target.y += 0.6
                    pose = next
                }
            }
            moveCamera(animated: true)
        }

        private var viewAspect: Float {
            guard let view, view.bounds.height > 0 else { return 0.65 }
            return Float(view.bounds.width / view.bounds.height)
        }

        private func lock(_ id: String, elevate: Bool) {
            if focusedSiteID.wrappedValue != id { labels.resetWindow() }
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
                if let flow = TopologyFlow.parse(roadName: name) {
                    focusedSiteID.wrappedValue = flow.from
                }
                applyHighlight()
                syncLabels()
            }
        }

        private func selectLabel(_ id: String) {
            if id.hasPrefix("name:") {
                let siteID = String(id.dropFirst("name:".count))
                lock(siteID, elevate: false)
                selection.wrappedValue = TopologySelection(siteID: siteID, layer: nil)
            } else if id.hasPrefix("site:") {
                let components = id.split(separator: ":", maxSplits: 2)
                guard components.count == 3, let layer = Int(components[2]) else { return }
                let siteID = String(components[1])
                lock(siteID, elevate: false)
                selection.wrappedValue = TopologySelection(siteID: siteID, layer: layer)
            } else if id.hasPrefix("flow:") {
                let roadName = "road:" + id.dropFirst("flow:".count)
                guard let flow = TopologyFlow.parse(roadName: roadName) else { return }
                focusedRoad.wrappedValue = roadName
                focusedSiteID.wrappedValue = flow.from
                applyHighlight()
                syncLabels()
                labelInfo.wrappedValue = TopologyLabelInfo(
                    id: id, title: anchors.first(where: { $0.id == id })?.text ?? "\(flow.from) → \(flow.to)",
                    detail: anchors.first(where: { $0.id == id })?.detail ?? flow.origin.title,
                    explanation: flow.origin == .external ? "Public client traffic entering the edge."
                        : flow.origin == .ourService ? "A call between services that we operate."
                        : "A service accessing our database or cache."
                )
            } else if id == "host" || id.hasPrefix("ext:") {
                lock(id, elevate: false)
                if let anchor = anchors.first(where: { $0.id == id }) {
                    labelInfo.wrappedValue = TopologyLabelInfo(
                        id: id, title: anchor.text, detail: anchor.detail,
                        explanation: id == "host" ? "Public traffic enters the infrastructure through this node."
                            : "This is a data service used by the application."
                    )
                }
            }
        }

        private func scrollFocusedTower(by points: CGFloat) {
            guard mode.showsArchitecture, let view, let id = focusedSiteID.wrappedValue,
                  let group = towerGroups[id], let baseHeight = towerBaseHeights[id],
                  let height = towerHeights[id], height > 0.5, view.bounds.height > 0 else { return }
            let top = group.presentation.convertPosition(SCNVector3(0, baseHeight, 0), to: nil)
            let bottom = group.presentation.convertPosition(SCNVector3Zero, to: nil)
            let projectedHeight = abs(view.projectPoint(top).y - view.projectPoint(bottom).y)
            guard projectedHeight > Float(view.bounds.height) * 0.75 else { return }
            let worldPerPoint = pose.distance * 2 * tan(52 * Float.pi / 360) / Float(view.bounds.height)
            let next = min(height - 0.25, max(0.25, pose.target.y + Float(points) * worldPerPoint))
            guard abs(next - pose.target.y) > 0.001 else { return }
            pose.target.y = next
            moveCamera(animated: false)
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
            let tap = gesture.location(in: view)
            let hits = view.hitTest(tap, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            let names = hits.compactMap(\.node.name).filter { !$0.hasPrefix("packet") }
            if let tower = names.first(where: { $0.hasPrefix("site:") || $0.hasPrefix("tower:") || $0.hasPrefix("hit:") || $0.hasPrefix("ext:") || $0 == "host" }) {
                return tower.hasPrefix("hit:") ? "tower:" + tower.dropFirst("hit:".count) : tower
            }
            if let road = names.first(where: { $0.hasPrefix("road:") }) { return road }
            var nearest: (id: String, distance: CGFloat)?
            for (id, base) in towerBases {
                let mid = SCNVector3(base.x, max(0.6, (towerHeights[id] ?? 1.6) * 0.5), base.z)
                let projected = view.projectPoint(mid)
                guard projected.z >= 0 else { continue }
                let distance = hypot(CGFloat(projected.x) - tap.x, CGFloat(projected.y) - tap.y)
                if distance < 56, nearest == nil || distance < nearest!.distance {
                    nearest = (id, distance)
                }
            }
            if let nearest {
                return nearest.id == "host" || nearest.id.hasPrefix("ext:") ? nearest.id : "tower:\(nearest.id)"
            }
            return nil
        }
    }
}

private struct LabelAnchor {
    enum Rank { case name, flow, runtime, analysis }
    let id: String
    let siteID: String
    let world: SCNVector3
    let localY: Float
    let usesTower: Bool
    let text: String
    var detail: String
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
        var rank: LabelAnchor.Rank = .name
    }

    private var chips: [String: UILabel] = [:]
    private var leaders: [(CGPoint, CGPoint, UIColor)] = []
    private var windowStart = 0
    private var lastFocus: String?
    private var lastNames: [Item] = []
    private var lastLayers: [Item] = []
    private var lastBand: ClosedRange<CGFloat>?
    private var lastVisible = 4
    private var scrollRemainder: CGFloat = 0
    var onTapItem: ((String) -> Void)?
    var onScrollLayers: ((CGFloat) -> Void)?
    let scrollGesture = UIPanGestureRecognizer()
    let tapGesture = UITapGestureRecognizer()
    private let moreAbove = UIButton(type: .system)
    private let moreBelow = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        configureMore(moreAbove)
        configureMore(moreBelow)
        moreAbove.addTarget(self, action: #selector(pageUp), for: .touchUpInside)
        moreBelow.addTarget(self, action: #selector(pageDown), for: .touchUpInside)
        addSubview(moreAbove)
        addSubview(moreBelow)
        scrollGesture.addTarget(self, action: #selector(scrollLayers(_:)))
        scrollGesture.maximumNumberOfTouches = 1
        scrollGesture.cancelsTouchesInView = false
        addGestureRecognizer(scrollGesture)
        tapGesture.addTarget(self, action: #selector(tapLabel(_:)))
        tapGesture.require(toFail: scrollGesture)
        addGestureRecognizer(tapGesture)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit !== self { return hit }
        return labelScrollFrame.contains(point) || item(at: point) != nil ? self : nil
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        for (start, end, color) in leaders {
            context.setStrokeColor(color.withAlphaComponent(0.7).cgColor)
            context.setLineWidth(1)
            context.move(to: start)
            context.addLine(to: CGPoint(x: (start.x + end.x) / 2, y: start.y))
            context.addLine(to: end)
            context.strokePath()
            if end.x > start.x + 8 {
                context.move(to: CGPoint(x: end.x - 5, y: end.y - 3))
                context.addLine(to: end)
                context.addLine(to: CGPoint(x: end.x - 5, y: end.y + 3))
                context.strokePath()
            }
        }
    }

    func resetWindow() {
        windowStart = 0
    }

    func render(names: [Item], layers: [Item], band: ClosedRange<CGFloat>?, focusID: String?) {
        if focusID != lastFocus {
            windowStart = 0
            lastFocus = focusID
        }
        lastNames = names
        lastLayers = layers
        lastBand = band
        let keep = Set((names + layers).map(\.id))
        chips.keys.filter { !keep.contains($0) }.forEach {
            chips[$0]?.removeFromSuperview()
            chips[$0] = nil
        }
        chips.values.forEach { $0.isHidden = true }
        var nextLeaders: [(CGPoint, CGPoint, UIColor)] = []
        place(names.sorted { $0.point.y < $1.point.y }, band: nil, into: &nextLeaders)
        if let band {
            let ordered = layers.sorted { $0.point.y < $1.point.y }
            let measured = measure(ordered)
            let preferred = measured.map { $0.item.point.y - $0.height / 2 }
            let window = TopologyLayout.arrangeLabels(
                preferredTops: preferred,
                heights: measured.map(\.height),
                minY: band.lowerBound + 18,
                maxY: band.upperBound - 18,
                start: windowStart
            )
            windowStart = window.start
            lastVisible = max(1, window.count)
            let visible = Array(measured.dropFirst(window.start).prefix(window.count))
            for (index, row) in visible.enumerated() {
                let top = window.tops.indices.contains(index) ? window.tops[index] : row.item.point.y - row.height / 2
                place(row, top: top, into: &nextLeaders)
            }
            layoutMore(moreAbove, text: "▲ \(window.moreAbove) more", visible: window.moreAbove > 0, y: band.lowerBound)
            layoutMore(moreBelow, text: "▼ \(window.moreBelow) more", visible: window.moreBelow > 0, y: band.upperBound - 22)
        } else {
            place(layers.sorted { $0.point.y < $1.point.y }, band: nil, into: &nextLeaders)
            moreAbove.isHidden = true
            moreBelow.isHidden = true
        }
        leaders = nextLeaders
        setNeedsDisplay()
    }

    @objc private func pageUp() {
        windowStart = max(0, windowStart - pageSize)
        onScrollLayers?(CGFloat(pageSize) * 24)
        render(names: lastNames, layers: lastLayers, band: lastBand, focusID: lastFocus)
    }

    @objc private func pageDown() {
        windowStart += pageSize
        onScrollLayers?(-CGFloat(pageSize) * 24)
        render(names: lastNames, layers: lastLayers, band: lastBand, focusID: lastFocus)
    }

    @objc private func scrollLayers(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            scrollRemainder = 0
        case .changed:
            let movement = gesture.translation(in: self).y
            scrollRemainder += movement
            gesture.setTranslation(.zero, in: self)
            onScrollLayers?(movement)
            let row: CGFloat = 24
            while abs(scrollRemainder) >= row {
                let delta = scrollRemainder < 0 ? 1 : -1
                scrollRemainder += scrollRemainder < 0 ? row : -row
                scrollWindow(by: delta)
            }
        case .ended, .cancelled:
            if abs(scrollRemainder) > 10 { scrollWindow(by: scrollRemainder < 0 ? 1 : -1) }
            scrollRemainder = 0
        default:
            break
        }
    }

    @objc private func tapLabel(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let id = item(at: gesture.location(in: self)) else { return }
        onTapItem?(id)
    }

    private func item(at point: CGPoint) -> String? {
        for entry in lastLayers + lastNames {
            if let chip = chips[entry.id], !chip.isHidden, chip.frame.contains(point) { return entry.id }
        }
        return nil
    }

    private func scrollWindow(by delta: Int) {
        let maxStart = max(0, lastLayers.count - max(1, lastVisible))
        let next = min(maxStart, max(0, windowStart + delta))
        guard next != windowStart else { return }
        windowStart = next
        render(names: lastNames, layers: lastLayers, band: lastBand, focusID: lastFocus)
    }

    private var labelScrollFrame: CGRect {
        guard let band = lastBand else { return .null }
        let visibleFrames = lastLayers.compactMap { item -> CGRect? in
            guard let chip = chips[item.id], !chip.isHidden else { return nil }
            return chip.frame
        }
        guard var frame = visibleFrames.first else { return .null }
        for next in visibleFrames.dropFirst() { frame = frame.union(next) }
        return CGRect(x: frame.minX - 24, y: band.lowerBound,
                      width: frame.width + 48, height: band.upperBound - band.lowerBound).intersection(bounds)
    }

    private var pageSize: Int { max(1, lastVisible - 2) }

    private func measure(_ items: [Item]) -> [(item: Item, chip: UILabel, width: CGFloat, height: CGFloat)] {
        items.map { item in
            let chip = chips[item.id] ?? makeChip()
            chip.text = item.detail.isEmpty ? "  \(item.text)  " : "  \(item.text)   \(item.detail)  "
            chip.textColor = item.color
            chip.sizeToFit()
            chips[item.id] = chip
            return (item, chip, min(172, chip.intrinsicContentSize.width + 14), chip.intrinsicContentSize.height + 6)
        }
    }

    private func place(_ items: [Item], band: ClosedRange<CGFloat>?, into leaders: inout [(CGPoint, CGPoint, UIColor)]) {
        let measured = measure(items)
        var cursor: CGFloat = -1_000
        for row in measured {
            var top = row.item.point.y - row.height / 2
            if top < cursor + 3 { top = cursor + 3 }
            if let band {
                top = min(max(band.lowerBound, top), band.upperBound - row.height)
            }
            cursor = top + row.height
            place(row, top: top, into: &leaders)
        }
    }

    private func place(_ row: (item: Item, chip: UILabel, width: CGFloat, height: CGFloat), top: CGFloat, into leaders: inout [(CGPoint, CGPoint, UIColor)]) {
        let maxX = bounds.maxX - row.width - 8
        let x = min(max(8, row.item.point.x + 14), max(8, maxX))
        row.chip.frame = CGRect(x: x, y: top, width: row.width, height: row.height)
        row.chip.isHidden = false
        if row.chip.superview == nil { addSubview(row.chip) }
        chips[row.item.id] = row.chip
        leaders.append((row.item.point, CGPoint(x: row.chip.frame.minX, y: row.chip.frame.midY), row.item.color))
    }

    private func configureMore(_ button: UIButton) {
        button.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        button.setTitleColor(UIColor(red: 1, green: 0.83, blue: 0.47, alpha: 1), for: .normal)
        button.backgroundColor = UIColor(red: 0.04, green: 0.08, blue: 0.1, alpha: 0.86)
        button.layer.cornerRadius = 5
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor(red: 1, green: 0.7, blue: 0.33, alpha: 0.45).cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        button.isHidden = true
    }

    private func layoutMore(_ button: UIButton, text: String, visible: Bool, y: CGFloat) {
        button.setTitle(text, for: .normal)
        button.isHidden = !visible
        guard visible else { return }
        button.sizeToFit()
        let width = min(160, button.bounds.width + 6)
        button.frame = CGRect(x: bounds.maxX - width - 10, y: y, width: width, height: 22)
        bringSubviewToFront(button)
    }

    private func makeChip() -> UILabel {
        let chip = UILabel()
        chip.font = .systemFont(ofSize: 11, weight: .semibold)
        chip.textAlignment = .left
        chip.backgroundColor = UIColor(red: 0.04, green: 0.08, blue: 0.1, alpha: 0.78)
        chip.layer.cornerRadius = 5
        chip.layer.masksToBounds = true
        chip.layer.borderWidth = 0.5
        chip.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        return chip
    }
}
