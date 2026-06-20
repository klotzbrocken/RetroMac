import AppKit
import WebKit

/// Key-accepting borderless panel — the 98.js games need keyboard input.
final class WebAppPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Themed app window: NATIVE chrome (Win98 spec / XP Luna / plain) drawn in Swift —
/// crisp at any scale, close always works — hosting a WKWebView that loads the target
/// URL top-level (sites that forbid iframes, like yahoo.com, work fine).
final class WebAppController: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler {

    private static var openWindows: [String: WebAppController] = [:]

    static func open(name: String, url: String, width: CGFloat, height: CGFloat) {
        if let existing = openWindows[url], existing.panel?.isVisible == true {
            existing.panel?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let c = WebAppController(name: name, url: url, size: NSSize(width: width, height: height))
        openWindows[url] = c
        c.show()
    }

    /// Hosts that serve the self-contained 98.js apps and may carry the native Save/Print
    /// bridge. The project moved from GitHub Pages to its own domain — the old github.io URL
    /// now 301-redirects there, so both must be trusted (otherwise the cross-host redirect is
    /// blocked by the navigation confinement below and the app never loads).
    static func isTrusted98Host(_ host: String?) -> Bool {
        host == "bored-win98.pisaucer.com" || host == "bored-entertainment.github.io"
    }

    /// True only for a trusted 98.js host (current dedicated domain, or the legacy github.io
    /// path-scoped URL which redirects to it).
    static func isTrusted98App(_ urlString: String) -> Bool {
        guard let c = URLComponents(string: urlString), c.scheme == "https" else { return false }
        if c.host == "bored-win98.pisaucer.com" { return true }
        if c.host == "bored-entertainment.github.io" && c.path.hasPrefix("/98.js/") { return true }
        return false
    }

    static func closeAll() {
        Array(openWindows.values).forEach { $0.close() }   // full teardown (handlers + webview), not just orderOut
        openWindows.removeAll()
    }

    private let appName: String
    private let appURL: String
    private let size: NSSize
    private var panel: WebAppPanel?
    private weak var webView: WKWebView?
    private var bridgeActive = false   // true only for trusted 98.js windows (native Save/Print)

    private init(name: String, url: String, size: NSSize) {
        self.appName = name; self.appURL = url; self.size = size
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: .dockThemeChanged, object: nil)
    }

    @objc private func themeChanged() { close() }

