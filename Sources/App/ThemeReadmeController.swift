import AppKit
import WebKit

/// Opens a theme's "About This Theme" readme — a self-contained, period-styled HTML page in the
/// theme bundle (`readme.html`) with a short history of the OS and a few "did you know" curiosities.
/// One reusable window; loading a different theme's readme just swaps the content.
final class ThemeReadmeController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

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
            wv.navigationDelegate = self
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

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Make every readme fill the window edge-to-edge: the pages wrap content in a centred
        // `.win` card over a coloured `body`, which showed a coloured margin ("Rand um den Rand")
        // inside the borderless themed window. Force the card to fill and drop the body padding /
        // outer shadow so the page's own title bar is the only frame (matches the Win95 readme).
        webView.evaluateJavaScript("""
        (function(){
          var s=document.getElementById('readme-fill'); if(s) s.remove();
          s=document.createElement('style'); s.id='readme-fill';
          s.textContent='html,body{margin:0!important;padding:0!important;background:transparent!important;}'
            +'.win{max-width:none!important;width:100%!important;margin:0!important;min-height:100vh!important;box-shadow:none!important;border-radius:0!important;}';
          document.head.appendChild(s);
        })();
        """)
        // Guarantee every theme's readme is closable: if the page did not draw its own close button
        // (only Win95/Me do), inject a period-appropriate one wired to `readmeClose`.
        webView.evaluateJavaScript(Self.closeButtonJS(for: RetroFrameTheme.key()))
        // Size the window to the content so the readme never needs scrolling (#2). Measure after the
        // close-button injection so its presence is accounted for; clamp to the visible screen.
        webView.evaluateJavaScript("Math.ceil(Math.max(document.body.scrollHeight, document.documentElement.scrollHeight))") { [weak self] result, _ in
            guard let self = self, let win = self.window,
                  let n = result as? NSNumber else { return }
            let content = CGFloat(truncating: n)
            guard content > 0, let screen = win.screen ?? NSScreen.main else { return }
            let maxH = screen.visibleFrame.height - 40
            let newH = min(max(content, 300), maxH)
            // fullSizeContentView: the web view fills the whole window, so content height == window height.
            let top = win.frame.maxY
            var f = win.frame
            f.size.height = newH
            f.origin.y = top - f.height   // keep the top edge anchored
            win.setFrame(f, display: true, animate: false)
        }
    }

    /// JS that appends a close button to the readme's title bar when the page provides none.
    /// Styled by theme family so it reads as period chrome rather than a foreign control.
    private static func closeButtonJS(for key: String) -> String {
        // Per-family look: Aero/XP red, classic-Windows silver caption, Mac red traffic dot, neutral.
        let isMac = key.hasPrefix("macos")
        let variant: String
        switch key {
        case "win7", "winxp":            variant = "winRed"
        case "win98", "win31":           variant = "winSilver"
        default:                         variant = isMac ? "macDot" : "neutral"
        }
        return """
        (function(){
          if (document.querySelector('[data-readme-close]')) return;   // page has its own
          var bar = document.querySelector('.titlebar') || document.body;
          if (getComputedStyle(bar).position === 'static') bar.style.position = 'relative';
          var b = document.createElement('button');
          b.setAttribute('data-readme-close','');
          b.setAttribute('aria-label','Close');
          b.onclick = function(){ try{ window.webkit.messageHandlers.readmeClose.postMessage(1); }catch(e){} };
          var v = '\(variant)';
          var base = 'position:absolute;cursor:pointer;padding:0;display:flex;align-items:center;justify-content:center;';
          if (v === 'macDot') {
            b.style.cssText = base + 'top:50%;left:10px;transform:translateY(-50%);width:12px;height:12px;border-radius:50%;'
              + 'background:#ff5f57;border:1px solid #e0443e;color:transparent;font-size:0;box-shadow:inset 0 0 0 .5px rgba(0,0,0,.1);';
          } else if (v === 'winRed') {
            b.textContent = '\\u2715';
            b.style.cssText = base + 'top:6px;right:8px;width:26px;height:18px;color:#fff;font:700 12px \"Segoe UI\",Arial,sans-serif;'
              + 'background:linear-gradient(#e88a7d,#d05a45 46%,#c8452f 54%,#b23a22);border:1px solid rgba(0,0,0,.35);border-radius:3px;';
          } else if (v === 'winSilver') {
            b.textContent = '\\u2715';
            b.style.cssText = base + 'top:50%;right:6px;transform:translateY(-50%);width:20px;height:18px;color:#000;font:700 12px Tahoma,sans-serif;'
              + 'background:#c0c0c0;border:none;box-shadow:inset 1px 1px 0 #fff,inset -1px -1px 0 #000,inset 2px 2px 0 #dfdfdf,inset -2px -2px 0 #808080;';
          } else {
            b.textContent = '\\u2715';
            b.style.cssText = base + 'top:8px;right:10px;width:22px;height:20px;color:inherit;font:700 13px system-ui,sans-serif;'
              + 'background:rgba(127,127,127,.22);border:1px solid rgba(0,0,0,.28);border-radius:4px;';
          }
          bar.appendChild(b);
        })();
        """
    }
}
