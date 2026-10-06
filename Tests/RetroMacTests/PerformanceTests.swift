import XCTest
@testable import RetroMac

/// The measurable goals of Lastenheft 3.0, section 12, on the reference Mac. The figures are
/// printed for the performance protocol (docs/PERFORMANCE-3.0.md).
final class PerformanceTests: XCTestCase {
    private func theme(_ folder: String) throws -> ThemeBundle {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes/\(folder)")
        return try ThemeBundle(url: url, isBuiltIn: true)
    }

    /// p95 in milliseconds of `runs` warm calls (one cold call first, not counted).
    private func p95(_ runs: Int = 30, _ body: () -> Void) -> Double {
        body()
        let times = (0..<runs).map { _ -> Double in
            let t = DispatchTime.now().uptimeNanoseconds
            body()
            return Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6
        }.sorted()
        return times[Int((Double(runs) * 0.95).rounded(.up)) - 1]
    }

    /// Builds the menu and draws its first frame offscreen.
    @MainActor
    private func drawn(_ items: [CDEMenuItem], title: String?) {
        let view = CDEMenuView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900))
        view.open(items, title: title, at: .zero, level: 0)
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
    }

    /// PERF-04: a launcher menu opens with its first frame within 100 ms (p95, warm, 30 runs).
    @MainActor
    func testMenusOpenWithin100ms() throws {
        let cde = try theme("Solaris8-CDE.retromactheme")
        _ = PhotonLaunchMenu.items()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))   // the background read of the app folders comes in
        let launch = p95 { drawn(PhotonLaunchMenu.items(), title: nil) }
        let workspace = p95 { drawn(CDEDesktop.workspaceMenu(theme: cde), title: "Workspace Menu") }
        let subpanel = p95 {
            let v = CDESubpanel(kind: .applications, theme: cde)
            let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
            v.cacheDisplay(in: v.bounds, to: rep)
        }
        print(String(format: "[PERF-04] p95 ms: Photon Launch %.1f, CDE Workspace Menu %.1f, CDE subpanel %.1f", launch, workspace, subpanel))
        XCTAssertLessThan(launch, 100)
        XCTAssertLessThan(workspace, 100)
        XCTAssertLessThan(subpanel, 100)
    }

    /// PERF-06: 100 times open and close leave no window, mouse monitor or held key behind.
    @MainActor
    func testOpenAndCloseLeaveNothingBehind() throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("no display") }
        let items = [CDEMenuItem(title: "One", action: {}), CDEMenuItem(title: "Two", submenu: [CDEMenuItem(title: "Three", action: {})])]
        let point = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let before = NSApp.windows.filter(\.isVisible).count, allBefore = NSApp.windows.count
        for i in 0..<100 {
            autoreleasepool {   // as the app's run loop drains its pool after each event
                CDEMenu.show(items, at: point, look: i.isMultiple(of: 2) ? .cde : .photon)
                XCTAssertTrue(CDEMenu.isOpen)
                CDEMenu.close()
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertFalse(CDEMenu.isOpen)
        XCTAssertFalse(CDEEscape.isHeld, "Esc let go")
        XCTAssertEqual(NSApp.windows.filter(\.isVisible).count, before, "no menu panel left on screen")
        XCTAssertLessThanOrEqual(NSApp.windows.count, allBefore + 1, "no menu window kept alive")
        print("[PERF-06] 100 open/close: visible windows \(before) before, \(NSApp.windows.filter(\.isVisible).count) after; all windows \(NSApp.windows.count)")
    }

    /// PERF-02: what the new surfaces add while idle. Each wakes once a second (the shelf only while
    /// shown with its monitor open), takes its readings and draws again; that second's work is
    /// measured here and given as a share of one core.
    @MainActor
    func testIdleCostOfTheNewSurfaces() throws {
        let qnx = try theme("QNX621-Photon.retromactheme"), cde = try theme("Solaris8-CDE.retromactheme")
        let shelf = PhotonShelfView(theme: qnx)
        shelf.frame = NSRect(x: 0, y: 0, width: PhotonShelfView.width, height: 575)
        let shelfRep = shelf.bitmapImageRepForCachingDisplay(in: shelf.bounds)!
        let panel = CDEFrontPanelView(theme: cde)
        let panelRep = panel.bitmapImageRepForCachingDisplay(in: panel.bounds)!
        let shelfMs = mean { shelf.start(); shelf.stop(); shelf.cacheDisplay(in: shelf.bounds, to: shelfRep) }
        let panelMs = mean { panel.start(); panel.stop(); panel.cacheDisplay(in: panel.bounds, to: panelRep) }
        print(String(format: "[PERF-02] one second's work: QNX shelf %.2f ms (%.2f %% of a core), CDE Front Panel %.2f ms (%.2f %%)",
                     shelfMs, shelfMs / 10, panelMs, panelMs / 10))
        XCTAssertLessThan(shelfMs / 10, 1, "under one percentage point")
        XCTAssertLessThan(panelMs / 10, 1)
    }

    /// Mean milliseconds of 30 warm runs.
    private func mean(_ body: () -> Void) -> Double {
        body()
        let t = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<30 { body() }
        return Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6 / 30
    }
}
