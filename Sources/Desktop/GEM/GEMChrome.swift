import AppKit
import CoreText

/// Atari TOS 4.04's GEM desktop, measured off the Falcon030 screenshots in `Downloads/Tos404`
/// (the 640 × 480 "tos404-multilingual" series, one screen pixel one point). Everything is drawn
/// into flipped views on whole points, so a Retina display shows each Atari pixel as a 2 × 2 block.
enum GEMChrome {
    /// The free desktop, RGB 158/190/255 in the blue series; the turquoise #00AAA9 of the second
    /// 4.04 picture was another user's setting.
    static let desk = NSColor.fromHex("#9EBEFF")
    /// The grey of dialogs and window gadgets, and their shade.
    static let face = NSColor.fromHex("#CFCFCF")
    static let shade = NSColor.fromHex("#B2B2B2")

    /// The menu bar: 18 rows of white and a black rule, the titles each a space either side.
    static let barHeight: CGFloat = 19
    static let charW: CGFloat = 8, rowH: CGFloat = 16
    /// A desktop icon's cell: 80 across, 51 down, the 32 × 32 picture 20 in, the 72 × 8 label under it.
    static let cellW: CGFloat = 80, cellH: CGFloat = 51
    static let iconInset: CGFloat = 20, labelW: CGFloat = 72, labelH: CGFloat = 8

    // MARK: The system font

    /// The Falcon's 8 × 16 system font has no free copy; IBM's VGA 8 × 16 (VileR's PxPlus,
    /// CC BY-SA 4.0, already shipped for Notepad) has the same cell and close letterforms.
    private static var fontName: String?
    static var font: NSFont {
        if fontName == nil, let url = Bundle.main.resourceURL?.appendingPathComponent("Widgets/Notepad/fonts/PxPlus_IBM_VGA_8x16.ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)   // already registered → harmless error
            let d = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first
            fontName = d.flatMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String } ?? ""
        }
        if let n = fontName, !n.isEmpty, let f = NSFont(name: n, size: 16) { return f }
        return .monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    /// A line of the system font with the top of its 16-row cell at `p` (flipped view).
    static func text(_ s: String, at p: NSPoint, color: NSColor = .black) {
        NSGraphicsContext.current?.cgContext.setShouldAntialias(false)
        (s as NSString).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
        NSGraphicsContext.current?.cgContext.setShouldAntialias(true)
    }
    static func textWidth(_ s: String) -> CGFloat { CGFloat(s.count) * charW }

    // MARK: The small font of the icon labels

