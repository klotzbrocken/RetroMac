import AppKit

/// NeXTSTEP miniwindows: a miniaturized window became a 64×64 tile of its own on the workspace,
/// the app's icon under a black strip with the window's title, and a double-click put the window
/// back. Under the NeXT theme RetroMac lays one out for every minimised window, along the bottom of
/// the screen from the Dock leftwards (the app icons cascade in from the left). The window itself
/// still goes where macOS minimises it to.
final class NextMiniwindowsController {
    static let shared = NextMiniwindowsController()
    private var panels: [NextMiniwindowPanel] = []
    private var shown: [String] = []
    private var token: NSObjectProtocol?
    private init() {}

    func update() {
        guard ThemeManager.shared.activeTheme?.config.isNextStep == true else { return hide() }
        if token == nil {
            token = NotificationCenter.default.addObserver(forName: .minimizedWindowsChanged, object: nil,
                                                           queue: .main) { [weak self] _ in self?.rebuild() }
        }
        rebuild()
    }

    func hide() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
        shown = []
    }

    private func rebuild() {
        let minimized = MinimizedWindowTracker.shared.entries.filter { !$0.isAppLevel }
        // The tracker also reports focus changes: only a different set of miniwindows lays out anew.
        let ids = minimized.map { "\(CFHash($0.window))|\($0.title)" }
        guard ids != shown else { return }
        shown = ids
        panels.forEach { $0.orderOut(nil) }
        panels = []
        guard let f = NSScreen.main?.visibleFrame else { return }
        for (i, entry) in minimized.enumerated() {
            let x = f.maxX - 64 - 4 - CGFloat(i + 1) * NextAppIconPanel.gridPitch   // left of the Dock column
            let panel = NextMiniwindowPanel(entry: entry, icon: ThemeManager.shared.icon(for: entry.bundleID, size: 64),
                                            origin: NSPoint(x: x, y: f.minY))
            panel.orderFront(nil)
            panels.append(panel)
        }
    }
}

/// One miniwindow: double-click to put the window back.
final class NextMiniwindowPanel: NSPanel {
    private let entry: MinimizedWindowTracker.Entry

    init(entry: MinimizedWindowTracker.Entry, icon: NSImage?, origin: NSPoint) {
        self.entry = entry
        super.init(contentRect: NSRect(x: origin.x, y: origin.y, width: 64, height: 64),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: 5)   // the NeXT icon tier, with the app icons and the Dock
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        let view = NextMiniwindowView(title: entry.title, icon: icon)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("\(entry.title), miniaturized")
        view.onPress = { [weak self] in self?.restore() }
        contentView = view
        title = entry.title
    }

    override var canBecomeKey: Bool { false }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount >= 2 { restore() }
    }

    private func restore() {
        MinimizedWindowTracker.shared.activate(entry)
    }
}

final class NextMiniwindowView: NSView {
    var onPress: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { onPress?(); return true }
    private let title: String
    private let icon: NSImage?

    init(title: String, icon: NSImage?) {
        self.title = title; self.icon = icon
        super.init(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NeXTChrome.dockTile(bounds, flipped: false, in: ctx)
        // The black title strip along the top, the title small and white in it.
        let strip = NSRect(x: 2, y: bounds.height - 14, width: bounds.width - 4, height: 12)
        NeXTChrome.black.setFill()
        ctx.fill(strip)
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: strip.insetBy(dx: 2, dy: 0).offsetBy(dx: 0, dy: -1),
                                 withAttributes: [.font: NeXTChrome.titleFont(9), .foregroundColor: NeXTChrome.white,
                                                  .paragraphStyle: p])
        icon?.draw(in: NSRect(x: 14, y: 6, width: 36, height: 36), from: .zero, operation: .sourceOver, fraction: 1)
    }
}
