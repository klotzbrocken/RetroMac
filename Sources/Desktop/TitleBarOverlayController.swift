import AppKit
import ApplicationServices
import SkyLightBridge

/// EXPERIMENT: a Platinum (Mac OS 9) or Luna (Windows XP) title bar laid over the real title bar
/// of every window on screen. Nothing in the other app changes; the overlay is our own panel,
/// ordered directly above its target the way the window borders are, and the three controls
/// drive the real window through the Accessibility API (close, minimise, zoom; dragging the bar
/// moves it). Where there is no control the panel lets clicks through to the real bar, so the
/// native drag and double-click keep working.
///
/// Why the corners are painted rather than removed: the two global corner keys the themes use
/// (NSConvolutionOverride1, NSSplitViewItemGlassMinimumCornerRadius) can make a window's corners
/// rounder on macOS 27 but not squarer than the system's own ~10 pt — 0, 0.5, 1 and 4 all render
/// the default, 30 renders 30 (tested 15 Sep 2026, TextEdit and Finder after a relaunch). So
/// the bar covers the top corners and the border paints the bottom ones.
///
/// Known limits, on purpose: the strip is the theme's own height (22 / 30 pt) from the top edge,
/// so on a window whose toolbar shares the title bar (Safari, Finder) it covers the top of that
/// toolbar. And the real traffic lights underneath are hidden but not gone: the strip above them
/// is a dead zone the overlay handles itself, so a click there never reaches them.
final class TitleBarOverlayController {

    static let shared = TitleBarOverlayController()
    private init() {}

    enum Style { case platinum, luna }

    private final class Overlay {
        let panel: NSPanel
        let view: TitleBarOverlayView
        var bounds: CGRect          // target bounds, top-left global
        var level: Int32
        init(panel: NSPanel, view: TitleBarOverlayView, bounds: CGRect, level: Int32) {
            self.panel = panel; self.view = view; self.bounds = bounds; self.level = level
        }
    }

    private var running = false
    var isRunning: Bool { running && style != nil }
    private var style: Style?
    private var excluded: Set<String> = []
    private var overlays: [CGWindowID: Overlay] = [:]
    private var axWindows: [CGWindowID: AXUIElement] = [:]
    private var wsTokens: [NSObjectProtocol] = []
    private var syncTimer: Timer?
    private var mouseMonitor: Any?

    // MARK: - Lifecycle

    static func style(for key: String) -> Style? {
        switch key {
        case "macos9": return .platinum
        case "winxp":  return .luna
        default:       return nil
        }
    }

    func update() {
        let want = AppSettings.shared.themeTitleBars
            && AppSettings.shared.dockEnabled
            && !AppSettings.shared.dockOnly
        if want { start() } else { stop() }
    }

