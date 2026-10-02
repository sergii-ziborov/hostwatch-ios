import CoreLocation
import MapKit
import SceneKit
import XCTest
@testable import Hostwatch

final class HostwatchTests: XCTestCase {
    func testSiteWithoutContainersDecodesFromAgentResponse() throws {
        let response = #"{"id":"static","name":"Static site","domains":null,"sharedNginx":false,"containers":null,"cpuPercent":0,"memoryBytes":0,"memoryLimit":0,"requestsPerMinute":0,"bytesPerMinute":0,"errorRate":0,"p95Ms":0}"#
        let site = try JSONDecoder().decode(Site.self, from: Data(response.utf8))
        XCTAssertEqual(site.id, "static")
        XCTAssertTrue(site.domains.isEmpty)
        XCTAssertTrue(site.containers.isEmpty)
        XCTAssertEqual(site.normalMemoryLimit, 0)
        XCTAssertEqual(site.peakMemoryLimit, 0)
        XCTAssertEqual(site.memoryPressure, .unavailable)
    }

    func testSiteMemoryPolicyDecodesBothLimitsAndWarnsAtThresholds() throws {
        let response = #"{"id":"kablay-us","name":"Kablay US","domains":["kablay.us"],"sharedNginx":false,"containers":[],"cpuPercent":20,"memoryBytes":220200960,"memoryLimit":268435456,"normalMemoryBytes":268435456,"peakMemoryBytes":524288000,"memoryMode":"normal","requestsPerMinute":12,"bytesPerMinute":0,"errorRate":0,"p95Ms":80}"#
        var site = try JSONDecoder().decode(Site.self, from: Data(response.utf8))
        XCTAssertEqual(site.normalMemoryLimit, 268_435_456)
        XCTAssertEqual(site.peakMemoryLimit, 524_288_000)
        XCTAssertEqual(site.memoryPressure, .approachingNormal)
        site.memoryBytes = 300_000_000
        site.memoryMode = "overflow"
        XCTAssertEqual(site.memoryPressure, .overflow)
        XCTAssertEqual(site.memoryStatus, "Above normal limit")
        site.memoryBytes = 480_000_000
        XCTAssertEqual(site.memoryPressure, .nearPeak)
        site.memoryBytes = 100_000_000
        XCTAssertEqual(site.memoryStatus, "Peak active · cooling down")
    }

