import Foundation
import Security

struct StoredCookie: Codable, Equatable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: Date?
    var secure: Bool
    var httpOnly: Bool
    var sameSite: String?

    static func snapshot(from storage: HTTPCookieStorage, url: URL) -> [StoredCookie] {
        (storage.cookies(for: url) ?? []).map { cookie in
            StoredCookie(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path,
                expires: cookie.expiresDate,
                secure: cookie.isSecure,
                httpOnly: cookie.isHTTPOnly,
                sameSite: cookie.sameSitePolicy?.rawValue
            )
        }
    }

    static func apply(_ cookies: [StoredCookie], to storage: HTTPCookieStorage) {
        for cookie in cookies {
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name,
                .value: cookie.value,
                .domain: cookie.domain,
                .path: cookie.path,
                .secure: cookie.secure ? "TRUE" : "FALSE"
            ]
            if cookie.httpOnly { props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            props[.expires] = cookie.expires ?? Date().addingTimeInterval(60 * 60 * 24 * 30)
            if let sameSite = cookie.sameSite { props[.sameSitePolicy] = sameSite }
            if let restored = HTTPCookie(properties: props) { storage.setCookie(restored) }
        }
    }
}

struct StoredSession: Codable {
    var baseURL: String
    var csrf: String
    var cookies: [StoredCookie]
    var snapshot: SessionState
    var savedAt: Date
}

enum SessionVault {
    private static let service = "com.hostwatch.controlplane.session"
    private static let account = "session-v1"

    static var exists: Bool { load() != nil }

    static func save(_ value: StoredSession) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> StoredSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
