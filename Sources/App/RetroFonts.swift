import AppKit

/// The bitmap faces RetroMac ships for its own chrome, registered for this process on first
/// use. Chicago's stand-in for Platinum menus, Pixel Operator for desktop labels.
enum RetroFonts {
    private static var registered = false

    private static func registerIfNeeded() {
        guard !registered else { return }
        registered = true
        for name in ["ChiKareGo2.ttf", "PixelOperator.ttf"] {
            guard let u = Bundle.main.resourceURL?.appendingPathComponent("Fonts/\(name)"),
                  FileManager.default.fileExists(atPath: u.path) else { continue }
            CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil)   // already registered → harmless error
        }
    }

    /// ChiKareGo2 (Giles Booth, CC BY): Chicago 12 as a 16 px bitmap. The size is a multiple of
    /// 16 for clean pixels; anything else blurs.
    static func chicago(_ size: CGFloat = 16) -> NSFont {
        registerIfNeeded()
        return NSFont(name: "ChiKareGo2", size: size) ?? NSFont(name: "Charcoal", size: size) ?? .systemFont(ofSize: size)
    }

    /// Pixel Operator (Jayvee Enaguas, CC0): an 8 px grid, sized in multiples of 16.
    static func pixelOperator(_ size: CGFloat = 16) -> NSFont {
        registerIfNeeded()
        return NSFont(name: "PixelOperator", size: size) ?? .systemFont(ofSize: size)
    }

    /// A font by name, registered the same way, for themes that name one of the shipped faces.
    static func named(_ name: String, size: CGFloat) -> NSFont? {
        registerIfNeeded()
        return NSFont(name: name, size: size)
    }
}
