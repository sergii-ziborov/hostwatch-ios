import Foundation

struct SessionState: Codable {
    var authenticated = false
    var requiresOtp: Bool?
    var csrf: String?
    var user: User?
    var organization: Organization?
    var role: String?
    var license: LicenseStatus?

    struct User: Codable { let id: String; let email: String; let name: String; let totpEnabled: Bool }
}

struct QRStart: Codable {
    let id: String
    let secret: String
    let entryCode: String
    let verificationCode: String
    let expiresAt: String
    let kind: String
}

struct QRApproval: Codable, Identifiable {
    let id: String
    let entryCode: String
    let verificationCode: String
    let expiresAt: String
    let kind: String
    let device: String
    let clientIP: String
    let status: String
}

struct TOTPSetup: Codable {
    let totpSecret: String
    let issuer: String
    let account: String
    var uri: String {
        var parts = URLComponents()
        parts.scheme = "otpauth"
        parts.host = "totp"
        parts.path = "/\(issuer):\(account)"
        parts.queryItems = [.init(name: "secret", value: totpSecret), .init(name: "issuer", value: issuer),
                            .init(name: "algorithm", value: "SHA1"), .init(name: "digits", value: "6"), .init(name: "period", value: "30")]
        return parts.url?.absoluteString ?? ""
    }
}

struct Organization: Codable, Identifiable { let id: String; let name: String; let slug: String; let createdAt: String }
struct LicenseStatus: Codable {
    let deploymentMode: String
    let state: String
    let enforced: Bool
    let installationId: String
    let message: String
    let claims: Claims?
    struct Claims: Codable { let customer: String; let edition: String; let expiresAt: String; let limits: Limits; let features: [String] }
    struct Limits: Codable { let nodes: Int; let users: Int }
}
struct ManagedNode: Codable, Identifiable { let id: String; let name: String; let url: String; let local: Bool; let createdAt: String }
struct Member: Codable, Identifiable {
    var id: String { userId }
    let userId: String; let organizationId: String; let role: String; let user: MemberUser
    struct MemberUser: Codable { let id: String; let email: String; let name: String }
}
struct EnvironmentVariable: Codable, Identifiable { var id: String { name }; let name: String; let secret: Bool }
struct EnvironmentState: Codable { let siteId: String; let variables: [EnvironmentVariable]; let managed: Bool; let updatedAt: String?; let error: String? }
struct AccessRule: Codable, Identifiable { let id: String; let site: String; let kind: String; let value: String; let label: String?; let createdAt: String }
struct AccessRuleState: Codable { let rules: [AccessRule]; let managed: Bool; let updatedAt: String?; let error: String? }
struct TrafficGuardPolicy: Codable {
    var enabled: Bool; var mode: String; var includedBytes: Double; var warningBytes: Double; var cutoffBytes: Double
    var normalMbps: Double; var warningMbps: Double; var emergencyMbps: Double; var warningAction: String
    var anomalyEnabled: Bool; var maxRequestsPerSecond: Double; var maxIngressMbps: Double; var maxPacketsPerSecond: Double
    var anomalyAction: String; var anomalyMbps: Double; var triggerSeconds: Int; var recoverySeconds: Int; var riskThreshold: Double; var updatedAt: String
}
struct TrafficGuardState: Codable {
    let policy: TrafficGuardPolicy
    let stage: String
    let reason: String
    let requestsPerSecond: Double
    let ingressMbps: Double
    let egressMbps: Double
    let packetsPerSecond: Double
    let appliedMbps: Double
    let managed: Bool
    let error: String?
    var shapingMode: String? = nil
    var verified: Bool? = nil
    var constraints: [String]? = nil
    var attackStage: String? = nil
    var dailyStage: String? = nil
    var monthlyStage: String? = nil
    var meterStage: String? = nil
}

struct Overview: Codable {
    let timestamp: String
    let hostname: String
    let uptimeSeconds: Double
    let cpuPercent: Double
    let load1: Double
    let load5: Double
    let load15: Double
    let memory: Memory
    let disk: Disk
    let network: Network
    let budget: Budget
    let nginxLogHealthy: Bool
    let dockerHealthy: Bool
    var runtimeHealthy: Bool? = nil
    var platform: String? = nil
    var trafficGuard: TrafficGuardState? = nil

