import AppKit
import WebKit

/// Desktop Calculator widget — a themed standard calculator (BeOS / Mac OS 9 / Windows XP /
/// Windows 98 / Maiks Favourite / Mac OS X Aqua). Opened from a "Calculator" desktop icon
/// (type "calculator"). Mirrors ClockWidgetController (borderless WKWebView panel +
/// DragOverlayView chrome) but uses a key-accepting panel so the keypad takes keyboard input.
final class CalculatorController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    static let shared = CalculatorController()

    private var panel: KeyableWidgetPanel?
    private var webView: WKWebView?
    private var dragOverlay: DragOverlayView?
    private var moveObserver: NSObjectProtocol?
    private let posKey = "calculatorWidgetOrigin"

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
        guard let html = Bundle.main.resourceURL?.appendingPathComponent("Widgets/Calculator/Calculator.html"),
              FileManager.default.fileExists(atPath: html.path) else { NSSound.beep(); return }

        if panel == nil {
            let initial = NSRect(x: 0, y: 0, width: 236, height: 240)
            let cfg = WKWebViewConfiguration()
            cfg.userContentController.add(self, name: "calculator")
            let wv = WKWebView(frame: initial, configuration: cfg)
            wv.navigationDelegate = self
            wv.autoresizingMask = [.width, .height]
            wv.setValue(false, forKey: "drawsBackground")

            let overlay = DragOverlayView(frame: .zero)
            overlay.onClose = { [weak self] in self?.close() }
            overlay.onHover = { [weak self] h in
                self?.webView?.evaluateJavaScript("window.setHover && window.setHover(\(h))")
            }
            overlay.onButtonState = { [weak self] slot, state in
                self?.webView?.evaluateJavaScript("window.setBtnState && window.setBtnState('\(slot)','\(state)')")
            }

            let container = NSView(frame: initial)
            addWin7Glass(to: container)   // Aero glass behind the transparent webview (win7 only)
            container.addSubview(wv); container.addSubview(overlay)

            let p = KeyableWidgetPanel(contentRect: initial, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.level = .normal
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.contentView = container
            self.panel = p; self.webView = wv; self.dragOverlay = overlay
            installMacOS9BlurTracking(panel: p) { [weak self] in self?.webView }
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in self?.saveOrigin() }
        }

        webView?.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        restorePosition()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "calculator", (message.body as? String) == "close" { close() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.setTheme && window.setTheme('\(RetroFrameTheme.key())')")
        webView.evaluateJavaScript("window.widgetSize ? window.widgetSize() : [236,240]") { [weak self] result, _ in
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
            overlay.frame = CGRect(x: 0, y: H - (tabY + tabH), width: wv.bounds.width, height: tabH)
            overlay.closeRect = CGRect(x: a[4], y: tabH - ((a[5] - tabY) + a[7]), width: a[6], height: a[7])
            overlay.collapseRect = .zero; overlay.zoomRect = .zero
        }
    }
}
