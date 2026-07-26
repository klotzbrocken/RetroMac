import AppKit
import WebKit

/// A borderless desktop-widget panel that can still become key. Borderless panels are non-key by
/// default, so without this the Mac OS 9 widgets could never show the inactive (blurred) chrome —
/// they'd always look active. Non-activating is preserved, so clicking a widget does not steal
/// app focus; it only makes that widget the key window among the widgets.
final class KeyableWidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Drive the Mac OS 9 inactive-window chrome (os9.ca `.window.blur`) by toggling an `rm-blur`
/// body class on the widget's webview as its panel gains/loses key focus. Returns the observer
/// tokens so the caller can retain (and later remove) them.
@discardableResult
func installMacOS9BlurTracking(panel: NSWindow, webView: @escaping () -> WKWebView?) -> [NSObjectProtocol] {
    func set(_ blur: Bool) {
        webView()?.evaluateJavaScript("document.body.classList.\(blur ? "add" : "remove")('rm-blur')")
    }
    let nc = NotificationCenter.default
    // Seed the initial state (a widget opened while another window is key starts inactive).
    set(!(panel.isKeyWindow))
    return [
        nc.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { _ in set(true) },
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification,  object: panel, queue: .main) { _ in set(false) },
    ]
}
