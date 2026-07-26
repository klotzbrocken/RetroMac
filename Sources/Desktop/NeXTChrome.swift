import AppKit

/// Shared NeXTSTEP drawing primitives — the chiseled bevel, the four-grey palette, the title bar
/// and the title-bar button boxes. Used by the widget/WebApp window chrome (`WebAppChromeView`)
/// and the vertical Workspace menu, so the whole theme stays pixel-consistent.
///
/// Everything is the classic 2-bit MegaPixel ramp (0 / ⅓ / ⅔ / 1 = black / #555 / #AAA / white).
/// The signature look is a 2px chisel: white on the top+left edges, dark on the bottom+right,
/// square-cornered. Measured from the reference screenshot; matches the OpenStep UI guidelines.
enum NeXTChrome {

    // MARK: Palette (the canonical NeXT greys)
    static let black     = NSColor(srgbRed: 0,     green: 0,     blue: 0,     alpha: 1)
    static let darkGray  = NSColor(srgbRed: 0.333, green: 0.333, blue: 0.333, alpha: 1)  // #555 main-window bar, shadow edge
    static let face      = NSColor(srgbRed: 0.667, green: 0.667, blue: 0.667, alpha: 1)  // #AAA window/menu/button face
    static let white     = NSColor(srgbRed: 1,     green: 1,     blue: 1,     alpha: 1)
    static let desktop   = NSColor(srgbRed: 0x50/255.0, green: 0x51/255.0, blue: 0x70/255.0, alpha: 1) // #505170

