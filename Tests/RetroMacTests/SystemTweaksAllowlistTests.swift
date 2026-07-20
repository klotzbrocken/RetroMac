import XCTest
@testable import RetroMac

/// Unit tests for the systemTweaks security guards: the cosmetic-key allowlist and the
/// Finder/Dock-only clamp on `killall` refresh targets. Both are pure — no `defaults`/`killall`.
final class SystemTweaksAllowlistTests: XCTestCase {

    private func tweak(_ domain: String, _ key: String, refresh: String? = nil) -> DockThemeConfig.SystemTweak {
        DockThemeConfig.SystemTweak(domain: domain, key: key, type: "bool", value: "true", refresh: refresh)
    }

    // MARK: - Allowlist

    func testAllowedCosmeticKeysPass() {
        XCTAssertTrue(SystemTweaksAdapter.isTweakAllowed(tweak("com.apple.finder", "ShowStatusBar")))
        XCTAssertTrue(SystemTweaksAdapter.isTweakAllowed(tweak("-g", "AppleShowAllExtensions")))
        XCTAssertTrue(SystemTweaksAdapter.isTweakAllowed(tweak("com.apple.dock", "mineffect")))
        XCTAssertTrue(SystemTweaksAdapter.isTweakAllowed(tweak("com.apple.universalaccess", "reduceTransparency")))
    }

    func testForeignDomainRejected() {
        // A third-party app's domain must never be writable through a theme.
        XCTAssertFalse(SystemTweaksAdapter.isTweakAllowed(tweak("com.evil.app", "pwned")))
        XCTAssertFalse(SystemTweaksAdapter.isTweakAllowed(tweak("com.apple.loginwindow", "autoLoginUser")))
    }

    func testNonCosmeticKeyInAllowedDomainRejected() {
        // Right domain, but a key that is not on the cosmetic allowlist.
        XCTAssertFalse(SystemTweaksAdapter.isTweakAllowed(tweak("com.apple.finder", "SomeUnknownKey")))
        XCTAssertFalse(SystemTweaksAdapter.isTweakAllowed(tweak("-g", "NSSomethingArbitrary")))
    }

    // MARK: - Refresh clamp (never killall an arbitrary process)

    func testRefreshClampedToFinderDock() {
        XCTAssertEqual(SystemTweaksAdapter.refreshTargets(domain: "com.apple.finder", refresh: "Finder"), ["Finder"])
        XCTAssertEqual(SystemTweaksAdapter.refreshTargets(domain: "com.apple.dock", refresh: "Dock"), ["Dock"])
    }

    func testArbitraryRefreshTargetIgnored() {
        // "loginwindow" would log the user out; it must be dropped and the domain default used.
        XCTAssertEqual(SystemTweaksAdapter.refreshTargets(domain: "com.apple.finder", refresh: "loginwindow"), ["Finder"])
        XCTAssertEqual(SystemTweaksAdapter.refreshTargets(domain: "com.apple.dock", refresh: "WindowServer"), ["Dock"])
        // Global domain with a bogus refresh falls back to refreshing Finder + Dock.
        XCTAssertEqual(SystemTweaksAdapter.refreshTargets(domain: "-g", refresh: "kernel_task"), ["Finder", "Dock"])
    }
}
