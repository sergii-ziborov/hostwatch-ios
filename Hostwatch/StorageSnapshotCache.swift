import CryptoKit
import Foundation

struct StorageSnapshotCache {
    private let directory: URL
    private let prefix = "hostwatch-storage-"

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    func load(baseURL: String, organizationID: String, userID: String, nodeID: String) -> StorageResponse? {
        let url = fileURL(baseURL: baseURL, organizationID: organizationID, userID: userID, nodeID: nodeID)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(StorageResponse.self, from: data),
              snapshot.mode == "summary",
              let scannedAt = ChartTime.parse(snapshot.scannedAt),
              scannedAt <= Date().addingTimeInterval(60),
              scannedAt >= Date().addingTimeInterval(-7 * 24 * 60 * 60) else { return nil }
        return snapshot
    }

    func save(_ snapshot: StorageResponse, baseURL: String, organizationID: String, userID: String, nodeID: String) {
        guard snapshot.mode == "summary", let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(baseURL: baseURL, organizationID: organizationID, userID: userID, nodeID: nodeID)
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func clearAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix(prefix) && file.pathExtension == "json" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func fileURL(baseURL: String, organizationID: String, userID: String, nodeID: String) -> URL {
        let scope = [baseURL, organizationID, userID, nodeID].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(prefix)\(digest).json")
    }
}
