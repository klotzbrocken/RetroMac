import AppKit

/// Colours of the screens, straight from the hardware palettes.
///
/// The 9x blue is the same `#0000A8` the era used for an active title bar, which the repo already
/// carries as `Win31Chrome.activeTitle` — the two are the same VGA colour, and taking it from one
/// place keeps them that way.
enum CrashPalette {
    static let ninetyXBlue = CGColor(srgbRed: 0x00/255, green: 0x00/255, blue: 0xA8/255, alpha: 1)
    static let ninetyXText = CGColor(srgbRed: 0xA8/255, green: 0xA8/255, blue: 0xA8/255, alpha: 1)
    /// The plaque at the top of the 9x screen is the text colour with the blue punched out of it.
    static let ninetyXPlaqueBG = ninetyXText
    static let ninetyXPlaqueFG = ninetyXBlue

    /// Windows 2000 through 7 moved a shade darker.
    static let ntBlue = CGColor(srgbRed: 0x00/255, green: 0x00/255, blue: 0x80/255, alpha: 1)
    static let ntText = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    static let consoleBlack = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    /// VGA colour 7, the grey every BIOS and DOS prompt was written in.
    static let dosGrey = CGColor(srgbRed: 0xAA/255, green: 0xAA/255, blue: 0xAA/255, alpha: 1)
    /// The orange of "It's now safe to turn off your computer".
    static let shutdownOrange = CGColor(srgbRed: 0xFF/255, green: 0x9F/255, blue: 0x00/255, alpha: 1)
    /// ScanDisk ran in VGA colour 1, a blue a shade brighter than the blue screen's.
    static let scandiskBlue = CGColor(srgbRed: 0x00/255, green: 0x00/255, blue: 0xAA/255, alpha: 1)

    static func background(_ palette: ScreenPalette) -> CGColor {
        switch palette {
        case .win9x: return ninetyXBlue
        case .nt: return ntBlue
        case .console, .dos, .orange9x: return consoleBlack
        case .scandisk: return scandiskBlue
        }
    }
    static func foreground(_ palette: ScreenPalette) -> CGColor {
        switch palette {
        case .win9x: return ninetyXText
        case .nt, .console: return ntText
        case .dos, .scandisk: return dosGrey
        case .orange9x: return shutdownOrange
        }
    }
    /// The brighter colour a screen used for the part that mattered: the filled progress bar.
    static func accent(_ palette: ScreenPalette) -> CGColor {
        switch palette {
        case .scandisk, .dos: return ntText
        default: return foreground(palette)
        }
    }
}

/// Turns a surface into pixels. Stateless on purpose: the director decides what is on screen,
/// this decides only what it looks like.
enum CrashRenderer {

    /// `counter` fills the `.counter` lines — 0...100 for the memory dump. `blinkOn` is the phase
    /// of the block cursor.
    static func image(for screen: TextScreen, counter: Int = 0, blinkOn: Bool = true) -> CGImage? {
        let grid = screen.grid
        guard let canvas = TextCanvas(grid: grid, background: CrashPalette.background(screen.palette),
                                      font: screen.font) else { return nil }
        let fg = CrashPalette.foreground(screen.palette)
        let accent = CrashPalette.accent(screen.palette)
        let clamped = max(0, min(100, counter))

        var row = screen.topRow
        for line in screen.lines {
            guard row < grid.rows else { break }
            switch line {
            case .blank:
                break
            case .text(let s):
                canvas.put(s, col: screen.leftColumn, row: row, fg: fg)
            case .centred(let s):
                canvas.centre(s, row: row, fg: fg)
            case .inverted(let s):
                canvas.centre(s, row: row,
                              fg: CrashPalette.ninetyXPlaqueFG, bg: CrashPalette.ninetyXPlaqueBG)
            case .counter(let prefix):
                canvas.put("\(prefix)\(counter)", col: screen.leftColumn, row: row, fg: fg)
            case .prompt(let s):
                canvas.put(s + (blinkOn ? "\u{2588}" : " "), col: screen.leftColumn, row: row, fg: fg)
            case .progressBar(let prefix, let width, let suffix):
                let filled = width * clamped / 100
                var col = screen.leftColumn
                if !prefix.isEmpty { canvas.put(prefix, col: col, row: row, fg: fg); col += prefix.count }
                if filled > 0 {
                    canvas.put(String(repeating: "\u{2588}", count: filled), col: col, row: row, fg: accent)
                }
                if width - filled > 0 {
                    canvas.put(String(repeating: "\u{2591}", count: width - filled),
                               col: col + filled, row: row, fg: fg)
                }
                if !suffix.isEmpty { canvas.put(suffix, col: col + width, row: row, fg: fg) }
            case .percent(let prefix, let suffix):
                canvas.put("\(prefix)\(clamped)\(suffix)", col: screen.leftColumn, row: row, fg: fg)
            case .countdown(let prefix, let seconds, let suffix):
                let left = seconds - seconds * clamped / 100
                canvas.put("\(prefix)\(left)\(suffix)", col: screen.leftColumn, row: row, fg: fg)
            }
            row += 1
        }
        return canvas.image()
    }

}

