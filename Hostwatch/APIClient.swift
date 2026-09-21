import Foundation
import UIKit
import CryptoKit

enum APIError: LocalizedError {
    case invalidURL
    case server(String)
    case invalidResponse
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The control-plane URL is invalid."
        case .server(let message): message
        case .invalidResponse: "The server returned an invalid response."
        case .unauthorized: "The saved session is no longer valid. Sign in again."
        }
    }
}

actor APIClient {
    private var baseURL: URL
    private var csrf = ""
    private var selectedNode = ""
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 90
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        session = URLSession(configuration: configuration)
    }

    func configure(baseURL: URL) { self.baseURL = baseURL }
    func select(node: String) { selectedNode = node }

    private func call<T: Decodable>(_ path: String, method: String = "GET", body: Encodable? = nil) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        // A cold disk scan or Docker prune may take close to the controller's 75-second limit.
        // Session restore must fail quickly instead of trapping a disconnected user on the splash.
        request.timeoutInterval = path.hasPrefix("/api/v1/storage") || path.hasPrefix("/api/v1/cleanup") ? 85 :
            (path == "/api/session" && method == "GET" ? 12 : 25)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Hostwatch iOS/1.0", forHTTPHeaderField: "User-Agent")
        if (path.hasPrefix("/api/v1/") || path.hasPrefix("/api/v2/")), !selectedNode.isEmpty { request.setValue(selectedNode, forHTTPHeaderField: "X-Hostwatch-Node") }
        if !csrf.isEmpty, !["GET", "HEAD"].contains(method) { request.setValue(csrf, forHTTPHeaderField: "X-Hostwatch-CSRF") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw APIError.unauthorized }
            let server = try? decoder.decode(ServerError.self, from: data)
            throw APIError.server(server?.error ?? "Request failed (HTTP \(http.statusCode)).")
        }
        return try decoder.decode(T.self, from: data)
    }

    private func empty(_ path: String, method: String, body: Encodable? = nil) async throws {
        let _: EmptyResponse = try await call(path, method: method, body: body)
    }

    func sessionState() async throws -> SessionState {
        let value: SessionState = try await call("/api/session")
        csrf = value.csrf ?? ""
        if value.authenticated { persistAuthenticated(value) }
        return value
    }

    func signIn(email: String, password: String) async throws -> SessionState {
        let value: SessionState = try await call("/api/session", method: "POST", body: Credentials(email: email, password: password))
        csrf = value.csrf ?? ""
        if value.authenticated { persistAuthenticated(value) }
        return value
    }

    func verify(otp: String) async throws -> SessionState {
        let value: SessionState = try await call("/api/session/totp", method: "POST", body: OTP(otp: otp))
        csrf = value.csrf ?? ""
        if value.authenticated { persistAuthenticated(value) }
        return value
    }

    func startQR(kind: String) async throws -> QRStart { try await call("/api/session/qr", method: "POST", body: QRKind(kind: kind)) }
    func redeemQR(_ ticket: QRStart) async throws -> SessionState {
        let value: SessionState = try await call("/api/session/qr/\(ticket.id)/redeem", method: "POST", body: QRSecret(secret: ticket.secret))
        if value.authenticated {
            csrf = value.csrf ?? ""
            persistAuthenticated(value)
        }
        return value
    }
    func claimDeviceQR(_ ticket: DeviceQRTicket, proof: String) async throws -> QRApproval {
        try await call("/api/session/qr/\(ticket.id)/claim", method: "POST", body: DeviceQRClaim(secret: ticket.secret, proof: proof, device: UIDevice.current.model))
    }
    func redeemDeviceQR(_ ticket: DeviceQRTicket, proof: String) async throws -> SessionState {
        let value: SessionState = try await call("/api/session/qr/\(ticket.id)/redeem", method: "POST", body: DeviceQRProof(secret: ticket.secret, proof: proof))
        if value.authenticated {
            csrf = value.csrf ?? ""
            persistAuthenticated(value)
        }
        return value
    }
    func inspectQR(_ value: String) async throws -> QRApproval {
        var parts = URLComponents(); parts.queryItems = [.init(name: "value", value: value)]
        return try await call("/api/session/qr/inspect?\(parts.percentEncodedQuery ?? "")")
    }
    func pendingQRApprovals() async throws -> [QRApproval] { try await call("/api/session/qr/approvals") }
    func approveQR(_ ticket: QRApproval, approve: Bool) async throws {
        try await empty("/api/session/qr/\(ticket.id)/\(approve ? "approve" : "reject")", method: "POST", body: QRVerification(verificationCode: ticket.verificationCode))
    }
    func beginTOTP(currentPassword: String) async throws -> TOTPSetup {
        try await call("/api/control/security/totp/setup", method: "POST", body: CurrentPassword(currentPassword: currentPassword))
    }
    func confirmTOTP(otp: String) async throws {
        try await empty("/api/control/security/totp/confirm", method: "POST", body: OTP(otp: otp))
    }
    func disableTOTP(currentPassword: String, otp: String) async throws {
        try await empty("/api/control/security/totp/disable", method: "POST", body: DisableTOTP(currentPassword: currentPassword, otp: otp))
    }

    func signOut() async throws -> SessionState {
        let value: SessionState = try await call("/api/session", method: "DELETE")
        csrf = ""
        return value
    }

    func forgetSession() {
        csrf = ""; selectedNode = ""
        let storage = HTTPCookieStorage.shared
        for cookie in storage.cookies(for: baseURL) ?? [] { storage.deleteCookie(cookie) }
        SessionVault.delete()
    }

    func hasSavedSession() -> Bool {
        SessionVault.load()?.snapshot.authenticated == true
    }

    func cachedSnapshot() -> SessionState? {
        let stored = SessionVault.load()
        return stored?.snapshot.authenticated == true ? stored?.snapshot : nil
    }

    func persistAuthenticated(_ state: SessionState) {
        guard state.authenticated else { return }
        csrf = state.csrf ?? csrf
        SessionVault.save(StoredSession(
            baseURL: baseURL.absoluteString,
            csrf: csrf,
            cookies: StoredCookie.snapshot(from: .shared, url: baseURL),
            snapshot: state,
            savedAt: Date()
        ))
    }

    func applySavedSession() -> SessionState? {
        guard let stored = SessionVault.load(), stored.snapshot.authenticated else { return nil }
        if let url = URL(string: stored.baseURL) { baseURL = url }
        csrf = stored.csrf
        StoredCookie.apply(stored.cookies, to: .shared)
        return stored.snapshot
    }

    func currentBaseURL() -> String { baseURL.absoluteString }

    func nodes() async throws -> [ManagedNode] { try await call("/api/control/nodes") }
    func overview() async throws -> Overview { try await call("/api/v1/overview") }
    func networkPorts() async throws -> NetworkPorts { try await call("/api/v1/network-ports") }
    func sites() async throws -> [Site] { try await call("/api/v1/sites") }
    func dataServices() async throws -> DataServicesResponse { try await call("/api/v1/data-services") }
    func dataTables(path: String) async throws -> DataTablesResponse {
        try await call("/api/v1/data-tables?\(queryItems(["path": path]))")
    }
    func dataRows(path: String, table: String, limit: Int = 25, offset: Int = 0) async throws -> DataRowsResponse {
        try await call("/api/v1/data-rows?\(queryItems(["path": path, "table": table, "limit": String(limit), "offset": String(offset)]))")
    }
    func history(hours: Int) async throws -> [SystemPoint] { try await call("/api/v1/system-history?hours=\(hours)") }
    func traffic(site: String, hours: Int) async throws -> [TrafficPoint] { try await call("/api/v1/traffic?\(scope(site: site, hours: hours))") }
    func sources(site: String, hours: Int) async throws -> Sources { try await call("/api/v1/sources?\(scope(site: site, hours: hours))") }
    func requests(site: String) async throws -> [RequestSample] {
        let query = site.isEmpty ? "" : "?site=\(site.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? site)"
        return try await call("/api/v1/requests\(query)")
    }
    func errors(site: String, hours: Int) async throws -> ErrorEvidence { try await call("/api/v1/error-requests?\(scope(site: site, hours: hours))") }
    func errorGroups(site: String, hours: Int) async throws -> [ErrorProjectGroup] { try await call("/api/v1/errors?\(scope(site: site, hours: hours))") }
    func errorContext(id: String) async throws -> ErrorContext {
        try await call("/api/v1/errors/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)")
    }
    func importedNotes(kind: String, site: String) async throws -> [ImportedNote] {
        try await call("/api/v1/imports?\(queryItems(["kind": kind, "site": site]))")
    }
    func importMarkdown(kind: String, site: String, markdown: String) async throws -> ImportResult {
        try await call("/api/v1/imports", method: "POST", body: MarkdownImport(kind: kind, site: site, markdown: markdown))
    }
    func exportMarkdown(kind: String, site: String) async throws -> MarkdownExport {
        try await call("/api/v1/export.md?\(queryItems(["kind": kind, "site": site]))")
    }
    func paths(site: String, hours: Int) async throws -> RequestPaths { try await call("/api/v1/paths?\(scope(site: site, hours: hours))") }
    func storage(path: String? = nil, refresh: Bool = false) async throws -> StorageResponse {
        var items: [URLQueryItem] = []
        if let path { items.append(.init(name: "path", value: path)) }
        if refresh { items.append(.init(name: "refresh", value: "1")) }
        var components = URLComponents(); components.queryItems = items
        return try await call("/api/v1/storage\(components.percentEncodedQuery.map { "?\($0)" } ?? "")")
    }
    func cleanupPreview() async throws -> CleanupPreview { try await call("/api/v1/cleanup") }
    func cleanCache(_ kind: String) async throws -> CleanupRun {
        guard ["docker-build-cache", "apt-archives", "man-cache", "all"].contains(kind) else { throw APIError.invalidResponse }
        return try await call("/api/v1/cleanup/\(kind)", method: "DELETE")
    }
    func projects() async throws -> [ProjectHealth] { try await call("/api/v1/projects") }
    func jobs() async throws -> [JobState] { try await call("/api/v1/jobs") }
    func license() async throws -> LicenseStatus { try await call("/api/control/license") }
    func members() async throws -> [Member] { try await call("/api/control/members") }
    func createUser(name: String, email: String, password: String, role: String) async throws {
        try await empty("/api/control/users", method: "POST", body: NewUser(name: name, email: email, password: password, role: role))
    }
    func installLicense(_ value: String) async throws -> LicenseStatus { try await call("/api/control/license", method: "PUT", body: LicenseValue(license: value)) }
    func environment(site: String) async throws -> EnvironmentState { try await call("/api/v1/sites/\(site)/environment") }
    func createEnvironmentShare(site: String, names: [String], minutes: Int, allowedCIDRs: [String]) async throws -> URL {
        let exported: EnvironmentExport = try await call("/api/v1/sites/\(site)/environment/export", method: "POST", body: EnvironmentExportScope(names: names))
        let key = SymmetricKey(size: .bits256)
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(Data(exported.dotenv.utf8), using: key, nonce: nonce)
        let keyBytes = key.withUnsafeBytes { Data($0) }
        let payload = EnvironmentSharePayload(siteId: site, names: names, iv: Data(nonce).base64URL, ciphertext: (sealed.ciphertext + sealed.tag).base64URL, minutes: minutes, allowedCidrs: allowedCIDRs)
        let created: CreatedEnvironmentShare = try await call("/api/control/environment-shares", method: "POST", body: payload)
        guard let link = URL(string: "/share/env/\(created.id)#k=\(keyBytes.base64URL)", relativeTo: baseURL)?.absoluteURL else { throw APIError.invalidURL }
        return link
    }
    func environmentShares() async throws -> [EnvironmentShareRecord] { try await call("/api/control/environment-shares") }
    func revokeEnvironmentShare(_ id: String) async throws { try await empty("/api/control/environment-shares/\(id)", method: "DELETE") }
    func setEnvironment(site: String, name: String, value: String) async throws -> EnvironmentState { try await call("/api/v1/sites/\(site)/environment/\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)", method: "PUT", body: EnvironmentValue(value: value)) }
    func deleteEnvironment(site: String, name: String) async throws -> EnvironmentState { try await call("/api/v1/sites/\(site)/environment/\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)", method: "DELETE") }
    func vaultSecrets(site: String) async throws -> [VaultSecret] { try await call("/api/v1/vault/secrets?site=\(site)") }
    func vaultGrants(site: String) async throws -> [VaultGrant] { try await call("/api/v1/vault/grants?site=\(site)") }
    func vaultEvents(site: String) async throws -> [VaultEvent] { try await call("/api/v1/vault/events?site=\(site)") }
    func putVaultSecret(site: String, name: String, value: String, description: String, expiresAt: String) async throws -> VaultSecret {
        try await call("/api/v1/vault/secrets/\(site)/\(name)", method: "PUT", body: VaultSecretPayload(value: value, description: description, expiresAt: expiresAt))
    }
    func deleteVaultSecret(site: String, name: String) async throws { try await empty("/api/v1/vault/secrets/\(site)/\(name)", method: "DELETE") }
    func applyVaultSecret(site: String, name: String) async throws -> EnvironmentState { try await call("/api/v1/vault/secrets/\(site)/\(name)/apply", method: "POST") }
    func createVaultGrant(site: String, label: String, names: [String], minutes: Int, allowedCidrs: [String], maxReads: Int) async throws -> VaultGrantCreated {
        try await call("/api/v1/vault/grants", method: "POST", body: VaultGrantPayload(site: site, label: label, names: names, minutes: minutes, allowedCidrs: allowedCidrs, maxReads: maxReads))
    }
    func revokeVaultGrant(_ id: String) async throws { try await empty("/api/v1/vault/grants/\(id)", method: "DELETE") }
    func accessRules(site: String) async throws -> AccessRuleState {
        let value = site.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? site
        return try await call("/api/v1/access-rules?site=\(value)")
    }
    func removeAccessRule(id: String) async throws -> AccessRuleState { try await call("/api/v1/access-rules/\(id)", method: "DELETE") }
    func trafficGuard() async throws -> TrafficGuardState { try await call("/api/v1/traffic-guard") }
    func updateTrafficGuard(_ policy: TrafficGuardPolicy) async throws -> TrafficGuardState { try await call("/api/v1/traffic-guard", method: "PUT", body: policy) }

    func siteAction(_ id: String, action: String) async throws {
        try await empty("/api/v1/sites/\(id)/\(action)", method: "POST")
    }
    func addAccessRule(site: String, kind: String, value: String, label: String) async throws {
        try await empty("/api/v1/access-rules", method: "POST", body: Rule(site: site, kind: kind, value: value, label: label))
    }
    func runJob(_ id: String) async throws { try await empty("/api/v1/jobs/\(id)/run", method: "POST") }
    func hybridPeers() async throws -> [HybridPeer] { try await call("/api/v2/peers") }
    func hybridSettings() async throws -> HybridSettings { try await call("/api/v2/settings") }
    func updateHybridSettings(_ settings: HybridSettings) async throws -> HybridSettings { try await call("/api/v2/settings", method: "PUT", body: settings) }
    func hybridAdmission() async throws -> HybridAdmission { try await call("/api/v2/admission") }
    func fleetLinks() async throws -> [FleetLink] { try await call("/api/v2/links") }
    func mcpSnapshot() async throws -> MCPSnapshot { try await call("/api/v1/mcp") }
    func updateMCPGovernance(_ value: MCPGovernance) async throws -> MCPGovernance {
        try await call("/api/v1/mcp/governance", method: "PUT", body: value)
    }

    private func scope(site: String, hours: Int) -> String {
        var components = URLComponents()
        components.queryItems = [.init(name: "hours", value: String(hours))]
        if !site.isEmpty { components.queryItems?.append(.init(name: "site", value: site)) }
        return components.percentEncodedQuery ?? "hours=\(hours)"
    }

    private func queryItems(_ values: [String: String]) -> String {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery ?? ""
    }
}

