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
/// Square corners come two ways. The global default NSConvolutionOverride1 is the window corner
/// radius an AppKit app reads when it launches: 0.5 makes every window it opens square (0 means
/// "not set"; measured on macOS 27 on the window's own alpha, 15 Sep 2026 — the sibling key
/// NSSplitViewItemGlassMinimumCornerRadius only concerns sidebars and does nothing here). It is
/// written through SystemTweaksAdapter while a bar style runs, and Finder is relaunched to pick
/// it up. Apps that were already running keep their rounded windows until they are reopened.
///
/// The lights styles (Mac OS X, Snow Leopard) are the small version: only the three traffic
/// lights are covered, at the exact spots the Accessibility API reports for the real ones,
/// and the rest of the title bar is left as it is.
///
/// The bar sits ABOVE the window, outside it, not over its title bar: the real title bar and
/// its toolbar stay whole and clickable, and the bar is the window's own (drag it, double-click
/// it, its buttons are the only controls there). What remains of the real bar is its three
/// lights, and those are hidden under a patch that wears the bar's own colour, photographed
/// off the screen next to them (`NativeBarSampler`). A window with no room above it is moved
/// down by the bar's height, so every window can carry its bar. Apps running before the bars
/// went on keep their rounded corners until they are reopened; nothing is painted over them.
///
/// Diagnostics: RETROMAC_TITLEBAR_STATS=1 logs event and sync rates every 10 s. Measured
/// 15 Sep 2026 with 10 windows, bars and borders on: 2.1 syncs/s (the timer), no reorder
/// events at idle, RetroMac 3–7 % CPU in every mode — no feedback loop, no case for a shared
/// window service yet.
final class TitleBarOverlayController {

    static let shared = TitleBarOverlayController()
    private init() {}

    enum Style: CaseIterable {
        case system6, system7, platinum        // the Mac bars
        case win31, win98, luna, aero          // the Windows bars (95, 98 and Me share win98)
        case aquaLights, snowLights            // the three lights only (Mac OS X, Snow Leopard, Mountain Lion)
        var isBar: Bool { self != .aquaLights && self != .snowLights }
        /// Windows caption buttons cluster on the right; the Mac's close box sits on the left.
        var isWindows: Bool { self == .win31 || self == .win98 || self == .luna || self == .aero }
    }

    private final class Overlay {
        let panel: NSPanel
        let view: TitleBarOverlayView
        var bounds: CGRect          // target bounds, top-left global
        var level: Int32
        let pid: pid_t
        /// The panel over the real lights (bar styles only): a photograph of the bar beside them.
        var patch: NSPanel?
        var patchView: LightsPatchView?
        var patchSampledFront: Bool?   // the front state the sample was taken in
        var sampleGeneration = 0       // the request whose picture is still wanted
        var sampleRetryAfter = Date.distantPast   // a failed capture is not repeated every sync
        init(panel: NSPanel, view: TitleBarOverlayView, bounds: CGRect, level: Int32, pid: pid_t) {
            self.panel = panel; self.view = view; self.bounds = bounds; self.level = level; self.pid = pid
        }
    }

    private var running = false
    var isRunning: Bool { running && style != nil }
    /// Whether the real windows are being squared right now (bar styles only).
    var squaresCorners: Bool { running && style?.isBar == true }
    /// The window corner radius the running style asks macOS for: square under a bar (0.5 is
    /// the smallest value the key takes; 0 means unset). Nil under the lights and when nothing
    /// runs. The lights used to ask for 5 pt, the top corner of a Mac OS X window from Aqua
    /// through Snow Leopard, but the key is a global default every app reads at launch and it
    /// puts a mask on the window: Webex started under it showed every participant grey while
    /// its own camera preview ran (the received tiles are hosted layers from its media process,
    /// and those do not survive a window mask). Under the lights the windows keep the system's
    /// rounding; a bar needs the square corner, so bar styles keep the key, and the Settings
    /// row says what that can do to video apps.
    var desiredCornerRadius: CGFloat? {
        guard running, let style else { return nil }
        return Self.cornerRadius(for: style)
    }
    static func cornerRadius(for style: Style) -> CGFloat? { style.isBar ? 0.5 : nil }
    /// The rounding of the bar's own top corners (Luna, Aero); the frame's sides stop under it.
    var barCornerRadius: CGFloat { style.map { Self.barCornerRadius(for: $0) } ?? 0 }
    static func barCornerRadius(for style: Style) -> CGFloat {
        switch style { case .luna: return 8; case .aero: return 6; default: return 0 }
    }
    /// How much the bar adds above each window while a bar style runs (0 otherwise), for the
    /// border to frame and the zoom to allow for.
    var barAboveHeight: CGFloat { squaresCorners ? Self.stripHeight(style!) : 0 }
    /// The same for one window: 0 when this window has no bar (excluded app, screen-sized,
    /// lights style, or not yet measured).
    func barHeight(for wid: CGWindowID) -> CGFloat {
        guard let o = overlays[wid], o.view.isBarPanel else { return 0 }
        return barAboveHeight
    }
    private var style: Style?
    private var excluded: Set<String> = []
    private var overlays: [CGWindowID: Overlay] = [:]
    private var axWindows: [CGWindowID: AXUIElement] = [:]
    private var wsTokens: [NSObjectProtocol] = []
    private var syncTimer: Timer?

    // MARK: - Lifecycle

    static func style(for key: String) -> Style? {
        switch key {
        case "macos6":      return .system6
        case "system7":     return .system7   // the striped bar at 256 colours
        case "macos9":      return .platinum
        case "win31":       return .win31
        case "win98":       return .win98      // Windows 95, 98 and Me
        case "winxp":       return .luna
        case "win7":        return .aero
        case "macosx":      return .aquaLights
        case "snowleopard": return .snowLights // and Mountain Lion, which declares the same chrome
        default:            return nil
        }
    }

    /// Every control on the bar is driven through Accessibility; without the permission the
    /// bar would hide the real buttons behind ones that do nothing. Settings ▸ Themes says so.
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    func update() {
        let want = AppSettings.shared.themeTitleBars
            && AppSettings.shared.dockEnabled
            && !AppSettings.shared.dockOnly
            && Self.accessibilityGranted
            && Self.style(for: RetroFrameTheme.key()) != nil   // an unsupported theme runs nothing at all
        if want { start() } else { stop() }
    }

