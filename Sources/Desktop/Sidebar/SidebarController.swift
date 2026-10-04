import AppKit
import WebKit

/// Windows Vista's Sidebar: a column on the right edge of the main screen, from the menu bar
/// down to the taskbar, holding gadgets (clock, calendar, CPU/memory meter). Shown for themes
/// that declare `sidebar`. It sits below normal windows, as Vista's did unless "always on top"
/// was ticked. The gadgets live in one web page; this feeds it the CPU and memory load once a
/// second and keeps the user's choice of gadgets.
final class SidebarController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    static let shared = SidebarController()
    static let width: CGFloat = 150
    static let allGadgets: [(id: String, title: String)] = [("clock", "Clock"), ("calendar", "Calendar"), ("cpu", "CPU Meter")]

    private var panel: NSPanel?
    private var webView: WKWebView?
    private var timer: Timer?
    private var lastTicks: SystemSampler.Ticks?
    private var screenObserver: NSObjectProtocol?
    private let gadgetsKey = "sidebarGadgets"

    /// True while the theme has a Sidebar at all (whether or not the user closed it).
    var isAvailable: Bool { !AppSettings.shared.dockOnly && ThemeManager.shared.activeTheme?.config.sidebar != nil }
    var isShown: Bool { panel != nil }

    /// "Close Sidebar" sticks, across theme switches and launches, until it is opened again.
    private var userClosed: Bool {
        get { UserDefaults.standard.bool(forKey: "sidebarClosed") }
        set { UserDefaults.standard.set(newValue, forKey: "sidebarClosed") }
    }

    func update() {
        guard isAvailable, !userClosed, let config = ThemeManager.shared.activeTheme?.config.sidebar else { hide(); return }
        show(defaultGadgets: config.gadgets ?? Self.allGadgets.map(\.id))
    }

    /// Open or close it — the Start menu's "Windows Sidebar" entry.
    func toggle() { userClosed = isShown; update() }

    func hide() {
        timer?.invalidate(); timer = nil
        if let o = screenObserver { NotificationCenter.default.removeObserver(o); screenObserver = nil }
        if let wv = webView {
            wv.stopLoading()
            wv.navigationDelegate = nil
            wv.configuration.userContentController.removeAllScriptMessageHandlers()
        }
        webView = nil
        panel?.orderOut(nil); panel = nil
        lastTicks = nil
    }

    private var defaultGadgets: [String] = []
    /// The gadgets on show: the user's choice from the "+" menu, else the theme's.
    private var gadgets: [String] {
        get { UserDefaults.standard.stringArray(forKey: gadgetsKey) ?? defaultGadgets }
        set { UserDefaults.standard.set(newValue, forKey: gadgetsKey) }
    }

    private func show(defaultGadgets: [String]) {
        self.defaultGadgets = defaultGadgets
        // The taskbar may come up after the theme switch that calls this; look again once it has.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.reposition() }
        guard panel == nil else { reposition(); return }
        guard let html = Bundle.main.resourceURL?.appendingPathComponent("Widgets/Sidebar/Sidebar.html"),
              FileManager.default.fileExists(atPath: html.path) else { return }

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()   // a bundled page with nothing to keep
        cfg.userContentController.add(self, name: "sidebar")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = self
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")

        let p = KeyableWidgetPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 400),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Above the desktop icons (normal − 4), below every app window.
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) - 3)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        // No .fullScreenAuxiliary: the Sidebar stays off full-screen Spaces by itself.
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.contentView = wv
        panel = p; webView = wv

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            // The taskbar settles after the screen change; follow it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.reposition() }
        }
        reposition()
        wv.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        p.orderFrontRegardless()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
    }

    private func reposition() {
        guard let panel = panel, let screen = NSScreen.main else { return }
        var f = screen.visibleFrame
        // With the menu bar hidden its strip still slides in under the pointer and takes the
        // click, so the "+" has to sit below it either way.
        f.size.height = min(f.height, screen.frame.maxY - NSStatusBar.system.thickness - f.minY)
        // Stop at the taskbar, as Vista's did.
        if let bar = DockController.shared.barScreenFrame, bar.intersects(f), bar.maxY < f.maxY - 100 {
            f.size.height = f.maxY - bar.maxY; f.origin.y = bar.maxY
        }
        panel.setFrame(NSRect(x: f.maxX - Self.width, y: f.minY, width: Self.width, height: f.height), display: true)
    }

    // MARK: - Data

    /// CPU and memory in percent, once a second. Only the system totals are read (no process
    /// list), so this costs next to nothing.
    private func sample() {
        guard let wv = webView, let now = SystemSampler.totalTicks() else { return }
        defer { lastTicks = now }
        guard let last = lastTicks, let load = SystemSampler.load(from: last, to: now) else { return }
        var ram = 0.0
        if let vm = SystemSampler.vmStats(), let physical = SystemSampler.sysctlUInt64("hw.memsize"), physical > 0 {
            let used = UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
            ram = min(100, Double(used * UInt64(vm_kernel_page_size)) / Double(physical) * 100)
        }
        wv.evaluateJavaScript("window.update && window.update({cpu:\(Int(load.busy.rounded())),ram:\(Int(ram.rounded()))})")
    }

    // MARK: - Page

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pushGadgets()
        sample()
    }

    private func pushGadgets() {
        let list = gadgets.map { "'\($0)'" }.joined(separator: ",")
        webView?.evaluateJavaScript("window.setGadgets && window.setGadgets([\(list)])")
    }

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "sidebar", let wv = webView,
              let body = message.body as? [String: Any], let x = body["x"] as? Double, let y = body["y"] as? Double else { return }
        // The "+" and a right-click both open this: which gadgets to show (Vista's "Add Gadgets"
        // gallery, cut down to a list) and "Close Sidebar".
        let menu = NSMenu()
        for g in Self.allGadgets {
            let item = NSMenuItem(title: g.title, action: #selector(toggleGadget(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = g.id
            item.state = gadgets.contains(g.id) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let close = NSMenuItem(title: "Close Sidebar", action: #selector(closeSidebar), keyEquivalent: "")
        close.target = self
        menu.addItem(close)
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: wv)   // page coordinates: WKWebView is flipped
    }

    @objc private func closeSidebar() { userClosed = true; hide() }

    @objc private func toggleGadget(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        var list = gadgets
        if let i = list.firstIndex(of: id) { list.remove(at: i) } else {
            // Keep the Sidebar's own order whatever order they were ticked in.
            list = Self.allGadgets.map(\.id).filter { list.contains($0) || $0 == id }
        }
        gadgets = list
        pushGadgets()
    }
}
