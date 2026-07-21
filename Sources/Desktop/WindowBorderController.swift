import AppKit
import ApplicationServices

/// PROTOTYPE — "Window borders in theme style".
///
/// Draws a single theme-coloured border around the *focused* window of whatever app is
/// frontmost, so real app windows (Finder, Safari, Mail …) pick up the active theme's accent.
///
/// Focus discovery uses the public Accessibility API (no SIP, no scripting addition). The live
/// *frame* comes from the WindowServer via SkyLight (`SLSGetWindowBounds`) — the same source
/// JankyBorders uses — because AX window positions lag badly during a drag, making the border
/// trail. AX only tells us *which* window is focused; SkyLight tells us where it is, every frame.
///
/// Scope note: only the focused/front window is bordered. Bordering *every* window (including
/// background ones) needs the SkyLight window-layer approach to sit each border correctly in the
/// global z-order — that is the follow-up, not this prototype.
final class WindowBorderController {

    static let shared = WindowBorderController()
    private init() {}

    // Overlay
    private var panel: NSPanel?
    private var borderView: BorderView?
    private var lastOuter: NSRect = .zero

    // Accessibility observation of the current frontmost app
    private var observedPID: pid_t = 0
    private var axApp: AXUIElement?
    private var axObserver: AXObserver?
    private var observedWindow: AXUIElement?
    private var trackedWindowID: CGWindowID = 0

    // Workspace + tracking tick
    private var wsTokens: [NSObjectProtocol] = []
    private var tickTimer: Timer?
    private var didRegisterEvents = false

    // Current theme's edge treatment (recomputed on theme change).
    private var currentWidth: CGFloat = 4
    private var hasStyle = false

    // MARK: - Lifecycle

    /// Reconcile running state with the flag (called from AppSettings.didSet and theme changes).
    func update() {
        let want = AppSettings.shared.themeWindowBorders
            && AppSettings.shared.dockEnabled
            && !AppSettings.shared.dockOnly
        if want { start() } else { stop() }
    }

    private func start() {
        guard panel == nil else { refresh(); return }   // already running → just recolour/reposition
        guard AXIsProcessTrusted() else {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            return   // once granted, a later update()/theme change will start it
        }

        let bv = BorderView(frame: .zero)
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.contentView = bv
        panel = p
        borderView = bv

        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            wsTokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        registerServerEvents()

        // Safety-net poll. With SkyLight events the border is driven event-for-event by the
        // WindowServer (zero-lag during a drag); this timer only backstops a missed event.
        // Without events it is the primary tracker, so it runs fast.
        let interval = PrivateWindowAPI.eventsAvailable ? 0.25
                     : (PrivateWindowAPI.available ? 1.0 / 120.0 : 0.4)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t

        refresh()
    }

    private func stop() {
        tickTimer?.invalidate(); tickTimer = nil
        let nc = NSWorkspace.shared.notificationCenter
        wsTokens.forEach { nc.removeObserver($0) }
        wsTokens.removeAll()
        detachAX()
        panel?.orderOut(nil)
        panel = nil
        borderView = nil
        lastOuter = .zero
    }

    // MARK: - Focus tracking (which window)

