import XCTest
import Carbon.HIToolbox
@testable import RetroMac

/// Keyboard access to the theme surfaces: the arrow keys in the drawn menus, the dock focus,
/// and the two shortcuts' defaults.
final class KeyboardNavigationTests: XCTestCase {

    /// A menu level as the engines hand them over: rows, a highlight, a row that opens a child.
    private final class FakeLevel: KeyMenuLevel {
        var keyRows: [KeyMenuRow]
        var keyHighlight: Int?
        var children: [Int: FakeLevel] = [:]
        var chosen: [Int] = []
        weak var menu: FakeMenu?
        init(_ rows: [KeyMenuRow]) { keyRows = rows }
        func setKeyHighlight(_ i: Int) { keyHighlight = i; menu?.closeDeeper(than: self) }
        func activateKeyRow(_ i: Int) {
            if let child = children[i] { menu?.levels.append(child) } else { chosen.append(i); menu?.levels = [] }
        }
    }

    private final class FakeMenu {
        var levels: [FakeLevel] = []
        func closeDeeper(than level: FakeLevel) {
            if let i = levels.firstIndex(where: { $0 === level }) { levels = Array(levels.prefix(i + 1)) }
        }
        func key(_ k: NavKey) -> String? {
            MenuKeyNavigator.handle(k, levels: { self.levels }, close: { self.levels = Array(self.levels.prefix($0)) })
        }
    }

    private func makeMenu() -> (FakeMenu, FakeLevel, FakeLevel) {
        let menu = FakeMenu()
        let root = FakeLevel([KeyMenuRow(label: "About"), KeyMenuRow(label: "", selectable: false),
                              KeyMenuRow(label: "Programs", submenu: true), KeyMenuRow(label: "Dimmed", selectable: false),
                              KeyMenuRow(label: "Shut Down")])
        let child = FakeLevel([KeyMenuRow(label: "", selectable: false), KeyMenuRow(label: "Notepad"), KeyMenuRow(label: "Paint")])
        root.children[2] = child
        root.menu = menu; child.menu = menu
        menu.levels = [root]
        return (menu, root, child)
    }

    func testStepSkipsWhatCannotBeHighlightedAndWraps() {
        let rows = [KeyMenuRow(label: "a"), KeyMenuRow(label: "-", selectable: false), KeyMenuRow(label: "b")]
        XCTAssertEqual(MenuKeyNavigator.step(rows, from: nil, by: 1), 0, "Down from nothing: the top")
        XCTAssertEqual(MenuKeyNavigator.step(rows, from: nil, by: -1), 2, "Up from nothing: the bottom")
        XCTAssertEqual(MenuKeyNavigator.step(rows, from: 0, by: 1), 2, "over the separator")
        XCTAssertEqual(MenuKeyNavigator.step(rows, from: 2, by: 1), 0, "round from the bottom")
        XCTAssertEqual(MenuKeyNavigator.step(rows, from: 0, by: -1), 2, "round from the top")
        XCTAssertNil(MenuKeyNavigator.step([KeyMenuRow(label: "-", selectable: false)], from: nil, by: 1))
        XCTAssertNil(MenuKeyNavigator.step([], from: nil, by: 1))
    }

    func testArrowsReturnAndEscapeInAMenu() {
        let (menu, root, child) = makeMenu()
        XCTAssertEqual(menu.key(.down), "About")
        XCTAssertEqual(menu.key(.right), nil, "Right on a plain row does nothing")
        XCTAssertEqual(menu.key(.down), "Programs, submenu")
        XCTAssertEqual(menu.key(.down), "Shut Down", "the dimmed row is passed over")
        XCTAssertEqual(menu.key(.up), "Programs, submenu")
        XCTAssertEqual(menu.key(.right), "Notepad", "Right opens the submenu at its first row")
        XCTAssertEqual(menu.levels.count, 2)
        XCTAssertEqual(menu.key(.down), "Paint", "the keys now work in the submenu")
        XCTAssertEqual(menu.key(.left), "Programs, submenu", "Left closes it, back on its row")
        XCTAssertEqual(menu.levels.count, 1)
        XCTAssertEqual(root.keyHighlight, 2)
        child.keyHighlight = nil
        XCTAssertEqual(menu.key(.enter), "Notepad", "Return opens a submenu as Right does")
        XCTAssertNil(menu.key(.enter))
        XCTAssertEqual(child.chosen, [1], "Return chooses")
        XCTAssertTrue(menu.levels.isEmpty, "and the menu closes")
    }

    func testEscapeClosesTheWholeMenu() {
        let (menu, _, _) = makeMenu()
        _ = menu.key(.down); _ = menu.key(.down); _ = menu.key(.right)
        XCTAssertEqual(menu.levels.count, 2)
        XCTAssertNil(menu.key(.escape))
        XCTAssertTrue(menu.levels.isEmpty)
    }

    func testLeftOnTheFirstLevelStays() {
        let (menu, root, _) = makeMenu()
        _ = menu.key(.down)
        XCTAssertEqual(menu.key(.left), "About", "says where the keyboard still is")
        XCTAssertEqual(menu.levels.count, 1)
        XCTAssertEqual(root.keyHighlight, 0)
    }

