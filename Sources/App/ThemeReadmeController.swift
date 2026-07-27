import AppKit
import WebKit

/// Opens a theme's "About This Theme" readme — a self-contained, period-styled HTML page in the
/// theme bundle (`readme.html`) with a short history of the OS and a few "did you know" curiosities.
/// One reusable window; loading a different theme's readme just swaps the content.
final class ThemeReadmeController: NSObject {

    static let shared = ThemeReadmeController()
    private var window: NSWindow?
    private var webView: WKWebView?
    private override init() { super.init() }

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
            let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 580, height: 720))
            wv.setValue(false, forKey: "drawsBackground")   // let the page paint its own backdrop
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 720),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable],
                               backing: .buffered, defer: false)
            win.isReleasedWhenClosed = false
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
