import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Windows 7's Aero Snap and Aero Shake for the Windows 7 theme.
///
/// - **Snap.** Drag a window by its title bar to the left or right edge of the screen and it fills
///   that half, to the top edge and it fills the screen; a glass preview shows where while you
///   hold it there. Dragging a snapped window away gives it its old size back. Ctrl+Option+←/→
///   snaps the front window to a half, ↑ fills the screen, ↓ restores a snapped window or else
///   minimizes it (Windows used the Windows key; a Mac keyboard has none to spare).
/// - **Shake.** Shake a window by its title bar and every other app hides; shake it again and they
///   come back.
///
/// Both need Accessibility. A window under one of RetroMac's own title bars is dragged by that bar,
/// which reports to `barDragged`/`barDragEnded`; any other by its own, seen by a global mouse
/// monitor. Moves and sizes go through the title bars' Accessibility queue. After macOS 7 Ultimate SP1's SnapController and ShakeDetector
/// (github.com/kaganisildak/macOS-7-Ultimate-SP1, GPL-3.0).
final class AeroSnap {
    static let shared = AeroSnap()
    static let themeID = "com.retromac.microsoft.windows7"
    private static let signature: OSType = 0x534E4150   // 'SNAP'

    private struct Drag {
        let window: AXUIElement?
        var start: CGRect
        var moving = false
        var lastRead = 0.0
        var shake: ShakeDetector
        var target: CGRect?
    }

    private var monitor: Any?
    private var drag: Drag?
    private let preview = SnapPreview()
    /// Snapped windows: the frame before the snap and the one the app actually took.
    private var snapped: [CGWindowID: (original: CGRect, applied: CGRect)] = [:]
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var shakeHidden: [NSRunningApplication] = []

    private var snapOn = false, shakeOn = false
    private var permissionToken: NSObjectProtocol?

