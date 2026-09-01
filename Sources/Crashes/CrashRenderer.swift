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

    static func background(_ palette: ScreenPalette) -> CGColor {
        switch palette {
        case .win9x: return ninetyXBlue
        case .nt: return ntBlue
        case .console: return consoleBlack
        }
    }
    static func foreground(_ palette: ScreenPalette) -> CGColor {
        switch palette {
        case .win9x: return ninetyXText
        case .nt, .console: return ntText
        }
    }
}

/// Turns a surface into pixels. Stateless on purpose: the director decides what is on screen,
/// this decides only what it looks like.
enum CrashRenderer {

    /// `counter` fills the `.counter` lines — 0...100 for the memory dump.
    static func image(for screen: TextScreen, counter: Int = 0) -> CGImage? {
        let grid = screen.grid
        guard let canvas = TextCanvas(grid: grid, background: CrashPalette.background(screen.palette),
                                      font: screen.font) else { return nil }
        let fg = CrashPalette.foreground(screen.palette)

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
