import XCTest
@testable import RetroMac

/// What VoiceOver gets to see of RetroMac's windows: not the ones that only draw.
final class AccessibilityWindowsTests: XCTestCase {
    private func window() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 50, height: 20), styleMask: [.borderless], backing: .buffered, defer: true)
    }

    func testClickThroughWindowsAreDecoration() {
        let w = window(); w.ignoresMouseEvents = true
        XCTAssertTrue(RetroMacApplication.isDecorative(w))
    }

    func testTitleBarsAreDecoration() {
        let bar = window(); bar.contentView = TitleBarOverlayView(frame: .zero)
        XCTAssertTrue(RetroMacApplication.isDecorative(bar))
        let aero = window(); aero.contentView = NSView(); aero.contentView!.addSubview(TitleBarOverlayView(frame: .zero))
        XCTAssertTrue(RetroMacApplication.isDecorative(aero), "Aero's bar sits on a glass view")
    }

    func testWindowsPeopleUseStay() {
        XCTAssertFalse(RetroMacApplication.isDecorative(window()), "a window that takes the mouse and is no title bar")
        XCTAssertFalse(RetroMacApplication.isDecorative("not a window"))
    }
}
