import AppKit

/// The countdown before a Party-mode crash: a small panel that says what is about to happen, so
/// nobody in the room mistakes the next ten seconds for a real failure of the machine.
final class CountdownHUD {

    static let shared = CountdownHUD()
    private init() {}

    private var panel: NSPanel?
    private var label: NSTextField?

    func show(seconds: Int) {
        if panel == nil { build() }
        label?.stringValue = "Crashing in \(seconds)…  (Esc cancels)"
        label?.sizeToFit()
        layout()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        label = nil
    }

    private func build() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 44),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.ignoresMouseEvents = true

        let bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 280, height: 44))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 10
        bg.autoresizingMask = [.width, .height]

        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.textColor = .white
        bg.addSubview(l)
        p.contentView = bg
        panel = p
        label = l
    }

    private func layout() {
        guard let p = panel, let l = label,
              let screen = NSScreen.main else { return }
        let w = max(200, l.frame.width + 32)
        p.setFrame(NSRect(x: screen.frame.midX - w / 2,
                          y: screen.visibleFrame.minY + 120,
                          width: w, height: 44), display: true)
        l.frame.origin = NSPoint(x: 16, y: 13)
    }
}
