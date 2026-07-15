import AppKit
import WebKit
import Darwin

/// BeOS "CPU Monitor" desktop widget: a borderless WKWebView panel that loads the
/// BeOS-styled HTML and is driven with live CPU data (System + User load) sampled via the
/// Mach host_statistics API. Launched from the Deskbar's processor tray icon.
final class CPUMonitorController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    static let shared = CPUMonitorController()

    private var panel: NSPanel?
    private var webView: WKWebView?
    private var dragOverlay: DragOverlayView?
    private var timer: Timer?
    private var moveObserver: NSObjectProtocol?
    private var prev: (user: Double, system: Double, idle: Double, nice: Double)?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: .dockThemeChanged, object: nil)
    }

    /// Rebuild the widget fresh on theme switch (correct chrome, no stale collapsed/zoom state).
    @objc private func themeChanged() { destroy() }

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    func show() {
        guard let html = Bundle.main.resourceURL?
            .appendingPathComponent("Widgets/CPUMonitor/CPUMonitor.html"),
              FileManager.default.fileExists(atPath: html.path) else {
            NSSound.beep(); return
        }

        if panel == nil {
            let initial = NSRect(x: 0, y: 0, width: 560, height: 220)
            let cfg = WKWebViewConfiguration()
            cfg.userContentController.add(self, name: "cpu")
            let wv = WKWebView(frame: initial, configuration: cfg)
            wv.navigationDelegate = self
            wv.autoresizingMask = [.width, .height]
            wv.setValue(false, forKey: "drawsBackground")   // transparent (Developer ID build)

            // A transparent overlay over the yellow title-tab handles dragging the window
            // (a mouseDown override on WKWebView itself never fires — its internal views
            // swallow the event) and the close box.
            let overlay = DragOverlayView(frame: .zero)
            overlay.onClose = { [weak self] in self?.close() }
            overlay.onHover = { [weak self] h in
                self?.webView?.evaluateJavaScript("window.setHover && window.setHover(\(h))")
            }
            overlay.onButtonState = { [weak self] slot, state in
                self?.webView?.evaluateJavaScript("window.setBtnState && window.setBtnState('\(slot)','\(state)')")
            }

            let container = NSView(frame: initial)
            container.addSubview(wv)
            container.addSubview(overlay)   // on top

            let p = NSPanel(contentRect: initial,
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .normal   // behaves like a normal window (not always-on-top)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.contentView = container
            self.panel = p
            self.webView = wv
            self.dragOverlay = overlay
            // Remember the position whenever the user drags the widget.
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in self?.saveOrigin() }
        }

        webView?.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        restorePosition()   // place at the saved spot BEFORE showing (no visible jump)
        panel?.orderFrontRegardless()
        startSampling()
    }

    /// Warm hide — stops sampling but keeps the WebView for instant reopen.
    func close() {
        saveOrigin()
        timer?.invalidate(); timer = nil
        prev = nil
        panel?.orderOut(nil)
    }

    /// Cold teardown — removes the script-message handler and releases the WebView.
    func destroy() {
        saveOrigin()
        timer?.invalidate(); timer = nil
        prev = nil
        if let mo = moveObserver { NotificationCenter.default.removeObserver(mo); moveObserver = nil }
        if let wv = webView {
            wv.stopLoading()
            wv.navigationDelegate = nil
            wv.configuration.userContentController.removeAllScriptMessageHandlers()
            wv.removeFromSuperview()
        }
        webView = nil
        dragOverlay = nil
        panel?.orderOut(nil); panel = nil
    }

    private let posKey = "cpuMonitorOrigin"

    private func saveOrigin() {
        guard let panel = panel, panel.isVisible else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: posKey)
    }

    /// Restore the last position if it's still (at least partly) on a screen; else default.
    private func restorePosition() {
        guard let panel = panel else { return }
        if let s = UserDefaults.standard.string(forKey: posKey) {
            let origin = NSPointFromString(s)
            let frame = NSRect(origin: origin, size: panel.frame.size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                panel.setFrameOrigin(origin)
                return
            }
        }
        positionDefault()
    }

    private func positionDefault() {
        guard let panel = panel, let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        // Upper-right, a little inset.
        let f = panel.frame
        panel.setFrameOrigin(NSPoint(x: vf.maxX - f.width - 40, y: vf.maxY - f.height - 40))
    }

    // MARK: - WKScriptMessageHandler (close box)

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "cpu", (message.body as? String) == "close" { close() }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pushCPUInfo()
        // Theme the window chrome (BeOS tab vs Mac OS 9 Platinum) before sizing.
        webView.evaluateJavaScript("window.setTheme && window.setTheme('\(RetroFrameTheme.key())')")
        // Size the panel to the SCALED widget, then capture the draggable title-tab region.
        webView.evaluateJavaScript("window.widgetSize ? window.widgetSize() : [0,0]") { [weak self] result, _ in
            guard let self = self, let panel = self.panel,
                  let arr = result as? [NSNumber], arr.count == 2 else { return }
            let w = CGFloat(truncating: arr[0]), h = CGFloat(truncating: arr[1])
            guard w > 40, h > 40 else { return }
            panel.setContentSize(NSSize(width: w, height: h))
            self.webView?.frame = NSRect(origin: .zero, size: NSSize(width: w, height: h))
            self.restorePosition()
            self.captureDragRegions()
        }
    }

    private func captureDragRegions() {
        webView?.evaluateJavaScript("window.regions ? window.regions() : []") { [weak self] result, _ in
            guard let self = self, let wv = self.webView, let overlay = self.dragOverlay,
                  let a = (result as? [NSNumber])?.map({ CGFloat(truncating: $0) }), a.count >= 8 else { return }
            // [title.x,y,w,h, close.x,y,w,h, (collapse…, zoom…)] — top-left CSS px.
            let tabY = a[1], tabH = a[3]
            let H = wv.bounds.height
            // Full-width overlay (like the Clock widget) so box hit-testing is robust
            // regardless of the title bar's left offset; box rects in absolute x.
            overlay.frame = CGRect(x: 0, y: H - (tabY + tabH), width: wv.bounds.width, height: tabH)
            func local(_ i: Int) -> CGRect {
                CGRect(x: a[i], y: tabH - ((a[i+1] - tabY) + a[i+3]), width: a[i+2], height: a[i+3])
            }
            overlay.closeRect = local(4)
            if a.count >= 16 {   // Mac OS 9: collapse (WindowShade) + zoom boxes
                overlay.collapseRect = local(8)
                overlay.zoomRect = local(12)
                overlay.onCollapse = { [weak self] in self?.resizeToWidget("window.toggleCollapse ? window.toggleCollapse() : [0,0]") }
                overlay.onZoom = { [weak self] in self?.resizeToWidget("window.toggleZoom ? window.toggleZoom() : [0,0]") }
            } else {
                overlay.collapseRect = .zero; overlay.zoomRect = .zero
            }
        }
    }

    /// Run a JS title-control that returns the new widget size; resize the panel
    /// (top-left anchored) and re-capture the title regions.
    private func resizeToWidget(_ js: String) {
        webView?.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self, let panel = self.panel,
                  let arr = result as? [NSNumber], arr.count == 2 else { return }
            let w = CGFloat(truncating: arr[0]), h = CGFloat(truncating: arr[1])
            guard w > 20, h > 20 else { return }
            let top = panel.frame.maxY
            panel.setContentSize(NSSize(width: w, height: h))
            self.webView?.frame = NSRect(origin: .zero, size: NSSize(width: w, height: h))
            var f = panel.frame; f.origin.y = top - f.height; panel.setFrame(f, display: true)
            self.captureDragRegions()
        }
    }

    // MARK: - CPU sampling

    private func startSampling() {
        timer?.invalidate()
        prev = nil
        sampleAndPush()   // prime
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.sampleAndPush() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sampleAndPush() {
        guard let cur = Self.cpuTicks() else { return }
        defer { prev = cur }
        guard let p = prev else { return }   // need two samples
        let du = cur.user - p.user, dn = cur.nice - p.nice
        let ds = cur.system - p.system, di = cur.idle - p.idle
        let total = du + dn + ds + di
        guard total > 0 else { return }
        let userPct = (du + dn) / total * 100.0
        let systemPct = ds / total * 100.0
        webView?.evaluateJavaScript(String(format: "window.setLoad && window.setLoad(%.1f, %.1f)", systemPct, userPct))
    }

    private static func cpuTicks() -> (user: Double, system: Double, idle: Double, nice: Double)? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info_data_t()
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        // cpu_ticks: 0 = USER, 1 = SYSTEM, 2 = IDLE, 3 = NICE
        return (Double(info.cpu_ticks.0), Double(info.cpu_ticks.1), Double(info.cpu_ticks.2), Double(info.cpu_ticks.3))
    }

    // MARK: - CPU identity

    private func pushCPUInfo() {
        let (silicon, model, clock) = Self.cpuInfo()
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") }
        webView?.evaluateJavaScript("window.setCPUInfo && window.setCPUInfo('\(esc(silicon))','\(esc(model))','\(esc(clock))')")
    }

    private static func cpuInfo() -> (silicon: String, model: String, clock: String) {
        let brand = sysctlString("machdep.cpu.brand_string") ?? "CPU"
        let phys = sysctlInt32("hw.physicalcpu") ?? 0
        let logical = sysctlInt32("hw.logicalcpu") ?? 0
        if brand.localizedCaseInsensitiveContains("apple") {
            let model = brand.replacingOccurrences(of: "Apple ", with: "").trimmingCharacters(in: .whitespaces)
            let cores = phys > 0 ? phys : logical
            return ("Apple silicon", model.isEmpty ? "Apple" : model, "\(cores)\u{2011}Core CPU")
        } else {
            var model = "Core"
            if let r = brand.range(of: #"i[3579]"#, options: .regularExpression) { model = "Core " + brand[r] }
            var clock = logical > 0 ? "\(logical)\u{2011}Core CPU" : ""
            if let r = brand.range(of: #"[0-9]+\.[0-9]+\s*GHz"#, options: .regularExpression) {
                clock = brand[r].replacingOccurrences(of: "GHz", with: " GHz").replacingOccurrences(of: "  ", with: " ")
            }
            let silicon = brand.localizedCaseInsensitiveContains("intel") ? "Intel" : "x86"
            return (silicon, model, clock)
        }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
    private static func sysctlInt32(_ name: String) -> Int? {
        var v: Int32 = 0; var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
        return Int(v)
    }
}

/// Transparent view placed over the BeOS yellow title-tab: dragging it moves the window,
/// clicking the close-box region closes the widget. (A WKWebView mouseDown override never
/// fires because the web content's internal views swallow the event — hence this overlay.)
final class DragOverlayView: NSView {
    var onClose: (() -> Void)?
    var onCollapse: (() -> Void)?       // Mac OS 9 WindowShade (collapse box)
    var onZoom: (() -> Void)?           // Mac OS 9 zoom box
    var onHover: ((Bool) -> Void)?      // title-bar hover (Aqua reveals traffic-light glyphs)
    /// Per-button interaction feedback: (slot, state) where slot ∈ "close"/"collapse"/"zoom"
    /// and state ∈ "hover"/"press"/"normal". The widget's JS toggles a class on the button so
    /// its title-bar controls light up like the native chrome. See `window.setBtnState`.
    var onButtonState: ((String, String) -> Void)?
    var closeRect: CGRect = .zero
    var collapseRect: CGRect = .zero
    var zoomRect: CGRect = .zero
    /// While a WebView menu is open (SimpleText's classic menu bar), let clicks fall through
    /// to the WebView so dropdown items over the title bar aren't swallowed as a window drag.
    var passthrough = false
    private var hoverTracking: NSTrackingArea?
    private var hovered: String?
    private var pressed: String?
    override func hitTest(_ point: NSPoint) -> NSView? { passthrough ? nil : super.hitTest(point) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // Keep the normal arrow over the title bar — the resize-corner overlays underneath set a
    // crosshair cursor, which would otherwise show through in the title-bar region.
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = hoverTracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t); hoverTracking = t
    }

    /// The button slot under `p`, matching the exact-then-generous-slop hit-testing used for
    /// clicks (so hover/press light up exactly what a click would trigger).
    private func regionAt(_ p: CGPoint) -> String? {
        // Exact hits first — decisive when boxes are large and adjacent (Win98's trio).
        if closeRect.contains(p) { return "close" }
        if !collapseRect.isEmpty && collapseRect.contains(p) { return "collapse" }
        if !zoomRect.isEmpty && zoomRect.contains(p) { return "zoom" }
        // Then generous slop — Platinum boxes are only ~11px; collapse+zoom route to the
        // nearer box centre where the padded rects overlap.
        let pad: CGFloat = 11
        if closeRect.insetBy(dx: -pad, dy: -pad).contains(p) { return "close" }
        let cHit = !collapseRect.isEmpty && collapseRect.insetBy(dx: -pad, dy: -pad).contains(p)
        let zHit = !zoomRect.isEmpty && zoomRect.insetBy(dx: -pad, dy: -pad).contains(p)
        if cHit || zHit {
            if cHit && zHit { return abs(p.x - collapseRect.midX) <= abs(p.x - zoomRect.midX) ? "collapse" : "zoom" }
            return cHit ? "collapse" : "zoom"
        }
        return nil
    }

    private func fire(_ slot: String) {
        switch slot { case "close": onClose?(); case "collapse": onCollapse?(); case "zoom": onZoom?(); default: break }
    }

    override func mouseEntered(with event: NSEvent) { guard !passthrough else { return }; onHover?(true) }
    override func mouseExited(with event: NSEvent) {
        onHover?(false)
        if let old = hovered { onButtonState?(old, "normal"); hovered = nil }
    }
    override func mouseMoved(with event: NSEvent) {
        guard !passthrough, pressed == nil else { return }
        let r = regionAt(convert(event.locationInWindow, from: nil))
        if r != hovered {
            if let old = hovered { onButtonState?(old, "normal") }
            if let new = r { onButtonState?(new, "hover") }
            hovered = r
        }
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let r = regionAt(p) {
            // Press the button (visual only); it fires on mouse-up-inside, like the native chrome.
            pressed = r; hovered = r
            onButtonState?(r, "press")
            return
        }
        window?.performDrag(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let pr = pressed else { return }
        let inside = regionAt(convert(event.locationInWindow, from: nil)) == pr
        onButtonState?(pr, inside ? "press" : "normal")
    }
    override func mouseUp(with event: NSEvent) {
        guard let pr = pressed else { return }
        let hit = regionAt(convert(event.locationInWindow, from: nil)) == pr
        onButtonState?(pr, "normal")
        pressed = nil
        hovered = hit ? pr : nil
        if hit { fire(pr) }
    }
}
