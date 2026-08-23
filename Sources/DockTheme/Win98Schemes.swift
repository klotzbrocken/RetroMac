import AppKit

/// A Windows 98 "Plus!" desktop theme, expressed as a runtime variant of the base Windows 98
/// theme: a `[Control Panel\Colors]` colour scheme + wallpaper + desktop icons + cursor set.
/// Applied via `ThemeManager.applyWin98PlusVariant()` using the same `setConfigOverride` path as
/// the Mac OS 6/9 dock variants. The empty-id scheme ("Windows 98") is the built-in default and
/// has no entry here (→ no override → the standard navy look, Clouds/Teal wallpapers).
///
/// Colours are transcribed from the original Microsoft `.theme` files (via azayrahmad/win98-web,
/// MIT); the wallpapers/icons/cursors are Microsoft Plus! trade dress, bundled like the XP set.
struct Win98Scheme {
    let id: String
    let display: String
    let colors: DockThemeConfig.ChromeColors
    let wallpaper: String?           // filename at the theme-bundle root
    let iconComputer: String?        // My Computer desktop icon (in icons/)
    let iconRecycleEmpty: String?
    let iconRecycleFull: String?
    let cursorDir: String?           // Resources/<dir> for CursorThemeManager.loadBundledSet

    /// The two Plus! schemes (the default "Windows 98" is intentionally absent = no override).
    static let all: [Win98Scheme] = [
        Win98Scheme(
            id: "dangerous-creatures", display: "Dangerous Creatures",
            colors: DockThemeConfig.ChromeColors(
                activeTitle: "#008080", activeTitleEnd: nil, titleText: "#FFFFFF",
                inactiveTitle: "#484848", inactiveTitleText: "#707070",
                face: "#707070", hilight: "#B8B8B8", light: "#707070", shadow: "#484848", dkShadow: "#000000",
                window: "#B8B8B8", windowText: "#000000", menu: "#707070", menuText: "#000000",
                selection: "#008080", selectionText: "#FFFFFF"),
            wallpaper: "wp-dangerous-creatures.jpg",
            iconComputer: "dc-computer.png", iconRecycleEmpty: "dc-recycle-empty.png", iconRecycleFull: "dc-recycle-full.png",
            cursorDir: "Cursors/Win98-DangerousCreatures"),
        Win98Scheme(
            id: "leonardo", display: "Leonardo da Vinci",
            colors: DockThemeConfig.ChromeColors(
                activeTitle: "#800000", activeTitleEnd: nil, titleText: "#FFFFFF",
                inactiveTitle: "#8B655C", inactiveTitleText: "#DFD2D0",
                face: "#BFA59F", hilight: "#DFD2D0", light: "#BFA59F", shadow: "#8B655C", dkShadow: "#000000",
                window: "#FFFFFF", windowText: "#000000", menu: "#BFA59F", menuText: "#000000",
                selection: "#800000", selectionText: "#FFFFFF"),
            wallpaper: "wp-leonardo.jpg",
            iconComputer: "leo-computer.png", iconRecycleEmpty: "leo-recycle-empty.png", iconRecycleFull: "leo-recycle-full.png",
            cursorDir: "Cursors/Win98-Leonardo"),
        Win98Scheme(
            id: "more-windows", display: "More Windows",
            colors: DockThemeConfig.ChromeColors(
                activeTitle: "#000000", activeTitleEnd: nil, titleText: "#F0D030",
                inactiveTitle: "#606870", inactiveTitleText: "#C8C8D0",
                face: "#9098A0", hilight: "#C8D0D0", light: "#9098A0", shadow: "#606870", dkShadow: "#000000",
                window: "#FFFFFF", windowText: "#000000", menu: "#9098A0", menuText: "#000000",
                selection: "#F0D030", selectionText: "#000000"),
            wallpaper: "wp-more-windows.jpg",
            iconComputer: "mw-computer.png", iconRecycleEmpty: "mw-recycle-empty.png", iconRecycleFull: "mw-recycle-full.png",
            cursorDir: "Cursors/Win98-MoreWindows"),
    ]

    static let byID: [String: Win98Scheme] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// The Plus! 98 schemes are a WINDOWS 98 feature — they must apply only to the Windows 98 theme
    /// itself, not to every theme that merely reuses the win98 chrome (e.g. Windows Me), which would
    /// otherwise inherit the globally-selected scheme's colours. Scope all scheme accessors to this.
    static var isWin98Active: Bool {
        RetroFrameTheme.key() == "win98" && ThemeManager.shared.activeTheme?.config.name == "Windows 98"
    }

