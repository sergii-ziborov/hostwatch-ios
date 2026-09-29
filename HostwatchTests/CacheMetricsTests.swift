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
