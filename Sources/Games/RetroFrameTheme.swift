import AppKit

/// Central place for theme-aware window framing of launched content (games, TV/video).
/// Games/engines that support it draw a matching window frame (e.g. Pac-Man's BeOS Lasche);
/// external engines (GZDoom, ares, …) ignore it. Default falls back to current behaviour.
enum RetroFrameTheme {

    /// Active RetroMac theme key handed to launched processes via RETROMAC_THEME.
    static func key() -> String {
        // Only frame launched content (TV window chrome, game frames) when a theme
        // is actually ON. After a clean launch ThemeManager still remembers the last
        // theme, but dockEnabled == false means "no theme active" — TV/games must not
        // inherit a stale theme's window chrome / menu bar.
        guard AppSettings.shared.dockEnabled else { return "default" }
        let name = (ThemeManager.shared.activeTheme?.config.name ?? "").lowercased()
        if name.contains("beos") { return "beos" }
        if name.contains("mac os 9") { return "macos9" }
        if name.contains("mac os 6") { return "macos9" }   // System 6 clone shares the Platinum widget chrome
        if name.contains("mac os x") { return "macosx" }
        if name.contains("windows 98") { return "win98" }
        if name.contains("windows xp") || name == "xp" || name.hasPrefix("xp ") { return "winxp" }
        if name.contains("maiks favourite") || name.contains("maiks favorite") { return "maiksfav" }
        return "default"
    }

    /// Process environment to merge into a launched game so it can match the RetroMac theme.
    static func gameEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["RETROMAC_THEME"] = key()
        return env
    }
}
