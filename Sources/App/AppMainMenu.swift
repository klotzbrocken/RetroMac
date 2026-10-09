import AppKit

/// The main menu nobody sees. RetroMac lives in the menu bar and shows no menus of its own,
/// but key equivalents still go through `NSApp.mainMenu`: without one, ⌘W closed nothing, Esc
/// did not dismiss Settings, and ⌘C/⌘V only worked while Settings had put an Edit menu in.
enum AppMainMenu {
    /// Only while one of RetroMac's titled windows is key: that is where ⌘W and Esc are wanted.
    /// Standing all the time, a main menu changed how the menu-bar icon's own menu behaved (a
    /// second click on the icon no longer closed it), as Settings' Edit menu once taught.
    private static var observers: [NSObjectProtocol] = []
    private static var menu: NSMenu?

    static func install() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                DispatchQueue.main.async { sync() }   // after the key window has settled
            })
        }
    }

    private static func sync() {
        let wanted = NSApp.keyWindow.map { $0.styleMask.contains(.titled) && $0.isVisible } ?? false
        if wanted, NSApp.mainMenu == nil {
            NSApp.mainMenu = menu ?? build()
        } else if !wanted, let m = menu, NSApp.mainMenu === m {
            NSApp.mainMenu = nil
        }
    }

    private static func build() -> NSMenu {
        let main = NSMenu()

        let app = NSMenuItem(); app.submenu = NSMenu(); main.addItem(app)

        let edit = NSMenuItem(); let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu; main.addItem(edit)

        let window = NSMenuItem(); let windowMenu = NSMenu(title: "Window")
        let close = NSMenuItem(title: "Close Window", action: #selector(Closer.closeKeyWindow(_:)), keyEquivalent: "w")
        close.target = Closer.shared
        windowMenu.addItem(close)
        // Esc closes a window too, as asked for by a VoiceOver user; not while text is being typed.
        let esc = NSMenuItem(title: "Close", action: #selector(Closer.escapeKeyWindow(_:)), keyEquivalent: "\u{1b}")
        esc.keyEquivalentModifierMask = []
        esc.target = Closer.shared
        windowMenu.addItem(esc)
        window.submenu = windowMenu; main.addItem(window)

        menu = main
        return main
    }

    final class Closer: NSObject, NSMenuItemValidation {
        static let shared = Closer()

        /// A RetroMac window a person opened and can close: titled and closable, no sheet on it.
        private var closable: NSWindow? {
            guard let w = NSApp.keyWindow, w.styleMask.contains(.titled), w.styleMask.contains(.closable),
                  w.attachedSheet == nil, w.sheetParent == nil else { return nil }
            return w
        }

        func validateMenuItem(_ item: NSMenuItem) -> Bool {
            guard let w = closable else { return false }
            if item.action == #selector(escapeKeyWindow(_:)) { return !(w.firstResponder is NSText) }
            return true
        }

        @objc func closeKeyWindow(_ sender: Any?) { close(closable) }
        @objc func escapeKeyWindow(_ sender: Any?) { close(closable) }

        /// Through the close button when the window shows one (so its delegate is asked), else
        /// straight away: the readme and the setup windows hide theirs and draw their own.
        private func close(_ w: NSWindow?) {
            guard let w else { return }
            if let button = w.standardWindowButton(.closeButton), !button.isHidden { w.performClose(nil) } else { w.close() }
        }
    }
}
