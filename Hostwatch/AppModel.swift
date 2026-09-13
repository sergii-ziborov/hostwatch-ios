import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var session = SessionState()
    @Published var nodes: [ManagedNode] = []
    @Published var selectedNode = ""
    @Published var selectedSite = ""
    @Published var hours = 24
    @Published var live = true
    @Published var loading = false
    @Published var errorMessage: String?

    @Published var overview: Overview?
    @Published var sites: [Site] = []
    @Published var dataServices: [DataService] = []
    @Published var dataServicesError: String?
    @Published var history: [SystemPoint] = []
    @Published var traffic: [TrafficPoint] = []
    @Published var sources = Sources(windowHours: 24, site: nil, sources: [], countries: [], bots: [])
    @Published var requests: [RequestSample] = []
    @Published var errorEvidence: ErrorEvidence?
    @Published var paths: [RequestPath] = []
    @Published var storage: StorageResponse?
    @Published var projects: [ProjectHealth] = []
    @Published var jobs: [JobState] = []
    @Published var license: LicenseStatus?
    @Published var members: [Member] = []
    @Published var environment: EnvironmentState?
    @Published var accessRules = AccessRuleState(rules: [], managed: false, updatedAt: nil, error: nil)
    @Published var guardState: TrafficGuardState?

    @Published var baseURLText: String {
        didSet { UserDefaults.standard.set(baseURLText, forKey: "controlPlaneURL") }
    }

    let fixtures: Bool
    private var client: APIClient
    private var liveTask: Task<Void, Never>?

    init() {
#if DEBUG
        fixtures = ProcessInfo.processInfo.environment["HOSTWATCH_FIXTURES"] == "1"
#else
        // The distributed app always requires a real, authenticated control plane.
        fixtures = false
#endif
        let saved = UserDefaults.standard.string(forKey: "controlPlaneURL") ?? "https://gethostwatch.com"
        baseURLText = saved
        client = APIClient(baseURL: URL(string: saved) ?? URL(string: "https://gethostwatch.com")!)
#if DEBUG
        if fixtures {
            session = SessionState(authenticated: true, csrf: "fixture", user: .init(id: "owner", email: "owner@hostwatch.local", name: "Sergii Ziborov", totpEnabled: true), organization: .init(id: "org", name: "Ziborov Infrastructure", slug: "ziborov", createdAt: ISO8601DateFormatter().string(from: .now)), role: "platform_owner")
            nodes = [.init(id: "primary", name: "Primary node", url: "https://node.internal", local: false, createdAt: ISO8601DateFormatter().string(from: .now))]
            selectedNode = "primary"
            installFixtures()
        } else {
            Task { await restoreSession() }
        }
#else
        Task { await restoreSession() }
#endif
    }

    deinit { liveTask?.cancel() }

