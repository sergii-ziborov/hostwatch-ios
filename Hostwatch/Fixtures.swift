import Foundation

enum Fixtures {
    static let overview = Overview(
        timestamp: ISO8601DateFormatter().string(from: .now), hostname: "apps-prod-nbg1-2", uptimeSeconds: 270_000,
        cpuPercent: 18.7, load1: 0.7, load5: 0.6, load15: 0.6,
        memory: .init(total: 4_294_967_296, used: 2_897_641_472, available: 1_397_325_824, swapTotal: 0, swapUsed: 0),
        disk: .init(total: 86_228_590_592, used: 61_203_865_600, free: 25_024_724_992),
        network: .init(rxBytes: 4_300_000_000, txBytes: 1_900_000_000, rxBytesPerSecond: 98_120, txBytesPerSecond: 43_882, rxPacketsPerSecond: 84, txPacketsPerSecond: 47),
        budget: .init(period: "2026-09", usedBytes: 1_610_612_736, includedBytes: 21_990_232_555_520, warningBytes: 32_985_348_833_280, cutoffBytes: 41_782_136_619_008, locked: false, egressMbps: 100, emergencyMbps: 1, monthlyMaxAtCapBytes: 35_184_372_088_832),
        nginxLogHealthy: true, dockerHealthy: true
    )

    static let sites: [Site] = [
        .init(id: "applydjinn", name: "ApplyDjinn", domains: ["applydjinn.com"], sharedNginx: true, containers: [], cpuPercent: 8.2, memoryBytes: 943_718_400, memoryLimit: 1_610_612_736, requestsPerMinute: 38.4, bytesPerMinute: 2_408_448, errorRate: 1.8, p95Ms: 316),
        .init(id: "kablay-il", name: "Kablay IL", domains: ["kablay.co.il"], sharedNginx: true, containers: [], cpuPercent: 5.4, memoryBytes: 681_574_400, memoryLimit: 1_181_116_006, requestsPerMinute: 24.2, bytesPerMinute: 1_138_688, errorRate: 3.2, p95Ms: 422),
        .init(id: "kablay-us", name: "Kablay US", domains: ["kablay.us"], sharedNginx: true, containers: [], cpuPercent: 2.1, memoryBytes: 524_288_000, memoryLimit: 1_181_116_006, requestsPerMinute: 13.8, bytesPerMinute: 614_400, errorRate: 0.7, p95Ms: 184),
        .init(id: "eppy", name: "Eppy", domains: ["eppy.co.il"], sharedNginx: true, containers: [], cpuPercent: 1.2, memoryBytes: 314_572_800, memoryLimit: 1_073_741_824, requestsPerMinute: 4.1, bytesPerMinute: 178_176, errorRate: 0.0, p95Ms: 88)
    ]

