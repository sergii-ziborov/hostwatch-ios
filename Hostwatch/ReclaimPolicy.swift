import SwiftUI

enum ReclaimPolicy {
    static func advise(_ entries: [StorageEntry]) -> [ReclaimAdvice] {
        entries.map { entry in
            let (className, reason) = classify(entry)
            return ReclaimAdvice(className: className, path: entry.path, kind: entry.category, bytes: entry.bytes, reason: reason)
        }
    }

    static func classify(_ entry: StorageEntry) -> (String, String) {
        let path = entry.path.lowercased()
        let haystack = "\(path) \(entry.category) \(entry.kind)".lowercased()
        if contains(haystack, "overlay2", "containerd", "docker image") {
            return ("protected", "Shared container layers. Unused image prune can break a running or next deploy.")
        }
        if contains(haystack, "postgres", "database", "backup", "/srv/data/backups") {
            return ("protected", "Application data or backups. Never auto-deleted.")
        }
        if contains(haystack, "/usr", "/boot", "/opt", "operating system") {
            return ("protected", "Operating system or installed services.")
        }
        if pathAt(path, "/var/cache/apt/archives") || pathAt(path, "/var/cache/man") || path == "docker:build-cache" {
            return ("safe", "Allowlisted cache. Preview and clean from Cleanup; downloads or rebuilds may take longer.")
        }
        if contains(haystack, "/tmp", "/var/tmp") {
            return ("review", "Temporary files. Confirm nothing in-flight is writing here before removal.")
        }
        if contains(haystack, "/var/log", "container logs") {
            return ("review", "Logs explain crashes and should be rotated, not deleted wholesale.")
        }
        if let site = entry.siteId, !site.isEmpty, site != "__host__" {
            return ("review", "Attributed to a project. Inspect the path before treating it as reclaimable.")
        }
        return ("review", "Unclassified host space. Open the path and confirm it is not live data.")
    }

    static func color(for className: String) -> Color {
        switch className {
        case "safe": return HW.teal
        case "protected": return HW.red
        default: return HW.amber
        }
    }

    private static func contains(_ haystack: String, _ tokens: String...) -> Bool {
        tokens.contains { haystack.contains($0.lowercased()) }
    }

    private static func pathAt(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }
}
