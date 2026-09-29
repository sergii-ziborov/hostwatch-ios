import SwiftUI

struct CacheMetrics: Codable {
    let status: String
    let error: String?
    let collectedAt: String
    let engine: String?
    let version: String?
    let role: String?
    let uptimeSeconds: Int
    let usedMemoryBytes: Double
    let maxMemoryBytes: Double
    let memoryPolicy: String?
    let connectedClients: Int
    let blockedClients: Int
    let operationsPerSecond: Int
    let totalCommands: Int
    let keys: Int
    let hits: Int
    let misses: Int
    let hitRatioPercent: Double?
    let averageCommandMicros: Double?
    let evictedKeys: Int
    let expiredKeys: Int
    let rejectedConnections: Int
    let inputBytesPerSecond: Double
    let outputBytesPerSecond: Double
}

struct CacheMetricsSection: View {
    let metrics: CacheMetrics
    var body: some View {
        if metrics.status == "ok" {
            Section("Native cache metrics") {
                HWLabeled("Engine", value: "\(metrics.engine == "valkey" ? "Valkey" : "Redis") \(metrics.version ?? "")")
                HWLabeled("Operations / second", value: metrics.operationsPerSecond.formatted())
                HWLabeled("Cache memory", value: Format.bytes(metrics.usedMemoryBytes))
                HWLabeled("Cache memory limit", value: metrics.maxMemoryBytes > 0 ? Format.bytes(metrics.maxMemoryBytes) : "No limit")
                HWLabeled("Memory policy", value: metrics.memoryPolicy ?? "Unavailable")
                HWLabeled("Clients", value: "\(metrics.connectedClients) · \(metrics.blockedClients) blocked")
                HWLabeled("Keys", value: metrics.keys.formatted())
                HWLabeled("Hit ratio since start", value: metrics.hitRatioPercent.map { Format.percent($0) } ?? "Not measured")
                HWLabeled("Hits / misses", value: "\(metrics.hits.formatted()) / \(metrics.misses.formatted())")
                HWLabeled("Evicted / expired", value: "\(metrics.evictedKeys.formatted()) / \(metrics.expiredKeys.formatted())")
                HWLabeled("Average command CPU", value: metrics.averageCommandMicros.map { String(format: "%.2f µs", $0) } ?? "Not measured")
                HWLabeled("Network received / second", value: Format.bytes(metrics.inputBytesPerSecond))
                HWLabeled("Network sent / second", value: Format.bytes(metrics.outputBytesPerSecond))
                HWLabeled("Rejected connections", value: metrics.rejectedConnections.formatted())
                HWLabeled("Uptime", value: "\(metrics.uptimeSeconds.formatted()) seconds")
                HWLabeled("Collected", value: metrics.collectedAt)
                Text("Native INFO counters. Average command CPU is measured since start and excludes network latency.").font(.footnote).foregroundStyle(HW.secondary)
            }
        } else {
            Section("Cache metrics unavailable") {
                Text(metrics.error ?? "The local INFO probe could not read this service.").font(.footnote).foregroundStyle(HW.secondary)
            }
        }
    }
}
