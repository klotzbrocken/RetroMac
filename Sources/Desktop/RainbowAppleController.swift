import AppKit
import ApplicationServices

/// Covers the system Apple-menu glyph (top-left of the menu bar) with the classic
/// rainbow Apple for Apple-OS themes. One borderless, **click-through** window per
/// menu-bar screen, drawn just above the menu bar. Clicks pass through
/// (`ignoresMouseEvents`) so the real Apple menu still opens underneath.
///
/// Position + size come from Accessibility: the Apple menu is the first item of an
/// app's AXMenuBar; its frame gives the exact rect to sit on. The Apple item is the
/// same for every app, so we query a real app that HAS a menu bar (Finder/whatever
/// is frontmost) and never our own LSUIElement agent — that's why a freshly-shown
/// overlay used to be misplaced until a fullscreen round-trip put a real app in front.
/// Falls back to fixed geometry (left edge + status-bar height) only if AX fails.
///
/// Shown only when: an Apple-OS theme is active, the dock is on, the menu bar is NOT
/// hidden, and not in dock-only mode.
final class RainbowAppleController {
    static let shared = RainbowAppleController()

    /// Rendered glyph height in points — sized to match the system Apple mark. Width
    /// follows the PNG aspect ratio. Tune here if it looks large/small.
    private let glyphHeightPt: CGFloat = 17
    /// Nudge the logo up by a couple of points so it sits exactly on the white glyph
    /// (the system mark is centred a touch higher than the menu-item rect's centre).
    private let glyphYOffset: CGFloat = 1.0
    private let fallbackGlyphCenterX: CGFloat = 14   // only used if AX fails

    private var windows: [NSWindow] = []
    private var observers: [NSObjectProtocol] = []
    private var imageCache: [String: NSImage] = [:]

    private init() {}

    /// Theme-independent: shown whenever a style is selected (1 = rainbow, 2 = aqua)
    /// and a menu bar is visible. Driven by `menuBarAppleStyle` (flyout cycle + Settings).
    func update() {
        let s = AppSettings.shared
        let wantShow = s.menuBarAppleStyle != 0 && !s.hideMenuBar
        guard wantShow else { hide(); return }
        // A hidden/auto-hiding system menu bar means there is no Apple glyph to cover —
        // the overlay would float over a bare desktop. Checked off-main (shells out).
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let barHidden = SystemUIHelper.isMenuBarAutoHidden()
            DispatchQueue.main.async {
                if barHidden { self?.hide() } else { self?.rebuild() }
            }
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        observers.removeAll()
    }

    // MARK: - Build / position

    private func menuScreens() -> [NSScreen] {
        NSScreen.screensHaveSeparateSpaces ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
    }

    /// The rect to overlay on a given screen: the exact AX Apple-item rect when it
    /// lands on this screen; else the AX geometry transplanted onto this screen (same
    /// left offset + width, but THIS screen's own menu-bar height — bar heights differ
    /// between the notched internal panel and external monitors); else fixed geometry.
    private func itemRect(for screen: NSScreen, axFrame: NSRect?) -> NSRect {
        if let f = axFrame, screen.frame.intersects(f) { return f.integral }   // integral → pixel-aligned
        // This screen's real menu-bar height (visibleFrame excludes it at the top).
        let ownBarH = screen.frame.maxY - screen.visibleFrame.maxY
        let menuH = ownBarH > 1 ? ownBarH : NSStatusBar.system.thickness
        if let f = axFrame,
           let src = NSScreen.screens.first(where: { $0.frame.intersects(f) }) {
            let relX = f.minX - src.frame.minX   // Apple item's offset from its screen's left edge
            return NSRect(x: screen.frame.minX + relX, y: screen.frame.maxY - menuH,
                          width: f.width, height: menuH).integral
        }
        return NSRect(x: screen.frame.minX, y: screen.frame.maxY - menuH,
                      width: fallbackGlyphCenterX * 2, height: menuH).integral
    }

    private func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()

        let axFrame = appleMenuFrameCocoa()
        for screen in menuScreens() {
            windows.append(makeWindow(itemRect: itemRect(for: screen, axFrame: axFrame)))
        }

