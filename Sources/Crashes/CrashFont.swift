import AppKit
import CoreText

/// The text-mode font.
///
/// macOS has nothing that looks like a VGA character ROM, so the real thing is bundled:
/// Px437 IBM VGA 9x16 from VileR's Oldschool PC Font Pack, CC BY-SA 4.0, unmodified, credited in
/// the About box. At 16 pt it measures exactly 9 x 16 pixels per character, which is what makes
/// the whole screen plain grid arithmetic.
///
/// Registration is process-scoped, the same way theme fonts are registered
/// (ThemeManager.registerThemeFonts) and Windows 3.1's font is (Win31Chrome.registerFont).
enum CrashFont {

    static let postScriptName = "Px437_IBM_VGA_9x16"
    private static var didRegister = false
    private(set) static var isAvailable = false

    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        guard let url = fontURL() else { return }
        var error: Unmanaged<CFError>?
        isAvailable = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }

    /// The app bundle, which is where `build.sh` rsyncs it. Nothing else is searched: the same
    /// rule the theme and chrome resources follow (ThemeManager.swift:41).
    private static func fontURL() -> URL? {
        guard let u = Bundle.main.resourceURL?.appendingPathComponent("Fonts/Px437_IBM_VGA_9x16.ttf"),
              FileManager.default.fileExists(atPath: u.path) else { return nil }
        return u
    }

    /// The VGA face at `size`, or the system's monospaced font when the bundle is missing it.
    /// The fallback still lands on the grid — every glyph is positioned by hand — it just sits a
    /// little narrow inside a 9-pixel cell.
    static func face(size: CGFloat) -> CTFont {
        registerIfNeeded()
        if isAvailable {
            let f = CTFontCreateWithName(postScriptName as CFString, size, nil)
            // CTFontCreateWithName substitutes silently, so check we got what we asked for.
            if (CTFontCopyPostScriptName(f) as String) == postScriptName { return f }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
    }
}
