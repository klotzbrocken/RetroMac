import XCTest
import AppKit
@testable import RetroMac

/// The dock's row is enumerated in one place so that sizing, creation, positioning and
/// change-detection cannot disagree. These tests hold that enumeration to its contract; the bug
/// they exist for is the trash being drawn beside the bar because the Dashboard tile reached
/// three of those four places and not the fourth.
final class DockTileTests: XCTestCase {

    private let icon: CGFloat = 52
    private let gap: CGFloat = 4
    private let doom: CGFloat = 96

    private func app(_ id: String) -> DockApp {
        DockApp(bundleID: id, customIconPath: nil, order: 0, folderPath: nil)
    }
    private func folder(_ id: String, _ path: String) -> DockApp {
        DockApp(bundleID: id, customIconPath: nil, order: 0, folderPath: path)
    }

    private func tiles(apps: [DockApp] = [],
                       transients: [String] = [],
                       taskbar: Bool = false,
                       showQuickLaunch: Bool = true,
                       stacksOnRight: Bool = true,
                       dashboard: Bool = false,
                       showDesktop: Bool = false,
                       urlLauncher: Bool = false,
                       trash: Bool = false,
                       doomLauncher: Bool = false) -> [DockTile] {
        DockView.iconDockTiles(taskbar: taskbar,
                               showQuickLaunch: showQuickLaunch,
                               apps: apps,
                               transients: transients,
                               stacksOnRight: stacksOnRight,
                               hasDashboard: dashboard,
                               hasShowDesktop: showDesktop,
                               hasUrlLauncher: urlLauncher,
                               hasTrash: trash,
                               hasDoomLauncher: doomLauncher,
                               iconSize: icon,
                               spacing: gap,
                               doomWidth: doom)
    }

    /// Walk the tiles exactly the way the dock lays them out and report where the row ends.
    /// If this ever disagrees with `iconDockRunLength`, the bar is the wrong size for its
    /// contents — which is the failure this whole arrangement exists to prevent.
    private func walkedLength(_ tiles: [DockTile]) -> CGFloat {
        var x: CGFloat = 0
        for t in tiles {
            x += t.gapBefore
            x += t.width + gap
        }
        return max(0, x - gap)
    }

    // MARK: - The invariant

    func testRunLengthMatchesWalkingTheRow() {
        let cases: [[DockTile]] = [
            tiles(),
            tiles(apps: [app("a")]),
            tiles(apps: [app("a"), app("b"), app("c")]),
            tiles(apps: [app("a")], dashboard: true),
            tiles(apps: [app("a")], transients: ["t1", "t2"]),
            tiles(apps: [app("a"), folder("d", "~/Downloads")], trash: true),
            tiles(apps: [app("a")], dashboard: true, urlLauncher: true, trash: true, doomLauncher: true),
            tiles(apps: [app("a"), folder("d", "~/Downloads"), folder("p", "/Applications")],
                  transients: ["t"], dashboard: true, trash: true),
        ]
        for row in cases {
            XCTAssertEqual(DockView.iconDockRunLength(row, spacing: gap),
                           walkedLength(row),
                           accuracy: 0.0001,
                           "sizing and layout disagree for \(row.map { $0.id })")
        }
    }

    /// The regression itself: the row has to grow by a full tile when Dashboard is in it.
    func testDashboardWidensTheRowByOneTile() {
        let without = tiles(apps: [app("finder"), app("safari")], trash: true)
        let with = tiles(apps: [app("finder"), app("safari")], dashboard: true, trash: true)
        XCTAssertEqual(with.count, without.count + 1)
        XCTAssertEqual(DockView.iconDockRunLength(with, spacing: gap)
                        - DockView.iconDockRunLength(without, spacing: gap),
                       icon + gap, accuracy: 0.0001)
    }

    // MARK: - Order and grouping

    func testDashboardSitsDirectlyAfterTheFirstApp() {
        let row = tiles(apps: [app("finder"), app("safari")], dashboard: true)
        XCTAssertEqual(row.map { $0.id }, ["finder", "__dashboard__", "safari"])
    }

    func testDashboardStillAppearsWithNoPinnedApps() {
        XCTAssertEqual(tiles(dashboard: true).map { $0.id }, ["__dashboard__"])
    }

    func testFolderStacksMoveNextToTheTrash() {
        let row = tiles(apps: [app("finder"), folder("dl", "~/Downloads"), app("mail")],
                        trash: true)
        XCTAssertEqual(row.map { $0.id }, ["finder", "mail", "dl", "__trash__"])
    }

    func testFolderStacksStayInlineWithoutARightHandGroup() {
        let row = tiles(apps: [app("finder"), folder("dl", "~/Downloads")], stacksOnRight: false)
        XCTAssertEqual(row.map { $0.id }, ["finder", "dl"])
    }

    func testTrashIsAlwaysLastExceptForTheDoomTile() {
        XCTAssertEqual(tiles(apps: [app("a")], urlLauncher: true, trash: true).map { $0.id }.last,
                       "__trash__")
        XCTAssertEqual(tiles(apps: [app("a")], trash: true, doomLauncher: true).map { $0.id }.last,
                       "__doomlauncher__")
    }

    // MARK: - Separators and gaps

    func testEachGroupIsIntroducedByExactlyOneSeparator() {
        let row = tiles(apps: [app("a"), folder("dl", "~/Downloads")],
                        transients: ["t1", "t2"], trash: true)
        XCTAssertEqual(row.filter { $0.separator == .transients }.count, 1)
        XCTAssertEqual(row.filter { $0.separator == .rightGroup }.count, 1)
        // A separated tile is the one that carries the extra gap.
        for t in row where t.separator != nil {
            XCTAssertEqual(t.gapBefore, gap, "\(t.id) marks a group but reserves no room for it")
        }
        for t in row where t.separator == nil {
            XCTAssertEqual(t.gapBefore, 0, "\(t.id) reserves a gap it never draws into")
        }
    }

    // MARK: - Windows taskbars

    func testTaskbarRowIsQuickLaunchOnly() {
        let row = tiles(apps: [app("a"), app("b")], transients: ["t"],
                        taskbar: true, dashboard: true, showDesktop: true, trash: true)
        // Running apps are task buttons, not tiles; no Dashboard, no stacks, no trash.
        XCTAssertEqual(row.map { $0.id }, ["__showdesktop__", "a", "b"])
    }

    func testTaskbarWithoutQuickLaunchHasNoTiles() {
        XCTAssertTrue(tiles(apps: [app("a")], taskbar: true, showQuickLaunch: false,
                            showDesktop: true).isEmpty)
    }

    // MARK: - Identity

    func testIDsAreUniqueSoChangeDetectionCanRelyOnThem() {
        let row = tiles(apps: [app("a"), folder("dl", "~/Downloads")],
                        transients: ["t"], dashboard: true,
                        urlLauncher: true, trash: true, doomLauncher: true)
        XCTAssertEqual(Set(row.map { $0.id }).count, row.count)
    }

    func testTheDoomTileIsWiderThanAnIcon() {
        let row = tiles(apps: [app("a")], trash: true, doomLauncher: true)
        XCTAssertEqual(row.last?.width, doom)
        XCTAssertTrue(row.dropLast().allSatisfy { $0.width == icon })
    }
}