    /// Called when the theme, the settings or the Accessibility permission change.
    func update() {
        if permissionToken == nil {
            permissionToken = NotificationCenter.default.addObserver(forName: .systemCapabilitiesChanged, object: nil,
                                                                     queue: .main) { _ in AeroSnap.shared.update() }
        }
        let s = AppSettings.shared
        let win7 = ThemeManager.shared.activeTheme?.config.id == Self.themeID && AXIsProcessTrusted()
        snapOn = win7 && s.win7Snap
        shakeOn = win7 && s.win7Shake
        if (snapOn || shakeOn) && monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] e in
                if e.type == .leftMouseUp { self?.finishDrag() } else { self?.continueDrag(time: e.timestamp) }
            }
        } else if !(snapOn || shakeOn), let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
            drag = nil
            preview.hide()
        }
        if !shakeOn { restoreShaken() }
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys = []
        guard snapOn else { return }
        installHandler()
        for (n, code) in [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow].enumerated() {
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(UInt32(code), UInt32(controlKey | optionKey), EventHotKeyID(signature: Self.signature, id: UInt32(n)),
                                   GetApplicationEventTarget(), 0, &ref) == noErr, let ref { hotKeys.append(ref) }
        }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == AeroSnap.signature else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { AeroSnap.shared.key(Int(id.id)) }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    // MARK: - Geometry

    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private static func ax(_ r: NSRect) -> CGRect { CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height) }

    private static var cursor: CGPoint {
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    /// The screen's work area in Accessibility coordinates: its visible frame less the taskbar.
    private static func workArea(of screen: NSScreen) -> CGRect {
        let visible = ax(screen.visibleFrame)
        guard let bar = DockController.shared.currentDockFrame(), screen.frame.intersects(bar) else { return visible }
        return WorkArea.usable(visible: visible, bar: ax(bar))
    }

    private static func screen(at p: CGPoint) -> NSScreen? {
        NSScreen.screens.first { ax($0.frame).insetBy(dx: -1, dy: -1).contains(p) }
    }

    /// Where a window dragged with the cursor at `p` snaps to, if anywhere.
    static func target(cursor p: CGPoint) -> CGRect? {
        guard let screen = screen(at: p) else { return nil }
        let full = ax(screen.frame), area = workArea(of: screen)
        return SnapGeometry.target(cursor: p, screen: full, workArea: area)
    }

    // MARK: - Dragging

    private static func focusedWindow() -> AXUIElement? {
        var app: AnyObject?, win: AnyObject?
        let system = AXUIElementCreateSystemWide()
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &app) == .success,
              let app, CFGetTypeID(app) == AXUIElementGetTypeID(),
              AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedWindowAttribute as CFString, &win) == .success,
              let win, CFGetTypeID(win) == AXUIElementGetTypeID() else { return nil }
        return (win as! AXUIElement)
    }

    private static func id(of window: AXUIElement) -> CGWindowID? {
        var wid: CGWindowID = 0
        return axUIElementGetWindow?(window, &wid) == .success && wid != 0 ? wid : nil
    }

    private func continueDrag(time: TimeInterval) {
        let p = Self.cursor
        if drag == nil {
            // Only a drag that began on the title bar: the band under the window's top edge.
            guard let w = Self.focusedWindow(), var f = WorkAreaKeeper.frame(of: w),
                  p.y >= f.minY - 4, p.y <= f.minY + 34, p.x >= f.minX, p.x <= f.maxX else { return }
            if let id = Self.id(of: w), let s = snapped[id] {
                if f.size == s.applied.size {
                    // Pulled off its snap: back to its old size, under the cursor where it was held.
                    let rel = f.width > 0 ? (p.x - f.minX) / f.width : 0.5
                    WorkAreaKeeper.set(w, size: s.original.size)
                    WorkAreaKeeper.set(w, origin: CGPoint(x: p.x - rel * s.original.width, y: f.minY))
                    f = WorkAreaKeeper.frame(of: w) ?? s.original
                }
                snapped[id] = nil
            }
            drag = Drag(window: w, start: f, shake: ShakeDetector(startX: p.x))
            return
        }
        guard var d = drag else { return }
        defer { drag = d }
        if shakeOn, d.shake.add(x: p.x, time: time), let w = d.window { shake(exceptPID: Self.pid(of: w)) }
        guard snapOn, time - d.lastRead >= 0.05 else { return }
        d.lastRead = time
        if !d.moving {
            guard let w = d.window, let f = WorkAreaKeeper.frame(of: w) else { return }
            // Moving, not resizing and not selecting text in the title bar's band.
            d.moving = f.origin != d.start.origin && f.size == d.start.size
            if !d.moving { return }
        }
        d.target = Self.target(cursor: p)
        if let t = d.target { preview.show(axFrame: t) } else { preview.hide() }
    }

    private func finishDrag() {
        defer { drag = nil; preview.hide() }
        guard let d = drag, d.moving, let target = d.target, let w = d.window else { return }
        snap(w, to: target, original: d.start)
    }

    // MARK: - Dragged by RetroMac's own title bar

    private var barDrag: (wid: CGWindowID, pid: pid_t)?

    /// The title bar of window `wid` is being dragged; `frame` is where the window is going.
    func barDragged(wid: CGWindowID, pid: pid_t, frame: CGRect) {
        guard snapOn || shakeOn else { return }
        let p = Self.cursor, time = ProcessInfo.processInfo.systemUptime
        if barDrag?.wid != wid {
            barDrag = (wid, pid)
            drag = Drag(window: nil, start: frame, moving: true, shake: ShakeDetector(startX: p.x))
            if let s = snapped[wid], frame.size == s.applied.size {
                // Pulled off its snap: back to its old size.
                snapped[wid] = nil
                let size = s.original.size
                TitleBarOverlayController.axQueue.async {
                    if let w = TitleBarOverlayController.findAXWindow(wid, pid: pid) { WorkAreaKeeper.set(w, size: size) }
                }
            } else {
                snapped[wid] = nil
            }
            return
        }
        guard var d = drag else { return }
        defer { drag = d }
        if shakeOn, d.shake.add(x: p.x, time: time) { shake(exceptPID: pid) }
        guard snapOn else { return }
        d.target = Self.target(cursor: p)
        if let t = d.target { preview.show(axFrame: t) } else { preview.hide() }
    }

    /// The bar was let go. True when the window snaps: the drag's last position must not follow.
    @discardableResult
    func barDragEnded() -> Bool {
        defer { drag = nil; barDrag = nil; preview.hide() }
        guard let (wid, pid) = barDrag, let d = drag, let target = d.target else { return false }
        let original = d.start
        TitleBarOverlayController.axQueue.async { [weak self] in
            guard let w = TitleBarOverlayController.findAXWindow(wid, pid: pid) else { return }
            let applied = Self.apply(target, to: w)
            DispatchQueue.main.async { self?.snapped[wid] = (original, applied) }
        }
        return true
    }

    /// On the Accessibility queue. Position, size and the position again: an app may refuse a
    /// size that does not fit where the window still is.
    private static func apply(_ target: CGRect, to window: AXUIElement) -> CGRect {
        WorkAreaKeeper.set(window, origin: target.origin)
        WorkAreaKeeper.set(window, size: target.size)
        WorkAreaKeeper.set(window, origin: target.origin)
        return WorkAreaKeeper.frame(of: window) ?? target
    }

    private func snap(_ window: AXUIElement, to target: CGRect, original: CGRect) {
        TitleBarOverlayController.axQueue.async { [weak self] in
            let applied = Self.apply(target, to: window)
            guard let id = Self.id(of: window) else { return }
            DispatchQueue.main.async { self?.snapped[id] = (original, applied) }
        }
    }

    private static func pid(of window: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return pid
    }

    // MARK: - Keyboard

    private func key(_ n: Int) {
        guard snapOn, let w = Self.focusedWindow(), let f = WorkAreaKeeper.frame(of: w),
              let screen = Self.screen(at: CGPoint(x: f.midX, y: f.midY)) ?? NSScreen.main else { return }
        let area = Self.workArea(of: screen)
        let id = Self.id(of: w)
        let original = id.flatMap { snapped[$0]?.original } ?? f
        switch n {
        case 0: snap(w, to: SnapGeometry.half(area, left: true), original: original)
        case 1: snap(w, to: SnapGeometry.half(area, left: false), original: original)
        case 2: snap(w, to: area, original: original)
        default:
            let back = id.flatMap { snapped[$0]?.original }
            if let id { snapped[id] = nil }
            TitleBarOverlayController.axQueue.async {
                if let back { _ = Self.apply(back, to: w) }
                else { AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
            }
        }
    }

    // MARK: - Shake

    private func shake(exceptPID pid: pid_t) {
        if !shakeHidden.isEmpty { return restoreShaken() }
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != pid && app.processIdentifier != getpid()
            && !app.isHidden && app.hide() {
            shakeHidden.append(app)
        }
    }

    private func restoreShaken() {
        shakeHidden.forEach { $0.unhide() }
        shakeHidden = []
    }
}

