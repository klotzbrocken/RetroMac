import AppKit

/// A single desktop icon: image + label, with Mac OS 9-style label selection and double-click action.
final class DesktopIconView: NSView {

    let entry: DockThemeConfig.DesktopIconEntry

    weak var target: AnyObject?
    var action: Selector?

    private let imageView: NSImageView
    private let label: NSTextField
    private let iconSize: CGFloat
    private var isSelected = false
    private var isPixelated: Bool

    private var emptyImage: NSImage
    private var fullImage: NSImage?

    /// The theme's label plate colour, drawn behind the text (nil: shadowed white text).
    private let labelPlate: NSColor?

    init(entry: DockThemeConfig.DesktopIconEntry, image: NSImage, fullImage: NSImage?,
         iconSize: CGFloat, isPixelated: Bool, labelStyle: DockThemeConfig.DesktopLabelStyle? = nil) {
        self.entry = entry
        self.iconSize = iconSize
        self.isPixelated = isPixelated
        self.emptyImage = image
        self.fullImage = fullImage
        self.labelPlate = labelStyle?.background.map { NSColor.fromHex($0) }

        // Image view
        imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        if isPixelated {
            imageView.wantsLayer = true
            imageView.layer?.magnificationFilter = .nearest
            imageView.layer?.minificationFilter = .nearest
        }

        // Label
        label = NSTextField(labelWithString: entry.name)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping     // wrap to a second line instead of clipping
        label.maximumNumberOfLines = 2
        label.cell?.wraps = true
        label.cell?.truncatesLastVisibleLine = true
        label.backgroundColor = .clear
        label.drawsBackground = false

        if let style = labelStyle {
            // The theme's own lettering: its font, its colour, and no shadow — the plate
            // behind the text (drawn in `draw`) is what keeps it readable.
            if let name = style.font, let f = RetroFonts.named(name, size: style.size ?? 16) { label.font = f }
            label.textColor = style.color.map { NSColor.fromHex($0) } ?? .black
        } else {
            // Drop shadow on label text for readability on desktop
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
            shadow.shadowOffset = NSSize(width: 1, height: -1)
            shadow.shadowBlurRadius = 2
            label.shadow = shadow
        }

        super.init(frame: .zero)

        addSubview(imageView)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let w = bounds.width
        let imgX = (w - iconSize) / 2
        let imgY = bounds.height - iconSize - 2
        imageView.frame = NSRect(x: imgX, y: imgY, width: iconSize, height: iconSize)

        // Room for the two lines the name may wrap to, in whatever font the theme gives it.
        let labelH = max(30, 2 * lineHeight + 4)
        // Label hugs the icon; the remaining cell space below becomes spacing to the
        // NEXT row (instead of a growing icon→label gap). A plate needs a little more air
        // than shadowed text, or it touches the icon.
        let gap: CGFloat = labelPlate == nil ? 4 : 9
        let labelY = max(0, bounds.height - iconSize - gap - labelH)
        label.frame = NSRect(x: -8, y: labelY, width: w + 16, height: labelH)
    }

    /// One line of the label as its own cell lays it out (a pixel font's metrics say less
    /// than it draws).
    private var lineHeight: CGFloat {
        guard let cell = label.cell else { return 16 }
        return ceil(cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: 10_000, height: 10_000)).height)
    }

    /// The name's lines as the label wraps them, measured by the label's own cell, so the plate
    /// and the highlight cover exactly what is drawn: `(widest line, number of lines)`.
    private func laidOutText() -> (width: CGFloat, lines: Int) {
        guard let cell = label.cell?.copy() as? NSCell else { return (label.frame.width, 1) }
        let wrapWidth = label.frame.width
        func size(_ s: String, width: CGFloat) -> NSSize {
            cell.stringValue = s
            return cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10_000))
        }
        let one = lineHeight
        let name = entry.name
        let single = size(name, width: 10_000).width
        guard size(name, width: wrapWidth).height > one * 1.5 else { return (single, 1) }
        // Two lines: the first takes words while they fit on one line, the rest wraps.
        let words = name.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var first = ""
        var n = 0
        for (k, w) in words.enumerated() {
            let candidate = k == 0 ? w : first + " " + w
            if k > 0, size(candidate, width: wrapWidth).height > one * 1.5 { break }
            first = candidate; n = k + 1
        }
        let rest = words.dropFirst(n).joined(separator: " ")
        guard n > 0, !rest.isEmpty else { return (min(single, wrapWidth), 2) }   // one long word, broken
        return (max(size(first, width: 10_000).width, min(size(rest, width: 10_000).width, wrapWidth)), 2)
    }

    /// The rectangle hugging the label's text as it is actually laid out — one or two lines,
    /// as wide as the longer line — for the plate and the highlight.
    private var textRect: NSRect {
        let lf = label.frame
        let (textW, lines) = laidOutText()
        let w = min(ceil(textW) + 4, lf.width)
        let h = CGFloat(lines) * lineHeight + 2
        // The label is TOP-aligned in its frame, so anchor to its top to hug the text. The
        // highlight may lean 2 pt above the frame; the plate stays inside it, clear of the icon.
        let lift: CGFloat = labelPlate == nil ? 2 : 0
        return NSRect(x: lf.midX - w / 2, y: lf.maxY - h + lift, width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isSelected {
            // Highlight hugs the LABEL TEXT only (the word), not the full two-line cell.
            // System 7.1's Finder: the name inverts, white on black, whatever the colours.
            if Mac256.active {
                Mac256.black.setFill()
                textRect.fill()
                label.textColor = Mac256.white
            } else {
                NSColor.selectedContentBackgroundColor.withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: textRect, xRadius: 3, yRadius: 3).fill()
            }
        } else if let plate = labelPlate {
            // Mac OS 9: the name sits on a plate of the label colour, square-cornered.
            if Mac256.active { label.textColor = Mac256.black }
            plate.setFill()
            textRect.fill()
        }
    }

    // MARK: - Trash State

    func setTrashFull(_ isFull: Bool) {
        imageView.image = (isFull ? fullImage : nil) ?? emptyImage
    }

    // Drag + context menu (desktop icon customization)
    var onMoved: ((DesktopIconView) -> Void)?
    var onContextMenu: ((DesktopIconView, NSEvent) -> Void)?
    private var dragOffset: NSPoint?
    private var didDrag = false

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        // Deselect all siblings first
        if let parent = superview {
            for sibling in parent.subviews {
                if let iconView = sibling as? DesktopIconView, iconView !== self {
                    iconView.deselect()
                }
            }
        }

        isSelected = true
        needsDisplay = true
        didDrag = false
        if let parent = superview {
            let m = parent.convert(event.locationInWindow, from: nil)
            dragOffset = NSPoint(x: m.x - frame.minX, y: m.y - frame.minY)
        }

        if event.clickCount >= 2 {
            if let target = target, let action = action {
                NSApp.sendAction(action, to: target, from: self)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let off = dragOffset, let parent = superview else { return }
        didDrag = true
        let m = parent.convert(event.locationInWindow, from: nil)
        var o = NSPoint(x: m.x - off.x, y: m.y - off.y)
        o.x = max(0, min(o.x, parent.bounds.width - frame.width))
        o.y = max(0, min(o.y, parent.bounds.height - frame.height))
        setFrameOrigin(o)
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag { onMoved?(self) }
        dragOffset = nil; didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(self, event)
    }

    /// Deselect this icon.
    func deselect() {
        guard isSelected else { return }
        isSelected = false
        needsDisplay = true
    }
}
