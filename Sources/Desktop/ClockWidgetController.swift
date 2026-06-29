import AppKit
import WebKit

/// Desktop analog-clock widget — square, themed (BeOS replicant / Mac OS 9 / Windows XP /
/// Maiks Favourite). Opened by clicking the clock in the deskbar / taskbar / control strip.
/// Mirrors CPUMonitorController (borderless WKWebView panel + DragOverlayView chrome).
final class ClockWidgetController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    static let shared = ClockWidgetController()

    private var panel: NSPanel?
    private var webView: WKWebView?
    private var dragOverlay: DragOverlayView?
    private var moveObserver: NSObjectProtocol?
    private let posKey = "clockWidgetOrigin"

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: .dockThemeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clockFormatChanged),
                                               name: .clockFormatChanged, object: nil)
    }

    @objc private func themeChanged() { destroy() }

    @objc private func clockFormatChanged() {
        webView?.evaluateJavaScript("window.set24 && window.set24(\(AppSettings.shared.clockUse24Hour))")
    }

    func toggle() { if panel?.isVisible == true { close() } else { show() } }

    /// Warm hide — keeps the WebView alive for instant reopen.
    func close() { saveOrigin(); panel?.orderOut(nil) }

    /// Cold teardown — removes the script-message handler (breaks the userContentController→self
    /// retain cycle) and releases the WebView + its WebContent process. Use when widgets are
    /// turned off or the theme changes.
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
        guard let html = Bundle.main.resourceURL?.appendingPathComponent("Widgets/Clock/Clock.html"),
              FileManager.default.fileExists(atPath: html.path) else { NSSound.beep(); return }

        if panel == nil {
            let initial = NSRect(x: 0, y: 0, width: 200, height: 224)
            let cfg = WKWebViewConfiguration()
            cfg.userContentController.add(self, name: "clock")
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

            let p = NSPanel(contentRect: initial, styleMask: [.borderless, .nonactivatingPanel],
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
        restorePosition()   // remember the last spot (no jump on show)
        panel?.orderFrontRegardless()
    }

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "clock", (message.body as? String) == "close" { close() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.setTheme && window.setTheme('\(RetroFrameTheme.key())')")
        webView.evaluateJavaScript("window.set24 && window.set24(\(AppSettings.shared.clockUse24Hour))")
        // Size the panel to the themed widget, then place the drag/close overlay over the title.
        webView.evaluateJavaScript("window.widgetSize ? window.widgetSize() : [200,224]") { [weak self] result, _ in
            guard let self = self, let panel = self.panel,
                  let a = (result as? [NSNumber])?.map({ CGFloat(truncating: $0) }), a.count == 2, a[0] > 20 else { return }
            panel.setContentSize(NSSize(width: a[0], height: a[1]))
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
            // Full-width title strip as the drag region (robust — the BeOS tab is narrow;
            // dragging anywhere along the top now moves the window). Close box mapped within it.
            overlay.frame = CGRect(x: 0, y: H - (tabY + tabH), width: wv.bounds.width, height: tabH)
            overlay.closeRect = CGRect(x: a[4], y: tabH - ((a[5] - tabY) + a[7]), width: a[6], height: a[7])
            overlay.collapseRect = .zero; overlay.zoomRect = .zero
        }
    }
}
