import AppKit
import ApplicationServices

/// The CDE workspace under the windows (Lastenheft 3.0, CDE-09 and CDE-10): a right-click
/// posts the Workspace Menu, and every minimised window lies on it as an icon, top left, the
/// way dtwm laid them out. A click on an icon posts its window menu, a double-click restores
/// the window. Measured off `solcdegeneral.png`: a 60 × 59 raised box with the 48 pt picture
/// in an etched frame, a 20 pt label box under it, one icon every 85 pt.
///
/// Like the themed desktop icons of the other themes, the layer sits just under the normal
/// windows and takes the clicks that land on the bare desktop. QNX's Photon uses it too: there a
/// right-click posts the Launch menu (QNX-05) and no icons lie about, the taskbar has the windows.
final class CDEDesktop {
    enum Mode { case cde, photon }
    static let shared = CDEDesktop()
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private(set) var mode: Mode = .cde

    func show(_ mode: Mode) {
        self.mode = mode
        guard let screen = NSScreen.screens.first else { return }
        if panel == nil {
            let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            // The themed desktop's band: under the application windows, and not at desktop level,
            // where Sonoma takes a click as "show the desktop" (see DesktopIconsController).
            p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) - 4)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = false
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.contentView = CDEDesktopView(frame: NSRect(origin: .zero, size: screen.frame.size))
            panel = p
            let nc = NotificationCenter.default
            observers = [
                nc.addObserver(forName: .minimizedWindowsChanged, object: nil, queue: .main) { [weak self] _ in self?.reload() },
                nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in guard let self else { return }; self.show(self.mode) },
            ]
        }
        panel?.setFrame(screen.frame, display: false)
        panel?.contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
        reload()
        panel?.orderFrontRegardless()
    }

    /// With a mode, only when the layer is that theme's: the CDE and Photon controllers both tidy up
    /// at every theme change and must not take the other one's desktop away.
    func hide(_ only: Mode? = nil) {
        if let only, only != mode { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        CDEMenu.close()
        panel?.orderOut(nil)
        panel = nil
    }

    private func reload() {
        guard let view = panel?.contentView as? CDEDesktopView, let screen = NSScreen.screens.first else { return }
        view.top = screen.frame.maxY - screen.visibleFrame.maxY
        view.bottom = screen.frame.height - (screen.visibleFrame.minY - screen.frame.minY) - CDEFrontPanelView.size.height
        view.entries = mode == .cde ? MinimizedWindowTracker.shared.entries : []
    }

    // MARK: Menus

    /// dtwm's window menu. What macOS cannot do for another app's window (move or size by
    /// keyboard, lower, workspaces) stays in the menu, insensitive, as dtwm showed what did not apply.
    static func windowMenu(restore: (() -> Void)?, minimize: (() -> Void)?, maximize: (() -> Void)?, close: (() -> Void)?) -> [CDEMenuItem] {
        func item(_ t: String, _ a: (() -> Void)?) -> CDEMenuItem { CDEMenuItem(title: t, enabled: a != nil, action: a) }
        return [item("Restore", restore), item("Move", nil), item("Size", nil), item("Minimize", minimize),
                item("Maximize", maximize), item("Lower", nil), .separator,
                item("Occupy Workspace...", nil), item("Occupy All Workspaces", nil), item("Unoccupy Workspace", nil),
                .separator, item("Close", close)]
    }

    /// The Workspace Menu of Solaris 8, in its order. The cascades carry the subpanels' contents,
    /// as CDE built them from the Front Panel; "Add Item to Menu" and "Customize Menu" give way
    /// to RetroMac's own settings, named as such, and "Log out" ends the theme (CDE-11).
    static func workspaceMenu(theme t: ThemeBundle) -> [CDEMenuItem] {
        func mi(_ name: String) -> NSImage? { t.iconResource("mi_\(name).png").flatMap { NSImage(contentsOf: $0) } }
        func app(_ title: String, _ icon: String, _ bundleID: String) -> CDEMenuItem? {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) == nil ? nil
                : CDEMenuItem(title: title, icon: mi(icon), action: CDEActions.app(bundleID))
        }
        func sub(_ kind: CDESubpanel.Kind) -> CDEMenuItem {
            CDEMenuItem(title: kind.title, submenu: CDESubpanel.items(for: kind, theme: t).map { CDEMenuItem(title: $0.title, icon: $0.icon, action: $0.action) })
        }
        let applications: [CDEMenuItem?] = [
            CDEMenuItem(title: "Application Manager", icon: mi("appmgr"), action: { AppFolderController.shared.show() }),
            CDEMenuItem(title: "Audio Control", icon: mi("audioctl"), action: CDEActions.settings("com.apple.Sound-Settings.extension")),
            app("Audio and Video", "audiovideo", "com.apple.QuickTimePlayerX"),
            app("Calculator", "calculator", "com.apple.calculator"),
            app("Calendar", "calendar", "com.apple.iCal"),
            app("Image Viewer", "imageviewer", "com.apple.Preview"),
            CDEMenuItem(title: "Clock", icon: mi("owclock"), action: CDEFrontPanelView.openClock),
            app("Snapshot", "snapshot", "com.apple.screenshot.launcher"),
            app("Text Editor", "texteditor", "com.apple.TextEdit"),
            app("Text Note", "textnote", "com.apple.Stickies"),
            app("Voice Note", "voicenote", "com.apple.VoiceMemos"),
        ]
        let fm = FileManager.default
        let places: [(String, URL?)] = [("Home Folder", CDEActions.home),
             ("Desktop", fm.urls(for: .desktopDirectory, in: .userDomainMask).first),
             ("Documents", fm.urls(for: .documentDirectory, in: .userDomainMask).first),
             ("Downloads", fm.urls(for: .downloadsDirectory, in: .userDomainMask).first),
             ("Applications", URL(fileURLWithPath: "/Applications"))]
        let folders = places.compactMap { title, url in url.map { CDEMenuItem(title: title, icon: NSWorkspace.shared.icon(forFile: $0.path), action: CDEActions.open($0)) } }
        let minimized = MinimizedWindowTracker.shared.entries
        let windows: [CDEMenuItem] = [
            CDEMenuItem(title: "Show All Windows", action: CDEActions.missionControl),
            CDEMenuItem(title: "Restore All Icons", enabled: !minimized.isEmpty, action: {
                Set(minimized.map(\.bundleID)).forEach(MinimizedWindowTracker.shared.restoreWindows(for:))
            }),
            CDEMenuItem(title: "Minimize/Restore Front Panel", action: { CDEFrontPanelController.shared.toggleMinimized() }),
        ]
        return [CDEMenuItem(title: "Applications", submenu: applications.compactMap { $0 }),
                sub(.cards), sub(.files), CDEMenuItem(title: "Folders", submenu: folders),
                sub(.help), sub(.hosts), sub(.links), sub(.mail), sub(.tools), .separator,
                CDEMenuItem(title: "Windows", submenu: windows), .separator,
                CDEMenuItem(title: "RetroMac Settings...", icon: NSApplication.shared.applicationIconImage, action: { AppDelegate.shared?.launcherOpenSettings() }),
                .separator,
                CDEMenuItem(title: "Lock Display", icon: mi("lock"), action: { ScreensaverController.shared.start() }),
                CDEMenuItem(title: "Exit Theme...", icon: mi("exit"), action: { AppDelegate.shared?.launcherDisableTheme() })]
    }
}