private struct Credentials: Encodable { let email: String; let password: String }
private struct OTP: Encodable { let otp: String }
private struct QRKind: Encodable { let kind: String }
private struct QRSecret: Encodable { let secret: String }
private struct DeviceQRClaim: Encodable { let secret: String; let proof: String; let device: String }
private struct DeviceQRProof: Encodable { let secret: String; let proof: String }
private struct QRVerification: Encodable { let verificationCode: String }
private struct CurrentPassword: Encodable { let currentPassword: String }
private struct DisableTOTP: Encodable { let currentPassword: String; let otp: String }
private struct Rule: Encodable { let site: String; let kind: String; let value: String; let label: String }
private struct EnvironmentValue: Encodable { let value: String }
private struct VaultSecretPayload: Encodable { let value: String; let description: String; let expiresAt: String }
private struct VaultGrantPayload: Encodable { let site: String; let label: String; let names: [String]; let minutes: Int; let allowedCidrs: [String]; let maxReads: Int }
private struct EnvironmentExportScope: Encodable { let names: [String] }
private struct EnvironmentExport: Decodable { let dotenv: String }
private struct EnvironmentSharePayload: Encodable { let siteId: String; let names: [String]; let iv: String; let ciphertext: String; let minutes: Int; let allowedCidrs: [String] }
private struct CreatedEnvironmentShare: Decodable { let id: String }
private struct NewUser: Encodable { let name: String; let email: String; let password: String; let role: String }
private struct LicenseValue: Encodable { let license: String }
private struct MarkdownImport: Encodable { let kind: String; let site: String; let markdown: String }
private struct ServerError: Decodable { let error: String? }
private struct EmptyResponse: Decodable {}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void
    init(_ value: Encodable) { encodeValue = value.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}

private extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