    func testMemoryLimitUpdatePreservesTrafficAndProcessCaps() throws {
        let response = #"{"requestsPerSecond":400,"cpuPercent":140,"memoryBytes":1207959552,"normalMemoryBytes":1207959552,"peakMemoryBytes":1476395008,"pids":512,"managed":true,"memoryMode":"normal"}"#
        let limits = try JSONDecoder().decode(SiteLimits.self, from: Data(response.utf8))
        let update = try SiteLimitUpdate(limits: limits, normalMiB: 1_152, peakMiB: 1_408)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(update)) as? [String: Any])
        XCTAssertEqual(payload["memoryBytes"] as? Int64, 1_207_959_552)
        XCTAssertEqual(payload["peakMemoryBytes"] as? Int64, 1_476_395_008)
        XCTAssertEqual(payload["requestsPerSecond"] as? Int, 400)
        XCTAssertEqual(payload["cpuPercent"] as? Double, 140)
        XCTAssertEqual(payload["pids"] as? Int64, 512)
        XCTAssertThrowsError(try SiteLimitUpdate(limits: limits, normalMiB: 1_152, peakMiB: 1_000))
    }

    func testTLSInventoryKeepsUnknownStatesAndNoPrivateKeyMaterial() throws {
        let response = #"{"siteId":"hostwatch","name":"Hostwatch","domains":["gethostwatch.com"],"management":"future_adapter","certificates":[{"lineage":"gethostwatch.com","fingerprint":"abcd","issuer":"Let's Encrypt","domains":["gethostwatch.com"],"notAfter":"2026-12-10T14:51:18Z","status":"future_status","renewalOwner":"certbot"}],"observations":[{"domain":"gethostwatch.com","boundary":"public","status":"unreachable","hostnameMatch":false,"trusted":false,"error":"TLS handshake unavailable"}],"scheduler":{"configured":true,"enabled":true},"warnings":[],"observedAt":"2026-09-30T00:00:00Z"}"#
        let snapshot = try JSONDecoder().decode(TLSSite.self, from: Data(response.utf8))
        XCTAssertEqual(snapshot.management, "future_adapter")
        XCTAssertEqual(snapshot.certificates[0].status, "future_status")
        XCTAssertEqual(snapshot.observations[0].status, "unreachable")
        XCTAssertNil(snapshot.observations[0].fingerprint)
        XCTAssertNil(snapshot.certificates[0].lastOperation)
        XCTAssertFalse(response.contains("privateKey"))
    }

    func testRequestThreatEvidenceAndOlderAgentCompatibility() throws {
        let sample = Fixtures.requests[0]
        let encoded = try JSONEncoder().encode(sample)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "dangerousBot")
        object.removeValue(forKey: "threatCategory")
        object.removeValue(forKey: "threatReason")
        let older = try JSONDecoder().decode(RequestSample.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(older.dangerousBot)
        object["dangerousBot"] = true
        object["threatCategory"] = "wordpress-probe"
        object["threatReason"] = "WordPress login probe"
        let threat = try JSONDecoder().decode(RequestSample.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(threat.dangerousBot, true)
        XCTAssertEqual(threat.threatCategory, "wordpress-probe")
        XCTAssertEqual(threat.threatReason, "WordPress login probe")
    }

    func testByteFormattingUsesBinaryUnits() {
        XCTAssertEqual(Format.bytes(1_073_741_824), "1.0 GB")
        XCTAssertEqual(Format.bytes(1024), "1.0 KB")
    }

    func testEveryMenuItemHasUniqueProductName() {
        XCTAssertEqual(Set(SidebarPage.allCases.map(\.title)).count, SidebarPage.allCases.count)
        XCTAssertFalse(SidebarPage.allCases.map(\.title).contains("Weavatrix"))
        XCTAssertFalse(SidebarPage.allCases.map(\.title).contains("Repo Lens"))
    }

    func testInternalServiceAddressCannotBeBlockedFromRequestInspector() {
        XCTAssertTrue(IPAddressSafety.isInternal("172.21.0.3"))
        XCTAssertTrue(IPAddressSafety.isInternal("10.0.0.8"))
        XCTAssertTrue(IPAddressSafety.isInternal("::1"))
        XCTAssertFalse(IPAddressSafety.isInternal("203.0.113.10"))
    }

    func testPairingQRIsBoundToTheConfiguredController() {
        let id = "ABCDEFGHIJKLMNOPQRSTUVWX"
        let value = QRPayload.url(server: "https://control.example.com", id: id)?.absoluteString
        XCTAssertEqual(value, "https://control.example.com/app/approve/\(id)")
        XCTAssertEqual(QRPayload.id(from: value ?? "", server: "https://control.example.com"), id)
        XCTAssertEqual(QRPayload.id(from: "hostwatch://control.example.com/app/approve/\(id)", server: "https://control.example.com"), id)
        XCTAssertNil(QRPayload.id(from: value ?? "", server: "https://different.example.com"))
        XCTAssertNil(QRPayload.id(from: "https://control.example.com/#approve=bad", server: "https://control.example.com"))
    }

    func testWebsiteDeviceSignInQRContainsOnlyExpectedOriginAndTicket() {
        let id = "ABCDEFGHIJKLMNOPQRSTUVWX"
        let secret = String(repeating: "a", count: 43)
        let value = "https://gethostwatch.com/#device-login=\(id).\(secret)"
        let universal = "https://gethostwatch.com/app/device-login/\(id)#secret=\(secret)"
        XCTAssertEqual(QRPayload.deviceTicket(from: universal)?.id, id)
        XCTAssertEqual(QRPayload.deviceTicket(from: universal.replacingOccurrences(of: "https://", with: "hostwatch://"))?.id, id)
        XCTAssertEqual(QRPayload.deviceTicket(from: universal)?.secret, secret)
        let ticket = QRPayload.deviceTicket(from: value)
        XCTAssertEqual(ticket?.server, "https://gethostwatch.com/")
        XCTAssertEqual(ticket?.id, id)
        XCTAssertEqual(ticket?.secret, secret)
        XCTAssertNil(QRPayload.deviceTicket(from: "http://evil.example/#device-login=\(id).\(secret)"))
        XCTAssertNil(QRPayload.deviceTicket(from: "https://gethostwatch.com/#approve=\(id)"))
        XCTAssertNil(QRPayload.deviceTicket(from: "https://gethostwatch.com/#device-login=bad.\(secret)"))
    }

    func testAuthenticatorQRHasExpectedIssuerAndSecret() {
        let setup = TOTPSetup(totpSecret: "ABCDEFGHIJKLMNOP", issuer: "HOSTWATCH", account: "owner@example.com")
        let parts = URLComponents(string: setup.uri)
        XCTAssertEqual(parts?.scheme, "otpauth")
        XCTAssertEqual(parts?.host, "totp")
        XCTAssertEqual(parts?.queryItems?.first(where: { $0.name == "secret" })?.value, "ABCDEFGHIJKLMNOP")
        XCTAssertEqual(parts?.queryItems?.first(where: { $0.name == "issuer" })?.value, "HOSTWATCH")
    }

    func testInternalRoutesStayOnTheTopologyContract() throws {
        let payload = Data("""
        {"windowHours":24,"sources":[],"countries":[],"bots":[],"internalRoutes":[{"caller":"applydjinn","destinationHost":"kablay.il","targetService":"kablay-il","requests":12,"bytes":4096}]}
        """.utf8)
        let sources = try JSONDecoder().decode(Sources.self, from: payload)
        XCTAssertEqual(sources.internalRoutes?.first?.targetService, "kablay-il")
        XCTAssertEqual(sources.internalRoutes?.first?.caller, "applydjinn")
    }

    func testNetworkSocketSnapshotDecodesPortEvidence() throws {
        let payload = Data("""
        {"observedAt":"2026-09-14T08:45:00Z","interface":"eth0","tcpConnections":2,"udpConnections":0,"localPorts":[{"protocol":"TCP","port":443,"connections":1,"listening":true}],"remotePorts":[{"protocol":"TCP","port":5432,"connections":1}],"available":true}
        """.utf8)
        let snapshot = try JSONDecoder().decode(NetworkPorts.self, from: payload)
        XCTAssertEqual(snapshot.localPorts.first?.port, 443)
        XCTAssertEqual(snapshot.remotePorts.first?.protocolName, "TCP")
        XCTAssertEqual(snapshot.tcpConnections, 2)
    }

    func testDataInventoryDecodesServicesAndObservedFiles() throws {
        let payload = Data("""
        {"services":[],"files":[{"path":"/srv/data/app/app.sqlite3","type":"SQLite database","siteId":"app","siteName":"App","container":"app-1","sizeBytes":1048576,"modifiedAt":"2026-09-14T08:45:00Z","backup":false}],"dockerHealthy":true,"scannedAt":"2026-09-14T08:46:00Z"}
        """.utf8)
        let inventory = try JSONDecoder().decode(DataServicesResponse.self, from: payload)
        XCTAssertEqual(inventory.services.count, 0)
        XCTAssertEqual(inventory.files.first?.siteName, "App")
        XCTAssertEqual(inventory.files.first?.sizeBytes, 1_048_576)
    }

    func testPodmanDataServicesDecodeRuntimeOwnership() throws {
        let payload = Data("""
        {"services":[{"type":"Redis / Valkey","role":"Cache","siteId":"app","container":{"id":"same","runtimeId":"podman-main","engine":"podman","name":"redis","project":"app","state":"running","status":"Up","image":"redis:7.4","imageId":"image","cpuPercent":0,"memoryBytes":0,"memoryLimit":100,"networkRxBytes":0,"networkTxBytes":0,"pids":1,"metricsStatus":"unavailable","networkMetricsStatus":"unsupported"}}],"files":[],"dockerHealthy":false,"runtimeHealthy":true,"scannedAt":"2026-09-29T10:00:00Z"}
        """.utf8)
        let inventory = try JSONDecoder().decode(DataServicesResponse.self, from: payload)
        XCTAssertEqual(inventory.runtimeHealthy, true)
        XCTAssertEqual(inventory.services.first?.id, "podman-main:same")
        XCTAssertEqual(inventory.services.first?.container.engine, "podman")
        XCTAssertEqual(inventory.services.first?.container.networkMetricsStatus, "unsupported")
    }

    func testChartTimeUsesTimestampsAndAcceptsFractionalSeconds() {
        guard let start = ChartTime.parse("2026-09-13T08:00:00Z"),
              let end = ChartTime.parse("2026-09-13T08:05:00.123Z") else {
            XCTFail("Expected ISO timestamps to parse")
            return
        }
        XCTAssertEqual(end.timeIntervalSince(start), 300.123, accuracy: 0.001)
    }

    func testTrafficModeShowsPacketsAndTowersModeShowsArchitecture() {
        XCTAssertTrue(TopologyMode.traffic.showsPackets)
        XCTAssertFalse(TopologyMode.traffic.showsArchitecture)
        XCTAssertFalse(TopologyMode.towers.showsPackets)
        XCTAssertTrue(TopologyMode.towers.showsArchitecture)
    }

    func testVisitorMapDropsInternalAndZeroCoordinates() {
        let visitor = Fixtures.requests.first { $0.origin == .external && $0.latitude != nil }!
        XCTAssertNotNil(GeoPlace.coordinate(for: visitor))
        XCTAssertNil(GeoPlace.coordinate(for: Fixtures.requests.first { $0.origin == .ourService }!))
        XCTAssertFalse(GeoPlace.isUsable(latitude: 0, longitude: 0))
        XCTAssertFalse(GeoPlace.isUsable(latitude: .nan, longitude: 34))
        XCTAssertNotNil(GeoPlace.centroid(code: "IL", country: "Israel"))
        XCTAssertGreaterThan(GeoPlace.pins(from: Fixtures.requests).count, 0)
    }

    func testVisitorMapRegionStaysValidForWorldwidePins() {
        let worldwide = [
            CLLocationCoordinate2D(latitude: -41.29, longitude: 174.78),
            CLLocationCoordinate2D(latitude: 38.91, longitude: -77.04),
            CLLocationCoordinate2D(latitude: 35.68, longitude: 139.69)
        ]
        let region = GeoPlace.regionCovering(worldwide)
        XCTAssertNotNil(region)
        XCTAssertLessThanOrEqual(region?.span.latitudeDelta ?? 999, 80)
        XCTAssertLessThanOrEqual(region?.span.longitudeDelta ?? 999, 140)
        let tall = GeoPlace.sanitized(region!, fitting: CGSize(width: 1, height: 260))
        XCTAssertLessThanOrEqual(tall.span.latitudeDelta, 80)
        XCTAssertLessThanOrEqual(tall.span.longitudeDelta, 140)
        XCTAssertTrue(CLLocationCoordinate2DIsValid(tall.center))
        let phone = GeoPlace.sanitized(region!, fitting: CGSize(width: 390, height: 260))
        XCTAssertLessThanOrEqual(phone.span.latitudeDelta, 80)
        XCTAssertLessThanOrEqual(phone.span.longitudeDelta, 140)
        let polar = GeoPlace.sanitized(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 89, longitude: 179), span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 60)), fitting: CGSize(width: 390, height: 260))
        XCTAssertLessThanOrEqual(polar.center.latitude + polar.span.latitudeDelta / 2, 90)
        XCTAssertLessThanOrEqual(polar.center.longitude + polar.span.longitudeDelta / 2, 180)
    }

    func testTrafficRoadsDistinguishPublicClientsFromOurServices() {
        XCTAssertEqual(TopologyRoadKind.feeder.origin, .external)
        XCTAssertEqual(TopologyRoadKind.call.origin, .ourService)
        XCTAssertEqual(TopologyRoadKind.io.origin, .ourData)
        let publicEdge = TopologyFlow.parse(roadName: "road:host:applydjinn:feeder")
        XCTAssertEqual(publicEdge?.from, "host")
        XCTAssertEqual(publicEdge?.to, "applydjinn")
        XCTAssertEqual(publicEdge?.origin, .external)
        let serviceCall = TopologyFlow.parse(roadName: "road:applydjinn:kablay-il:call")
        XCTAssertEqual(serviceCall?.from, "applydjinn")
        XCTAssertEqual(serviceCall?.to, "kablay-il")
        XCTAssertEqual(serviceCall?.origin, .ourService)
        let data = TopologyFlow.parse(roadName: "road:applydjinn:ext:pg-1:io")
        XCTAssertEqual(data?.from, "applydjinn")
        XCTAssertEqual(data?.to, "ext:pg-1")
        XCTAssertEqual(data?.origin, .ourData)
        XCTAssertEqual(TrafficOrigin(Fixtures.requests.first { $0.internalRequest == true }!), .ourService)
        XCTAssertEqual(TrafficOrigin(Fixtures.requests.first { $0.internalRequest != true }!), .external)
    }

    func testTowerLockFramesFromTheRightLikeElectron() {
        let pose = TopologyCamera.lock(base: SCNVector3(2, 0, -1), height: 4)
        let eye = TopologyCamera.eye(of: pose)
        XCTAssertGreaterThan(pose.target.x, 2)
        XCTAssertLessThan(pose.target.z, -1)
        XCTAssertGreaterThan(eye.x, pose.target.x)
        XCTAssertGreaterThan(eye.y, pose.target.y)
        XCTAssertGreaterThan(eye.z, pose.target.z)
        XCTAssertGreaterThanOrEqual(pose.pitch, TopologyCamera.minPitch)
        XCTAssertLessThanOrEqual(pose.pitch, TopologyCamera.maxPitch)
        XCTAssertGreaterThan(pose.distance, 7)
        XCTAssertLessThan(pose.distance, 10)
        XCTAssertEqual(pose.target.y, 2.08, accuracy: 0.01)
        let tall = TopologyCamera.lock(base: SCNVector3(2, 0, -1), height: 7)
        XCTAssertEqual(tall.target.y, 3.64, accuracy: 0.01)
        XCTAssertGreaterThan(tall.distance, pose.distance)
        let wide = TopologyCamera.lock(base: SCNVector3(2, 0, -1), height: 4, aspect: 1.4)
        XCTAssertGreaterThan(wide.target.x, pose.target.x)
        XCTAssertLessThan(wide.target.z, pose.target.z)
    }

    func testOrbitCameraStaysUprightAcrossFullYaw() {
        var pose = TopologyCamera.Pose(target: SCNVector3(0, 1.2, 0), yaw: 0, pitch: 0.62, distance: 18)
        var yaw: Float = -.pi
        while yaw <= .pi {
            pose.yaw = yaw
            XCTAssertGreaterThan(TopologyCamera.basisUpY(of: pose), 0.35, "yaw \(yaw)")
            yaw += 0.35
        }
        pose.pitch = TopologyCamera.maxPitch
        XCTAssertGreaterThan(TopologyCamera.basisUpY(of: pose), 0.2)
    }

    func testProjectFilterExplodesEppyIntoFrontendBackendAndDatabase() {
        let site = Fixtures.sites.first { $0.id == "eppy" }!
        let project = Fixtures.projects.first { $0.id == "eppy" }
        let components = TopologyLayer.explode(site, project: project, services: Fixtures.dataServices)
        let roles = Set(components.compactMap { TopologyServiceRole.of(siteID: $0.id) })
        XCTAssertEqual(roles, [.frontend, .backend, .database])
        XCTAssertEqual(components.map(\.name), ["Frontend", "Backend", "Database"])
        let roads = TopologyLayer.componentRoads(parent: site, components: components, routes: Fixtures.sources.internalRoutes ?? [])
        XCTAssertTrue(roads.contains { $0.from.hasSuffix("/frontend") && $0.to.hasSuffix("/backend") && $0.kind == .call })
        XCTAssertTrue(roads.contains { $0.from.hasSuffix("/backend") && $0.to.hasSuffix("/database") && $0.kind == .io })
        XCTAssertTrue(roads.contains { $0.from == "host" && $0.to.hasSuffix("/frontend") })
        let backend = components.first { TopologyServiceRole.of(siteID: $0.id) == .backend }!
        let layers = TopologyLayer.layers(for: backend, project: project)
        XCTAssertTrue(layers.contains { $0.kind == .module && $0.title == "api" })
        XCTAssertFalse(layers.contains { $0.kind == .module && $0.title == "web" })
    }

    func testProjectFilterSynthesizesFrontendWhenOnlyBackendExists() {
        let site = Fixtures.sites.first { $0.id == "kablay-us" }!
        let components = TopologyLayer.explode(site, project: Fixtures.projects.first { $0.id == site.id }, services: [])
        XCTAssertTrue(components.contains { TopologyServiceRole.of(siteID: $0.id) == .frontend })
        XCTAssertTrue(components.contains { TopologyServiceRole.of(siteID: $0.id) == .backend })
    }

    func testWeavatrixModulesBecomeInnerTowerLayers() {
        let site = Fixtures.sites[0]
        let project = Fixtures.projects.first { $0.id == site.id }
        let layers = TopologyLayer.layers(for: site, project: project)
        XCTAssertTrue(layers.contains { $0.kind == .runtime })
        XCTAssertTrue(layers.contains { $0.kind == .module && $0.title == "web" })
        XCTAssertTrue(layers.contains { $0.kind == .community })
        XCTAssertGreaterThan(layers.filter { $0.kind == .runtime }.count, 1)
        let hops = TopologyLayer.hops(for: site, project: project, routes: Fixtures.sources.internalRoutes ?? [])
        XCTAssertTrue(hops.contains { !$0.weavatrix })
        XCTAssertTrue(hops.contains { $0.weavatrix && $0.title.contains("Weavatrix") })
    }

    func testTowerLabelsStayPinnedToTheirSections() {
        let pinned = TopologyLayout.arrangeLabels(
            preferredTops: [100, 150, 200], heights: [20, 20, 20], minY: 80, maxY: 240, gap: 3
        )
        XCTAssertEqual(pinned.tops, [100, 150, 200])
        XCTAssertEqual(pinned.moreAbove, 0)
        XCTAssertEqual(pinned.moreBelow, 0)
        let collided = TopologyLayout.arrangeLabels(
            preferredTops: [100, 104, 108], heights: [20, 20, 20], minY: 80, maxY: 240, gap: 3
        )
        XCTAssertGreaterThanOrEqual(collided.tops[1], collided.tops[0] + 23)
        XCTAssertGreaterThanOrEqual(collided.tops[2], collided.tops[1] + 23)
        let overflow = TopologyLayout.arrangeLabels(
            preferredTops: (0..<14).map { CGFloat($0) * 12 },
            heights: Array(repeating: 20, count: 14),
            minY: 0, maxY: 100, gap: 3, start: 0
        )
        XCTAssertGreaterThan(overflow.moreBelow, 0)
        XCTAssertLessThan(overflow.count, 14)
        XCTAssertEqual(overflow.tops.count, overflow.count)
        let end = TopologyLayout.arrangeLabels(
            preferredTops: (0..<14).map { CGFloat($0) * 12 },
            heights: Array(repeating: 20, count: 14),
            minY: 0, maxY: 100, gap: 3, start: 13
        )
        XCTAssertGreaterThan(end.moreAbove, 0)
        XCTAssertEqual(end.moreBelow, 0)
        XCTAssertEqual(end.start + end.count, 14)
        for index in 1..<overflow.tops.count {
            XCTAssertGreaterThanOrEqual(overflow.tops[index], overflow.tops[index - 1] + 18)
        }
    }

    func testFocusedLabelBandKeepsTheSameHeightForShortAndTallTowers() {
        let shortTower = TopologyLayout.focusedLabelBand(centerY: 490, viewportHeight: 600)!
        let tallTower = TopologyLayout.focusedLabelBand(centerY: 220, viewportHeight: 600)!
        XCTAssertEqual(shortTower.upperBound - shortTower.lowerBound,
                       tallTower.upperBound - tallTower.lowerBound, accuracy: 0.01)
        XCTAssertEqual(shortTower.upperBound - shortTower.lowerBound, 316.8, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(shortTower.lowerBound, 12)
        XCTAssertLessThanOrEqual(shortTower.upperBound, 588)
        XCTAssertGreaterThanOrEqual(tallTower.lowerBound, 12)
        XCTAssertLessThanOrEqual(tallTower.upperBound, 588)
    }

    func testSceneLayerSelectionIdentifiesEachLayer() {
        let runtime = TopologySelection.sceneLayer("site:kablay-us:0:runtime")
        let graph = TopologySelection.sceneLayer("site:kablay-us:11:graph")
        XCTAssertEqual(runtime?.siteID, "kablay-us")
        XCTAssertEqual(runtime?.layer, 0)
        XCTAssertEqual(graph?.layer, 11)
        XCTAssertNotEqual(runtime?.id, graph?.id)
        XCTAssertNil(TopologySelection.sceneLayer("tower:kablay-us"))
    }

    func testTopologyDetailsResolveTheExactProject() {
        let projects = Fixtures.projects
        XCTAssertEqual(TopologyLayer.project(for: "kablay-us", in: projects)?.id, "kablay-us")
        XCTAssertEqual(TopologyLayer.project(for: "kablay-us/frontend-1", in: projects)?.id, "kablay-us")
        XCTAssertNil(TopologyLayer.project(for: "kablay-unknown", in: projects))
    }

    func testManhattanRoadsStayOrthogonalOnTheCyberboard() {
        let a = TopologyPoint(x: -4.4, z: -1)
        let b = TopologyPoint(x: 4.4, z: 3.4)
        let path = TopologyLayout.manhattan(from: a, to: b, siteXs: [-4.4, 0, 4.4], siteZs: [-1, 3.4])
        XCTAssertGreaterThanOrEqual(path.count, 2)
        XCTAssertTrue(TopologyLayout.isOrthogonal(path))
        XCTAssertEqual(path.first, a)
        XCTAssertEqual(path.last, b)
    }

    func testPublicEdgeNeverOccupiesASiteTowerPlate() {
        for count in 1...15 {
            let hub = TopologyLayout.hubPosition(siteCount: count)
            for index in 0..<count {
                let site = TopologyLayout.gridPosition(index: index, count: count)
                let distance = hypot(hub.x - site.x, hub.z - site.z)
                XCTAssertGreaterThanOrEqual(distance, TopologyLayout.spacing - 0.001,
                                            "Public edge overlaps site \(index) in a \(count)-site scene")
            }
        }
    }

    func testHybridFleetContractDecodesAgentJSON() throws {
        let payload = Data("""
        {"id":"home-main","kind":"home-compute","publicIp":"203.0.113.44","previousIp":"203.0.113.10","fresh":true,"ipChanged":true,"diskFreeBytes":4096,"runningJobs":1,"cpuPercent":12.5,"lastSeen":"2026-09-19T00:00:00Z"}
        """.utf8)
        let peer = try JSONDecoder().decode(HybridPeer.self, from: payload)
        XCTAssertEqual(peer.id, "home-main")
        XCTAssertTrue(peer.ipChanged)
        XCTAssertEqual(peer.publicIp, "203.0.113.44")
        XCTAssertEqual(SidebarPage.fleet.title, "Fleet")
    }

    func testUnmappedNginxHostIsNotAnOpenableDestination() {
        XCTAssertFalse(RequestEvidence.usableHost("_"))
        XCTAssertFalse(RequestEvidence.usableHost("localhost"))
        XCTAssertTrue(RequestEvidence.usableHost("api.kablay.us"))
        XCTAssertTrue(RequestEvidence.diagnosis(status: 400, host: "_", method: "UNKNOWN", path: "/", upstream: nil).contains("No application or destination page"))
        XCTAssertEqual(RequestEvidence.destinationURL(for: Fixtures.requests.first { $0.method == "GET" }!)?.host, Fixtures.requests.first { $0.method == "GET" }?.host)
        XCTAssertNil(RequestEvidence.destinationURL(for: Fixtures.requests.first { $0.method == "POST" }!))
        XCTAssertGreaterThan(DestinationGroup.groups(from: Fixtures.requests).count, 24)
        XCTAssertEqual(SidebarPage.data.title, "Database")
    }

    func testMCPSnapshotDecodesAgentJSON() throws {
        let payload = Data("""
        {"governance":{"enabled":true,"allowObserve":true,"allowMutate":false,"deniedTools":["deploy"],"maxMutationsPerHour":20,"staleAfterSeconds":900,"updatedAt":"2026-09-20T00:00:00Z"},"clients":[{"id":"studio","hostname":"studio.local","username":"sergii","app":"cursor","remoteIp":"203.0.113.44","firstSeen":"2026-09-20T00:00:00Z","lastSeen":"2026-09-20T00:00:00Z","lastTool":"overview","observeCalls":1,"mutateCalls":0,"stale":false}],"history":[],"knownTools":[{"name":"overview","kind":"observe","title":"Overview"}]}
        """.utf8)
        let snap = try JSONDecoder().decode(MCPSnapshot.self, from: payload)
        XCTAssertEqual(snap.governance.deniedTools, ["deploy"])
        XCTAssertFalse(snap.governance.allowMutate)
        XCTAssertEqual(snap.clients[0].hostname, "studio.local")
        XCTAssertEqual(snap.knownTools[0].name, "overview")
        XCTAssertEqual(SidebarPage.mcp.title, "MCP")
        XCTAssertEqual(SidebarPage.mcp.icon, "antenna.radiowaves.left.and.right")
        XCTAssertEqual(SidebarPage.errors.title, "Errors")
    }

    func testErrorContextAndGroupsDecodeAgentJSON() throws {
        let payload = Data("""
        {"request":{"id":"req-1","time":"2026-09-20T12:00:00Z","site":"applydjinn","host":"applydjinn.com","method":"GET","path":"/api","status":502,"bytes":120,"durationMs":40,"clientIp":"203.0.113.10","country":"Germany","countryCode":"DE","userAgent":"Safari","source":"Direct"},"projectId":"applydjinn","projectName":"ApplyDjinn","previous":[],"logs":[{"time":"2026-09-20T12:00:00Z","stream":"stderr","text":"panic: boom","crash":true}],"logSource":"applydjinn/app","crashHint":"panic: boom"}
        """.utf8)
        let context = try JSONDecoder().decode(ErrorContext.self, from: payload)
        XCTAssertEqual(context.projectName, "ApplyDjinn")
        XCTAssertEqual(context.logs.first?.crash, true)
        XCTAssertEqual(context.crashHint, "panic: boom")
        let groups = try JSONDecoder().decode([ErrorProjectGroup].self, from: Data("""
        [{"projectId":"applydjinn","projectName":"ApplyDjinn","count":2,"lastTime":"2026-09-20T12:00:00Z","statuses":{"502":2},"requests":[]}]
        """.utf8))
        XCTAssertEqual(groups.first?.projectId, "applydjinn")
        XCTAssertEqual(groups.first?.count, 2)
        let mixed = try JSONDecoder().decode([ErrorProjectGroup].self, from: Data("""
        [{"projectId":"applydjin","projectName":"ApplyDjinn","count":7417,"blockedRequests":7356,"cancelledRequests":2,"lastTime":null,"statuses":{"444":7356,"404":59,"499":2},"requests":[]}]
        """.utf8))
        XCTAssertEqual(mixed.first?.httpErrorCount, 59)
        XCTAssertEqual(mixed.first?.edgeBlockCount, 7356)
    }

    func testMarkdownNotesImportAndExportAdvisories() {
        let notes = MarkdownNotes.parse(kind: "vulnerability", project: "applydjinn", markdown: "- CVE-2026-1142 (critical) example-runtime\n- not an advisory")
        XCTAssertEqual(notes.map(\.title), ["CVE-2026-1142"])
        XCTAssertEqual(notes.first?.severity, "critical")
        let errors = MarkdownNotes.parse(kind: "error", project: "applydjinn", markdown: "- 502 GET /api applydjinn.com")
        XCTAssertEqual(errors.first?.title, "502 GET /api")
        let exported = MarkdownNotes.export(kind: "vulnerability", projects: Fixtures.projects, groups: [])
        XCTAssertTrue(exported.contains("CVE-2026-1142"))
        XCTAssertTrue(exported.contains("# Hostwatch vulnerabilities"))
    }

    func testReclaimAdvisorProtectsDatabasesAndAllowsCaches() {
        let advice = ReclaimPolicy.advise([
            .init(path: "/var/lib/postgresql", kind: "directory", category: "Databases", siteId: nil, siteName: "Host", bytes: 100, direct: false),
            .init(path: "/var/cache/apt/archives", kind: "directory", category: "Caches", siteId: nil, siteName: "Host", bytes: 20, direct: false),
            .init(path: "/var/lib/containerd", kind: "Docker images, snapshots, writable layers and build cache", category: "Container runtime", siteId: nil, siteName: "Host", bytes: 200, direct: false),
            .init(path: "/var/lib/containers/storage", kind: "Podman image layers", category: "Container runtime", siteId: nil, siteName: "Host", bytes: 80, direct: false),
            .init(path: "/srv/apps/applydjinn/uploads", kind: "directory", category: "Images & media", siteId: "applydjinn", siteName: "ApplyDjinn", bytes: 50, direct: false)
        ])
        XCTAssertEqual(advice.first { $0.path.hasSuffix("postgresql") }?.className, "protected")
        XCTAssertEqual(advice.first { $0.path.contains("apt") }?.className, "safe")
        XCTAssertEqual(advice.first { $0.path.contains("containerd") }?.className, "protected")
        XCTAssertEqual(advice.first { $0.path.contains("containers/storage") }?.className, "protected")
        XCTAssertEqual(advice.first { $0.path.contains("uploads") }?.className, "review")
    }

    func testSessionCookieSnapshotCanBeRestoredAfterAppDeath() throws {
        let stored = StoredCookie(
            name: "hostwatch",
            value: "session-token",
            domain: "gethostwatch.com",
            path: "/",
            expires: nil,
            secure: true,
            httpOnly: true,
            sameSite: "lax"
        )
        let encoded = try JSONEncoder().encode(StoredSession(
            baseURL: "https://gethostwatch.com",
            csrf: "csrf-token",
            cookies: [stored],
            snapshot: SessionState(authenticated: true, csrf: "csrf-token", user: .init(id: "u", email: "a@b.c", name: "A", totpEnabled: true), organization: nil, role: "owner"),
            savedAt: Date()
        ))
        let decoded = try JSONDecoder().decode(StoredSession.self, from: encoded)
        XCTAssertEqual(decoded.csrf, "csrf-token")
        XCTAssertTrue(decoded.snapshot.authenticated)
        XCTAssertEqual(decoded.cookies.first?.value, "session-token")

        let storage = HTTPCookieStorage.shared
        let url = URL(string: "https://gethostwatch.com")!
        for cookie in storage.cookies(for: url) ?? [] { storage.deleteCookie(cookie) }
        StoredCookie.apply(decoded.cookies, to: storage)
        let restored = storage.cookies(for: url)?.first { $0.name == "hostwatch" }
        XCTAssertEqual(restored?.value, "session-token")
        XCTAssertNotNil(restored?.expiresDate, "Session cookies must gain an expiry so iOS keeps them after the app is killed.")
    }
}