    enum CodingKeys: String, CodingKey {
        case timestamp, hostname, uptimeSeconds, cpuPercent, load1, load5, load15
        case memory, disk, network, budget, nginxLogHealthy, dockerHealthy, runtimeHealthy, platform
        case trafficGuard = "guard"
    }

    struct Memory: Codable { let total: Double; let used: Double; let available: Double; let swapTotal: Double; let swapUsed: Double }
    struct Disk: Codable { let total: Double; let used: Double; let free: Double }
    struct Network: Codable { let rxBytes: Double; let txBytes: Double; let rxBytesPerSecond: Double; let txBytesPerSecond: Double; let rxPacketsPerSecond: Double; let txPacketsPerSecond: Double }
    struct Budget: Codable {
        let period: String; let usedBytes: Double; let includedBytes: Double; let warningBytes: Double; let cutoffBytes: Double
        let locked: Bool; let egressMbps: Double; let emergencyMbps: Double; let monthlyMaxAtCapBytes: Double
        var dailyUsedBytes: Double? = nil
        var dailySoftBytes: Double? = nil
        var dailyHardBytes: Double? = nil
        var rolling24hBytes: Double? = nil
        var meterStatus: String? = nil
    }
}

struct NetworkPort: Codable, Identifiable {
    var id: String { "\(protocolName):\(port)" }
    let protocolName: String
    let port: Int
    let connections: Int
    let listening: Bool?

    enum CodingKeys: String, CodingKey { case protocolName = "protocol", port, connections, listening }
}

struct NetworkPorts: Codable {
    let observedAt: String
    let interface: String
    let tcpConnections: Int
    let udpConnections: Int
    let localPorts: [NetworkPort]
    let remotePorts: [NetworkPort]
    let available: Bool
    let error: String?
}

struct ContainerInfo: Codable, Identifiable {
    let id: String; let name: String; let project: String; let state: String; let status: String; let image: String; let imageId: String
    let cpuPercent: Double; let memoryBytes: Double; let memoryLimit: Double; let networkRxBytes: Double; let networkTxBytes: Double; let pids: Int
}

struct DataService: Codable, Identifiable {
    var id: String { container.id }
    let type: String
    let role: String
    let siteId: String?
    let siteName: String?
    let container: ContainerInfo
}

struct DataFile: Decodable, Identifiable {
    var id: String { path }
    let path: String
    let type: String
    let siteId: String?
    let siteName: String?
    let container: String?
    let sizeBytes: Double
    let modifiedAt: String
    let backup: Bool
}

struct DataServicesResponse: Decodable {
    let services: [DataService]
    let files: [DataFile]
    let dockerHealthy: Bool
    let scannedAt: String
    let scanError: String?

    // Older node agents returned a bare service array. Keep their inventory
    // readable while accepting the current response with discovered data files.
    init(from decoder: Decoder) throws {
        if let legacy = try? [DataService](from: decoder) {
            services = legacy; files = []; dockerHealthy = true; scannedAt = ""
            scanError = "This node agent does not report database files yet."
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        services = try values.decode([DataService].self, forKey: .services)
        files = try values.decode([DataFile].self, forKey: .files)
        dockerHealthy = try values.decode(Bool.self, forKey: .dockerHealthy)
        scannedAt = try values.decode(String.self, forKey: .scannedAt)
        scanError = try values.decodeIfPresent(String.self, forKey: .scanError)
    }

    private enum CodingKeys: String, CodingKey { case services, files, dockerHealthy, scannedAt, scanError }
}

struct DataTableInfo: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let columns: [String]?
    let rowCount: Int?
}

struct DataTablesResponse: Decodable {
    let path: String
    let tables: [DataTableInfo]
    let error: String?
}

struct DataRowsResponse: Decodable {
    let path: String
    let table: String
    let columns: [String]
    let rows: [[String]]
    let offset: Int
    let limit: Int
    let rowCount: Int?
    let truncated: Bool
}

struct MCPGovernance: Codable {
    var enabled: Bool
    var allowObserve: Bool
    var allowMutate: Bool
    var deniedTools: [String]
    var maxMutationsPerHour: Int
    var staleAfterSeconds: Int
    var updatedAt: String?
}

