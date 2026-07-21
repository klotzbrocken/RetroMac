import AppKit
import WebKit

/// A playable Tic-Tac-Toe widget for the classic Mac themes — the board rendering ported from Josh
/// Juran's Mac Tic-tac-toe (metamage_1), an unbeatable minimax opponent, in a System 6 window.
/// Opened from the desktop "Tic-Tac-Toe" icon (toggles). Unlike Nyanochrome, only the title bar is
/// draggable so board clicks reach the game.
final class TicTacToeController: NSObject {

    static let shared = TicTacToeController()

    private var panel: NSPanel?
    private var webView: WKWebView?
    private let posKey = "ticTacToeOrigin"

    /// Title-bar-only overlay: click the close box to close, drag elsewhere in the bar to move.
    /// Like the CPU widget, the close box shows a pressed state on mouse-down and only fires on
    /// mouse-up-inside (dragging out cancels), so closing reads as a real click.
    private final class TitleDragView: NSView {
        var closeRect: CGRect = .zero      // in this view's local (bottom-left) coords
        var onClose: (() -> Void)?
        var onClosePress: ((Bool) -> Void)?
        private var pressingClose = false
        override func mouseDown(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            if closeRect.contains(p) { pressingClose = true; onClosePress?(true); return }
            window?.performDrag(with: event)
        }
        override func mouseDragged(with event: NSEvent) {
            guard pressingClose else { return }
            onClosePress?(closeRect.contains(convert(event.locationInWindow, from: nil)))
        }
        override func mouseUp(with event: NSEvent) {
            guard pressingClose else { return }
            pressingClose = false
            if closeRect.contains(convert(event.locationInWindow, from: nil)) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
                    self?.onClosePress?(false); self?.onClose?()
                }
            } else {
                onClosePress?(false)
            }
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
        guard let html = Bundle.main.resourceURL?.appendingPathComponent("Widgets/TicTacToe/index.html"),
              FileManager.default.fileExists(atPath: html.path) else { NSSound.beep(); return }

        if panel == nil {
            let W: CGFloat = 224, H: CGFloat = 248, TB: CGFloat = 24   // matches the canvas
            let initial = NSRect(x: 0, y: 0, width: W, height: H)
            let wv = WKWebView(frame: initial, configuration: WKWebViewConfiguration())
            wv.autoresizingMask = [.width, .height]
            wv.setValue(false, forKey: "drawsBackground")

            // Drag overlay covers ONLY the title bar (top strip) so board clicks pass to the WebView.
            let drag = TitleDragView(frame: NSRect(x: 0, y: H - TB, width: W, height: TB))
            drag.autoresizingMask = [.width, .minYMargin]
            drag.closeRect = CGRect(x: 6, y: 2, width: 18, height: 18)   // close box, local coords
            drag.onClose = { [weak self] in self?.close() }
            drag.onClosePress = { [weak self] pressed in
                self?.webView?.evaluateJavaScript("window.setClosePressed && window.setClosePressed(\(pressed))", completionHandler: nil)
            }

            let container = NSView(frame: initial)
            container.addSubview(wv)
            container.addSubview(drag)

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