    private func show() {
        let frame = NSRect(origin: .zero, size: size)
        // A window is a trusted self-contained 98.js app ONLY if it is served from the exact
        // 98.js host + path — not any URL that merely contains "github.io" somewhere (e.g.
        // github.io.evil.com or example.com/?github.io). Trusted apps get the native
        // Save/Print bridge and no nav chrome; everything else is a plain browser window.
        let isTrusted98 = Self.isTrusted98App(appURL)
        let showNav = !isTrusted98
        bridgeActive = isTrusted98
        let chrome = WebAppChromeView(frame: frame, title: appName, showNav: showNav)
        chrome.onClose = { [weak self] in self?.close() }

        let cfg = WKWebViewConfiguration()
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        // Bridge the hosted apps' File/Print menus to native macOS: window.print() and
        // <a download> clicks (how Notepad/Paint "Save"/"Save As" fall back when the
        // File System Access API is unavailable, as it is in WKWebView) are routed to Swift.
        //
        // SECURITY: only install the bridge for the self-contained 98.js app windows — NOT
        // for the IE/browser windows (`showNav`), which load arbitrary websites. And only in
        // the main frame, so embedded ad iframes can never trigger a native save/print dialog.
        if !showNav {
            let ucc = WKUserContentController()
            ucc.add(self, name: "webapp")
            ucc.addUserScript(WKUserScript(source: Self.bridgeJS, injectionTime: .atDocumentStart,
                                           forMainFrameOnly: true))
            ucc.addUserScript(WKUserScript(source: Self.saveAsJS, injectionTime: .atDocumentEnd,
                                           forMainFrameOnly: true))
            // Internet Explorer (98.js explorer shell): point its hardcoded Home button at RetroMac.
            if appURL.contains("programs/explorer") {
                ucc.addUserScript(WKUserScript(source: Self.homeOverrideJS, injectionTime: .atDocumentStart,
                                               forMainFrameOnly: true))
            }
            cfg.userContentController = ucc
        }

        let wv = WKWebView(frame: chrome.contentRect(), configuration: cfg)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        wv.uiDelegate = self
        if let u = URL(string: appURL) { wv.load(URLRequest(url: u)) }
        chrome.embed(wv)
        self.webView = wv
        chrome.onBack = { [weak wv] in if wv?.canGoBack == true { wv?.goBack() } }
        chrome.onForward = { [weak wv] in if wv?.canGoForward == true { wv?.goForward() } }

        let p = WebAppPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        p.level = .normal
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.hidesOnDeactivate = false
        p.minSize = NSSize(width: 360, height: 240)            // resizable, with a floor
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView = chrome
        self.panel = p
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    private func close() {
        // Tear down the WebView explicitly: removing the script-message handler breaks the
        // userContentController → self retain cycle (WebKit can otherwise keep the handler,
        // config and web content process alive long after the window is gone).
        if let wv = webView {
            wv.stopLoading()
            wv.navigationDelegate = nil
            wv.uiDelegate = nil
            wv.configuration.userContentController.removeAllScriptMessageHandlers()
            wv.removeFromSuperview()
        }
        webView = nil
        panel?.orderOut(nil); panel = nil
        WebAppController.openWindows.removeValue(forKey: appURL)
    }

    // MARK: - File dialogs / popups / downloads (Notepad & Paint open/save support)

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = parameters.allowsMultipleSelection
        p.canChooseDirectories = parameters.allowsDirectories
        NSApp.activate(ignoringOtherApps: true)
        p.begin { resp in completionHandler(resp == .OK ? p.urls : nil) }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // window.open / target=_blank → load in the same window instead of nothing.
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        // Bridge-equipped (trusted 98.js) windows must STAY on the trusted host — a redirect
        // or link to another domain must not inherit the native Save/Print bridge.
        if bridgeActive,
           navigationAction.targetFrame?.isMainFrame == true,
           let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
           !Self.isTrusted98Host(url.host) {
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        // Always ask the user where to save — never write to ~/Downloads silently, so a page
        // (e.g. inside the IE window) can't drop files without explicit consent.
        let sp = NSSavePanel()
        sp.nameFieldStringValue = suggestedFilename
        sp.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        sp.begin { resp in
            completionHandler(resp == .OK ? sp.url : nil)
        }
    }

    // MARK: - JS bridge (Save / Save As / Print / Page Setup)

    /// Injected at document start. Routes the hosted apps' save/print actions to native macOS.
    /// Save paths covered: real <a download> clicks (jspaint), programmatic a.click(), and
    /// FileSaver.js / blob saveAs() which dispatch a click on a *detached* anchor (Notepad).
    private static let bridgeJS = """
    (function(){
      function post(m){ try{ window.webkit.messageHandlers.webapp.postMessage(m); }catch(e){} }
      function saveHref(href, name){
        if(!href) return;
        fetch(href).then(function(r){return r.blob();}).then(function(b){
          var fr = new FileReader();
          fr.onload = function(){ post({action:'save', name:(name||'document'), data:fr.result}); };
          fr.readAsDataURL(b);
        }).catch(function(){});
      }
      // Print + Page Setup → native print panel.
      window.print = function(){ post({action:'print'}); };
      // Real clicks on a download link (capture phase).
      document.addEventListener('click', function(e){
        var a = e.target && e.target.closest ? e.target.closest('a[download]') : null;
        if(!a || !a.href) return;
        e.preventDefault(); e.stopPropagation();
        saveHref(a.href, a.getAttribute('download'));
      }, true);
      // Programmatic anchor.click() on a download link.
      var origClick = HTMLAnchorElement.prototype.click;
      HTMLAnchorElement.prototype.click = function(){
        if(this.download && this.href){ saveHref(this.href, this.download); return; }
        return origClick.apply(this, arguments);
      };
      // FileSaver.js path: dispatchEvent(new MouseEvent('click')) on a detached anchor.
      var origDispatch = EventTarget.prototype.dispatchEvent;
      EventTarget.prototype.dispatchEvent = function(ev){
        if(ev && ev.type === 'click' && this.tagName === 'A' && this.download && this.href){
          saveHref(this.href, this.download); return true;
        }
        return origDispatch.call(this, ev);
      };
    })();
    """

    /// Repoints the 98.js explorer's hardcoded Home button at RetroMac. A capture-phase
    /// listener runs before jQuery's bubble handler and cancels the original go_home().
    private static let homeOverrideJS = """
    (function(){
      var HOME = "https://www.myretromac.app";
      document.addEventListener('click', function(e){
        var h = e.target && e.target.closest ? e.target.closest('.home-button') : null;
        if(!h) return;
        e.stopImmediatePropagation(); e.preventDefault();
        if (typeof window.go_to === 'function') { window.go_to(HOME); }
        else { var a = document.getElementById('address'); if(a){ a.value = HOME; } window.location.href = window.location.href; }
      }, true);
    })();
    """

    /// Injected at document end — after FileSaver.js has installed its global — so Notepad's
    /// saveAs(blob, name) is captured directly even if the anchor path is missed.
    private static let saveAsJS = """
    (function(){
      function post(m){ try{ window.webkit.messageHandlers.webapp.postMessage(m); }catch(e){} }
      if (typeof window.saveAs === 'function') {
        window.saveAs = function(blob, name){
          var fr = new FileReader();
          fr.onload = function(){ post({action:'save', name:(name||'document'), data:fr.result}); };
          fr.readAsDataURL(blob);
        };
      }
    })();
    """

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        switch action {
        case "print": runPrint()
        case "save":  saveFromBridge(name: body["name"] as? String ?? "document",
                                     dataURL: body["data"] as? String ?? "")
        default: break
        }
    }