    /// The active scheme's ButtonFace as an NSColor, or nil when the default Windows 98 scheme is
    /// active (or the theme isn't Win98). Used by the dock's task buttons / start button so they
    /// match the scheme's window face.
    static func activeFaceColor() -> NSColor? {
        if isWin98Active, let hex = byID[AppSettings.shared.win98Scheme]?.colors.face, !hex.isEmpty {
            return NSColor.fromHex(hex)
        }
        // A win98-chrome theme that ships its own palette (e.g. Windows Me) uses its face colour.
        if RetroFrameTheme.key() == "win98", let hex = ThemeManager.shared.activeTheme?.config.chromeColors?.face, !hex.isEmpty {
            return NSColor.fromHex(hex)
        }
        return nil
    }

    /// The active scheme's title-text colour (e.g. More Windows uses gold), or nil for default.
    static func activeTitleTextColor() -> NSColor? {
        guard isWin98Active,
              let hex = byID[AppSettings.shared.win98Scheme]?.colors.titleText, !hex.isEmpty else { return nil }
        return NSColor.fromHex(hex)
    }

    /// The active scheme's active-title colours (gradient start, end) — for the start-menu banner
    /// and any other title-coloured surface. A scheme with no gradient end is a solid bar. nil for
    /// the default scheme.
    static func activeTitleColors() -> (NSColor, NSColor)? {
        guard isWin98Active,
              let c = byID[AppSettings.shared.win98Scheme]?.colors,
              let a = c.activeTitle, !a.isEmpty else { return nil }
        let start = NSColor.fromHex(a)
        let end = (c.activeTitleEnd.flatMap { $0.isEmpty ? nil : NSColor.fromHex($0) }) ?? start
        return (start, end)
    }

    /// JS that recolours a themed widget's Windows 98 chrome to the active scheme, by injecting a
    /// small `#w98scheme` override `<style>` (no per-widget HTML edits, and self-clearing for the
    /// default scheme). Every widget controller runs this right after `setTheme`.
    static func widgetOverrideJS() -> String {
        // IMPORTANT: wrap in an IIFE. WKWebView `evaluateJavaScript` runs each script in the page's
        // shared global scope, so a bare top-level `var st`/`var e` collides with the widget page's
        // own globals ("SyntaxError: Can't create duplicate variable"), which silently aborted the
        // whole injection — the reason Windows 95 title bars kept showing the static gradient.
        let remove = "(function(){var e=document.getElementById('w98scheme'); if(e) e.remove();})();"
        guard RetroFrameTheme.key() == "win98" else { return remove }
        // Win98 Plus! scheme (Windows 98 only), else the active theme's own palette (e.g. Windows Me).
        let c: DockThemeConfig.ChromeColors?
        if isWin98Active { c = byID[AppSettings.shared.win98Scheme]?.colors }
        else { c = ThemeManager.shared.activeTheme?.config.chromeColors }
        guard let colors = c else { return remove }
        let a = colors.activeTitle ?? "#00007b"
        let b = colors.activeTitleEnd ?? a
        let tt = colors.titleText ?? "#ffffff"
        let face = colors.face ?? "#c4c4c4"
        // The CONTENT area (file list / document) uses the scheme's `window` colour (white by
        // default) — NOT the grey ButtonFace used for the window frame and buttons. Painting it
        // with `face` turned the Fun Stuff / Programs / TV list backgrounds grey.
        let win = colors.window ?? "#ffffff"
        let winText = colors.windowText ?? "#000000"
        let css = """
        body.theme-win98 .w98-title,body.theme-win98 .w98-dlg-tb{background:linear-gradient(90deg,\(a),\(b))!important;}
        body.theme-win98 .w98-cap,body.theme-win98 .w98-dlg-tb{color:\(tt)!important;}
        body.theme-win98 #win,body.theme-win98 .body,body.theme-win98 .w98-btn,body.theme-win98 .be-win,body.theme-win98 .window{background:\(face)!important;}
        body.theme-win98 .be-content{background:\(win)!important;color:\(winText)!important;}
        """
        return "(function(){var e=document.getElementById('w98scheme'); if(e) e.remove(); var st=document.createElement('style'); st.id='w98scheme'; st.textContent=`\(css)`; document.head.appendChild(st);})();"
    }

    /// All picker options including the built-in default (empty id).
    static let pickerOptions: [(id: String, display: String)] =
        [("", "Windows 98")] + all.map { ($0.id, $0.display) }
}
