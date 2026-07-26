import AppKit
import ApplicationServices
import SkyLightBridge

/// "Window borders in theme style" — draws an authentic theme-coloured edge around EVERY real
/// window (JankyBorders technique), keeping the z-order correct.
///
/// Each border is our OWN WindowServer window (`SkyLightBridge`), inserted directly above its
/// target at the target's level, so a buried window's border correctly sits behind whatever
/// covers it. Candidate windows come from the public `CGWindowListCopyWindowInfo`; the server-side
/// filter (`skb_filter_windows` → `window_suitable`) keeps only real top-level document/modal
/// windows, so menus, tooltips, sheets and minimized windows never get a border. Live move/resize
/// come from SkyLight connection events (zero-lag), with a slow safety-net poll.
final class WindowBorderController {

    static let shared = WindowBorderController()
    private init() {}

    private final class SkyBorder {
        let wid: UInt32
        let ctx: CGContext
        var size: CGSize
        var level: Int32 = 0
        var origin: CGPoint = CGPoint(x: -99999, y: -99999)
        var onSpace: Bool = false   // did SLSMoveWindowsToManagedSpace succeed? retry until it does
        var hidpi: Bool             // backing scale of the display this border was created for
        init(wid: UInt32, ctx: CGContext, size: CGSize, hidpi: Bool) {
            self.wid = wid; self.ctx = ctx; self.size = size; self.hidpi = hidpi
        }
    }

    private var running = false
    private var borders: [CGWindowID: SkyBorder] = [:]
    private var currentStyle: WindowBorderStyle = .none
    private var wsTokens: [NSObjectProtocol] = []
    private var syncTimer: Timer?
    private var didRegisterEvents = false
    /// Per-app Accessibility observers for window (de)miniaturize. WindowServer has no reliable
    /// minimize event and during the genie the window still reports full on-screen bounds, so the
    /// border would linger over the animation. AX fires the instant minimize begins → drop it then.
    private var axObservers: [pid_t: AXObserver] = [:]

    /// Backing scale of the display a window sits on. `windowBounds` are Quartz global coords
    /// (top-left origin, y-down); convert each NSScreen into that space and pick the one with the
    /// largest overlap, so borders on a non-Retina display don't inherit the main display's 2x
    /// (and vice-versa). Recomputed per window and on every move so a drag across displays retiles.
    private func isHiDPI(for windowBounds: CGRect) -> Bool {
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main else { return true }
        let primaryTop = primary.frame.maxY
        var best: NSScreen?
        var bestArea: CGFloat = 0
        for s in NSScreen.screens {
            let f = s.frame
            let quartz = CGRect(x: f.minX, y: primaryTop - f.maxY, width: f.width, height: f.height)
            let inter = quartz.intersection(windowBounds)
            let area = inter.isNull ? 0 : inter.width * inter.height
            if area > bestArea { bestArea = area; best = s }
        }
        return ((best ?? NSScreen.main)?.backingScaleFactor ?? 2) >= 2
    }

    // MARK: - Lifecycle

    func update() {
        let want = AppSettings.shared.themeWindowBorders
            && AppSettings.shared.dockEnabled
            && !AppSettings.shared.dockOnly
        if want { start() } else { stop() }
    }

