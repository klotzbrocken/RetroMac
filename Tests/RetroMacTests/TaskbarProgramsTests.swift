import XCTest
@testable import RetroMac

/// The taskbar without Accessibility: a program gets a button only while it has a window.
final class TaskbarProgramsTests: XCTestCase {
    private func window(pid: pid_t, layer: Int = 0, w: CGFloat = 800, h: CGFloat = 600) -> [String: Any] {
        [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
         kCGWindowBounds as String: CGRect(x: 0, y: 0, width: w, height: h).dictionaryRepresentation]
    }

    func testOnlyProgramsWithADocumentWindowCount() {
        let info = [window(pid: 1), window(pid: 2, layer: 25), window(pid: 3, w: 20, h: 20), window(pid: 4, h: 49)]
        XCTAssertEqual(MinimizedWindowTracker.pidsWithWindows(info), [1])
    }
}
