import AppKit
import SkyLightBridge

/// The theme on chosen Spaces only (Settings ▸ General ▸ Spaces, or Themes ▸ On This Space in
/// the menu). The other Spaces stay plain macOS.
///
/// macOS has no setting for it, so RetroMac does it in two parts:
/// - **Its own windows** (dock, desktop layers, panels, widgets) normally join every Space. Here
///   they lose that and are put onto the theme's Space through the window server, so they stay
///   there and slide away with it.
/// - **What a theme changes for the whole Mac** is switched with the Space: the shader pauses,
///   the Mac's Dock and menu bar come back, and the cursor, title bars and window borders are
///   the system's again. The wallpaper follows by itself (`ThemeManager`). The appearance,
///   accent colour, Terminal profile, Finder tweaks and system icons stay as the theme set them:
///   switching those costs seconds and restarts the Finder and Dock.
final class ThemeSpaces {
    static let shared = ThemeSpaces()

    /// Whether the theme shows on the Space `current`. Pure, for the tests.
    static func showsTheme(chosenOnly: Bool, chosen: [String], current: String?) -> Bool {
        guard chosenOnly, let current else { return true }   // no answer from the window server: as before
        return chosen.contains(current)
    }

    /// The Space the main display shows, as the uuid macOS keeps across restarts.
    /// ponytail: the main display decides for all of them; with "Displays have separate Spaces"
    /// a second display follows the main one. Per display if anyone asks.
    static var currentSpace: String? {
        guard let display = (NSScreen.primaryDisplay ?? NSScreen.main)?.displayUUID else { return nil }
        return skb_copy_current_space_uuid(display as CFString) as String?
    }

    /// Every Space that exists, in the window server's order, for "Desktop 3" in Settings.
    static var allSpaces: [String] { (skb_copy_space_uuids() as? [String]) ?? [] }

    var showsThemeHere: Bool {
        let s = AppSettings.shared
        return Self.showsTheme(chosenOnly: s.themeOnChosenSpaces, chosen: s.themeSpaces, current: Self.currentSpace)
    }

    /// True while RetroMac holds the theme back because this Space is not one of them.
    private(set) var heldBack = false
    /// When the theme last went or came back on a Space switch; the Mac's Dock takes a moment
    /// to settle after that, and the Dock watcher must not read the moment as a change of its own.
    private(set) var lastSwitch = Date.distantPast
    private let bound = NSHashTable<NSWindow>.weakObjects()   // windows we took off "every Space"
    private var boundTo: UInt64 = 0
    private var observers: [NSObjectProtocol] = []
    private var sweep: Timer?
    private var pending: DispatchWorkItem?

    func start() {
        guard observers.isEmpty else { return }
        observers = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.schedule() },
            NotificationCenter.default.addObserver(forName: .dockThemeChanged, object: nil, queue: .main) { [weak self] _ in self?.schedule() },
        ]
        evaluate()
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluate() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func evaluate() {
        let s = AppSettings.shared
        let themeOn = s.dockEnabled && ThemeManager.shared.activeTheme != nil
        guard s.themeOnChosenSpaces, themeOn else { release(themeOn: themeOn); return }
        let here = showsThemeHere
        // The windows live on this Space when it is one of the theme's, else on the first of
        // them that still exists.
        let target = here ? Self.currentSpace : s.themeSpaces.first { skb_space_id_for_uuid($0 as CFString) != 0 }
        boundTo = target.map { skb_space_id_for_uuid($0 as CFString) } ?? 0
        for w in bound.allObjects { _ = skb_move_window_to_space(UInt32(w.windowNumber), boundTo) }
        bindNewWindows()
        if sweep == nil {
            // New theme windows (a widget opened, the dock rebuilt) join every Space again.
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.bindNewWindows() }
            RunLoop.main.add(t, forMode: .common)
            sweep = t
        }
        setHeldBack(!here)
    }

    /// Back to every Space: the setting is off, or the theme is. With the theme off, its Dock,
    /// menu bar and cursor are already the Mac's (`DockController.stop`), so only the shader
    /// comes back.
    private func release(themeOn: Bool) {
        sweep?.invalidate(); sweep = nil
        for w in bound.allObjects { w.collectionBehavior.insert(.canJoinAllSpaces) }
        bound.removeAllObjects()
        boundTo = 0
        if themeOn { setHeldBack(false); return }
        guard heldBack else { return }
        heldBack = false
        AppDelegate.shared?.setEffectPausedForSpace(false)
        WindowBorderController.shared.update()
    }

    /// RetroMac's own controls stay on every Space: the menu-bar popover, the flyout and its
    /// button, menus. Everything else that joins every Space belongs to the theme.
    private static let ownControls: Set<String> = ["NSStatusBarWindow", "_NSPopoverWindow", "LauncherWindow",
                                                   "NSMenuWindowManagerWindow", "NSCarbonMenuWindow"]

    private func bindNewWindows() {
        guard boundTo != 0 else { return }
        let launcher = FloatingLauncherButton.shared.buttonWindow
        for w in NSApp.windows where w.collectionBehavior.contains(.canJoinAllSpaces) && !bound.contains(w) {
            guard w !== launcher, !Self.ownControls.contains(String(describing: type(of: w))) else { continue }
            w.collectionBehavior.remove(.canJoinAllSpaces)
            bound.add(w)
            _ = skb_move_window_to_space(UInt32(w.windowNumber), boundTo)
        }
    }

    private func setHeldBack(_ back: Bool) {
        guard back != heldBack else { return }
        heldBack = back
        lastSwitch = Date()
        let s = AppSettings.shared
        AppDelegate.shared?.setEffectPausedForSpace(back)
        if DockController.shared.hidesSystemDock { CoreDockBridge.setAutoHide(!back) }
        if s.hideMenuBar { DispatchQueue.global(qos: .userInitiated).async { SystemUIHelper.setMenuBarAutoHide(!back) } }
        if back { CursorThemeManager.shared.restore() }
        else if let config = ThemeManager.shared.activeTheme?.config { CursorThemeManager.shared.apply(for: config) }
        WindowBorderController.shared.update()   // and the title bars with it
        ThemeManager.shared.applyWallpaper(spaceChange: true)   // this Space's picture, also without a Space switch
    }

    /// "Desktop 3", or nil for a Space that is gone.
    static func label(for space: String) -> String? {
        guard let i = allSpaces.firstIndex(of: space) else { return nil }
        return "Desktop \(i + 1)"
    }
}