    private func start() {
        let newStyle = Self.style(for: RetroFrameTheme.key())
        excluded = Set(AppSettings.shared.themeTitleBarsExcludedApps)
        if running {
            if newStyle != style { style = newStyle; stopOverlays() }
            sync()
            return
        }
        style = newStyle
        running = true
        WindowBorderController.shared.ensureServerEvents()   // move/resize/minimise arrive through it
        WindowBorderController.shared.ensureObservers()      // and closed windows, through Accessibility
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            wsTokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.sync() })
        }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.sync() }
        RunLoop.main.add(t, forMode: .common)
        syncTimer = t
        // The panels ignore the mouse except over a control; this is what flips them.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.routeMouse(NSEvent.mouseLocation)
        }
        sync()
    }

    private func stop() {
        guard running else { return }
        running = false
        syncTimer?.invalidate(); syncTimer = nil
        let nc = NSWorkspace.shared.notificationCenter
        wsTokens.forEach { nc.removeObserver($0) }
        wsTokens.removeAll()
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        stopOverlays()
        WindowBorderController.shared.releaseObserversIfIdle()
    }

    private func stopOverlays() {
        for o in overlays.values { o.panel.orderOut(nil) }
        overlays.removeAll()
        axWindows.removeAll()
    }

    // MARK: - Sync

    private func sync() {
        guard running, let style else { return }
        let windows = Self.onScreenWindows()
        var infoByID = [CGWindowID: WindowInfo](minimumCapacity: windows.count)
        for w in windows { infoByID[w.id] = w }

        let candidates = windows.map { $0.id }
        PrivateWindowAPI.requestNotifications(for: candidates)
        var outWID = [UInt32](repeating: 0, count: candidates.count)
        var outLevel = [Int32](repeating: 0, count: candidates.count)
        let count = candidates.withUnsafeBufferPointer { cand in
            outWID.withUnsafeMutableBufferPointer { w in
                outLevel.withUnsafeMutableBufferPointer { l in
                    Int(skb_filter_windows(cand.baseAddress, Int32(cand.count),
                                            w.baseAddress, l.baseAddress, Int32(cand.count)))
                }
            }
        }
        // The front window: the first suitable one, in z-order, that belongs to the active app.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        var frontWID: CGWindowID = 0
        var suitable = Set<CGWindowID>()
        for i in 0..<count {
            let wid = outWID[i]
            guard let info = infoByID[wid] else { continue }
            if frontWID == 0, info.pid == frontPID { frontWID = wid }
            if excluded.contains(info.bundleID) { continue }
            suitable.insert(wid)
            apply(info, level: outLevel[i], style: style, isFront: wid == frontWID)
        }
        for (wid, o) in overlays where !suitable.contains(wid) {
            o.panel.orderOut(nil)
            overlays.removeValue(forKey: wid)
            axWindows.removeValue(forKey: wid)
        }
    }

    private func apply(_ info: WindowInfo, level: Int32, style: Style, isFront: Bool) {
        // Skip full-screen / desktop-sized windows, like the borders do.
        if let scr = NSScreen.screens.first(where: { $0.frame.width >= info.bounds.width }),
           info.bounds.width >= scr.frame.width - 1, info.bounds.height >= scr.frame.height - 1 {
            drop(for: info.id); return
        }
        let frame = Self.barFrame(for: info.bounds, style: style)
        let title = info.title.isEmpty ? (axTitle(info.id, pid: info.pid) ?? info.ownerName) : info.title
        let icon = style == .luna ? NSRunningApplication(processIdentifier: info.pid)?.icon : nil

        if let o = overlays[info.id] {
            o.bounds = info.bounds
            if o.panel.frame != frame { o.panel.setFrame(frame, display: false) }
            // Re-assert the order every pass: when the target's app comes to the front its
            // windows rise above ours, and nothing but this puts the bar back on top.
            o.level = level
            order(o, above: info.id)
            o.view.configure(style: style, title: title, icon: icon, isFront: isFront,
                             radius: WindowBorderController.windowCornerRadius())
            return
        }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        let view = TitleBarOverlayView(frame: NSRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        view.configure(style: style, title: title, icon: icon, isFront: isFront,
                       radius: WindowBorderController.windowCornerRadius())
        view.onAction = { [weak self] kind in self?.perform(kind, on: info.id, pid: info.pid) }
        view.onDrag = { [weak self] delta in self?.drag(info.id, pid: info.pid, by: delta) }
        view.onDragEnd = { [weak self] in self?.dragOrigin = nil }
        view.onLeave = { [weak panel] in panel?.ignoresMouseEvents = true }
        panel.contentView = view
        let o = Overlay(panel: panel, view: view, bounds: info.bounds, level: level)
        overlays[info.id] = o
        panel.orderFrontRegardless()
        order(o, above: info.id)
    }

    /// Directly above the target, at the target's level, so a buried window's bar is buried with
    /// it. AppKit's cross-application ordering does what the SkyLight transaction does for the
    /// border windows; the transaction itself leaves an AppKit window invisible.
    private func order(_ o: Overlay, above target: CGWindowID) {
        o.panel.level = NSWindow.Level(rawValue: Int(o.level))
        o.panel.order(.above, relativeTo: Int(target))
    }

    /// Height of the strip: the theme's title bar, but never less than the real one (28 pt), or
    /// the bottom of the traffic lights peeks out under a 22 pt Platinum bar.
    static func stripHeight(_ style: Style) -> CGFloat {
        switch style {
        case .platinum: return 28
        case .luna:     return 30
        }
    }

    /// Quartz top-left global bounds → AppKit bottom-left frame of the strip along the top edge.
    static func appKitFrame(topLeft b: CGRect, height: CGFloat) -> NSRect {
        let primaryTop = (NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main)?.frame.maxY ?? 0
        return NSRect(x: b.minX, y: primaryTop - b.minY - height, width: b.width, height: height)
    }

    /// The bar's frame: the strip along the window's top edge, widened over the window border
    /// when that is on, so bar and frame are one piece out to the edge.
    static func barFrame(for bounds: CGRect, style: Style) -> NSRect {
        let bw = WindowBorderController.shared.activeBorderWidth
        let grown = CGRect(x: bounds.minX - bw, y: bounds.minY - bw, width: bounds.width + 2 * bw, height: bounds.height + bw)
        return appKitFrame(topLeft: grown, height: stripHeight(style) + bw)
    }

    // MARK: - Events from the WindowServer (forwarded by WindowBorderController)

    func handleServerEvent(event: UInt32, wid: CGWindowID) {
        guard running else { return }
        switch event {
        case PrivateWindowAPI.EVENT_WINDOW_MOVE, PrivateWindowAPI.EVENT_WINDOW_RESIZE:
            guard let o = overlays[wid], let style else { return }
            guard let g = PrivateWindowAPI.bounds(of: wid) else { drop(for: wid); return }
            o.bounds = g
            let f = Self.barFrame(for: g, style: style)
            if f.size == o.panel.frame.size {
                if f.origin != o.panel.frame.origin { o.panel.setFrameOrigin(f.origin) }   // a move: no redraw
            } else if o.panel.frame != f {
                o.panel.setFrame(f, display: false)
                o.view.needsDisplay = true
            }
        case PrivateWindowAPI.EVENT_WINDOW_MINIMIZE, PrivateWindowAPI.EVENT_WINDOW_DESTROY:
            drop(for: wid)
        case PrivateWindowAPI.EVENT_WINDOW_REORDER, PrivateWindowAPI.EVENT_FRONT_CHANGE:
            for (target, o) in overlays { order(o, above: target) }
            sync()   // the front window changed, and with it which bar draws active
        case PrivateWindowAPI.EVENT_WINDOW_CREATE:
            sync()
        default: break
        }
    }

    func drop(for wid: CGWindowID) {
        guard let o = overlays[wid] else { return }
        o.panel.orderOut(nil)
        overlays.removeValue(forKey: wid)
        axWindows.removeValue(forKey: wid)
    }

    /// Drop every bar whose window is not in `onScreen` (a closed window, reported through AX).
    func dropAll(notIn onScreen: Set<CGWindowID>) {
        for wid in overlays.keys where !onScreen.contains(wid) { drop(for: wid) }
    }

    // MARK: - Mouse routing

    /// Only the controls and the dead zone take the mouse; everywhere else the panel is
    /// transparent to events so the real title bar drags and double-clicks as always.
    private func routeMouse(_ screenPoint: NSPoint) {
        for o in overlays.values {
            let inside = o.panel.frame.contains(screenPoint)
            let local = o.view.convert(o.panel.convertPoint(fromScreen: screenPoint), from: nil)
            let hot = inside && o.view.isHot(local)
            if o.panel.ignoresMouseEvents == hot { o.panel.ignoresMouseEvents = !hot }
            if inside { o.view.hover(at: local) } else { o.view.hoverEnded() }
        }
    }

    // MARK: - Driving the real window (Accessibility)

    private var dragOrigin: CGPoint?

    private func axWindow(_ wid: CGWindowID, pid: pid_t) -> AXUIElement? {
        if let cached = axWindows[wid] { return cached }
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let wins = ref as? [AXUIElement] else { return nil }
        for w in wins {
            var id: CGWindowID = 0
            if axUIElementGetWindow?(w, &id) == .success, id == wid {
                axWindows[wid] = w
                return w
            }
        }
        return nil
    }

    private func axTitle(_ wid: CGWindowID, pid: pid_t) -> String? {
        guard let w = axWindow(wid, pid: pid) else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &ref) == .success else { return nil }
        return (ref as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func perform(_ kind: ChromeButtonKind, on wid: CGWindowID, pid: pid_t) {
        guard let w = axWindow(wid, pid: pid) else { return }
        let attr: String
        switch kind {
        case .close:              attr = kAXCloseButtonAttribute
        case .minimize, .collapse: attr = kAXMinimizeButtonAttribute
        case .maximize, .zoom, .restore: zoom(w, wid: wid); return
        default: return
        }
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(w, attr as CFString, &ref) == .success, let ref {
            // The bar goes before the window does; a bar over a fading window is the one thing
            // that gives the trick away. Comes back on the next sync if the app asked to save.
            if kind == .close { drop(for: wid) }
            AXUIElementPerformAction(ref as! AXUIElement, kAXPressAction as CFString)
        } else if attr == kAXMinimizeButtonAttribute {
            AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }

    /// Frames remembered before a zoom, so the second click puts the window back.
    private var zoomedFrom: [CGWindowID: CGRect] = [:]

    /// Zoom the way the era did: fill the screen the window is on, and back again. Pressing the
    /// real green button would put the window into native full screen instead, which is
    /// neither Platinum nor Luna and leaves no bar to click.
    private func zoom(_ w: AXUIElement, wid: CGWindowID) {
        guard let current = overlays[wid]?.bounds ?? PrivateWindowAPI.bounds(of: wid) else { return }
        let primaryTop = (NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main)?.frame.maxY ?? 0
        func quartz(_ r: NSRect) -> CGRect { CGRect(x: r.minX, y: primaryTop - r.maxY, width: r.width, height: r.height) }
        let screen = NSScreen.screens.max(by: { quartz($0.frame).intersection(current).area < quartz($1.frame).intersection(current).area })
        guard let screen else { return }
        // The screen minus the menu bar and the system Dock, and minus the retro taskbar too:
        // a maximised window stopped at the taskbar, and a window the size of the screen would
        // also lose its bar (screen-sized windows get none, so a native full-screen one is left alone).
        var visible = screen.visibleFrame
        if let bar = DockController.shared.barScreenFrame, bar.intersects(screen.frame) {
            if bar.midY < screen.frame.midY {
                let top = bar.maxY
                if top > visible.minY { visible = NSRect(x: visible.minX, y: top, width: visible.width, height: visible.maxY - top) }
            } else {
                let bottom = bar.minY
                if bottom < visible.maxY { visible = NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: bottom - visible.minY) }
            }
        }
        if visible.height >= screen.frame.height - 1 { visible = visible.insetBy(dx: 0, dy: 1) }
        let full = quartz(visible)
        let target: CGRect
        if let back = zoomedFrom[wid], abs(current.width - full.width) < 2, abs(current.height - full.height) < 2 {
            target = back
            zoomedFrom.removeValue(forKey: wid)
        } else {
            zoomedFrom[wid] = current
            target = full
        }
        var p = target.origin, sz = target.size
        if let pv = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv) }
        if let sv = AXValueCreate(.cgSize, &sz) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv) }
        if let pv = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv) }
    }

    /// Move the real window by `delta` (AppKit points, y up) from where it was when the drag began.
    private func drag(_ wid: CGWindowID, pid: pid_t, by delta: NSPoint) {
        guard let w = axWindow(wid, pid: pid) else { return }
        if dragOrigin == nil {
            var ref: CFTypeRef?
            var p = CGPoint.zero
            guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &ref) == .success, let ref,
                  AXValueGetValue(ref as! AXValue, .cgPoint, &p) else { return }
            dragOrigin = p
        }
        guard let origin = dragOrigin else { return }
        var target = CGPoint(x: origin.x + delta.x, y: origin.y - delta.y)   // AX is y-down
        if let v = AXValueCreate(.cgPoint, &target) {
            AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v)
        }
    }

    // MARK: - Window enumeration

    private struct WindowInfo {
        let id: CGWindowID
        let pid: pid_t
        let bounds: CGRect
        let title: String
        let ownerName: String
        let bundleID: String
    }

    private static var bundleIDs: [pid_t: String] = [:]
    private static func bundleID(for pid: pid_t) -> String {
        if let b = bundleIDs[pid] { return b }
        let b = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        bundleIDs[pid] = b
        return b
    }

    private static func onScreenWindows() -> [WindowInfo] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let myPID = getpid()
        var out: [WindowInfo] = []
        for w in raw {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != myPID else { continue }
            guard let num = w[kCGWindowNumber as String] as? CGWindowID,
                  let bDict = w[kCGWindowBounds as String] as? [String: Any] else { continue }
            var b = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(bDict as CFDictionary, &b),
                  b.width > 40, b.height > 60 else { continue }
            // kCGWindowName needs Screen Recording, which the shader already has; empty otherwise.
            out.append(WindowInfo(id: num, pid: pid, bounds: b,
                                  title: (w[kCGWindowName as String] as? String) ?? "",
                                  ownerName: (w[kCGWindowOwnerName as String] as? String) ?? "",
                                  bundleID: bundleID(for: pid)))
        }
        return out
    }
}

