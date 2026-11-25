import AppKit
import CoreText

/// OS X 10.9's Calendar tile shows today's date even while the app is closed. A theme opts in by
/// shipping `icons/calendar-empty.png`, the blank page Apple drew the date onto; the month and
/// day go where they sit on 10.9's own "JUL 17" artwork.
enum CalendarDockIcon {
    static let bundleID = "com.apple.iCal"
    static let blankFile = "calendar-empty.png"

    /// Changes at midnight, so a cached tile from yesterday is never reused.
    static func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// The short month in the user's language, upper case and without the abbreviation dot
    /// ("JAN", "OKT"), as the localised Calendar tile showed it.
    static func monthText(_ date: Date, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("LLL")
        return f.string(from: date).replacingOccurrences(of: ".", with: "").uppercased(with: locale)
    }

    /// Fitted against Apple's 256 px "JUL 17" tile: the date lies on the page, so it turns with it
    /// (10.5° rising to the right) and narrows a touch further down. Fractions of the icon size.
    private enum Fit {
        static let angle = -10.46, keystone: CGFloat = -0.05
        static let day = (size: 0.399, x: 0.514, y: 0.549)      // centre of the digits' cap box
        static let month = (size: 0.118, x: 0.1586, y: 0.393)   // start of the baseline
    }

    static func render(blank: NSImage, date: Date = Date(), size: CGFloat) -> NSImage {
        let month = monthText(date)
        let day = String(Calendar.current.component(.day, from: date))
        return NSImage(size: NSSize(width: size, height: size), flipped: true) { r in
            blank.draw(in: r)
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            let s = r.width
            let df = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, s * Fit.day.size, nil)
            let dp = textPath(day, df)
            ctx.addPath(place(dp, at: CGPoint(x: s * Fit.day.x, y: s * Fit.day.y),
                              origin: CGPoint(x: dp.boundingBoxOfPath.midX, y: CTFontGetCapHeight(df) / 2), size: s))
            ctx.setFillColor(gray: 0.30, alpha: 1)
            ctx.fillPath()
            let mf = CTFontCreateWithName("HelveticaNeue" as CFString, s * Fit.month.size, nil)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: s / 256), blur: s / 256, color: NSColor(white: 0, alpha: 0.3).cgColor)
            ctx.addPath(place(textPath(month, mf), at: CGPoint(x: s * Fit.month.x, y: s * Fit.month.y), origin: .zero, size: s))
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fillPath()
            ctx.restoreGState()
            return true
        }
    }

    /// The glyph outlines of `text`, baseline at y = 0, y up.
    private static func textPath(_ text: String, _ font: CTFont) -> CGPath {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let out = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let n = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &pos)
            for i in 0..<n {
                if let g = CTFontCreatePathForGlyph(font, glyphs[i], nil) {
                    out.addPath(g, transform: CGAffineTransform(translationX: pos[i].x, y: pos[i].y))
                }
            }
        }
        return out
    }

    /// Lays `path` onto the page of a flipped canvas: `origin` (in the path's y-up space) lands on
    /// `at`, rows narrow by the keystone the further down they are, and all of it turns with the page.
    private static func place(_ path: CGPath, at: CGPoint, origin: CGPoint, size s: CGFloat) -> CGPath {
        let c = CGFloat(cos(Fit.angle * .pi / 180)), sn = CGFloat(sin(Fit.angle * .pi / 180))
        func f(_ p: CGPoint) -> CGPoint {
            let y = origin.y - p.y, x = (p.x - origin.x) * (1 + Fit.keystone * y / s)
            return CGPoint(x: at.x + x * c - y * sn, y: at.y + x * sn + y * c)
        }
        let out = CGMutablePath()
        path.applyWithBlock { e in
            let pts = e.pointee.points
            switch e.pointee.type {
            case .moveToPoint: out.move(to: f(pts[0]))
            case .addLineToPoint: out.addLine(to: f(pts[0]))
            case .addQuadCurveToPoint: out.addQuadCurve(to: f(pts[1]), control: f(pts[0]))
            case .addCurveToPoint: out.addCurve(to: f(pts[2]), control1: f(pts[0]), control2: f(pts[1]))
            case .closeSubpath: out.closeSubpath()
            @unknown default: break
            }
        }
        return out
    }
}
