import XCTest
@testable import RetroMac

/// Unit tests for the SystemBridge capability probes. The probes take their raw OS checks
/// as injectable closures, so these run WITHOUT shelling out to real `defaults`/AX.
final class SystemBridgeTests: XCTestCase {

    // MARK: systemDockControl — write + read-back of the dock pref schema

    func testDockControlAvailableWhenReadBackMatches() {
        var stored = "0"   // pretend the dock pref starts unset/false
        let status = SystemBridge.shared.probeSystemDockControl(
            read: { _ in stored },
            write: { _, v in stored = v; return true }   // honest write
        )
        XCTAssertTrue(status.available)
        XCTAssertFalse(status.degraded)
    }

    func testDockControlAvailableNormalizesBoolStrings() {
        // Original is "true"; probe writes "1" — normalization must treat them as equal.
        var stored = "true"
        let status = SystemBridge.shared.probeSystemDockControl(
            read: { _ in stored },
            write: { _, v in stored = (v == "1") ? "true" : "false"; return true }
        )
        XCTAssertTrue(status.available)
    }

    func testDockControlUnavailableOnSchemaMismatch() {
        // macOS-27 simulation: the write "succeeds" but read-back never reflects it.
        let status = SystemBridge.shared.probeSystemDockControl(
            read: { _ in "garbage" },
            write: { _, _ in true }
        )
        XCTAssertFalse(status.available)
        XCTAssertTrue(status.degraded)
        XCTAssertNotNil(status.reason)
    }

    func testDockControlUnavailableWhenWriteFails() {
        let status = SystemBridge.shared.probeSystemDockControl(
            read: { _ in "0" },
            write: { _, _ in false }   // pref not writable
        )
        XCTAssertFalse(status.available)
        XCTAssertNotNil(status.reason)
    }

    // MARK: accessibility / screen capture / virtual display

    func testAccessibilityReflectsTrust() {
        XCTAssertTrue(SystemBridge.shared.probeAccessibility(trusted: { true }).available)
        let denied = SystemBridge.shared.probeAccessibility(trusted: { false })
        XCTAssertFalse(denied.available)
        XCTAssertNotNil(denied.reason)
    }

    func testScreenCaptureReflectsPreflight() {
        XCTAssertTrue(SystemBridge.shared.probeScreenCapture(preflight: { true }).available)
        XCTAssertFalse(SystemBridge.shared.probeScreenCapture(preflight: { false }).available)
    }

    func testVirtualDisplayReflectsSymbol() {
        XCTAssertTrue(SystemBridge.shared.probeVirtualDisplay(symbolPresent: { true }).available)
        XCTAssertFalse(SystemBridge.shared.probeVirtualDisplay(symbolPresent: { false }).available)
    }

    func testMenuBarAutohideAvailableWhenAutomationGranted() {
        XCTAssertTrue(SystemBridge.shared.probeMenuBarAutohide(automationOK: { true }).available)
    }

    // MARK: capability cache default

    func testCapabilityDefaultsToAssumedAvailableBeforeProbe() {
        // A capability never probed in this process reads as assumed-available, so startup
        // never blocks on the probe (the async probe reconciles afterwards).
        let status = SystemBridge.shared.capability(.virtualDisplay)
        XCTAssertTrue(status.available)
        XCTAssertFalse(status.degraded)
        XCTAssertNil(status.reason)
    }
}