    /// The mouse opened a cascade without lighting a row in it: the keys stay on the parent.
    func testKeysWorkOnTheDeepestLevelWithAHighlight() {
        let (menu, root, child) = makeMenu()
        root.keyHighlight = 2
        menu.levels.append(child)
        XCTAssertEqual(menu.key(.down), "Shut Down")
        XCTAssertEqual(menu.levels.count, 1, "moving on closes the cascade")
    }

    func testKeyCodes() {
        XCTAssertEqual(NavKey(keyCode: kVK_Return), .enter)
        XCTAssertEqual(NavKey(keyCode: kVK_ANSI_KeypadEnter), .enter)
        XCTAssertEqual(NavKey(keyCode: kVK_Escape), .escape)
        XCTAssertEqual(NavKey(keyCode: kVK_UpArrow), .up)
        XCTAssertNil(NavKey(keyCode: kVK_ANSI_A))
    }

    func testDockFocusKeys() {
        XCTAssertEqual(DockFocusNavigator.action(for: .right, index: 0, count: 3), .move(1))
        XCTAssertEqual(DockFocusNavigator.action(for: .right, index: 2, count: 3), .move(0), "round from the last")
        XCTAssertEqual(DockFocusNavigator.action(for: .left, index: 0, count: 3), .move(2), "round from the first")
        XCTAssertEqual(DockFocusNavigator.action(for: .down, index: 1, count: 3), .move(2), "a vertical dock")
        XCTAssertEqual(DockFocusNavigator.action(for: .up, index: 1, count: 3), .move(0))
        XCTAssertEqual(DockFocusNavigator.action(for: .enter, index: 1, count: 3), .press)
        XCTAssertEqual(DockFocusNavigator.action(for: .escape, index: 1, count: 3), .leave)
        XCTAssertEqual(DockFocusNavigator.action(for: .right, index: 0, count: 0), .leave, "nothing to focus")
    }

    /// The real CDE menu view: the levels share one view, and arming a cascade row opens it.
    func testCDEMenuByKeyboard() {
        let view = CDEMenuView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let items = [CDEMenuItem(title: "One", action: {}), .separator,
                     CDEMenuItem(title: "Off", enabled: false, action: {}),
                     CDEMenuItem(title: "Two", submenu: [CDEMenuItem(title: "Three", action: {})])]
        view.open(items, title: "Workspace Menu", at: NSPoint(x: 10, y: 10), level: 0)
        func key(_ k: NavKey) -> String? { MenuKeyNavigator.handle(k, levels: { view.keyLevels }, close: { view.closeKeyLevel($0) }) }
        XCTAssertEqual(key(.down), "One")
        XCTAssertEqual(key(.down), "Two, submenu", "the separator and the insensitive row are passed over")
        XCTAssertEqual(view.keyLevels.count, 2, "a cascade posts as its row is armed")
        XCTAssertEqual(key(.right), "Three")
        XCTAssertEqual(key(.left), "Two, submenu")
        XCTAssertEqual(view.keyLevels.count, 1)
    }

    func testShortcutDefaults() {
        let suite = "retromac.keys.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        let s = AppSettings(defaults: store)
        XCTAssertEqual(s.launcherHotkeyCode, UInt32(kVK_Escape))
        XCTAssertEqual(s.launcherHotkeyModifiers, UInt32(controlKey), "⌃Esc, as Windows opens Start")
        XCTAssertEqual(s.dockFocusHotkeyCode, UInt32(kVK_Escape))
        XCTAssertEqual(s.dockFocusHotkeyModifiers, UInt32(controlKey | shiftKey), "⌃⇧Esc")
        XCTAssertTrue(s.isRetroMacHotkey(code: UInt32(kVK_Escape), modifiers: UInt32(controlKey)), "Rescue and the switcher refuse it")
    }

    /// An overlay toggle of yours on ⌃Esc stays yours: the launcher starts without a shortcut.
    func testTheLauncherNeverTakesYourShortcut() {
        let suite = "retromac.keys.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        store.set(UInt32(kVK_Escape), forKey: "hotkeyCode")
        store.set(UInt32(controlKey), forKey: "hotkeyModifiers")
        let s = AppSettings(defaults: store)
        XCTAssertEqual(s.launcherHotkeyModifiers, 0)
        XCTAssertEqual(s.dockFocusHotkeyModifiers, UInt32(controlKey | shiftKey), "the other one is free")
        XCTAssertEqual(AppSettings(defaults: store).launcherHotkeyModifiers, 0, "and at the next start")
        XCTAssertFalse(s.isHotkeyTaken(code: UInt32(kVK_Escape), modifiers: UInt32(controlKey | shiftKey),
                                       byOtherThan: (s.dockFocusHotkeyCode, s.dockFocusHotkeyModifiers)), "setting your own again")
        XCTAssertTrue(s.isHotkeyTaken(code: UInt32(kVK_Escape), modifiers: UInt32(controlKey),
                                      byOtherThan: (s.dockFocusHotkeyCode, s.dockFocusHotkeyModifiers)), "the overlay toggle's")
    }
}