/// The desktop layer: draws the minimised windows' icons and posts the menus.
private final class CDEDesktopView: NSView {
    var entries: [MinimizedWindowTracker.Entry] = [] { didSet { needsDisplay = true } }
    var top: CGFloat = 0       // the menu bar's strip, view points from the top
    var bottom: CGFloat = 0    // where the Front Panel begins

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private static let box = NSSize(width: 60, height: 59), labelH: CGFloat = 20, pitch: CGFloat = 85, columnPitch: CGFloat = 66
    private static let face = NSColor(srgbRed: 0xAD / 255, green: 0xB5 / 255, blue: 0xC6 / 255, alpha: 1)
    private static let light = NSColor(srgbRed: 0xDE / 255, green: 0xDE / 255, blue: 0xE7 / 255, alpha: 1)
    private static let dark = NSColor(srgbRed: 0x5A / 255, green: 0x63 / 255, blue: 0x6B / 255, alpha: 1)

    /// Icon boxes (picture and label together), top to bottom, then the next column.
    private func slots() -> [NSRect] {
        let perColumn = max(1, Int((bottom - top - 4) / Self.pitch))
        return entries.indices.map { i in
            NSRect(x: 2 + CGFloat(i / perColumn) * Self.columnPitch, y: top + 4 + CGFloat(i % perColumn) * Self.pitch,
                   width: Self.box.width, height: Self.box.height + Self.labelH)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .high
        for (r, e) in zip(slots(), entries) {
            let pic = NSRect(x: r.minX, y: r.minY, width: Self.box.width, height: Self.box.height)
            let label = NSRect(x: r.minX, y: pic.maxY, width: r.width, height: Self.labelH)
            for b in [pic, label] { Self.face.setFill(); b.fill(); raised(b) }
            // The etched frame round the picture, 4 pt in.
            let etch = pic.insetBy(dx: 4, dy: 4)
            Self.dark.setStroke(); NSBezierPath(rect: NSRect(x: etch.minX + 0.5, y: etch.minY + 0.5, width: etch.width - 2, height: etch.height - 2)).stroke()
            Self.light.setStroke(); NSBezierPath(rect: NSRect(x: etch.minX + 1.5, y: etch.minY + 1.5, width: etch.width - 2, height: etch.height - 2)).stroke()
            Self.picture(for: e)?.draw(in: NSRect(x: pic.minX + 6, y: pic.minY + 6, width: 48, height: 48), from: .zero,
                                       operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            // The label is cut off at the box, as dtwm cut "Calculator" to "Calcula".
            let attrs: [NSAttributedString.Key: Any] = [.font: CDEMenu.font, .foregroundColor: NSColor.black]
            let name = (e.title.isEmpty ? NSRunningApplication(processIdentifier: e.pid)?.localizedName ?? "" : e.title) as NSString
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: label.minX + 4, y: label.minY, width: label.width - 8, height: label.height).clip()
            name.draw(at: NSPoint(x: label.minX + 4, y: label.minY + ((label.height - name.size(withAttributes: attrs).height) / 2).rounded()), withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// A 2 pt raised bevel: lit top and left, shaded right and bottom.
    private func raised(_ r: NSRect) {
        Self.light.setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 2).fill()
        NSRect(x: r.minX, y: r.minY, width: 2, height: r.height).fill()
        Self.dark.setFill()
        NSRect(x: r.maxX - 2, y: r.minY + 1, width: 2, height: r.height - 1).fill()
        NSRect(x: r.minX + 1, y: r.maxY - 1, width: r.width - 1, height: 1).fill()
    }

    /// The theme's picture for the app if it maps one, else the app's own icon (ICO-07).
    private static func picture(for e: MinimizedWindowTracker.Entry) -> NSImage? {
        if ThemeManager.shared.activeTheme?.config.iconMappings[e.bundleID] != nil {
            return ThemeManager.shared.icon(for: e.bundleID, size: 48)
        }
        return NSRunningApplication(processIdentifier: e.pid)?.icon
    }

    // MARK: Mouse

    private func screenPoint(_ p: NSPoint) -> NSPoint {
        let f = window?.frame ?? .zero
        return NSPoint(x: f.minX + p.x, y: f.maxY - p.y)
    }

    override func mouseDown(with event: NSEvent) {
        CDESubpanel.closeAll()   // a click on the bare desktop closes an open subpanel
        let p = convert(event.locationInWindow, from: nil)
        guard let i = slots().firstIndex(where: { $0.contains(p) }) else { return }
        let e = entries[i]
        if event.clickCount >= 2 { MinimizedWindowTracker.shared.activate(e); return }
        postIconMenu(e, slot: slots()[i])
    }

    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = slots().firstIndex(where: { $0.contains(p) }) { postIconMenu(entries[i], slot: slots()[i]); return }
        if CDEDesktop.shared.mode == .photon { PhotonLaunchMenu.show(at: screenPoint(p)); return }
        guard let theme = ThemeManager.shared.activeTheme else { return }
        CDEMenu.show(CDEDesktop.workspaceMenu(theme: theme), title: "Workspace Menu", at: screenPoint(p))
    }

    /// The icon's window menu, under the label; a second click on the icon restores the window.
    private func postIconMenu(_ e: MinimizedWindowTracker.Entry, slot: NSRect) {
        let restore = { MinimizedWindowTracker.shared.activate(e) }
        var close: (() -> Void)?
        var ref: CFTypeRef?
        if !e.isAppLevel, AXUIElementCopyAttributeValue(e.window, kAXCloseButtonAttribute as CFString, &ref) == .success, let ref {
            let button = ref as! AXUIElement
            close = { AXUIElementPerformAction(button, kAXPressAction as CFString) }
        }
        let tl = screenPoint(NSPoint(x: slot.minX, y: slot.maxY))
        let br = screenPoint(NSPoint(x: slot.maxX, y: slot.minY))
        CDEMenu.show(CDEDesktop.windowMenu(restore: restore, minimize: nil, maximize: nil, close: close),
                     at: tl, anchor: NSRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y), onAnchorDoubleClick: restore)
    }
}