struct MCPToolInfo: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let kind: String
    let title: String
}

struct MCPClientInfo: Decodable, Identifiable {
    let id: String
    let hostname: String
    let username: String
    let app: String
    let remoteIp: String?
    let firstSeen: String
    let lastSeen: String
    let lastTool: String?
    let observeCalls: Int
    let mutateCalls: Int
    let stale: Bool
}

struct MCPHistoryEvent: Decodable, Identifiable {
    let id: String
    let time: String
    let clientId: String
    let hostname: String
    let username: String
    let app: String
    let tool: String
    let kind: String
    let status: String
    let summary: String?
    let error: String?
    let remoteIp: String?
}

struct MCPSnapshot: Decodable {
    let governance: MCPGovernance
    let clients: [MCPClientInfo]
    let history: [MCPHistoryEvent]
    let knownTools: [MCPToolInfo]
}

struct Site: Codable, Identifiable, Hashable {
    let id: String; let name: String; let domains: [String]; let sharedNginx: Bool; let containers: [ContainerInfo]
    let cpuPercent: Double; let memoryBytes: Double; let memoryLimit: Double; let requestsPerMinute: Double; let bytesPerMinute: Double; let errorRate: Double; let p95Ms: Double
    static func == (lhs: Site, rhs: Site) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct TrafficPoint: Codable, Identifiable {
    var id: String { time }
    let time: String; let requests: Double; let bytes: Double; let errors4xx: Double; let errors5xx: Double; let averageMs: Double
    var classifiedRequests: Double? = nil; var internalRequests: Double? = nil; var externalRequests: Double? = nil
}
struct SystemPoint: Codable, Identifiable {
    var id: String { time }
    let time: String; let cpuPercent: Double; let memoryBytes: Double; let swapBytes: Double; let diskBytes: Double; let load1: Double
    let rxBytesPerSecond: Double; let txBytesPerSecond: Double; let rxPacketsPerSecond: Double; let txPacketsPerSecond: Double; let riskScore: Double
}
struct SourceMetric: Codable, Identifiable, Hashable { var id: String { name }; let name: String; let requests: Double; let bytes: Double }
struct InternalRoute: Codable, Identifiable {
    var id: String { "\(caller)|\(destinationHost)|\(targetService ?? "")" }
    let caller: String; let destinationHost: String; let targetService: String?; let requests: Double; let bytes: Double
}
struct Sources: Codable {
    let windowHours: Int; let site: String?; let sources: [SourceMetric]; let countries: [SourceMetric]; let bots: [SourceMetric]
    var totalRequests: Double? = nil
    var classifiedRequests: Double? = nil; var internalRequests: Double? = nil; var externalRequests: Double? = nil
    var internalRoutes: [InternalRoute]? = nil
}

struct RequestPath: Codable, Identifiable, Hashable {
    var id: String { path }
    let path: String; let requests: Double; let bytes: Double; let errors4xx: Double; let errors5xx: Double; let averageMs: Double
    let errorStatuses: [String: Double]?; let errorMethods: [String: Double]?
}
struct RequestPaths: Codable { let windowHours: Int; let site: String?; let interval: String?; let paths: [RequestPath] }
struct RequestSample: Codable, Identifiable, Hashable {
    let id: String; let time: String; let site: String; let host: String; let method: String; let path: String; let status: Int
    let bytes: Double; let requestBytes: Double?; let durationMs: Double; let scheme: String?; let protocolName: String?; let tlsProtocol: String?; let tlsCipher: String?
    let upstreamAddr: String?; let upstreamStatus: String?; let upstreamMs: Double?; let cacheStatus: String?
    let clientIp: String; let internalRequest: Bool?; let country: String; let countryCode: String; let region: String?; let city: String?; let latitude: Double?; let longitude: Double?
    var clientService: String? = nil; var targetService: String? = nil
    let userAgent: String; let source: String; let referrerPath: String?; let bot: String?

    enum CodingKeys: String, CodingKey {
        case id,time,site,host,method,path,status,bytes,requestBytes,durationMs,scheme,tlsProtocol,tlsCipher,upstreamAddr,upstreamStatus,upstreamMs,cacheStatus,clientIp,clientService,targetService,country,countryCode,region,city,latitude,longitude,userAgent,source,referrerPath,bot
        case protocolName = "protocol"
        case internalRequest = "internal"
    }