    /// The 6 × 6 font GEM wrote under desktop icons, five rows of five dots in a six-dot cell.
    /// The letters of the blue series' labels are read off the screenshot; the rest are drawn to
    /// match them. Lower case shows as capitals, as TOS file names were.
    static let small: [Character: [UInt8]] = {
        func g(_ rows: [String]) -> [UInt8] { rows.map { (UInt8($0, radix: 2) ?? 0) << 3 } }   // column 0 in the top bit
        let t: [Character: [String]] = [
            "A": ["01110", "10001", "11111", "10001", "10001"], "B": ["11110", "10001", "11110", "10001", "11110"],
            "C": ["01111", "10000", "10000", "10000", "01111"], "D": ["11110", "10001", "10001", "10001", "11110"],
            "E": ["11111", "10000", "11110", "10000", "11111"], "F": ["11111", "10000", "11110", "10000", "10000"],
            "G": ["01111", "10000", "10011", "10001", "01111"], "H": ["10001", "10001", "11111", "10001", "10001"],
            "I": ["01110", "00100", "00100", "00100", "01110"], "J": ["00111", "00010", "00010", "10010", "01100"],
            "K": ["01001", "01010", "01100", "01010", "01001"], "L": ["01000", "01000", "01000", "01000", "01111"],
            "M": ["10001", "11011", "10101", "10001", "10001"], "N": ["10001", "11001", "10101", "10011", "10001"],
            "O": ["01110", "10001", "10001", "10001", "01110"], "P": ["11110", "10001", "11110", "10000", "10000"],
            "Q": ["01110", "10001", "10101", "10010", "01101"], "R": ["11110", "10001", "11110", "10100", "10011"],
            "S": ["01111", "10000", "01110", "00001", "11110"], "T": ["11111", "00100", "00100", "00100", "00100"],
            "U": ["10001", "10001", "10001", "10001", "01111"], "V": ["10001", "10001", "10001", "01010", "00100"],
            "W": ["10001", "10001", "10101", "11011", "10001"], "X": ["10001", "01010", "00100", "01010", "10001"],
            "Y": ["10001", "10001", "01010", "00100", "00100"], "Z": ["11111", "00010", "00100", "01000", "11111"],
            "Ä": ["01010", "01110", "10001", "11111", "10001"], "Ö": ["01010", "01110", "10001", "10001", "01110"],
            "Ü": ["01010", "00000", "10001", "10001", "01111"],
            "0": ["01110", "10011", "10101", "11001", "01110"], "1": ["00100", "01100", "00100", "00100", "01110"],
            "2": ["11110", "00001", "01110", "10000", "11111"], "3": ["11110", "00001", "00110", "00001", "11110"],
            "4": ["00110", "01010", "10010", "11111", "00010"], "5": ["11111", "10000", "11110", "00001", "11110"],
            "6": ["01110", "10000", "11110", "10001", "01110"], "7": ["11111", "00001", "00010", "00100", "00100"],
            "8": ["01110", "10001", "01110", "10001", "01110"], "9": ["01110", "10001", "01111", "00001", "01110"],
            ".": ["00000", "00000", "00000", "00110", "00110"], "-": ["00000", "00000", "01110", "00000", "00000"],
            "_": ["00000", "00000", "00000", "00000", "11111"], "&": ["01100", "10010", "01101", "10010", "01101"],
            "'": ["00100", "00100", "00000", "00000", "00000"], "(": ["00010", "00100", "00100", "00100", "00010"],
            ")": ["01000", "00100", "00100", "00100", "01000"], "+": ["00000", "00100", "01110", "00100", "00000"],
            ":": ["00000", "00100", "00000", "00100", "00000"], "!": ["00100", "00100", "00100", "00000", "00100"],
            "?": ["01110", "00001", "00110", "00000", "00100"], "/": ["00001", "00010", "00100", "01000", "10000"],
            ",": ["00000", "00000", "00000", "00100", "01000"], " ": ["00000", "00000", "00000", "00000", "00000"],
        ]
        return t.mapValues(g)
    }()

    /// What a label can show: capitals, umlauts kept, anything else a question mark.
    static func smallLabel(_ name: String, maxChars: Int = 12) -> String {
        let up = name.replacingOccurrences(of: "ß", with: "SS").uppercased()
        let mapped = String(up.map { c -> Character in
            if small[c] != nil { return c }
            let plain = String(c).folding(options: .diacriticInsensitive, locale: nil).first ?? "?"   // É → E
            return small[plain] != nil ? plain : "?"
        })
        return mapped.count <= maxChars ? mapped : String(mapped.prefix(maxChars - 1)) + "."
    }

    /// The label text in the small font, its first cell's top left at `p`.
    static func smallText(_ s: String, at p: NSPoint, color: NSColor) {
        color.setFill()
        for (i, ch) in s.enumerated() {
            guard let rows = small[ch] else { continue }
            for (y, bits) in rows.enumerated() where bits != 0 {
                for x in 0..<6 where bits & (0x80 >> x) != 0 {
                    NSRect(x: p.x + CGFloat(i * 6 + x), y: p.y + CGFloat(y), width: 1, height: 1).fill()
                }
            }
        }
    }

    // MARK: Bitmaps

    /// A one-colour bitmap, "#" set, anything else clear, rows from the top.
    static func bitmap(_ rows: [String], at p: NSPoint, color: NSColor) {
        color.setFill()
        for (y, row) in rows.enumerated() {
            for (x, c) in row.enumerated() where c == "#" {
                NSRect(x: p.x + CGFloat(x), y: p.y + CGFloat(y), width: 1, height: 1).fill()
            }
        }
    }

