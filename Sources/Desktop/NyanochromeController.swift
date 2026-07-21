import AppKit
import WebKit

/// A tiny 1-bit "Nyanochrome" cat widget for the System 6 theme — a monochrome Nyan Cat drawn on a
/// canvas (Widgets/Nyanochrome/index.html), shown in a borderless, drag-anywhere panel. Opened from
/// the System 6 desktop "Nyanochrome" icon (toggles). Mirrors the other WebView widgets but simpler
/// (no themed title chrome — the HTML draws its own System 6 black window frame).
final class NyanochromeController: NSObject {

    static let shared = NyanochromeController()

    private var panel: NSPanel?
    private var webView: WKWebView?
    private let posKey = "nyanochromeOrigin"

    /// Transparent full-panel overlay: click the title-bar close box to close, drag anywhere else.
    private final class DragView: NSView {
        var closeRect: CGRect = .zero
        var onClose: (() -> Void)?
        override func mouseDown(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            if closeRect.contains(p) { onClose?(); return }
            window?.performDrag(with: event)
        }
    }

    func toggle() { if panel?.isVisible == true { close() } else { show() } }

    func close() { saveOrigin(); panel?.orderOut(nil) }

    func destroy() {
        saveOrigin()
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        panel?.orderOut(nil); panel = nil
    }

    func show() {
        guard let html = Bundle.main.resourceURL?.appendingPathComponent("Widgets/Nyanochrome/index.html"),
              FileManager.default.fileExists(atPath: html.path) else { NSSound.beep(); return }

        if panel == nil {
            let initial = NSRect(x: 0, y: 0, width: 280, height: 310)   // matches the 280x310 canvas (title bar + 280x288 scene)
            let wv = WKWebView(frame: initial, configuration: WKWebViewConfiguration())
            wv.autoresizingMask = [.width, .height]
            wv.setValue(false, forKey: "drawsBackground")

            let drag = DragView(frame: initial)
            drag.autoresizingMask = [.width, .height]
            // Close box lives in the canvas title bar top-left; map it to view coords (bottom-left
            // Close box: canvas (8,4) size 14x14 at the top → view coords (bottom-left origin), 1:1 scale.
            drag.closeRect = CGRect(x: 6, y: initial.height - 22, width: 18, height: 18)
            drag.onClose = { [weak self] in self?.close() }

            let container = NSView(frame: initial)
            container.addSubview(wv)
            container.addSubview(drag)   // over the webview → drag anywhere

            let p = NSPanel(contentRect: initial, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.level = .normal
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.contentView = container
            panel = p; webView = wv
        }

        webView?.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        restorePosition()
        panel?.orderFrontRegardless()
    }

    // MARK: - Position persistence

    private func saveOrigin() {
        guard let panel = panel, panel.isVisible else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: posKey)
    }

    private func restorePosition() {
        guard let panel = panel else { return }
        if let s = UserDefaults.standard.string(forKey: posKey) {
            panel.setFrameOrigin(NSPointFromString(s))
        } else if let screen = NSScreen.main {
            let f = panel.frame
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - f.width / 2,
                                         y: screen.visibleFrame.midY - f.height / 2))
        }
    }
}
