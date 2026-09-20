import SceneKit
import XCTest
@testable import Hostwatch

final class HostwatchTests: XCTestCase {
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
        XCTAssertEqual(value, "https://control.example.com/#approve=\(id)")
        XCTAssertEqual(QRPayload.id(from: value ?? "", server: "https://control.example.com"), id)
        XCTAssertNil(QRPayload.id(from: value ?? "", server: "https://different.example.com"))
        XCTAssertNil(QRPayload.id(from: "https://control.example.com/#approve=bad", server: "https://control.example.com"))
    }

    func testWebsiteDeviceSignInQRContainsOnlyExpectedOriginAndTicket() {
        let id = "ABCDEFGHIJKLMNOPQRSTUVWX"
        let secret = String(repeating: "a", count: 43)
        let value = "https://gethostwatch.com/#device-login=\(id).\(secret)"
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

    func testTowerLockFramesFromTheRightLikeElectron() {
        let pose = TopologyCamera.lock(base: SCNVector3(2, 0, -1), height: 4)
        let eye = TopologyCamera.eye(of: pose)
        XCTAssertEqual(pose.target.x, 2, accuracy: 0.15)
        XCTAssertEqual(pose.target.z, -1, accuracy: 0.15)
        XCTAssertGreaterThan(eye.x, pose.target.x)
        XCTAssertGreaterThan(eye.y, pose.target.y)
        XCTAssertGreaterThan(eye.z, pose.target.z)
        XCTAssertGreaterThanOrEqual(pose.pitch, TopologyCamera.minPitch)
        XCTAssertLessThanOrEqual(pose.pitch, TopologyCamera.maxPitch)
        XCTAssertGreaterThan(pose.distance, 10)
        XCTAssertLessThan(pose.distance, 22)
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

    func testTowerLabelsPackTightlyInsideTheTowerBand() {
        let tops = TopologyLayout.packLabels(heights: [20, 20, 20], minY: 100, maxY: 200, gap: 2)
        XCTAssertEqual(tops, [100, 122, 144])
        XCTAssertLessThanOrEqual((tops.last ?? 0) + 20, 200)
        let squeezed = TopologyLayout.packLabels(heights: Array(repeating: 20, count: 10), minY: 0, maxY: 100, gap: 2)
        XCTAssertEqual(squeezed.first ?? -1, 0, accuracy: 0.5)
        XCTAssertLessThanOrEqual((squeezed.last ?? 0) + 20, 100.5)
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
