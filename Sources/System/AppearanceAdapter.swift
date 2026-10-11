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
    private static let origIconKey = "appearanceOrigIconStyle"       // [theme, tint, appearance]

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
        // The icon style: tinted for a theme that asks for it, the user's own for any other. Kept
        // apart from the snapshot above, which an earlier theme may have taken without it.
        if d.array(forKey: origIconKey) == nil, config.iconStyle != nil, let icons = IconStyle.current() {
            d.set([icons.theme, icons.tint, icons.appearance].map(Int.init), forKey: origIconKey)
        }
        let original = (d.array(forKey: origIconKey) as? [Int]).flatMap(IconStyle.Value.init)
        let iconsWanted = config.iconStyle == "tinted" ? IconStyle.tinted : original
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
            // The tint IS the accent colour on macOS 26+, read when the style is saved: so the
            // style goes last, once the accent is written, as System Settings does it. Set first,
            // the icons took the old accent (blue) and kept it.
            // Saved even when it is tinted already: the save is what makes the Dock tint again,
            // with the accent just written. Skipped because it was "unchanged", the icons kept
            // the blue of before.
            // A moment after the announcement, so the Dock has the new accent when it tints.
            if let iconsWanted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if iconsWanted == IconStyle.tinted || iconsWanted != IconStyle.current() { IconStyle.set(iconsWanted) }
                }
            }
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
        if let icons = (d.array(forKey: origIconKey) as? [Int]).flatMap(IconStyle.Value.init), icons != IconStyle.current() {
            IconStyle.set(icons)
        }
        d.removeObject(forKey: origIconKey)
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
    static func setDarkMode(_ dark: Bool) {
        OriginalSettings.remember("-g", "AppleInterfaceStyle")
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
        // All four System Settings sends with an accent change: AppKit's and CoreUI's own for the
        // accent (AppleAquaColorVariantChanged, kCUI…) are what make running apps and the Dock
        // read it again; the first two alone left the Dock's tinted icons in the old colour.
        for n in ["AppleColorPreferencesChangedNotification", "AppleInterfaceThemeChangedNotification",
                  "AppleAquaColorVariantChanged", "kCUINotificationAquaColorVariantChanged"] {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(n), object: nil, userInfo: nil, deliverImmediately: true)
        }
    }
}

/// macOS 26's icon and widget style, through SkyLight's `SLSIconAppearanceConfiguration`, the
/// class System Settings ▸ Appearance uses. Its numbers are not documented; measured on macOS 27
/// by setting the style there and reading it back: Default (dark) is theme 2, appearance 0;
/// Tinted (dark) is theme 8, appearance 1; the tint is the accent colour (choosing an orange tint
/// there sets AppleAccentColor to orange and leaves the tint at 0). Nil where the class
/// is missing (before macOS 26), and then nothing is changed.
enum IconStyle {
    struct Value: Equatable {
        var theme: UInt32, tint: UInt32, appearance: UInt32
        init(theme: UInt32, tint: UInt32, appearance: UInt32) { self.theme = theme; self.tint = tint; self.appearance = appearance }
        init?(_ saved: [Int]) {
            guard saved.count == 3 else { return nil }
            self.init(theme: UInt32(saved[0]), tint: UInt32(saved[1]), appearance: UInt32(saved[2]))
        }
    }
    static let tinted = Value(theme: 8, tint: 0, appearance: 1)

    private static func configuration() -> NSObject? {
        let fetch = NSSelectorFromString("fetchCurrentIconAppearanceConfiguration")
        guard let cls = NSClassFromString("SLSIconAppearanceConfiguration") as? NSObject.Type,
              cls.responds(to: fetch) else { return nil }
        return cls.perform(fetch)?.takeUnretainedValue() as? NSObject
    }
    private static func get(_ o: NSObject, _ name: String) -> UInt32? {
        let sel = NSSelectorFromString(name)
        guard o.responds(to: sel) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> UInt32
        return unsafeBitCast(o.method(for: sel), to: Getter.self)(o, sel)
    }
    private static func set(_ o: NSObject, _ name: String, _ v: UInt32) {
        let sel = NSSelectorFromString(name)
        guard o.responds(to: sel) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, UInt32) -> Void
        unsafeBitCast(o.method(for: sel), to: Setter.self)(o, sel, v)
    }

    static func current() -> Value? {
        guard let c = configuration(), let theme = get(c, "iconAppearanceTheme"), let tint = get(c, "iconTintColorName"),
              let appearance = get(c, "appearanceTheme") else { return nil }
        return Value(theme: theme, tint: tint, appearance: appearance)
    }

    static func set(_ v: Value) {
        guard let c = configuration(), c.responds(to: NSSelectorFromString("save")) else { return }
        set(c, "setIconAppearanceTheme:", v.theme)
        set(c, "setIconTintColorName:", v.tint)
        set(c, "setAppearanceTheme:", v.appearance)
        c.perform(NSSelectorFromString("save"))
        print("[Appearance] Icon style → theme \(v.theme), tint \(v.tint), appearance \(v.appearance)")
    }
}
