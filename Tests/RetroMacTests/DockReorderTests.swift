import XCTest
@testable import RetroMac

/// Rearranging the dock: the slot a drop names counts the icons of the group without the
/// dragged one, so a move to the right lands where it was let go and not one further on.
final class DockReorderTests: XCTestCase {

    private func app(_ id: String) -> DockApp { DockApp(bundleID: id, customIconPath: nil, order: 0) }
    private func folder(_ path: String) -> DockApp {
        DockApp(bundleID: "__folder__" + path, customIconPath: nil, order: 0, folderPath: path)
    }
    private func ids(_ apps: [DockApp]) -> [String] { apps.map(\.bundleID) }
    private let everything: (DockApp) -> Bool = { _ in true }

    func testMovingRightLandsBetweenTheIconsItWasDroppedBetween() {
        // A B C D, B dropped between C and D: without B the row is A C D, and C is before the
        // drop point, A too — slot 2.
        let r = AppManager.reordered([app("A"), app("B"), app("C"), app("D")], moving: "B", toSlot: 2, inRow: everything)
        XCTAssertEqual(ids(r), ["A", "C", "B", "D"])
    }

    func testMovingLeftAndToTheEnds() {
        let list = [app("A"), app("B"), app("C"), app("D")]
        XCTAssertEqual(ids(AppManager.reordered(list, moving: "D", toSlot: 1, inRow: everything)), ["A", "D", "B", "C"])
        XCTAssertEqual(ids(AppManager.reordered(list, moving: "C", toSlot: 0, inRow: everything)), ["C", "A", "B", "D"])
        XCTAssertEqual(ids(AppManager.reordered(list, moving: "A", toSlot: 3, inRow: everything)), ["B", "C", "D", "A"])
    }

    func testFoldersMoveAmongTheFolders() {
        // Apps and folders interleaved in the list; the stacks group counts only folders.
        let list = [app("A"), folder("/F1"), app("B"), folder("/F2"), folder("/F3")]
        let folders: (DockApp) -> Bool = { $0.isFolder }
        let r = AppManager.reordered(list, moving: "__folder__/F1", toSlot: 1, inRow: folders)   // after F2
        XCTAssertEqual(ids(r).filter { $0.hasPrefix("__folder__") }, ["__folder__/F2", "__folder__/F1", "__folder__/F3"])
        XCTAssertEqual(ids(r).filter { !$0.hasPrefix("__folder__") }, ["A", "B"], "the apps keep their order")
    }

    func testSlotCountsTheIconsBeforeTheDropPoint() {
        let centres: [CGFloat] = [20, 60, 100]            // the group without the dragged icon
        XCTAssertEqual(DockView.slot(forDrop: 5, centres: centres, descending: false), 0)
        XCTAssertEqual(DockView.slot(forDrop: 80, centres: centres, descending: false), 2)
        XCTAssertEqual(DockView.slot(forDrop: 500, centres: centres, descending: false), 3)
        // Down a vertical dock y grows upwards: "before" is above.
        XCTAssertEqual(DockView.slot(forDrop: 70, centres: [300, 200, 100, 20], descending: true), 3)
    }

    func testDoubleClickOnTheBarDoesWhatEachEraDid() {
        XCTAssertEqual(TitleBarOverlayController.Style.platinum.doubleClickAction, .collapse, "Mac OS 8/9: WindowShade")
        XCTAssertNil(TitleBarOverlayController.Style.system7.doubleClickAction, "System 7.1 did nothing")
        XCTAssertNil(TitleBarOverlayController.Style.system6.doubleClickAction)
        XCTAssertEqual(TitleBarOverlayController.Style.luna.doubleClickAction, .zoom, "Windows maximised")
        XCTAssertEqual(TitleBarOverlayController.Style.snowLights.doubleClickAction, .minimize, "10.6 minimised")
    }
}