// MARK: - Macintosh

extension CrashRenderer {

    /// The period error badges, from the artwork the systems actually used.
    static func badge(_ icon: ErrorDialog.Icon) -> NSImage? {
        switch icon {
        case .none:    return nil
        case .error9x: return asset("error-win9x.png")
        case .errorXP: return asset("error-winxp.png")
        case .warning: return NSImage(named: NSImage.cautionName)
        }
    }

    private static func asset(_ name: String) -> NSImage? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Crashes/\(name)") else { return nil }
        return NSImage(contentsOf: url)
    }

    static var bomb: NSImage? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Crashes/bomb.png") else { return nil }
        return NSImage(contentsOf: url)
    }

    /// The kernel panic curtain: a dark scrim over whatever was on screen, the power symbol, and
    /// the same sentence in four languages. Drawn at screen size and laid over the still.
    static func panicImage(_ panic: KernelPanic, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor(white: 0.10, alpha: 0.82).setFill()
        NSRect(origin: .zero, size: size).fill()

        // Power symbol: a ring with a gap at the top and a bar through it.
        let side = min(size.width, size.height) * 0.11
        let centre = NSPoint(x: size.width / 2, y: size.height * 0.62)
        let ring = NSBezierPath()
        ring.appendArc(withCenter: centre, radius: side / 2,
                       startAngle: 70, endAngle: 110, clockwise: true)
        ring.lineWidth = max(3, side * 0.09)
        NSColor.white.setStroke()
        ring.stroke()
        let bar = NSBezierPath()
        bar.move(to: NSPoint(x: centre.x, y: centre.y + side * 0.10))
        bar.line(to: NSPoint(x: centre.x, y: centre.y + side * 0.62))
        bar.lineWidth = max(3, side * 0.09)
        bar.stroke()

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineSpacing = 2
        var y = centre.y - side * 0.9
        let width = min(size.width * 0.62, 760)
        for (i, message) in panic.messages.enumerated() {
            let font = NSFont.systemFont(ofSize: i == 0 ? 15 : 13, weight: i == 0 ? .medium : .regular)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(i == 0 ? 0.95 : 0.75),
                .paragraphStyle: para]
            let box = (message as NSString).boundingRect(
                with: NSSize(width: width, height: 200),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
            let rect = NSRect(x: (size.width - width) / 2, y: y - box.height, width: width, height: box.height)
            (message as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading],
                                       attributes: attrs)
            y -= box.height + 14
        }
        return image
    }
}

// MARK: - Pixel art

extension CrashRenderer {