    private func start() {
        currentStyle = Self.style(for: RetroFrameTheme.key(),
                                  colors: ThemeManager.shared.activeTheme?.config.chromeColors,
                                  radius: Self.windowCornerRadius())
        guard !running else { restyle(); return }
        running = true
        registerServerEvents()
        setupMinimizeObservers()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            wsTokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                // A newly launched OR (re)activated app gets its minimize observer — activation
                // is also the retry path for an app whose registration failed while it was launching.
                if name == NSWorkspace.didLaunchApplicationNotification || name == NSWorkspace.didActivateApplicationNotification,
                   let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self?.addMinimizeObserver(pid: app.processIdentifier)
                }
                self?.sync()
            })
        }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.sync() }
        RunLoop.main.add(t, forMode: .common)
        syncTimer = t
        sync()
    }

    private func stop() {
        running = false
        syncTimer?.invalidate(); syncTimer = nil
        let nc = NSWorkspace.shared.notificationCenter
        wsTokens.forEach { nc.removeObserver($0) }
        wsTokens.removeAll()
        removeMinimizeObservers()
        for b in borders.values { skb_destroy(b.wid) }
        borders.removeAll()
    }

    // MARK: - Minimize detection (Accessibility)

    private func setupMinimizeObservers() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            addMinimizeObserver(pid: app.processIdentifier)
        }
    }

    fileprivate func addMinimizeObserver(pid: pid_t) {
        guard pid != getpid(), axObservers[pid] == nil else { return }
        var observer: AXObserver?
        // Requires Accessibility permission (the app already uses it); fails gracefully otherwise —
        // then the event/poll path still removes the border, just not as instantly.
        let createErr = AXObserverCreate(pid, axWindowNotify, &observer)
        guard createErr == .success, let observer = observer else { return }
        let appEl = AXUIElementCreateApplication(pid)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        // If the app can't register the notification yet (e.g. still launching → .cannotComplete),
        // do NOT store the observer, so a later app activation/launch retries instead of leaving it
        // permanently ineffective. The miniaturize notification is the one that matters.
        let addErr = AXObserverAddNotification(observer, appEl, kAXWindowMiniaturizedNotification as CFString, ctx)
        guard addErr == .success else { return }
        AXObserverAddNotification(observer, appEl, kAXWindowDeminiaturizedNotification as CFString, ctx)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObservers[pid] = observer
    }

    private func removeMinimizeObservers() {
        for (_, observer) in axObservers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        axObservers.removeAll()
    }

    /// Drop a window's border immediately (called the instant AX reports a minimize).
    fileprivate func dropBorder(for wid: CGWindowID) {
        guard let b = borders[wid] else { return }
        skb_destroy(b.wid)
        borders.removeValue(forKey: wid)
    }

    /// Re-add a border after a window is de-miniaturized (restored from the Dock).
    fileprivate func resync() { sync() }

    private func restyle() {
        currentStyle = Self.style(for: RetroFrameTheme.key(),
                                  colors: ThemeManager.shared.activeTheme?.config.chromeColors,
                                  radius: Self.windowCornerRadius())
        // Recolour every existing border in place.
        for b in borders.values { drawInto(b); skb_flush(b.wid, b.ctx) }
        sync()
    }

    // MARK: - Sync (which windows get a border)

    private func sync() {
        guard running else { return }
        guard !currentStyle.isNone else {
            for b in borders.values { skb_destroy(b.wid) }
            borders.removeAll()
            return
        }
        let windows = Self.onScreenWindows()                 // [(id, top-left-global bounds)]
        var boundsByID = [CGWindowID: CGRect](minimumCapacity: windows.count)
        for w in windows { boundsByID[w.id] = w.bounds }

        // Server-side suitability filter (excludes menus/tooltips/sheets/minimized).
        let candidates = windows.map { $0.id }
        PrivateWindowAPI.requestNotifications(for: candidates)   // deliver move/resize for these
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
        var suitable = Set<CGWindowID>()
        for i in 0..<count {
            let wid = outWID[i]
            guard let b = boundsByID[wid] else { continue }
            suitable.insert(wid)
            apply(target: wid, windowBounds: b, level: outLevel[i])
        }

        // Drop borders whose window is gone / no longer suitable.
        for (wid, b) in borders where !suitable.contains(wid) {
            skb_destroy(b.wid)
            borders.removeValue(forKey: wid)
        }
    }

    /// Border frame (top-left global) = the window grown by the edge width on all sides.
    private func outerFrame(_ windowBounds: CGRect) -> CGRect {
        windowBounds.insetBy(dx: -currentStyle.width, dy: -currentStyle.width)
    }

    /// Create or update the border for one target window.
    private func apply(target: CGWindowID, windowBounds: CGRect, level: Int32) {
        // Skip full-screen / desktop-sized windows.
        if let scr = NSScreen.screens.first(where: { $0.frame.width >= windowBounds.width }),
           windowBounds.width >= scr.frame.width - 1, windowBounds.height >= scr.frame.height - 1 {
            if let b = borders[target] { skb_destroy(b.wid); borders.removeValue(forKey: target) }
            return
        }
        let f = outerFrame(windowBounds)
        let hd = isHiDPI(for: windowBounds)

        if let b = borders[target] {
            // Recreate on a size OR resolution change (the context is bound to both) — e.g. dragging
            // the window onto a display with a different backing scale.
            if b.size != f.size || b.hidpi != hd {
                skb_destroy(b.wid)
                borders.removeValue(forKey: target)
            } else {
                if b.origin != f.origin { skb_move(b.wid, Float(f.minX), Float(f.minY)); b.origin = f.origin }
                if b.level != level { skb_order(b.wid, level, target); b.level = level }
                // Retry a previously-failed space assignment so the border can't stay invisible.
                if !b.onSpace { b.onSpace = (skb_send_to_space(b.wid, target) != 0) }
                return
            }
        }
        // (Re)create. Shape/position and order the window FIRST, then draw into its context —
        // reshaping after drawing discards the backing content.
        var wid: UInt32 = 0
        guard let ctx = skb_create(Float(f.width), Float(f.height), hd, &wid), wid != 0 else { return }
        let b = SkyBorder(wid: wid, ctx: ctx, size: f.size, hidpi: hd)
        b.onSpace = (skb_send_to_space(b.wid, target) != 0)   // a fresh window is on no space → invisible
        skb_set_frame(b.wid, Float(f.minX), Float(f.minY), Float(f.width), Float(f.height))
        b.origin = f.origin
        skb_order(b.wid, level, target)
        b.level = level
        drawInto(b)
        skb_flush(b.wid, b.ctx)
        borders[target] = b
    }

    /// Live reposition from a WindowServer move/resize event (zero-lag during a drag).
    private func reposition(_ target: CGWindowID) {
        guard let b = borders[target] else { return }
        guard let g = PrivateWindowAPI.bounds(of: target) else {
            // No valid bounds anymore (window minimizing / hidden / gone) → drop its border now
            // instead of leaving it hanging over the minimize animation until the next sync.
            skb_destroy(b.wid); borders.removeValue(forKey: target)
            return
        }
        let f = outerFrame(g)
        // Resize OR a cross-display move to a different backing scale → recreate at the new size/res.
        if b.size != f.size || b.hidpi != isHiDPI(for: g) { apply(target: target, windowBounds: g, level: b.level) }
        else if b.origin != f.origin { skb_move(b.wid, Float(f.minX), Float(f.minY)); b.origin = f.origin }
    }

    private func reorderAll() {
        for (target, b) in borders { skb_order(b.wid, b.level, target) }
    }

    private func drawInto(_ b: SkyBorder) {
        Self.drawBorder(currentStyle, into: b.ctx, size: b.size)
    }

    // MARK: - Window enumeration (public CGWindowList; top-left global bounds)

    private struct WindowInfo { let id: CGWindowID; let bounds: CGRect }

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
                  b.width > 40, b.height > 40 else { continue }
            out.append(WindowInfo(id: num, bounds: b))
        }
        return out
    }

    // MARK: - WindowServer events

    private func registerServerEvents() {
        guard PrivateWindowAPI.eventsAvailable, !didRegisterEvents else { return }
        didRegisterEvents = true
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let procPtr = unsafeBitCast(borderNotifyProc as PrivateWindowAPI.NotifyProc, to: UnsafeMutableRawPointer.self)
        let events: [UInt32] = [PrivateWindowAPI.EVENT_WINDOW_MOVE, PrivateWindowAPI.EVENT_WINDOW_RESIZE,
                  PrivateWindowAPI.EVENT_WINDOW_MINIMIZE,
                  PrivateWindowAPI.EVENT_WINDOW_REORDER, PrivateWindowAPI.EVENT_FRONT_CHANGE,
                  PrivateWindowAPI.EVENT_WINDOW_CREATE, PrivateWindowAPI.EVENT_WINDOW_DESTROY]
        for e in Set(events) {
            PrivateWindowAPI.register(proc: procPtr, event: e, context: ctx)
        }
    }

    fileprivate func handleServerEvent(event: UInt32, wid: CGWindowID) {
        guard running, !currentStyle.isNone else { return }
        switch event {
        case PrivateWindowAPI.EVENT_WINDOW_MOVE, PrivateWindowAPI.EVENT_WINDOW_RESIZE:
            reposition(wid)
        case PrivateWindowAPI.EVENT_WINDOW_MINIMIZE:
            // Fires at the START of the minimize (before the genie), unlike the AX notification
            // which only arrives at the end. Drop the border now so it doesn't trail. No-op for
            // our own border windows (their wid isn't a border key); a false positive self-heals
            // on the next sync.
            dropBorder(for: wid)
        case PrivateWindowAPI.EVENT_WINDOW_REORDER, PrivateWindowAPI.EVENT_FRONT_CHANGE:
            // Focus/z-order changed → cheap single-pass re-order of existing borders. (Minimize is
            // handled by the dedicated 816 event + AX, so front-change no longer needs a full sync.)
            reorderAll()
        case PrivateWindowAPI.EVENT_WINDOW_CREATE, PrivateWindowAPI.EVENT_WINDOW_DESTROY:
            sync()
        default: break
        }
    }

    // MARK: - Authentic per-theme edge style

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
            return .bevel(hiOuter: hex(colors?.hilight, "#FFFFFF"), hiInner: hex(colors?.light, "#DFDFDF"),
                          loInner: hex(colors?.shadow, "#808080"), loOuter: hex(colors?.dkShadow, "#000000"),
                          width: 4, radius: R)
        case "macos9":
            return .bevel(hiOuter: NSColor.fromHex("#FFFFFF"), hiInner: NSColor.fromHex("#E4E4E8"),
                          loInner: NSColor.fromHex("#9A9AA2"), loOuter: NSColor.fromHex("#5A5A62"), width: 3, radius: R)
        case "macos6":
            return .solid(color: .black, width: 2, topRadius: R, bottomRadius: R)
        case "win31":
            // Windows 3.1 had a flat (pre-3D) window frame with a crisp dark outline.
            return .solid(color: NSColor.fromHex("#404040"), width: 2, topRadius: R, bottomRadius: R)
        case "nextstep":
            // NeXTSTEP's signature chiseled frame: a crisp 2px bevel, white top-left / black
            // bottom-right, square-cornered. Same primitive as Win98's raised ring, just thinner
            // and hard-edged (radius 0) with the NeXT four-grey ramp (#FFF / #AAA / #555 / #000).
            return .bevel(hiOuter: NSColor.fromHex("#FFFFFF"), hiInner: NSColor.fromHex("#AAAAAA"),
                          loInner: NSColor.fromHex("#555555"), loOuter: NSColor.fromHex("#000000"),
                          width: 2, radius: 0)
        case "winxp":
            return .solid(color: NSColor.fromHex("#2A63D8"), width: 4, topRadius: R, bottomRadius: R)
        case "win7":
            return .glow(color: NSColor.fromHex("#6FB3F0").withAlphaComponent(0.55), width: 6, radius: R)
        default:
            return .none
        }
    }

    // MARK: - Drawing (into a CGContext, bottom-left origin)

    static func drawBorder(_ style: WindowBorderStyle, into ctx: CGContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        ctx.clear(bounds)                       // transparent background (window has alpha)
        ctx.setShouldAntialias(true)
        switch style {
        case let .bevel(hiOuter, hiInner, loInner, loOuter, width, radius):
            let o = (width / 2).rounded()
            beveledRing(ctx, bounds, outerInset: 0, innerInset: o, outerRadius: radius + width, innerRadius: radius + width - o, light: hiOuter, dark: loOuter)
            beveledRing(ctx, bounds, outerInset: o, innerInset: width, outerRadius: radius + width - o, innerRadius: radius, light: hiInner, dark: loInner)
        case let .solid(color, width, topR, _):
            strokeRing(ctx, bounds, width: width, radius: topR, color: color, glow: false)
        case let .glow(color, width, radius):
            strokeRing(ctx, bounds, width: width, radius: radius, color: color, glow: true)
        case .none:
            break
        }
    }

    private static func roundedOrRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        let rad = min(max(0, radius), min(r.width, r.height) / 2)
        return rad > 0 ? CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
                       : CGPath(rect: r, transform: nil)
    }

    /// Raised 3D ring: clip to the band between outer and inner rounded rects, then paint the
    /// light half (top-left) and dark half (bottom-right) split by the bottom-left→top-right diagonal.
    private static func beveledRing(_ ctx: CGContext, _ bounds: CGRect, outerInset: CGFloat, innerInset: CGFloat,
                                    outerRadius: CGFloat, innerRadius: CGFloat, light: NSColor, dark: NSColor) {
        ctx.saveGState()
        ctx.addPath(roundedOrRect(bounds.insetBy(dx: outerInset, dy: outerInset), outerRadius))
        ctx.addPath(roundedOrRect(bounds.insetBy(dx: innerInset, dy: innerInset), innerRadius))
        ctx.clip(using: .evenOdd)
        ctx.setFillColor(light.cgColor)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: bounds.minX, y: bounds.minY)); ctx.addLine(to: CGPoint(x: bounds.minX, y: bounds.maxY)); ctx.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY)); ctx.closePath()
        ctx.fillPath()
        ctx.setFillColor(dark.cgColor)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: bounds.minX, y: bounds.minY)); ctx.addLine(to: CGPoint(x: bounds.maxX, y: bounds.minY)); ctx.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY)); ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
    }

    private static func strokeRing(_ ctx: CGContext, _ bounds: CGRect, width: CGFloat, radius: CGFloat, color: NSColor, glow: Bool) {
        ctx.saveGState()
        let r = bounds.insetBy(dx: width / 2, dy: width / 2)
        ctx.addPath(roundedOrRect(r, radius))
        ctx.setLineWidth(width)
        ctx.setStrokeColor(color.cgColor)
        if glow { ctx.setShadow(offset: .zero, blur: 8, color: color.cgColor) }
        ctx.strokePath()
        ctx.restoreGState()
    }
}

