import AppKit

/// OS X 10.9's Calendar tile shows today's date even while the app is closed. A theme opts in by
/// shipping `icons/calendar-empty.png`, the blank page Apple drew the date onto; the month and
/// day go where they sit on 10.9's own "JUL 17" artwork (measured at 512 px).
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

    static func render(blank: NSImage, date: Date = Date(), size: CGFloat) -> NSImage {
        let month = monthText(date)
        let day = String(Calendar.current.component(.day, from: date))
        return NSImage(size: NSSize(width: size, height: size), flipped: true) { r in
            blank.draw(in: r)
            let s = r.width
            // Month: white, left in the red band, cap top 0.275, baseline 0.369 of the height.
            let mf = NSFont(name: "HelveticaNeue", size: s * 0.13) ?? .systemFont(ofSize: s * 0.13)
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
            shadow.shadowOffset = NSSize(width: 0, height: -s / 256)   // flipped: a hair below
            shadow.shadowBlurRadius = s / 256
            (month as NSString).draw(at: NSPoint(x: s * 0.16, y: s * 0.369 - mf.ascender),
                                     withAttributes: [.font: mf, .foregroundColor: NSColor.white, .shadow: shadow])
            // Day: bold dark grey, centred at 0.49, baseline 0.717, cap height 0.277 of the height.
            let df = NSFont(name: "HelveticaNeue-Bold", size: s * 0.39) ?? .boldSystemFont(ofSize: s * 0.39)
            let attrs: [NSAttributedString.Key: Any] = [.font: df, .foregroundColor: NSColor(white: 0.30, alpha: 1)]
            let w = (day as NSString).size(withAttributes: attrs).width
            (day as NSString).draw(at: NSPoint(x: s * 0.49 - w / 2, y: s * 0.717 - df.ascender), withAttributes: attrs)
            return true
        }
    }
}