    /// A one-bit picture from rows of text: `#` is ink, anything else is clear. The way the
    /// classic Mac's own icons were kept, and the only way to be sure a 32-pixel face is the
    /// same 32 pixels on every display.
    static func bitmap(_ rows: [String], ink: NSColor, scale: Int) -> NSImage {
        let h = rows.count
        let w = rows.map(\.count).max() ?? 0
        let image = NSImage(size: NSSize(width: w * scale, height: h * scale))
        guard w > 0, h > 0 else { return image }
        image.lockFocus()
        ink.setFill()
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch == "#" {
                NSRect(x: x * scale, y: (h - 1 - y) * scale, width: scale, height: scale).fill()
            }
        }
        image.unlockFocus()
        return image
    }

    /// The pictures a Mac drew when it could not boot, at screen size.
    static func bootGlyphImage(_ glyph: BootGlyph, blinkOn: Bool, counter: Int = 0, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        let bounds = NSRect(origin: .zero, size: size)
        let unit = max(1, Int((min(size.width, size.height) / 160).rounded()))

        switch glyph {
        case .windowsUpdate(let screen):
            drawWindowsUpdate(screen, counter: counter, in: bounds)

        case .sadMac(let codes):
            NSColor.black.setFill(); bounds.fill()
            let face = bitmap(Self.sadMacRows, ink: .white, scale: unit * 2)
            let origin = NSPoint(x: (size.width - face.size.width) / 2,
                                 y: size.height * 0.56 - face.size.height / 2)
            face.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            let font = CrashFont.face(size: CGFloat(unit * 12)) as NSFont
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let s = (codes as NSString).size(withAttributes: attrs)
            (codes as NSString).draw(at: NSPoint(x: (size.width - s.width) / 2, y: origin.y - s.height - CGFloat(unit * 10)),
                                     withAttributes: attrs)

        case .questionFolder:
            NSColor(white: 0.745, alpha: 1).setFill(); bounds.fill()
            let folder = bitmap(Self.folderRows, ink: .black, scale: unit * 2)
            let origin = NSPoint(x: (size.width - folder.size.width) / 2,
                                 y: (size.height - folder.size.height) / 2)
            folder.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            if blinkOn {
                let mark = bitmap(Self.questionRows, ink: .black, scale: unit * 2)
                mark.draw(at: NSPoint(x: origin.x + (folder.size.width - mark.size.width) / 2,
                                      y: origin.y + (folder.size.height - mark.size.height) / 2 - CGFloat(unit * 2)),
                          from: .zero, operation: .sourceOver, fraction: 1)
            }

        case .prohibitory:
            NSColor(white: 0.745, alpha: 1).setFill(); bounds.fill()
            let side = min(size.width, size.height) * 0.18
            let rect = NSRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            let ring = NSBezierPath(ovalIn: rect)
            ring.lineWidth = side * 0.13
            NSColor(white: 0.22, alpha: 1).setStroke()
            ring.stroke()
            let bar = NSBezierPath()
            let inset = side * 0.20
            bar.move(to: NSPoint(x: rect.minX + inset, y: rect.maxY - inset))
            bar.line(to: NSPoint(x: rect.maxX - inset, y: rect.minY + inset))
            bar.lineWidth = side * 0.13
            bar.stroke()
        }
        return image
    }

    /// The update screen. Text is set in Tahoma on XP, which macOS ships, and in the system
    /// face for 7, whose Segoe UI it does not. Everything scales from the picture's height so a
    /// 4:3 window and a 16:9 screen get the same proportions.
    private static func drawWindowsUpdate(_ screen: WindowsUpdateScreen, counter: Int, in bounds: NSRect) {
        let percent = min(max(counter, 0), screen.ceiling)
        let h = bounds.height
        let top: NSColor, bottom: NSColor
        switch screen.style {
        case .xp:   top = NSColor(red: 0.36, green: 0.51, blue: 0.88, alpha: 1); bottom = NSColor(red: 0.20, green: 0.33, blue: 0.75, alpha: 1)
        case .win7: top = NSColor(red: 0.17, green: 0.43, blue: 0.63, alpha: 1); bottom = NSColor(red: 0.05, green: 0.19, blue: 0.35, alpha: 1)
        }
        NSGradient(starting: top, ending: bottom)?.draw(in: bounds, angle: -90)

        let bodySize = (h * 0.024).rounded()
        let headSize = screen.style == .xp ? (h * 0.030).rounded() : bodySize
        let body: NSFont = screen.style == .xp
            ? (NSFont(name: "Tahoma", size: bodySize) ?? .systemFont(ofSize: bodySize))
            : .systemFont(ofSize: bodySize, weight: .regular)
        let head: NSFont = screen.style == .xp
            ? (NSFont(name: "Tahoma-Bold", size: headSize) ?? .boldSystemFont(ofSize: headSize))
            : body
        let lineGap = bodySize * 0.55
        let lines = screen.lines.map { $0.replacingOccurrences(of: WindowsUpdateScreen.percentToken, with: String(percent)) }
        let sized: [(String, NSFont, NSSize)] = lines.enumerated().map { i, text in
            let font = i == 0 ? head : body
            return (text, font, (text as NSString).size(withAttributes: [.font: font]))
        }
        let barHeight = screen.bar ? bodySize * 0.9 : 0
        let barGap = screen.bar ? bodySize * 1.2 : 0
        let block = sized.reduce(0) { $0 + $1.2.height } + lineGap * CGFloat(max(0, sized.count - 1)) + barGap + barHeight
        var y = bounds.midY + block / 2
        for (text, font, size) in sized {
            y -= size.height
            (text as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: y),
                                    withAttributes: [.font: font, .foregroundColor: NSColor.white])
            y -= lineGap
        }
        guard screen.bar else { return }
        y = y + lineGap - barGap - barHeight
        // Luna's bar: a sunken white trough with green blocks that never quite reach the end.
        let width = (bounds.width * 0.26).rounded()
        let trough = NSRect(x: bounds.midX - width / 2, y: y, width: width, height: barHeight)
        NSColor(white: 1, alpha: 0.92).setFill(); trough.fill()
        NSColor(red: 0.42, green: 0.53, blue: 0.80, alpha: 1).setStroke()
        NSBezierPath(rect: trough.insetBy(dx: 0.5, dy: 0.5)).stroke()
        let inner = trough.insetBy(dx: barHeight * 0.18, dy: barHeight * 0.18)
        let blockW = inner.height * 0.62, gap = inner.height * 0.16
        let filled = inner.width * CGFloat(percent) / 100
        var x = inner.minX
        while x + blockW <= inner.minX + filled {
            let r = NSRect(x: x, y: inner.minY, width: blockW, height: inner.height)
            NSGradient(starting: NSColor(red: 0.55, green: 0.85, blue: 0.40, alpha: 1),
                       ending: NSColor(red: 0.20, green: 0.63, blue: 0.16, alpha: 1))?.draw(in: r, angle: -90)
            x += blockW + gap
        }
    }

    /// The Sad Mac, traced from the 32x32 original.
    static let sadMacRows: [String] = [
        "..............................  ",
        ".############################.  ",
        ".#..........................#.  ",
        ".#.########################.#.  ",
        ".#.#......................#.#.  ",
        ".#.#......................#.#.  ",
        ".#.#...##.........##......#.#.  ",
        ".#.#....##.......##.......#.#.  ",
        ".#.#.....##.....##........#.#.  ",
        ".#.#....##.......##.......#.#.  ",
        ".#.#...##.........##......#.#.  ",
        ".#.#......................#.#.  ",
        ".#.#......................#.#.  ",
        ".#.#........########......#.#.  ",
        ".#.#.......##......##.....#.#.  ",
        ".#.#......##........##....#.#.  ",
        ".#.#......................#.#.  ",
        ".#.########################.#.  ",
        ".#..........................#.  ",
        ".#..........................#.  ",
        ".#.#####....................#.  ",
        ".#..........................#.  ",
        ".############################.  ",
        "..#........................#..  ",
        "..##########################..  ",
    ]

    /// A folder outline, the shape Mac OS X blinked while it looked for a system.
    static let folderRows: [String] = [
        "....................................",
        ".############.......................",
        "#............#......................",
        "#.............################......",
        "#.............................#.....",
        "#..............................#....",
        "#..............................#....",
        "#..............................#....",
        "#..............................#....",
        "#..............................#....",
        "#..............................#....",
        "#..............................#....",
        "#..............................#....",
        "#..............................#....",
        "#..............................#....",
        "#..............................#....",
        "#..............................#....",
        "#..............................#....",
        "#..............................#....",
        "#..............................#....",
        "#..............................#....",
        "#..............................#....",
        "#..............................#....",
        ".##############################.....",
    ]

    static let questionRows: [String] = [
        "...####...",
        "..#....#..",
        ".#......#.",
        ".#......#.",
        "........#.",
        ".......#..",
        "......#...",
        ".....#....",
        "....#.....",
        "....#.....",
        "..........",
        "..........",
        "....#.....",
        "....#.....",
    ]
}

