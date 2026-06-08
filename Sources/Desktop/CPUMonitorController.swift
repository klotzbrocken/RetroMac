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
    @objc private func themeChanged() {
        timer?.invalidate(); timer = nil
        panel?.close(); panel = nil; webView = nil; dragOverlay = nil
    }

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

    func close() {
        saveOrigin()
        timer?.invalidate(); timer = nil
        prev = nil
        panel?.orderOut(nil)
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
            let tabX = a[0], tabY = a[1], tabW = a[2], tabH = a[3]
            let H = wv.bounds.height
            overlay.frame = CGRect(x: tabX, y: H - (tabY + tabH), width: tabW, height: tabH)
            func local(_ i: Int) -> CGRect {
                CGRect(x: a[i] - tabX, y: tabH - ((a[i+1] - tabY) + a[i+3]), width: a[i+2], height: a[i+3])
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
    var closeRect: CGRect = .zero
    var collapseRect: CGRect = .zero
    var zoomRect: CGRect = .zero
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if closeRect.contains(p) { onClose?(); return }
        if !collapseRect.isEmpty, collapseRect.contains(p) { onCollapse?(); return }
        if !zoomRect.isEmpty, zoomRect.contains(p) { onZoom?(); return }
        window?.performDrag(with: event)
    }
}
