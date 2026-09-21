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
    @Published var restoringSession = true
    @Published var hasSavedSession = false
    @Published var errorMessage: String?

    @Published var overview: Overview?
    @Published var sites: [Site] = []
    @Published var dataServices: [DataService] = []
    @Published var dataFiles: [DataFile] = []
    @Published var dataServicesScannedAt: String?
    @Published var dataServicesScanError: String?
    @Published var dataServicesError: String?
    @Published var history: [SystemPoint] = []
    @Published var traffic: [TrafficPoint] = []
    @Published var sources = Sources(windowHours: 24, site: nil, sources: [], countries: [], bots: [])
    @Published var requests: [RequestSample] = []
    @Published var errorEvidence: ErrorEvidence?
    @Published var errorGroups: [ErrorProjectGroup] = []
    @Published var importedNotes: [ImportedNote] = []
    @Published var importNotice: String?
    @Published var paths: [RequestPath] = []
    @Published var storage: StorageResponse?
    @Published var storageBrowse: StorageResponse?
    @Published var storageLoading = false
    @Published var storageError: String?
    @Published var cleanupPreview: CleanupPreview?
    @Published var cleanupLoading = false
    @Published var cleanupError: String?
    @Published var cleanupNotice: String?
    @Published var projects: [ProjectHealth] = []
    @Published var jobs: [JobState] = []
    @Published var license: LicenseStatus?
    @Published var members: [Member] = []
    @Published var environment: EnvironmentState?
    @Published var accessRules = AccessRuleState(rules: [], managed: false, updatedAt: nil, error: nil)
    @Published var guardState: TrafficGuardState?
    @Published var hybridPeers: [HybridPeer] = []
    @Published var hybridSettings: HybridSettings?
    @Published var hybridAdmission: HybridAdmission?
    @Published var fleetLinks: [FleetLink] = []
    @Published var hybridError: String?
    @Published var mcpSnapshot: MCPSnapshot?

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
            Task { await initialRestore() }
        }
#else
        Task { await initialRestore() }