    static func titleFont(_ size: CGFloat = 13) -> NSFont {
        NSFont(name: "Helvetica-Bold", size: size) ?? .boldSystemFont(ofSize: size)
    }
    static func labelFont(_ size: CGFloat = 13) -> NSFont {
        NSFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size)
    }

    // MARK: Chiseled bevel

    /// Draw a 2px chiseled bevel around `rect` (edges only; does not fill the interior).
    /// `raised` = white top-left / dark bottom-right (a button or tile popping out);
    /// `raised == false` inverts it (a pressed button or a sunken well).
    ///
    /// `flipped` must match the drawing context: `true` for a flipped NSView (y grows DOWN, so the
    /// visual top edge is at `minY`, as in `WebAppChromeView`), `false` for a standard y-up context.
    static func bevel(_ rect: NSRect, raised: Bool = true, width: CGFloat = 2, flipped: Bool, in ctx: CGContext) {
        let light = raised ? white : darkGray
        let dark  = raised ? darkGray : white
        let topEdge = NSRect(x: rect.minX, y: flipped ? rect.minY : rect.maxY - width, width: rect.width, height: width)
        let botEdge = NSRect(x: rect.minX, y: flipped ? rect.maxY - width : rect.minY, width: rect.width, height: width)
        let leftEdge  = NSRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
        let rightEdge = NSRect(x: rect.maxX - width, y: rect.minY, width: width, height: rect.height)
        ctx.saveGState()
        light.setFill(); ctx.fill(topEdge); ctx.fill(leftEdge)     // top + left = light
        dark.setFill();  ctx.fill(botEdge); ctx.fill(rightEdge)    // bottom + right = dark
        ctx.restoreGState()
    }

    /// Fill `rect` with the #AAA face and stroke a raised/sunken chisel around it.
    static func tile(_ rect: NSRect, raised: Bool = true, flipped: Bool, in ctx: CGContext) {
        face.setFill(); ctx.fill(rect)
        bevel(rect, raised: raised, flipped: flipped, in: ctx)
    }

    // The authentic NeXT app-tile colours, measured from the shipped icon tiles: a grey-violet
    // face that darkens toward the bottom, a 1px white highlight on the top+left edges and a dark
    // edge on the bottom+right. `dockTile` reproduces that so real app icons match the icon set.
    static let tileFaceTop    = NSColor(srgbRed: 0x96/255.0, green: 0x96/255.0, blue: 0xA4/255.0, alpha: 1)
    static let tileFaceBottom = NSColor(srgbRed: 0x70/255.0, green: 0x70/255.0, blue: 0x7E/255.0, alpha: 1)
    static let tileEdgeDark   = NSColor(srgbRed: 0x3D/255.0, green: 0x3E/255.0, blue: 0x45/255.0, alpha: 1)

    /// Draw the authentic NeXT app tile (grey-violet gradient face, white top-left highlight, dark
    /// bottom-right edge) so a real app icon composited on top matches the shipped dock tiles.
    static func dockTile(_ rect: NSRect, flipped: Bool, in ctx: CGContext) {
        ctx.saveGState()
        // Vertical gradient: lighter at the visual top, darker at the bottom.
        let g = NSGradient(colors: [tileFaceTop, tileFaceBottom])!
        g.draw(in: NSBezierPath(rect: rect), angle: flipped ? -90 : 90)
        white.setFill()
        ctx.fill(NSRect(x: rect.minX, y: flipped ? rect.minY : rect.maxY - 1, width: rect.width, height: 1))  // top
        ctx.fill(NSRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height))                            // left
        tileEdgeDark.setFill()
        ctx.fill(NSRect(x: rect.minX, y: flipped ? rect.maxY - 2 : rect.minY, width: rect.width, height: 2))   // bottom
        ctx.fill(NSRect(x: rect.maxX - 2, y: rect.minY, width: 2, height: rect.height))                        // right
        ctx.restoreGState()
    }

    // MARK: Title bar

    enum WindowState { case key, main, inactive }

    /// NeXT title bar: black (key), #555 (main), #AAA (inactive). Centered Helvetica-Bold title.
    /// `bar` is in the view's own (flipped) coordinate space with the bar at the top.
    static func titleBar(_ bar: NSRect, title: String, state: WindowState, in ctx: CGContext) {
        let fill: NSColor
        let textColor: NSColor
        switch state {
        case .key:      fill = black;    textColor = white
        case .main:     fill = darkGray; textColor = white
        case .inactive: fill = face;     textColor = black
        }
        fill.setFill(); ctx.fill(bar)
        let p = NSMutableParagraphStyle(); p.alignment = .center; p.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: titleFont(13), .foregroundColor: textColor, .paragraphStyle: p]
        let size = (title as NSString).size(withAttributes: attrs)
        let ty = bar.midY - size.height / 2
        (title as NSString).draw(in: NSRect(x: bar.minX + 24, y: ty, width: bar.width - 48, height: size.height),
                                 withAttributes: attrs)
    }

    // MARK: Title-bar buttons

    enum ButtonKind { case miniaturize, close, closeBroken }

    /// A NeXT title-bar button: a raised #AAA tile with a glyph. Miniaturize = small inset square;
    /// close = an X (or a broken X when the document is unsaved). `pressed` sinks the bevel.
    static func button(_ rect: NSRect, kind: ButtonKind, pressed: Bool = false, flipped: Bool, in ctx: CGContext) {
        tile(rect, raised: !pressed, flipped: flipped, in: ctx)
        let inset = rect.insetBy(dx: 4, dy: 4)
        ctx.saveGState()
        switch kind {
        case .miniaturize:
            // a small filled square in the lower area (the "shrink to miniwindow" mark)
            black.setStroke()
            let s = min(inset.width, inset.height) * 0.62
            let sq = NSRect(x: rect.midX - s/2, y: rect.midY - s/2, width: s, height: s)
            let p = NSBezierPath(rect: sq); p.lineWidth = 1.5; p.stroke()
        case .close, .closeBroken:
            black.setStroke()
            let p = NSBezierPath(); p.lineWidth = 1.5
            if kind == .close {
                p.move(to: NSPoint(x: inset.minX, y: inset.minY)); p.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
                p.move(to: NSPoint(x: inset.minX, y: inset.maxY)); p.line(to: NSPoint(x: inset.maxX, y: inset.minY))
            } else {
                // broken X: the two strokes are notched at the centre (unsaved-document mark)
                let g: CGFloat = 2
                p.move(to: NSPoint(x: inset.minX, y: inset.minY)); p.line(to: NSPoint(x: inset.midX - g, y: inset.midY - g))
                p.move(to: NSPoint(x: inset.midX + g, y: inset.midY + g)); p.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
                p.move(to: NSPoint(x: inset.minX, y: inset.maxY)); p.line(to: NSPoint(x: inset.maxX, y: inset.minY))
            }
            p.stroke()
        }
        ctx.restoreGState()
    }
}
