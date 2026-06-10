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

    init(entry: DockThemeConfig.DesktopIconEntry, image: NSImage, fullImage: NSImage?,
         iconSize: CGFloat, isPixelated: Bool) {
        self.entry = entry
        self.iconSize = iconSize
        self.isPixelated = isPixelated
        self.emptyImage = image
        self.fullImage = fullImage

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

        // Drop shadow on label text for readability on desktop
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowOffset = NSSize(width: 1, height: -1)
        shadow.shadowBlurRadius = 2
        label.shadow = shadow

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

        let labelH: CGFloat = 30
        // Label hugs the icon; the remaining cell space below becomes spacing to the
        // NEXT row (instead of a growing icon→label gap).
        let labelY = max(0, bounds.height - iconSize - 4 - labelH)
        label.frame = NSRect(x: -8, y: labelY, width: w + 16, height: labelH)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isSelected {
            // Highlight hugs the LABEL TEXT only (the word), not the full two-line cell.
            let font = label.font ?? NSFont.systemFont(ofSize: 11, weight: .medium)
            let textW = ceil((entry.name as NSString).size(withAttributes: [.font: font]).width)
            let lineH = ceil(font.ascender - font.descender + font.leading)
            let lf = label.frame
            let twoLines = textW > (lf.width - 4)
            let hiW = twoLines ? lf.width : min(textW + 8, lf.width)
            let hiH = (twoLines ? lineH * 2 : lineH) + 4
            let hiRect = NSRect(x: lf.midX - hiW / 2, y: lf.midY - hiH / 2, width: hiW, height: hiH)
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: hiRect, xRadius: 3, yRadius: 3).fill()
        }
    }

    // MARK: - Trash State

    func setTrashFull(_ isFull: Bool) {
        if isFull, let full = fullImage {
            imageView.image = full
        } else {
            imageView.image = emptyImage
        }
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
