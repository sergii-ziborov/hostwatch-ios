import XCTest
@testable import Hostwatch

final class CacheMetricsTests: XCTestCase {
    func testNativeCacheCountersAndUnavailableEvidence() throws {
        let raw = """
        {"status":"ok","collectedAt":"2026-09-29T10:00:00Z","engine":"valkey","version":"9.1.2","uptimeSeconds":600,"usedMemoryBytes":2048,"maxMemoryBytes":100663296,"connectedClients":3,"blockedClients":0,"operationsPerSecond":24,"totalCommands":300,"keys":18,"hits":75,"misses":25,"hitRatioPercent":75,"averageCommandMicros":9.5,"evictedKeys":0,"expiredKeys":12,"rejectedConnections":0,"inputBytesPerSecond":1024,"outputBytesPerSecond":4096}
        """
        let metrics = try JSONDecoder().decode(CacheMetrics.self, from: Data(raw.utf8))
        XCTAssertEqual(metrics.engine, "valkey")
        XCTAssertEqual(metrics.operationsPerSecond, 24)
        XCTAssertEqual(metrics.hitRatioPercent, 75)
        XCTAssertEqual(metrics.averageCommandMicros, 9.5)
        let unavailable = raw.replacingOccurrences(of: "\"status\":\"ok\"", with: "\"status\":\"unavailable\"")
            .replacingOccurrences(of: ",\"hitRatioPercent\":75", with: "")
            .replacingOccurrences(of: ",\"averageCommandMicros\":9.5", with: "")
        let absent = try JSONDecoder().decode(CacheMetrics.self, from: Data(unavailable.utf8))
        XCTAssertEqual(absent.status, "unavailable")
        XCTAssertNil(absent.hitRatioPercent)
        XCTAssertNil(absent.averageCommandMicros)
    }
}

final class PodmanCleanupTests: XCTestCase {
    func testRuntimeIdentityAndLegacyCleanupPayloads() throws {
        let legacy = #"{"kind":"docker-build-cache","name":"Docker","path":"docker:build-cache","bytes":0,"items":0,"available":true,"description":"cache","consequence":"rebuild"}"#
        let old = try JSONDecoder().decode(CleanupTarget.self, from: Data(legacy.utf8))
        XCTAssertNil(old.runtimeId)
        let native = legacy.replacingOccurrences(of: "docker-build-cache", with: "podman-build-cache")
            .replacingOccurrences(of: "\"name\":", with: "\"runtimeId\":\"podman-team\",\"name\":")
        let target = try JSONDecoder().decode(CleanupTarget.self, from: Data(native.utf8))
        XCTAssertEqual(target.runtimeId, "podman-team")
    }

    func testPodmanCleanupPreservesRuntimeQueryIdentity() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CleanupTestProtocol.self]
        let client = APIClient(baseURL: URL(string: "https://cleanup-tests.example.invalid")!, configuration: configuration)
        let result = try await client.cleanCache("podman-build-cache", runtimeID: "podman-team & staging")
        XCTAssertEqual(result.results.first?.runtimeId, "podman-team & staging")
    }

    func testUnknownCleanupActionIsRejectedBeforeNetworkRequest() async {
        let client = APIClient(baseURL: URL(string: "https://cleanup-tests.example.invalid")!)
        do {
            _ = try await client.cleanCache("system-prune")
            XCTFail("Broad cleanup must remain rejected")
        } catch APIError.invalidResponse {} catch { XCTFail("Unexpected error: \(error)") }
    }
}

private final class CleanupTestProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "cleanup-tests.example.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/v1/cleanup/podman-build-cache")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "runtimeId" })?.value, "podman-team & staging")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"results":[{"kind":"podman-build-cache","runtimeId":"podman-team & staging","reclaimedBytes":100,"deletedItems":1,"completedAt":"2026-09-29T10:00:00Z"}],"errors":{},"completedAt":"2026-09-29T10:00:00Z"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