    private func runPrint() {
        guard let wv = webView else { return }
        let info = NSPrintInfo.shared
        let op = wv.printOperation(with: info)
        op.showsPrintPanel = true          // the print panel also exposes paper/orientation (Page Setup)
        op.showsProgressPanel = true
        if let win = panel { op.runModal(for: win, delegate: nil, didRun: nil, contextInfo: nil) }
        else { op.run() }
    }

    /// Max accepted bridge-save payload (the base64 string length, pre-decode).
    private static let maxSavePayloadBytes = 25 * 1024 * 1024

    private func saveFromBridge(name: String, dataURL: String) {
        // data:[<mime>][;base64],<payload>
        guard let comma = dataURL.firstIndex(of: ",") else { return }
        let payload = String(dataURL[dataURL.index(after: comma)...])
        guard payload.utf8.count <= Self.maxSavePayloadBytes else {
            NSLog("[WebApp] Save rejected — payload exceeds %d bytes", Self.maxSavePayloadBytes)
            return
        }
        // Decode off the main thread (large images can be multi-MB), then present the panel.
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = Data(base64Encoded: payload) else { return }
            DispatchQueue.main.async {
                let sp = NSSavePanel()
                sp.nameFieldStringValue = name
                sp.canCreateDirectories = true
                NSApp.activate(ignoringOtherApps: true)
                sp.begin { resp in
                    guard resp == .OK, let url = sp.url else { return }
                    try? data.write(to: url)
                }
            }
        }
    }
}

/// Native themed window frame. Flipped coordinates (origin top-left) keep the math simple.
final class WebAppChromeView: NSView {

    enum Style { case win98, winxp, plain }

