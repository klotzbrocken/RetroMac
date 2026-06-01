import AppKit

/// Shared drawing helpers + colors for the Windows 3.1 Program Manager look.
/// All colors and bevels are measured to match the classic Win 3.x VGA palette.
enum Win31Chrome {

    // MARK: - Palette (classic Win 3.1 16-color VGA)
    static let face      = NSColor(red: 0.753, green: 0.753, blue: 0.753, alpha: 1)   // #C0C0C0 button face
    static let white     = NSColor.white                                              // top-left highlight
    static let lightGray = NSColor(red: 0.875, green: 0.875, blue: 0.875, alpha: 1)   // #DFDFDF
    static let darkGray  = NSColor(red: 0.502, green: 0.502, blue: 0.502, alpha: 1)   // #808080 shadow
    static let black     = NSColor.black                                              // outer shadow
    static let activeTitle   = NSColor(red: 0.0,  green: 0.0,  blue: 0.502, alpha: 1) // #000080 navy
    static let inactiveTitle = NSColor(red: 0.502, green: 0.502, blue: 0.502, alpha: 1) // #808080
    static let titleText     = NSColor.white
    static let inactiveTitleText = NSColor(white: 0.86, alpha: 1)
    static let workspace = NSColor(red: 0.502, green: 0.502, blue: 0.502, alpha: 1)   // PM workspace gray

    // MARK: - Font

    private static var fontRegistered = false
    private static var fontFamilyName: String?

