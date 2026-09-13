import XCTest
@testable import Hostwatch

final class HostwatchTests: XCTestCase {
    func testByteFormattingUsesBinaryUnits() {
        XCTAssertEqual(Format.bytes(1_073_741_824), "1.0 GB")
        XCTAssertEqual(Format.bytes(1024), "1.0 KB")
    }

    func testEveryMenuItemHasUniqueProductName() {
        XCTAssertEqual(Set(SidebarPage.allCases.map(\.title)).count, SidebarPage.allCases.count)
        XCTAssertFalse(SidebarPage.allCases.map(\.title).contains("Weavatrix"))
        XCTAssertFalse(SidebarPage.allCases.map(\.title).contains("Repo Lens"))
    }

    func testInternalServiceAddressCannotBeBlockedFromRequestInspector() {
        XCTAssertTrue(IPAddressSafety.isInternal("172.21.0.3"))
        XCTAssertTrue(IPAddressSafety.isInternal("10.0.0.8"))
        XCTAssertTrue(IPAddressSafety.isInternal("::1"))
        XCTAssertFalse(IPAddressSafety.isInternal("203.0.113.10"))
    }

    func testPairingQRIsBoundToTheConfiguredController() {
        let id = "ABCDEFGHIJKLMNOPQRSTUVWX"
        let value = QRPayload.url(server: "https://control.example.com", id: id)?.absoluteString
        XCTAssertEqual(value, "https://control.example.com/#approve=\(id)")
        XCTAssertEqual(QRPayload.id(from: value ?? "", server: "https://control.example.com"), id)
        XCTAssertNil(QRPayload.id(from: value ?? "", server: "https://different.example.com"))
        XCTAssertNil(QRPayload.id(from: "https://control.example.com/#approve=bad", server: "https://control.example.com"))
    }

    func testWebsiteDeviceSignInQRContainsOnlyExpectedOriginAndTicket() {
        let id = "ABCDEFGHIJKLMNOPQRSTUVWX"
        let secret = String(repeating: "a", count: 43)
        let value = "https://gethostwatch.com/#device-login=\(id).\(secret)"
        let ticket = QRPayload.deviceTicket(from: value)
        XCTAssertEqual(ticket?.server, "https://gethostwatch.com/")
        XCTAssertEqual(ticket?.id, id)
        XCTAssertEqual(ticket?.secret, secret)
        XCTAssertNil(QRPayload.deviceTicket(from: "http://evil.example/#device-login=\(id).\(secret)"))
        XCTAssertNil(QRPayload.deviceTicket(from: "https://gethostwatch.com/#approve=\(id)"))
        XCTAssertNil(QRPayload.deviceTicket(from: "https://gethostwatch.com/#device-login=bad.\(secret)"))
    }

    func testAuthenticatorQRHasExpectedIssuerAndSecret() {
        let setup = TOTPSetup(totpSecret: "ABCDEFGHIJKLMNOP", issuer: "HOSTWATCH", account: "owner@example.com")
        let parts = URLComponents(string: setup.uri)
        XCTAssertEqual(parts?.scheme, "otpauth")
        XCTAssertEqual(parts?.host, "totp")
        XCTAssertEqual(parts?.queryItems?.first(where: { $0.name == "secret" })?.value, "ABCDEFGHIJKLMNOP")
        XCTAssertEqual(parts?.queryItems?.first(where: { $0.name == "issuer" })?.value, "HOSTWATCH")
    }
}
