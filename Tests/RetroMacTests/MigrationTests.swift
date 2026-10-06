import XCTest
@testable import RetroMac

/// Updating from 2.8.8 to 3.0 (Lastenheft 3.0, release acceptance): the themes, shortcuts and
/// choices of a 2.8 store come through, and the new defaults never take a shortcut of yours.
final class MigrationTests: XCTestCase {
    private var suite: String!
    private var store: UserDefaults!

    override func setUp() {
        suite = "retromac.migration.\(UUID().uuidString)"
        store = UserDefaults(suiteName: suite)
    }
    override func tearDown() { store.removePersistentDomain(forName: suite) }

    /// A store as 2.8.8 left it: a theme, a wallpaper choice, shortcuts of your own, and a
    /// switch 3.0 no longer has.
    private func fill288() {
        store.set(true, forKey: "dockEnabled")
        store.set("com.retromac.microsoft.windowsxp", forKey: "dockTheme")
        store.set(["com.retromac.microsoft.windowsxp": "bliss.jpg"], forKey: "themeWallpaperOverrides")
        store.set(UInt32(0x0F), forKey: "hotkeyCode")          // R
        store.set(UInt32(0x0300), forKey: "hotkeyModifiers")   // ⌘⇧
        store.set(true, forKey: "showHotkeyConflictTips")
    }

    func testA288StoreComesThrough() {
        fill288()
        let s = AppSettings(defaults: store)
        XCTAssertTrue(s.dockEnabled)
        XCTAssertEqual(s.dockTheme, "com.retromac.microsoft.windowsxp")
        XCTAssertEqual(s.themeWallpaperOverrides["com.retromac.microsoft.windowsxp"], "bliss.jpg")
        XCTAssertEqual(s.hotkeyCode, 0x0F)
        XCTAssertEqual(s.hotkeyModifiers, 0x0300)
        // The new actions come with their defaults where those are free.
        XCTAssertEqual(s.rescueHotkeyCode, 0x0F)
        XCTAssertEqual(s.rescueHotkeyModifiers, 0x1900, "⌃⌥⌘R")
        XCTAssertEqual(s.switcherHotkeyCode, 0x30)
        XCTAssertEqual(s.switcherHotkeyModifiers, 0x1800, "⌃⌥Tab")
        XCTAssertEqual(s.switcherOffThemes, [])
    }

    /// Your overlay toggle on ⌃⌥Tab stays yours: the switcher starts without a shortcut.
    func testANewDefaultNeverTakesYourShortcut() {
        fill288()
        store.set(UInt32(0x30), forKey: "hotkeyCode")
        store.set(UInt32(0x1800), forKey: "hotkeyModifiers")
        store.set(UInt32(0x0F), forKey: "exposeHotkeyCode")
        store.set(UInt32(0x1900), forKey: "exposeHotkeyModifiers")
        let s = AppSettings(defaults: store)
        XCTAssertEqual(s.hotkeyModifiers, 0x1800)
        XCTAssertEqual(s.switcherHotkeyModifiers, 0)
        XCTAssertEqual(s.rescueHotkeyModifiers, 0, "your Exposé shortcut was on ⌃⌥⌘R")
        XCTAssertEqual(AppSettings(defaults: store).switcherHotkeyModifiers, 0, "and at the next start; set it yourself in Settings ▸ Shortcuts")
    }

    /// Once you set the switcher yourself, your choice stands, conflict or not.
    func testYourOwnSwitcherShortcutStands() {
        fill288()
        store.set(UInt32(0x30), forKey: "hotkeyCode")
        store.set(UInt32(0x1800), forKey: "hotkeyModifiers")
        store.set(UInt32(0x1800), forKey: "switcherHotkeyModifiers")
        XCTAssertEqual(AppSettings(defaults: store).switcherHotkeyModifiers, 0x1800)
    }
}