    /// Register the bundled Win 3.1 UI font from a theme bundle (call once on theme load).
    static func registerFont(at url: URL) {
        guard !fontRegistered else { return }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // Discover the family name from the registered font
            if let dataProvider = CGDataProvider(url: url as CFURL),
               let cgFont = CGFont(dataProvider),
               let psName = cgFont.postScriptName as String? {
                // Map PostScript name to a usable NSFont family by trying it directly
                fontFamilyName = psName
            }
            fontRegistered = true
        }
    }

    /// Returns the Win 3.1 UI font at the given size, falling back to a crisp system font.
    static func font(size: CGFloat, bold: Bool = true) -> NSFont {
        if let name = fontFamilyName, let f = NSFont(name: name, size: size) {
            return f
        }
        // Fallback — bold system font approximates MS Sans Serif weight
        return bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    }

    // MARK: - Bevels

    /// Raised 3D bevel (Win 3.1 button/window border): white top-left, dark+black bottom-right.
    /// thickness=1 → single line; thickness=2 → classic double border.
    static func drawRaisedBevel(_ rect: NSRect, thickness: CGFloat = 2) {
        drawBevel(rect, topLeft: white, bottomRightInner: darkGray, bottomRightOuter: black,
                  topLeftInner: lightGray, thickness: thickness)
    }

    /// Sunken 3D bevel (pressed / well): dark top-left, white bottom-right.
    static func drawSunkenBevel(_ rect: NSRect, thickness: CGFloat = 2) {
        drawBevel(rect, topLeft: darkGray, bottomRightInner: white, bottomRightOuter: white,
                  topLeftInner: black, thickness: thickness)
    }

    private static func drawBevel(_ rect: NSRect, topLeft: NSColor, bottomRightInner: NSColor,
                                  bottomRightOuter: NSColor, topLeftInner: NSColor, thickness: CGFloat) {
        let r = rect
        // Outer edges
        // Top + Left = highlight
        topLeft.setFill()
        NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()       // top
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()          // left
        // Bottom + Right = outer shadow (black)
        bottomRightOuter.setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()           // bottom
        NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()      // right

        if thickness >= 2 {
            // Inner edges
            topLeftInner.setFill()
            NSRect(x: r.minX + 1, y: r.maxY - 2, width: r.width - 2, height: 1).fill()  // top inner
            NSRect(x: r.minX + 1, y: r.minY + 1, width: 1, height: r.height - 2).fill() // left inner
            bottomRightInner.setFill()
            NSRect(x: r.minX + 1, y: r.minY + 1, width: r.width - 2, height: 1).fill()  // bottom inner
            NSRect(x: r.maxX - 2, y: r.minY + 1, width: 1, height: r.height - 2).fill() // right inner
        }
    }

    // MARK: - Window sizing frame

    /// Draw the classic Win 3.1 resizable window border: a thick raised gray band
    /// with corner division marks (the sizing-handle look). The interior (client) is
    /// left untouched — the caller fills it (white) and draws the title bar inside.
    static func drawWindowFrame(_ rect: NSRect, border: CGFloat) {
        let r = rect
        // Fill the four border bands with face gray
        face.setFill()
        NSRect(x: r.minX, y: r.maxY - border, width: r.width, height: border).fill()  // top
        NSRect(x: r.minX, y: r.minY, width: r.width, height: border).fill()           // bottom
        NSRect(x: r.minX, y: r.minY, width: border, height: r.height).fill()          // left
        NSRect(x: r.maxX - border, y: r.minY, width: border, height: r.height).fill() // right

        // Outer raised edge (highlight top/left, shadow bottom/right)
        white.setFill()
        NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()
        black.setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
        NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()

        // Inner edge at the client boundary (recessed)
        let inX = r.minX + border, inY = r.minY + border
        let inW = r.width - 2 * border, inH = r.height - 2 * border
        darkGray.setFill()
        NSRect(x: inX - 1, y: inY + inH, width: inW + 2, height: 1).fill()  // top inner shadow
        NSRect(x: inX - 1, y: inY - 1, width: 1, height: inH + 2).fill()    // left inner shadow
        white.setFill()
        NSRect(x: inX - 1, y: inY - 1, width: inW + 2, height: 1).fill()    // bottom inner hi
        NSRect(x: inX + inW, y: inY - 1, width: 1, height: inH + 2).fill()  // right inner hi

        // Corner division marks (dark lines crossing the band a fixed distance from each corner)
        let c: CGFloat = 16
        black.setFill()
        // top & bottom bands → vertical marks
        for x in [r.minX + c, r.maxX - c - 1] {
            NSRect(x: x, y: r.maxY - border, width: 1, height: border).fill()
            NSRect(x: x, y: r.minY, width: 1, height: border).fill()
        }
        // left & right bands → horizontal marks
        for y in [r.minY + c, r.maxY - c - 1] {
            NSRect(x: r.minX, y: y, width: border, height: 1).fill()
            NSRect(x: r.maxX - border, y: y, width: border, height: 1).fill()
        }
    }

    // MARK: - Title bar

    /// Draw a Win 3.1 title bar (solid navy when active). Returns nothing — caller draws text/buttons.
    static func drawTitleBar(_ rect: NSRect, active: Bool) {
        (active ? activeTitle : inactiveTitle).setFill()
        rect.fill()
    }

    /// Draw the system-menu box (left of title bar): a raised button with a horizontal "minus" bar.
    static func drawSystemBox(_ rect: NSRect) {
        face.setFill(); rect.fill()
        drawRaisedBevel(rect, thickness: 2)
        // Center minus bar (the "window menu" glyph)
        black.setFill()
        let barW = rect.width * 0.5
        let barH: CGFloat = 2
        NSRect(x: rect.midX - barW / 2, y: rect.midY - barH / 2, width: barW, height: barH).fill()
        // small white highlight under it
        white.setFill()
        NSRect(x: rect.midX - barW / 2, y: rect.midY - barH / 2 - 1, width: barW, height: 1).fill()
    }

    /// Draw a title-bar button (minimize ▼ or maximize ▲ / restore) as a raised box with glyph.
    enum CaptionGlyph { case minimize, maximize, restore }
    static func drawCaptionButton(_ rect: NSRect, glyph: CaptionGlyph) {
        face.setFill(); rect.fill()
        drawRaisedBevel(rect, thickness: 2)
        black.setFill()
        switch glyph {
        case .minimize:
            // Down triangle
            let cx = rect.midX, cy = rect.minY + rect.height * 0.38
            let s: CGFloat = rect.width * 0.22
            let p = NSBezierPath()
            p.move(to: NSPoint(x: cx - s, y: cy + s * 0.7))
            p.line(to: NSPoint(x: cx + s, y: cy + s * 0.7))
            p.line(to: NSPoint(x: cx, y: cy - s * 0.7))
            p.close(); p.fill()
        case .maximize:
            // Up triangle
            let cx = rect.midX, cy = rect.midY
            let s: CGFloat = rect.width * 0.22
            let p = NSBezierPath()
            p.move(to: NSPoint(x: cx - s, y: cy - s * 0.7))
            p.line(to: NSPoint(x: cx + s, y: cy - s * 0.7))
            p.line(to: NSPoint(x: cx, y: cy + s * 0.7))
            p.close(); p.fill()
        case .restore:
            // Authentic Win 3.1 restore glyph: a small up-triangle (▲) stacked over a
            // down-triangle (▼), clearly separated and centered in the button.
            let cx = rect.midX
            let s: CGFloat = rect.width * 0.20
            let gap: CGFloat = 1
            // Up triangle (top half) — apex points up
            let upBase = rect.midY + gap
            let up = NSBezierPath()
            up.move(to: NSPoint(x: cx - s, y: upBase))
            up.line(to: NSPoint(x: cx + s, y: upBase))
            up.line(to: NSPoint(x: cx, y: upBase + s)); up.close(); up.fill()
            // Down triangle (bottom half) — apex points down
            let dnBase = rect.midY - gap
            let dn = NSBezierPath()
            dn.move(to: NSPoint(x: cx - s, y: dnBase))
            dn.line(to: NSPoint(x: cx + s, y: dnBase))
            dn.line(to: NSPoint(x: cx, y: dnBase - s)); dn.close(); dn.fill()
        }
    }

    // MARK: - Scrollbars

    static let scrollbarThickness: CGFloat = 16

    /// Light-gray scrollbar track.
    static func drawScrollTrack(_ rect: NSRect) {
        NSColor(white: 0.78, alpha: 1).setFill()
        rect.fill()
    }

    enum ArrowDir { case up, down, left, right }

    /// A scrollbar end-arrow button (raised, with a directional triangle).
    static func drawScrollArrow(_ rect: NSRect, dir: ArrowDir) {
        face.setFill(); rect.fill()
        drawRaisedBevel(rect, thickness: 2)
        black.setFill()
        let cx = rect.midX, cy = rect.midY
        let s = rect.width * 0.20
        let p = NSBezierPath()
        switch dir {
        case .up:
            p.move(to: NSPoint(x: cx - s, y: cy - s * 0.6))
            p.line(to: NSPoint(x: cx + s, y: cy - s * 0.6))
            p.line(to: NSPoint(x: cx, y: cy + s * 0.8))
        case .down:
            p.move(to: NSPoint(x: cx - s, y: cy + s * 0.6))
            p.line(to: NSPoint(x: cx + s, y: cy + s * 0.6))
            p.line(to: NSPoint(x: cx, y: cy - s * 0.8))
        case .left:
            p.move(to: NSPoint(x: cx + s * 0.6, y: cy - s))
            p.line(to: NSPoint(x: cx + s * 0.6, y: cy + s))
            p.line(to: NSPoint(x: cx - s * 0.8, y: cy))
        case .right:
            p.move(to: NSPoint(x: cx - s * 0.6, y: cy - s))
            p.line(to: NSPoint(x: cx - s * 0.6, y: cy + s))
            p.line(to: NSPoint(x: cx + s * 0.8, y: cy))
        }
        p.close(); p.fill()
    }

    /// The draggable scrollbar thumb (raised gray box).
    static func drawScrollThumb(_ rect: NSRect) {
        face.setFill(); rect.fill()
        drawRaisedBevel(rect, thickness: 2)
    }

    /// Draw text in the Win 3.1 UI font, left-aligned, vertically centered, no antialiasing for crispness.
    static func drawText(_ string: String, in rect: NSRect, size: CGFloat,
                         color: NSColor, centered: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.alignment = centered ? .center : .left
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font(size: size),
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        let attr = NSAttributedString(string: string, attributes: attrs)
        let textH = attr.size().height
        let y = rect.minY + (rect.height - textH) / 2
        attr.draw(in: NSRect(x: rect.minX, y: y, width: rect.width, height: textH))
    }
}
