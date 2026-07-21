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
        init(wid: UInt32, ctx: CGContext, size: CGSize) { self.wid = wid; self.ctx = ctx; self.size = size }
    }

    private var running = false
    private var borders: [CGWindowID: SkyBorder] = [:]
    private var currentStyle: WindowBorderStyle = .none
    private var wsTokens: [NSObjectProtocol] = []
    private var syncTimer: Timer?
    private var didRegisterEvents = false
    private let hidpi: Bool = (NSScreen.main?.backingScaleFactor ?? 2) >= 2

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
        sync()
    }

    private func stop() {
        running = false
        syncTimer?.invalidate(); syncTimer = nil
        let nc = NSWorkspace.shared.notificationCenter
        wsTokens.forEach { nc.removeObserver($0) }
        wsTokens.removeAll()
        for b in borders.values { skb_destroy(b.wid) }
        borders.removeAll()
    }

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

        if let b = borders[target] {
            if b.size != f.size {                            // resized → recreate (context is size-bound)
                skb_destroy(b.wid)
                borders.removeValue(forKey: target)
            } else {
                if b.origin != f.origin { skb_move(b.wid, Float(f.minX), Float(f.minY)); b.origin = f.origin }
                if b.level != level { skb_order(b.wid, level, target); b.level = level }
                return
            }
        }
        // (Re)create. Shape/position and order the window FIRST, then draw into its context —
        // reshaping after drawing discards the backing content.
        var wid: UInt32 = 0
        guard let ctx = skb_create(Float(f.width), Float(f.height), hidpi, &wid), wid != 0 else { return }
        let b = SkyBorder(wid: wid, ctx: ctx, size: f.size)
        _ = skb_send_to_space(b.wid, target)             // a fresh window is on no space → invisible
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
        guard let b = borders[target], let g = PrivateWindowAPI.bounds(of: target) else { return }
        let f = outerFrame(g)
        if b.size != f.size { apply(target: target, windowBounds: g, level: b.level) }   // resize → recreate
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
        for e in [PrivateWindowAPI.EVENT_WINDOW_MOVE, PrivateWindowAPI.EVENT_WINDOW_RESIZE,
                  PrivateWindowAPI.EVENT_WINDOW_REORDER, PrivateWindowAPI.EVENT_FRONT_CHANGE,
                  PrivateWindowAPI.EVENT_WINDOW_CREATE, PrivateWindowAPI.EVENT_WINDOW_DESTROY] {
            PrivateWindowAPI.register(proc: procPtr, event: e, context: ctx)
        }
    }

    fileprivate func handleServerEvent(event: UInt32, wid: CGWindowID) {
        guard running, !currentStyle.isNone else { return }
        switch event {
        case PrivateWindowAPI.EVENT_WINDOW_MOVE, PrivateWindowAPI.EVENT_WINDOW_RESIZE:
            reposition(wid)
        case PrivateWindowAPI.EVENT_WINDOW_REORDER, PrivateWindowAPI.EVENT_FRONT_CHANGE:
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
    let wid: CGWindowID = (event == PrivateWindowAPI.EVENT_FRONT_CHANGE)
        ? 0 : (data?.assumingMemoryBound(to: UInt32.self).pointee ?? 0)
    if Thread.isMainThread { controller.handleServerEvent(event: event, wid: wid) }
    else { DispatchQueue.main.async { controller.handleServerEvent(event: event, wid: wid) } }
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
