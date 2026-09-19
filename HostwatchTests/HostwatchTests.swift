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
    }
}