/// WindowServer connection notify proc (runs on the main run loop for an AppKit app).
private func borderNotifyProc(_ event: UInt32, _ data: UnsafeMutableRawPointer?,
                              _ length: Int, _ context: UnsafeMutableRawPointer?) {
    guard let context = context else { return }
    let controller = Unmanaged<WindowBorderController>.fromOpaque(context).takeUnretainedValue()
    // The payload format for these private events is undocumented and varies by event. Only read a
    // window id when the payload is actually large enough — never dereference past `length`. Use an
    // unaligned load since `data` isn't guaranteed 4-byte aligned. A zero id is a harmless no-op.
    let wid: CGWindowID
    if event == PrivateWindowAPI.EVENT_FRONT_CHANGE {
        wid = 0
    } else if let data = data, length >= MemoryLayout<UInt32>.size {
        wid = data.loadUnaligned(fromByteOffset: 0, as: UInt32.self)
    } else {
        wid = 0
    }
    if Thread.isMainThread { controller.handleServerEvent(event: event, wid: wid) }
    else { DispatchQueue.main.async { controller.handleServerEvent(event: event, wid: wid) } }
}

/// Private AX helper (`_AXUIElementGetWindow`, in HIServices): maps an AXUIElement window to its
/// CGWindowID. Resolved via `dlsym(RTLD_DEFAULT,…)` rather than `@_silgen_name` so that if Apple
/// ever removes the symbol the app still LAUNCHES (a hard link would make dyld abort at startup);
/// the callback then simply falls back to a full re-sync.
private let axUIElementGetWindow: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, "_AXUIElementGetWindow") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
}()

