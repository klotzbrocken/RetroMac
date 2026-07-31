import AppKit
import WebKit

/// Opens a theme's "About This Theme" readme — a self-contained, period-styled HTML page in the
/// theme bundle (`readme.html`) with a short history of the OS and a few "did you know" curiosities.
/// One reusable window; loading a different theme's readme just swaps the content.
final class ThemeReadmeController: NSObject, WKScriptMessageHandler {

    static let shared = ThemeReadmeController()
    private var window: NSWindow?
    private var webView: WKWebView?
    private override init() { super.init() }

    /// The readme page draws its own period close button; it posts `readmeClose` to shut the window
    /// (the native traffic lights are hidden so the themed title bar is the only chrome).
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "readmeClose" { window?.performClose(nil) }
    }

    /// A theme has a readme when its bundle ships a `readme.html`.
    static func activeThemeHasReadme() -> Bool {
        guard let t = ThemeManager.shared.activeTheme else { return false }
        return FileManager.default.fileExists(atPath: t.url.appendingPathComponent("readme.html").path)
    }

    func showForActiveTheme() {
        guard let theme = ThemeManager.shared.activeTheme else { return }
        let readme = theme.url.appendingPathComponent("readme.html")
        guard FileManager.default.fileExists(atPath: readme.path) else { return }

        if window == nil {
            let cfg = WKWebViewConfiguration()
            cfg.userContentController.add(self, name: "readmeClose")
            let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 580, height: 720), configuration: cfg)
            wv.setValue(false, forKey: "drawsBackground")   // let the page paint its own backdrop
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 720),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                               backing: .buffered, defer: false)
            win.isReleasedWhenClosed = false
            // The readme paints its own period title bar (Win98/XP/NeXT chrome). Let that be the only
            // visible bar: make the native title bar transparent + full-height content, and hide the
            // native title text so it does not stack a second (Aqua) bar on top of the themed one.
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.isMovableByWindowBackground = true
            // No Aqua traffic lights over a Win98/XP/NeXT title bar — the page draws its own chrome.
            // The window stays closable via Cmd-W / the Window menu.
            win.standardWindowButton(.closeButton)?.isHidden = true
            win.standardWindowButton(.miniaturizeButton)?.isHidden = true
            win.standardWindowButton(.zoomButton)?.isHidden = true
            win.contentView = wv
            win.center()
            win.minSize = NSSize(width: 420, height: 480)
            window = win
            webView = wv
        }
        window?.title = ThemeManager.displayName(for: theme.config.name)
        // Read access to the whole bundle so the page can reference the theme's own icons/wallpaper.
        webView?.loadFileURL(readme, allowingReadAccessTo: theme.url)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
