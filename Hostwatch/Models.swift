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
struct TrafficGuardState: Codable { let policy: TrafficGuardPolicy; let stage: String; let reason: String; let requestsPerSecond: Double; let ingressMbps: Double; let egressMbps: Double; let packetsPerSecond: Double; let appliedMbps: Double; let managed: Bool; let error: String? }

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

    struct Memory: Codable { let total: Double; let used: Double; let available: Double; let swapTotal: Double; let swapUsed: Double }
    struct Disk: Codable { let total: Double; let used: Double; let free: Double }
    struct Network: Codable { let rxBytes: Double; let txBytes: Double; let rxBytesPerSecond: Double; let txBytesPerSecond: Double; let rxPacketsPerSecond: Double; let txPacketsPerSecond: Double }
    struct Budget: Codable { let period: String; let usedBytes: Double; let includedBytes: Double; let warningBytes: Double; let cutoffBytes: Double; let locked: Bool; let egressMbps: Double; let emergencyMbps: Double; let monthlyMaxAtCapBytes: Double }
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

struct Site: Codable, Identifiable, Hashable {
    let id: String; let name: String; let domains: [String]; let sharedNginx: Bool; let containers: [ContainerInfo]
    let cpuPercent: Double; let memoryBytes: Double; let memoryLimit: Double; let requestsPerMinute: Double; let bytesPerMinute: Double; let errorRate: Double; let p95Ms: Double
    static func == (lhs: Site, rhs: Site) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct TrafficPoint: Codable, Identifiable {
    var id: String { time }
    let time: String; let requests: Double; let bytes: Double; let errors4xx: Double; let errors5xx: Double; let averageMs: Double
}
struct SystemPoint: Codable, Identifiable {
    var id: String { time }
    let time: String; let cpuPercent: Double; let memoryBytes: Double; let swapBytes: Double; let diskBytes: Double; let load1: Double
    let rxBytesPerSecond: Double; let txBytesPerSecond: Double; let rxPacketsPerSecond: Double; let txPacketsPerSecond: Double; let riskScore: Double
}
struct SourceMetric: Codable, Identifiable, Hashable { var id: String { name }; let name: String; let requests: Double; let bytes: Double }
struct Sources: Codable { let windowHours: Int; let site: String?; let sources: [SourceMetric]; let countries: [SourceMetric]; let bots: [SourceMetric] }

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
    let userAgent: String; let source: String; let referrerPath: String?; let bot: String?

    enum CodingKeys: String, CodingKey {
        case id,time,site,host,method,path,status,bytes,requestBytes,durationMs,scheme,tlsProtocol,tlsCipher,upstreamAddr,upstreamStatus,upstreamMs,cacheStatus,clientIp,country,countryCode,region,city,latitude,longitude,userAgent,source,referrerPath,bot
        case protocolName = "protocol"
        case internalRequest = "internal"
    }
}
struct ErrorEvidence: Codable { let windowHours: Int; let site: String?; let interval: String?; let requests: [RequestSample]; let retainedErrors: Int; let retainedFrom: String?; let capped: Bool }

struct StorageGroup: Codable, Identifiable, Hashable { let id: String; let name: String; let bytes: Double; let items: Int }
struct StorageEntry: Codable, Identifiable, Hashable {
    var id: String { "\(path)|\(siteId ?? "host")" }
    let path: String; let kind: String; let category: String; let siteId: String?; let siteName: String?; let bytes: Double; let direct: Bool?
}
struct StorageResponse: Codable {
    let mode: String; let scannedAt: String; let root: String; let path: String; let parent: String?; let disk: Overview.Disk
    let totalBytes: Double; let analyzedBytes: Double; let unattributedBytes: Double
    let sites: [StorageGroup]; let categories: [StorageGroup]; let areas: [StorageEntry]; let entries: [StorageEntry]
}

struct Vulnerability: Codable, Identifiable, Hashable { let id: String; let severity: String; let package: String; let installedVersion: String; let fixedVersion: String; let summary: String; let url: String }
struct HealthFinding: Codable, Identifiable, Hashable { var id: String { "\(file):\(line):\(message)" }; let category: String; let severity: String; let message: String; let file: String; let line: Int }
struct GraphHealth: Codable { let status: String?; let revision: String?; let nodes: Int?; let edges: Int?; let buildMs: Double? }
struct GitHealth: Codable { let status: String?; let head: String?; let branch: String?; let dirty: Bool?; let dirtyFiles: Int?; let untrackedFiles: Int?; let lastCommitAt: String?; let lastMessage: String?; let evidence: String? }
struct CodeAnalysis: Codable { let status: String?; let modules: [CodeModule]?; let hotPaths: [HotPath]?; let deadCode: [DeadCode]? }
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

enum SidebarPage: String, CaseIterable, Identifiable {
    case overview, traffic, incidents, topology, workloads, policies, environment, codeHealth, automations, access, security, organization
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Overview"; case .traffic: "Traffic"; case .incidents: "Incidents & risks"; case .topology: "Runtime topology"
        case .workloads: "Workloads"; case .policies: "Traffic policies"; case .environment: "Environment"; case .codeHealth: "Code health"
        case .automations: "Automations"; case .access: "Access"; case .security: "Account security"; case .organization: "Organization"
        }
    }
    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"; case .traffic: "chart.xyaxis.line"; case .incidents: "exclamationmark.shield"; case .topology: "point.3.connected.trianglepath.dotted"
        case .workloads: "shippingbox"; case .policies: "shield.lefthalf.filled"; case .environment: "key.horizontal"; case .codeHealth: "waveform.path.ecg.rectangle"
        case .automations: "clock.arrow.trianglehead.counterclockwise.rotate.90"; case .access: "person.2.badge.gearshape"; case .security: "lock.shield"; case .organization: "building.2"
        }
    }
}
