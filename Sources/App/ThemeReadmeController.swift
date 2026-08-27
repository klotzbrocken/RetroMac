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
        if message.name == "readmeDrag", let win = window, let d = message.body as? [String: Any],
           let dx = (d["dx"] as? NSNumber)?.doubleValue, let dy = (d["dy"] as? NSNumber)?.doubleValue {
            // The page's own title bar drags the window. `isMovableByWindowBackground` cannot do
            // this: the web view is the content view, so it swallows every mouse event before
            // AppKit sees a background drag — which is why the readme could be closed but never
            // moved, in any theme. The page reports screen deltas; y is inverted (web grows down).
            win.setFrameOrigin(NSPoint(x: win.frame.origin.x + dx, y: win.frame.origin.y - dy))
        }
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
            // Non-persistent: a bundled file: page with no state worth keeping. The default store
            // caches it across launches by URL, and since the path never changes an edited widget
            // kept rendering the previous build. (Notepad is deliberately NOT on this list — it
            // keeps the user's notes in localStorage.)
            cfg.websiteDataStore = .nonPersistent()
            cfg.userContentController.add(self, name: "readmeClose")
            cfg.userContentController.add(self, name: "readmeDrag")
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
        webView.evaluateJavaScript(Self.dragJS)
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

    /// Makes the readme's own title bar drag the window. Every theme gets this; without it the
    /// window is stuck wherever it opened, because the web view eats the mouse events that
    /// `isMovableByWindowBackground` would need.
    private static let dragJS = """
    (function(){
      if (window.__readmeDrag) return; window.__readmeDrag = true;
      var bar = document.querySelector('.titlebar') || document.querySelector('.title-bar');
      if (!bar) return;
      bar.style.cursor = 'default';
      var on = false, sx = 0, sy = 0;
      bar.addEventListener('mousedown', function(e){
        if (e.button !== 0) return;
        // Never steal a click meant for a control in the bar (close box, links, buttons).
        if (e.target.closest('[data-readme-close],button,a,input,select')) return;
        on = true; sx = e.screenX; sy = e.screenY; e.preventDefault();
      });
      window.addEventListener('mousemove', function(e){
        if (!on) return;
        var dx = e.screenX - sx, dy = e.screenY - sy;
        if (dx === 0 && dy === 0) return;
        sx = e.screenX; sy = e.screenY;
        try { window.webkit.messageHandlers.readmeDrag.postMessage({dx: dx, dy: dy}); } catch (err) {}
      });
      window.addEventListener('mouseup', function(){ on = false; });
      window.addEventListener('blur', function(){ on = false; });
    })();
    """

    /// JS that appends a close button to the readme's title bar when the page provides none.
    /// Styled by theme family so it reads as period chrome rather than a foreign control.
    private static func closeButtonJS(for key: String) -> String {
        // Per-family look: Aero/XP red, classic-Windows silver caption, Mac red traffic dot, neutral.
        // "snowleopard" is a Mac key too, it just doesn't start with "macos".
        let isMac = key.hasPrefix("macos") || key == "snowleopard"
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
            // The exact 10.6 orb, rendered by SnowLeopardChrome and inlined here. Built from
            // CSS before, but no CSS primitive can draw that rim: a border or an inset shadow
            // darkens the top and the bottom too, and those are precisely where 10.6 puts the
            // near-white specular and the pale glow. That read as a black cap on the orb.
            b.style.cssText = base + 'top:50%;left:8px;transform:translateY(-50%);width:14px;height:14px;'
              + 'border:none;box-shadow:none;color:transparent;font-size:0;'
              + 'background:center/14px 14px no-repeat url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAADqADAAQAAAABAAAADgAAAACeOBvAAAACaElEQVQoFU1SPUwUURD+3u7b3dvb4/Y4lj3+j0sukRASTIwFEJHKyoJCo8bGQihooJGYWBorExOl8aewM9HECjuDkaiJlY0aRAxyyQF7J3gXPOBY3F1nzmCc5Hs7OzPfm/neewL/2TWgTQGmCeOEPKdC4AvhBeHubcA7KhdHzg3gshDivpu0Ex0DA7DHxgBFoLrwCpufP6G8s1OPoujKLeApc1ReiHQhLuWTwfYOPW+nkB0ZRvuli3CO9aHZ85DySrBNU1b3984NheG3N8BHlceLCfH6RG9OZg0DrqKglchJRYVVXIe5/BV6yUNck7CSSZSq1TMngccyRpp63Eysx7bh+Icwoghy9TtEpQqQEO1nBbaUMISA0HWUMm2JVW9zWpHA2WxXF1KWhbhpQlNVRAd1BNvbCLa2EZKvShUm5dJWHFxL+sYphL7WjAszDCFoZ3DE9xEGv1k+/UsITYNixmDEYnCamkBVeUkdhEbaFOrEBSBfHB7SPdAFsJHmiMkUVw0dOklhjtRSqeKB72eRTjeSCIgQMZhFC2tjMoE32SMJejpdkFZv78tSpXK1q7OzkRTcmYobRrszke4PCAIaIkS5UoHV3b2gHJ+YeLCxu7v/i/W1tEA4Drg7mpv/fnkSjlGOazZqNX9wcvKh+mh+fuvH2ppaLBROO7kcDCIo8TgEg06agUQCO9Ttw/IynJGRm6dmZ583ZqJRMu/m5qYqKyvX6bj1jOvCIiLNiL16HV65jEKxuJ/M5e6MzszcIynlf2+VyO7m0tLwyuLieb9WGwqDoId10mmv64nE2/zo6LOO/v73RCpx/A91kc2wvC974AAAAABJRU5ErkJggg==);'
              + 'background-image:-webkit-image-set('
              + 'url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAADqADAAQAAAABAAAADgAAAACeOBvAAAACaElEQVQoFU1SPUwUURD+3u7b3dvb4/Y4lj3+j0sukRASTIwFEJHKyoJCo8bGQihooJGYWBorExOl8aewM9HECjuDkaiJlY0aRAxyyQF7J3gXPOBY3F1nzmCc5Hs7OzPfm/neewL/2TWgTQGmCeOEPKdC4AvhBeHubcA7KhdHzg3gshDivpu0Ex0DA7DHxgBFoLrwCpufP6G8s1OPoujKLeApc1ReiHQhLuWTwfYOPW+nkB0ZRvuli3CO9aHZ85DySrBNU1b3984NheG3N8BHlceLCfH6RG9OZg0DrqKglchJRYVVXIe5/BV6yUNck7CSSZSq1TMngccyRpp63Eysx7bh+Icwoghy9TtEpQqQEO1nBbaUMISA0HWUMm2JVW9zWpHA2WxXF1KWhbhpQlNVRAd1BNvbCLa2EZKvShUm5dJWHFxL+sYphL7WjAszDCFoZ3DE9xEGv1k+/UsITYNixmDEYnCamkBVeUkdhEbaFOrEBSBfHB7SPdAFsJHmiMkUVw0dOklhjtRSqeKB72eRTjeSCIgQMZhFC2tjMoE32SMJejpdkFZv78tSpXK1q7OzkRTcmYobRrszke4PCAIaIkS5UoHV3b2gHJ+YeLCxu7v/i/W1tEA4Drg7mpv/fnkSjlGOazZqNX9wcvKh+mh+fuvH2ppaLBROO7kcDCIo8TgEg06agUQCO9Ttw/IynJGRm6dmZ583ZqJRMu/m5qYqKyvX6bj1jOvCIiLNiL16HV65jEKxuJ/M5e6MzszcIynlf2+VyO7m0tLwyuLieb9WGwqDoId10mmv64nE2/zo6LOO/v73RCpx/A91kc2wvC974AAAAABJRU5ErkJggg==) 1x,'
              + 'url(data:image/png;base64,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) 2x);';
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
