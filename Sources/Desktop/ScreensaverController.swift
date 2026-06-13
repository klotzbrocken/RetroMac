import AppKit
import WebKit

/// Per-theme screensaver. After `screensaverIdleMinutes` of no input it covers every screen
/// with a fullscreen WKWebView running the theme's chosen saver (3D Pipes / FlowerBox via
/// 98.js at runtime, or the bundled Flying Toasters / Flurry). Any input dismisses it.
/// Idle + dismiss are detected by polling the system-wide input clock — no extra permissions,
/// no global event monitors.
final class ScreensaverController: NSObject, WKNavigationDelegate {

    static let shared = ScreensaverController()

    private var windows: [NSWindow] = []
    private var timer: Timer?
    private var active = false
    private var shownAt: Date?

    private override init() { super.init() }

    /// System-wide seconds since the last input event of any kind.
    private var systemIdleSeconds: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    // MARK: - Idle watch (driven by DockController.start/stop)

    func beginIdleWatch() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func endIdleWatch() {
        timer?.invalidate(); timer = nil
        dismiss()
    }

    private func tick() {
        let idle = systemIdleSeconds
        if active {
            // Stay up for at least 1s (so the click/keypress that launched a manual preview
            // doesn't instantly dismiss it), then dismiss on the next bit of input.
            if let s = shownAt, Date().timeIntervalSince(s) < 1.0 { return }
            if idle < 0.8 { dismiss() }
        } else {
            guard AppSettings.shared.screensaverEnabled, resolvedSaverID() != "none" else { return }
            let threshold = Double(max(1, AppSettings.shared.screensaverIdleMinutes)) * 60.0
            if idle >= threshold { start() }
        }
    }

    // MARK: - Present / dismiss

    /// Show the screensaver now — used by the idle trigger, the Settings "Preview" button and
    /// the desktop "Screen Saver" icon.
    func start() {
        guard !active else { return }
        let id = resolvedSaverID()
        guard id != "none", let url = saverURL(id) else { NSSound.beep(); return }
        active = true
        shownAt = Date()
        for screen in NSScreen.screens {
            let win = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.level = .screenSaver
            win.isOpaque = true
            win.backgroundColor = .black
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            win.ignoresMouseEvents = true

            let cfg = WKWebViewConfiguration()
            // Strip the 98.js program chrome (menu/controls/fullscreen buttons) and make the
            // saver canvas fill the screen — otherwise Pipes shows its on-screen control UI.
            cfg.userContentController.addUserScript(
                WKUserScript(source: Self.saverChromeCSS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            let wv = WKWebView(frame: NSRect(origin: .zero, size: screen.frame.size), configuration: cfg)
            wv.navigationDelegate = self
            wv.autoresizingMask = [.width, .height]
            wv.setValue(false, forKey: "drawsBackground")
            if url.isFileURL {
                // Allow the whole Screensavers dir so shared assets resolve.
                let root = url.deletingLastPathComponent().deletingLastPathComponent()
                wv.loadFileURL(url, allowingReadAccessTo: root)
            } else {
                wv.load(URLRequest(url: url))
            }
            win.contentView = wv
            win.orderFrontRegardless()
            windows.append(win)
        }
        NSCursor.hide()
        if timer == nil { beginIdleWatch() }   // ensure the dismiss poll runs even for manual starts
    }

    func dismiss() {
        guard active else { return }
        active = false
        shownAt = nil
        NSCursor.unhide()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    // MARK: - Saver resolution

    private func resolvedSaverID() -> String {
        let name = ThemeManager.shared.activeTheme?.config.name ?? ""
        if let o = AppSettings.shared.themeScreensaverOverrides[name], !o.isEmpty { return o }
        return ThemeManager.shared.activeTheme?.config.screensaver ?? "none"
    }

    private func saverURL(_ id: String) -> URL? {
        switch id {
        case "pipes":
            return Bundle.main.resourceURL?.appendingPathComponent("Widgets/Screensavers/Pipes/index.html")
        case "flowerbox":
            return Bundle.main.resourceURL?.appendingPathComponent("Widgets/Screensavers/FlowerBox/index.html")
        case "flying-toasters":
            return Bundle.main.resourceURL?.appendingPathComponent("Widgets/Screensavers/FlyingToasters/index.html")
        case "flurry":
            return Bundle.main.resourceURL?.appendingPathComponent("Widgets/Screensavers/Flurry/index.html")
        default:
            return nil
        }
    }

    /// Injected at document start: hide the 98.js program chrome/controls and make the saver
    /// canvas truly fullscreen (applies to Pipes; harmless for the bare FlowerBox/local savers).
    private static let saverChromeCSS = """
    (function(){
      var css = "html,body{margin:0!important;padding:0!important;width:100%!important;height:100%!important;background:#000!important;overflow:hidden!important;cursor:none!important}"
        + ".controls,.ui-container,.toggle-controls,.fullscreen-button,nav,.menu-bar,.menus{display:none!important}"
        + ".canvas-container{position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important}"
        + "canvas{width:100vw!important;height:100vh!important;display:block!important}";
      var s = document.createElement('style'); s.textContent = css;
      (document.head || document.documentElement).appendChild(s);
    })();
    """

    /// Available savers for the Settings picker (id, display name).
    static let available: [(id: String, name: String)] = [
        ("none", "None"),
        ("pipes", "3D Pipes"),
        ("flowerbox", "3D FlowerBox"),
        ("flying-toasters", "Flying Toasters"),
        ("flurry", "Flurry"),
    ]
}