    var onClose: (() -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    private let title: String
    private let style: Style
    private let showNav: Bool
    private var closeHit: CGRect = .zero
    private var backHit: CGRect = .zero
    private var fwdHit: CGRect = .zero
    private weak var hosted: NSView?
    private var grip: ResizeGripView?

    init(frame: NSRect, title: String, showNav: Bool = false) {
        self.title = title
        self.showNav = showNav
        switch RetroFrameTheme.key() {
        case "win98": style = .win98
        case "winxp": style = .winxp
        default:      style = .plain
        }
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private var titleH: CGFloat { style == .winxp ? 30 : 22 }
    private var pad: CGFloat { 4 }

    /// Frame for the hosted webview (below the title bar, inside the window border).
    func contentRect() -> NSRect {
        let topOffset = pad + titleH + 2
        return NSRect(x: pad, y: topOffset,
                      width: bounds.width - pad * 2,
                      height: bounds.height - topOffset - pad)
    }

    /// Host the webview and add a bottom-right resize grip on top of it.
    func embed(_ view: NSView) {
        hosted = view
        view.frame = contentRect()
        addSubview(view)
        let g = ResizeGripView(frame: .zero)
        grip = g
        addSubview(g)   // last → stays on top of the webview, so the corner is grabbable
        layoutContents()
    }

    private func layoutContents() {
        hosted?.frame = contentRect()
        let s: CGFloat = 16
        grip?.frame = NSRect(x: bounds.maxX - pad - s, y: bounds.maxY - pad - s, width: s, height: s)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContents()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds
        switch style {
        case .win98: drawWin98(ctx, b)
        case .winxp: drawXP(ctx, b)
        case .plain: drawPlain(ctx, b)
        }
    }

    // ---- Windows 98 (SPEC: #C4C4C4 surface, 4-step bevel, #00007B→#1085D2 caption) ----
    private func drawWin98(_ ctx: CGContext, _ b: NSRect) {
        NSColor(srgbRed: 0.769, green: 0.769, blue: 0.769, alpha: 1).setFill()   // #C4C4C4
        ctx.fill(b)
        // raised window bevel (outer white/black, inner #DBDBDB/#808080)
        func line(_ r: NSRect, _ c: NSColor) { c.setFill(); ctx.fill(r) }
        line(NSRect(x: 0, y: 0, width: b.width, height: 1), .white)
        line(NSRect(x: 0, y: 0, width: 1, height: b.height), .white)
        line(NSRect(x: 0, y: b.height - 1, width: b.width, height: 1), .black)
        line(NSRect(x: b.width - 1, y: 0, width: 1, height: b.height), .black)
        let light = NSColor(srgbRed: 0.859, green: 0.859, blue: 0.859, alpha: 1)  // #DBDBDB
        let shade = NSColor(srgbRed: 0.502, green: 0.502, blue: 0.502, alpha: 1)  // #808080
        line(NSRect(x: 1, y: 1, width: b.width - 2, height: 1), light)
        line(NSRect(x: 1, y: 1, width: 1, height: b.height - 2), light)
        line(NSRect(x: 1, y: b.height - 2, width: b.width - 2, height: 1), shade)
        line(NSRect(x: b.width - 2, y: 1, width: 1, height: b.height - 2), shade)

        // caption: #00007B → #1085D2, left → right
        let cap = NSRect(x: pad, y: pad, width: b.width - pad * 2, height: titleH)
        let grad = NSGradient(starting: NSColor(srgbRed: 0, green: 0, blue: 0.482, alpha: 1),
                              ending: NSColor(srgbRed: 0.063, green: 0.522, blue: 0.824, alpha: 1))
        grad?.draw(in: cap, angle: 0)

        // buttons right: [ _ ][ ▢ ] gap [ × ]  — 20×18, SPEC bevels, crisp glyphs
        let bw: CGFloat = 20, bh: CGFloat = 18
        let by = cap.minY + (titleH - bh) / 2
        let closeR = NSRect(x: cap.maxX - 2 - bw, y: by, width: bw, height: bh)
        let maxR   = NSRect(x: closeR.minX - 3 - bw, y: by, width: bw, height: bh)
        let minR   = NSRect(x: maxR.minX - bw, y: by, width: bw, height: bh)
        for r in [minR, maxR, closeR] { drawW98Button(ctx, r) }
        let dis = shade
        // min glyph (disabled grey)
        line(NSRect(x: minR.minX + 5, y: minR.maxY - 7, width: 8, height: 2), dis)
        // max glyph (disabled grey): box with thick top
        dis.setStroke()
        let mb = NSRect(x: maxR.minX + 5, y: maxR.minY + 4, width: 10, height: 9)
        NSBezierPath(rect: mb).stroke()
        line(NSRect(x: mb.minX, y: mb.minY, width: mb.width, height: 2), dis)
        // close glyph (black ×)
        NSColor.black.setStroke()
        let x = NSBezierPath()
        x.lineWidth = 1.6
        x.move(to: NSPoint(x: closeR.minX + 6, y: closeR.minY + 5))
        x.line(to: NSPoint(x: closeR.maxX - 6, y: closeR.maxY - 5))
        x.move(to: NSPoint(x: closeR.maxX - 6, y: closeR.minY + 5))
        x.line(to: NSPoint(x: closeR.minX + 6, y: closeR.maxY - 5))
        x.stroke()
        closeHit = closeR.insetBy(dx: -3, dy: -3)

        // optional navigation (browser windows): ◀ ▶ raised buttons left in the caption
        var titleX = cap.minX + 6
        backHit = .zero; fwdHit = .zero
        if showNav {
            let backR = NSRect(x: cap.minX + 3, y: by, width: bw, height: bh)
            let fwdR  = NSRect(x: backR.maxX + 2, y: by, width: bw, height: bh)
            for r in [backR, fwdR] { drawW98Button(ctx, r) }
            NSColor.black.setFill()
            func tri(_ r: NSRect, left: Bool) {
                let t = NSBezierPath()
                if left {
                    t.move(to: NSPoint(x: r.minX + 13, y: r.minY + 4))
                    t.line(to: NSPoint(x: r.minX + 13, y: r.maxY - 4))
                    t.line(to: NSPoint(x: r.minX + 6,  y: r.midY))
                } else {
                    t.move(to: NSPoint(x: r.minX + 7, y: r.minY + 4))
                    t.line(to: NSPoint(x: r.minX + 7, y: r.maxY - 4))
                    t.line(to: NSPoint(x: r.minX + 14, y: r.midY))
                }
                t.close(); t.fill()
            }
            tri(backR, left: true); tri(fwdR, left: false)
            backHit = backR.insetBy(dx: -2, dy: -3); fwdHit = fwdR.insetBy(dx: -2, dy: -3)
            titleX = fwdR.maxX + 7
        }

        // title text — bold, white, left
        let font = NSFont(name: "Tahoma-Bold", size: 12) ?? NSFont.boldSystemFont(ofSize: 12)
        (title as NSString).draw(at: NSPoint(x: titleX, y: cap.minY + (titleH - 15) / 2),
                                 withAttributes: [.font: font, .foregroundColor: NSColor.white])
    }

    private func drawW98Button(_ ctx: CGContext, _ r: NSRect) {
        NSColor(srgbRed: 0.769, green: 0.769, blue: 0.769, alpha: 1).setFill(); ctx.fill(r)
        func line(_ rr: NSRect, _ c: NSColor) { c.setFill(); ctx.fill(rr) }
        let light = NSColor(srgbRed: 0.859, green: 0.859, blue: 0.859, alpha: 1)
        let shade = NSColor(srgbRed: 0.502, green: 0.502, blue: 0.502, alpha: 1)
        line(NSRect(x: r.minX, y: r.minY, width: r.width, height: 1), light)
        line(NSRect(x: r.minX, y: r.minY, width: 1, height: r.height), light)
        line(NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1), .black)
        line(NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height), .black)
        line(NSRect(x: r.minX + 1, y: r.minY + 1, width: r.width - 2, height: 1), .white)
        line(NSRect(x: r.minX + 1, y: r.minY + 1, width: 1, height: r.height - 2), .white)
        line(NSRect(x: r.minX + 1, y: r.maxY - 2, width: r.width - 2, height: 1), shade)
        line(NSRect(x: r.maxX - 2, y: r.minY + 1, width: 1, height: r.height - 2), shade)
    }