#endif
    }

    deinit { liveTask?.cancel() }

    private func initialRestore() async {
        hasSavedSession = await client.hasSavedSession()
        if hasSavedSession, Self.prefersDeviceUnlock, !DeviceUnlock.isRunningTests {
            restoringSession = false
            return
        }
        if hasSavedSession { await unlockSavedSession() }
        else { await restoreSession() }
        restoringSession = false
    }

    static var prefersDeviceUnlock: Bool {
        guard DeviceUnlock.isAvailable() else { return false }
        if UserDefaults.standard.object(forKey: "biometricUnlockEnabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "biometricUnlockEnabled")
    }

    func unlockSavedSession() async {
        if session.authenticated {
            await persistSession()
            return
        }
        if let snapshot = await client.applySavedSession() {
            session = snapshot
            let url = await client.currentBaseURL()
            if url != baseURLText { baseURLText = url }
            hasSavedSession = true
        }
        await restoreSession()
    }

    func persistSession() async {
        guard session.authenticated, !fixtures else { return }
        await client.persistAuthenticated(session)
        hasSavedSession = true
    }

#if DEBUG
    private func installFixtures() {
        overview = Fixtures.overview; sites = Fixtures.sites; dataServices = Fixtures.dataServices; dataFiles = Fixtures.dataFiles; dataServicesError = nil; mcpSnapshot = Fixtures.mcp
        history = Fixtures.history; traffic = Fixtures.traffic; sources = Fixtures.sources
        requests = Fixtures.requests
        errorEvidence = .init(windowHours: 24, site: nil, interval: nil, requests: Fixtures.requests.filter { $0.status >= 400 }, retainedErrors: Fixtures.requests.filter { $0.status >= 400 }.count, retainedFrom: Fixtures.requests.last?.time, capped: false)
        errorGroups = []; importedNotes = []; importNotice = nil
        cleanupPreview = Fixtures.cleanupPreview
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
        storage = Fixtures.storage; restoringSession = false; projects = Fixtures.projects; jobs = Fixtures.jobs
        license = .init(deploymentMode: "enterprise", state: "active", enforced: true, installationId: "hostwatch-enterprise", message: "Enterprise license active", claims: .init(customer: "Ziborov Infrastructure", edition: "enterprise", expiresAt: "2027-09-12", limits: .init(nodes: 25, users: 100), features: ["traffic", "topology", "code-health", "policies"]))
        members = [.init(userId: "owner", organizationId: "org", role: "platform_owner", user: .init(id: "owner", email: "owner@hostwatch.local", name: "Sergii Ziborov")), .init(userId: "ops", organizationId: "org", role: "operator", user: .init(id: "ops", email: "ops@hostwatch.local", name: "Operations"))]
        environment = .init(siteId: selectedSite.isEmpty ? Fixtures.sites[0].id : selectedSite, variables: [.init(name: "DATABASE_URL", secret: true), .init(name: "NODE_ENV", secret: false), .init(name: "SENTRY_DSN", secret: true)], managed: true, updatedAt: ISO8601DateFormatter().string(from: .now), error: nil)
        accessRules = .init(rules: [.init(id: "rule-1", site: "applydjinn", kind: "country", value: "RU", label: "Policy review", createdAt: ISO8601DateFormatter().string(from: .now))], managed: true, updatedAt: ISO8601DateFormatter().string(from: .now), error: nil)
        guardState = .init(policy: .init(enabled: true, mode: "automatic", includedBytes: 21_990_232_555_520, warningBytes: 32_985_348_833_280, cutoffBytes: 41_782_136_619_008, normalMbps: 100, warningMbps: 20, emergencyMbps: 1, warningAction: "throttle", anomalyEnabled: true, maxRequestsPerSecond: 800, maxIngressMbps: 180, maxPacketsPerSecond: 10_000, anomalyAction: "throttle", anomalyMbps: 5, triggerSeconds: 20, recoverySeconds: 180, riskThreshold: 72, updatedAt: ISO8601DateFormatter().string(from: .now)), stage: "normal", reason: "No active threshold breach", requestsPerSecond: 62, ingressMbps: 4.8, egressMbps: 2.1, packetsPerSecond: 138, appliedMbps: 100, managed: true, error: nil)
        hybridPeers = Fixtures.hybridPeers
        hybridSettings = Fixtures.hybridSettings
        hybridAdmission = Fixtures.hybridAdmission
        fleetLinks = Fixtures.fleetLinks
        hybridError = nil
        if let site = ProcessInfo.processInfo.environment["HOSTWATCH_SITE"], sites.contains(where: { $0.id == site }) {
            selectedSite = site
        }
    }
#endif

    func restoreSession() async {
        do {
            try await configureClient()
            let value = try await client.sessionState()
            if value.authenticated {
                session = value
                hasSavedSession = true
                try await loadNodes()
                await reload(page: .overview)
                errorMessage = nil
            } else {
                await client.forgetSession()
                session = SessionState()
                hasSavedSession = false
            }
        } catch APIError.unauthorized {
            await client.forgetSession()
            session = SessionState()
            hasSavedSession = false
            errorMessage = APIError.unauthorized.errorDescription
        } catch {
            if let cached = await client.cachedSnapshot() {
                session = cached
                hasSavedSession = true
                _ = await client.applySavedSession()
            } else {
                session = SessionState()
                errorMessage = error.localizedDescription
            }
        }
    }

    func signIn(email: String, password: String) async {
        loading = true; errorMessage = nil
        defer { loading = false }
        do {
            try await configureClient()
            session = try await client.signIn(email: email, password: password)
            if session.authenticated {
                hasSavedSession = true
                try await loadNodes()
                await reload(page: .overview)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func verify(otp: String) async {
        loading = true; defer { loading = false }
        do {
            session = try await client.verify(otp: otp)
            if session.authenticated {
                hasSavedSession = true
                try await loadNodes()
                await reload(page: .overview)
            }
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
        hasSavedSession = true
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
        hasSavedSession = true
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
        await client.forgetSession()
        session = SessionState()
        hasSavedSession = false
        clearPrivateData()
    }
    func disableTOTP(currentPassword: String, otp: String) async throws {
        try await client.disableTOTP(currentPassword: currentPassword, otp: otp)
        _ = try? await client.signOut()
        await client.forgetSession()
        session = SessionState()
        hasSavedSession = false
        clearPrivateData()
    }

    func signOut() async {
        if fixtures { return }
        do { _ = try await client.signOut(); errorMessage = nil }
        catch { errorMessage = "The local session was removed, but server sign-out could not be confirmed: \(error.localizedDescription)" }
        await client.forgetSession()
        session = SessionState()
        hasSavedSession = false
        clearPrivateData()
    }

    private func clearPrivateData() {
        liveTask?.cancel(); liveTask = nil
        overview = nil; sites = []; dataServices = []; dataFiles = []; dataServicesScannedAt = nil; dataServicesScanError = nil; dataServicesError = nil; history = []; traffic = []
        requests = []; errorEvidence = nil; errorGroups = []; importedNotes = []; importNotice = nil; paths = []; storage = nil; storageBrowse = nil
        storageError = nil; cleanupPreview = nil; cleanupError = nil; cleanupNotice = nil
        projects = []; jobs = []; members = []; license = nil; environment = nil
        nodes = []; selectedNode = ""; selectedSite = ""
        hybridPeers = []; hybridSettings = nil; hybridAdmission = nil; fleetLinks = []; hybridError = nil
        mcpSnapshot = nil
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

    func networkPorts() async throws -> NetworkPorts {
#if DEBUG
        if fixtures { throw APIError.server("Port inventory is unavailable in the sample preview.") }
#endif
        return try await client.networkPorts()
    }

    func changeNode(_ id: String, page: SidebarPage) async {
        selectedNode = id; storage = nil; storageBrowse = nil; cleanupPreview = nil
        await client.select(node: id); await reload(page: page)
    }

    func setLive(_ enabled: Bool, page: SidebarPage) {
        live = enabled
        liveTask?.cancel(); liveTask = nil
        guard enabled else { return }
        liveTask = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                await HWSleep.seconds(page == .topology ? 3 : 8)
                guard let self, !Task.isCancelled else { return }
                if page == .topology {
                    await self.pulseTopology(full: ticks % 10 == 0)
                    ticks += 1
                } else {
                    await self.reload(page: page, quiet: true)
                }
            }
        }
    }

    private func pulseTopology(full: Bool) async {
#if DEBUG
        if fixtures { return }
#endif
        do {
            async let overviewCall = client.overview()
            async let sitesCall = client.sites()
            if full {
                async let sourcesCall = client.sources(site: "", hours: hours)
                async let projectsCall = client.projects()
                let loaded = try await (overviewCall, sitesCall, sourcesCall, projectsCall)
                overview = loaded.0
                sites = loaded.1
                sources = loaded.2
                projects = loaded.3
                await loadDataServices()
            } else {
                let loaded = try await (overviewCall, sitesCall)
                overview = loaded.0
                sites = loaded.1
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload(page: SidebarPage, quiet: Bool = false) async {
#if DEBUG
        if fixtures {
            if overview == nil { installFixtures() }
            return
        }
#endif
        if !quiet { loading = true }; defer { if !quiet { loading = false } }
        do {
            if !quiet || overview == nil || sites.isEmpty {
                async let commonOverview = client.overview()
                async let commonSites = client.sites()
                let common = try await (commonOverview, commonSites)
                overview = common.0
                sites = common.1
            }
            switch page {
            case .overview:
                history = try await client.history(hours: hours)
            case .data:
                await loadDataServices()
            case .traffic:
                async let trafficCall = client.traffic(site: selectedSite, hours: hours)
                async let sourcesCall = client.sources(site: selectedSite, hours: hours)
                if quiet {
                    let loaded = try await (trafficCall, sourcesCall)
                    traffic = loaded.0; sources = loaded.1
                } else {
                    async let requestsCall = client.requests(site: selectedSite)
                    async let errorsCall = client.errors(site: selectedSite, hours: hours)
                    async let pathsCall = client.paths(site: selectedSite, hours: hours)
                    let loaded = try await (trafficCall, sourcesCall, requestsCall, errorsCall, pathsCall)
                    traffic = loaded.0; sources = loaded.1; requests = loaded.2; errorEvidence = loaded.3; paths = loaded.4.paths
                }
            case .incidents, .errors, .topology, .codeHealth:
                if page == .topology {
                    async let projectsCall = client.projects()
                    async let sourcesCall = client.sources(site: "", hours: hours)
                    async let jobsCall = client.jobs()
                    let loaded = try await (projectsCall, sourcesCall, jobsCall)
                    projects = loaded.0
                    sources = loaded.1
                    jobs = loaded.2
                    await loadDataServices()
                } else {
                    if page == .errors {
                        async let projectsCall = client.projects()
                        async let errorsCall = client.errors(site: selectedSite, hours: hours)
                        async let groupsCall = client.errorGroups(site: selectedSite, hours: hours)
                        async let notesCall = client.importedNotes(kind: "", site: selectedSite)
                        let loaded = try await (projectsCall, errorsCall, groupsCall, notesCall)
                        projects = loaded.0
                        errorEvidence = loaded.1
                        errorGroups = loaded.2
                        importedNotes = loaded.3
                    } else {
                        projects = try await client.projects()
                        if page != .codeHealth { jobs = try await client.jobs() }
                    }
                }
            case .fleet:
                await loadFleet()
            case .workloads:
                requests = try await client.requests(site: selectedSite)
            case .cleanup:
                await refreshCleanup()
            case .policies:
                async let guardCall = client.trafficGuard()
                async let rulesCall = client.accessRules(site: selectedSite)
                (guardState, accessRules) = try await (guardCall, rulesCall)
            case .environment:
                if let site = sites.first(where: { $0.id == selectedSite }) ?? sites.first { environment = try await client.environment(site: site.id) }
            case .mcp:
                mcpSnapshot = try await client.mcpSnapshot()
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

    func hasCachedContent(for page: SidebarPage) -> Bool {
        switch page {
        case .overview: return overview != nil
        case .traffic: return !traffic.isEmpty || !requests.isEmpty
        case .errors: return !(errorEvidence?.requests.isEmpty ?? true) || !errorGroups.isEmpty
        case .data: return !dataServices.isEmpty || !dataFiles.isEmpty || dataServicesError != nil
        case .workloads: return !sites.isEmpty
        case .topology: return !sites.isEmpty || !projects.isEmpty
        case .mcp: return mcpSnapshot != nil
        default: return true
        }
    }

    func saveMCPGovernance(_ value: MCPGovernance) async {
#if DEBUG
        if fixtures {
            mcpSnapshot = MCPSnapshot(governance: value, clients: mcpSnapshot?.clients ?? Fixtures.mcp.clients, history: mcpSnapshot?.history ?? Fixtures.mcp.history, knownTools: mcpSnapshot?.knownTools ?? Fixtures.mcp.knownTools)
            return
        }
#endif
        do {
            let updated = try await client.updateMCPGovernance(value)
            if var snap = mcpSnapshot { snap = MCPSnapshot(governance: updated, clients: snap.clients, history: snap.history, knownTools: snap.knownTools); mcpSnapshot = snap }
            else { mcpSnapshot = try await client.mcpSnapshot() }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func dataTables(path: String) async throws -> DataTablesResponse {
#if DEBUG
        if fixtures { return Fixtures.tables(for: path) }
#endif
        return try await client.dataTables(path: path)
    }

    func dataRows(path: String, table: String, limit: Int = 25, offset: Int = 0) async throws -> DataRowsResponse {
#if DEBUG
        if fixtures { return Fixtures.rows(path: path, table: table, limit: limit, offset: offset) }
#endif
        return try await client.dataRows(path: path, table: table, limit: limit, offset: offset)
    }

    private func loadDataServices() async {
        do {
            let inventory = try await client.dataServices()
            dataServices = inventory.services
            dataFiles = inventory.files
            dataServicesScannedAt = inventory.scannedAt
            dataServicesScanError = inventory.scanError
            dataServicesError = nil
        } catch {
            dataServices = []
            dataFiles = []
            dataServicesScannedAt = nil
            dataServicesScanError = nil
            dataServicesError = error.localizedDescription
        }
    }

    func scanStorage(refresh: Bool = false) async {
#if DEBUG
        if fixtures { storage = Fixtures.storage; storageError = nil; return }
#endif
        guard !storageLoading else { return }
        storageLoading = true; storageError = nil
        defer { storageLoading = false }
        do {
            storage = try await client.storage(refresh: refresh)
            storageBrowse = nil
        } catch { storageError = error.localizedDescription }
    }

    func browseStorage(path: String) async {
#if DEBUG
        if fixtures {
            storageBrowse = StorageResponse(mode: "browse", scannedAt: Fixtures.storage.scannedAt, root: "/", path: path, parent: path == "/" ? nil : "/", disk: Fixtures.storage.disk, totalBytes: Fixtures.storage.totalBytes, analyzedBytes: Fixtures.storage.analyzedBytes, unattributedBytes: 0, sites: Fixtures.storage.sites, categories: Fixtures.storage.categories, areas: Fixtures.storage.entries.filter { $0.path.hasPrefix(path) }, entries: Fixtures.storage.entries.filter { $0.path.hasPrefix(path) })
            return
        }
#endif
        storageLoading = true; storageError = nil
        defer { storageLoading = false }
        do { storageBrowse = try await client.storage(path: path) } catch { storageError = error.localizedDescription }
    }

    func refreshCleanup() async {
#if DEBUG
        if fixtures { cleanupPreview = Fixtures.cleanupPreview; cleanupError = nil; return }
#endif
        guard !cleanupLoading else { return }
        cleanupLoading = true; cleanupError = nil
        defer { cleanupLoading = false }
        do { cleanupPreview = try await client.cleanupPreview() }
        catch { cleanupError = error.localizedDescription }
    }

    func cleanCache(_ kind: String) async {
        guard !fixtures, ["platform_owner", "owner", "admin"].contains(session.role ?? "") else { return }
        cleanupLoading = true; cleanupError = nil; cleanupNotice = nil
        defer { cleanupLoading = false }
        do {
            let result = try await client.cleanCache(kind)
            let count = result.results.reduce(0) { $0 + $1.deletedItems }
            cleanupNotice = "Removed \(count) eligible cache files or records. Actual freed space depends on shared Docker layers."
            if let errors = result.errors, !errors.isEmpty {
                cleanupError = errors.map { "\($0.key): \($0.value)" }.sorted().joined(separator: " · ")
            }
            cleanupPreview = try await client.cleanupPreview()
        } catch { cleanupError = error.localizedDescription }
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

    func createEnvironmentShare(names: [String], minutes: Int) async throws -> URL {
        guard let site = sites.first(where: { $0.id == selectedSite }) ?? sites.first else { throw APIError.invalidResponse }
        guard ["owner", "platform_owner"].contains(session.role ?? "") else { throw APIError.server("Owner access is required.") }
        return try await client.createEnvironmentShare(site: site.id, names: names, minutes: minutes)
    }

    func environmentShares() async throws -> [EnvironmentShareRecord] { try await client.environmentShares() }
    func revokeEnvironmentShare(_ id: String) async throws { try await client.revokeEnvironmentShare(id) }

    func removeRule(_ rule: AccessRule) async {
        if fixtures { accessRules = .init(rules: accessRules.rules.filter { $0.id != rule.id }, managed: true, updatedAt: accessRules.updatedAt, error: nil); return }
        do { accessRules = try await client.removeAccessRule(id: rule.id) } catch { errorMessage = error.localizedDescription }
    }

    func saveHybridSettings(_ settings: HybridSettings) async {
        if fixtures { hybridSettings = settings; return }
        do { hybridSettings = try await client.updateHybridSettings(settings); hybridError = nil }
        catch { hybridError = error.localizedDescription; errorMessage = error.localizedDescription }
    }

    private func loadFleet() async {
        do {
            async let peersCall = client.hybridPeers()
            async let settingsCall = client.hybridSettings()
            async let admissionCall = client.hybridAdmission()
            async let linksCall = client.fleetLinks()
            let loaded = try await (peersCall, settingsCall, admissionCall, linksCall)
            hybridPeers = loaded.0
            hybridSettings = loaded.1
            hybridAdmission = loaded.2
            fleetLinks = loaded.3
            hybridError = nil
        } catch {
            hybridPeers = []
            hybridSettings = nil
            hybridAdmission = nil
            fleetLinks = []
            hybridError = error.localizedDescription
        }
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

    func errorContext(for request: RequestSample) async -> ErrorContext {
#if DEBUG
        if fixtures { return Fixtures.errorContext(for: request) }
#endif
        do { return try await client.errorContext(id: request.id) }
        catch { return localErrorContext(for: request, error: error.localizedDescription) }
    }

    func importMarkdown(kind: String, project: String, markdown: String) async {
#if DEBUG
        if fixtures {
            let parsed = MarkdownNotes.parse(kind: kind, project: project, markdown: markdown)
            importedNotes.append(contentsOf: parsed)
            importNotice = "Imported \(parsed.count) \(kind) notes from Markdown."
            return
        }
#endif
        do {
            let result = try await client.importMarkdown(kind: kind, site: project, markdown: markdown)
            importedNotes.append(contentsOf: result.added)
            importNotice = "Imported \(result.added.count), skipped \(result.skipped)."
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func exportMarkdown(kind: String) async -> String? {
#if DEBUG
        if fixtures { return MarkdownNotes.export(kind: kind, projects: projects, groups: groupedErrors()) }
#endif
        do { return try await client.exportMarkdown(kind: kind, site: selectedSite).markdown }
        catch { errorMessage = error.localizedDescription; return nil }
    }

    func refreshErrors() async {
#if DEBUG
        if fixtures { return }
#endif
        do {
            async let errorsCall = client.errors(site: selectedSite, hours: hours)
            async let groupsCall = client.errorGroups(site: selectedSite, hours: hours)
            async let notesCall = client.importedNotes(kind: "", site: selectedSite)
            let loaded = try await (errorsCall, groupsCall, notesCall)
            errorEvidence = loaded.0; errorGroups = loaded.1; importedNotes = loaded.2
        } catch { errorMessage = error.localizedDescription }
    }

    func groupedErrors() -> [ErrorProjectGroup] {
        if !errorGroups.isEmpty { return errorGroups }
        let rows = errorEvidence?.requests.filter { $0.status >= 400 } ?? []
        let names = Dictionary(uniqueKeysWithValues: sites.map { ($0.id, $0.name) })
        return Dictionary(grouping: rows, by: { $0.site.isEmpty ? "unmapped" : $0.site }).map { id, items in
            ErrorProjectGroup(projectId: id, projectName: names[id] ?? (id == "unmapped" ? "Unmapped traffic" : id),
                              count: items.count, lastTime: items.map(\.time).max(),
                              statuses: Dictionary(grouping: items, by: { String($0.status) }).mapValues(\.count),
                              requests: items)
        }.sorted { $0.count > $1.count }
    }

    private func localErrorContext(for request: RequestSample, error: String) -> ErrorContext {
        let project = sites.first { $0.id == request.site }
        let previous = (errorEvidence?.requests ?? []).filter {
            $0.id != request.id && $0.path == request.path && $0.host == request.host && $0.status >= 400 && $0.time < request.time
        }
        return ErrorContext(request: request, projectId: request.site.isEmpty ? "unmapped" : request.site,
                            projectName: project?.name ?? (request.site.isEmpty ? "Unmapped traffic" : request.site),
                            previous: previous, logs: [], logSource: nil, logError: error, crashHint: nil)
    }
}
