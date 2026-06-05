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

    private override init() { super.init() }

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
            p.level = .floating
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
        positionDefault()
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
                  let a = result as? [NSNumber], a.count == 8 else { return }
            let v = a.map { CGFloat(truncating: $0) }
            // [tab.x, tab.y, tab.w, tab.h, close.x, close.y, close.w, close.h] — top-left CSS px.
            let tabX = v[0], tabY = v[1], tabW = v[2], tabH = v[3]
            let cX = v[4], cY = v[5], cW = v[6], cH = v[7]
            let H = wv.bounds.height
            // Overlay sits over the tab strip (AppKit bottom-left coords).
            overlay.frame = CGRect(x: tabX, y: H - (tabY + tabH), width: tabW, height: tabH)
            // Close box relative to the overlay (bottom-left within the tab).
            overlay.closeRect = CGRect(x: cX - tabX, y: tabH - ((cY - tabY) + cH), width: cW, height: cH)
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
    var closeRect: CGRect = .zero
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if closeRect.contains(p) { onClose?(); return }
        window?.performDrag(with: event)
    }
}