/// Where Aero Snap puts a window, in Accessibility coordinates (y down).
enum SnapGeometry {
    /// The cursor against the screen's left or right edge: that half of the work area; against the
    /// top edge (or up in the menu bar): all of it.
    static func target(cursor p: CGPoint, screen: CGRect, workArea: CGRect) -> CGRect? {
        if p.x <= screen.minX + 1 { return half(workArea, left: true) }
        if p.x >= screen.maxX - 2 { return half(workArea, left: false) }
        if p.y <= workArea.minY + 1 { return workArea }
        return nil
    }

    static func half(_ area: CGRect, left: Bool) -> CGRect {
        let w = (area.width / 2).rounded(.down)
        return CGRect(x: left ? area.minX : area.maxX - w, y: area.minY, width: w, height: area.height)
    }
}

/// Fed the cursor's x during one title-bar drag, it fires once when the window has been shaken:
/// at least three turns, every leg at least 40 points, the turns within 0.6 seconds, and the drag
/// never more than 120 points from where it began.
struct ShakeDetector {
    static let reversals = 3
    static let minLeg: CGFloat = 40
    static let window: TimeInterval = 0.6
    static let maxDrift: CGFloat = 120

    private let startX: CGFloat
    private var direction: CGFloat = 0
    private var extremeX: CGFloat = 0
    private var extremeTime: TimeInterval = 0
    private var turns: [TimeInterval] = []
    private var done = false

    init(startX: CGFloat) { self.startX = startX }

    /// True exactly once, on the sample that completes a shake.
    mutating func add(x: CGFloat, time: TimeInterval) -> Bool {
        guard !done else { return false }
        if abs(x - startX) > Self.maxDrift { done = true; return false }
        if direction == 0 {
            guard abs(x - startX) >= Self.minLeg else { return false }
            direction = x > startX ? 1 : -1
            extremeX = x; extremeTime = time
            return false
        }
        if (x - extremeX) * direction > 0 {
            extremeX = x; extremeTime = time
            return false
        }
        guard (extremeX - x) * direction >= Self.minLeg else { return false }
        turns.append(extremeTime)
        direction = -direction
        extremeX = x; extremeTime = time
        let recent = turns.suffix(Self.reversals)
        guard recent.count >= Self.reversals, recent.last! - recent.first! <= Self.window else { return false }
        done = true
        return true
    }
}

