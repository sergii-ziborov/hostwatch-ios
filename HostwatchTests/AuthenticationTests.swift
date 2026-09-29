import Foundation
import XCTest
@testable import Hostwatch

final class AuthenticationTests: XCTestCase {
    private let origin = URL(string: "https://auth-tests.example.invalid")!
    private let sessionStorage = MemorySessionStorage()

    override func tearDown() {
        AuthenticationProtocol.handler = nil
        for cookie in HTTPCookieStorage.shared.cookies(for: origin) ?? [] {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        super.tearDown()
    }

    private func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthenticationProtocol.self]
        configuration.httpCookieStorage = .shared
        return APIClient(baseURL: origin, configuration: configuration, sessionStorage: sessionStorage)
    }

    func testExpiredDeviceAuthorizationDoesNotPreventPasswordRetry() async throws {
        let client = client()
        sessionStorage.save(StoredSession(baseURL: origin.absoluteString, csrf: "old-csrf", cookies: [
            StoredCookie(name: "hostwatch_device", value: "revoked-device", domain: origin.host!, path: "/",
                         expires: Date().addingTimeInterval(3_600), secure: true, httpOnly: true, sameSite: "strict")
        ], snapshot: SessionState(authenticated: true), savedAt: Date()))
        _ = await client.applySavedSession()
        AuthenticationProtocol.handler = { [origin] request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/session"):
                return (200, [:], #"{"authenticated":false}"#)
            case ("POST", "/api/session/refresh"):
                return (401, [:], #"{"error":"Device sign-in expired or was revoked. Sign in again."}"#)
            case ("POST", "/api/session"):
                XCTAssertNil(request.value(forHTTPHeaderField: "X-Hostwatch-CSRF"))
                XCTAssertFalse((request.value(forHTTPHeaderField: "Cookie") ?? "").contains("revoked-device"))
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Hostwatch-Client"), "ios")
                return (200, ["Set-Cookie": "hostwatch_session=fresh-session; Path=/; Secure; Max-Age=28800, hostwatch_device=new-device; Path=/; HttpOnly; Secure; Max-Age=7776000"],
                        #"{"authenticated":true,"csrf":"fresh-csrf"}"#)
            case ("GET", "/api/control/nodes"):
                XCTAssertTrue((HTTPCookieStorage.shared.cookies(for: origin) ?? []).contains { $0.name == "hostwatch_session" && $0.value == "fresh-session" })
                return (200, [:], "[]")
            default:
                XCTFail("Unexpected authentication request: \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                return (500, [:], #"{"error":"Unexpected request"}"#)
            }
        }

        do {
            _ = try await client.sessionState()
            XCTFail("The revoked device credential must be rejected")
        } catch APIError.unauthorized {
            // This rejection must not block a new password sign-in.
        }
        let result = try await client.signIn(email: "owner@example.invalid", password: "current-password")
        XCTAssertTrue(result.authenticated)
        _ = try await client.nodes()
        let saved = try XCTUnwrap(sessionStorage.load())
        XCTAssertEqual(saved.csrf, "fresh-csrf")
        XCTAssertTrue(saved.cookies.contains { $0.name == "hostwatch_device" && $0.value == "new-device" })
        XCTAssertFalse(saved.cookies.contains { $0.value == "revoked-device" })
    }

    func testWrongPasswordShowsPasswordErrorInsteadOfExpiredSession() async throws {
        AuthenticationProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/session")
            XCTAssertEqual(request.httpMethod, "POST")
            return (401, [:], #"{"success":false,"error":"Invalid email or password"}"#)
        }
        do {
            _ = try await client().signIn(email: "owner@example.invalid", password: "wrong-password")
            XCTFail("A rejected password must fail")
        } catch APIError.server(let message) {
            XCTAssertEqual(message, "Invalid email or password")
        }
    }

    func testWrongSecondFactorKeepsChallengeAndShowsCodeError() async throws {
        let client = client()
        AuthenticationProtocol.handler = { [origin] request in
            if request.url?.path == "/api/session" {
                return (202, ["Set-Cookie": "hostwatch_challenge=challenge; Path=/; Secure; Max-Age=300"],
                        #"{"authenticated":false,"requiresOtp":true}"#)
            }
            XCTAssertEqual(request.url?.path, "/api/session/totp")
            XCTAssertTrue((HTTPCookieStorage.shared.cookies(for: origin) ?? []).contains { $0.name == "hostwatch_challenge" && $0.value == "challenge" })
            return (401, [:], #"{"error":"Invalid verification code"}"#)
        }
        let challenge = try await client.signIn(email: "owner@example.invalid", password: "current-password")
        XCTAssertEqual(challenge.requiresOtp, true)
        do {
            _ = try await client.verify(otp: "000000")
            XCTFail("A rejected code must fail")
        } catch APIError.server(let message) {
            XCTAssertEqual(message, "Invalid verification code")
        }
        XCTAssertTrue((HTTPCookieStorage.shared.cookies(for: origin) ?? []).contains { $0.name == "hostwatch_challenge" })
    }

    func testBackgroundPersistenceCannotRestorePreRenewalCSRF() async throws {
        let client = client()
        AuthenticationProtocol.handler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/session"):
                return (200, [:], #"{"authenticated":true,"csrf":"old-csrf"}"#)
            case ("GET", "/api/session"):
                return (200, [:], #"{"authenticated":false}"#)
            case ("POST", "/api/session/refresh"):
                return (200, [:], #"{"authenticated":true,"csrf":"renewed-csrf"}"#)
            case ("POST", "/api/control/users"):
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Hostwatch-CSRF"), "renewed-csrf")
                return (200, [:], #"{"success":true}"#)
            default:
                XCTFail("Unexpected authentication request")
                return (500, [:], #"{"error":"Unexpected request"}"#)
            }
        }
        let oldSnapshot = try await client.signIn(email: "owner@example.invalid", password: "current-password")
        let renewed = try await client.sessionState()
        XCTAssertEqual(renewed.csrf, "renewed-csrf")
        await client.persistAuthenticated(oldSnapshot)
        XCTAssertEqual(sessionStorage.load()?.csrf, "renewed-csrf")
        XCTAssertEqual(sessionStorage.load()?.snapshot.csrf, "renewed-csrf")
        try await client.createUser(name: "Test", email: "test@example.invalid", password: "temporary-password", role: "viewer")
    }

    func testRateLimitMessageIsPreserved() async throws {
        AuthenticationProtocol.handler = { _ in
            (429, [:], #"{"error":"Too many sign-in attempts. Try again in 15 minutes."}"#)
        }
        do {
            _ = try await client().signIn(email: "owner@example.invalid", password: "wrong-password")
            XCTFail("A rate-limited sign-in must fail")
        } catch APIError.server(let message) {
            XCTAssertEqual(message, "Too many sign-in attempts. Try again in 15 minutes.")
        }
    }

    func testLiveControllerSignInWhenExplicitlyConfigured() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["HOSTWATCH_TEST_ORIGIN"], let origin = URL(string: address),
              let email = environment["HOSTWATCH_TEST_EMAIL"], let password = environment["HOSTWATCH_TEST_PASSWORD"] else {
            throw XCTSkip("Live sign-in requires explicit test origin and credentials; never use committed credentials.")
        }
        let client = APIClient(baseURL: origin, configuration: .ephemeral, sessionStorage: sessionStorage)
        do {
            let signedIn = try await client.signIn(email: email, password: password)
            XCTAssertTrue(signedIn.authenticated)
            let restored = try await client.sessionState()
            XCTAssertTrue(restored.authenticated)
            _ = try await client.nodes()
            XCTAssertTrue(sessionStorage.load()?.cookies.contains { $0.name == "hostwatch_device" } == true)
            _ = try await client.signOut()
            await client.forgetSession()
        } catch {
            _ = try? await client.signOut()
            await client.forgetSession()
            throw error
        }
    }
}

private final class MemorySessionStorage: SessionStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var value: StoredSession?
    func save(_ value: StoredSession) { lock.lock(); defer { lock.unlock() }; self.value = value }
    func load() -> StoredSession? { lock.lock(); defer { lock.unlock() }; return value }
    func delete() { lock.lock(); defer { lock.unlock() }; value = nil }
}

private final class AuthenticationProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (Int, [String: String], String)
    private static let lock = NSLock()
    private static var storedHandler: Handler?
    static var handler: Handler? {
        get { lock.lock(); defer { lock.unlock() }; return storedHandler }
        set { lock.lock(); defer { lock.unlock() }; storedHandler = newValue }
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "auth-tests.example.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (status, headers, body) = try handler(request)
            let response = try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