    var origin: TrafficOrigin { TrafficOrigin(self) }
}

enum TrafficOrigin: String, Equatable {
    case external
    case ourService

    init(_ request: RequestSample) {
        self = request.internalRequest == true ? .ourService : .external
    }

    var badge: String { self == .ourService ? "OUR" : "EXT" }
    var title: String { self == .ourService ? "Our service" : "External" }
    var detail: String {
        self == .ourService ? "Call from one of our services" : "Public client after forwarding"
    }

    func sourceLabel(for request: RequestSample) -> String {
        switch self {
        case .ourService: return request.clientService ?? "Unknown private peer"
        case .external: return request.clientIp
        }
    }
}
struct ErrorEvidence: Codable { let windowHours: Int; let site: String?; let interval: String?; let requests: [RequestSample]; let retainedErrors: Int; let retainedFrom: String?; let capped: Bool }
struct ErrorProjectGroup: Codable, Identifiable {
    var id: String { projectId }
    let projectId: String; let projectName: String; let count: Int; let lastTime: String?
    let statuses: [String: Int]?; let requests: [RequestSample]
}
struct ErrorLogLine: Codable, Identifiable, Hashable {
    var id: String { "\(time ?? "")|\(stream)|\(text)" }
    let time: String?; let stream: String; let text: String; let crash: Bool?
}
struct ErrorContext: Codable {
    let request: RequestSample; let projectId: String; let projectName: String
    let previous: [RequestSample]; let logs: [ErrorLogLine]
    let logSource: String?; let logError: String?; let crashHint: String?
}
struct ImportedNote: Codable, Identifiable, Hashable {
    let id: String; let kind: String; let projectId: String?; let title: String
    let detail: String?; let severity: String?; let url: String?; let createdAt: String
}
struct ImportResult: Codable { let kind: String?; let added: [ImportedNote]; let skipped: Int }
struct MarkdownExport: Codable { let kind: String; let markdown: String; let itemCount: Int; let generatedAt: String }
struct ReclaimAdvice: Codable, Identifiable, Hashable {
    var id: String { "\(className)|\(path)" }
    let className: String; let path: String; let kind: String; let bytes: Double; let reason: String
    enum CodingKeys: String, CodingKey { case className = "class", path, kind, bytes, reason }
}

struct StorageGroup: Codable, Identifiable, Hashable { let id: String; let name: String; let bytes: Double; let items: Int }
struct StorageEntry: Codable, Identifiable, Hashable {
    var id: String { "\(path)|\(siteId ?? "host")" }
    let path: String; let kind: String; let category: String; let siteId: String?; let siteName: String?; let bytes: Double; let direct: Bool?
}
struct StorageResponse: Codable {
    let mode: String; let scannedAt: String; let root: String; let path: String; let parent: String?; let disk: Overview.Disk
    let totalBytes: Double; let analyzedBytes: Double; let unattributedBytes: Double
    let sites: [StorageGroup]; let categories: [StorageGroup]; let areas: [StorageEntry]; let entries: [StorageEntry]
    var advice: [ReclaimAdvice]? = nil
}

struct CleanupTarget: Codable, Identifiable {
    var id: String { kind }
    let kind: String; let name: String; let path: String
    let bytes: Double; let items: Int; let available: Bool
    let description: String; let consequence: String; let error: String?
}
struct CleanupPreview: Codable { let targets: [CleanupTarget]; let advice: [ReclaimAdvice]?; let scannedAt: String }
struct CleanupResult: Codable { let kind: String; let reclaimedBytes: Double; let deletedItems: Int; let completedAt: String }
struct CleanupRun: Codable { let results: [CleanupResult]; let errors: [String: String]?; let completedAt: String }

struct Vulnerability: Codable, Identifiable, Hashable { let id: String; let severity: String; let package: String; let installedVersion: String; let fixedVersion: String; let summary: String; let url: String }
struct HealthFinding: Codable, Identifiable, Hashable { var id: String { "\(file):\(line):\(message)" }; let category: String; let severity: String; let message: String; let file: String; let line: Int }
struct GraphHealth: Codable { let status: String?; let revision: String?; let nodes: Int?; let edges: Int?; let buildMs: Double? }
struct GitHealth: Codable { let status: String?; let head: String?; let branch: String?; let dirty: Bool?; let dirtyFiles: Int?; let untrackedFiles: Int?; let lastCommitAt: String?; let lastMessage: String?; let evidence: String? }
struct CodeCommunity: Codable, Identifiable, Hashable {
    let id: Int
    let nodes: Int
    var sample: [String]? = nil
}
struct CodeAnalysis: Codable {
    let status: String?
    let modules: [CodeModule]?
    var communities: [CodeCommunity]? = nil
    let hotPaths: [HotPath]?
    let deadCode: [DeadCode]?
}
struct CodeModule: Codable, Identifiable { var id: String { path }; let path: String; let files: Int; let symbols: Int }
struct HotPath: Codable, Identifiable { var id: String { "\(file):\(line)" }; let label: String; let kind: String; let file: String; let line: Int; let score: Double }
struct DeadCode: Codable, Identifiable { var id: String { "\(file):\(line)" }; let label: String; let kind: String; let file: String; let line: Int; let confidence: String; let reason: String }
struct ProjectHealth: Codable, Identifiable, Hashable {
    let id: String; let name: String; let root: String; let revision: String; let version: String; let status: String; let completeness: String; let scanner: String; let scannedAt: String
    let git: GitHealth?; let graph: GraphHealth?; let analysis: CodeAnalysis?; let vulnerabilities: [Vulnerability]?; let findings: [HealthFinding]?
    static func == (lhs: ProjectHealth, rhs: ProjectHealth) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct JobState: Codable, Identifiable, Hashable { let id: String; let name: String; let timerUnit: String; let runUnit: String; let activeState: String; let unitFileState: String; let nextRun: String; let lastResult: String }

struct HybridSettings: Codable {
    var homeMaxJobs: Int
    var homeMinDiskBytes: Int
    var homeStaleAfterSeconds: Int
    var keepAliveSeconds: Int
    var allowUnregisteredHome: Bool?
}

struct HybridPeer: Codable, Identifiable {
    let id: String
    let kind: String
    var publicIp: String?
    var previousIp: String?
    var tunnelIp: String?
    var lastSeen: String?
    var fresh: Bool
    var ipChanged: Bool
    var diskFreeBytes: Double?
    var runningJobs: Int?
    var cpuPercent: Double?
}

struct HybridAdmission: Codable {
    let accept: Bool
    let reason: String
    let homeFresh: Bool
    let activeLeases: Int
    let maxJobs: Int
    var diskFreeBytes: Double?
}

struct FleetLinkLayer: Codable {
    let name: String
    let status: String
    var detail: String?
}

struct FleetLink: Codable, Identifiable {
    let id: String
    let layers: [FleetLinkLayer]
}

enum SidebarPage: String, CaseIterable, Identifiable {
    case overview, traffic, data, incidents, errors, topology, workloads, fleet, cleanup, policies, environment, mcp, codeHealth, automations, access, security, organization
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Overview"; case .traffic: "Traffic"; case .data: "Database"; case .incidents: "Incidents & risks"; case .errors: "Errors"; case .topology: "Runtime topology"
        case .workloads: "Workloads"; case .fleet: "Fleet"; case .cleanup: "Cleanup"; case .policies: "Traffic policies"; case .environment: "Environment"; case .mcp: "MCP"
        case .codeHealth: "Code health"
        case .automations: "Automations"; case .access: "Access"; case .security: "Account security"; case .organization: "Organization"
        }
    }
    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"; case .traffic: "chart.xyaxis.line"; case .data: "cylinder.split.1x2"; case .incidents: "exclamationmark.shield"; case .errors: "exclamationmark.octagon"; case .topology: "point.3.connected.trianglepath.dotted"
        case .workloads: "shippingbox"; case .fleet: "laptopcomputer.and.iphone"; case .cleanup: "sparkles.rectangle.stack"; case .policies: "shield.lefthalf.filled"; case .environment: "key.horizontal"; case .mcp: "antenna.radiowaves.left.and.right"
        case .codeHealth: "waveform.path.ecg.rectangle"
        case .automations: "clock.arrow.circlepath"; case .access: "person.2"; case .security: "lock.shield"; case .organization: "building.2"
        }
    }
}