        if observers.isEmpty {
            observers.append(NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main) { [weak self] _ in self?.update() })
            let ws = NSWorkspace.shared.notificationCenter
            ws.addObserver(self, selector: #selector(reposition),
                           name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            // A real app coming to the front means the AX menu bar is now queryable —
            // re-assert position so a launch-time placement (when our agent was front)
            // self-corrects without needing a manual fullscreen round-trip.
            ws.addObserver(self, selector: #selector(reposition),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        }

        // Belt-and-suspenders: re-assert once shortly after show, in case AX/menu-bar
        // geometry wasn't settled yet at first build.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.reposition() }
    }

    /// Re-query AX and move the existing windows in place (no teardown).
    @objc private func reposition() {
        guard !windows.isEmpty else { return }
        let axFrame = appleMenuFrameCocoa()
        for win in windows {
            let screen = win.screen ?? NSScreen.main ?? NSScreen.screens.first
            guard let screen else { continue }
            let rect = itemRect(for: screen, axFrame: axFrame)
            if win.frame != rect { win.setFrame(rect, display: true) }
            layoutImage(in: win, itemRect: rect)
        }
    }

    private func makeWindow(itemRect: NSRect) -> NSWindow {
        let win = NSWindow(contentRect: itemRect, styleMask: .borderless,
                           backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let content = NSView(frame: NSRect(origin: .zero, size: itemRect.size))
        let iv = RainbowAppleView()
        iv.image = appleImage()
        content.addSubview(iv)
        win.contentView = content
        layoutImage(in: win, itemRect: itemRect)
        win.orderFrontRegardless()
        return win
    }

    /// Center the rainbow Apple in the window at the fixed glyph height.
    private func layoutImage(in win: NSWindow, itemRect: NSRect) {
        guard let iv = win.contentView?.subviews.first as? RainbowAppleView else { return }
        win.contentView?.frame = NSRect(origin: .zero, size: itemRect.size)
        let img = appleImage()
        let aspect = img.size.height > 0 ? img.size.width / img.size.height : 0.86
        let h = glyphHeightPt
        let w = (h * aspect).rounded()
        iv.frame = NSRect(x: ((itemRect.width - w) / 2).rounded(),
                          y: ((itemRect.height - h) / 2 + glyphYOffset).rounded(),
                          width: w, height: h)
    }

    // MARK: - Accessibility: exact Apple-menu rect

    /// Frame of the Apple menu item in Cocoa global coords. Queries a real app that
    /// has a menu bar (never our own agent), so it's correct even right after launch.
    private func appleMenuFrameCocoa() -> NSRect? {
        guard AXIsProcessTrusted() else { return nil }
        let own = Bundle.main.bundleIdentifier
        var apps: [NSRunningApplication] = []
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != own {
            apps.append(front)
        }
        apps += NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != own
        }
        for app in apps {
            if let rect = appleFrame(forPID: app.processIdentifier) { return rect }
        }
        return nil
    }

    private func appleFrame(forPID pid: pid_t) -> NSRect? {
        let axApp = AXUIElementCreateApplication(pid)
        var mbRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &mbRef) == .success,
              let mb = mbRef, CFGetTypeID(mb) == AXUIElementGetTypeID() else { return nil }
        let menuBar = mb as! AXUIElement

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement], let apple = children.first else { return nil }

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(apple, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(apple, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, CFGetTypeID(posVal) == AXValueGetTypeID(),
              let sizeVal = sizeRef, CFGetTypeID(sizeVal) == AXValueGetTypeID() else { return nil }

        var pos = CGPoint.zero
        var sz = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &sz)
        guard sz.width > 0, sz.height > 0 else { return nil }

        // AX: top-left origin relative to the primary display (the one at (0,0)).
        let primaryH = (NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.main)?.frame.height ?? 0
        return NSRect(x: pos.x, y: primaryH - pos.y - sz.height, width: sz.width, height: sz.height)
    }

    // MARK: - Image

    private func appleImage() -> NSImage {
        let name: String
        switch AppSettings.shared.menuBarAppleStyle {
        case 2: name = "aqua_apple"
        case 3: name = "aqua_classic_apple"
        case 4: name = "apple_hell"
        default: name = "rainbow_apple"
        }
        if let cached = imageCache[name] { return cached }
        let img: NSImage
        if let path = Bundle.main.path(forResource: name, ofType: "png"),
           let loaded = NSImage(contentsOfFile: path) {
            img = loaded
        } else {
            img = drawnFallbackApple()
        }
        imageCache[name] = img
        return img
    }

    /// Fallback only if the bundled PNG is missing: six-stripe rainbow from the
    /// `apple.logo` SF Symbol silhouette.
    private func drawnFallbackApple() -> NSImage {
        let size = NSSize(width: 200, height: 238)
        let stripes: [NSColor] = [
            NSColor(srgbRed: 0.380, green: 0.733, blue: 0.275, alpha: 1),
            NSColor(srgbRed: 0.992, green: 0.722, blue: 0.153, alpha: 1),
            NSColor(srgbRed: 0.961, green: 0.510, blue: 0.122, alpha: 1),
            NSColor(srgbRed: 0.878, green: 0.227, blue: 0.243, alpha: 1),
            NSColor(srgbRed: 0.588, green: 0.239, blue: 0.592, alpha: 1),
            NSColor(srgbRed: 0.000, green: 0.616, blue: 0.863, alpha: 1),
        ]
        let img = NSImage(size: size)
        img.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        let stripeH = size.height / CGFloat(stripes.count)
        for (i, c) in stripes.enumerated() {
            c.setFill()
            NSRect(x: 0, y: size.height - CGFloat(i + 1) * stripeH,
                   width: size.width, height: stripeH).fill()
        }
        let cfg = NSImage.SymbolConfiguration(pointSize: 220, weight: .black)
        if let sym = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) {
            sym.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
        }
        img.unlockFocus()
        return img
    }
}

/// Draws the rainbow Apple with high-quality interpolation at the view's exact
/// backing-pixel size, so the down-scale to ~16pt stays crisp instead of the soft
/// result NSImageView's default minification produced.
private final class RainbowAppleView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // never intercept clicks
    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
}