// MARK: - The bar itself

/// Draws one title bar and owns its controls. Flipped, so y runs down like the strip does.
final class TitleBarOverlayView: NSView {
    var onAction: ((ChromeButtonKind) -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    var onLeave: (() -> Void)?

    private var style: TitleBarOverlayController.Style = .platinum
    private var title = ""
    private var icon: NSImage?
    private var isFront = true
    private var radius: CGFloat = 10
    private var tracker = ChromeButtonTracker()
    private var buttonRects: [(ChromeButtonKind, NSRect)] = []
    private var dragStart: NSPoint?
    private var dragging = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Where the real traffic lights sit under the bar. Clicks there are ours, never theirs.
    private var deadZone: NSRect { NSRect(x: 0, y: 0, width: 76, height: bounds.height) }

    func configure(style: TitleBarOverlayController.Style, title: String, icon: NSImage?, isFront: Bool, radius: CGFloat) {
        guard style != self.style || title != self.title || isFront != self.isFront
                || radius != self.radius || (icon == nil) != (self.icon == nil) else { return }
        self.style = style; self.title = title; self.icon = icon; self.isFront = isFront; self.radius = radius
        needsDisplay = true
    }

    /// Whether the panel should take the mouse at `p` (view coordinates).
    func isHot(_ p: NSPoint) -> Bool {
        if buttonRects.contains(where: { $0.1.insetBy(dx: -3, dy: -3).contains(p) }) { return true }
        return deadZone.contains(p)
    }

    func hover(at p: NSPoint) { if tracker.mouseMoved(to: p) { needsDisplay = true } }
    func hoverEnded() { if tracker.mouseExited() { needsDisplay = true } }

    // MARK: Layout

    private func layoutControls() {
        tracker.reset()
        buttonRects.removeAll()
        let h = bounds.height, w = bounds.width
        switch style {
        case .platinum:
            let s = ClassicMacChrome.boxSize
            let y = ((h - s) / 2).rounded()
            let close = NSRect(x: 8, y: y, width: s, height: s)
            let zoom = NSRect(x: w - 7 - s, y: y, width: s, height: s)
            let collapse = NSRect(x: zoom.minX - 5 - s, y: y, width: s, height: s)
            for (k, r) in [(ChromeButtonKind.close, close), (.collapse, collapse), (.zoom, zoom)] {
                tracker.add(k, r.insetBy(dx: -3, dy: -3), interactive: isFront)
                buttonRects.append((k, r))
            }
        case .luna:
            let cs = ChromeStyleFactory.xp()
            let bw = cs.buttonSize.width, bh = cs.buttonSize.height
            let y = ((h - bh) / 2).rounded()
            let close = NSRect(x: w - cs.buttonInset - bw, y: y, width: bw, height: bh)
            let max = NSRect(x: close.minX - cs.buttonSpacing - bw, y: y, width: bw, height: bh)
            let min = NSRect(x: max.minX - cs.buttonSpacing - bw, y: y, width: bw, height: bh)
            for (k, r) in [(ChromeButtonKind.minimize, min), (.maximize, max), (.close, close)] {
                tracker.add(k, r, interactive: true)
                buttonRects.append((k, r))
            }
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        layoutControls()
        // Square, edge to edge: the bar covers the window's rounded top corners, and when the
        // window border is on it runs out over the frame too (`barFrame`), so the two are one.
        let b = bounds
        switch style {
        case .platinum: drawPlatinum(b)
        case .luna:     drawLuna(b)
        }
    }

    private func drawPlatinum(_ b: NSRect) {
        ClassicMacChrome.face.setFill(); b.fill()
        let font = ChromeStyleFactory.macClassic().titleFont
        if isFront {
            ClassicMacChrome.pinstripes(in: b)
            for (k, r) in buttonRects {
                ClassicMacChrome.bevelBox(r, state: tracker.state(for: k))
                if k == .zoom { ClassicMacChrome.zoomGlyph(in: r) }
                if k == .collapse { ClassicMacChrome.collapseGlyph(in: r) }
            }
            ClassicMacChrome.titlePlaque(title, bar: b, font: font)
        } else {
            // An inactive Platinum window: plain plate, no boxes, grey title.
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1)]
            let s = title.size(withAttributes: attrs)
            (title as NSString).draw(at: NSPoint(x: (b.width - s.width) / 2, y: (b.height - s.height) / 2), withAttributes: attrs)
        }
        ClassicMacChrome.botShadow.setFill()
        NSRect(x: 0, y: b.height - 1, width: b.width, height: 1).fill()
    }