#if DEBUG
    private func installFixtures() {
        overview = Fixtures.overview; sites = Fixtures.sites; dataServices = Fixtures.dataServices; dataServicesError = nil
        history = Fixtures.history; traffic = Fixtures.traffic; sources = Fixtures.sources
        requests = Fixtures.requests; errorEvidence = .init(windowHours: 24, site: nil, interval: nil, requests: Fixtures.requests.filter { $0.status >= 400 }, retainedErrors: Fixtures.requests.filter { $0.status >= 400 }.count, retainedFrom: Fixtures.requests.last?.time, capped: false)
        let grouped = Dictionary(grouping: Fixtures.requests, by: \RequestSample.path)
        var fixturePaths: [RequestPath] = []
        for (path, rows) in grouped {
            let bytes = rows.reduce(0.0) { $0 + $1.bytes }
            let clientErrors = rows.filter { (400..<500).contains($0.status) }.count
            let serverErrors = rows.filter { $0.status >= 500 }.count
            let duration = rows.reduce(0.0) { $0 + $1.durationMs }
            fixturePaths.append(.init(path: path, requests: Double(rows.count), bytes: bytes, errors4xx: Double(clientErrors), errors5xx: Double(serverErrors), averageMs: duration / Double(rows.count), errorStatuses: nil, errorMethods: nil))
        }
        paths = fixturePaths.sorted { $0.requests > $1.requests }
        storage = Fixtures.storage; projects = Fixtures.projects; jobs = Fixtures.jobs
        license = .init(deploymentMode: "enterprise", state: "active", enforced: true, installationId: "hostwatch-enterprise", message: "Enterprise license active", claims: .init(customer: "Ziborov Infrastructure", edition: "enterprise", expiresAt: "2027-09-12", limits: .init(nodes: 25, users: 100), features: ["traffic", "topology", "code-health", "policies"]))
        members = [.init(userId: "owner", organizationId: "org", role: "platform_owner", user: .init(id: "owner", email: "owner@hostwatch.local", name: "Sergii Ziborov")), .init(userId: "ops", organizationId: "org", role: "operator", user: .init(id: "ops", email: "ops@hostwatch.local", name: "Operations"))]
        environment = .init(siteId: selectedSite.isEmpty ? Fixtures.sites[0].id : selectedSite, variables: [.init(name: "DATABASE_URL", secret: true), .init(name: "NODE_ENV", secret: false), .init(name: "SENTRY_DSN", secret: true)], managed: true, updatedAt: ISO8601DateFormatter().string(from: .now), error: nil)
        accessRules = .init(rules: [.init(id: "rule-1", site: "applydjinn", kind: "country", value: "RU", label: "Policy review", createdAt: ISO8601DateFormatter().string(from: .now))], managed: true, updatedAt: ISO8601DateFormatter().string(from: .now), error: nil)
        guardState = .init(policy: .init(enabled: true, mode: "automatic", includedBytes: 21_990_232_555_520, warningBytes: 32_985_348_833_280, cutoffBytes: 41_782_136_619_008, normalMbps: 100, warningMbps: 20, emergencyMbps: 1, warningAction: "throttle", anomalyEnabled: true, maxRequestsPerSecond: 800, maxIngressMbps: 180, maxPacketsPerSecond: 10_000, anomalyAction: "throttle", anomalyMbps: 5, triggerSeconds: 20, recoverySeconds: 180, riskThreshold: 72, updatedAt: ISO8601DateFormatter().string(from: .now)), stage: "normal", reason: "No active threshold breach", requestsPerSecond: 62, ingressMbps: 4.8, egressMbps: 2.1, packetsPerSecond: 138, appliedMbps: 100, managed: true, error: nil)
    }
