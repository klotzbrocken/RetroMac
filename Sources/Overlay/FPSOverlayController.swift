import AppKit

final class FPSOverlayController {
    private var window: NSPanel?
    private var label: NSTextField?

    private var fps: Int = 0
    private var gpuTimeMs: Double = 0
    private var resolution: String = "—"

    func show() {
        guard window == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 20, y: 0, width: 220, height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: 26)
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let field = NSTextField(labelWithString: "FPS: — | GPU: —ms | —")
        field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        field.textColor = .green
        field.backgroundColor = .clear
        field.isBezeled = false
        field.isEditable = false
        field.frame = NSRect(x: 8, y: 4, width: 204, height: 20)
        panel.contentView?.addSubview(field)

        if let screen = NSScreen.main {
            let x: CGFloat = 20
            let y = screen.frame.maxY - 28 - 40
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        self.window = panel
        self.label = field
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        label = nil
    }

    var isVisible: Bool { window != nil }

    /// Render rate and CAPTURE rate, separately, per screen.
    ///
    /// One "FPS" field could not answer the question it was there for: the draw loop re-presents
    /// the last texture when ScreenCaptureKit goes quiet on a static display, so a healthy render
    /// number says nothing about whether a frame has arrived recently. `capture` and the age of
    /// the newest frame say that.
    func update(render: [Int], capture: [Int], captureAge: Double,
                gpuTimeMs: Double, resolution: String) {
        self.fps = render.first ?? 0
        self.gpuTimeMs = gpuTimeMs
        self.resolution = resolution

        let renderStr = render.isEmpty ? "—" : render.map(String.init).joined(separator: "/")
        let captureStr = capture.isEmpty ? "—" : capture.map(String.init).joined(separator: "/")
        // Only worth showing once it is genuinely stale; a frame or two of slack is normal.
        let ageStr = captureAge > 1.5 ? String(format: " (stale %.0fs)", captureAge) : ""

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let gpuStr = String(format: "%.1f", self.gpuTimeMs)
            self.label?.stringValue =
                "Draw: \(renderStr) | Capture: \(captureStr)\(ageStr) | GPU: \(gpuStr)ms | \(self.resolution)"
        }
    }
}