    private func start() {
        let newStyle = Self.style(for: RetroFrameTheme.key())
        excluded = Set(AppSettings.shared.themeTitleBarsExcludedApps)
        if running {
            if newStyle != style {
                if newStyle?.isBar != true { undoAutoGeometry() }   // no bar, no room needed above
                style = newStyle; stopOverlays(); squareTheRealCorners()
            }
            // Same style, other theme (95 → 98 → Me, a Plus! scheme): the colours come from the
            // theme at draw time, so every bar draws again.
            Self.classicIcons.removeAll()   // another theme, other pictures
            for o in overlays.values { o.view.needsDisplay = true }
            takeCommandM()
            sync()
            return
        }
        style = newStyle
        running = true
        takeCommandM()
        // A hung app must not hang RetroMac: every Accessibility request this process makes
        // gives up after half a second instead of the six-second default. Process-wide, which
        // also covers the observers and the minimised-window tracker.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        squareTheRealCorners()
        WindowBorderController.shared.ensureServerEvents()   // move/resize/minimise arrive through it
        WindowBorderController.shared.ensureObservers()      // and closed windows, through Accessibility
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            wsTokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if name == NSWorkspace.didTerminateApplicationNotification, let pid = app?.processIdentifier {
                    Self.bundleIDs.removeValue(forKey: pid)
                    Self.icons.removeValue(forKey: pid)
                    Self.classicIcons.removeValue(forKey: pid)
                    WindowBorderController.shared.removeMinimizeObserver(pid: pid)
                } else if let pid = app?.processIdentifier {
                    // A new or re-activated app needs its AX observer (closed/minimised windows)
                    // whether or not the borders are running.
                    WindowBorderController.shared.addMinimizeObserver(pid: pid)
                }
                self.sync()
            })
        }
        // A safety net behind the WindowServer and Accessibility events, not the main path.
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.sync() }
        RunLoop.main.add(t, forMode: .common)
        syncTimer = t
        sync()
    }

    private func stop() {
        guard running else { return }
        running = false
        MinimizeZoom.shared.setHotKey(false)
        syncGeneration += 1
        syncTimer?.invalidate(); syncTimer = nil
        let nc = NSWorkspace.shared.notificationCenter
        wsTokens.forEach { nc.removeObserver($0) }
        wsTokens.removeAll()
        undoAutoGeometry()   // before the element cache goes
        stopOverlays()
        WindowBorderController.shared.releaseObserversIfIdle()
        squareTheRealCorners()   // reconciles without the corner key now
    }

    /// Under the theme without a dock, ⌘M minimises the front window the way the bar's box
    /// does — the picture zooms away, no shrinking into a corner (`MinimizeZoom`).
    private func takeCommandM() {
        MinimizeZoom.shared.onCommandM = { [weak self] in self?.minimizeFront() }
        MinimizeZoom.shared.setHotKey(MinimizeZoom.wanted && style?.isBar == true)
    }

    /// ⌘M: the front window with a bar goes through the bar's own minimise; one without (an
    /// app left alone, a panel) is minimised plainly, so the key is never dead.
    func minimizeFront() {
        if let o = overlays[frontWindowID] { perform(.minimize, on: frontWindowID, pid: o.pid); return }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let ref else { return }
        let w = ref as! AXUIElement
        Self.axQueue.async { AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
    }

    /// Write (or withdraw) the corner key through the adapter that handles the theme's own
    /// "Classic Finder" tweaks, so it is snapshotted and put back with them. Only while a theme
    /// is on: when the theme is going off, ThemeManager's restore has the last word.
    private func squareTheRealCorners() {
        let wanted = squaresCorners
        guard AppSettings.shared.dockEnabled, let theme = ThemeManager.shared.activeTheme else { return }
        SystemTweaksAdapter.apply(for: theme.config, isBuiltIn: theme.isBuiltIn)
        if wanted {
            SystemTweaksAdapter.showCornerHintIfNeeded(for: theme.config, squareCorners: true) { [weak self] in self?.squaresCorners == true }
        }
    }

    private func stopOverlays() {
        for o in overlays.values { o.panel.alphaValue = 0; o.patch?.alphaValue = 0; o.panel.orderOut(nil); o.patch?.orderOut(nil) }
        overlays.removeAll()
        axWindows.removeAll()
        lightOffsets.removeAll()
        lightOffsetsRetry.removeAll()
        titles.removeAll()
        zoomedFrom.removeAll()
        zoomedTo.removeAll()
    }

    // MARK: - Sync

    private var resampleTimer: Timer?
    private var remeasureTimer: Timer?
    private var remeasurePending: Set<CGWindowID> = []
    private var lastOrderSignature: [CGWindowID] = []
    private var frontWindowID: CGWindowID = 0
    private var reorderDue = false
    private var syncInFlight = false
    private var syncPending = false
    /// The window list is the expensive half of a sync (3 ms with a dozen windows, mostly the
    /// titles) and does not need the main thread; the dock's magnification does.
    private static let listQueue = DispatchQueue(label: "com.retromac.titlebar.windowlist", qos: .userInitiated)

    private func sync() {
        guard running, style != nil else { return }
        if syncInFlight { syncPending = true; return }
        syncInFlight = true
        let generation = syncGeneration
        Self.listQueue.async {
            let (windows, order) = Self.onScreenWindows()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.syncInFlight = false
                if generation == self.syncGeneration { self.finishSync(windows, order: order) }
                if self.syncPending { self.syncPending = false; self.sync() }
            }
        }
    }

    /// Bumped by stop(), so a list fetched for a run that has ended is thrown away.
    private var syncGeneration = 0

    private func finishSync(_ list: [WindowInfo], order: [CGWindowID]) {
        guard running, let style else { return }
        // The permission can go away while we run; without it the bars would keep drawing
        // buttons that do nothing and patches that swallow clicks on the real lights.
        guard AXIsProcessTrusted() else { stop(); return }
        let t0 = Date()
        defer { count("sync", seconds: Date().timeIntervalSince(t0)) }
        var windows = list
        for i in windows.indices { windows[i].bundleID = Self.bundleID(for: windows[i].pid) }
        // Re-order only when the z-order actually changed since the last pass. A periodic
        // re-order of every overlay made AppKit revisit our whole window list every three
        // seconds, dock included. Two things count as a change: the other apps' windows in a
        // new order, and one of our panels no longer above its window — Chrome opening a tab
        // raises its window over the lights without a reorder event the WindowServer would
        // tell us about. (Comparing the whole list including our panels re-ordered every
        // second: our own re-order changes that list.)
        let others = windows.map { $0.id }
        var index = [CGWindowID: Int](minimumCapacity: order.count)
        for (i, wid) in order.enumerated() { index[wid] = i }
        let buried = overlays.contains { target, o in
            guard let t = index[target] else { return false }
            let p = index[CGWindowID(o.panel.windowNumber)] ?? Int.max
            let q = o.patch.map { index[CGWindowID($0.windowNumber)] ?? Int.max } ?? 0
            return p > t || q > t
        }
        reorderDue = others != lastOrderSignature || buried
        if reorderDue { lastOrderSignature = others; count(buried ? "reorder.buried" : "reorder") }
        var infoByID = [CGWindowID: WindowInfo](minimumCapacity: windows.count)
        for w in windows { infoByID[w.id] = w }

        let candidates = windows.map { $0.id }
        let tFilter = Date()
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
        self.count("sync.filter", seconds: Date().timeIntervalSince(tFilter))
        // The front window: the first suitable one, in z-order, that belongs to the active app.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        let screens = NSScreen.screens
        var frontWID: CGWindowID = 0
        var suitable = Set<CGWindowID>()
        for i in 0..<count {
            let wid = outWID[i]
            guard let info = infoByID[wid] else { continue }
            if frontWID == 0, info.pid == frontPID {
                frontWID = wid
                if wid != frontWindowID {
                    // A title that came through Accessibility (no name on the window list) is
                    // asked for again when its window comes forward: a document or tab may
                    // have changed. (The WindowServer's front-change event names no window.)
                    if Self.refreshesTitle(titles[wid]?.title) { titles.removeValue(forKey: wid) }
                    frontWindowID = wid
                }
            }
            if excluded.contains(info.bundleID) { continue }
            suitable.insert(wid)
            apply(info, level: outLevel[i], style: style, isFront: wid == frontWID, screens: screens)
        }
        for wid in overlays.keys where !suitable.contains(wid) { forget(wid) }
        if Date() >= nextPrune {
            nextPrune = Date().addingTimeInterval(30)
            pruneCaches(present: Set(infoByID.keys))
        }
    }

    /// The screen a window mostly sits on, in Quartz (top-left) coordinates.
    static func screen(for bounds: CGRect, screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        let top = primaryTop(screens)
        return screens.max(by: { quartz($0.frame, top).intersection(bounds).area < quartz($1.frame, top).intersection(bounds).area })
    }

    static func primaryTop(_ screens: [NSScreen] = NSScreen.screens) -> CGFloat {
        (screens.first(where: { $0.frame.origin == .zero }) ?? screens.first)?.frame.maxY ?? 0
    }

    static func quartz(_ r: NSRect, _ top: CGFloat = primaryTop()) -> CGRect {
        CGRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height)
    }

    /// A window the size of its own screen is native full screen (or as good as): leave it.
    static func isScreenSized(_ bounds: CGRect, screens: [NSScreen] = NSScreen.screens) -> Bool {
        guard let scr = screen(for: bounds, screens: screens) else { return false }
        return bounds.width >= scr.frame.width - 1 && bounds.height >= scr.frame.height - 1
    }

    private func apply(_ info: WindowInfo, level: Int32, style: Style, isFront: Bool, screens: [NSScreen]) {
        if let until = leaving[info.id] {
            if Date() < until { return }
            leaving.removeValue(forKey: info.id)
        }
        if Self.isScreenSized(info.bounds, screens: screens) { drop(for: info.id); return }
        let frame: NSRect
        var lights: [ChromeButtonKind: NSRect] = [:]
        var deadZoneWidth: CGFloat = 0
        let drawStyle = style
        if style.isBar {
            frame = Self.barFrame(for: info.bounds, style: style)
            deadZoneWidth = 0   // nothing native lies under a bar that sits above the window
            _ = lightOffsets(for: info)   // measured for the patch, not needed for the bar itself
        } else {
            // The panel is just big enough for the three lights, wherever this window keeps
            // them; without the measurement there is nothing to draw.
            guard let offsets = lightOffsets(for: info) else {
                if Self.statsEnabled { print("[TitleBar] no light offsets for \(info.ownerName) wid=\(info.id) retry=\(String(describing: lightOffsetsRetry[info.id])) axRetry=\(String(describing: axWindowRetry[info.id]))") }
                drop(for: info.id); return
            }
            (frame, lights) = Self.lightsFrame(for: info.bounds, offsets: offsets)
        }
        let title = drawStyle.isBar ? title(for: info) : ""
        let icon: NSImage?
        if drawStyle == .platinum {
            icon = Self.classicIcon(for: info.pid)   // the theme's icon, or its generic one
        } else if drawStyle.isWindows && drawStyle != .win31 {
            icon = Self.icon(for: info.pid)
        } else {
            icon = nil
        }
        let zoomed = zoomedTo[info.id] != nil

        if let o = overlays[info.id] {
            o.bounds = info.bounds
            if o.panel.frame != frame { o.panel.setFrame(frame, display: false) }
            if style.isBar { makeRoom(for: o, info: info, screens: screens); updatePatch(o, info: info, isFront: isFront) }
            // The z-order is re-asserted on the WindowServer's reorder and front-change events
            // (`handleServerEvent`); here only when the level changed, and once every few
            // seconds as a safety net. Ordering every overlay every pass was most of the 7 ms a
            // sync cost, and 7 ms twice a second is a dropped frame in the dock's magnification.
            if o.level != level || reorderDue {
                o.level = level
                order(o, above: info.id)
            }
            o.view.configure(style: drawStyle, title: title, icon: icon, isFront: isFront, lights: lights,
                             deadZoneWidth: deadZoneWidth, zoomed: zoomed)
            return
        }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // The panels take the mouse, always. A bar sits above the window, where nothing native
        // needs the click; the lights panel covers the real lights and a few points around them.
        // They used to ignore the mouse until something noticed the pointer arriving: first a
        // global mouse monitor (which cost the dock its smoothness), then a 25 Hz poll — and
        // a click in the 40 ms before the poll went to the real light underneath, so the
        // window minimised natively with our lights still sitting on it. The tracking area
        // gives the view its own hover now.
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        let view = TitleBarOverlayView(frame: NSRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        var content: NSView = view
        if style == .aero {
            // Real Aero: the desktop behind the bar, blurred, with the tints painted over it.
            // The glass is a sibling under the drawing view, not a subview of it: a subview
            // would sit on top of what the view draws.
            let container = NSView(frame: view.bounds)
            let glass = NSVisualEffectView(frame: view.bounds)
            glass.autoresizingMask = [.width, .height]
            glass.blendingMode = .behindWindow
            glass.material = .fullScreenUI
            glass.state = .active
            glass.appearance = NSAppearance(named: .aqua)
            // The glass follows the bar's rounded top corners: the drawing view clips itself,
            // the glass needs a mask of the same outline (stretchable, so any width fits).
            glass.maskImage = TitleBarOverlayView.topCornersMask(radius: Self.barCornerRadius(for: .aero), height: frame.height)
            container.addSubview(glass)
            container.addSubview(view)
            content = container
        }
        view.configure(style: drawStyle, title: title, icon: icon, isFront: isFront, lights: lights,
                       deadZoneWidth: deadZoneWidth, zoomed: zoomed)
        view.onAction = { [weak self] kind in self?.perform(kind, on: info.id, pid: info.pid) }
        view.onActivate = { [weak self] in self?.activate(info.id, pid: info.pid) }
        view.onDrag = { [weak self] delta in self?.drag(info.id, pid: info.pid, by: delta) }
        view.onDragEnd = { [weak self] in self?.endDrag() }
        view.onPress = { [weak self] in self?.press(info.id, pid: info.pid) }
        panel.contentView = content
        let o = Overlay(panel: panel, view: view, bounds: info.bounds, level: level, pid: info.pid)
        overlays[info.id] = o
        panel.orderFrontRegardless()
        order(o, above: info.id)
        if style.isBar { makeRoom(for: o, info: info, screens: screens); updatePatch(o, info: info, isFront: isFront) }
    }

    // MARK: - Room above, and the patch over the lights

    /// A window whose top edge leaves no room for the bar is moved down until there is: the
    /// bar is part of the window now, and no title bar ever went above the screen. Not while
    /// the user is dragging it with the bar, to avoid a tug of war.
    private func makeRoom(for o: Overlay, info: WindowInfo, screens: [NSScreen]) {
        // Not while a drag is on, ours or the app's own: moving a window the user is holding
        // is a tug of war.
        guard dragOrigin == nil, NSEvent.pressedMouseButtons == 0,
              let scr = Self.screen(for: info.bounds, screens: screens) else { return }
        let top = Self.primaryTop(screens)
        let usableTop = top - scr.visibleFrame.maxY   // Quartz y of the first usable row (below the menu bar)
        let need = usableTop + Self.stripHeight(style ?? .luna) - info.bounds.minY
        guard need > 0, let w = axWindow(info.id, pid: info.pid) else { return }
        var target = CGRect(x: info.bounds.minX, y: info.bounds.minY + need, width: info.bounds.width, height: info.bounds.height)
        // A window as tall as the screen would now end under the taskbar or the Dock: take the
        // overhang off its height, as far as the app allows.
        var usableBottom = top - scr.visibleFrame.minY
        if let bar = DockController.shared.barScreenFrame, bar.intersects(scr.frame), bar.midY < scr.frame.midY {
            usableBottom = min(usableBottom, top - bar.maxY)
        }
        let overhang = target.maxY - usableBottom
        if overhang > 0 { target.size.height = max(100, target.height - overhang) }
        guard let reached = Self.setFrame(target, of: w) else { return }
        // Remembered, so the window goes back where it was when the bars go off — unless the
        // user has moved or sized it since (then it is theirs to keep).
        if autoGeometry[info.id] == nil { autoGeometry[info.id] = (before: info.bounds, after: reached) }
        else { autoGeometry[info.id]?.after = reached }
    }

    private var autoGeometry: [CGWindowID: (before: CGRect, after: CGRect)] = [:]

    /// Put back every window `makeRoom` moved, if it still sits where we left it.
    private func undoAutoGeometry() {
        for (wid, g) in autoGeometry {
            guard let now = PrivateWindowAPI.bounds(of: wid), Self.roughlySame(now, g.after),
                  let w = axWindows[wid] else { continue }
            _ = Self.setFrame(g.before, of: w)
        }
        autoGeometry.removeAll()
    }

    /// Create or refresh the patch that hides the real lights. The sample is retaken when the
    /// window's front state changes, because the real bar changes colour with it.
    private func updatePatch(_ o: Overlay, info: WindowInfo, isFront: Bool) {
        guard let offsets = lightOffsets[info.id], let close = offsets[.close] else { return }
        let last = offsets.values.map { $0.maxX }.max() ?? close.maxX
        let top = offsets.values.map { $0.minY }.min() ?? close.minY
        let bottom = offsets.values.map { $0.maxY }.max() ?? close.maxY
        // The patch: from just left of the close light to just right of the last one.
        let rel = CGRect(x: close.minX - 3, y: top - 2, width: last - close.minX + 6, height: bottom - top + 4)
        let quartz = CGRect(x: info.bounds.minX + rel.minX, y: info.bounds.minY + rel.minY, width: rel.width, height: rel.height)
        let frame = Self.appKitFrame(topLeft: quartz, height: quartz.height)
        var created = false
        if o.patch == nil {
            created = true
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            // The patch takes the mouse: a hover would otherwise reach the hidden green light,
            // whose "Move & Resize" popover would pop up out of nowhere. A click there behaves
            // like a click on the bar: it brings the window forward, and a drag moves it.
            panel.ignoresMouseEvents = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
            panel.animationBehavior = .none
            let v = LightsPatchView(frame: NSRect(origin: .zero, size: frame.size))
            v.autoresizingMask = [.width, .height]
            v.onActivate = o.view.onActivate
            v.onDrag = o.view.onDrag
            v.onDragEnd = o.view.onDragEnd
            v.onPress = o.view.onPress
            panel.contentView = v
            o.patch = panel
            o.patchView = v
            panel.orderFrontRegardless()
        } else if o.patch!.frame != frame {
            o.patch!.setFrame(frame, display: false)
        }
        if o.patchSampledFront != isFront, Date() >= o.sampleRetryAfter {
            o.patchSampledFront = isFront
            // A strip of the real bar from the gap between the first two lights: plain on every
            // title bar, and away from the corner, which on a window opened before the bars went
            // on still curves and lets the desktop through.
            let gapStart = close.maxX + 2
            let gapEnd = (offsets[.minimize]?.minX ?? (close.maxX + 7)) - 2
            let sample = CGRect(x: info.bounds.minX + gapStart, y: quartz.minY, width: max(2, gapEnd - gapStart), height: quartz.height)
            let wid = info.id
            // The sample lies under the patch itself: hide the patch for the photograph, and
            // let the mouse through to the real lights until there is a picture to stand in
            // for them. Only the newest request may deliver: two in flight (front, and back
            // again) used to let whichever finished last win.
            o.sampleGeneration += 1
            let generation = o.sampleGeneration
            o.patch?.alphaValue = 0
            o.patch?.ignoresMouseEvents = true
            count("sample")
            NativeBarSampler.sample(sample) { [weak self, weak requester = o] image in
                // The overlay that asked must still be the one on duty: a theme switch makes a
                // new overlay for the same window, whose own count starts at one again.
                guard let self, let o = self.overlays[wid], o === requester, o.sampleGeneration == generation else { return }
                guard let image else {
                    // No picture: the real lights stay visible and usable, and a later sync
                    // asks again, not before five seconds have passed.
                    o.patchSampledFront = nil
                    o.sampleRetryAfter = Date().addingTimeInterval(5)
                    self.count("sample.failed")
                    return
                }
                o.patchView?.image = image
                o.patch?.alphaValue = 1
                o.patch?.ignoresMouseEvents = false
            }
        }
        if created || reorderDue, let patch = o.patch { orderPatch(patch, above: info.id) }
    }

    private func orderPatch(_ patch: NSPanel, above target: CGWindowID) {
        count("order")
        patch.level = overlays[target]?.panel.level ?? .normal
        patch.order(.above, relativeTo: Int(target))
    }

    /// Directly above the target, at the target's level, so a buried window's bar is buried with
    /// it. AppKit's cross-application ordering does what the SkyLight transaction does for the
    /// border windows; the transaction itself leaves an AppKit window invisible.
    private func order(_ o: Overlay, above target: CGWindowID) {
        count("order")
        o.panel.level = NSWindow.Level(rawValue: Int(o.level))
        // Above the border window when there is one, so the bar is never under the frame.
        let anchor = WindowBorderController.shared.borderWindowID(for: target) ?? target
        o.panel.order(.above, relativeTo: Int(anchor))
        if let patch = o.patch { orderPatch(patch, above: target) }
    }

    /// Height of the bar above the window: the era's own, since nothing native has to be
    /// covered any more. Windows 95/98/Me: the 22 pt caption the theme's own windows use, and
    /// the 2 pt of face under it.
    static func stripHeight(_ style: Style) -> CGFloat {
        switch style {
        case .system6:  return 20
        case .system7:  return System7Chrome.barHeight
        case .platinum: return 22
        case .win31:    return 20
        case .win98:    return 24
        case .luna:     return 30
        case .aero:     return 30
        case .aquaLights, .snowLights: return 0   // sized from the real lights instead
        }
    }

    /// Quartz top-left global bounds → AppKit bottom-left frame of the strip along the top edge.
    static func appKitFrame(topLeft b: CGRect, height: CGFloat) -> NSRect {
        let primaryTop = (NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main)?.frame.maxY ?? 0
        return NSRect(x: b.minX, y: primaryTop - b.minY - height, width: b.width, height: height)
    }

    /// The lights panel: the union of the three orbs plus a little air, and each orb's rect
    /// inside it.
    static func lightsFrame(for bounds: CGRect, offsets: [ChromeButtonKind: CGRect]) -> (NSRect, [ChromeButtonKind: NSRect]) {
        let orb = lightDiameter
        let pad: CGFloat = 3
        let rects = offsets.map { NSRect(x: $0.value.midX - orb / 2, y: $0.value.midY - orb / 2, width: orb, height: orb) }
        let union = rects.reduce(NSRect.null) { $0.union($1) }.insetBy(dx: -pad, dy: -pad)
        let frame = appKitFrame(topLeft: CGRect(x: bounds.minX + union.minX, y: bounds.minY + union.minY,
                                                width: union.width, height: union.height), height: union.height)
        var lights: [ChromeButtonKind: NSRect] = [:]
        for (kind, r) in offsets {
            lights[kind] = NSRect(x: r.midX - orb / 2 - union.minX, y: r.midY - orb / 2 - union.minY, width: orb, height: orb)
        }
        return (frame, lights)
    }

    /// The bar's frame: a strip of the theme's height directly above the window, as wide as
    /// the window. The border, when on, frames window and bar together.
    ///
    /// macOS draws a hairline round every window just outside its bounds (part of the shadow;
    /// a window captured without one has none), so on screen the window is a point wider than
    /// it says. The Platinum bar's own black frame line stands on that hairline — a point out
    /// on each side — or the bar reads as set in from the window under it. Not when the window
    /// border is on: it covers the hairline, and window and bar share the border.
    static func barFrame(for bounds: CGRect, style: Style, overhang: CGFloat? = nil) -> NSRect {
        let h = stripHeight(style)
        let overhang = overhang ?? platinumOverhang(for: style)
        return appKitFrame(topLeft: CGRect(x: bounds.minX - overhang, y: bounds.minY - h, width: bounds.width + 2 * overhang, height: h), height: h)
    }
    static func platinumOverhang(for style: Style) -> CGFloat {
        style == .platinum && !AppSettings.shared.themeWindowBorders ? 1 : 0
    }

    // MARK: - Events from the WindowServer (forwarded by WindowBorderController)

    // MARK: Diagnostics (RETROMAC_TITLEBAR_STATS=1): event and sync rates, logged every 10 s.
    private static let statsEnabled: Bool = {
        guard ProcessInfo.processInfo.environment["RETROMAC_TITLEBAR_STATS"] != nil else { return false }
        setvbuf(stdout, nil, _IOLBF, 0) // the lines must reach a log file while it runs
        return true
    }()
    private var stats: [String: Int] = [:]
    private var statsSince = Date()
    private var statsTime: [String: Double] = [:]
    private func count(_ key: String, seconds: Double = 0) {
        guard Self.statsEnabled else { return }
        stats[key, default: 0] += 1
        statsTime[key, default: 0] += seconds
        if Date().timeIntervalSince(statsSince) >= 10 {
            let line = stats.sorted { $0.key < $1.key }.map { k, v in
                let t = statsTime[k] ?? 0
                return t > 0 ? String(format: "%@=%d(%.1fms avg)", k, v, t / Double(v) * 1000) : "\(k)=\(v)"
            }.joined(separator: " ")
            print("[TitleBar] stats/10s overlays=\(overlays.count) \(line)")
            stats.removeAll(); statsTime.removeAll(); statsSince = Date()
        }
    }

    func handleServerEvent(event: UInt32, wid: CGWindowID) {
        guard running else { return }
        count("event\(event)")
        switch event {
        case PrivateWindowAPI.EVENT_WINDOW_MOVE, PrivateWindowAPI.EVENT_WINDOW_RESIZE:
            guard let o = overlays[wid], let style else { return }
            guard let g = PrivateWindowAPI.bounds(of: wid) else { forget(wid); return }
            let previous = o.bounds
            o.bounds = g
            let f: NSRect
            if o.view.isBarPanel {
                f = Self.barFrame(for: g, style: style)
                if let patch = o.patch {
                    let d = CGPoint(x: g.minX - previous.minX, y: g.minY - previous.minY)
                    if d != .zero { patch.setFrameOrigin(NSPoint(x: patch.frame.minX + d.x, y: patch.frame.minY - d.y)) }
                    // The bar behind the lights may look different where the window now sits
                    // (another display, a different backdrop through a translucent bar): take
                    // the photograph again once the window has come to rest.
                    o.patchSampledFront = nil
                    resampleTimer?.invalidate()
                    resampleTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in self?.sync() }
                }
            } else if let offsets = lightOffsets[wid] {
                f = Self.lightsFrame(for: g, offsets: offsets).0   // the lights do not move inside the window
            } else { return }
            if event == PrivateWindowAPI.EVENT_WINDOW_RESIZE, previous.size != g.size {
                // The lights sit where the title bar puts them, and a resize can rebuild that
                // (a toolbar collapsing, Safari's tab bar): measure again once the window has
                // come to rest, not on every frame of the drag.
                remeasurePending.insert(wid)
                remeasureTimer?.invalidate()
                remeasureTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    for w in self.remeasurePending where self.overlays[w] != nil { self.lightOffsets.removeValue(forKey: w) }
                    self.remeasurePending.removeAll()
                    self.sync()
                }
            }
            if f.size == o.panel.frame.size {
                if f.origin != o.panel.frame.origin { o.panel.setFrameOrigin(f.origin) }   // a move: no redraw
            } else if o.panel.frame != f {
                o.panel.setFrame(f, display: false)
                o.view.needsDisplay = true
            }
        case PrivateWindowAPI.EVENT_WINDOW_MINIMIZE, PrivateWindowAPI.EVENT_WINDOW_DESTROY:
            forget(wid)
        case PrivateWindowAPI.EVENT_WINDOW_REORDER, PrivateWindowAPI.EVENT_FRONT_CHANGE:
            for (target, o) in overlays { order(o, above: target) }
            sync()   // the front window changed, and with it which bar draws active
        case PrivateWindowAPI.EVENT_WINDOW_CREATE:
            sync()
        default: break
        }
    }

    /// Take the overlay away; what was learnt about the window stays. A window that gave no
    /// measurement keeps its retry schedule this way — dropping that with the overlay meant the
    /// next sync asked again at once, every second, for every window without buttons.
    func drop(for wid: CGWindowID) {
        zoomedFrom.removeValue(forKey: wid)
        zoomedTo.removeValue(forKey: wid)
        guard let o = overlays[wid] else { return }
        // Alpha first: an orderOut on a panel ordered relative to another app's window can take
        // the WindowServer a few hundred milliseconds to honour, and the lights sat over the
        // minimise genie for exactly that long. Alpha is immediate.
        o.panel.alphaValue = 0
        o.patch?.alphaValue = 0
        o.panel.orderOut(nil)
        o.patch?.orderOut(nil)
        overlays.removeValue(forKey: wid)
    }

    /// A window on its way out by our hand (close, minimise): the overlay goes now, and the
    /// next second's syncs leave the window alone — its genie is still on screen, and a fresh
    /// measurement would put the lights straight back over the shrinking picture.
    private var leaving: [CGWindowID: Date] = [:]
    private func leave(_ wid: CGWindowID) {
        leaving[wid] = Date().addingTimeInterval(1)
        forget(wid)
        WindowBorderController.shared.windowIsLeaving(wid)   // the frame would trail the genie too
    }

    /// The window is gone (closed, minimised, off the list): overlay and every cache with it.
    func forget(_ wid: CGWindowID) {
        drop(for: wid)
        autoGeometry.removeValue(forKey: wid)
        lightOffsets.removeValue(forKey: wid)
        lightOffsetsRetry.removeValue(forKey: wid)
        titles.removeValue(forKey: wid)
        axWindows.removeValue(forKey: wid)
    }

    /// What is known about windows that no longer exist. `forget` runs for windows that had a
    /// bar; a window that never had one (screen-sized, excluded, dropped) but was measured or
    /// asked about kept its entries for the rest of the session, one more set for every such
    /// window ever opened. Every 30 s, every window-keyed cache is checked against the
    /// WindowServer: an id it no longer knows is gone for good. A window merely off this list
    /// (another space, minimised) still exists and keeps what was learnt about it.
    private var nextPrune = Date.distantPast
    private func pruneCaches(present: Set<CGWindowID>) {
        var known = Set(axWindows.keys).union(titles.keys).union(lightOffsets.keys)
            .union(lightOffsetsRetry.keys).union(autoGeometry.keys).union(axWindowRetry.keys)
            .union(leaving.keys).union(zoomedFrom.keys).union(zoomedTo.keys)
        known.subtract(present)
        known.subtract(overlays.keys)
        let now = Date()
        for wid in known where PrivateWindowAPI.bounds(of: wid) == nil {
            forget(wid)
            axWindowRetry.removeValue(forKey: wid)
            if let until = leaving[wid], until < now { leaving.removeValue(forKey: wid) }
        }
    }

    /// A window came back from the Dock: give it its bar again without waiting for the poll.
    func resync() { sync() }

    /// Drop every bar whose window is not in `onScreen` (a closed window, reported through AX).
    func dropAll(notIn onScreen: Set<CGWindowID>) {
        for wid in overlays.keys where !onScreen.contains(wid) { forget(wid) }
    }

    // MARK: - Mouse routing

    // MARK: - Driving the real window (Accessibility)

    /// The window being dragged by its bar and where it stood when the drag began (Quartz,
    /// top-left). Keyed to the window, set afresh on every press: a mouse-up that never
    /// arrived (the bar rebuilt under the pointer) can no longer leave a stale origin that
    /// throws the next drag — of this window or another — somewhere else.
    private var dragOrigin: CGPoint?
    private var dragWindow: CGWindowID?
    /// The latest position asked for while the previous one is still being set: drags are
    /// coalesced, the app gets the newest point and never a queue of old ones.
    private var dragTarget: CGPoint?
    private var dragSetting = false

    static let lightDiameter: CGFloat = 15   // a hair over the real 14, so nothing of them shows

    /// Where the three real lights sit, relative to the window's top-left corner — the
    /// corner as Accessibility reports it in the same breath as the buttons, so a window still
    /// sliding into place gives the same answer as one at rest. Measured once per window:
    /// during a drag the app answers Accessibility slowly, and a re-measure then (nine round
    /// trips at up to half a second each) was the four seconds the lights took to catch up.
    private var lightOffsets: [CGWindowID: [ChromeButtonKind: CGRect]] = [:]
    /// A window that gave no answer is asked again after 1, 2, 4 … 30 s, not every sync: with
    /// a hung app each ask costs the full timeout.
    private var lightOffsetsRetry: [CGWindowID: (next: Date, failures: Int)] = [:]

    /// Accessibility reads run here, one at a time, never on the main thread: an app that
    /// does not answer (Citrix, a process stopped in the debugger) costs its 0.5 s timeout on
    /// this queue, not in the dock's magnification. Results come back to main, where all the
    /// state lives. User actions (close, zoom, drag) stay on main: their wait is the user's.
    private static let axQueue = DispatchQueue(label: "com.retromac.titlebar.ax", qos: .userInitiated)
    private var measuring: Set<CGWindowID> = []
    private var fetchingTitle: Set<CGWindowID> = []

    private func lightOffsets(for info: WindowInfo) -> [ChromeButtonKind: CGRect]? {
        if let cached = lightOffsets[info.id] { return cached }
        if let r = lightOffsetsRetry[info.id], Date() < r.next { return nil }
        guard !measuring.contains(info.id) else { return nil }   // one request in flight per window
        measuring.insert(info.id)
        let wid = info.id, pid = info.pid, known = axWindows[wid]
        Self.axQueue.async {
            let w = known ?? Self.findAXWindow(wid, pid: pid)
            let offsets = w.flatMap { Self.measureLights(of: $0, fallbackOrigin: info.bounds.origin) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.measuring.remove(wid)
                guard self.running else { return }
                if let w { self.axWindows[wid] = w }
                if let offsets {
                    self.lightOffsets[wid] = offsets
                    self.lightOffsetsRetry.removeValue(forKey: wid)
                } else {
                    self.noteOffsetsFailure(wid)
                }
                self.sync()
            }
        }
        return nil
    }

    /// The three lights relative to the window's top-left corner, the corner taken from the
    /// same source as the buttons so a window still sliding into place gives one answer.
    private static func measureLights(of w: AXUIElement, fallbackOrigin: CGPoint) -> [ChromeButtonKind: CGRect]? {
        var origin = fallbackOrigin
        var oRef: CFTypeRef?
        var op = CGPoint.zero
        if AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &oRef) == .success, let oRef,
           AXValueGetValue(oRef as! AXValue, .cgPoint, &op) { origin = op }
        var out: [ChromeButtonKind: CGRect] = [:]
        for (kind, attr) in [(ChromeButtonKind.close, kAXCloseButtonAttribute),
                             (.minimize, kAXMinimizeButtonAttribute), (.zoom, kAXZoomButtonAttribute)] {
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(w, attr as CFString, &ref) == .success, let ref else { continue }
            let button = ref as! AXUIElement
            var pRef: CFTypeRef?, sRef: CFTypeRef?
            var p = CGPoint.zero, sz = CGSize.zero
            guard AXUIElementCopyAttributeValue(button, kAXPositionAttribute as CFString, &pRef) == .success, let pRef,
                  AXValueGetValue(pRef as! AXValue, .cgPoint, &p),
                  AXUIElementCopyAttributeValue(button, kAXSizeAttribute as CFString, &sRef) == .success, let sRef,
                  AXValueGetValue(sRef as! AXValue, .cgSize, &sz), sz.width > 0 else { continue }
            out[kind] = CGRect(x: p.x - origin.x, y: p.y - origin.y, width: sz.width, height: sz.height)
        }
        return out[.close] != nil ? out : nil
    }

    private func noteOffsetsFailure(_ wid: CGWindowID) {
        let failures = lightOffsetsRetry[wid]?.failures ?? 0
        lightOffsetsRetry[wid] = (Date().addingTimeInterval(min(30, pow(2, Double(failures)))), failures + 1)
    }

    /// The app's window element for a window number. Pure Accessibility, safe on any thread.
    private static func findAXWindow(_ wid: CGWindowID, pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let wins = ref as? [AXUIElement] else { return nil }
        for w in wins {
            var id: CGWindowID = 0
            if axUIElementGetWindow?(w, &id) == .success, id == wid { return w }
        }
        return nil
    }

    private var axWindowRetry: [CGWindowID: Date] = [:]

    /// For the user's actions on the main thread: the cached element, or one lookup with a
    /// 2 s pause after a miss.
    private func axWindow(_ wid: CGWindowID, pid: pid_t) -> AXUIElement? {
        if let cached = axWindows[wid] { return cached }
        if let next = axWindowRetry[wid], Date() < next { return nil }
        axWindowRetry[wid] = Date().addingTimeInterval(2)   // a miss is not asked about again for 2 s
        guard let w = Self.findAXWindow(wid, pid: pid) else { return nil }
        axWindows[wid] = w
        axWindowRetry.removeValue(forKey: wid)
        return w
    }

    /// Whether a cached title (nil = none cached, or a failure entry) is worth asking for again.
    static func refreshesTitle(_ cached: String?) -> Bool { cached != nil }

    /// Titles the window list did not carry, fetched through Accessibility once and kept. A
    /// window that yields none is asked again after 1, 2, 4 … 30 seconds, not twice a second.
    private struct TitleEntry { var title: String?; var nextTry: Date; var failures: Int }
    private var titles: [CGWindowID: TitleEntry] = [:]

    private func title(for info: WindowInfo) -> String {
        if !info.title.isEmpty { titles.removeValue(forKey: info.id); return info.title }
        if let e = titles[info.id] {
            if let t = e.title { return t }
            if Date() < e.nextTry { return info.ownerName }
        }
        guard !fetchingTitle.contains(info.id) else { return info.ownerName }
        fetchingTitle.insert(info.id)
        let wid = info.id, pid = info.pid, known = axWindows[wid]
        Self.axQueue.async {
            let w = known ?? Self.findAXWindow(wid, pid: pid)
            var title: String?
            if let w {
                var ref: CFTypeRef?
                if AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &ref) == .success {
                    title = (ref as? String).flatMap { $0.isEmpty ? nil : $0 }
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.fetchingTitle.remove(wid)
                guard self.running else { return }
                if let w { self.axWindows[wid] = w }
                if let title {
                    self.titles[wid] = TitleEntry(title: title, nextTry: .distantFuture, failures: 0)
                } else {
                    let failures = self.titles[wid]?.failures ?? 0
                    let wait = min(30, pow(2, Double(failures)))
                    self.titles[wid] = TitleEntry(title: nil, nextTry: Date().addingTimeInterval(wait), failures: failures + 1)
                }
                self.sync()
            }
        }
        return info.ownerName
    }

    private static var icons: [pid_t: NSImage] = [:]
    private static var classicIcons: [pid_t: NSImage] = [:]
    private static func classicIcon(for pid: pid_t) -> NSImage? {
        if let i = classicIcons[pid] { return i }
        let bid = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        guard let i = ThemeManager.shared.activeTheme?.classicAppIcon(for: bid) ?? icon(for: pid) else { return nil }
        classicIcons[pid] = i
        return i
    }

    private static func icon(for pid: pid_t) -> NSImage? {
        if let i = icons[pid] { return i }
        guard let i = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        icons[pid] = i
        return i
    }

    /// Bring a window's app to the front and the window with it, the way a click on a real
    /// title bar does; the bar intercepts that click, so it has to do it itself. The window is
    /// raised first and the app activated after, so the app brings this window forward and
    /// not whichever of its windows was frontmost; and all of it runs off the main thread —
    /// an app slow to answer Accessibility (a browser with many windows) used to hold the
    /// main thread long enough for the spinning cursor.
    private func activate(_ wid: CGWindowID, pid: pid_t) {
        let known = axWindows[wid]
        Self.axQueue.async {
            func raise(_ w: AXUIElement) -> Bool {
                AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
                return AXUIElementPerformAction(w, kAXRaiseAction as CFString) == .success
            }
            var w = known
            // A cached element can outlive its window's identity; look it up again if it fails.
            if w == nil || !raise(w!) {
                w = Self.findAXWindow(wid, pid: pid)
                if let w { _ = raise(w) }
            }
            // The app to the front through Accessibility: RetroMac is rarely the active app when
            // a bar is clicked (the bar's panel does not activate it), and since macOS 14 an
            // app in the background may not activate another one through NSRunningApplication.
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            DispatchQueue.main.async { [weak self] in
                if let w { self?.axWindows[wid] = w } else { self?.axWindows.removeValue(forKey: wid) }
                guard let app = NSRunningApplication(processIdentifier: pid) else { return }
                if #available(macOS 14.0, *) { NSApp.yieldActivation(to: app) }
                app.activate(options: [])
            }
        }
    }

    /// A press on a bar: whatever drag comes next starts from this window as it stands now,
    /// and its Accessibility element is fetched in the background if it is not known yet.
    private func press(_ wid: CGWindowID, pid: pid_t) {
        endDrag()
        dragWindow = wid
        dragOrigin = overlays[wid]?.bounds.origin
        guard axWindows[wid] == nil else { return }
        Self.axQueue.async {
            let w = Self.findAXWindow(wid, pid: pid)
            DispatchQueue.main.async { [weak self] in if let w { self?.axWindows[wid] = w } }
        }
    }

    private func endDrag() {
        dragOrigin = nil
        dragWindow = nil
        dragTarget = nil
    }

    private func perform(_ kind: ChromeButtonKind, on wid: CGWindowID, pid: pid_t) {
        count("action.\(kind)")
        guard let w = axWindow(wid, pid: pid) else { return }
        let attr: String
        switch kind {
        case .close:              attr = kAXCloseButtonAttribute
        case .minimize, .collapse: attr = kAXMinimizeButtonAttribute
        case .maximize, .zoom, .restore: zoom(w, wid: wid); return
        default: return
        }
        var ref: CFTypeRef?
        let button = AXUIElementCopyAttributeValue(w, attr as CFString, &ref) == .success ? ref.map { $0 as! AXUIElement } : nil
        guard button != nil || attr == kAXMinimizeButtonAttribute else { return }
        // Under the theme without a dock the window zooms away in picture, a still of the
        // desktop under it hiding the real minimise; photographed while the bar still stands.
        var zoomed = false
        if attr == kAXMinimizeButtonAttribute, MinimizeZoom.wanted, let o = overlays[wid] {
            zoomed = MinimizeZoom.shared.begin(wid: wid, windowBounds: o.bounds, bar: o.panel, barView: o.view, patch: o.patch)
        }
        // The bar goes before the window does; a bar over a fading window is the one thing
        // that gives the trick away. Comes back on the next sync if the app asked to save.
        // The same for minimise: the WindowServer's minimise event arrives when the genie
        // has finished, and until then the lights would sit over a shrinking window.
        leave(wid)
        // The press itself runs off the main thread: the app answers it only when its
        // minimise or close animation is over (half a second for the genie), and a main thread
        // waiting that long would not have committed the panel's disappearance first.
        Self.axQueue.async {
            if let button { AXUIElementPerformAction(button, kAXPressAction as CFString) }
            else { AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
            if zoomed { DispatchQueue.main.async { MinimizeZoom.shared.end() } }
        }
    }

    /// Frames remembered around a zoom: where the window came from, and where it actually
    /// ended up (an app may refuse part of the size, so the request is no measure of it).
    private var zoomedFrom: [CGWindowID: CGRect] = [:]
    private var zoomedTo: [CGWindowID: CGRect] = [:]

    /// Zoom the way the era did: fill the screen the window is on, and back again. Pressing the
    /// real green button would put the window into native full screen instead, which is
    /// neither Platinum nor Luna and leaves no bar to click.
    private func zoom(_ w: AXUIElement, wid: CGWindowID) {
        guard let current = overlays[wid]?.bounds ?? PrivateWindowAPI.bounds(of: wid) else { return }
        func quartz(_ r: NSRect) -> CGRect { Self.quartz(r) }
        guard let screen = Self.screen(for: current) else { return }
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
        // The bar above the window is part of it now: a zoomed window starts a bar lower.
        let bar = barAboveHeight
        visible = NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: max(100, visible.height - bar))
        if visible.height + bar >= screen.frame.height - 1 { visible = visible.insetBy(dx: 0, dy: 1) }
        let full = quartz(visible)
        let target: CGRect
        let restoring: Bool
        if let back = zoomedFrom[wid], let reached = zoomedTo[wid], Self.roughlySame(current, reached) {
            target = back
            restoring = true
        } else {
            zoomedFrom[wid] = current
            target = full
            restoring = false
        }
        guard let reached = Self.setFrame(target, of: w) else {
            // The app refused or could not say where it went: no zoom state to remember, and
            // no restore glyph promising one.
            if !restoring { zoomedFrom.removeValue(forKey: wid) }
            return
        }
        if restoring {
            zoomedFrom.removeValue(forKey: wid)
            zoomedTo.removeValue(forKey: wid)
        } else {
            zoomedTo[wid] = reached   // whatever the app allowed is what "zoomed" looks like now
        }
        overlays[wid]?.view.configure(zoomed: !restoring)
    }

    static func roughlySame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }

    /// Position, size, position again (a move first can be clipped to the old size), then read
    /// back what the app actually did. Nil when it answered none of it.
    @discardableResult
    private static func setFrame(_ target: CGRect, of w: AXUIElement) -> CGRect? {
        var p = target.origin, sz = target.size
        var ok = false
        if let pv = AXValueCreate(.cgPoint, &p) { ok = AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv) == .success || ok }
        if let sv = AXValueCreate(.cgSize, &sz) { ok = AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv) == .success || ok }
        if let pv = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv) }
        guard ok else { return nil }
        var pRef: CFTypeRef?, sRef: CFTypeRef?
        var rp = CGPoint.zero, rs = CGSize.zero
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &pRef) == .success, let pRef,
              AXValueGetValue(pRef as! AXValue, .cgPoint, &rp),
              AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sRef) == .success, let sRef,
              AXValueGetValue(sRef as! AXValue, .cgSize, &rs) else { return nil }   // set, but unreadable: no state
        return CGRect(origin: rp, size: rs)
    }

    /// Move the real window by `delta` (AppKit points, y up) from where it was when the drag
    /// began. The position is set on the Accessibility queue, coalesced: while one is being
    /// set, only the newest target waits.
    private func drag(_ wid: CGWindowID, pid: pid_t, by delta: NSPoint) {
        if dragWindow != wid { press(wid, pid: pid) }
        guard let origin = dragOrigin else { return }
        dragTarget = CGPoint(x: origin.x + delta.x, y: origin.y - delta.y)   // AX is y-down
        guard let w = axWindows[wid] else { return }   // still being fetched: the next event moves it
        applyDrag(w)
    }

    private func applyDrag(_ w: AXUIElement) {
        guard !dragSetting, var target = dragTarget else { return }
        dragTarget = nil
        dragSetting = true
        Self.axQueue.async {
            if let v = AXValueCreate(.cgPoint, &target) {
                AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v)
            }
            DispatchQueue.main.async { [weak self] in
                self?.dragSetting = false
                self?.applyDrag(w)
            }
        }
    }

    // MARK: - Window enumeration

    private struct WindowInfo {
        let id: CGWindowID
        let pid: pid_t
        let bounds: CGRect
        let title: String
        let ownerName: String
        var bundleID = ""   // filled in on the main thread, see `bundleIDs`
    }

    /// Main thread only: the list runs on `listQueue` without touching it, and the terminate
    /// observer prunes it on main. Both used to share it unsynchronised, and a Swift dictionary
    /// written from two threads at once is a crash, not a stale value.
    private static var bundleIDs: [pid_t: String] = [:]
    private static func bundleID(for pid: pid_t) -> String {
        if let b = bundleIDs[pid] { return b }
        let b = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        bundleIDs[pid] = b
        return b
    }

    /// The other apps' windows worth a bar, and the z-order of everything on screen (ours too).
    private static func onScreenWindows() -> ([WindowInfo], [CGWindowID]) {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return ([], []) }
        let myPID = getpid()
        var out: [WindowInfo] = []
        var order: [CGWindowID] = []
        for w in raw {
            guard let num = w[kCGWindowNumber as String] as? CGWindowID else { continue }
            if (w[kCGWindowLayer as String] as? Int) == 0 { order.append(num) }
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != myPID else { continue }
            guard let bDict = w[kCGWindowBounds as String] as? [String: Any] else { continue }
            var b = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(bDict as CFDictionary, &b),
                  b.width > 40, b.height > 60 else { continue }
            // kCGWindowName needs Screen Recording, which the shader already has; empty otherwise.
            out.append(WindowInfo(id: num, pid: pid, bounds: b,
                                  title: (w[kCGWindowName as String] as? String) ?? "",
                                  ownerName: (w[kCGWindowOwnerName as String] as? String) ?? ""))
        }
        return (out, order)
    }
}

