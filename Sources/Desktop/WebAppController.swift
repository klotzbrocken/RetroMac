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
final class WebAppController: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {

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

    static func closeAll() {
        for (_, c) in openWindows { c.panel?.orderOut(nil) }
        openWindows.removeAll()
    }

    private let appName: String
    private let appURL: String
    private let size: NSSize
    private var panel: WebAppPanel?

    private init(name: String, url: String, size: NSSize) {
        self.appName = name; self.appURL = url; self.size = size
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: .dockThemeChanged, object: nil)
    }

    @objc private func themeChanged() { close() }

    private func show() {
        let frame = NSRect(origin: .zero, size: size)
        // Browser-style windows (real websites) get back/forward navigation in the chrome;
        // the self-contained 98.js apps don't need it.
        let showNav = !appURL.contains("github.io")
        let chrome = WebAppChromeView(frame: frame, title: appName, showNav: showNav)
        chrome.onClose = { [weak self] in self?.close() }

        let cfg = WKWebViewConfiguration()
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        let wv = WKWebView(frame: chrome.contentRect(), configuration: cfg)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        wv.uiDelegate = self
        if let u = URL(string: appURL) { wv.load(URLRequest(url: u)) }
        chrome.addSubview(wv)
        chrome.onBack = { [weak wv] in if wv?.canGoBack == true { wv?.goBack() } }
        chrome.onForward = { [weak wv] in if wv?.canGoForward == true { wv?.goForward() } }

        let p = WebAppPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        p.level = .normal
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.hidesOnDeactivate = false
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
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
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
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var url = dir.appendingPathComponent(suggestedFilename)
        var i = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let base = (suggestedFilename as NSString).deletingPathExtension
            let ext = (suggestedFilename as NSString).pathExtension
            url = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)")
            i += 1
        }
        completionHandler(url)
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
        NSColor(srgbRed: 0.031, green: 0.192, blue: 0.851, alpha: 1).setFill()   // #0831D9 frame
        NSBezierPath(roundedRect: b, xRadius: 8, yRadius: 8).fill()
        ctx.fill(NSRect(x: 0, y: b.height - 12, width: b.width, height: 12))      // square bottom

        let cap = NSRect(x: 0, y: 0, width: b.width, height: titleH)
        let grad = NSGradient(colorsAndLocations:
            (NSColor(srgbRed: 0.035, green: 0.592, blue: 1.0, alpha: 1), 0.0),    // #0997FF
            (NSColor(srgbRed: 0.0, green: 0.325, blue: 0.933, alpha: 1), 0.45),   // #0053EE
            (NSColor(srgbRed: 0.0, green: 0.4, blue: 1.0, alpha: 1), 0.52),       // #0066FF
            (NSColor(srgbRed: 0.0, green: 0.239, blue: 0.824, alpha: 1), 1.0))    // #003DD2
        let capPath = NSBezierPath(roundedRect: cap, xRadius: 8, yRadius: 8)
        grad?.draw(in: capPath, angle: -90)
        ctx.fill(NSRect(x: 0, y: titleH - 6, width: 0, height: 0))

        // close (red), min/max dimmed
        let bw: CGFloat = 21, bh: CGFloat = 19
        let by = (titleH - bh) / 2
        let closeR = NSRect(x: b.width - 6 - bw, y: by, width: bw, height: bh)
        let maxR   = NSRect(x: closeR.minX - 2 - bw, y: by, width: bw, height: bh)
        let minR   = NSRect(x: maxR.minX - 2 - bw, y: by, width: bw, height: bh)
        func gel(_ r: NSRect, top: NSColor, bottom: NSColor, alpha: CGFloat) {
            let p = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
            NSGradient(starting: top.withAlphaComponent(alpha), ending: bottom.withAlphaComponent(alpha))?
                .draw(in: p, angle: -90)
            NSColor.white.withAlphaComponent(0.55 * alpha).setStroke(); p.stroke()
        }
        gel(minR, top: NSColor(srgbRed: 0.61, green: 0.75, blue: 0.97, alpha: 1),
                  bottom: NSColor(srgbRed: 0.16, green: 0.31, blue: 0.72, alpha: 1), alpha: 0.45)
        gel(maxR, top: NSColor(srgbRed: 0.61, green: 0.75, blue: 0.97, alpha: 1),
                  bottom: NSColor(srgbRed: 0.16, green: 0.31, blue: 0.72, alpha: 1), alpha: 0.45)
        gel(closeR, top: NSColor(srgbRed: 0.97, green: 0.70, blue: 0.62, alpha: 1),
                    bottom: NSColor(srgbRed: 0.77, green: 0.22, blue: 0.16, alpha: 1), alpha: 1.0)
        NSColor.white.setStroke()
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