    // ---- Windows XP (Luna) ----
    private func drawXP(_ ctx: CGContext, _ b: NSRect) {
        // Outer Luna frame — blue, rounded; the white content sits inside a thin border.
        NSColor(srgbRed: 0.012, green: 0.31, blue: 0.78, alpha: 1).setFill()      // #0250C7
        NSBezierPath(roundedRect: b, xRadius: 8, yRadius: 8).fill()

        // Title bar: authentic Luna blue — bright glossy top, dip, slight lift at the bottom.
        let cap = NSRect(x: 0, y: 0, width: b.width, height: titleH)
        let capPath = NSBezierPath(roundedRect: cap, xRadius: 8, yRadius: 8)
        let grad = NSGradient(colorsAndLocations:
            (NSColor(srgbRed: 0.27, green: 0.60, blue: 0.99, alpha: 1), 0.0),     // #459AFD bright top
            (NSColor(srgbRed: 0.11, green: 0.47, blue: 0.96, alpha: 1), 0.08),    // gloss
            (NSColor(srgbRed: 0.04, green: 0.38, blue: 0.93, alpha: 1), 0.42),
            (NSColor(srgbRed: 0.02, green: 0.31, blue: 0.86, alpha: 1), 0.50),    // dip
            (NSColor(srgbRed: 0.06, green: 0.27, blue: 0.83, alpha: 1), 0.55),
            (NSColor(srgbRed: 0.10, green: 0.33, blue: 0.88, alpha: 1), 1.0))     // bottom lift
        grad?.draw(in: capPath, angle: -90)
        // 1px white top highlight + soft gloss over the upper ~40%
        NSColor.white.withAlphaComponent(0.5).setFill()
        ctx.fill(NSRect(x: 8, y: 0, width: b.width - 16, height: 1))
        NSColor.white.withAlphaComponent(0.12).setFill()
        ctx.fill(NSRect(x: 1, y: 1, width: b.width - 2, height: titleH * 0.40))

        // Caption buttons: min/max full blue gel, close red gel — each with a glossy top.
        let bw: CGFloat = 21, bh: CGFloat = 19
        let by = (titleH - bh) / 2
        let closeR = NSRect(x: b.width - 6 - bw, y: by, width: bw, height: bh)
        let maxR   = NSRect(x: closeR.minX - 2 - bw, y: by, width: bw, height: bh)
        let minR   = NSRect(x: maxR.minX - 2 - bw, y: by, width: bw, height: bh)
        func gel(_ r: NSRect, top: NSColor, bottom: NSColor, alpha: CGFloat = 1.0) {
            let p = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
            NSGradient(starting: top.withAlphaComponent(alpha), ending: bottom.withAlphaComponent(alpha))?
                .draw(in: p, angle: -90)
            // glossy highlight over the top ~42%
            let hl = NSBezierPath(roundedRect: NSRect(x: r.minX + 1.5, y: r.minY + 1.5,
                                                      width: r.width - 3, height: r.height * 0.42),
                                  xRadius: 2, yRadius: 2)
            NSColor.white.withAlphaComponent(0.45 * alpha).setFill(); hl.fill()
            NSColor.white.withAlphaComponent(0.55 * alpha).setStroke(); p.stroke()
        }
        let blueTop = NSColor(srgbRed: 0.42, green: 0.66, blue: 0.98, alpha: 1)
        let blueBot = NSColor(srgbRed: 0.07, green: 0.28, blue: 0.74, alpha: 1)
        gel(minR, top: blueTop, bottom: blueBot)
        gel(maxR, top: blueTop, bottom: blueBot)
        gel(closeR, top: NSColor(srgbRed: 0.96, green: 0.55, blue: 0.45, alpha: 1),
                    bottom: NSColor(srgbRed: 0.72, green: 0.13, blue: 0.09, alpha: 1))
        // glyphs (white): min underscore, max square, close ×
        NSColor.white.setFill()
        ctx.fill(NSRect(x: minR.minX + 5, y: minR.maxY - 6, width: bw - 11, height: 2))
        let mb = NSRect(x: maxR.minX + 5, y: maxR.minY + 4, width: bw - 11, height: bh - 9)
        NSColor.white.setStroke()
        let mp = NSBezierPath(rect: mb); mp.lineWidth = 1.5; mp.stroke()
        ctx.fill(NSRect(x: mb.minX, y: mb.minY, width: mb.width, height: 2))
        let x = NSBezierPath(); x.lineWidth = 2
        x.move(to: NSPoint(x: closeR.minX + 6, y: closeR.minY + 5))
        x.line(to: NSPoint(x: closeR.maxX - 6, y: closeR.maxY - 5))
        x.move(to: NSPoint(x: closeR.maxX - 6, y: closeR.minY + 5))
        x.line(to: NSPoint(x: closeR.minX + 6, y: closeR.maxY - 5))
        x.stroke()
        closeHit = closeR.insetBy(dx: -3, dy: -3)

        var titleX: CGFloat = 9
        backHit = .zero; fwdHit = .zero
        if showNav {
            let backR = NSRect(x: 6, y: by, width: bw, height: bh)
            let fwdR  = NSRect(x: backR.maxX + 2, y: by, width: bw, height: bh)
            for r in [backR, fwdR] {
                gel(r, top: NSColor(srgbRed: 0.61, green: 0.85, blue: 0.55, alpha: 1),
                       bottom: NSColor(srgbRed: 0.13, green: 0.55, blue: 0.18, alpha: 1), alpha: 1.0)
            }
            NSColor.white.setFill()
            func tri(_ r: NSRect, left: Bool) {
                let t = NSBezierPath()
                if left {
                    t.move(to: NSPoint(x: r.minX + 14, y: r.minY + 4))
                    t.line(to: NSPoint(x: r.minX + 14, y: r.maxY - 4))
                    t.line(to: NSPoint(x: r.minX + 6,  y: r.midY))
                } else {
                    t.move(to: NSPoint(x: r.minX + 7, y: r.minY + 4))
                    t.line(to: NSPoint(x: r.minX + 7, y: r.maxY - 4))
                    t.line(to: NSPoint(x: r.minX + 15, y: r.midY))
                }
                t.close(); t.fill()
            }
            tri(backR, left: true); tri(fwdR, left: false)
            backHit = backR.insetBy(dx: -2, dy: -3); fwdHit = fwdR.insetBy(dx: -2, dy: -3)
            titleX = fwdR.maxX + 8
        }

        let font = NSFont(name: "Trebuchet MS Bold", size: 13) ?? NSFont.boldSystemFont(ofSize: 13)
        let shadow = NSShadow(); shadow.shadowColor = NSColor(white: 0, alpha: 0.5)
        shadow.shadowOffset = NSSize(width: 1, height: -1)
        (title as NSString).draw(at: NSPoint(x: titleX, y: (titleH - 16) / 2),
                                 withAttributes: [.font: font, .foregroundColor: NSColor.white, .shadow: shadow])
    }

