import AppKit

/// A single program item inside a group window: pixelated icon + label below.
/// Single-click selects (label highlight), double-click launches the mapped app.
final class ProgramItemView: NSView {

    let entry: DockThemeConfig.DesktopIconEntry
    private let image: NSImage?
    private var selected = false

    /// Icon size scales with the Settings desktop-icon slider (dock slider while linked).
    static var scale: CGFloat { max(0.5, min(2.5, CGFloat(AppSettings.shared.effectiveDesktopIconScale))) }
    static var iconSize: CGFloat { (32 * scale).rounded() }
    static var cellWidth: CGFloat { max(72, iconSize + 44).rounded() }
    static var cellHeight: CGFloat { (iconSize + 32).rounded() }

    private let iconSize: CGFloat = ProgramItemView.iconSize

    override var isFlipped: Bool { true }

    init(entry: DockThemeConfig.DesktopIconEntry, image: NSImage?) {
        self.entry = entry
        self.image = image
        super.init(frame: NSRect(x: 0, y: 0, width: Self.cellWidth, height: Self.cellHeight))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        // Icon (top, centered). respectFlipped keeps it upright in a flipped view.
        let iconRect = NSRect(x: (bounds.width - iconSize) / 2, y: 2, width: iconSize, height: iconSize)
        if let image = image {
            NSGraphicsContext.current?.imageInterpolation = .none
            image.draw(in: iconRect, from: .zero, operation: .sourceOver,
                       fraction: 1.0, respectFlipped: true, hints: nil)
        }

        // Label
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        // Black text on the gray group interior; white-on-navy when selected (Win 3.1).
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Win31Chrome.font(size: 11, bold: false),
            .foregroundColor: selected ? NSColor.white : NSColor.black,
            .paragraphStyle: style
        ]
        let attr = NSAttributedString(string: entry.name, attributes: attrs)
        let labelTop = iconSize + 4
        let labelRect = NSRect(x: 0, y: labelTop, width: bounds.width, height: bounds.height - labelTop)
        let tb = attr.boundingRect(with: NSSize(width: labelRect.width, height: labelRect.height),
                                   options: [.usesLineFragmentOrigin])

        if selected {
            Win31Chrome.selection.setFill()
            let w = min(tb.width + 6, bounds.width)
            NSRect(x: (bounds.width - w) / 2, y: labelTop,
                   width: w, height: min(tb.height + 2, labelRect.height)).integral.fill()
        }
        attr.draw(with: labelRect, options: [.usesLineFragmentOrigin])
    }

    func setSelected(_ s: Bool) {
        guard selected != s else { return }
        selected = s
        needsDisplay = true
    }

    // Drag-to-reposition support (enabled for Program Manager items)
    var draggable = false
    var onMoved: ((ProgramItemView) -> Void)?
    var onContextMenu: ((ProgramItemView, NSEvent) -> Void)?
    private var dragOrigin: NSPoint?
    private var didDrag = false

    override func mouseDown(with event: NSEvent) {
        if let parent = superview {
            for v in parent.subviews { (v as? ProgramItemView)?.setSelected(false) }
        }
        setSelected(true)
        didDrag = false
        if draggable, let parent = superview {
            let m = parent.convert(event.locationInWindow, from: nil)
            dragOrigin = NSPoint(x: m.x - frame.minX, y: m.y - frame.minY)
        }
        if event.clickCount >= 2 { DesktopLauncher.launch(entry) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard draggable, let off = dragOrigin, let parent = superview else { return }
        didDrag = true
        let m = parent.convert(event.locationInWindow, from: nil)
        var o = NSPoint(x: m.x - off.x, y: m.y - off.y)
        o.x = max(0, min(o.x, parent.bounds.width - frame.width))
        o.y = max(0, min(o.y, parent.bounds.height - frame.height))
        setFrameOrigin(o)
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag { onMoved?(self) }
        dragOrigin = nil; didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(self, event)
    }
}