    /// Re-derive the focused window of the frontmost app; set colour + tracked window id.
    /// Called on AX focus/app-change events, not every frame.
    func refresh() {
        guard let panel = panel else { return }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front != .current,                                   // never border our own windows
              front.activationPolicy == .regular else {
            hideOverlay(); detachAX(); return
        }

        if front.processIdentifier != observedPID {
            attachAX(to: front.processIdentifier)
        }
        guard let axApp = axApp else { hideOverlay(); return }

        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let wr = winRef, CFGetTypeID(wr) == AXUIElementGetTypeID() else {
            hideOverlay(); return
        }
        let window = wr as! AXUIElement

        if observedWindow == nil || !CFEqual(observedWindow, window) {
            registerWindowNotifications(window)
        }
        // Only themes with an authentic edge treatment draw anything. The corner radius follows the
        // theme's own window-corner tweak so the edge matches the (theme-squared) window rounding.
        let style = Self.style(for: RetroFrameTheme.key(),
                               colors: ThemeManager.shared.activeTheme?.config.chromeColors,
                               radius: Self.windowCornerRadius())
        hasStyle = !style.isNone
        guard hasStyle else { hideOverlay(); return }
        currentWidth = style.width

        trackedWindowID = PrivateWindowAPI.windowID(of: window) ?? 0
        if trackedWindowID != 0 {
            // Subscribe this window to WindowServer move/resize notifications.
            PrivateWindowAPI.requestNotifications(for: trackedWindowID)
        }
        borderView?.apply(style: style)
        _ = panel   // positioned by tick()
        tick()
    }

    // MARK: - WindowServer events (zero-lag tracking)

    private func registerServerEvents() {
        guard PrivateWindowAPI.eventsAvailable, !didRegisterEvents else { return }
        didRegisterEvents = true
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let procPtr = unsafeBitCast(borderNotifyProc as PrivateWindowAPI.NotifyProc,
                                    to: UnsafeMutableRawPointer.self)
        for e in [PrivateWindowAPI.EVENT_WINDOW_MOVE, PrivateWindowAPI.EVENT_WINDOW_RESIZE,
                  PrivateWindowAPI.EVENT_WINDOW_DESTROY, PrivateWindowAPI.EVENT_FRONT_CHANGE] {
            PrivateWindowAPI.register(proc: procPtr, event: e, context: ctx)
        }
    }

    /// Called from the WindowServer notify proc (main thread) — reposition immediately.
    fileprivate func handleServerEvent(event: UInt32, wid: CGWindowID) {
        guard panel != nil else { return }   // ignore while stopped
        switch event {
        case PrivateWindowAPI.EVENT_WINDOW_MOVE, PrivateWindowAPI.EVENT_WINDOW_RESIZE:
            if wid == trackedWindowID { tick() }
        case PrivateWindowAPI.EVENT_FRONT_CHANGE, PrivateWindowAPI.EVENT_WINDOW_DESTROY:
            refresh()
        default: break
        }
    }

    // MARK: - Per-frame positioning (where the window is)

    private func tick() {
        guard let panel = panel, hasStyle else { return }
        guard let frame = currentFrame() else { hideOverlay(); return }
        // Skip full-screen / desktop-sized windows — a border around the whole screen is noise.
        if let scr = NSScreen.screens.first(where: { $0.frame.intersects(frame) }),
           frame.width >= scr.frame.width - 1, frame.height >= scr.frame.height - 1 {
            hideOverlay(); return
        }
        let outer = frame.insetBy(dx: -currentWidth, dy: -currentWidth)
        if outer != lastOuter {
            // Move-only is cheaper than a full setFrame; only resize when the size actually changed.
            if outer.size == lastOuter.size {
                panel.setFrameOrigin(outer.origin)
            } else {
                panel.setFrame(outer, display: false)
            }
            lastOuter = outer
        }
        if !panel.isVisible { panel.orderFront(nil) }
    }

    /// Live focused-window frame in Cocoa coords. Prefer SkyLight (lag-free); fall back to AX.
    private func currentFrame() -> NSRect? {
        if trackedWindowID != 0, let g = PrivateWindowAPI.bounds(of: trackedWindowID) {
            return flip(g)
        }
        if let w = observedWindow, let g = axFrame(w) { return flip(g) }
        return nil
    }

    /// AX position/size (top-left global) as a raw rect — fallback when SkyLight is unavailable.
    private func axFrame(_ window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let pr = posRef, let sr = sizeRef,
              CFGetTypeID(pr) == AXValueGetTypeID(), CFGetTypeID(sr) == AXValueGetTypeID() else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(pr as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sr as! AXValue, .cgSize, &size)
        guard size.width > 1, size.height > 1 else { return nil }
        return CGRect(origin: pos, size: size)
    }

