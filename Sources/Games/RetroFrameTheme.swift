import AppKit

/// Central place for theme-aware window framing of launched content (games, TV/video).
/// Games/engines that support it draw a matching window frame (e.g. Pac-Man's BeOS Lasche);
/// external engines (GZDoom, ares, …) ignore it. Default falls back to current behaviour.
enum RetroFrameTheme {

    /// Active RetroMac theme key handed to launched processes via RETROMAC_THEME.
    ///
    /// This one value drives the window chrome, window borders, widget chrome, TV chrome and the
    /// context-menu style across ~30 call sites. It is therefore the single place that decides
    /// "which era does this theme look like" — so it reads the theme's DECLARED `chrome.style`
    /// (Manifest 2.0). A theme can pick its renderer without any central switch being edited;
    /// the display-name heuristic below survives only for pre-2.0 themes that declare nothing.
    /// A slug for the ACTIVE theme by name, for the places that need one era rather than the
    /// chrome family. `key()` collapses Windows 95, 98 and Me into `win98` on purpose, because
    /// they draw the same chrome — but they do not furnish their windows the same way, and Me is
    /// the one with the web-view panel and without the navigation toolbar.
    ///
    /// Empty when no theme is on, so a caller can add nothing rather than a misleading class.
    static func eraSlug() -> String {
        guard AppSettings.shared.dockEnabled,
              let name = ThemeManager.shared.activeTheme?.config.name, !name.isEmpty else { return "" }
        let lower = name.lowercased()
        var out = ""
        var lastWasDash = false
        for ch in lower {
            if ch.isLetter || ch.isNumber { out.append(ch); lastWasDash = false }
            else if !lastWasDash && !out.isEmpty { out.append("-"); lastWasDash = true }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    static func key() -> String {
        // Only frame launched content (TV window chrome, game frames) when a theme
        // is actually ON. After a clean launch ThemeManager still remembers the last
        // theme, but dockEnabled == false means "no theme active" — TV/games must not
        // inherit a stale theme's window chrome / menu bar.
        guard AppSettings.shared.dockEnabled else { return "default" }
        guard let config = ThemeManager.shared.activeTheme?.config else { return "default" }
        if let declared = config.chrome?.style, !declared.isEmpty { return declared }
        return legacyKeyFromName(config.name)
    }

    /// Pre-Manifest-2.0 fallback: guess the chrome from the display name. Kept byte-for-byte as it
    /// was so imported themes without a `chrome.style` keep rendering exactly as before.
    static func legacyKeyFromName(_ displayName: String) -> String {
        let name = displayName.lowercased()
        if name.contains("beos") { return "beos" }
        if name.contains("mac os 9") { return "macos9" }
        if name.contains("mac os 6") { return "macos6" }   // authentic 1-bit System 6 chrome (System6Chrome)
        // The Aqua family splits in two. "macosx" is Cheetah-era Aqua: pinstripes, gel controls,
        // candy scrollbars. 10.6 dropped all of that for a flat unified grey title bar, and 10.8 kept
        // it, so Snow Leopard and Mountain Lion share their own key instead of borrowing 2001's look.
        if name.contains("snow leopard") || name.contains("mountain lion") { return "snowleopard" }
        if name.contains("mac os x") { return "macosx" }
        if name.contains("windows 7") { return "win7" }   // Aero glass chrome (drawWin7)
        if name.contains("windows 98") { return "win98" }
        if name.contains("windows 95") { return "win98" }   // Win95 reuses the 98 chrome (solid navy via chromeColors)
        if name.contains("windows me") { return "win98" }   // Millennium Edition reuses the 98 chrome
        if name.contains("windows 3") { return "win31" }   // flat pre-3D window frame
        if name.contains("windows xp") || name == "xp" || name.hasPrefix("xp ") { return "winxp" }
        if name.contains("maiks favourite") || name.contains("maiks favorite") { return "maiksfav" }
        if name.contains("nextstep") || name.contains("next step") { return "nextstep" }
        if name.contains("futurama") { return "futurama" }
        return "default"
    }

    /// True for any Mac OS X era theme, whichever Aqua generation it renders. Use this where the
    /// question is "is this a Mac OS X theme at all"; switch on `key()` where the look differs.
    static var isAquaFamily: Bool { key() == "macosx" || key() == "snowleopard" }

    /// Process environment to merge into a launched game so it can match the RetroMac theme.
    static func gameEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["RETROMAC_THEME"] = key()
        return env
    }
}