// MARK: - The bar itself

/// Draws one title bar and owns its controls. Flipped, so y runs down like the strip does.
final class TitleBarOverlayView: NSView {
    var onAction: ((ChromeButtonKind) -> Void)?
    var onActivate: (() -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    /// Every mouse-down on the bar, before anything else: a drag starts afresh from here.
    var onPress: (() -> Void)?

    private var style: TitleBarOverlayController.Style = .platinum
    private var title = ""
    private var icon: NSImage?
    private var isFront = true
    private var lights: [ChromeButtonKind: NSRect] = [:]
    private var deadZoneWidth: CGFloat = 0
    private var zoomed = false
    private var tracker = ChromeButtonTracker()
    var currentStyle: TitleBarOverlayController.Style { style }
    var isBarPanel: Bool { style.isBar }
    private var buttonRects: [(ChromeButtonKind, NSRect)] = []
    private var dragStart: NSPoint?
    private var dragging = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// A bar sits above the window with nothing native under it, so all of it is ours: drag
    /// anywhere, double-click anywhere, and the buttons. A lights panel is only its lights.
    private var deadZone: NSRect { style.isBar ? bounds : .zero }

    func configure(style: TitleBarOverlayController.Style, title: String, icon: NSImage?, isFront: Bool,
                   lights: [ChromeButtonKind: NSRect], deadZoneWidth: CGFloat, zoomed: Bool) {
        guard style != self.style || title != self.title || isFront != self.isFront
                || lights != self.lights || (icon == nil) != (self.icon == nil)
                || deadZoneWidth != self.deadZoneWidth || zoomed != self.zoomed else { return }
        self.style = style; self.title = title; self.icon = icon; self.isFront = isFront; self.lights = lights
        self.deadZoneWidth = deadZoneWidth; self.zoomed = zoomed
        needsDisplay = true
    }

    func configure(zoomed: Bool) {
        guard zoomed != self.zoomed else { return }
        self.zoomed = zoomed
        needsDisplay = true
    }

    /// Whether the panel should take the mouse at `p` (view coordinates). An inactive Platinum
    /// bar shows no boxes, so it has none to hit; its dead zone still takes the click, to
    /// activate the window.
    func isHot(_ p: NSPoint) -> Bool {
        let boxesShown = true   // the Platinum boxes are drawn in every state now, like the widgets'
        if boxesShown, buttonRects.contains(where: { $0.1.insetBy(dx: -3, dy: -3).contains(p) }) { return true }
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
        case .aquaLights, .snowLights:
            for kind in [ChromeButtonKind.close, .minimize, .zoom] {
                guard let r = lights[kind] else { continue }
                tracker.add(kind, r, interactive: true)
                buttonRects.append((kind, r))
            }
        case .platinum:
            let boxes = PlatinumBar.boxRects(width: w)
            for (k, r) in [(ChromeButtonKind.close, boxes.close), (.collapse, boxes.collapse), (.zoom, boxes.zoom)] {
                tracker.add(k, r.insetBy(dx: -3, dy: -3), interactive: true)
                buttonRects.append((k, r))
            }
        case .system6:
            // System 6: the close box on the left, the zoom box on the right, both 15 pt.
            let s = System6Chrome.boxSize
            let y = ((h - s) / 2).rounded()
            for (k, r) in [(ChromeButtonKind.close, NSRect(x: 8, y: y, width: s, height: s)),
                           (.zoom, NSRect(x: w - 8 - s, y: y, width: s, height: s))] {
                tracker.add(k, r.insetBy(dx: -3, dy: -3), interactive: isFront)
                buttonRects.append((k, r))
            }
        case .system7:
            // System 7.1: the close box left and the zoom box right, 11 pt, 9 pt in from the edges.
            let bar = NSRect(x: 0, y: 0, width: w, height: h)
            for (k, r) in [(ChromeButtonKind.close, System7Chrome.closeRect(in: bar, flipped: true)),
                           (.zoom, System7Chrome.zoomRect(in: bar, flipped: true))] {
                tracker.add(k, r.insetBy(dx: -3, dy: -3), interactive: isFront)
                buttonRects.append((k, r))
            }
        case .win31:
            // The system-menu box on the left (a double-click closed the window; here one
            // click does), minimise and maximise on the right.
            let bw: CGFloat = 18, bh: CGFloat = 18
            let y = ((h - bh) / 2).rounded()
            let sys = NSRect(x: 1, y: y, width: bw, height: bh)
            let max = NSRect(x: w - 1 - bw, y: y, width: bw, height: bh)
            let min = NSRect(x: max.minX - bw, y: y, width: bw, height: bh)
            for (k, r) in [(ChromeButtonKind.close, sys), (.minimize, min), (.maximize, max)] {
                tracker.add(k, r, interactive: true)
                buttonRects.append((k, r))
            }
        case .win98:
            // 20x18 bevel buttons, the theme's own size: [min][max], a 2 pt gap, [close].
            let bw: CGFloat = 20, bh: CGFloat = 18
            let y: CGFloat = 2
            let close = NSRect(x: w - 2 - bw, y: y, width: bw, height: bh)
            let max = NSRect(x: close.minX - 2 - bw, y: y, width: bw, height: bh)
            let min = NSRect(x: max.minX - bw, y: y, width: bw, height: bh)
            for (k, r) in [(ChromeButtonKind.minimize, min), (.maximize, max), (.close, close)] {
                tracker.add(k, r, interactive: true)
                buttonRects.append((k, r))
            }
        case .aero:
            // The glass cluster hangs from the top edge: [min][max][close], close 29x19 like the rest.
            let bw: CGFloat = 29, bh: CGFloat = 19
            let close = NSRect(x: w - 6 - bw, y: 0, width: bw, height: bh)
            let max = NSRect(x: close.minX - bw, y: 0, width: bw, height: bh)
            let min = NSRect(x: max.minX - bw, y: 0, width: bw, height: bh)
            for (k, r) in [(ChromeButtonKind.minimize, min), (.maximize, max), (.close, close)] {
                tracker.add(k, r, interactive: true)
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
        case .system6:    drawSystem6(b)
        case .system7:    drawSystem7(b)
        case .platinum:   drawPlatinum(b)
        case .win31:      drawWin31(b)
        case .win98:      drawWin98(b)
        case .luna:       Self.topCorners(b, radius: TitleBarOverlayController.barCornerRadius(for: .luna)).addClip(); drawLuna(b)
        case .aero:       Self.topCorners(b, radius: TitleBarOverlayController.barCornerRadius(for: .aero)).addClip(); drawAero(b)
        case .snowLights: drawLights(aqua: false)
        case .aquaLights: drawLights(aqua: true)
        }
    }

    /// The bar's outline with its two top corners rounded, the bottom square where it meets
    /// the window. Built from tangents (`appendArc(from:to:radius:)`), which reads the same in
    /// a flipped view; the angle form once mirrored and cut the right end of the bar off.
    static func topCorners(_ b: NSRect, radius r: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: b.minX, y: b.maxY))
        p.line(to: NSPoint(x: b.minX, y: b.minY + r))
        p.appendArc(from: NSPoint(x: b.minX, y: b.minY), to: NSPoint(x: b.minX + r, y: b.minY), radius: r)
        p.line(to: NSPoint(x: b.maxX - r, y: b.minY))
        p.appendArc(from: NSPoint(x: b.maxX, y: b.minY), to: NSPoint(x: b.maxX, y: b.minY + r), radius: r)
        p.line(to: NSPoint(x: b.maxX, y: b.maxY))
        p.close()
        return p
    }

    /// A stretchable mask with the bar's rounded top corners, for `NSVisualEffectView.maskImage`
    /// (its coordinates are not flipped: the top is maxY).
    static func topCornersMask(radius r: CGFloat, height: CGFloat) -> NSImage {
        let w = r * 2 + 2
        let img = NSImage(size: NSSize(width: w, height: height), flipped: false) { rect in
            let p = NSBezierPath()
            p.move(to: NSPoint(x: rect.minX, y: rect.minY))
            p.line(to: NSPoint(x: rect.minX, y: rect.maxY - r))
            p.appendArc(from: NSPoint(x: rect.minX, y: rect.maxY), to: NSPoint(x: rect.minX + r, y: rect.maxY), radius: r)
            p.line(to: NSPoint(x: rect.maxX - r, y: rect.maxY))
            p.appendArc(from: NSPoint(x: rect.maxX, y: rect.maxY), to: NSPoint(x: rect.maxX, y: rect.maxY - r), radius: r)
            p.line(to: NSPoint(x: rect.maxX, y: rect.minY))
            p.close()
            NSColor.black.setFill()
            p.fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: r, left: r, bottom: 0, right: r)
        img.resizingMode = .stretch
        return img
    }

    // MARK: System 6

    private func drawSystem6(_ b: NSRect) {
        System6Chrome.titleBar(b, active: isFront)
        System6Chrome.black.setFill()
        NSRect(x: 0, y: b.height - 1, width: b.width, height: 1).fill()   // the frame line under the bar
        if isFront {
            for (k, r) in buttonRects {
                if k == .close { System6Chrome.closeBox(r, state: tracker.state(for: k)) }
                else {
                    // The zoom box: hollow, with the small square in its upper-left (y down here).
                    System6Chrome.white.setFill(); r.fill()
                    System6Chrome.black.setStroke()
                    let o = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); o.lineWidth = 1.5; o.stroke()
                    let g = NSBezierPath(rect: NSRect(x: r.minX + 2.5, y: r.minY + 2.5, width: 4, height: 4)); g.lineWidth = 1; g.stroke()
                    if tracker.state(for: k) == .pressed { System6Chrome.black.setFill(); r.insetBy(dx: 3, dy: 3).fill() }
                }
            }
        }
        let left = (buttonRects.first { $0.0 == .close }?.1.maxX ?? 0) + 8
        let right = (buttonRects.first { $0.0 == .zoom }?.1.minX ?? b.width) - 8
        let font = System6Chrome.titleFont
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let width = min(title.size(withAttributes: attrs).width, max(0, right - left - 16))
        // The plaque is drawn by the helper at full title width; clip it to the room between the boxes.
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: (b.width - width) / 2 - 8, y: 0, width: width + 16, height: b.height).clip()
        System6Chrome.titlePlaque(title, bar: b, font: font, active: isFront)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: System 7.1

    private func drawSystem7(_ b: NSRect) {
        System7Chrome.titleBar(b, active: isFront, flipped: true)
        if isFront {
            for (k, r) in buttonRects {
                let pressed = tracker.state(for: k) == .pressed
                if k == .close { System7Chrome.closeBox(r, pressed: pressed, flipped: true) }
                else { System7Chrome.zoomBox(r, pressed: pressed, flipped: true) }
            }
        }
        let left = buttonRects.first { $0.0 == .close }?.1.maxX ?? 0
        let right = buttonRects.first { $0.0 == .zoom }?.1.minX ?? b.width
        System7Chrome.title(title, bar: b, active: isFront, flipped: true, minX: left, maxX: right)
    }

    // MARK: Windows 3.1

    private func drawWin31(_ b: NSRect) {
        Win31Chrome.face.setFill(); b.fill()
        let cap = NSRect(x: 0, y: 0, width: b.width, height: b.height - 2)
        (isFront ? Win31Chrome.activeTitle : Win31Chrome.inactiveTitle).setFill(); cap.fill()
        for (k, r) in buttonRects {
            let pressed = tracker.state(for: k) == .pressed
            Win31Chrome.face.setFill(); r.fill()
            bevel(r, raised: !pressed, hi: .white, lo: Win31Chrome.darkGray, edge: .black)
            Win31Chrome.black.setFill()
            switch k {
            case .close:
                // The system-menu glyph: a bar with a white line under it.
                NSRect(x: r.midX - 5, y: r.midY - 1, width: 10, height: 2).fill()
                NSColor.white.setFill(); NSRect(x: r.midX - 5, y: r.midY + 1, width: 10, height: 1).fill()
            case .minimize: triangle(in: r, pointingDown: true)
            default:
                if zoomed {   // restore: an up triangle over a down triangle
                    triangle(in: NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height / 2 + 1), pointingDown: false)
                    triangle(in: NSRect(x: r.minX, y: r.midY - 1, width: r.width, height: r.height / 2 + 1), pointingDown: true)
                } else { triangle(in: r, pointingDown: false) }
            }
        }
        let font = Win31Chrome.font(size: 12)
        let color = isFront ? Win31Chrome.titleText : Win31Chrome.inactiveTitleText
        let left = (buttonRects.first { $0.0 == .close }?.1.maxX ?? 0) + 6
        let right = (buttonRects.first { $0.0 == .minimize }?.1.minX ?? b.width) - 6
        drawCentredTitle(in: NSRect(x: left, y: cap.minY, width: max(0, right - left), height: cap.height), font: font, color: color)
    }

    private func triangle(in r: NSRect, pointingDown: Bool) {
        let s = r.width * 0.22
        let cy = r.midY + (pointingDown ? 0.5 : -0.5)
        let p = NSBezierPath()
        if pointingDown {
            p.move(to: NSPoint(x: r.midX - s, y: cy - s * 0.7)); p.line(to: NSPoint(x: r.midX + s, y: cy - s * 0.7)); p.line(to: NSPoint(x: r.midX, y: cy + s * 0.7))
        } else {
            p.move(to: NSPoint(x: r.midX - s, y: cy + s * 0.7)); p.line(to: NSPoint(x: r.midX + s, y: cy + s * 0.7)); p.line(to: NSPoint(x: r.midX, y: cy - s * 0.7))
        }
        p.close(); p.fill()
    }

    /// A 3D bevel in this flipped view: light along the top and left, dark along the bottom
    /// and right (or the other way round when sunken), an outer edge in `edge`.
    private func bevel(_ r: NSRect, raised: Bool, hi: NSColor, lo: NSColor, edge: NSColor) {
        func line(_ rr: NSRect, _ c: NSColor) { c.setFill(); rr.fill() }
        let a = raised ? hi : lo, z = raised ? lo : hi
        line(NSRect(x: r.minX, y: r.minY, width: r.width, height: 1), a)
        line(NSRect(x: r.minX, y: r.minY, width: 1, height: r.height), a)
        line(NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1), raised ? edge : hi)
        line(NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height), raised ? edge : hi)
        line(NSRect(x: r.minX + 1, y: r.maxY - 2, width: r.width - 2, height: 1), z)
        line(NSRect(x: r.maxX - 2, y: r.minY + 1, width: 1, height: r.height - 2), z)
    }

    private func drawCentredTitle(in box: NSRect, font: NSFont, color: NSColor, shadow: NSShadow? = nil) {
        let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byTruncatingTail
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
        if let shadow { attrs[.shadow] = shadow }
        let h = title.size(withAttributes: attrs).height
        (title as NSString).draw(in: NSRect(x: box.minX, y: box.midY - h / 2, width: box.width, height: h), withAttributes: attrs)
    }

    // MARK: Windows 95 / 98 / Me

    private func drawWin98(_ b: NSRect) {
        let cs = ChromeStyleFactory.win98()   // colours follow the theme's scheme (Plus!)
        cs.windowFill.setFill(); b.fill()
        let cap = NSRect(x: 0, y: 0, width: b.width, height: 22)
        if isFront {
            cs.captionGradient?.draw(in: cap)
        } else {
            let a = cs.bevelShadow ?? NSColor(white: 0.5, alpha: 1), z = cs.bevelLight ?? NSColor(white: 0.75, alpha: 1)
            NSGradient(starting: a, ending: z)?.draw(in: cap, angle: 0)
        }
        var x: CGFloat = 3
        if let icon {
            icon.draw(in: NSRect(x: x, y: 3, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += 21
        }
        let hi = cs.bevelHilight ?? .white, lo = cs.bevelDkShadow ?? .black
        let light = cs.bevelLight ?? NSColor(white: 0.86, alpha: 1), shade = cs.bevelShadow ?? NSColor(white: 0.5, alpha: 1)
        for (k, r) in buttonRects {
            let pressed = tracker.state(for: k) == .pressed
            cs.windowFill.setFill(); r.fill()
            if pressed { bevel(r, raised: false, hi: hi, lo: shade, edge: lo) }
            else {
                bevel(r, raised: true, hi: light, lo: shade, edge: lo)
                hi.setFill(); NSRect(x: r.minX + 1, y: r.minY + 1, width: r.width - 2, height: 1).fill(); NSRect(x: r.minX + 1, y: r.minY + 1, width: 1, height: r.height - 2).fill()
            }
            let o: CGFloat = pressed ? 1 : 0
            NSColor.black.setFill(); NSColor.black.setStroke()
            switch k {
            case .minimize:
                NSRect(x: r.minX + 5 + o, y: r.maxY - 6 + o, width: 8, height: 2).fill()
            case .maximize:
                if zoomed {   // restore: two overlapping frames
                    frameGlyph(NSRect(x: r.minX + 7 + o, y: r.minY + 3 + o, width: 8, height: 7))
                    cs.windowFill.setFill(); NSRect(x: r.minX + 4 + o, y: r.minY + 6 + o, width: 8, height: 7).fill(); NSColor.black.setFill()
                    frameGlyph(NSRect(x: r.minX + 4 + o, y: r.minY + 6 + o, width: 8, height: 7))
                } else {
                    frameGlyph(NSRect(x: r.minX + 4 + o, y: r.minY + 3 + o, width: 12, height: 11))
                }
            default:
                let p = NSBezierPath(); p.lineWidth = 1.8
                p.move(to: NSPoint(x: r.minX + 6 + o, y: r.minY + 5 + o)); p.line(to: NSPoint(x: r.maxX - 6 + o, y: r.maxY - 5 + o))
                p.move(to: NSPoint(x: r.maxX - 6 + o, y: r.minY + 5 + o)); p.line(to: NSPoint(x: r.minX + 6 + o, y: r.maxY - 5 + o))
                p.stroke()
            }
        }
        let right = (buttonRects.map { $0.1.minX }.min() ?? b.width) - 4
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: cs.titleFont, .foregroundColor: isFront ? cs.titleColor : NSColor(white: 0.78, alpha: 1), .paragraphStyle: para]
        let h = title.size(withAttributes: attrs).height
        (title as NSString).draw(in: NSRect(x: x, y: cap.midY - h / 2, width: max(0, right - x), height: h), withAttributes: attrs)
    }

    /// The Windows "maximise" glyph: a frame with a thick top edge.
    private func frameGlyph(_ r: NSRect) {
        let p = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); p.lineWidth = 1; p.stroke()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 2).fill()
    }

    // MARK: Windows 7 (Aero)

    private func drawAero(_ b: NSRect) {
        let cs = ChromeStyleFactory.win7()
        // The glass view behind this one blurs the desktop; only tints are painted here.
        NSColor(srgbRed: 0.271, green: 0.502, blue: 0.769, alpha: isFront ? 0.28 : 0.14).setFill(); b.fill()
        cs.captionGradient?.draw(in: b)
        NSGradient(colorsAndLocations: (NSColor.white.withAlphaComponent(0), 0), (NSColor.white.withAlphaComponent(0.55), 0.5), (NSColor.white.withAlphaComponent(0), 1))?
            .draw(in: NSRect(x: 0, y: b.height * 0.18, width: b.width, height: b.height * 0.24), angle: -90)
        NSColor.white.withAlphaComponent(0.66).setStroke()
        NSBezierPath(rect: b.insetBy(dx: 1.5, dy: 1.5)).stroke()
        NSColor.black.withAlphaComponent(0.55).setStroke()
        NSBezierPath(rect: b.insetBy(dx: 0.5, dy: 0.5)).stroke()
        guard let close = buttonRects.first(where: { $0.0 == .close })?.1,
              let minR = buttonRects.first(where: { $0.0 == .minimize })?.1,
              let maxR = buttonRects.first(where: { $0.0 == .maximize })?.1 else { return }
        let cluster = NSRect(x: minR.minX, y: 0, width: close.maxX - minR.minX, height: close.height)
        let path = NSBezierPath(roundedRect: cluster, xRadius: 4, yRadius: 4)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let W = { (a: CGFloat) in NSColor(srgbRed: 1, green: 1, blue: 1, alpha: a) }
        let K = { (a: CGFloat) in NSColor(srgbRed: 0, green: 0, blue: 0, alpha: a) }
        let glassR = NSRect(x: minR.minX, y: 0, width: maxR.maxX - minR.minX, height: close.height)
        NSGradient(colorsAndLocations: (W(0.5), 0), (W(0.3), 0.45), (K(0.1), 0.5), (K(0.1), 0.75), (W(0.5), 1))?.draw(in: glassR, angle: -90)
        for k in [ChromeButtonKind.minimize, .maximize] where tracker.state(for: k) == .hovered {
            NSColor(srgbRed: 0.6, green: 0.85, blue: 1, alpha: 0.35).setFill(); (k == .minimize ? minR : maxR).fill()
        }
        let s = tracker.state(for: .close)
        var top = NSColor(srgbRed: 0.878, green: 0.631, blue: 0.592, alpha: 1), mid = NSColor(srgbRed: 0.812, green: 0.475, blue: 0.416, alpha: 1), bot = NSColor(srgbRed: 0.835, green: 0.310, blue: 0.212, alpha: 1)
        if s == .hovered { top = NSColor(srgbRed: 0.98, green: 0.72, blue: 0.66, alpha: 1); mid = NSColor(srgbRed: 0.90, green: 0.42, blue: 0.34, alpha: 1); bot = NSColor(srgbRed: 0.92, green: 0.28, blue: 0.16, alpha: 1) }
        if s == .pressed { top = NSColor(srgbRed: 0.72, green: 0.34, blue: 0.28, alpha: 1); mid = NSColor(srgbRed: 0.64, green: 0.20, blue: 0.14, alpha: 1); bot = NSColor(srgbRed: 0.58, green: 0.12, blue: 0.08, alpha: 1) }
        if !isFront { top = top.blended(withFraction: 0.5, of: .gray) ?? top; mid = mid.blended(withFraction: 0.5, of: .gray) ?? mid; bot = bot.blended(withFraction: 0.5, of: .gray) ?? bot }
        NSGradient(colorsAndLocations: (top, 0), (mid, 0.25), (mid, 0.5), (bot, 0.5), (bot, 1))?.draw(in: close, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.28).setFill()
        NSRect(x: maxR.minX, y: 1, width: 1, height: close.height - 2).fill()
        NSRect(x: close.minX, y: 1, width: 1, height: close.height - 2).fill()
        NSColor.black.withAlphaComponent(0.30).setStroke(); path.lineWidth = 1; path.stroke()
        let ink = NSColor.black.withAlphaComponent(0.72)
        ink.setFill(); NSRect(x: minR.midX - 4, y: minR.midY + 1, width: 8, height: 2).fill()
        ink.setStroke(); ink.setFill()
        if zoomed {
            frameGlyph(NSRect(x: maxR.midX - 3, y: maxR.midY - 5, width: 8, height: 7))
            frameGlyph(NSRect(x: maxR.midX - 6, y: maxR.midY - 2, width: 8, height: 7))
        } else {
            frameGlyph(NSRect(x: maxR.midX - 5, y: maxR.midY - 4, width: 10, height: 8))
        }
        NSColor.white.setStroke()
        let xg = NSBezierPath(); xg.lineWidth = 2
        xg.move(to: NSPoint(x: close.midX - 4, y: close.midY - 4)); xg.line(to: NSPoint(x: close.midX + 4, y: close.midY + 4))
        xg.move(to: NSPoint(x: close.midX + 4, y: close.midY - 4)); xg.line(to: NSPoint(x: close.midX - 4, y: close.midY + 4))
        xg.stroke()
        var x: CGFloat = 8
        if let icon {
            icon.draw(in: NSRect(x: x, y: (b.height - 16) / 2, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: isFront ? 1 : 0.7, respectFlipped: true, hints: nil)
            x += 20
        }
        let glow = NSShadow(); glow.shadowColor = NSColor.white.withAlphaComponent(0.95); glow.shadowOffset = .zero; glow.shadowBlurRadius = 4
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: cs.titleFont, .foregroundColor: isFront ? NSColor.black : NSColor(white: 0.35, alpha: 1), .shadow: glow, .paragraphStyle: para]
        let h = title.size(withAttributes: attrs).height
        (title as NSString).draw(in: NSRect(x: x, y: (b.height - h) / 2, width: max(0, minR.minX - 8 - x), height: h), withAttributes: attrs)
    }

    /// The three orbs, and nothing else: the panel is clear around them. 10.6 shows the ×, −
    /// and + on all three as soon as the pointer is over any of them, and so did Aqua.
    private func drawLights(aqua: Bool) {
        let hovering = tracker.hovered != nil || tracker.pressed != nil
        for (kind, r) in buttonRects {
            let light: SnowLeopardChrome.Light = kind == .close ? .close : (kind == .minimize ? .minimize : .zoom)
            let pressed = tracker.state(for: kind) == .pressed
            if aqua { AquaGem.draw(r, light, active: isFront, pressed: pressed) }
            else { SnowLeopardChrome.drawLight(r, light, active: isFront, flipped: true) }
            if pressed { NSColor.black.withAlphaComponent(0.18).setFill(); NSBezierPath(ovalIn: r).fill() }
            if hovering && isFront { SnowLeopardChrome.drawGlyph(light, in: r) }
        }
    }

    /// The bar the Applications widget draws (os9.ca's CSS), line for line — see `PlatinumBar`.
    /// The proxy icon before the title is the theme's icon for the app, as the widget shows a
    /// folder before "Applications".
    private func drawPlatinum(_ b: NSRect) {
        PlatinumBar.drawBar(b, active: isFront)
        for (k, r) in buttonRects {
            PlatinumBar.drawBox(r, active: isFront, state: tracker.state(for: k))
            if k == .zoom { PlatinumBar.zoomGlyph(in: r, active: isFront) }
            if k == .collapse { PlatinumBar.collapseGlyph(in: r, active: isFront) }
        }
        let left = (buttonRects.first { $0.0 == .close }?.1.maxX ?? 0) + 8
        let right = (buttonRects.first { $0.0 == .zoom }?.1.minX ?? b.width) - 8
        PlatinumBar.drawTitle(title, icon: icon, in: b, active: isFront, minX: left, maxX: right)
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
        var attrs: [NSAttributedString.Key: Any] = [.font: cs.titleFont,
                                                   .foregroundColor: isFront ? NSColor.white : NSColor(white: 0.9, alpha: 1)]
        if isFront { attrs[.shadow] = shadow }   // XP dropped the emboss on an inactive caption
        let avail = (buttonRects.map { $0.1.minX }.min() ?? b.width) - 8 - x
        let s = title.size(withAttributes: attrs)
        (title as NSString).draw(in: NSRect(x: x, y: (b.height - s.height) / 2, width: max(0, avail), height: s.height),
                                 withAttributes: attrs)
        for (k, r) in buttonRects {
            let base: String
            switch k {
            case .close: base = "close"
            case .maximize: base = zoomed ? "restore" : "max"   // a maximised window offers Restore
            default: base = "min"
            }
            if let img = ChromeAssets.image(dir: "winxp", base: base, state: tracker.state(for: k)) {
                // Inactive captions paled their buttons along with the gradient.
                img.draw(in: r, from: .zero, operation: .sourceOver, fraction: isFront ? 1 : 0.75, respectFlipped: true, hints: nil)
            }
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onPress?()
        // A click on a window that is not in front brings it there first, as the real bar would.
        if !isFront { onActivate?() }
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
        hover(at: convert(event.locationInWindow, from: nil))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoverEnded()
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

/// The Aqua traffic light of Mac OS X 10.0 to 10.5: a candy gem, lit from above, with a dark
/// rim and a soft glow at the bottom. Drawn, not sampled.
enum AquaGem {
    static func draw(_ r: NSRect, _ kind: SnowLeopardChrome.Light, active: Bool, pressed: Bool) {
        let body: NSColor, deep: NSColor
        switch (active, kind) {
        case (false, _):        body = NSColor(srgbRed: 0.80, green: 0.80, blue: 0.80, alpha: 1); deep = NSColor(srgbRed: 0.55, green: 0.55, blue: 0.55, alpha: 1)
        case (true, .close):    body = NSColor(srgbRed: 1.00, green: 0.42, blue: 0.36, alpha: 1); deep = NSColor(srgbRed: 0.74, green: 0.10, blue: 0.08, alpha: 1)
        case (true, .minimize): body = NSColor(srgbRed: 1.00, green: 0.78, blue: 0.30, alpha: 1); deep = NSColor(srgbRed: 0.80, green: 0.50, blue: 0.02, alpha: 1)
        case (true, .zoom):     body = NSColor(srgbRed: 0.55, green: 0.86, blue: 0.36, alpha: 1); deep = NSColor(srgbRed: 0.15, green: 0.52, blue: 0.10, alpha: 1)
        }
        let disc = NSBezierPath(ovalIn: r)
        // Body: light where the light hits it (upper left), deep colour at the rim.
        NSGradient(colors: [body.blended(withFraction: pressed ? 0.25 : 0, of: .black) ?? body, deep])?
            .draw(in: disc, relativeCenterPosition: NSPoint(x: -0.25, y: -0.35))
        // Rim.
        deep.blended(withFraction: 0.35, of: .black)?.setStroke()
        disc.lineWidth = 0.8
        disc.stroke()
        // The specular arc across the top third (y down: near minY).
        let gloss = NSBezierPath(ovalIn: NSRect(x: r.minX + r.width * 0.18, y: r.minY + r.height * 0.06,
                                               width: r.width * 0.64, height: r.height * 0.42))
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.85), NSColor.white.withAlphaComponent(0.05)])?
            .draw(in: gloss, angle: -90)
        // The glow the bottom of the gem gives back.
        let glow = NSBezierPath(ovalIn: NSRect(x: r.minX + r.width * 0.22, y: r.maxY - r.height * 0.36,
                                              width: r.width * 0.56, height: r.height * 0.28))
        body.withAlphaComponent(0.45).setFill()
        glow.fill()
    }
}

/// The patch over the real traffic lights: the real title bar's own colour, photographed just
/// beside the lights and stretched across them. Until the photograph arrives it is clear.
final class LightsPatchView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var onActivate: (() -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    var onPress: (() -> Void)?
    private var dragStart: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
    }
    override func mouseDown(with event: NSEvent) { onPress?(); onActivate?(); dragStart = NSEvent.mouseLocation }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let now = NSEvent.mouseLocation
        onDrag?(NSPoint(x: now.x - start.x, y: now.y - start.y))
    }
    override func mouseUp(with event: NSEvent) { if dragStart != nil { dragStart = nil; onDragEnd?() } }
}