    /// The close box's mark (the window in `_3.png`).
    static let closeMark = [".#####.", "..###..", "#.###.#", "#..#..#", "##.#.##", "##...##", "##.#.##", "#..#..#", "#.###.#", "..###..", ".#####."]
    /// The full box's mark.
    static let fullMark = [".#####", "######", "##....", "##....", "##.###", "##.###", "##..##", "##..##", "##..##", "##..##", "######", ".####."]
    /// The menu's tick, 8 across.
    static let tick = ["       #", "       #", "      ##", "      ##", "     ## ", "     ## ", "#   ##  ", "#   ##  ", "## ##   ", " # ##   ", " ###    ", "  ##    ", "  #     "]
    /// The Atari mark in Desktop Info, 29 × 30, off `_2.png`.
    static let fuji = [
        "          ## ### ##          ", "          ## ### ##          ", "          ## ### ##          ", "          ## ### ##          ",
        "          ## ### ##          ", "          ## ### ##          ", "         ### ### ###         ", "         ### ### ###         ",
        "         ### ### ###         ", "         ### ### ###         ", "        #### ### ####        ", "        #### ### ####        ",
        "       ##### ### #####       ", "      #####  ###  #####      ", "     ######  ###  ######     ", "   #######   ###   #######   ",
        "#########    ###    #########", "########     ###     ########", "######       ###       ######", "####         ###         ####",
        "                             ", "   #  ######  #    #####   ##", "  ### ###### ###   ######  ##", "  ###   ##   ###   ##  ### ##",
        " ## ##  ##  ## ##  ##  ### ##", " ## ##  ##  ## ##  ## ###  ##", "####### ## ####### ## ##   ##", "####### ## ####### ## ###  ##",
        "##   ## ## ##   ## ##  ### ##", "##   ## ## ##   ## ##   ## ##",
    ]

    /// Half the pixels in `r`, alternately: the stipple GEM put over dimmed text and into slider tracks.
    static func checker(_ r: NSRect, color: NSColor) {
        color.setFill()
        let x0 = Int(r.minX), y0 = Int(r.minY)
        for y in y0..<Int(r.maxY) {
            var x = x0 + ((x0 + y) & 1)
            while x < Int(r.maxX) { NSRect(x: x, y: y, width: 1, height: 1).fill(); x += 2 }
        }
    }

    /// A raised gadget: white along the top and left, the shade along the bottom and right, grey between.
    static func raised(_ r: NSRect) {
        face.setFill(); r.fill()
        NSColor.white.setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width - 1, height: 1).fill()
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height - 1).fill()
        shade.setFill()
        NSRect(x: r.minX + 1, y: r.maxY - 1, width: r.width - 1, height: 1).fill()
        NSRect(x: r.maxX - 1, y: r.minY + 1, width: 1, height: r.height - 1).fill()
    }

    /// A 1 pt black outline inside `r`.
    static func outline(_ r: NSRect, width w: CGFloat = 1) {
        NSColor.black.setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: w).fill()
        NSRect(x: r.minX, y: r.maxY - w, width: r.width, height: w).fill()
        NSRect(x: r.minX, y: r.minY, width: w, height: r.height).fill()
        NSRect(x: r.maxX - w, y: r.minY, width: w, height: r.height).fill()
    }

    /// A dialog box (Desktop Info in `_2.png`): a grey edge and two white rows outside on the top
    /// and left, three of the shade on the bottom and right, then three of black around the grey face.
    static func dialog(_ r: NSRect) {
        shade.setFill(); r.fill()
        face.setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width - 3, height: 1).fill(); NSRect(x: r.minX, y: r.minY, width: 1, height: r.height - 3).fill()
        NSColor.white.setFill()
        NSRect(x: r.minX + 1, y: r.minY + 1, width: r.width - 4, height: 2).fill(); NSRect(x: r.minX + 1, y: r.minY + 1, width: 2, height: r.height - 4).fill()
        let inner = NSRect(x: r.minX + 3, y: r.minY + 3, width: r.width - 6, height: r.height - 6)
        face.setFill(); inner.fill()
        outline(inner, width: 3)
    }

    /// A button: raised, in a black line (three for the default one), its label centred.
    static func button(_ r: NSRect, title: String, isDefault: Bool, pressed: Bool = false) {
        let w: CGFloat = isDefault ? 3 : 1
        outline(r, width: w)
        let inner = r.insetBy(dx: w, dy: w)
        if pressed { NSColor.black.setFill(); inner.fill() } else { raised(inner) }
        text(title, at: NSPoint(x: (r.midX - textWidth(title) / 2).rounded(), y: (r.midY - 8).rounded()), color: pressed ? .white : .black)
    }
}
