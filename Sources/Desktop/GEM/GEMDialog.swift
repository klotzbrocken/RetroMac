import AppKit

/// A GEM alert or dialog (D7): centred on the screen in the grey box of Desktop Info (`_2.png`),
/// its lines centred, the buttons below with the default one in a three-point line. Return takes
/// the default, Esc the last button.
final class GEMDialog {
    enum Line { case text(String), rule, logo, gap }

    private static var open: [NSPanel] = []

    static func show(_ lines: [Line], buttons: [String], completion: ((Int) -> Void)? = nil) {
        let view = GEMDialogView(lines: lines, buttons: buttons)
        let size = view.preferredSize
        let screen = NSScreen.screens.first ?? NSScreen.main!
        let f = NSRect(x: (screen.frame.midX - size.width / 2).rounded(), y: (screen.frame.midY - size.height / 2).rounded(), width: size.width, height: size.height)
        let p = GEMDialogPanel(contentRect: f, styleMask: [.borderless], backing: .buffered, defer: false)
        p.level = .modalPanel
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.title = lines.compactMap { if case .text(let s) = $0 { return s }; return nil }.first ?? "Alert"   // what VoiceOver reads first
        view.frame = NSRect(origin: .zero, size: size)
        view.finish = { [weak p] choice in
            guard let p else { return }
            p.orderOut(nil)
            open.removeAll { $0 === p }
            completion?(choice)
        }
        p.contentView = view
        open.append(p)
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(view)
    }

    /// Desktop Info, as TOS 4.04 put it up (`_2.png`).
    static func desktopInfo() {
        show([.text("GEM, Graphic Environment Manager"), .gap, .text("TOS"), .rule, .gap, .logo, .gap, .gap,
              .text("Copyright © 1985-1993"), .text("Atari Corporation"), .text("Digital Research, Inc."), .text(" All Rights Reserved")],
             buttons: ["OK"])
    }

    static func info(for app: GEMApp) {
        let version = Bundle(url: app.url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        show([.text("Application Information"), .rule, .gap, .text(app.name), .text("in \(app.location)")]
             + (version.map { [.text("Version \($0)")] } ?? []), buttons: ["OK"])
    }

    static func info(for item: GEMDesktopView.Item) {
        var lines: [Line] = [.text("Item Information"), .rule, .gap, .text(item.name)]
        switch item.kind {
        case .boot(let u), .volume(let u):
            let v = try? u.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            let fmt = ByteCountFormatter()
            if let total = v?.volumeTotalCapacity { lines.append(.text("\(fmt.string(fromByteCount: Int64(total))) in all")) }
            if let free = v?.volumeAvailableCapacityForImportantUsage { lines.append(.text("\(fmt.string(fromByteCount: free)) free")) }
        case .apps: lines.append(.text("Every application on this Mac"))
        case .trash: lines.append(.text("The Mac's Trash"))
        case .app(let u): lines.append(.text("in \(u.deletingLastPathComponent().path)"))
        }
        show(lines, buttons: ["OK"])
    }
}

final class GEMDialogPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class GEMDialogView: NSView {
    let lines: [GEMDialog.Line]
    let buttons: [String]
    var finish: ((Int) -> Void)?
    private var pressed: Int?

    init(lines: [GEMDialog.Line], buttons: [String]) {
        self.lines = lines; self.buttons = buttons
        super.init(frame: .zero)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private static func height(_ l: GEMDialog.Line) -> CGFloat {
        switch l { case .text: return GEMChrome.rowH; case .rule: return 8; case .logo: return 30; case .gap: return 16 }
    }
    private var buttonSize: NSSize {
        NSSize(width: max(74, CGFloat(buttons.map(\.count).max() ?? 0) * GEMChrome.charW + 26), height: 26)
    }
    var preferredSize: NSSize {
        let textW = lines.compactMap { if case .text(let s) = $0 { return GEMChrome.textWidth(s) }; return nil }.max() ?? 0
        let w = max(288, textW + 64, CGFloat(buttons.count) * (buttonSize.width + 24) + 40)
        return NSSize(width: w, height: 24 + lines.reduce(0) { $0 + Self.height($1) } + 16 + buttonSize.height + 18)
    }
    func buttonRect(_ i: Int) -> NSRect {
        let s = buttonSize, gap: CGFloat = 24
        let total = CGFloat(buttons.count) * s.width + CGFloat(buttons.count - 1) * gap
        return NSRect(x: (bounds.midX - total / 2).rounded() + CGFloat(i) * (s.width + gap), y: bounds.height - 18 - s.height, width: s.width, height: s.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        GEMChrome.dialog(bounds)
        var y: CGFloat = 24
        for l in lines {
            switch l {
            case .text(let s): GEMChrome.text(s, at: NSPoint(x: (bounds.midX - GEMChrome.textWidth(s) / 2).rounded(), y: y))
            case .rule:
                // The dimmed row of dashes under "TOS".
                NSColor.black.setFill()
                var x = (bounds.midX - 116).rounded()
                while x < bounds.midX + 116 {
                    for c in 1...6 { NSRect(x: x + CGFloat(c), y: y + 2 + CGFloat((c + 1) % 2), width: 1, height: 1).fill() }
                    x += 8
                }
            case .logo: GEMChrome.bitmap(GEMChrome.fuji, at: NSPoint(x: (bounds.midX - 14).rounded(), y: y), color: .black)
            case .gap: break
            }
            y += Self.height(l)
        }
        for (i, b) in buttons.enumerated() { GEMChrome.button(buttonRect(i), title: b, isDefault: i == 0, pressed: pressed == i) }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = buttons.indices.first(where: { buttonRect($0).contains(p) }) else { return }
        pressed = i; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let was = pressed
        pressed = nil; needsDisplay = true
        if let i = was, buttonRect(i).contains(p) { finish?(i) }
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: finish?(0)
        case 53: finish?(buttons.count - 1)
        default: super.keyDown(with: event)
        }
    }

    private var axParts: [AccessibleHotspot] = []
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? {
        lines.compactMap { if case .text(let s) = $0 { return s }; return nil }.joined(separator: ", ")
    }
    override func accessibilityChildren() -> [Any]? {
        axParts = buttons.indices.map { i in AccessibleHotspot.make(in: self, label: buttons[i], rect: buttonRect(i)) { [weak self] in self?.finish?(i) } }
        return axParts
    }
}