#endif

    func restoreSession() async {
        do {
            try await configureClient()
            session = try await client.sessionState()
            if session.authenticated { try await loadNodes(); await reload(page: .overview) }
        } catch { session = SessionState(); errorMessage = error.localizedDescription }
    }

    func signIn(email: String, password: String) async {
        loading = true; errorMessage = nil
        defer { loading = false }
        do {
            try await configureClient()
            session = try await client.signIn(email: email, password: password)
            if session.authenticated { try await loadNodes(); await reload(page: .overview) }
        } catch { errorMessage = error.localizedDescription }
    }

    func verify(otp: String) async {
        loading = true; defer { loading = false }
        do {
            session = try await client.verify(otp: otp)
            if session.authenticated { try await loadNodes(); await reload(page: .overview) }
        } catch { errorMessage = error.localizedDescription }
    }

    func startQR(kind: String) async throws -> QRStart {
        try await configureClient()
        return try await client.startQR(kind: kind)
    }

    func redeemQR(_ ticket: QRStart) async throws -> Bool {
        let result = try await client.redeemQR(ticket)
        guard result.authenticated else { return false }
        session = result
        try await loadNodes()
        await reload(page: .overview)
        return true
    }

    func claimDeviceQR(_ ticket: DeviceQRTicket, proof: String) async throws -> QRApproval {
        guard let server = URL(string: ticket.server) else { throw APIError.invalidURL }
        await client.configure(baseURL: server)
        let claim = try await client.claimDeviceQR(ticket, proof: proof)
        baseURLText = ticket.server
        return claim
    }

    func redeemDeviceQR(_ ticket: DeviceQRTicket, proof: String) async throws -> Bool {
        let result = try await client.redeemDeviceQR(ticket, proof: proof)
        guard result.authenticated else { return false }
        session = result
        try await loadNodes()
        await reload(page: .overview)
        return true
    }

    func inspectQR(_ value: String) async throws -> QRApproval { try await client.inspectQR(value) }
    func pendingQRApprovals() async throws -> [QRApproval] { try await client.pendingQRApprovals() }
    func approveQR(_ ticket: QRApproval, approve: Bool) async throws { try await client.approveQR(ticket, approve: approve) }
    func beginTOTP(currentPassword: String) async throws -> TOTPSetup { try await client.beginTOTP(currentPassword: currentPassword) }
    func confirmTOTP(otp: String) async throws {
        try await client.confirmTOTP(otp: otp)
        _ = try? await client.signOut()
        session = SessionState()
    }
    func disableTOTP(currentPassword: String, otp: String) async throws {
        try await client.disableTOTP(currentPassword: currentPassword, otp: otp)
        _ = try? await client.signOut()
        session = SessionState()
    }

    func signOut() async {
        if fixtures { return }
        do { session = try await client.signOut() } catch { errorMessage = error.localizedDescription }
    }

    private func configureClient() async throws {
        guard let url = URL(string: baseURLText), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { throw APIError.invalidURL }
        await client.configure(baseURL: url)
    }

    private func loadNodes() async throws {
        nodes = try await client.nodes()
        if selectedNode.isEmpty { selectedNode = nodes.first?.id ?? "" }
        await client.select(node: selectedNode)
    }

    func changeNode(_ id: String, page: SidebarPage) async {
        selectedNode = id; await client.select(node: id); await reload(page: page)
    }

    func setLive(_ enabled: Bool, page: SidebarPage) {
        live = enabled
        liveTask?.cancel(); liveTask = nil
        guard enabled else { return }
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                await self.reload(page: page, quiet: true)
            }
        }
    }

    func reload(page: SidebarPage, quiet: Bool = false) async {
#if DEBUG
        if fixtures { installFixtures(); return }
#endif
        if !quiet { loading = true }; defer { if !quiet { loading = false } }
        do {
            let commonOverview = try await client.overview()
            let commonSites = try await client.sites()
            overview = commonOverview; sites = commonSites
            switch page {
            case .overview:
                history = try await client.history(hours: hours)
                await loadDataServices()
            case .traffic:
                async let trafficCall = client.traffic(site: selectedSite, hours: hours)
                async let sourcesCall = client.sources(site: selectedSite, hours: hours)
                async let requestsCall = client.requests(site: selectedSite)
                async let errorsCall = client.errors(site: selectedSite, hours: hours)
                async let pathsCall = client.paths(site: selectedSite, hours: hours)
                let loaded = try await (trafficCall, sourcesCall, requestsCall, errorsCall, pathsCall)
                traffic = loaded.0; sources = loaded.1; requests = loaded.2; errorEvidence = loaded.3; paths = loaded.4.paths
            case .incidents, .topology, .codeHealth:
                projects = try await client.projects()
                if page != .codeHealth { jobs = try await client.jobs() }
            case .workloads:
                requests = try await client.requests(site: selectedSite)
                await loadDataServices()
            case .policies:
                async let guardCall = client.trafficGuard()
                async let rulesCall = client.accessRules(site: selectedSite)
                (guardState, accessRules) = try await (guardCall, rulesCall)
            case .environment:
                if let site = sites.first(where: { $0.id == selectedSite }) ?? sites.first { environment = try await client.environment(site: site.id) }
            case .automations:
                jobs = try await client.jobs()
            case .access, .organization:
                async let licenseCall = client.license()
                async let memberCall = client.members()
                (license, members) = try await (licenseCall, memberCall)
            case .security:
                break
            }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadDataServices() async {
        do {
            dataServices = try await client.dataServices()
            dataServicesError = nil
        } catch {
            dataServices = []
            dataServicesError = error.localizedDescription
        }
    }

    func scanStorage(refresh: Bool = false) async {
#if DEBUG
        if fixtures { storage = Fixtures.storage; return }
#endif
        do { storage = try await client.storage(refresh: refresh) } catch { errorMessage = error.localizedDescription }
    }

    func browseStorage(path: String) async {
#if DEBUG
        if fixtures {
            storage = StorageResponse(mode: "browse", scannedAt: Fixtures.storage.scannedAt, root: "/", path: path, parent: path == "/" ? nil : "/", disk: Fixtures.storage.disk, totalBytes: Fixtures.storage.totalBytes, analyzedBytes: Fixtures.storage.analyzedBytes, unattributedBytes: 0, sites: Fixtures.storage.sites, categories: Fixtures.storage.categories, areas: Fixtures.storage.entries.filter { $0.path.hasPrefix(path) }, entries: Fixtures.storage.entries.filter { $0.path.hasPrefix(path) })
            return
        }
#endif
        do { storage = try await client.storage(path: path) } catch { errorMessage = error.localizedDescription }
    }

    func runSiteAction(_ site: Site, action: String) async {
        guard !fixtures else { return }
        do { try await client.siteAction(site.id, action: action); await reload(page: .workloads) } catch { errorMessage = error.localizedDescription }
    }

    func block(site: String, kind: String, value: String) async {
        guard !fixtures else { return }
        do {
            try await client.addAccessRule(site: site, kind: kind, value: value, label: "Added from iOS")
            accessRules = try await client.accessRules(site: selectedSite)
        } catch { errorMessage = error.localizedDescription }
    }

    func setEnvironment(name: String, value: String) async {
        guard let site = sites.first(where: { $0.id == selectedSite }) ?? sites.first else { return }
        if fixtures {
            let old = environment?.variables ?? []
            if !old.contains(where: { $0.name == name }) { environment = .init(siteId: site.id, variables: old + [.init(name: name, secret: true)], managed: true, updatedAt: ISO8601DateFormatter().string(from: .now), error: nil) }
            return
        }
        do { environment = try await client.setEnvironment(site: site.id, name: name, value: value) } catch { errorMessage = error.localizedDescription }
    }

    func deleteEnvironment(name: String) async {
        guard let site = sites.first(where: { $0.id == selectedSite }) ?? sites.first else { return }
        if fixtures { environment = environment.map { .init(siteId: $0.siteId, variables: $0.variables.filter { $0.name != name }, managed: $0.managed, updatedAt: $0.updatedAt, error: nil) }; return }
        do { environment = try await client.deleteEnvironment(site: site.id, name: name) } catch { errorMessage = error.localizedDescription }
    }

    func removeRule(_ rule: AccessRule) async {
        if fixtures { accessRules = .init(rules: accessRules.rules.filter { $0.id != rule.id }, managed: true, updatedAt: accessRules.updatedAt, error: nil); return }
        do { accessRules = try await client.removeAccessRule(id: rule.id) } catch { errorMessage = error.localizedDescription }
    }

    func saveGuard(_ policy: TrafficGuardPolicy) async {
        if fixtures { guardState = guardState.map { .init(policy: policy, stage: $0.stage, reason: $0.reason, requestsPerSecond: $0.requestsPerSecond, ingressMbps: $0.ingressMbps, egressMbps: $0.egressMbps, packetsPerSecond: $0.packetsPerSecond, appliedMbps: policy.normalMbps, managed: $0.managed, error: nil) }; return }
        do { guardState = try await client.updateTrafficGuard(policy) } catch { errorMessage = error.localizedDescription }
    }

    func runJob(_ job: JobState) async {
        guard !fixtures else { return }
        do { try await client.runJob(job.id); jobs = try await client.jobs() } catch { errorMessage = error.localizedDescription }
    }

    func createUser(name: String, email: String, password: String, role: String) async {
        if fixtures {
            let id = UUID().uuidString
            members.append(.init(userId: id, organizationId: session.organization?.id ?? "org", role: role, user: .init(id: id, email: email, name: name)))
            return
        }
        do { try await client.createUser(name: name, email: email, password: password, role: role); members = try await client.members() } catch { errorMessage = error.localizedDescription }
    }

    func installLicense(_ value: String) async {
        guard !fixtures else { return }
        do { license = try await client.installLicense(value) } catch { errorMessage = error.localizedDescription }
    }
}
