import AppKit

/// Installs a Terminal.app profile matching the active theme and makes it the
/// default/startup profile (Settings ▸ Dock ▸ "Terminal profile", default ON).
///
/// Profiles are generated at runtime (archived NSColor/NSFont, exactly what a
/// .terminal file contains) and written straight into Terminal's preferences —
/// zero-click import. The user's previous default/startup profile is snapshotted
/// and restored when the theme goes off or the toggle is disabled. The installed
/// RetroMac profiles themselves stay in Terminal (harmless, reusable).
enum TerminalThemer {

    private static let d = UserDefaults.standard
    private static let snapKey = "terminalProfileSnapshotTaken"
    private static let origDefaultKey = "terminalOrigDefault"
    private static let origStartupKey = "terminalOrigStartup"

    private struct Profile {
        let name: String
        let bg: NSColor
        let fg: NSColor
        let fontName: String
        let fontSize: CGFloat
    }

    /// Theme name (lowercased `contains` match) → profile.
    private static func profile(forThemeNamed name: String) -> Profile? {
        let n = name.lowercased()
        if n.contains("windows") || n.contains("dos") {
            return Profile(name: "RetroMac DOS", bg: .black,
                           fg: NSColor(red: 0.31, green: 0.92, blue: 0.31, alpha: 1),
                           fontName: "Menlo-Regular", fontSize: 13)
        }
        if n.contains("beos") {
            return Profile(name: "RetroMac BeOS", bg: NSColor(white: 1.0, alpha: 1),
                           fg: .black, fontName: "Menlo-Regular", fontSize: 12)
        }
        if n.contains("mac os 6") || n.contains("mac os 9") {
            return Profile(name: "RetroMac Classic Mac", bg: .white, fg: .black,
                           fontName: "Monaco", fontSize: 11)
        }
        if n.contains("maiks favourite ii") {
            return Profile(name: "RetroMac DOOM", bg: .black,
                           fg: NSColor(red: 1.0, green: 0.36, blue: 0.2, alpha: 1),
                           fontName: "Menlo-Bold", fontSize: 13)
        }
        if n.contains("irix") || n.contains("sgi") {
            return Profile(name: "RetroMac IRIX", bg: NSColor(red: 0.07, green: 0.17, blue: 0.22, alpha: 1),
                           fg: NSColor(red: 0.75, green: 0.92, blue: 0.95, alpha: 1),
                           fontName: "Menlo-Regular", fontSize: 12)
        }
        if n.contains("amiga") {
            return Profile(name: "RetroMac Amiga", bg: NSColor(red: 0.0, green: 0.2, blue: 0.66, alpha: 1),
                           fg: NSColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 1),
                           fontName: "Menlo-Regular", fontSize: 12)
        }
        if n.contains("os/2") || n.contains("os2") {
            return Profile(name: "RetroMac OS/2", bg: .black,
                           fg: NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1),
                           fontName: "Menlo-Regular", fontSize: 12)
        }
        return nil   // Aqua/Snow Leopard etc.: leave Terminal alone
    }

    /// Apply the matching profile for the active theme (no-op if the toggle is off or
    /// no profile fits). Runs off-main; Terminal picks it up on its next launch.
    static func apply(forThemeNamed name: String) {
        guard AppSettings.shared.themeTerminalProfile, let p = profile(forThemeNamed: name) else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let term = UserDefaults(suiteName: "com.apple.Terminal") else { return }
            snapshotIfNeeded(term)
            var windowSettings = term.dictionary(forKey: "Window Settings") ?? [:]
            windowSettings[p.name] = profileDict(p)
            term.set(windowSettings, forKey: "Window Settings")
            term.set(p.name, forKey: "Default Window Settings")
            term.set(p.name, forKey: "Startup Window Settings")
            print("[TerminalThemer] Default Terminal profile → \(p.name)")
        }
    }

    /// Restore the user's original default/startup profile.
    static func restore() {
        guard d.bool(forKey: snapKey) else { return }
        let origDefault = d.string(forKey: origDefaultKey)
        let origStartup = d.string(forKey: origStartupKey)
        d.removeObject(forKey: snapKey)
        d.removeObject(forKey: origDefaultKey)
        d.removeObject(forKey: origStartupKey)
        DispatchQueue.global(qos: .utility).async {
            guard let term = UserDefaults(suiteName: "com.apple.Terminal") else { return }
            if let v = origDefault, !v.isEmpty { term.set(v, forKey: "Default Window Settings") }
            else { term.removeObject(forKey: "Default Window Settings") }
            if let v = origStartup, !v.isEmpty { term.set(v, forKey: "Startup Window Settings") }
            else { term.removeObject(forKey: "Startup Window Settings") }
            print("[TerminalThemer] Restored the user's Terminal profile")
        }
    }

    private static func snapshotIfNeeded(_ term: UserDefaults) {
        guard !d.bool(forKey: snapKey) else { return }
        // Never snapshot one of OUR profiles as the "original" (re-entrant applies).
        let current = term.string(forKey: "Default Window Settings") ?? ""
        guard !current.hasPrefix("RetroMac ") else { return }
        d.set(current, forKey: origDefaultKey)
        d.set(term.string(forKey: "Startup Window Settings") ?? "", forKey: origStartupKey)
        d.set(true, forKey: snapKey)
        d.synchronize()
    }

    /// The same structure a .terminal file carries (archived colors/font).
    private static func profileDict(_ p: Profile) -> [String: Any] {
        func archived(_ obj: Any) -> Data? {
            try? NSKeyedArchiver.archivedData(withRootObject: obj, requiringSecureCoding: false)
        }
        var dict: [String: Any] = [
            "name": p.name,
            "type": "Window Settings",
            "ProfileCurrentVersion": 2.07,
            "columnCount": 90,
            "rowCount": 28,
        ]
        if let bg = archived(p.bg) { dict["BackgroundColor"] = bg }
        if let fg = archived(p.fg) {
            dict["TextColor"] = fg
            dict["TextBoldColor"] = fg
            dict["CursorColor"] = fg
        }
        if let font = NSFont(name: p.fontName, size: p.fontSize) ?? NSFont(name: "Menlo-Regular", size: p.fontSize),
           let f = archived(font) {
            dict["Font"] = f
        }
        return dict
    }
}
