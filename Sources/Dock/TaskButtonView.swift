import AppKit

/// An elongated Windows-style taskbar button: icon + (truncated) title, themed for Win98
/// (raised/sunken bevel) or XP Luna (glossy blue). The "active" window's button is drawn
/// pressed/sunken. Used only by the Win98/XP taskbar; click is handled by DockView.
final class TaskButtonView: NSView {

    enum Style { case win98, winxp }

    private let title: String
    private let icon: NSImage?
    private let style: Style
    private var isActive: Bool
    var onClick: (() -> Void)?
    private var pressed = false
    private var hovered = false
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, title: String, icon: NSImage?, style: Style, isActive: Bool) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isActive = isActive
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Optimistic active-state update on click (the tracker poll reconciles it later).
    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active; needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                owner: self, userInfo: nil)
        addTrackingArea(ta); trackingArea = ta
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        pressed = true; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        pressed = false; needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let sunken = isActive || pressed
        switch style {
        case .win98: drawWin98(ctx, sunken: sunken)
        case .winxp: drawXP(ctx, sunken: sunken, hovered: hovered && !sunken)
        }
        drawContent(sunken: sunken)
    }

    // MARK: - Win98 raised/sunken bevel

    private func drawWin98(_ ctx: CGContext, sunken: Bool) {
        let b = bounds
        NSColor(srgbRed: 0.769, green: 0.769, blue: 0.769, alpha: 1).setFill()   // #C4C4C4 face
        ctx.fill(b)
        func line(_ r: NSRect, _ c: NSColor) { c.setFill(); ctx.fill(r) }
        let white = NSColor.white
        let light = NSColor(srgbRed: 0.859, green: 0.859, blue: 0.859, alpha: 1)  // #DBDBDB
        let shade = NSColor(srgbRed: 0.502, green: 0.502, blue: 0.502, alpha: 1)  // #808080
        let dark  = NSColor.black
        // top-left vs bottom-right depending on raised/sunken
        let tl1 = sunken ? shade : white
        let tl2 = sunken ? dark  : light
        let br1 = sunken ? light : shade
        let br2 = sunken ? white : dark
        line(NSRect(x: 0, y: b.maxY - 1, width: b.width, height: 1), tl1)            // top (flipped? no — y-up: top = maxY)
        line(NSRect(x: 0, y: 0, width: 1, height: b.height), tl1)                    // left
        line(NSRect(x: 0, y: b.maxY - 2, width: b.width - 1, height: 1), tl2)
        line(NSRect(x: 1, y: 1, width: 1, height: b.height - 2), tl2)
        line(NSRect(x: 0, y: 0, width: b.width, height: 1), br1)                     // bottom
        line(NSRect(x: b.width - 1, y: 0, width: 1, height: b.height), br1)          // right
        line(NSRect(x: 1, y: 1, width: b.width - 2, height: 1), br2)
        line(NSRect(x: b.width - 2, y: 1, width: 1, height: b.height - 2), br2)
    }

    // MARK: - XP Luna glossy blue

    private func drawXP(_ ctx: CGContext, sunken: Bool, hovered: Bool) {
        let b = bounds
        // XP program tab (UI-kit "Program tab"): gentle vertical gradient with a subtle 3D edge
        // (light top highlight + darker bottom shadow) and a 1px light border. Three states:
        // resting / hover (brighter) / active (dark navy, recessed).
        func c(_ r: CGFloat, _ g: CGFloat, _ bl: CGFloat) -> NSColor {
            NSColor(srgbRed: r, green: g, blue: bl, alpha: 1)
        }
        let top: NSColor, bot: NSColor, border: NSColor
        if sunken {                                   // active window — dark navy, inset
            top = c(0.16, 0.33, 0.69); bot = c(0.09, 0.22, 0.52); border = c(0.07, 0.16, 0.40)
        } else if hovered {                           // hover — brighter blue
            top = c(0.49, 0.69, 0.97); bot = c(0.24, 0.47, 0.89); border = c(0.62, 0.79, 0.99)
        } else {                                      // resting
            top = c(0.36, 0.57, 0.92); bot = c(0.16, 0.37, 0.80); border = c(0.55, 0.73, 0.97)
        }
        let path = NSBezierPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        NSGradient(starting: bot, ending: top)?.draw(in: path, angle: 90)
        // 3D edge: 1px light highlight along the top, 1px shadow along the bottom (clipped).
        NSGraphicsContext.current?.saveGraphicsState(); path.addClip()
        let hi = sunken ? NSColor.white.withAlphaComponent(0.18) : NSColor.white.withAlphaComponent(0.45)
        hi.setFill(); ctx.fill(NSRect(x: b.minX, y: b.maxY - 2, width: b.width, height: 1.5))
        NSColor.black.withAlphaComponent(0.22).setFill()
        ctx.fill(NSRect(x: b.minX, y: b.minY, width: b.width, height: 1.5))
        NSGraphicsContext.current?.restoreGraphicsState()
        border.setStroke(); path.lineWidth = 1; path.stroke()
    }

    // MARK: - Icon + title

    private func drawContent(sunken: Bool) {
        let b = bounds
        let off: CGFloat = (sunken ? 1 : 0)
        // Win98 = small classic icon (~16px); XP = larger icon per the UI-kit tab.
        let iconSz: CGFloat = (style == .win98) ? min(18, b.height - 6) : min(26, b.height - 2)
        let iconX = (style == .win98 ? 4 : 6) + off
        let iconY = (b.height - iconSz) / 2 - off
        var textX = iconX
        if let icon = icon {
            icon.draw(in: NSRect(x: iconX, y: iconY, width: iconSz, height: iconSz),
                      from: .zero, operation: .sourceOver, fraction: 1.0)
            textX = iconX + iconSz + 5
        }
        let isWin98 = (style == .win98)
        let color: NSColor = isWin98 ? .black : .white
        let fsize: CGFloat = isWin98 ? 11 : 12
        let font = NSFont(name: "Tahoma", size: fsize)   // XP & Win98 both use Tahoma
            ?? NSFont.systemFont(ofSize: fsize, weight: isWin98 ? .regular : .semibold)
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
        if !isWin98 {
            let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.5)
            sh.shadowOffset = NSSize(width: 0, height: -1); attrs[.shadow] = sh
        }
        let th = font.ascender - font.descender
        let textRect = NSRect(x: textX, y: (b.height - th) / 2 - off,
                              width: max(0, b.width - textX - 5 - off), height: th + 2)
        (title as NSString).draw(in: textRect, withAttributes: attrs)
    }
}
