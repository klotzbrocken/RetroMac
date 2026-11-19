import AppKit

/// AmigaOS 4.1's window and screen chrome (AmigaOne, 2008), drawn point for point from the
/// screenshots of that install: the active "Execute a file" requester, the inactive Post-Install
/// window and the Workbench screen bar. The bars are banded, not smooth: the reference ran a
/// 16-bit screen, and the bands are kept row for row. The gadgets are drawn here too, never
/// taken from a theme pack. Everything assumes a flipped view (y runs down).
enum AmigaChrome {

    /// Title bar: its top edge, 29 rows of face and the dark line under it.
    static let barHeight: CGFloat = 31
    /// The Workbench screen bar: 30 rows and a dark line.
    static let screenBarHeight: CGFloat = 31
    /// Window sides, outside in: edge, light, face, shade, edge.
    static let frameWidth: CGFloat = 5
    /// The bottom border of a window with a sizer: the sizer sits in it, 6 pt from the corner.
    static let sizerBorderHeight: CGFloat = 24
    /// The rounding of the title bar's top corners (8 pt on the reference).
    static let cornerRadius: CGFloat = 8

    static func titleFont() -> NSFont { RetroFonts.dejaVu(13) }

    static func rgb(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255,
                blue: CGFloat(v & 255) / 255, alpha: a)
    }
    private static func bands(_ spec: [(UInt32, Int)]) -> [NSColor] {
        spec.flatMap { Array(repeating: rgb($0.0), count: $0.1) }
    }

    /// The active bar, top to bottom (Titelleiste-aktiv.png, column 150).
    static let activeRows = bands([(0x1A244D, 1), (0x90B4E6, 1), (0x5C87C2, 1), (0x4D7AB7, 3), (0x5C87C2, 5),
                                   (0x638CC4, 1), (0x648EC8, 3), (0x749BD2, 3), (0x86AADC, 3), (0x90B4E6, 3),
                                   (0xAFCBED, 4), (0x90B4E6, 1), (0x5576AE, 1), (0x1A244D, 1)])
    /// The inactive bar (Titelleiste-inaktiv.png, column 300).
    static let inactiveRows = bands([(0x424242, 1), (0xC7CBCA, 1), (0xB7B9BA, 1), (0xACAEB0, 6), (0xB4B2B2, 1),
                                     (0xB7B9BA, 1), (0xB5BAC3, 1), (0xB7B9BA, 2), (0xB9C0C2, 5), (0xC4C8C8, 1),
                                     (0xC7CBCA, 2), (0xCDD0D0, 1), (0xD4D4D3, 1), (0xD6D7D7, 2), (0xDDDFE2, 1),
                                     (0xE3E4E3, 1), (0xCDD0D0, 1), (0x8C8D90, 1), (0x424242, 1)])
    /// The Workbench screen bar (Screenbar.png, column 400).
    static let screenRows = bands([(0xF9F9F9, 1), (0xF0F0EE, 4), (0xEAEAEA, 4), (0xE8E6E5, 4), (0xE0E0E0, 3),
                                   (0xDEDEDC, 4), (0xDCDCDB, 4), (0xD6D7D7, 4), (0xD4D2D2, 2), (0x616364, 1)])

    /// Window sides, outside in (PostInstall.png: the requester's left edge, the Post-Install window's).
    static func frameColors(active: Bool) -> [NSColor] {
        (active ? [0x1A244D, 0x92BFFF, 0x648EC8, 0x204D8D, 0x1A244D] : [0x424242, 0xDCDCDB, 0xC7CBCA, 0x8C8D90, 0x424242]).map { rgb($0) }
    }

    /// Draws `rows` one per point down `r`; a taller or shorter rect keeps the edge rows and
    /// stretches the middle, so the borders stay one point.
    static func drawBands(_ rows: [NSColor], in r: NSRect) {
        let n = rows.count, h = Int(r.height.rounded())
        guard n > 2, h > 0 else { return }
        for y in 0..<h {
            let i: Int
            if y == 0 { i = 0 } else if y == h - 1 { i = n - 1 }
            else { i = 1 + min(n - 3, Int(Double(y - 1) * Double(n - 2) / Double(max(1, h - 2)))) }
            rows[i].setFill()
            NSRect(x: r.minX, y: r.minY + CGFloat(y), width: r.width, height: 1).fill()
        }
    }

    /// A window's title bar: the bands, a light column inside the left edge and a shaded one
    /// inside the right, the two top corners rounded with the edge colour following the curve.
    static func drawTitleBar(in b: NSRect, active: Bool) {
        let rows = active ? activeRows : inactiveRows
        NSGraphicsContext.saveGraphicsState()
        let outline = topCorners(b, radius: cornerRadius)
        outline.addClip()
        drawBands(rows, in: b)
        rows[1].setFill(); NSRect(x: b.minX + 1, y: b.minY + 1, width: 1, height: b.height - 2).fill()
        rows[rows.count - 2].setFill(); NSRect(x: b.maxX - 2, y: b.minY + 1, width: 1, height: b.height - 2).fill()
        rows[0].setStroke()
        let edge = topCorners(b.insetBy(dx: 0.5, dy: 0.5), radius: cornerRadius - 0.5)
        edge.lineWidth = 1
        edge.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The title, black DejaVu Sans 13, left-aligned from `left`, cut off before `right`.
    static func drawTitle(_ title: String, in b: NSRect, left: CGFloat, right: CGFloat) {
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: titleFont(), .foregroundColor: NSColor.black, .paragraphStyle: para]
        let h = (title as NSString).size(withAttributes: attrs).height
        // Grey antialiasing only: AmigaOS had no font smoothing, and macOS's thickens the stems.
        NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)
        (title as NSString).draw(in: NSRect(x: left, y: b.minY + ((b.height - h) / 2).rounded(), width: max(0, right - left), height: h),
                                 withAttributes: attrs)
    }

    /// The screen bar: bands across, the ball and the title on the left, the screen-depth gadget
    /// right (10 pt in, as on the reference).
    static func drawScreenBar(in b: NSRect, title: String, depthPressed: Bool) {
        drawBands(screenRows, in: b)
        drawBall(in: NSRect(x: b.minX + 1, y: b.minY + 8, width: 14, height: 14), shadow: true)
        drawTitle(title, in: NSRect(x: b.minX, y: b.minY, width: b.width, height: b.height - 1), left: b.minX + 21,
                  right: screenDepthRect(in: b).minX - 6)
        drawGadget(.depth, in: screenDepthRect(in: b), tone: .screen, pressed: depthPressed)
    }
    static func screenDepthRect(in b: NSRect) -> NSRect {
        let s = gadgetSize(.depth)
        return NSRect(x: b.maxX - 9 - s.width, y: b.minY + ((b.height - 1 - s.height) / 2).rounded(), width: s.width, height: s.height)
    }

    // MARK: Gadgets

    enum Gadget { case close, iconify, zoom, depth, sizer }
    /// Which bar a gadget sits on: its outline is a shade bluer on the active one.
    enum Tone { case active, inactive, screen }

    /// The gadget's box including its one-point emboss ring.
    static func gadgetSize(_ g: Gadget) -> NSSize {
        switch g {
        case .close: return NSSize(width: 10, height: 10)
        case .iconify, .zoom, .depth: return NSSize(width: 16, height: 16)
        case .sizer: return NSSize(width: 14, height: 14)
        }
    }

    /// Gadget rects on a title bar of width `w`: close 13 pt in on the left, then on the right
    /// from the outside in depth, zoom, iconify, 3 pt apart (the reference's 18 pt pitch),
    /// 12 pt in from the right edge. Only the gadgets in `kinds` get a place.
    static func titleGadgets(width w: CGFloat, height h: CGFloat = barHeight, kinds: Set<Gadget>) -> [(Gadget, NSRect)] {
        var out: [(Gadget, NSRect)] = []
        if kinds.contains(.close) {
            let s = gadgetSize(.close)
            out.append((.close, NSRect(x: 12, y: ((h - s.height) / 2).rounded(), width: s.width, height: s.height)))
        }
        var x = w - 12
        for g in [Gadget.depth, .zoom, .iconify] where kinds.contains(g) {
            let s = gadgetSize(g)
            x -= s.width
            out.append((g, NSRect(x: x, y: ((h - s.height) / 2).rounded(), width: s.width, height: s.height)))
            x -= 3
        }
        return out
    }

    /// One gadget at `r` (its emboss box). Released: a dark outline with a shadow ring above
    /// and left and a light ring below and right. Pressed: a white glow round it and the face
    /// gone translucent, as AmigaOS draws the selected state.
    static func drawGadget(_ g: Gadget, in r: NSRect, tone: Tone, pressed: Bool) {
        let ink = rgb(tone == .active ? 0x3C464A : (tone == .inactive ? 0x45464B : 0x424242))
        if pressed { glow(around: g, in: r) }
        switch g {
        case .close:
            let box = NSRect(x: r.minX + 1, y: r.minY + 1, width: 8, height: 8)
            emboss(box, pressed: pressed)
            outlined(box, ink: ink, fill: .light, pressed: pressed)
        case .zoom, .iconify:
            let box = NSRect(x: r.minX + 1, y: r.minY + 1, width: 14, height: 14)
            emboss(box, pressed: pressed)
            outlined(box, ink: ink, fill: .gray, pressed: pressed)
            // The small window: top-left for zoom, bottom-left for iconify, 7 pt square.
            let small = g == .zoom ? NSRect(x: box.minX, y: box.minY, width: 7, height: 7)
                                   : NSRect(x: box.minX, y: box.maxY - 7, width: 7, height: 7)
            outlined(small, ink: ink, fill: .light, pressed: pressed)
        case .depth:
            let back = NSRect(x: r.minX + 1, y: r.minY + 1, width: 10, height: 10)
            let front = NSRect(x: r.minX + 5, y: r.minY + 5, width: 10, height: 10)
            emboss(back.union(front), pressed: pressed, shape: [back, front])
            // Pressed, the windows swap: the back one comes to the front.
            if pressed {
                outlined(front, ink: ink, fill: .gray, pressed: true)
                outlined(back, ink: ink, fill: .light, pressed: true)
            } else {
                outlined(back, ink: ink, fill: .gray, pressed: false)
                outlined(front, ink: ink, fill: .light, pressed: false)
            }
        case .sizer:
            drawSizer(in: r, ink: ink, pressed: pressed)
        }
    }

    private enum Face { case light, gray }

    /// Face rows top to bottom, measured inside the closer (light) and the zoom gadget (grey);
    /// the two columns at the sides run a step lighter.
    private static func faceRows(_ f: Face, count n: Int) -> [NSColor] {
        let (top, a, z): (UInt32, UInt32, UInt32) = f == .light ? (0xDBE3E1, 0xCDD0D0, 0xEAF6F4) : (0x9D9FA3, 0x9D9FA3, 0xDCDCDB)
        return (0..<max(1, n)).map { i in
            if i == 0 { return rgb(top) }
            let t = n > 2 ? CGFloat(i - 1) / CGFloat(n - 2) : 1
            return lerp(a, z, t)
        }
    }
    private static func lerp(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> NSColor {
        func c(_ v: UInt32, _ s: UInt32) -> CGFloat { CGFloat(v >> s & 255) / 255 }
        return NSColor(srgbRed: c(a, 16) + (c(b, 16) - c(a, 16)) * t, green: c(a, 8) + (c(b, 8) - c(a, 8)) * t,
                       blue: c(a, 0) + (c(b, 0) - c(a, 0)) * t, alpha: 1)
    }

    private static func outlined(_ box: NSRect, ink: NSColor, fill: Face, pressed: Bool) {
        let inner = box.insetBy(dx: 1, dy: 1)
        let rows = faceRows(fill, count: Int(inner.height))
        let alpha: CGFloat = pressed ? 0.55 : 1   // the selected face lets the bar show through
        for (i, c) in rows.enumerated() {
            c.withAlphaComponent(alpha).setFill()
            NSRect(x: inner.minX, y: inner.minY + CGFloat(i), width: inner.width, height: 1).fill()
        }
        if !pressed, inner.width > 3 {
            NSColor(white: 1, alpha: 0.35).setFill()
            NSRect(x: inner.minX, y: inner.minY + 1, width: 1, height: inner.height - 1).fill()
            NSRect(x: inner.maxX - 1, y: inner.minY + 1, width: 1, height: inner.height - 1).fill()
        }
        ink.setFill()
        NSRect(x: box.minX, y: box.minY, width: box.width, height: 1).fill()
        NSRect(x: box.minX, y: box.maxY - 1, width: box.width, height: 1).fill()
        NSRect(x: box.minX, y: box.minY, width: 1, height: box.height).fill()
        NSRect(x: box.maxX - 1, y: box.minY, width: 1, height: box.height).fill()
    }

    /// The bevel round a released gadget: a darker ring above and left, a lighter one below and
    /// right (on the active bar #466498 over #5C87C2 and #86AADC over #648EC8).
    private static func emboss(_ box: NSRect, pressed: Bool, shape: [NSRect]? = nil) {
        guard !pressed else { return }
        let dark = NSColor(white: 0, alpha: 0.2), light = NSColor(white: 1, alpha: 0.3)
        for b in shape ?? [box] {
            dark.setFill()
            NSRect(x: b.minX - 1, y: b.minY - 1, width: b.width + 1, height: 1).fill()
            NSRect(x: b.minX - 1, y: b.minY, width: 1, height: b.height).fill()
            light.setFill()
            NSRect(x: b.minX, y: b.maxY, width: b.width + 1, height: 1).fill()
            NSRect(x: b.maxX, y: b.minY - 1, width: 1, height: b.height + 1).fill()
        }
    }

    /// The selected state's halo: three soft rings of white round the gadget.
    private static func glow(around g: Gadget, in r: NSRect) {
        for (i, a) in [(3, 0.18), (2, 0.35), (1, 0.75)] as [(CGFloat, CGFloat)] {
            NSColor(white: 1, alpha: a).setFill()
            NSBezierPath(roundedRect: r.insetBy(dx: 1 - i, dy: 1 - i), xRadius: i + 1, yRadius: i + 1).fill()
        }
    }

    /// The sizer: a right triangle in the bottom-right corner, its hypotenuse a staircase.
    private static func drawSizer(in r: NSRect, ink: NSColor, pressed: Bool) {
        let n = 12
        let o = NSPoint(x: r.minX + 1, y: r.minY + 1)
        let rows = faceRows(.gray, count: n)
        for y in 0..<n {
            let from = n - 1 - y   // the staircase: row y starts at column n-1-y
            if !pressed, from > 0 {
                NSColor(white: 0, alpha: 0.2).setFill()
                NSRect(x: o.x + CGFloat(from) - 1, y: o.y + CGFloat(y), width: 1, height: 1).fill()
            }
            (y == n - 2 ? rgb(0xD6D7D7) : rows[y]).withAlphaComponent(pressed ? 0.55 : 1).setFill()
            NSRect(x: o.x + CGFloat(from), y: o.y + CGFloat(y), width: CGFloat(n - from), height: 1).fill()
            ink.setFill()
            NSRect(x: o.x + CGFloat(from), y: o.y + CGFloat(y), width: 1, height: 1).fill()
            NSRect(x: o.x + CGFloat(n - 1), y: o.y + CGFloat(y), width: 1, height: 1).fill()
        }
        ink.setFill(); NSRect(x: o.x, y: o.y + CGFloat(n - 1), width: CGFloat(n), height: 1).fill()
        if !pressed {
            NSColor(white: 1, alpha: 0.3).setFill()
            NSRect(x: o.x, y: o.y + CGFloat(n), width: CGFloat(n), height: 1).fill()
            NSRect(x: o.x + CGFloat(n), y: o.y - 1, width: 1, height: CGFloat(n + 1)).fill()
        }
    }

    /// A window's frame below its title bar: the five-point sides and, with a sizer, the
    /// 24-point bottom border with the sizer 6 pt in from the corner; without, a 5-point one.
    static func drawFrame(in b: NSRect, active: Bool, sizer: Bool, sizerPressed: Bool = false) {
        let c = frameColors(active: active)
        let bottom = sizer ? sizerBorderHeight : frameWidth
        for (i, col) in c.enumerated() {
            col.setFill()
            let d = CGFloat(i)
            NSRect(x: b.minX + d, y: b.minY, width: 1, height: b.height - d).fill()
            NSRect(x: b.maxX - 1 - d, y: b.minY, width: 1, height: b.height - d).fill()
        }
        // The bottom border: edge at the bottom, the light row at its top, the face between.
        let bb = NSRect(x: b.minX, y: b.maxY - bottom, width: b.width, height: bottom)
        c[2].setFill(); NSRect(x: bb.minX + 4, y: bb.minY, width: bb.width - 8, height: bb.height - 1).fill()
        c[4].setFill(); NSRect(x: bb.minX + 4, y: bb.minY, width: bb.width - 8, height: 1).fill()
        c[1].setFill(); NSRect(x: bb.minX + 4, y: bb.minY + 1, width: bb.width - 8, height: 1).fill()
        c[3].setFill(); NSRect(x: bb.minX + 1, y: bb.maxY - 2, width: bb.width - 2, height: 1).fill()
        c[0].setFill(); NSRect(x: bb.minX, y: bb.maxY - 1, width: bb.width, height: 1).fill()
        if sizer { drawGadget(.sizer, in: sizerRect(in: b), tone: active ? .active : .inactive, pressed: sizerPressed) }
    }
    static func sizerRect(in b: NSRect) -> NSRect {
        let s = gadgetSize(.sizer)
        return NSRect(x: b.maxX - 6 - s.width + 1, y: b.maxY - 6 - s.height + 1, width: s.width, height: s.height)
    }

    /// A small Boing ball, the screen bar's emblem: red and white checks bent round a sphere,
    /// lit from the top left, and (on the bar) a grey shadow under it, as on Screenbar.png.
    static func drawBall(in r: NSRect, shadow: Bool = false) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if shadow {
            NSColor(white: 0.42, alpha: 0.75).setFill()
            NSBezierPath(ovalIn: NSRect(x: r.minX + r.width * 0.12, y: r.maxY - r.height * 0.3,
                                        width: r.width, height: r.height * 0.42)).fill()
        }
        ctx.saveGState()
        ctx.addEllipse(in: r); ctx.clip()
        let n = Int(max(8, r.width * 2))
        let step = r.width / CGFloat(n)
        for j in 0..<n { for i in 0..<n {
            let cell = NSRect(x: r.minX + CGFloat(i) * step, y: r.minY + CGFloat(j) * step, width: step + 0.3, height: step + 0.3)
            let u = (cell.midX - r.midX) / (r.width / 2), v = (cell.midY - r.midY) / (r.height / 2)
            guard u * u + v * v <= 1.05 else { continue }
            // The sphere tilted a little to the right, as the ball always leans.
            let lat = asin(max(-1, min(1, v))), lon = asin(max(-1, min(1, u / max(0.15, cos(lat))))) + 0.3
            let red = (Int(floor(lon / (.pi / 7) + 10)) + Int(floor(lat / (.pi / 7) + 10))) & 1 == 0
            // Lit from the top left: a highlight there, the lower right in shade.
            let light = max(0, min(1, 0.55 - 0.45 * u - 0.55 * v + 0.35 * sqrt(max(0, 1 - u * u - v * v))))
            let base: (CGFloat, CGFloat, CGFloat) = red ? (0.80, 0.10, 0.13) : (0.96, 0.94, 0.94)
            let k = 0.45 + 0.75 * light
            NSColor(srgbRed: min(1, base.0 * k + 0.15 * light), green: min(1, base.1 * k + 0.15 * light),
                    blue: min(1, base.2 * k + 0.15 * light), alpha: 1).setFill()
            cell.fill()
        }}
        ctx.restoreGState()
    }

    /// The bar's outline with its two top corners rounded (flipped: the top is minY).
    static func topCorners(_ b: NSRect, radius r: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: b.minX, y: b.maxY))
        p.line(to: NSPoint(x: b.minX, y: b.minY + r))
        p.appendArc(from: NSPoint(x: b.minX, y: b.minY), to: NSPoint(x: b.minX + r, y: b.minY), radius: r)
        p.line(to: NSPoint(x: b.maxX - r, y: b.minY))
        p.appendArc(from: NSPoint(x: b.maxX, y: b.minY), to: NSPoint(x: b.maxX, y: b.minY + r), radius: r)
        p.line(to: NSPoint(x: b.maxX, y: b.maxY))
        p.close()
        return p
    }

    /// Which gadget a title-bar gadget is in the shared button vocabulary, and back.
    static func kind(_ g: Gadget) -> ChromeButtonKind {
        switch g { case .close: return .close; case .iconify: return .minimize; case .zoom: return .zoom
        case .depth: return .depth; case .sizer: return .zoom }
    }

    /// The depth gadget's rule: the window at the front goes to the back, any other comes to the front.
    static func depthSendsBack(isFrontmost: Bool) -> Bool { isFrontmost }
}