    static let traffic: [TrafficPoint] = (0..<48).map { index in
        let wave = sin(Double(index) / 4) * 18 + 48
        let burst = index == 31 ? 95.0 : 0
        return .init(time: ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(index - 47) * 1_800)), requests: max(4, wave + burst + Double(index % 7) * 3), bytes: (wave + 12) * 19_000, errors4xx: Double(index % 8), errors5xx: index % 13 == 0 ? 3 : 0, averageMs: 120 + Double((index * 71) % 430))
    }

    static let history: [SystemPoint] = (0..<48).map { index in
        let time = ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(index - 47) * 1_800))
        return .init(time: time, cpuPercent: 10 + Double((index * 17) % 29), memoryBytes: 2_500_000_000 + Double(index * 5_000_000), swapBytes: 0,
                     diskBytes: 61_000_000_000, load1: 0.5 + Double(index % 8) / 10,
                     rxBytesPerSecond: 50_000 + Double((index * 31_919) % 120_000),
                     txBytesPerSecond: 20_000 + Double((index * 21_819) % 70_000),
                     rxPacketsPerSecond: 30 + Double(index % 21), txPacketsPerSecond: 20 + Double(index % 13), riskScore: Double(index % 18))
    }

    static let dataServices: [DataService] = [
        .init(type: "PostgreSQL", role: "Relational database", siteId: "applydjinn", siteName: "ApplyDjinn",
              container: .init(id: "postgres-fixture", name: "applydjinn-postgres-1", project: "applydjinn", state: "running", status: "Up 3 days", image: "postgres:16", imageId: "sha256:fixture", cpuPercent: 4.6, memoryBytes: 417_000_000, memoryLimit: 1_073_741_824, networkRxBytes: 42_000_000, networkTxBytes: 18_000_000, pids: 18)),
        .init(type: "Redis / Valkey", role: "Cache & key-value store", siteId: "kablay-il", siteName: "Kablay IL",
              container: .init(id: "redis-fixture", name: "kablay-redis-1", project: "kablay", state: "running", status: "Up 3 days", image: "redis:7", imageId: "sha256:fixture", cpuPercent: 1.2, memoryBytes: 112_000_000, memoryLimit: 536_870_912, networkRxBytes: 27_000_000, networkTxBytes: 11_000_000, pids: 5))
    ]

    static let sources = Sources(windowHours: 24, site: nil,
        sources: [.init(name: "Direct", requests: 5_854, bytes: 81_920_000), .init(name: "Googlebot", requests: 2_945, bytes: 35_651_584), .init(name: "Google", requests: 1_082, bytes: 9_437_184)],
        countries: [.init(name: "Israel", requests: 6_657, bytes: 73_400_320), .init(name: "United States", requests: 2_180, bytes: 30_408_704), .init(name: "Germany", requests: 859, bytes: 8_601_600)],
        bots: [.init(name: "Googlebot", requests: 2_945, bytes: 35_651_584), .init(name: "GoogleOther", requests: 872, bytes: 7_340_032), .init(name: "Bingbot", requests: 204, bytes: 1_468_006)])

    static let requests: [RequestSample] = (0..<42).map { index in
        let site = sites[index % sites.count]
        let paths = ["/", "/analytics/contact-settings", "/api/search", "/specialists", "/auth"]
        let statuses = [200, 200, 200, 404, 502, 200, 429]
        return .init(id: "req-\(index)", time: ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(-index * 28))), site: site.id, host: site.domains[0], method: index % 6 == 0 ? "POST" : "GET", path: paths[index % paths.count], status: statuses[index % statuses.count], bytes: Double(437 + index * 89), requestBytes: Double(212 + index), durationMs: Double(2 + (index * 73) % 1200), scheme: "https", protocolName: "HTTP/2.0", tlsProtocol: "TLSv1.3", tlsCipher: "TLS_AES_256_GCM_SHA384", upstreamAddr: "127.0.0.1:3000", upstreamStatus: String(statuses[index % statuses.count]), upstreamMs: Double(1 + index % 83), cacheStatus: index % 4 == 0 ? "HIT" : "MISS", clientIp: index % 3 == 0 ? "203.0.113.\(20 + index)" : "198.51.100.\(10 + index)", internalRequest: false, country: index % 3 == 0 ? "Israel" : "United States", countryCode: index % 3 == 0 ? "IL" : "US", region: index % 3 == 0 ? "Tel Aviv" : "Virginia", city: index % 3 == 0 ? "Tel Aviv" : "Ashburn", latitude: index % 3 == 0 ? 32.0853 : 39.0438, longitude: index % 3 == 0 ? 34.7818 : -77.4874, userAgent: index % 5 == 0 ? "Googlebot/2.1" : "Safari/605.1.15", source: index % 5 == 0 ? "Googlebot" : "Direct", referrerPath: index % 5 == 0 ? "/search" : nil, bot: index % 5 == 0 ? "Googlebot" : nil)
    }

    static let storage = StorageResponse(mode: "summary", scannedAt: ISO8601DateFormatter().string(from: .now), root: "/", path: "/", parent: nil, disk: overview.disk, totalBytes: overview.disk.used, analyzedBytes: overview.disk.used, unattributedBytes: 0,
        sites: [.init(id: "applydjinn", name: "ApplyDjinn", bytes: 5_690_343_424, items: 15), .init(id: "kablay-il", name: "Kablay IL", bytes: 3_435_973_837, items: 19), .init(id: "host", name: "Host & shared", bytes: 51_959_742_464, items: 12)],
        categories: [.init(id: "host", name: "Host & shared", bytes: 51_959_742_464, items: 12), .init(id: "persistent", name: "Persistent data", bytes: 5_798_205_440, items: 8), .init(id: "application", name: "Application files", bytes: 3_650_722_202, items: 52), .init(id: "media", name: "Images & media", bytes: 239_494_758, items: 5)],
        areas: [], entries: [
            .init(path: "/var/lib/docker/overlay2", kind: "directory", category: "Container layers", siteId: nil, siteName: "Host & shared", bytes: 31_385_128_960, direct: false),
            .init(path: "/swapfile", kind: "file", category: "Swap", siteId: nil, siteName: "Host & shared", bytes: 8_589_934_592, direct: true),
            .init(path: "/var/lib/postgresql", kind: "directory", category: "Databases", siteId: nil, siteName: "Host & shared", bytes: 7_516_192_768, direct: false),
            .init(path: "/srv/apps/applydjinn/uploads", kind: "directory", category: "Images & media", siteId: "applydjinn", siteName: "ApplyDjinn", bytes: 2_201_169_920, direct: false),
            .init(path: "/srv/apps/applydjinn/db", kind: "directory", category: "Persistent data", siteId: "applydjinn", siteName: "ApplyDjinn", bytes: 1_923_514_368, direct: false)
        ])

    static let projects: [ProjectHealth] = sites.map { site in
        ProjectHealth(id: site.id, name: site.name, root: "/srv/apps/\(site.id)", revision: "c3197f8", version: "1.0", status: "CURRENT", completeness: site.id == "applydjinn" ? "PARTIAL" : "CURRENT", scanner: "native", scannedAt: ISO8601DateFormatter().string(from: .now), git: .init(status: "CURRENT", head: "c3197f8", branch: "main", dirty: site.id == "kablay-il", dirtyFiles: site.id == "kablay-il" ? 12 : 0, untrackedFiles: 0, lastCommitAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7200)), lastMessage: "Update production configuration", evidence: "local"), graph: .init(status: "CURRENT", revision: "c3197f8", nodes: 1800 + site.name.count * 417, edges: 4900 + site.name.count * 801, buildMs: 460), analysis: .init(status: "CURRENT", modules: [.init(path: "src", files: 84, symbols: 526), .init(path: "api", files: 31, symbols: 218)], hotPaths: [.init(label: "request", kind: "function", file: "src/api.ts", line: 7, score: 0.91)], deadCode: [.init(label: "legacyHandler", kind: "function", file: "src/legacy.ts", line: 42, confidence: "high", reason: "No inbound references")]), vulnerabilities: site.id == "eppy" ? [] : [.init(id: "CVE-2026-1142", severity: site.id == "applydjinn" ? "critical" : "high", package: "example-runtime", installedVersion: "2.8.1", fixedVersion: "2.8.4", summary: "Request parsing can consume excessive resources", url: "https://example.invalid/CVE-2026-1142")], findings: [.init(category: "architecture", severity: "medium", message: "Module boundary is crossed by a direct import", file: "src/server.ts", line: 118)])
    }

    static let jobs: [JobState] = [
        .init(id: "backup", name: "Database backup", timerUnit: "backup.timer", runUnit: "backup.service", activeState: "active", unitFileState: "enabled", nextRun: "in 2 hours", lastResult: "success"),
        .init(id: "scan", name: "Code health scan", timerUnit: "scan.timer", runUnit: "scan.service", activeState: "active", unitFileState: "enabled", nextRun: "tomorrow 02:00", lastResult: "success")
    ]
}