    private func drawLuna(_ b: NSRect) {
        let cs = ChromeStyleFactory.xp()
        if isFront {
            cs.captionGradient?.draw(in: b)
        } else {
            NSGradient(starting: NSColor(srgbRed: 0.55, green: 0.66, blue: 0.91, alpha: 1),
                       ending: NSColor(srgbRed: 0.47, green: 0.58, blue: 0.86, alpha: 1))?.draw(in: b, angle: -90)
        }
        NSColor.white.withAlphaComponent(0.45).setFill()
        NSRect(x: 1, y: 0, width: b.width - 2, height: 1).fill()
        var x: CGFloat = 8
        if let icon {
            icon.draw(in: NSRect(x: x, y: (b.height - 16) / 2, width: 16, height: 16), from: .zero,
                      operation: .sourceOver, fraction: isFront ? 1 : 0.7, respectFlipped: true, hints: nil)
            x += 20
        }
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
        shadow.shadowOffset = NSSize(width: 1, height: -1)
        let attrs: [NSAttributedString.Key: Any] = [.font: cs.titleFont,
                                                   .foregroundColor: isFront ? NSColor.white : NSColor(white: 0.9, alpha: 1),
                                                   .shadow: shadow]
        let avail = (buttonRects.map { $0.1.minX }.min() ?? b.width) - 8 - x
        let s = title.size(withAttributes: attrs)
        (title as NSString).draw(in: NSRect(x: x, y: (b.height - s.height) / 2, width: max(0, avail), height: s.height),
                                 withAttributes: attrs)
        for (k, r) in buttonRects {
            let base: String
            switch k {
            case .close: base = "close"
            case .maximize: base = "max"
            default: base = "min"
            }
            if let img = ChromeAssets.image(dir: "winxp", base: base, state: tracker.state(for: k)) {
                img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if tracker.mouseDown(at: p) { needsDisplay = true; return }
        if deadZone.contains(p) {
            if event.clickCount == 2 { onAction?(.zoom); return }
            dragStart = NSEvent.mouseLocation
            dragging = false
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if tracker.mouseDragged(to: p) { needsDisplay = true }
        guard let start = dragStart else { return }
        let now = NSEvent.mouseLocation
        let delta = NSPoint(x: now.x - start.x, y: now.y - start.y)
        if !dragging, abs(delta.x) < 3, abs(delta.y) < 3 { return }
        dragging = true
        onDrag?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let (fire, redraw) = tracker.mouseUp(at: p)
        if redraw { needsDisplay = true }
        if let fire { onAction?(fire) }
        if dragStart != nil { dragStart = nil; dragging = false; onDragEnd?() }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        hover(at: p)
        if !isHot(p) { onLeave?() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoverEnded()
        onLeave?()
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
