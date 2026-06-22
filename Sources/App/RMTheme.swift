import SwiftUI

// MARK: - Design Tokens for Settings Redesign

extension Color {
    // Backgrounds — Retro skin: warm paper neutrals
    static let rmBg = Color(red: 0.980, green: 0.976, blue: 0.961)             // #faf9f5 warm paper
    static let rmSidebarBg = Color(red: 0.945, green: 0.933, blue: 0.902)      // #f1eee6
    static let rmSurface = Color(red: 1.0,   green: 0.996, blue: 0.984)        // #fffdf7 warm white
    static let rmSurface2 = Color(red: 0.969, green: 0.957, blue: 0.925)       // #f7f4ec

    // Lines — warm
    static let rmBorder = Color(red: 0.906, green: 0.886, blue: 0.839)         // #e7e2d6
    static let rmBorderStrong = Color(red: 0.847, green: 0.824, blue: 0.761)   // #d8d2c2
    static let rmDivider = Color(red: 0.937, green: 0.918, blue: 0.878)        // #efeae0

    // Text
    static let rmTextPrimary = Color(red: 0.102, green: 0.114, blue: 0.133)    // #1a1d22
    static let rmTextSecondary = Color(red: 0.420, green: 0.443, blue: 0.502)  // #6b7180
    static let rmTextTertiary = Color(red: 0.604, green: 0.627, blue: 0.678)   // #9aa0ad

    // CRT phosphor accent — Retro: #1f9a57
    static let rmAccent = Color(red: 0.122, green: 0.604, blue: 0.341)         // #1f9a57
    static let rmAccentSoft = Color(red: 0.847, green: 0.945, blue: 0.871)     // #d8f1de
    static let rmAccentText = Color(red: 0.090, green: 0.420, blue: 0.235)     // #176b3c

    // Status
    static let rmStatusOn = Color(red: 0.122, green: 0.604, blue: 0.341)       // same as accent
    static let rmDanger = Color(red: 0.890, green: 0.341, blue: 0.231)         // #e3573b
    static let rmWarning = Color(red: 0.878, green: 0.620, blue: 0.169)        // #e09e2b
    static let rmInfo = Color(red: 0.227, green: 0.510, blue: 0.910)           // #3a82e8
}

// MARK: - Typography

extension Font {
    /// 13 pt body
    static let rmBody = Font.system(size: 13)
    /// 11.5 pt secondary
    static let rmSecondary = Font.system(size: 11.5)
    /// 10.5 pt caption
    static let rmCaption = Font.system(size: 10.5)
    /// 11 pt section header, weight 600 — monospaced (Retro skin)
    static let rmSectionHeader = Font.system(size: 11, weight: .semibold, design: .monospaced)
    /// 10 pt sidebar header, weight 600 — monospaced (Retro skin)
    static let rmSidebarHeader = Font.system(size: 10, weight: .semibold, design: .monospaced)
    /// 13 pt sidebar item
    static let rmSidebarItem = Font.system(size: 13)
    /// 14 pt toolbar title, weight 600
    static let rmToolbarTitle = Font.system(size: 15, weight: .semibold)
    /// 24 pt hero number, weight 600
    static let rmHero = Font.system(size: 24, weight: .semibold).leading(.tight)
    /// Monospaced variant for FPS, resolution, percentages
    static func rmMono(size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Spacing & Radii

enum RMSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 12
    static let xxl: CGFloat = 14
    static let card: CGFloat = 16
    static let section: CGFloat = 18
    static let page: CGFloat = 20
    static let pageLarge: CGFloat = 24
}

enum RMRadius {
    static let window: CGFloat = 12
    static let card: CGFloat = 10
    static let tile: CGFloat = 9
    static let button: CGFloat = 6
    static let keyCap: CGFloat = 5
    static let chip: CGFloat = 999
}

// MARK: - CRT scanline (Retro skin)

/// Very subtle horizontal scanline overlay for the Settings window background.
struct RMScanline: View {
    var body: some View {
        Canvas { ctx, size in
            let line = Color.black.opacity(0.022)
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(line))
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Shadow Modifiers

extension View {
    func rmCardShadow() -> some View {
        self
            .shadow(color: Color.black.opacity(0.04), radius: 0, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
    }

    func rmSidebarActiveShadow() -> some View {
        self
            .shadow(color: Color.black.opacity(0.04), radius: 0, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
    }
}