/// AX observer callback (main run loop): a window was (de)miniaturized. `element` is normally that
/// window, but some apps deliver the application element instead — then `_AXUIElementGetWindow`
/// yields no id, so fall back to a full re-sync rather than silently doing nothing.
private func axWindowNotify(_ observer: AXObserver, _ element: AXUIElement,
                            _ notification: CFString, _ context: UnsafeMutableRawPointer?) {
    guard let context = context else { return }
    let controller = Unmanaged<WindowBorderController>.fromOpaque(context).takeUnretainedValue()
    var wid: CGWindowID = 0
    let gotWid = (axUIElementGetWindow?(element, &wid) == .success) && wid != 0
    if (notification as String) == (kAXWindowMiniaturizedNotification as String) {
        if gotWid { controller.dropBorder(for: wid) }   // remove the specific border, before the genie
        else { controller.resync() }                    // couldn't resolve the window → re-sync (drops off-screen ones)
    } else {
        controller.resync()                             // de-miniaturized (restored) → re-add its border
    }
}

// MARK: - Private SkyLight bridge (events + live bounds; window creation lives in SkyLightBridge.c)

enum PrivateWindowAPI {
    typealias ConnFn = @convention(c) () -> Int32
    typealias BoundsFn = @convention(c) (Int32, CGWindowID, UnsafeMutablePointer<CGRect>) -> Int32
    typealias RegisterNotifyFn = @convention(c) (UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?) -> Int32
    typealias RequestNotifsFn = @convention(c) (Int32, UnsafeMutablePointer<UInt32>?, Int32) -> Int32
    typealias NotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void

