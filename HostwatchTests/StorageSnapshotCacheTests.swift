import Foundation
import XCTest
@testable import Hostwatch

final class StorageSnapshotCacheTests: XCTestCase {
    func testCompletedScanSurvivesReopenWithoutCrossingNodeOrAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = StorageSnapshotCache(directory: directory)
        let snapshot = Fixtures.storage

        cache.save(snapshot, baseURL: "https://gethostwatch.com", organizationID: "org-a", userID: "user-a", nodeID: "primary")

        XCTAssertEqual(cache.load(baseURL: "https://gethostwatch.com", organizationID: "org-a", userID: "user-a", nodeID: "primary")?.scannedAt, snapshot.scannedAt)
        XCTAssertNil(cache.load(baseURL: "https://gethostwatch.com", organizationID: "org-a", userID: "user-a", nodeID: "mac"))
        XCTAssertNil(cache.load(baseURL: "https://gethostwatch.com", organizationID: "org-a", userID: "user-b", nodeID: "primary"))

        cache.clearAll()
        XCTAssertNil(cache.load(baseURL: "https://gethostwatch.com", organizationID: "org-a", userID: "user-a", nodeID: "primary"))
    }

    func testWeekOldScanIsNotRestored() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = StorageSnapshotCache(directory: directory)
        let encoded = try JSONEncoder().encode(Fixtures.storage)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["scannedAt"] = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-8 * 24 * 60 * 60))
        let old = try JSONDecoder().decode(StorageResponse.self, from: JSONSerialization.data(withJSONObject: object))

        cache.save(old, baseURL: "https://gethostwatch.com", organizationID: "org-a", userID: "user-a", nodeID: "primary")

        XCTAssertNil(cache.load(baseURL: "https://gethostwatch.com", organizationID: "org-a", userID: "user-a", nodeID: "primary"))
    }
}
