import XCTest
@testable import RetroMac

/// Unit tests for `LicenseManager.parseGumroad` — the pure decode of a Gumroad verify response.
/// `definitive` distinguishes a clear server verdict (act on it) from a transient failure (keep
/// the current status). Revalidation revokes only on `!valid && definitive`.
final class LicenseValidationTests: XCTestCase {

    func testValidPurchase() {
        let r = LicenseManager.parseGumroad([
            "success": true,
            "purchase": ["email": "buyer@example.com"]
        ])
        XCTAssertTrue(r.valid)
        XCTAssertTrue(r.definitive)
        XCTAssertEqual(r.email, "buyer@example.com")
        XCTAssertNil(r.error)
    }

    func testRefundedIsDefinitivelyInvalid() {
        let r = LicenseManager.parseGumroad([
            "success": true,
            "purchase": ["email": "buyer@example.com", "refunded": true]
        ])
        XCTAssertFalse(r.valid)
        XCTAssertTrue(r.definitive)   // → revoke
    }

    func testChargebackedIsDefinitivelyInvalid() {
        let r = LicenseManager.parseGumroad([
            "success": true,
            "purchase": ["chargebacked": true]
        ])
        XCTAssertFalse(r.valid)
        XCTAssertTrue(r.definitive)   // → revoke
    }

    func testServerSaysInvalidIsDefinitive() {
        let r = LicenseManager.parseGumroad([
            "success": false,
            "message": "That license does not exist for the provided product."
        ])
        XCTAssertFalse(r.valid)
        XCTAssertTrue(r.definitive)   // → revoke
        XCTAssertNotNil(r.error)
    }

    func testMalformedResponseIsNotDefinitive() {
        // Parseable JSON without a boolean "success" field (proxy/error page) ⇒ invalid but
        // NOT definitive, so revalidation keeps the current status instead of revoking.
        let r = LicenseManager.parseGumroad(["unexpected": "shape"])
        XCTAssertFalse(r.valid)
        XCTAssertFalse(r.definitive)
    }
}
