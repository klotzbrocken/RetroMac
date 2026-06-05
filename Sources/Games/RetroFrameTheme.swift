import AppKit

/// Central place for theme-aware window framing of launched content (games, TV/video).
/// Games/engines that support it draw a matching window frame (e.g. Pac-Man's BeOS Lasche);
/// external engines (GZDoom, ares, …) ignore it. Default falls back to current behaviour.
enum RetroFrameTheme {

    /// Active RetroMac theme key handed to launched processes via RETROMAC_THEME.
    static func key() -> String {
        let name = (ThemeManager.shared.activeTheme?.config.name ?? "").lowercased()
        if name.contains("beos") { return "beos" }
        if name.contains("mac os 9") { return "macos9" }
        if name.contains("windows xp") || name == "xp" || name.hasPrefix("xp ") { return "winxp" }
        return "default"
    }

    /// Process environment to merge into a launched game so it can match the RetroMac theme.
    static func gameEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["RETROMAC_THEME"] = key()
        return env
    }
}
