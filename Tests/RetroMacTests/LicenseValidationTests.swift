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

    // MARK: - The page that asks for the money

    /// Every paid feature has to appear on the Get More page.
    ///
    /// Retro Crashes was gated, added to `premiumFeatures`, wired to the unlock screen — and
    /// never mentioned on the one page the Setup Assistant shows to ask for the purchase. The
    /// file's own comment says whoever gates a feature edits that list; nothing enforced it.
    func testEveryPaidFeatureIsAdvertisedOnTheGetMorePage() {
        let sold = Set(GetMoreView.perks.compactMap(\.feature))
        for feature in LicenseManager.premiumFeatures {
            XCTAssertTrue(sold.contains(feature.name),
                          "\(feature.name) is paid but is not on the Get More page")
        }
    }

    /// And the other way round: a perk claiming to sell a feature that no longer exists would
    /// promise something the licence does not unlock.
    func testTheGetMorePageSellsNothingImaginary() {
        let real = Set(LicenseManager.premiumFeatures.map(\.name))
        for perk in GetMoreView.perks {
            guard let feature = perk.feature else { continue }
            XCTAssertTrue(real.contains(feature), "Get More sells \(feature), which is not gated")
        }
    }
}