/// The glass rectangle Windows 7 showed where a window would snap.
private final class SnapPreview {
    private var panel: NSPanel?

    func show(axFrame f: CGRect) {
        let h = NSScreen.screens.first?.frame.height ?? 0
        let frame = NSRect(x: f.minX, y: h - f.maxY, width: f.width, height: f.height).insetBy(dx: 6, dy: 6)
        let p = panel ?? make()
        if p.frame != frame { p.setFrame(frame, display: true) }
        if !p.isVisible { p.alphaValue = 0; p.orderFrontRegardless(); p.animator().alphaValue = 1 }
    }

    func hide() { panel?.orderOut(nil) }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 8
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor(white: 1, alpha: 0.6).cgColor
        glass.layer?.backgroundColor = NSColor(srgbRed: 0.6, green: 0.78, blue: 0.95, alpha: 0.25).cgColor
        p.contentView = glass
        panel = p
        return p
    }
}

/// Aero Peek: rest the pointer on the Show Desktop strip at the right end of the Windows 7
/// taskbar and the windows turn to glass outlines over the desktop; move away and they are back.
/// A click on the strip shows the desktop. macOS lets no app make another app's windows
/// transparent, so this lays the desktop picture and the windows' outlines over them instead.
final class AeroPeek {
    static let shared = AeroPeek()
    private var panels: [NSPanel] = []
    private var pending: DispatchWorkItem?

    var isOn: Bool { ThemeManager.shared.activeTheme?.config.id == AeroSnap.themeID && AppSettings.shared.win7Peek }

    func hover(_ inside: Bool) {
        pending?.cancel()
        pending = nil
        guard inside else { return end() }
        guard isOn, panels.isEmpty else { return }
        let item = DispatchWorkItem { [weak self] in self?.begin() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func click() {
        pending?.cancel()
        end()
        DockView.toggleShowDesktop()
    }

    private func begin() {
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                       as? [[String: Any]] ?? []).compactMap { info -> CGRect? in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != getpid(),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b), r.width > 40, r.height > 40 else { return nil }
            return NSRect(x: r.minX, y: primary - r.maxY, width: r.width, height: r.height)
        }
        for screen in NSScreen.screens {
            let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = NSWindow.Level(rawValue: DockWindow.defaultLevel - 1)
            p.isOpaque = true
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
            let view = PeekView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wallpaper = NSWorkspace.shared.desktopImageURL(for: screen).flatMap(NSImage.init(contentsOf:))
            view.outlines = windows.reversed().map { $0.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY) }
            p.contentView = view
            p.alphaValue = 0
            p.orderFrontRegardless()
            p.animator().alphaValue = 1
            panels.append(p)
        }
        DesktopIconsController.shared.raiseForPeek(true)
    }

    func end() {
        guard !panels.isEmpty else { return }
        panels.forEach { $0.orderOut(nil) }
        panels = []
        DesktopIconsController.shared.raiseForPeek(false)
    }

    private final class PeekView: NSView {
        var wallpaper: NSImage?
        var outlines: [NSRect] = []

        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.setFill()
            bounds.fill()
            if let img = wallpaper, img.size.width > 0, img.size.height > 0 {
                let s = max(bounds.width / img.size.width, bounds.height / img.size.height)
                let size = NSSize(width: img.size.width * s, height: img.size.height * s)
                img.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                                    width: size.width, height: size.height))
            }
            for r in outlines where r.intersects(bounds) {
                let outer = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
                NSColor(white: 1, alpha: 0.10).setFill()
                outer.fill()
                NSColor(white: 0, alpha: 0.45).setStroke()
                outer.lineWidth = 1
                outer.stroke()
                let inner = NSBezierPath(roundedRect: r.insetBy(dx: 1.5, dy: 1.5), xRadius: 5, yRadius: 5)
                NSColor(white: 1, alpha: 0.55).setStroke()
                inner.lineWidth = 1
                inner.stroke()
            }
        }
    }
}
