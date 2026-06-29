import AppKit

/// Floating "Quick-Switch" pill for changing the webcam scene mid-call without opening
/// Settings. Shows ◀ active-scene ▶; the arrows cycle scenes. Only visible while the virtual
/// camera is running (and the user hasn't disabled it). Draggable; position is remembered.
final class QuickSwitchController {
    static let shared = QuickSwitchController()

    private var window: NSWindow?
    private let posKey = "quickSwitchOrigin"
    private let size = NSSize(width: 220, height: 34)
    private var observers: [NSObjectProtocol] = []

    private init() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .virtualCameraStateChanged, object: nil, queue: .main) {
            [weak self] _ in self?.refreshVisibility()
        })
        observers.append(nc.addObserver(forName: .cameraSceneChanged, object: nil, queue: .main) {
            [weak self] _ in self?.window?.contentView?.needsDisplay = true
        })
    }

    /// Show iff the virtual camera is running and the feature is enabled; otherwise hide.
    func refreshVisibility() {
        let show = VirtualCameraManager.shared.isRunning && AppSettings.shared.quickSwitchEnabled
        show ? present() : window?.orderOut(nil)
    }

    private func present() {
        if window == nil { build() }
        position()
        window?.contentView?.needsDisplay = true
        window?.orderFrontRegardless()
    }

    private func build() {
        let view = QuickSwitchView(frame: NSRect(origin: .zero, size: size))
        view.onPrev = { CameraScene.cycle(by: -1) }
        view.onNext = { CameraScene.cycle(by: 1) }
        view.onMoved = { [weak self] origin in
            UserDefaults.standard.set(NSStringFromPoint(origin), forKey: self?.posKey ?? "quickSwitchOrigin")
        }
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = NSWindow.Level(rawValue: 26)   // above docks / launcher
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        win.ignoresMouseEvents = false
        win.alphaValue = 0.92
        win.contentView = view
        view.hostWindow = win
        window = win
    }

    private func position() {
        guard let win = window else { return }
        if let saved = UserDefaults.standard.string(forKey: posKey) {
            let p = NSPointFromString(saved)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(p) }) ?? NSScreen.main {
                let vf = screen.visibleFrame
                let x = min(max(p.x, vf.minX), vf.maxX - size.width)
                let y = min(max(p.y, vf.minY), vf.maxY - size.height)
                win.setFrameOrigin(NSPoint(x: x, y: y))
                return
            }
        }
        if let vf = NSScreen.main?.visibleFrame {
            win.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 90))
        }
    }
}

/// The pill view: dark translucent capsule with ◀ / ▶ and the active scene name.
/// Click-vs-drag aware (drag moves the window; a click on the left third = prev, else next).
private final class QuickSwitchView: NSView {
    var onPrev: (() -> Void)?
    var onNext: (() -> Void)?
    var onMoved: ((NSPoint) -> Void)?
    weak var hostWindow: NSWindow?

    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var didDrag = false

    override func draw(_ dirtyRect: NSRect) {
        let pill = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
        NSColor(white: 0.08, alpha: 0.82).setFill(); path.fill()
        NSColor(white: 1, alpha: 0.16).setStroke(); path.lineWidth = 1; path.stroke()

        let arrow: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        ("\u{25C0}" as NSString).draw(at: NSPoint(x: pill.minX + 12, y: pill.midY - 9), withAttributes: arrow)
        ("\u{25B6}" as NSString).draw(at: NSPoint(x: pill.maxX - 24, y: pill.midY - 9), withAttributes: arrow)

        let name = CameraScene.all.first { $0.id == AppSettings.shared.activeCameraSceneID }?.name ?? "Scene"
        let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byTruncatingTail
        let label: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white, .paragraphStyle: para
        ]
        (name as NSString).draw(in: NSRect(x: pill.minX + 30, y: pill.midY - 8, width: pill.width - 60, height: 16),
                                withAttributes: label)
    }

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = hostWindow?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStartMouse.x, dy = now.y - dragStartMouse.y
        if abs(dx) > 3 || abs(dy) > 3 { didDrag = true }
        hostWindow?.setFrameOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            if let o = hostWindow?.frame.origin { onMoved?(o) }
            return
        }
        let x = convert(event.locationInWindow, from: nil).x
        if x < bounds.width * 0.33 { onPrev?() } else { onNext?() }
    }
}
