import ScreenSaver
import WebKit

/// Generic RetroMac screensaver host: a WKWebView running the same HTML/canvas saver
/// the in-app screensaver uses (Pipes / FlowerBox / Flying Toasters / Flurry — the
/// bundled `saver/index.html` decides which one this .saver shows).
@objc(RetroMacSaverView)
public final class RetroMacSaverView: ScreenSaverView {

    private var webView: WKWebView?

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        let cfg = WKWebViewConfiguration()
        cfg.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let wv = WKWebView(frame: bounds, configuration: cfg)
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")
        addSubview(wv)
        webView = wv

        let bundle = Bundle(for: RetroMacSaverView.self)
        if let html = bundle.url(forResource: "index", withExtension: "html", subdirectory: "saver") {
            wv.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override var hasConfigureSheet: Bool { false }
    public override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()
    }
}
