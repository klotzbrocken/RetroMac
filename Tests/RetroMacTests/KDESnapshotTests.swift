import XCTest
@testable import RetroMac

/// KDE 1.0's panel at kpanelrc's sizes; with RETROMAC_SNAPSHOT_DIR set it is drawn to a PNG.
final class KDESnapshotTests: XCTestCase {
    private func theme() throws -> ThemeBundle {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes/KDE1.retromactheme")
        return try ThemeBundle(url: url, isBuiltIn: true)
    }

    private func snapshot(_ view: NSView, _ name: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"],
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }

    @MainActor
    func testPanelLaysOutAsKpanelDid() throws {
        let t = try theme()
        XCTAssertEqual(t.config.id, "com.retromac.kde.kde1")
        XCTAssertEqual(t.config.chrome?.style, "kde")
        XCTAssertEqual(ThemeManager.category(of: t), "Unix & Amiga")
        XCTAssertTrue(t.config.hidesDock, "the panel and the taskbar stand in for the dock")
        XCTAssertEqual(t.config.hideMenuBarDefault, true, "the taskbar holds the top edge, as on a KDE screen")
        XCTAssertEqual(t.config.wallpapers?.map(\.name), KDEDesktopController.desktopNames, "one background per desktop, kdisplayrc's four")
        for b in KPanelView.left + KPanelView.right { XCTAssertNotNil(t.iconResource(b.icon), b.icon) }
        let panel = KPanelView(theme: t)
        panel.frame = NSRect(x: 0, y: 0, width: 1024, height: KPanelView.height)
        let ids = panel.parts.map(\.id)
        XCTAssertEqual(Array(ids.prefix(6)), ["hide", "k", "windowlist", "home", "kcontrol", "kfind"])
        XCTAssertEqual(ids.last, "clock")
        let k = try XCTUnwrap(panel.parts.first { $0.id == "k" }).rect
        XCTAssertEqual(k, NSRect(x: 13, y: 1, width: 43, height: 43), "12 pt hide button, then the K button a point in")
        let one = try XCTUnwrap(panel.parts.first { $0.id == "desk0" }).rect, four = try XCTUnwrap(panel.parts.first { $0.id == "desk3" }).rect
        XCTAssertEqual(one.size, NSSize(width: 88, height: 22))
        XCTAssertEqual(four.minX - one.minX, 89, "two columns of desktops")
        XCTAssertEqual(four.minY, 23, "Two and Four in the lower row")
        try snapshot(panel, "kde-panel.png")
        let bar = KTaskbarView()
        bar.frame = NSRect(x: 0, y: 0, width: 1024, height: KTaskbarView.height)
        try snapshot(bar, "kde-taskbar.png")
    }

    func testGroupsFollowWhatAppsDeclare() {
        XCTAssertEqual(KDEApps.group(path: "/a.app", category: "public.app-category.action-games", internet: []), "Games")
        XCTAssertEqual(KDEApps.group(path: "/a.app", category: "public.app-category.photography", internet: []), "Graphics")
        XCTAssertEqual(KDEApps.group(path: "/a.app", category: "public.app-category.music", internet: []), "Multimedia")
        XCTAssertEqual(KDEApps.group(path: "/a.app", category: nil, internet: ["/a.app"]), "Internet")
        XCTAssertEqual(KDEApps.group(path: "/System/Applications/System Settings.app", category: nil, internet: []), "Settings")
        XCTAssertEqual(KDEApps.group(path: "/System/Applications/Utilities/Terminal.app", category: nil, internet: []), "System")
        XCTAssertEqual(KDEApps.group(path: "/Applications/Pages.app", category: "public.app-category.productivity", internet: []), "Applications")
    }

    func testTwoInstallsOfOneNameSayWhereTheyAre() {
        let apps = KDEApps.disambiguate([
            KDEApps.App(title: "Tool", path: "/Applications/Tool.app", bundleID: "a", group: "Applications"),
            KDEApps.App(title: "Tool", path: "/Volumes/X/Tool.app", bundleID: "b", group: "Applications"),
            KDEApps.App(title: "Alpha", path: "/Applications/Alpha.app", bundleID: "c", group: "Applications")])
        XCTAssertEqual(apps.map(\.title), ["Alpha", "Tool (/Applications)", "Tool (/Volumes/X)"])
    }

    func testRunCommandFindsTheApp() {
        let apps = ["Safari", "Calculator", "Claude", "Microsoft PowerPoint"].map {
            KDEApps.App(title: $0, path: "/Applications/\($0).app", bundleID: nil, group: "Applications")
        }
        XCTAssertEqual(KDECommandPanel.match("claude", in: apps)?.title, "Claude", "exact name first")
        XCTAssertEqual(KDECommandPanel.match("calc", in: apps)?.title, "Calculator")
        XCTAssertEqual(KDECommandPanel.match("powerpoint", in: apps)?.title, "Microsoft PowerPoint", "a word inside the name")
        XCTAssertNil(KDECommandPanel.match("  ", in: apps))
    }

    func testTheClockReadsAsKpanelWroteIt() {
        var c = DateComponents(); c.year = 1998; c.month = 7; c.day = 12; c.hour = 9; c.minute = 5
        XCTAssertEqual(KPanelView.clockLines(Calendar.current.date(from: c)!), ["Sun", "09:05", "Jul 12"])
    }
}

/// kwm's three buttons answer a click where they are drawn, the window in front or behind.
final class KWMBarClickTests: XCTestCase {
    func testEachButtonFiresItsAction() {
        let h = TitleBarOverlayController.stripHeight(.kde)
        for front in [true, false] {
            let view = TitleBarOverlayView(frame: NSRect(x: 0, y: 0, width: 420, height: h))
            let win = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            win.contentView = view
            view.configure(style: .kde, title: "Untitled", icon: nil, isFront: front, lights: [:], deadZoneWidth: 0, zoomed: false)
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: rep) }   // lays the buttons out
            var fired: [ChromeButtonKind] = []
            view.onAction = { fired.append($0) }
            // flipped view: y from the top; the buttons are 18 pt squares 5 pt down, close 4 pt from the right
            let xs: [CGFloat] = [407, 387, 367]   // close, maximise, iconify: centres of the 18 pt squares
            for x in xs {
                let p = view.convert(NSPoint(x: x, y: 5 + 9), to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber,
                                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                    type == .leftMouseDown ? view.mouseDown(with: e) : view.mouseUp(with: e)
                }
            }
            XCTAssertEqual(fired, [.close, .maximize, .minimize], "front=\(front)")
        }
    }
}
