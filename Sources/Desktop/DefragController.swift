import AppKit
import WebKit

/// Disk Defragmenter — a faithful recreation of the Windows 95/98 defrag utility as a desktop
/// widget: the cluster grid, the segmented progress bar, Legend and Hide Details. Purely a
/// nostalgia simulation; it never reads, moves or touches a single real file.
/// Mirrors CalculatorController (borderless WKWebView panel + DragOverlayView chrome).
final class DefragController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    static let shared = DefragController()

    private var panel: NSPanel?
    private var webView: WKWebView?
    private var dragOverlay: DragOverlayView?
    private var moveObserver: NSObjectProtocol?
    private let posKey = "defragWidgetOrigin"

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: .dockThemeChanged, object: nil)
    }

    @objc private func themeChanged() { destroy() }

    func toggle() { if panel?.isVisible == true { close() } else { show() } }

    /// Warm hide — keeps the WebView alive for instant reopen.
    func close() { saveOrigin(); panel?.orderOut(nil) }

    /// Cold teardown — removes the script-message handler and releases the WebView.
    func destroy() {
        saveOrigin()
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

    private func saveOrigin() {
        guard let panel = panel, panel.isVisible else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: posKey)
    }
    private func restorePosition() {
        guard let panel = panel else { return }
        if let s = UserDefaults.standard.string(forKey: posKey) {
            let origin = NSPointFromString(s)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(NSRect(origin: origin, size: panel.frame.size)) }) {
                panel.setFrameOrigin(origin); return
            }
        }
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.midX - panel.frame.width / 2, y: vf.midY - panel.frame.height / 2))
        }
    }

    func show() {
        guard let html = Bundle.main.resourceURL?.appendingPathComponent("Widgets/Defrag/Defrag.html"),
              FileManager.default.fileExists(atPath: html.path) else { NSSound.beep(); return }

        if panel == nil {
            let initial = NSRect(x: 0, y: 0, width: 604, height: 360)
            let cfg = WKWebViewConfiguration()
            cfg.userContentController.add(self, name: "defrag")
            let wv = WKWebView(frame: initial, configuration: cfg)
            wv.navigationDelegate = self
            wv.autoresizingMask = [.width, .height]
            wv.setValue(false, forKey: "drawsBackground")

            let overlay = DragOverlayView(frame: .zero)
            overlay.onClose = { [weak self] in self?.close() }
            overlay.onHover = { [weak self] h in
                self?.webView?.evaluateJavaScript("window.setHover && window.setHover(\(h))")
            }

            let container = NSView(frame: initial)
            container.addSubview(wv); container.addSubview(overlay)

            let p = KeyableWidgetPanel(contentRect: initial, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
            p.level = .normal
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.contentView = container
            self.panel = p; self.webView = wv; self.dragOverlay = overlay
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in self?.saveOrigin() }
        }

        webView?.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        restorePosition()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "defrag", let cmd = message.body as? String else { return }
        switch cmd {
        case "close":  close()
        case "resize": fitToContent()          // "Hide Details" collapses the cluster grid
        default: break
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // The title bar carries the program icon, like every other Win95/98 window.
        let name = ThemeManager.shared.activeTheme?.config.desktopIcons?
            .first(where: { $0.type == "defrag" })?.icon ?? "defrag.png"
        if let dataURL = ThemeManager.shared.iconDataURL(name) {
            webView.evaluateJavaScript("window.setWinIcon && window.setWinIcon('\(dataURL)')")
        }
        fitToContent()
    }

    /// Size the panel to the widget's own reported size, then re-place the title-bar overlay.
    private func fitToContent() {
        webView?.evaluateJavaScript("window.widgetSize ? window.widgetSize() : [604,360]") { [weak self] result, _ in
            guard let self = self, let panel = self.panel,
                  let a = (result as? [NSNumber])?.map({ CGFloat(truncating: $0) }),
                  a.count == 2, a[0] > 20 else { return }
            let top = panel.frame.maxY
            panel.setContentSize(NSSize(width: a[0], height: a[1]))
            var f = panel.frame; f.origin.y = top - f.height   // keep the top edge anchored
            panel.setFrame(f, display: true)
            self.webView?.frame = NSRect(origin: .zero, size: NSSize(width: a[0], height: a[1]))
            self.captureRegions()
        }
    }

    private func captureRegions() {
        webView?.evaluateJavaScript("window.regions ? window.regions() : []") { [weak self] result, _ in
            guard let self = self, let wv = self.webView, let overlay = self.dragOverlay,
                  let a = (result as? [NSNumber])?.map({ CGFloat(truncating: $0) }), a.count >= 8 else { return }
            let tabY = a[1], tabH = a[3]
            let H = wv.bounds.height
            overlay.frame = CGRect(x: 0, y: H - (tabY + tabH), width: wv.bounds.width, height: tabH)
            overlay.closeRect = CGRect(x: a[4], y: tabH - ((a[5] - tabY) + a[7]), width: a[6], height: a[7])
            overlay.collapseRect = .zero; overlay.zoomRect = .zero
        }
    }
}
