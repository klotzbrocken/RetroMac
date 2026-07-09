import AppKit

/// Small shared "installing…" progress window (a spinner + a status line) used by every
/// downloader/installer. Returns a plain `NSWindow`; call `update` to change the status line
/// and `window.close()` when done.
enum InstallProgressWindow {

    /// Create + show a centered floating progress window.
    static func make(title: String, detail: String) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 120))

        let spinner = NSProgressIndicator(frame: NSRect(x: 170, y: 75, width: 40, height: 40))
        spinner.style = .spinning
        spinner.startAnimation(nil)
        container.addSubview(spinner)

        let label = NSTextField(labelWithString: detail)
        label.frame = NSRect(x: 20, y: 30, width: 340, height: 36)
        label.alignment = .center
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.tag = 100
        container.addSubview(label)

        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }

    /// Update the status line of a window created by `make`.
    static func update(_ window: NSWindow, detail: String) {
        (window.contentView?.viewWithTag(100) as? NSTextField)?.stringValue = detail
    }

    /// The shared warn-but-allow prompt for an app that failed signature/notarization verification.
    /// Returns true if the user chose to install anyway. Safe to call from any thread.
    static func confirmUnverified(name: String) -> Bool {
        var proceed = false
        let ask = {
            let alert = NSAlert()
            alert.messageText = "Could not verify “\(name)”"
            alert.informativeText = "The downloaded app's code signature or notarization could not be verified. Installing it anyway bypasses macOS Gatekeeper — do this only if you trust the source."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Install Anyway")
            alert.addButton(withTitle: "Cancel")
            proceed = (alert.runModal() == .alertFirstButtonReturn)
        }
        if Thread.isMainThread { ask() } else { DispatchQueue.main.sync(execute: ask) }
        return proceed
    }
}
