import AppKit
import CoreText

/// A VGA text-mode screen, drawn one character cell at a time into a fixed bitmap.
///
/// Two decisions carry the whole look:
///
///  - The bitmap is exactly the size of the real video mode (720x400 or 640x480). Everything is
///    integer grid arithmetic, and the result is scaled up whole-number with nearest-neighbour,
///    so a 5K display shows honest chunky pixels instead of a smooth impression of them.
///  - Glyphs are placed by hand with CoreText rather than drawn with `NSString.draw`. The text
///    engine's kerning and line rounding do not land on a 9-pixel grid; explicit positions do,
///    and they keep the fallback font on the grid too.
final class TextCanvas {

    private let grid: CrashGrid
    private let font: CTFont
    private let context: CGContext
    private let descent: CGFloat

    init?(grid: CrashGrid, background: CGColor, font kind: ScreenFont = .vga) {
        self.grid = grid
        self.font = kind == .vga
            ? CrashFont.face(size: CGFloat(grid.cellHeight))
            : NSFont.monospacedSystemFont(ofSize: CGFloat(grid.cellHeight) * 0.8, weight: .regular) as CTFont
        self.descent = (CTFontGetDescent(font)).rounded()

        guard let ctx = CGContext(data: nil,
                                  width: grid.pixelWidth, height: grid.pixelHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        self.context = ctx
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.setAllowsAntialiasing(false)
        ctx.setShouldSmoothFonts(false)
        ctx.setAllowsFontSmoothing(false)
        ctx.setShouldSubpixelPositionFonts(false)
        ctx.setShouldSubpixelQuantizeFonts(false)
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: grid.pixelWidth, height: grid.pixelHeight))
    }

    /// Row 0 is the top row. The context stays y-up — flipping it and drawing glyphs through a
    /// text matrix reintroduces exactly the rounding this class exists to avoid — so the flip
    /// happens in arithmetic instead.
    private func cellRect(col: Int, row: Int, length: Int) -> CGRect {
        CGRect(x: CGFloat(col * grid.cellWidth),
               y: CGFloat(grid.pixelHeight - (row + 1) * grid.cellHeight),
               width: CGFloat(length * grid.cellWidth),
               height: CGFloat(grid.cellHeight))
    }

    func put(_ text: String, col: Int, row: Int, fg: CGColor, bg: CGColor? = nil) {
        let chars = Array(text.utf16)
        guard !chars.isEmpty, row >= 0, row < grid.rows else { return }
        let rect = cellRect(col: col, row: row, length: chars.count)
        if let bg = bg {
            context.setFillColor(bg)
            context.fill(rect)
        }
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count)
        let baseline = rect.minY + descent
        let positions = (0..<chars.count).map {
            CGPoint(x: CGFloat((col + $0) * grid.cellWidth), y: baseline)
        }
        context.setFillColor(fg)
        CTFontDrawGlyphs(font, glyphs, positions, chars.count, context)
    }

    func centre(_ text: String, row: Int, fg: CGColor, bg: CGColor? = nil) {
        let col = max(0, (grid.columns - text.count) / 2)
        put(text, col: col, row: row, fg: fg, bg: bg)
    }

    func image() -> CGImage? { context.makeImage() }
}