    static let EVENT_WINDOW_MOVE:    UInt32 = 806
    static let EVENT_WINDOW_RESIZE:  UInt32 = 807
    static let EVENT_WINDOW_REORDER: UInt32 = 808
    static let EVENT_WINDOW_MINIMIZE: UInt32 = 816   // fires at minimize START (before the genie)
    static let EVENT_WINDOW_CREATE:  UInt32 = 1325
    static let EVENT_WINDOW_DESTROY: UInt32 = 1326
    static let EVENT_FRONT_CHANGE:   UInt32 = 1508

    private static let skylight: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
    private static func sls<T>(_ name: String, _ type: T.Type) -> T? {
        guard let h = skylight, let sym = dlsym(h, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }
    private static let slsBounds: BoundsFn? = sls("SLSGetWindowBounds", BoundsFn.self)
    private static let registerNotify: RegisterNotifyFn? = sls("SLSRegisterNotifyProc", RegisterNotifyFn.self)
    private static let requestNotifs: RequestNotifsFn? = sls("SLSRequestNotificationsForWindows", RequestNotifsFn.self)
    private static let connectionID: Int32 = sls("SLSMainConnectionID", ConnFn.self)?() ?? 0

    static var eventsAvailable: Bool { slsBounds != nil && registerNotify != nil && connectionID != 0 }

    static func bounds(of wid: CGWindowID) -> CGRect? {
        guard let fn = slsBounds, connectionID != 0 else { return nil }
        var r = CGRect.zero
        return fn(connectionID, wid, &r) == 0 && r.width > 1 && r.height > 1 ? r : nil
    }
    static func register(proc: UnsafeMutableRawPointer, event: UInt32, context: UnsafeMutableRawPointer) {
        _ = registerNotify?(proc, event, context)
    }
    static func requestNotifications(for wids: [CGWindowID]) {
        guard let fn = requestNotifs, connectionID != 0, !wids.isEmpty else { return }
        var arr = wids
        _ = fn(connectionID, &arr, Int32(arr.count))
    }
}

/// Authentic per-theme window-edge treatment.
enum WindowBorderStyle {
    case bevel(hiOuter: NSColor, hiInner: NSColor, loInner: NSColor, loOuter: NSColor, width: CGFloat, radius: CGFloat)
    case solid(color: NSColor, width: CGFloat, topRadius: CGFloat, bottomRadius: CGFloat)
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
