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

    /// True only for a trusted 98.js APP URL — this gates the native Save/Print bridge,
    /// so each host is path-scoped to where its apps actually live (pisaucer serves them
    /// under /programs/, the legacy github.io mirror under /98.js/). Unrelated content
    /// later hosted elsewhere on the same domain does NOT inherit the bridge.
    static func isTrusted98App(_ urlString: String) -> Bool {
        guard let c = URLComponents(string: urlString), c.scheme == "https" else { return false }
        if c.host == "bored-win98.pisaucer.com" && c.path.hasPrefix("/programs/") { return true }
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
    private var preZoomFrame: NSRect?

    /// System 6 zoom box: toggle the window between its size and (near-)full screen.
    private func toggleZoom() {
        guard let p = panel, let screen = p.screen ?? NSScreen.main else { return }
        if let f = preZoomFrame {
            p.setFrame(f, display: true, animate: true); preZoomFrame = nil
        } else {
            preZoomFrame = p.frame
            p.setFrame(screen.visibleFrame.insetBy(dx: 24, dy: 24), display: true, animate: true)
        }
    }
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
        chrome.onZoom = { [weak self] in self?.toggleZoom() }

        let p = WebAppPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        p.level = .normal
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.hidesOnDeactivate = false
        p.minSize = NSSize(width: 360, height: 240)            // resizable, with a floor
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // Windows 7: real Aero glass. Put an NSVisualEffectView (behindWindow) behind the chrome
        // so the live desktop is blurred through the translucent title bar + frame; the chrome
        // draws its tints semi-transparently (see drawWin7). Other themes keep the opaque chrome.
        if RetroFrameTheme.key() == "win7" {
            let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
            container.autoresizesSubviews = true
            let glass = NSVisualEffectView(frame: container.bounds)
            glass.autoresizingMask = [.width, .height]
            glass.blendingMode = .behindWindow
            glass.material = .fullScreenUI
            glass.state = .active
            glass.appearance = NSAppearance(named: .aqua)   // stay light glass even in Dark Mode
            glass.wantsLayer = true
            glass.layer?.cornerRadius = 6
            glass.layer?.masksToBounds = true
            chrome.frame = container.bounds
            chrome.autoresizingMask = [.width, .height]
            container.addSubview(glass)
            container.addSubview(chrome)
            p.contentView = container
        } else {
            p.contentView = chrome
        }
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
        // Bridge-equipped (trusted 98.js) windows must STAY on the trusted PATH — the
        // bridge grant is path-scoped (/98.js/), so a same-host navigation to another
        // path must not inherit the native Save/Print bridge either.
        if bridgeActive,
           navigationAction.targetFrame?.isMainFrame == true,
           let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
           !Self.isTrusted98App(url.absoluteString) {
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

    enum Style { case win98, winxp, win7, macClassic, system6, nextstep, futurama, plain }

    var onClose: (() -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onZoom: (() -> Void)?
    private let title: String
    private let style: Style
    private let showNav: Bool
    private var closeHit: CGRect = .zero
    private var backHit: CGRect = .zero
    private var fwdHit: CGRect = .zero
    private weak var hosted: NSView?
    private var grip: ResizeGripView?

    /// Shared chrome model + interaction tracker. Non-nil only for styles migrated to the
    /// model (currently XP); other styles keep the legacy `closeHit` path.
    private let chromeStyle: ChromeStyle?
    private var tracker = ChromeButtonTracker()

    init(frame: NSRect, title: String, showNav: Bool = false) {
        self.title = title
        self.showNav = showNav
        switch RetroFrameTheme.key() {
        case "win98":  style = .win98;      chromeStyle = ChromeStyleFactory.win98()
        case "winxp":  style = .winxp;      chromeStyle = ChromeStyleFactory.xp()
        case "win7":   style = .win7;       chromeStyle = ChromeStyleFactory.win7()
        case "macos9": style = .macClassic; chromeStyle = ChromeStyleFactory.macClassic()
        case "macos6": style = .system6;    chromeStyle = ChromeStyleFactory.system6()
        case "nextstep": style = .nextstep; chromeStyle = ChromeStyleFactory.nextstep()
        case "futurama": style = .futurama; chromeStyle = nil
        default:       style = .plain;      chromeStyle = nil
        }
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private var titleH: CGFloat {
        switch style { case .winxp, .win7: return 30; case .system6: return 20; case .nextstep: return 22; case .futurama: return 26; default: return 22 }
    }
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
        case .win98:      drawWin98(ctx, b)
        case .winxp:      drawXP(ctx, b)
        case .win7:       drawWin7(ctx, b)
        case .macClassic: drawMacClassic(ctx, b)
        case .system6:    drawSystem6(ctx, b)
        case .nextstep:   drawNextstep(ctx, b)
        case .futurama:   drawFuturama(ctx, b)
        case .plain:      drawPlain(ctx, b)
        }
    }

    // ---- Futurama: cream body, sage-green rounded title bar, macOS traffic lights LEFT,
    //      centered dark title (as in the FuturamaOS mockup) ----
    private func drawFuturama(_ ctx: CGContext, _ b: NSRect) {
        let cream = NSColor(srgbRed: 0.95, green: 0.93, blue: 0.86, alpha: 1)
        let sageTop = NSColor(srgbRed: 0.72, green: 0.82, blue: 0.74, alpha: 1)
        let sageBot = NSColor(srgbRed: 0.62, green: 0.74, blue: 0.67, alpha: 1)
        let edge = NSColor(srgbRed: 0.40, green: 0.52, blue: 0.46, alpha: 1)
        // Window body + a soft rounded outer frame.
        let frame = NSBezierPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        cream.setFill(); frame.fill()
        // Title bar (rounded top only).
        let bar = NSRect(x: 1, y: 1, width: b.width - 2, height: titleH)
        ctx.saveGState()
        let clip = NSBezierPath(); let r: CGFloat = 9
        clip.move(to: NSPoint(x: bar.minX, y: bar.maxY))
        clip.line(to: NSPoint(x: bar.minX, y: bar.minY + r))
        clip.appendArc(withCenter: NSPoint(x: bar.minX + r, y: bar.minY + r), radius: r, startAngle: 180, endAngle: 270)
        clip.line(to: NSPoint(x: bar.maxX - r, y: bar.minY))
        clip.appendArc(withCenter: NSPoint(x: bar.maxX - r, y: bar.minY + r), radius: r, startAngle: 270, endAngle: 360)
        clip.line(to: NSPoint(x: bar.maxX, y: bar.maxY))
        clip.close(); clip.addClip()
        NSGradient(colors: [sageTop, sageBot])!.draw(in: bar, angle: 90)
        ctx.restoreGState()
        edge.withAlphaComponent(0.6).setStroke()
        let sep = NSBezierPath(); sep.move(to: NSPoint(x: bar.minX, y: bar.maxY)); sep.line(to: NSPoint(x: bar.maxX, y: bar.maxY)); sep.lineWidth = 1; sep.stroke()
        frame.lineWidth = 1; edge.withAlphaComponent(0.5).setStroke(); frame.stroke()

        // Traffic lights on the LEFT (close red / min yellow / zoom green), dark outline.
        let d: CGFloat = 12, gap: CGFloat = 8, ly = bar.midY - d/2
        let lights: [(NSColor, CGFloat)] = [
            (NSColor(srgbRed: 0.94, green: 0.33, blue: 0.31, alpha: 1), bar.minX + 12),
            (NSColor(srgbRed: 0.96, green: 0.74, blue: 0.22, alpha: 1), bar.minX + 12 + d + gap),
            (NSColor(srgbRed: 0.36, green: 0.78, blue: 0.36, alpha: 1), bar.minX + 12 + 2*(d + gap))]
        for (col, lx) in lights {
            let dot = NSRect(x: lx, y: ly, width: d, height: d)
            col.setFill(); NSBezierPath(ovalIn: dot).fill()
            NSColor.black.withAlphaComponent(0.35).setStroke()
            let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5)); ring.lineWidth = 1; ring.stroke()
        }
        let closeR = NSRect(x: bar.minX + 12, y: ly, width: d, height: d)
        tracker.reset()
        tracker.add(.close, closeR.insetBy(dx: -4, dy: -4), interactive: true)
        closeHit = .zero

        // Centered title.
        let p = NSMutableParagraphStyle(); p.alignment = .center; p.lineBreakMode = .byTruncatingTail
        let font = NSFont(name: "Helvetica-Bold", size: 13) ?? .boldSystemFont(ofSize: 13)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 0.12, alpha: 1), .paragraphStyle: p]
        let ts = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(in: NSRect(x: bar.minX + 90, y: bar.midY - ts.height/2, width: bar.width - 180, height: ts.height), withAttributes: attrs)
    }

    // ---- NeXTSTEP: chiseled grey window, black title bar, miniaturize LEFT + close RIGHT ----
    private func drawNextstep(_ ctx: CGContext, _ b: NSRect) {
        // Body (grey face) + the 2px chiseled window frame (white TL / dark BR).
        NeXTChrome.face.setFill(); ctx.fill(b)
        NeXTChrome.bevel(b, raised: true, width: 2, flipped: true, in: ctx)

        // Title bar across the top (flipped: y=0 is the top). A desktop widget is always "key".
        let bar = NSRect(x: 2, y: 2, width: b.width - 4, height: titleH)
        NeXTChrome.titleBar(bar, title: title, state: .key, in: ctx)

        // Buttons: miniaturize top-LEFT (decorative on a web/widget window), close top-RIGHT.
        let s: CGFloat = 16
        let by = bar.midY - s/2
        let miniR  = NSRect(x: bar.minX + 3, y: by, width: s, height: s)
        let closeR = NSRect(x: bar.maxX - 3 - s, y: by, width: s, height: s)
        tracker.reset()
        tracker.add(.minimize, miniR.insetBy(dx: -3, dy: -3), interactive: false)
        tracker.add(.close, closeR.insetBy(dx: -3, dy: -3), interactive: true)
        NeXTChrome.button(miniR, kind: .miniaturize, flipped: true, in: ctx)
        NeXTChrome.button(closeR, kind: .close, pressed: tracker.state(for: .close) == .pressed, flipped: true, in: ctx)
        closeHit = .zero   // close handled via `tracker`
    }

    // ---- Mac System 6 (authentic 1-bit B/W) — shared with the TV window via System6Chrome ----
    private func drawSystem6(_ ctx: CGContext, _ b: NSRect) {
        let cs = chromeStyle ?? ChromeStyleFactory.system6()
        NSColor.white.setFill(); ctx.fill(b)                        // white body
        let bar = NSRect(x: 0, y: 0, width: b.width, height: titleH)   // flipped: title bar at top
        System6Chrome.titleBar(bar, active: true)                   // racing stripes
        // 1px black separator under the title bar + the window frame
        System6Chrome.black.setFill(); ctx.fill(NSRect(x: 0, y: bar.maxY, width: b.width, height: 1))
        System6Chrome.windowFrame(b)
        // close box alone on the LEFT; no zoom/collapse in System 6
        let boxS = System6Chrome.boxSize
        let boxY = (titleH - boxS) / 2
        let closeR = NSRect(x: cs.buttonInset, y: boxY, width: boxS, height: boxS)
        let zoomR  = NSRect(x: b.width - cs.buttonInset - boxS, y: boxY, width: boxS, height: boxS)
        tracker.reset()
        tracker.add(.close, closeR.insetBy(dx: -3, dy: -3), interactive: true)
        tracker.add(.zoom, zoomR.insetBy(dx: -3, dy: -3), interactive: true)
        System6Chrome.closeBox(closeR, state: tracker.state(for: .close))
        System6Chrome.resizeBox(zoomR, state: tracker.state(for: .zoom))
        System6Chrome.titlePlaque(title, bar: bar, font: cs.titleFont, active: true)
        closeHit = .zero   // close is tracked via `tracker`
    }

    // ---- Classic Mac (System 6 / Platinum) — shared look with the TV window via ClassicMacChrome ----
    private func drawMacClassic(_ ctx: CGContext, _ b: NSRect) {
        let cs = chromeStyle ?? ChromeStyleFactory.macClassic()
        NSColor.white.setFill(); ctx.fill(b)                       // window body
        let bar = NSRect(x: 0, y: 0, width: b.width, height: titleH)   // flipped: title bar at top
        ClassicMacChrome.face.setFill(); ctx.fill(bar)
        ClassicMacChrome.pinstripes(in: bar)
        NSColor.black.setStroke(); NSBezierPath(rect: b.insetBy(dx: 0.5, dy: 0.5)).stroke()  // 1px frame
        // light-purple shadow line on the content-facing edge of the bar
        ClassicMacChrome.botShadow.setFill(); ctx.fill(NSRect(x: 0, y: bar.maxY, width: b.width, height: 1))

        // control boxes: close LEFT (functional), collapse + zoom RIGHT (decorative on a web window)
        let boxS = ClassicMacChrome.boxSize
        let boxY = (titleH - boxS) / 2
        let closeR    = NSRect(x: cs.buttonInset, y: boxY, width: boxS, height: boxS)
        let zoomR     = NSRect(x: b.width - 7 - boxS, y: boxY, width: boxS, height: boxS)
        let collapseR = NSRect(x: zoomR.minX - cs.buttonSpacing - boxS, y: boxY, width: boxS, height: boxS)
        tracker.reset()
        tracker.add(.close, closeR.insetBy(dx: -4, dy: -4), interactive: true)
        tracker.add(.collapse, collapseR, interactive: false)
        tracker.add(.zoom, zoomR, interactive: false)
        ClassicMacChrome.bevelBox(closeR, state: tracker.state(for: .close))
        ClassicMacChrome.bevelBox(collapseR, state: .normal)
        ClassicMacChrome.bevelBox(zoomR, state: .normal)
        ClassicMacChrome.zoomGlyph(in: zoomR)
        ClassicMacChrome.collapseGlyph(in: collapseR)
        ClassicMacChrome.titlePlaque(title, bar: bar, font: cs.titleFont)
        closeHit = .zero   // close is tracked via `tracker`
    }

    // ---- Windows 98 (SPEC: #C4C4C4 surface, 4-step bevel, #00007B→#1085D2 caption) ----
    private func drawWin98(_ ctx: CGContext, _ b: NSRect) {
        let cs = chromeStyle ?? ChromeStyleFactory.win98()
        let hi = cs.bevelHilight ?? .white
        let lo = cs.bevelDkShadow ?? .black
        let light = cs.bevelLight ?? NSColor(srgbRed: 0.859, green: 0.859, blue: 0.859, alpha: 1)  // #DBDBDB
        let shade = cs.bevelShadow ?? NSColor(srgbRed: 0.502, green: 0.502, blue: 0.502, alpha: 1) // #808080
        cs.windowFill.setFill()   // ButtonFace (#C4C4C4 default)
        ctx.fill(b)
        // raised window bevel (outer hilight/dkShadow, inner light/shadow)
        func line(_ r: NSRect, _ c: NSColor) { c.setFill(); ctx.fill(r) }
        line(NSRect(x: 0, y: 0, width: b.width, height: 1), hi)
        line(NSRect(x: 0, y: 0, width: 1, height: b.height), hi)
        line(NSRect(x: 0, y: b.height - 1, width: b.width, height: 1), lo)
        line(NSRect(x: b.width - 1, y: 0, width: 1, height: b.height), lo)
        line(NSRect(x: 1, y: 1, width: b.width - 2, height: 1), light)
        line(NSRect(x: 1, y: 1, width: 1, height: b.height - 2), light)
        line(NSRect(x: 1, y: b.height - 2, width: b.width - 2, height: 1), shade)
        line(NSRect(x: b.width - 2, y: 1, width: 1, height: b.height - 2), shade)

        // caption: active-title gradient (scheme, or built-in navy), left → right
        let cap = NSRect(x: pad, y: pad, width: b.width - pad * 2, height: titleH)
        cs.captionGradient?.draw(in: cap)

        // Caption button: only Close — a fixed web-app window has no working min/max, so no
        // dead grey placeholders (98.css likewise only styles real controls).
        let bw: CGFloat = 20, bh: CGFloat = 18
        let by = cap.minY + (titleH - bh) / 2
        let closeR = NSRect(x: cap.maxX - 2 - bw, y: by, width: bw, height: bh)
        tracker.reset()
        tracker.add(.close, closeR, interactive: true)
        let sClose = tracker.state(for: .close)
        drawW98Button(ctx, closeR, state: sClose)
        // close glyph (black ×) — nudged 1px down-right while pressed
        let o: CGFloat = (sClose == .pressed) ? 1 : 0
        NSColor.black.setStroke()
        let x = NSBezierPath()
        x.lineWidth = 1.6
        x.move(to: NSPoint(x: closeR.minX + 6 + o, y: closeR.minY + 5 + o))
        x.line(to: NSPoint(x: closeR.maxX - 6 + o, y: closeR.maxY - 5 + o))
        x.move(to: NSPoint(x: closeR.maxX - 6 + o, y: closeR.minY + 5 + o))
        x.line(to: NSPoint(x: closeR.minX + 6 + o, y: closeR.maxY - 5 + o))
        x.stroke()
        closeHit = .zero   // Win98 close is tracked via `tracker`, not the legacy hit rect

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

        // title text — bold, scheme title colour (white default), left
        let font = NSFont(name: "Tahoma-Bold", size: 12) ?? NSFont.boldSystemFont(ofSize: 12)
        (title as NSString).draw(at: NSPoint(x: titleX, y: cap.minY + (titleH - 15) / 2),
                                 withAttributes: [.font: font, .foregroundColor: cs.titleColor])
    }

    private func drawW98Button(_ ctx: CGContext, _ r: NSRect, state: ChromeButtonState = .normal) {
        let cs = chromeStyle ?? ChromeStyleFactory.win98()
        let hi = cs.bevelHilight ?? .white
        let lo = cs.bevelDkShadow ?? .black
        let light = cs.bevelLight ?? NSColor(srgbRed: 0.859, green: 0.859, blue: 0.859, alpha: 1)
        let shade = cs.bevelShadow ?? NSColor(srgbRed: 0.502, green: 0.502, blue: 0.502, alpha: 1)
        var faceCol = cs.windowFill
        if state == .hovered { faceCol = faceCol.blended(withFraction: 0.08, of: .white) ?? faceCol }
        faceCol.setFill(); ctx.fill(r)
        func line(_ rr: NSRect, _ c: NSColor) { c.setFill(); ctx.fill(rr) }
        if state == .pressed {
            // Sunken bevel (inverted): dark top-left, light bottom-right.
            line(NSRect(x: r.minX, y: r.minY, width: r.width, height: 1), shade)
            line(NSRect(x: r.minX, y: r.minY, width: 1, height: r.height), shade)
            line(NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1), hi)
            line(NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height), hi)
            line(NSRect(x: r.minX + 1, y: r.minY + 1, width: r.width - 2, height: 1), lo)
            line(NSRect(x: r.minX + 1, y: r.minY + 1, width: 1, height: r.height - 2), lo)
        } else {
            // Raised bevel (outer hilight/dkShadow, inner light/shade).
            line(NSRect(x: r.minX, y: r.minY, width: r.width, height: 1), light)
            line(NSRect(x: r.minX, y: r.minY, width: 1, height: r.height), light)
            line(NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1), lo)
            line(NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height), lo)
            line(NSRect(x: r.minX + 1, y: r.minY + 1, width: r.width - 2, height: 1), hi)
            line(NSRect(x: r.minX + 1, y: r.minY + 1, width: 1, height: r.height - 2), hi)
            line(NSRect(x: r.minX + 1, y: r.maxY - 2, width: r.width - 2, height: 1), shade)
            line(NSRect(x: r.maxX - 2, y: r.minY + 1, width: 1, height: r.height - 2), shade)
        }
    }

    // ---- Windows XP (Luna) ----
    private func drawXP(_ ctx: CGContext, _ b: NSRect) {
        // Outer Luna frame — blue, rounded. Matches the title-bar's bottom gradient stop so the
        // border flows out of the title bar with no visible seam ("aus einem Guss").
        NSColor(srgbRed: 0.10, green: 0.33, blue: 0.88, alpha: 1).setFill()
        NSBezierPath(roundedRect: b, xRadius: 8, yRadius: 8).fill()

        // Title bar: authentic Luna blue, CLIPPED to the window's rounded shape so its top
        // corners round with the frame but its bottom edge stays FLAT — a seamless transition
        // into the content (like the Notepad widget), with no domed "stuck-on" bulge.
        let cap = NSRect(x: 0, y: 0, width: b.width, height: titleH)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: b, xRadius: 8, yRadius: 8).addClip()
        let grad = NSGradient(colorsAndLocations:
            (NSColor(srgbRed: 0.27, green: 0.60, blue: 0.99, alpha: 1), 0.0),     // #459AFD bright top
            (NSColor(srgbRed: 0.11, green: 0.47, blue: 0.96, alpha: 1), 0.08),    // gloss
            (NSColor(srgbRed: 0.04, green: 0.38, blue: 0.93, alpha: 1), 0.42),
            (NSColor(srgbRed: 0.02, green: 0.31, blue: 0.86, alpha: 1), 0.50),    // dip
            (NSColor(srgbRed: 0.06, green: 0.27, blue: 0.83, alpha: 1), 0.55),
            (NSColor(srgbRed: 0.10, green: 0.33, blue: 0.88, alpha: 1), 1.0))     // flows into the frame blue
        grad?.draw(in: cap, angle: -90)
        // Subtle 1px top highlight only — no heavy gloss dome.
        NSColor.white.withAlphaComponent(0.45).setFill()
        ctx.fill(NSRect(x: 8, y: 0, width: b.width - 16, height: 1))
        NSColor.white.withAlphaComponent(0.08).setFill()
        ctx.fill(NSRect(x: 1, y: 1, width: b.width - 2, height: titleH * 0.32))
        NSGraphicsContext.restoreGraphicsState()

        // Caption buttons via ChromeStyle + tracker. Close is interactive (hover/press);
        // min/max are decorative on a fixed-size window → drawn muted, no hit region, so they
        // no longer read as clickable.
        let cs = chromeStyle ?? ChromeStyleFactory.xp()
        let bw = cs.buttonSize.width, bh = cs.buttonSize.height
        let by = (titleH - bh) / 2
        let closeR = NSRect(x: b.width - cs.buttonInset - bw, y: by, width: bw, height: bh)
        tracker.reset()
        tracker.add(.close, closeR, interactive: true)
        let sClose = tracker.state(for: .close)

        // Neutral srgb tints (same colorspace as the button colors → blend never fails).
        let W = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let K = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let Gy = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        func gel(_ r: NSRect, top: NSColor, bottom: NSColor, state: ChromeButtonState) {
            var t = top, bot = bottom, gloss: CGFloat = 0.45, edge: CGFloat = 0.55
            switch state {
            case .hovered:  t = top.blended(withFraction: 0.20, of: W) ?? top
                            bot = bottom.blended(withFraction: 0.12, of: W) ?? bottom; gloss = 0.60
            case .pressed:  t = top.blended(withFraction: 0.30, of: K) ?? top
                            bot = bottom.blended(withFraction: 0.24, of: K) ?? bottom
                            gloss = 0.12; edge = 0.35
            case .disabled: t = top.blended(withFraction: 0.55, of: Gy) ?? top
                            bot = bottom.blended(withFraction: 0.55, of: Gy) ?? bottom
                            gloss = 0.22; edge = 0.35
            case .normal:   break
            }
            let p = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
            NSGradient(starting: t, ending: bot)?.draw(in: p, angle: -90)
            let hl = NSBezierPath(roundedRect: NSRect(x: r.minX + 1.5, y: r.minY + 1.5,
                                                      width: r.width - 3, height: r.height * 0.42),
                                  xRadius: 2, yRadius: 2)
            NSColor.white.withAlphaComponent(gloss).setFill(); hl.fill()
            // Subtle dark-blue outline (not white) — a white rim reads as a stuck-on border.
            NSColor(srgbRed: 0.03, green: 0.13, blue: 0.42, alpha: 0.55).setStroke(); p.stroke()
            _ = edge
        }
        let redTop  = NSColor(srgbRed: 0.96, green: 0.55, blue: 0.45, alpha: 1)
        let redBot  = NSColor(srgbRed: 0.72, green: 0.13, blue: 0.09, alpha: 1)
        // Smooth red gel Close button (matches the TV XP chrome; no min/max on a web-app window).
        gel(closeR, top: redTop, bottom: redBot, state: sClose)
        NSColor.white.setStroke()
        let x = NSBezierPath(); x.lineWidth = 2
        x.move(to: NSPoint(x: closeR.minX + 6, y: closeR.minY + 5))
        x.line(to: NSPoint(x: closeR.maxX - 6, y: closeR.maxY - 5))
        x.move(to: NSPoint(x: closeR.maxX - 6, y: closeR.minY + 5))
        x.line(to: NSPoint(x: closeR.minX + 6, y: closeR.maxY - 5))
        x.stroke()
        closeHit = .zero   // XP close is tracked via `tracker`, not the legacy hit rect

        var titleX: CGFloat = 9
        backHit = .zero; fwdHit = .zero
        if showNav {
            let backR = NSRect(x: 6, y: by, width: bw, height: bh)
            let fwdR  = NSRect(x: backR.maxX + 2, y: by, width: bw, height: bh)
            for r in [backR, fwdR] {
                gel(r, top: NSColor(srgbRed: 0.61, green: 0.85, blue: 0.55, alpha: 1),
                       bottom: NSColor(srgbRed: 0.13, green: 0.55, blue: 0.18, alpha: 1), state: .normal)
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

    // ---- Windows 7 (Aero glass; 7.css recipe, MIT © Khang Nguyen Duy) ----
    private func drawWin7(_ ctx: CGContext, _ b: NSRect) {
        let cs = chromeStyle ?? ChromeStyleFactory.win7()
        let radius = cs.cornerRadius   // 6

        // REAL Aero glass: an NSVisualEffectView (behindWindow) sits behind this transparent
        // view and blurs the live desktop. We therefore paint only SEMI-TRANSPARENT tints so the
        // blur shows through — no opaque frame fill (see the win7 branch in WebAppController).
        let framePath = NSBezierPath(roundedRect: b, xRadius: radius, yRadius: radius)

        // Title-bar + thin frame border are glass, clipped to the rounded window.
        let cap = NSRect(x: 0, y: 0, width: b.width, height: titleH)
        NSGraphicsContext.saveGraphicsState()
        framePath.addClip()
        // faint blue frost over the whole glass frame, stronger on the title bar
        NSColor(srgbRed: 0.271, green: 0.502, blue: 0.769, alpha: 0.16).setFill()
        framePath.fill()
        NSColor(srgbRed: 0.271, green: 0.502, blue: 0.769, alpha: 0.28).setFill()
        ctx.fill(cap)
        cs.captionGradient?.draw(in: cap)   // left→right white/dark/white sheen
        // top highlight band: transparent → white → transparent
        NSGradient(colorsAndLocations:
            (NSColor.white.withAlphaComponent(0.0), 0.0),
            (NSColor.white.withAlphaComponent(0.55), 0.5),
            (NSColor.white.withAlphaComponent(0.0), 1.0))?
            .draw(in: NSRect(x: 0, y: titleH * 0.18, width: b.width, height: titleH * 0.24), angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // Content body — OPAQUE #f0f0f0 (the webview covers it); a `pad` glass border stays
        // translucent around it so the frame reads as Aero glass.
        let body = NSRect(x: pad, y: titleH, width: b.width - pad * 2, height: b.height - titleH - pad)
        NSColor(srgbRed: 0.941, green: 0.941, blue: 0.941, alpha: 1).setFill()
        ctx.fill(body)

        // White inner glow (box-shadow inset 0 0 0 1px #fffa) + 1px dark frame edge.
        NSColor.white.withAlphaComponent(0.66).setStroke()
        let inner = NSBezierPath(roundedRect: b.insetBy(dx: 1, dy: 1),
                                 xRadius: radius - 1, yRadius: radius - 1)
        inner.lineWidth = 1; inner.stroke()
        NSColor.black.withAlphaComponent(0.55).setStroke()
        let edge = NSBezierPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        edge.lineWidth = 1; edge.stroke()

        // Caption cluster: [min][max][close]. Close is red + interactive; on a fixed web-app
        // window min/max are decorative (muted glass, no hit region) — same choice as XP.
        let bw = cs.buttonSize.width, bh = cs.buttonSize.height
        let by: CGFloat = 0
        let closeR = NSRect(x: b.width - cs.buttonInset - bw, y: by, width: bw, height: bh)
        let maxR   = NSRect(x: closeR.minX - bw, y: by, width: bw, height: bh)
        let minR   = NSRect(x: maxR.minX - bw, y: by, width: bw, height: bh)
        tracker.reset()
        tracker.add(.close, closeR, interactive: true)
        let sClose = tracker.state(for: .close)

        let cluster = NSRect(x: minR.minX, y: by, width: closeR.maxX - minR.minX, height: bh)
        let clusterPath = NSBezierPath(roundedRect: cluster, xRadius: 4, yRadius: 4)
        NSGraphicsContext.saveGraphicsState()
        clusterPath.addClip()
        // min + max: translucent glass (`--w7-wct-bg`); close: red (`--w7-wct_close-bg`)
        win7GlassFill(NSRect(x: minR.minX, y: by, width: maxR.maxX - minR.minX, height: bh))
        win7CloseFill(closeR, state: sClose)
        NSGraphicsContext.restoreGraphicsState()
        // dividers + cluster border
        NSColor.black.withAlphaComponent(0.28).setFill()
        ctx.fill(NSRect(x: maxR.minX, y: by + 1, width: 1, height: bh - 2))
        ctx.fill(NSRect(x: closeR.minX, y: by + 1, width: 1, height: bh - 2))
        NSColor.black.withAlphaComponent(0.30).setStroke(); clusterPath.lineWidth = 1; clusterPath.stroke()

        // Glyphs
        win7Glyph(.minimize, in: minR, color: NSColor.black.withAlphaComponent(0.72))
        win7Glyph(.maximize, in: maxR, color: NSColor.black.withAlphaComponent(0.72))
        win7Glyph(.close, in: closeR, color: .white)
        closeHit = .zero   // Win7 close is tracked via `tracker`
        backHit = .zero; fwdHit = .zero

        // Title text: black with a white glow halo for legibility on glass.
        let glow = NSShadow(); glow.shadowColor = NSColor.white.withAlphaComponent(0.95)
        glow.shadowOffset = .zero; glow.shadowBlurRadius = 4
        (title as NSString).draw(at: NSPoint(x: 10, y: (titleH - 16) / 2),
                                 withAttributes: [.font: cs.titleFont,
                                                  .foregroundColor: NSColor.black, .shadow: glow])
    }

    /// Aero caption glass (`--w7-wct-bg`): translucent white top, dark mid-band, white bottom.
    private func win7GlassFill(_ r: NSRect) {
        let W = { (a: CGFloat) in NSColor(srgbRed: 1, green: 1, blue: 1, alpha: a) }
        let K = { (a: CGFloat) in NSColor(srgbRed: 0, green: 0, blue: 0, alpha: a) }
        NSGradient(colorsAndLocations:
            (W(0.50), 0.0), (W(0.30), 0.45),
            (K(0.10), 0.50), (K(0.10), 0.75), (W(0.50), 1.0))?
            .draw(in: r, angle: -90)
    }

    /// Aero red Close button (`--w7-wct_close-bg`), brighter with an inner glow on hover.
    private func win7CloseFill(_ r: NSRect, state: ChromeButtonState) {
        func c(_ hex: (CGFloat, CGFloat, CGFloat), _ a: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: hex.0, green: hex.1, blue: hex.2, alpha: a)
        }
        var top = c((0.878, 0.631, 0.592))    // #E0A197
        var mid = c((0.812, 0.475, 0.416))    // #CF796A
        var bot = c((0.835, 0.310, 0.212))    // #D54F36
        switch state {
        case .hovered: top = c((0.98, 0.72, 0.66)); mid = c((0.90, 0.42, 0.34)); bot = c((0.92, 0.28, 0.16))
        case .pressed: top = c((0.72, 0.34, 0.28)); mid = c((0.64, 0.20, 0.14)); bot = c((0.58, 0.12, 0.08))
        default: break
        }
        NSGradient(colorsAndLocations: (top, 0.0), (mid, 0.25), (mid, 0.5), (bot, 0.5), (bot, 1.0))?
            .draw(in: r, angle: -90)
        if state == .hovered {   // cyan-tinged inner glow along the bottom, like Aero
            NSColor.white.withAlphaComponent(0.22).setFill()
            NSBezierPath(rect: NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.4)).fill()
        }
    }

    /// Native Aero caption glyphs (minimize `_`, maximize `▢`, close `✕`).
    private func win7Glyph(_ kind: ChromeButtonKind, in r: NSRect, color: NSColor) {
        color.setStroke(); color.setFill()
        switch kind {
        case .minimize:
            NSBezierPath(rect: NSRect(x: r.midX - 4, y: r.midY + 3, width: 8, height: 2)).fill()
        case .maximize:
            let sq = NSRect(x: r.midX - 5, y: r.midY - 4, width: 10, height: 8)
            let p = NSBezierPath(rect: sq); p.lineWidth = 1; p.stroke()
            NSBezierPath(rect: NSRect(x: sq.minX, y: sq.minY, width: sq.width, height: 2)).fill()  // title cap
        case .close:
            let x = NSBezierPath(); x.lineWidth = 2
            x.move(to: NSPoint(x: r.midX - 4, y: r.midY - 4)); x.line(to: NSPoint(x: r.midX + 4, y: r.midY + 4))
            x.move(to: NSPoint(x: r.midX + 4, y: r.midY - 4)); x.line(to: NSPoint(x: r.midX - 4, y: r.midY + 4))
            x.stroke()
        default: break
        }
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

    // ---- Interaction: caption buttons (tracked, fire on mouse-up-inside) or window drag ----
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard chromeStyle != nil else { return }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        guard chromeStyle != nil else { return }
        if tracker.mouseMoved(to: convert(event.locationInWindow, from: nil)) { needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        if tracker.mouseExited() { needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if chromeStyle != nil {
            // A tracked caption button: press it (visual only); it fires on mouse-up-inside.
            if tracker.hitTest(p) != nil {
                if tracker.mouseDown(at: p) { needsDisplay = true }
                return
            }
        } else if closeHit.contains(p) {
            onClose?(); return
        }
        if backHit.contains(p) { onBack?(); return }
        if fwdHit.contains(p) { onForward?(); return }
        if p.y <= pad + titleH + 2 { window?.performDrag(with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard chromeStyle != nil else { return }
        if tracker.mouseDragged(to: convert(event.locationInWindow, from: nil)) { needsDisplay = true }
    }

    override func mouseUp(with event: NSEvent) {
        guard chromeStyle != nil else { return }
        let r = tracker.mouseUp(at: convert(event.locationInWindow, from: nil))
        if r.needsRedraw { needsDisplay = true }
        switch r.fire {
        case .close: onClose?()
        case .zoom:  onZoom?()
        default: break
        }
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