// MARK: - Busy pointers

extension CrashRenderer {

    /// One frame of a pointer that is busy rather than broken. `hotSpot` in the image's points,
    /// y down, the way NSCursor keeps it.
    struct CursorFrame {
        let image: NSImage
        let hotSpot: NSPoint
    }

    /// The beach ball of Mac OS X: eight wedges, flat colour, turning. Eight rotations so a
    /// full turn is eight frames.
    static func beachballFrames(scale: CGFloat) -> [CursorFrame] {
        let side: CGFloat = 32
        let colours: [NSColor] = [
            NSColor(srgbRed: 0.98, green: 0.30, blue: 0.29, alpha: 1),
            NSColor(srgbRed: 0.99, green: 0.62, blue: 0.20, alpha: 1),
            NSColor(srgbRed: 0.98, green: 0.88, blue: 0.24, alpha: 1),
            NSColor(srgbRed: 0.45, green: 0.80, blue: 0.30, alpha: 1),
            NSColor(srgbRed: 0.24, green: 0.72, blue: 0.85, alpha: 1),
            NSColor(srgbRed: 0.28, green: 0.45, blue: 0.90, alpha: 1),
            NSColor(srgbRed: 0.62, green: 0.36, blue: 0.85, alpha: 1),
            NSColor(srgbRed: 0.92, green: 0.40, blue: 0.70, alpha: 1),
        ]
        return (0..<8).map { step in
            let image = NSImage(size: NSSize(width: side, height: side))
            image.lockFocus()
            let centre = NSPoint(x: side / 2, y: side / 2)
            let radius = side / 2 - 1.5
            for (i, colour) in colours.enumerated() {
                let start = CGFloat(i * 45 + step * 45 / 8)
                let wedge = NSBezierPath()
                wedge.move(to: centre)
                wedge.appendArc(withCenter: centre, radius: radius, startAngle: start, endAngle: start + 45)
                wedge.close()
                colour.setFill()
                wedge.fill()
            }
            let rim = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: side - 3, height: side - 3))
            NSColor(white: 0.2, alpha: 0.7).setStroke()
            rim.lineWidth = 1
            rim.stroke()
            // A highlight, because the real one was drawn as a sphere.
            let shine = NSBezierPath(ovalIn: NSRect(x: side * 0.28, y: side * 0.58, width: side * 0.22, height: side * 0.14))
            NSColor(white: 1, alpha: 0.45).setFill()
            shine.fill()
            image.unlockFocus()
            return CursorFrame(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
        }
    }

    /// The Windows 7 busy ring: a blue ring with a brighter arc running round it.
    static func busyRingFrames(scale: CGFloat) -> [CursorFrame] {
        let side: CGFloat = 24
        return (0..<8).map { step in
            let image = NSImage(size: NSSize(width: side, height: side))
            image.lockFocus()
            let centre = NSPoint(x: side / 2, y: side / 2)
            let ring = NSBezierPath()
            ring.appendArc(withCenter: centre, radius: side * 0.34, startAngle: 0, endAngle: 360)
            ring.lineWidth = side * 0.22
            NSColor(srgbRed: 0.36, green: 0.60, blue: 0.86, alpha: 1).setStroke()
            ring.stroke()
            let start = CGFloat(360 - step * 45)
            let arc = NSBezierPath()
            arc.appendArc(withCenter: centre, radius: side * 0.34, startAngle: start, endAngle: start + 100)
            arc.lineWidth = side * 0.22
            NSColor(srgbRed: 0.82, green: 0.91, blue: 1.0, alpha: 1).setStroke()
            arc.stroke()
            image.unlockFocus()
            return CursorFrame(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
        }
    }

    /// The classic Mac OS wristwatch, one bit, two frames so the hands move.
    static func watchCursorFrames(scale: CGFloat) -> [CursorFrame] {
        let a: [String] = [
            ".....######.....",
            ".....######.....",
            "....#......#....",
            "...#........#...",
            "..#..........#..",
            "..#....#.....#..",
            "..#....#.....#..",
            "..#....###...#..",
            "..#..........#..",
            "..#..........#..",
            "...#........#...",
            "....#......#....",
            ".....######.....",
            ".....######.....",
            "................",
            "................",
        ]
        let b: [String] = [
            ".....######.....",
            ".....######.....",
            "....#......#....",
            "...#........#...",
            "..#..........#..",
            "..#..........#..",
            "..#..........#..",
            "..#....####..#..",
            "..#....#.....#..",
            "..#....#.....#..",
            "...#........#...",
            "....#......#....",
            ".....######.....",
            ".....######.....",
            "................",
            "................",
        ]
        return [a, b].map { rows in
            CursorFrame(image: outlined(rows), hotSpot: NSPoint(x: 9, y: 9))
        }
    }

    /// The Windows hourglass, in its two halves of a turn.
    static func hourglassFrames(scale: CGFloat) -> [CursorFrame] {
        let a: [String] = [
            "#############",
            "#############",
            ".#.........#.",
            ".#.........#.",
            ".#.#######.#.",
            "..#.#####.#..",
            "...#.###.#...",
            "....#.#.#....",
            ".....#.#.....",
            "....#...#....",
            "...#.....#...",
            "..#...#...#..",
            ".#...###...#.",
            ".#..#####..#.",
            "#############",
            "#############",
        ]
        let b: [String] = [
            "#############",
            "#############",
            ".#.........#.",
            ".#..#####..#.",
            ".#...###...#.",
            "..#...#...#..",
            "...#.....#...",
            "....#...#....",
            ".....#.#.....",
            "....#.#.#....",
            "...#.###.#...",
            "..#.#####.#..",
            ".#.#######.#.",
            ".#.........#.",
            "#############",
            "#############",
        ]
        return [a, b].map { rows in
            CursorFrame(image: outlined(rows), hotSpot: NSPoint(x: 7, y: 9))
        }
    }

    /// A one-bit cursor with the white surround the originals had, so it reads on any desktop.
    /// One point per pixel: these were 16-pixel cursors, and drawn twice the size they stop
    /// being a pointer and start being a picture of one. The layer scales them up whole-number
    /// on a Retina display, which keeps the pixels square.
    private static func outlined(_ rows: [String]) -> NSImage {
        let scale = 1
        let h = rows.count, w = rows.map(\.count).max() ?? 0
        let image = NSImage(size: NSSize(width: (w + 2) * scale, height: (h + 2) * scale))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        func ink(_ x: Int, _ y: Int) -> Bool {
            guard y >= 0, y < h, x >= 0 else { return false }
            let row = Array(rows[y])
            return x < row.count && row[x] == "#"
        }
        NSColor.white.setFill()
        for y in -1...h {
            for x in -1...w where !ink(x, y) {
                let near = [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(1,1),(-1,1),(1,-1)].contains { ink(x + $0.0, y + $0.1) }
                if near {
                    NSRect(x: (x + 1) * scale, y: (h - y) * scale, width: scale, height: scale).fill()
                }
            }
        }
        NSColor.black.setFill()
        for y in 0..<h {
            for x in 0..<w where ink(x, y) {
                NSRect(x: (x + 1) * scale, y: (h - y) * scale, width: scale, height: scale).fill()
            }
        }
        image.unlockFocus()
        return image
    }
}
