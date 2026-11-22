import AppKit

/// A RetroMac panel that sits on the Windows taskbar like a program (Notepad, Calculator): while
/// it is open it has a button there, minimise hides it into that button, and a click on the
/// button brings it back or minimises the window in front. The open state is tracked here, not
/// read from `isVisible`, so a hidden-but-open panel keeps its button.
final class PanelTask {
    private(set) var minimized = false
    private var isOpen = false
    private weak var panel: NSWindow?
    private var tokens: [NSObjectProtocol] = []

    func opened(_ p: NSWindow) {
        if panel !== p {
            tokens.forEach(NotificationCenter.default.removeObserver)
            panel = p
            tokens = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map {
                NotificationCenter.default.addObserver(forName: $0, object: p, queue: .main) { _ in PanelTask.changed() }
            }
        }
        isOpen = true; minimized = false; Self.changed()
    }
    func closed() { isOpen = false; minimized = false; Self.changed() }
    func minimize() { guard isOpen else { return }; minimized = true; panel?.orderOut(nil); Self.changed() }
    func restore() {
        minimized = false
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        Self.changed()
    }

    /// The taskbar entry, nil while the panel is closed.
    func task(_ title: String) -> (title: String, active: Bool, toggle: () -> Void)? {
        guard isOpen, let p = panel else { return nil }
        let active = !minimized && p.isKeyWindow
        return (title, active, { [weak self] in active ? self?.minimize() : self?.restore() })
    }

    static func changed() { NotificationCenter.default.post(name: ExplorerController.windowsChanged, object: nil) }
}
