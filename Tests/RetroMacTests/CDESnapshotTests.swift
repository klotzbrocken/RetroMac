import XCTest
@testable import RetroMac

/// The Solaris 8 Front Panel and a subpanel lay out at their measured sizes; with
/// RETROMAC_SNAPSHOT_DIR set, both are drawn to PNGs for comparing against the reference.
final class CDESnapshotTests: XCTestCase {
    private func theme() throws -> ThemeBundle {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes/Solaris8-CDE.retromactheme")
        return try ThemeBundle(url: url, isBuiltIn: true)
    }

    private func snapshot(_ view: NSView, _ name: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"],
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }

    @MainActor
    func testFrontPanel() throws {
        let t = try theme()
        XCTAssertEqual(t.config.id, "com.retromac.sun.solaris8-cde")
        XCTAssertTrue(t.config.hidesDock, "the Front Panel stands in for the dock")
        let v = CDEFrontPanelView(theme: t)
        XCTAssertEqual(v.frame.size, NSSize(width: 956, height: 86))
        try snapshot(v, "cde-frontpanel.png")
    }

    @MainActor
    func testSubpanel() throws {
        let v = CDESubpanel(kind: .help, theme: try theme())
        XCTAssertEqual(v.frame.width, 208, "the width of the Solaris 8 Help subpanel")
        try snapshot(v, "cde-subpanel-help.png")
    }

    @MainActor
    func testWorkspaceMenu() throws {
        let t = try theme()
        // Solaris 8's own Workspace Menu: 31 … 364 in the reference, 334 pt tall with its two
        // icon rows "Add Item to Menu" and "Customize Menu", here one row ("RetroMac Settings").
        let items = CDEDesktop.workspaceMenu(theme: t)
        XCTAssertEqual(CDEMenu.size(of: items, title: "Workspace Menu").height, 334 - 23)
        XCTAssertEqual(items.first?.title, "Applications")
        XCTAssertEqual(items.last?.title, "Exit Theme...", "CDE-11: the menu's last entry ends the theme, not the session")
        let v = CDEMenuView(frame: NSRect(x: 0, y: 0, width: 420, height: 360))
        v.open(items, title: "Workspace Menu", at: .zero, level: 0)
        try snapshot(v, "cde-workspace-menu.png")
    }

    func testApplicationManagerGroups() {
        // CDE-04: Mac apps go to Solaris-style groups by the App Store category they declare.
        XCTAssertEqual(AppFolderController.cdeGroup(forCategory: "public.app-category.utilities"), "Desktop_Tools")
        XCTAssertEqual(AppFolderController.cdeGroup(forCategory: "public.app-category.developer-tools"), "Developer_Tools")
        XCTAssertEqual(AppFolderController.cdeGroup(forCategory: "public.app-category.puzzle-games"), "Games")
        XCTAssertEqual(AppFolderController.cdeGroup(forCategory: "public.app-category.productivity"), "Desktop_Apps")
        XCTAssertEqual(AppFolderController.cdeGroup(forCategory: nil), "Desktop_Apps", "no category: the general group")
        XCTAssertFalse(AppFolderController.cdeGroups.contains(AppFolderController.cdeAllGroup))
    }

    func testSolarisPanicScreen() throws {
        var rng = CrashRNG(seed: 8)
        let screen = CrashCopy.solarisPanic(using: &rng)
        XCTAssertEqual(screen.palette, .sunConsole, "a Sun console is black on white")
        guard let dir = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"],
              let image = CrashRenderer.image(for: screen, counter: 64) else { return }
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("solaris-panic.png"))
    }
}