    /// Flip a top-left global rect (AX / SkyLight) into Cocoa's bottom-left screen space.
    private func flip(_ r: CGRect) -> NSRect {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: r.origin.x, y: primaryH - r.origin.y - r.height, width: r.width, height: r.height)
    }

    private func hideOverlay() {
        panel?.orderOut(nil)
        lastOuter = .zero
    }

    // MARK: - AXObserver plumbing

    private func attachAX(to pid: pid_t) {
        detachAX()
        let app = AXUIElementCreateApplication(pid)
        var obsRef: AXObserver?
        guard AXObserverCreate(pid, axBorderCallback, &obsRef) == .success, let obs = obsRef else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in appNotifs { AXObserverAddNotification(obs, app, n as CFString, refcon) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        axApp = app
        axObserver = obs
        observedPID = pid
        observedWindow = nil
        trackedWindowID = 0
    }

    private func registerWindowNotifications(_ window: AXUIElement) {
        guard let obs = axObserver else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        if let old = observedWindow {
            for n in windowNotifs { AXObserverRemoveNotification(obs, old, n as CFString) }
        }
        for n in windowNotifs { AXObserverAddNotification(obs, window, n as CFString, refcon) }
        observedWindow = window
    }

    private let appNotifs = [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
                             kAXApplicationHiddenNotification, kAXApplicationShownNotification]
    private let windowNotifs = [kAXWindowMovedNotification, kAXWindowResizedNotification,
                                kAXWindowMiniaturizedNotification, kAXUIElementDestroyedNotification]

    private func detachAX() {
        if let obs = axObserver {
            if let app = axApp {
                for n in appNotifs { AXObserverRemoveNotification(obs, app, n as CFString) }
            }
            if let w = observedWindow {
                for n in windowNotifs { AXObserverRemoveNotification(obs, w, n as CFString) }
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        axObserver = nil
        axApp = nil
        observedWindow = nil
        observedPID = 0
        trackedWindowID = 0
    }

    // MARK: - Authentic per-theme edge style

    /// The window-edge treatment for a theme key. `.none` for themes where an outer edge is not
    /// authentic (BeOS tab, Aqua glow, plain default) — those draw nothing even with the flag on.
    /// The corner radius windows actually have under the active theme: the theme's own window-corner
    /// tweak value (NSConvolutionOverride1) when Classic tweaks are applied, else the macOS default.
    /// Matching this makes the border hug the corners instead of leaving square-corner gaps.
    static func windowCornerRadius() -> CGFloat {
        let defaultRadius: CGFloat = 10
        guard AppSettings.shared.themeApplySystemTweaks,
              let tweaks = ThemeManager.shared.activeTheme?.config.systemTweaks else { return defaultRadius }
        for t in tweaks where t.key == "NSConvolutionOverride1" || t.key == "NSSplitViewItemGlassMinimumCornerRadius" {
            if let v = Double(t.value) { return CGFloat(v) }
        }
        return defaultRadius
    }

    static func style(for key: String, colors: DockThemeConfig.ChromeColors?, radius R: CGFloat) -> WindowBorderStyle {
        func hex(_ s: String?, _ fallback: String) -> NSColor { NSColor.fromHex((s?.isEmpty == false ? s! : fallback)) }
        switch key {
        case "win98":
            // Win9x raised 3D edge: highlight top-left, shadow bottom-right. Honour the active
            // Plus! scheme's 3D palette when present, else the classic silver default.
            return .bevel(hiOuter: hex(colors?.hilight, "#FFFFFF"),
                          hiInner: hex(colors?.light,   "#DFDFDF"),
                          loInner: hex(colors?.shadow,  "#808080"),
                          loOuter: hex(colors?.dkShadow, "#000000"),
                          width: 4, radius: R)
        case "macos9":
            // Platinum grey bevel.
            return .bevel(hiOuter: NSColor.fromHex("#FFFFFF"), hiInner: NSColor.fromHex("#E4E4E8"),
                          loInner: NSColor.fromHex("#9A9AA2"), loOuter: NSColor.fromHex("#5A5A62"),
                          width: 3, radius: R)
        case "macos6":
            // System 6 windows had a crisp 1-bit black outline.
            return .solid(color: .black, width: 2, topRadius: R, bottomRadius: R)
        case "winxp":
            // Luna windows have a solid themed border.
            return .solid(color: NSColor.fromHex("#2A63D8"), width: 4, topRadius: R, bottomRadius: R)
        case "win7":
            // Aero glass frame — approximated by a soft translucent blue edge.
            return .glow(color: NSColor.fromHex("#6FB3F0").withAlphaComponent(0.55), width: 6, radius: R)
        default:
            return .none
        }
    }

    fileprivate func handleAXEvent() { refresh() }
}

/// WindowServer connection notify proc. Runs on the main run loop (AppKit pumps the event port),
/// so we reposition synchronously for zero-lag tracking; hop to main only if ever called off-main.
private func borderNotifyProc(_ event: UInt32, _ data: UnsafeMutableRawPointer?,
                              _ length: Int, _ context: UnsafeMutableRawPointer?) {
    guard let context = context else { return }
    let controller = Unmanaged<WindowBorderController>.fromOpaque(context).takeUnretainedValue()
    // Only move/resize carry a bare uint32 window id; other events don't, so read it only then.
    let wid: CGWindowID = (event == PrivateWindowAPI.EVENT_WINDOW_MOVE || event == PrivateWindowAPI.EVENT_WINDOW_RESIZE)
        ? (data?.assumingMemoryBound(to: UInt32.self).pointee ?? 0) : 0
    if Thread.isMainThread {
        controller.handleServerEvent(event: event, wid: wid)
    } else {
        DispatchQueue.main.async { controller.handleServerEvent(event: event, wid: wid) }
    }
}

/// C-callback for AXObserver — recovers the controller from refcon and refreshes on the main queue.
private func axBorderCallback(_ observer: AXObserver, _ element: AXUIElement,
                              _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon = refcon else { return }
    let controller = Unmanaged<WindowBorderController>.fromOpaque(refcon).takeUnretainedValue()
    DispatchQueue.main.async { controller.handleAXEvent() }
}

// MARK: - Private WindowServer bridge (SkyLight + AX→CGWindowID)

/// Resolves the private symbols needed for lag-free window tracking at runtime (no link-time
/// dependency on the private frameworks): `_AXUIElementGetWindow` (AX element → CGWindowID) and
/// SkyLight's `SLSMainConnectionID` / `SLSGetWindowBounds` (window id → live frame). If any fail
/// to resolve, `available` is false and the controller falls back to slow AX positioning.
enum PrivateWindowAPI {
    typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    typealias ConnFn = @convention(c) () -> Int32
    typealias BoundsFn = @convention(c) (Int32, CGWindowID, UnsafeMutablePointer<CGRect>) -> Int32
    typealias RegisterNotifyFn = @convention(c) (UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?) -> Int32
    typealias RequestNotifsFn = @convention(c) (Int32, UnsafeMutablePointer<UInt32>?, Int32) -> Int32
    /// Connection notify proc: (event type, data → *uint32 window id for move/resize, length, context).
    typealias NotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void

    /// WindowServer event type numbers (SkyLight connection notifications).
    static let EVENT_WINDOW_MOVE:   UInt32 = 806
    static let EVENT_WINDOW_RESIZE: UInt32 = 807
    static let EVENT_WINDOW_DESTROY: UInt32 = 1326
    static let EVENT_FRONT_CHANGE:  UInt32 = 1508

    private static let skylight: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)

    private static func sls<T>(_ name: String, _ type: T.Type) -> T? {
        guard let h = skylight, let sym = dlsym(h, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    private static let axGetWindow: AXGetWindowFn? = {
        let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
        guard let sym = dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(sym, to: AXGetWindowFn.self)
    }()

    private static let slsBounds: BoundsFn? = sls("SLSGetWindowBounds", BoundsFn.self)
    private static let registerNotify: RegisterNotifyFn? = sls("SLSRegisterNotifyProc", RegisterNotifyFn.self)
    private static let requestNotifs: RequestNotifsFn? = sls("SLSRequestNotificationsForWindows", RequestNotifsFn.self)
    private static let connectionID: Int32 = sls("SLSMainConnectionID", ConnFn.self)?() ?? 0

    static var available: Bool { axGetWindow != nil && slsBounds != nil && connectionID != 0 }
    static var eventsAvailable: Bool { available && registerNotify != nil && requestNotifs != nil }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let fn = axGetWindow else { return nil }
        var wid: CGWindowID = 0
        return fn(element, &wid) == .success && wid != 0 ? wid : nil
    }

    static func bounds(of wid: CGWindowID) -> CGRect? {
        guard let fn = slsBounds, connectionID != 0 else { return nil }
        var r = CGRect.zero
        return fn(connectionID, wid, &r) == 0 && r.width > 1 && r.height > 1 ? r : nil
    }

    /// Register a WindowServer notify proc (fires in-process on the main run loop for an AppKit app).
    static func register(proc: UnsafeMutableRawPointer, event: UInt32, context: UnsafeMutableRawPointer) {
        _ = registerNotify?(proc, event, context)
    }

    /// Ask the WindowServer to deliver move/resize/… notifications for a specific window.
    static func requestNotifications(for wid: CGWindowID) {
        guard let fn = requestNotifs, connectionID != 0 else { return }
        var w = wid
        _ = fn(connectionID, &w, 1)
    }
}

/// Authentic per-theme window-edge treatment.
enum WindowBorderStyle {
    /// Win9x / Platinum raised 3D edge: highlight top-left, shadow bottom-right, two rings.
    /// `radius` is the inner (window-hugging) corner radius so the bevel follows the window's rounding.
    case bevel(hiOuter: NSColor, hiInner: NSColor, loInner: NSColor, loOuter: NSColor, width: CGFloat, radius: CGFloat)
    /// Solid stroke with independent top/bottom corner radii (XP: top-rounded; System 6: square).
    case solid(color: NSColor, width: CGFloat, topRadius: CGFloat, bottomRadius: CGFloat)
    /// Soft translucent stroke (Aero glass approximation).
    case glow(color: NSColor, width: CGFloat, radius: CGFloat)
    case none

    var width: CGFloat {
        switch self {
        case let .bevel(_, _, _, _, w, _): return w
        case let .solid(_, w, _, _): return w
        case let .glow(_, w, _): return w
        case .none: return 0
        }
    }
    var isNone: Bool { if case .none = self { return true }; return false }
}

/// Draws the theme edge in the ring around its bounds (bounds = window frame grown by `width`).
private final class BorderView: NSView {
    private var style: WindowBorderStyle = .none

    override var isFlipped: Bool { false }   // origin bottom-left: top = high y, left = low x

    func apply(style: WindowBorderStyle) {
        self.style = style
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        switch style {
        case let .bevel(hiOuter, hiInner, loInner, loOuter, width, radius):
            drawBevel(hiOuter: hiOuter, hiInner: hiInner, loInner: loInner, loOuter: loOuter,
                      width: width, radius: radius)
        case let .solid(color, width, topR, bottomR):
            strokePath(width: width, topRadius: topR, bottomRadius: bottomR, color: color)
        case let .glow(color, width, radius):
            strokePath(width: width, topRadius: radius, bottomRadius: radius, color: color)
        case .none:
            break
        }
    }

    /// Rounded raised edge that follows the window corners: two concentric rings, each split by the
    /// bottom-left→top-right diagonal into a light (top-left) and dark (bottom-right) half.
    private func drawBevel(hiOuter: NSColor, hiInner: NSColor, loInner: NSColor, loOuter: NSColor,
                           width w: CGFloat, radius R: CGFloat) {
        let o = (w / 2).rounded()   // outer band thickness
        // Outer band: bounds edge (radius R+w) → inset o (radius R+w-o). Inner band: → inset w (radius R).
        beveledRing(outerInset: 0, innerInset: o, outerRadius: R + w, innerRadius: R + w - o,
                    light: hiOuter, dark: loOuter)
        beveledRing(outerInset: o, innerInset: w, outerRadius: R + w - o, innerRadius: R,
                    light: hiInner, dark: loInner)
    }

    private func beveledRing(outerInset: CGFloat, innerInset: CGFloat,
                             outerRadius: CGFloat, innerRadius: CGFloat, light: NSColor, dark: NSColor) {
        let outer = bounds.insetBy(dx: outerInset, dy: outerInset)
        let inner = bounds.insetBy(dx: innerInset, dy: innerInset)
        let ring = NSBezierPath(roundedRect: outer, xRadius: max(0, outerRadius), yRadius: max(0, outerRadius))
        ring.append(NSBezierPath(roundedRect: inner, xRadius: max(0, innerRadius), yRadius: max(0, innerRadius)).reversed)
        ring.windingRule = .evenOdd

        NSGraphicsContext.saveGraphicsState()
        ring.setClip()
        // Diagonal bottom-left → top-right divides the two tones.
        let tl = NSBezierPath()   // top-left half: top + left edges
        tl.move(to: NSPoint(x: bounds.minX, y: bounds.minY))
        tl.line(to: NSPoint(x: bounds.minX, y: bounds.maxY))
        tl.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY))
        tl.close()
        light.setFill(); tl.fill()
        let br = NSBezierPath()   // bottom-right half: bottom + right edges
        br.move(to: NSPoint(x: bounds.minX, y: bounds.minY))
        br.line(to: NSPoint(x: bounds.maxX, y: bounds.minY))
        br.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY))
        br.close()
        dark.setFill(); br.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func strokePath(width: CGFloat, topRadius: CGFloat, bottomRadius: CGFloat, color: NSColor) {
        let r = bounds.insetBy(dx: width / 2, dy: width / 2)
        let path: NSBezierPath
        if topRadius == bottomRadius {
            path = topRadius > 0 ? NSBezierPath(roundedRect: r, xRadius: topRadius, yRadius: topRadius)
                                 : NSBezierPath(rect: r)
        } else {
            path = NSBezierPath()   // top-rounded, bottom-square (XP): build manually (y-up)
            let tr = min(topRadius, r.width / 2), br = min(bottomRadius, r.width / 2)
            path.move(to: NSPoint(x: r.minX, y: r.minY + br))
            path.line(to: NSPoint(x: r.minX, y: r.maxY - tr))
            path.appendArc(withCenter: NSPoint(x: r.minX + tr, y: r.maxY - tr), radius: tr, startAngle: 180, endAngle: 90, clockwise: true)
            path.line(to: NSPoint(x: r.maxX - tr, y: r.maxY))
            path.appendArc(withCenter: NSPoint(x: r.maxX - tr, y: r.maxY - tr), radius: tr, startAngle: 90, endAngle: 0, clockwise: true)
            path.line(to: NSPoint(x: r.maxX, y: r.minY + br))
            if br > 0 {
                path.appendArc(withCenter: NSPoint(x: r.maxX - br, y: r.minY + br), radius: br, startAngle: 0, endAngle: -90, clockwise: true)
                path.line(to: NSPoint(x: r.minX + br, y: r.minY))
                path.appendArc(withCenter: NSPoint(x: r.minX + br, y: r.minY + br), radius: br, startAngle: -90, endAngle: -180, clockwise: true)
            } else {
                path.line(to: NSPoint(x: r.maxX, y: r.minY))
                path.line(to: NSPoint(x: r.minX, y: r.minY))
            }
            path.close()
        }
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }
}
