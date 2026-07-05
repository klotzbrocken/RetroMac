import AppKit

/// Optionally matches the macOS appearance (light/dark) and accent colour to the active
/// theme (Settings ▸ Dock ▸ "Match appearance"). The user's original values are
/// snapshotted ONCE before the first change and restored when the theme goes off, the
/// toggle is disabled, or — crash-safe — on the next launch (restoreIfNeeded).
enum AppearanceAdapter {

    private static let d = UserDefaults.standard
    private static let snapKey = "appearanceSnapshotTaken"
    private static let origAccentKey = "appearanceOrigAccent"        // "" = key was unset
    private static let origHighlightKey = "appearanceOrigHighlight"
    private static let origAquaKey = "appearanceOrigAquaVariant"
    private static let origStyleKey = "appearanceOrigInterfaceStyle"

    /// accent name → (AppleAccentColor, AppleAquaColorVariant, AppleHighlightColor).
    /// Blue is the system default: accent 4, aqua 1, highlight unset.
    private static let accents: [String: (accent: String, aqua: String, highlight: String?)] = [
        "graphite": ("-1", "6", "0.847059 0.847059 0.862745 Graphite"),
        "red":      ("0",  "1", "1.000000 0.733333 0.721569 Red"),
        "orange":   ("1",  "1", "1.000000 0.874510 0.701961 Orange"),
        "yellow":   ("2",  "1", "1.000000 0.937255 0.690196 Yellow"),
        "green":    ("3",  "1", "0.752941 0.964706 0.678431 Green"),
        "blue":     ("4",  "1", nil),
        "purple":   ("5",  "1", "0.968627 0.831373 1.000000 Purple"),
        "pink":     ("6",  "1", "1.000000 0.749020 0.823529 Pink"),
    ]

    /// Apply the theme's appearance/accent (no-op unless the toggle is on and the theme
    /// declares at least one of them).
    static func apply(for config: DockThemeConfig) {
        guard AppSettings.shared.themeAdaptAppearance,
              config.appearance != nil || config.accentColor != nil else { return }
        snapshotIfNeeded()
        DispatchQueue.global(qos: .utility).async {
            let sb = SystemBridge.shared
            if let name = config.accentColor?.lowercased(), let a = accents[name] {
                sb.runDefaults(["write", "-g", "AppleAccentColor", "-int", a.accent])
                sb.runDefaults(["write", "-g", "AppleAquaColorVariant", "-int", a.aqua])
                if let hl = a.highlight {
                    sb.runDefaults(["write", "-g", "AppleHighlightColor", "-string", hl])
                } else {
                    sb.runDefaults(["delete", "-g", "AppleHighlightColor"])
                }
            }
            if let style = config.appearance?.lowercased() {
                setDarkMode(style == "dark")
            } else {
                // No appearance change to piggyback on: force a re-read of the accent by
                // toggling dark mode OFF/ON around the current value is too flashy — the
                // distributed notification at least reaches freshly launched apps.
            }
            notifyChanged()
            print("[Appearance] Matched to theme: accent=\(config.accentColor ?? "-") appearance=\(config.appearance ?? "-")")
        }
    }

    /// Put the user's original appearance/accent back (no-op without a snapshot).
    static func restore() {
        guard d.bool(forKey: snapKey) else { return }
        let orig: [(key: String, global: String, isInt: Bool)] = [
            (origAccentKey, "AppleAccentColor", true),
            (origAquaKey, "AppleAquaColorVariant", true),
            (origHighlightKey, "AppleHighlightColor", false),
            (origStyleKey, "AppleInterfaceStyle", false),
        ]
        let values = orig.map { (spec: $0, value: d.string(forKey: $0.key)) }
        DispatchQueue.global(qos: .utility).async {
            let sb = SystemBridge.shared
            for (spec, value) in values where spec.global != "AppleInterfaceStyle" {
                if let v = value, !v.isEmpty {
                    sb.runDefaults(["write", "-g", spec.global] + (spec.isInt ? ["-int", v] : ["-string", v]))
                } else {
                    sb.runDefaults(["delete", "-g", spec.global])
                }
            }
            // Appearance last, through System Events, so the live refresh re-reads the
            // just-restored accent values.
            let origStyle = values.first { $0.spec.global == "AppleInterfaceStyle" }?.value ?? ""
            setDarkMode(!(origStyle ?? "").isEmpty)
            notifyChanged()
            // Clear recovery keys only AFTER the restore actually ran — a quit/crash
            // mid-restore then still leaves the snapshot for the next launch to retry.
            d.removeObject(forKey: snapKey)
            orig.forEach { d.removeObject(forKey: $0.key) }
            print("[Appearance] Restored user's original appearance/accent")
        }
    }

    /// Crash / force-quit recovery: ANY leftover snapshot at launch means the previous
    /// session never restored — put the user's values back unconditionally. If the theme
    /// is still active, applyWallpaper() → apply() re-matches (and re-snapshots) right
    /// after launch, so this can't fight an active theme.
    static func restoreIfNeeded() {
        guard d.bool(forKey: snapKey) else { return }
        restore()
    }

    private static func snapshotIfNeeded() {
        guard !d.bool(forKey: snapKey) else { return }
        let sb = SystemBridge.shared
        d.set(sb.readDefault("-g", "AppleAccentColor") ?? "", forKey: origAccentKey)
        d.set(sb.readDefault("-g", "AppleAquaColorVariant") ?? "", forKey: origAquaKey)
        d.set(sb.readDefault("-g", "AppleHighlightColor") ?? "", forKey: origHighlightKey)
        d.set(sb.readDefault("-g", "AppleInterfaceStyle") ?? "", forKey: origStyleKey)
        d.set(true, forKey: snapKey)
        d.synchronize()   // survive a force-quit so restoreIfNeeded can undo on next launch
    }

    /// Dark/Light through System Events — the OFFICIAL path, which triggers the full
    /// system-wide appearance refresh (and makes running apps re-read the accent colour;
    /// a bare `defaults write` + distributed notification does NOT refresh live UI).
    /// Falls back to the defaults write when Automation permission is denied.
    private static func setDarkMode(_ dark: Bool) {
        let ok = SystemUIHelper.runAppleScript(
            "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)")
        if !ok {
            if dark { SystemBridge.shared.runDefaults(["write", "-g", "AppleInterfaceStyle", "Dark"]) }
            else { SystemBridge.shared.runDefaults(["delete", "-g", "AppleInterfaceStyle"]) }
        }
        // Persist the pref either way (System Events applies live but we keep defaults coherent).
        if dark { SystemBridge.shared.runDefaults(["write", "-g", "AppleInterfaceStyle", "Dark"]) }
        else { SystemBridge.shared.runDefaults(["delete", "-g", "AppleInterfaceStyle"]) }
    }

    private static func notifyChanged() {
        for n in ["AppleColorPreferencesChangedNotification", "AppleInterfaceThemeChangedNotification"] {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(n), object: nil, userInfo: nil, deliverImmediately: true)
        }
    }
}