    // ---- Plain fallback ----
    private func drawPlain(_ ctx: CGContext, _ b: NSRect) {
        NSColor(srgbRed: 0.85, green: 0.83, blue: 0.75, alpha: 1).setFill(); ctx.fill(b)
        let cap = NSRect(x: pad, y: pad, width: b.width - pad * 2, height: titleH)
        NSColor(srgbRed: 0.98, green: 0.85, blue: 0.36, alpha: 1).setFill(); ctx.fill(cap)
        NSColor.black.setStroke(); NSBezierPath(rect: cap).stroke()
        let closeR = NSRect(x: cap.minX + 5, y: cap.minY + 4, width: 14, height: 14)
        NSColor(srgbRed: 0.92, green: 0.73, blue: 0.16, alpha: 1).setFill(); ctx.fill(closeR)
        NSColor.black.setStroke(); NSBezierPath(rect: closeR).stroke()
        closeHit = closeR.insetBy(dx: -3, dy: -3)
        (title as NSString).draw(at: NSPoint(x: closeR.maxX + 6, y: cap.minY + 3),
                                 withAttributes: [.font: NSFont.boldSystemFont(ofSize: 12),
                                                  .foregroundColor: NSColor.black])
    }

    // ---- Interaction: close button or drag ----
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if closeHit.contains(p) { onClose?(); return }
        if backHit.contains(p) { onBack?(); return }
        if fwdHit.contains(p) { onForward?(); return }
        if p.y <= pad + titleH + 2 { window?.performDrag(with: event) }
    }
}

/// Bottom-right corner grip that resizes the borderless window (Notepad/Paint/IE et al.).
final class ResizeGripView: NSView {
    private var startMouse: NSPoint = .zero
    private var startFrame: NSRect = .zero

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // three subtle diagonal hatch lines, like a classic resize gripper
        NSColor(white: 0, alpha: 0.28).setStroke()
        let p = NSBezierPath(); p.lineWidth = 1
        for o in [CGFloat(3), 7, 11] {
            p.move(to: NSPoint(x: bounds.maxX - o, y: bounds.maxY - 1))
            p.line(to: NSPoint(x: bounds.maxX - 1, y: bounds.maxY - o))
        }
        p.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let win = window else { return }
        startMouse = NSEvent.mouseLocation
        startFrame = win.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let win = window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - startMouse.x
        let dy = now.y - startMouse.y                 // screen y grows upward
        var newW = startFrame.width + dx
        var newH = startFrame.height - dy             // drag down (dy<0) → taller
        newW = max(win.minSize.width, newW)
        newH = max(win.minSize.height, newH)
        let top = startFrame.maxY                      // keep the title bar anchored
        win.setFrame(NSRect(x: startFrame.minX, y: top - newH, width: newW, height: newH),
                     display: true, animate: false)
    }
}
