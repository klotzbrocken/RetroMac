import AppKit

/// What each macOS setting was before RetroMac first changed it — kept for good, so
/// Settings ▸ General can put the user's own Mac back ("Restore my settings"), not just macOS's
/// factory defaults, and a theme can show "yours → theme's" before it is turned on.
///
/// Remembered at the moment of the first change, never before: a snapshot taken at some launch
/// could catch a value RetroMac itself had left behind. Every `defaults write/delete` RetroMac
/// runs passes through `SystemBridge.runDefaults`, which calls `remember`; the three changes
/// made another way (the Dock's auto-hide through CoreDock, the menu bar and dark mode through
/// System Events) call it themselves.
enum OriginalSettings {
    private static let storeKey = "originalSystemSettings"   // ["domain\tkey": ["v": value] | ["unset": true]]
    private static let dateKey = "originalSystemSettingsSince"
    private static let lock = NSLock()

    /// Remember `domain`/`key` as it is now, unless it is remembered already. RetroMac's own
    /// domains are not the user's settings and are skipped.
    static func remember(_ domain: String, _ key: String) {
        guard !domain.hasPrefix("com.retromac") else { return }
        lock.lock(); defer { lock.unlock() }
        let d = UserDefaults.standard
        var store = d.dictionary(forKey: storeKey) ?? [:]
        let id = domain + "\t" + key
        guard store[id] == nil else { return }
        let value = read(domain, key)
        if value is NSArray || value is NSDictionary { return }   // not put back in one go; Terminal keeps its own
        store[id] = value.map { ["v": $0] } ?? ["unset": true]
        d.set(store, forKey: storeKey)
        if d.object(forKey: dateKey) == nil { d.set(Date(), forKey: dateKey) }
    }

    /// The remembered value: `.some(nil)` means the key was not set; nil means never touched.
    static func value(_ domain: String, _ key: String) -> Any?? {
        guard let entry = UserDefaults.standard.dictionary(forKey: storeKey)?[domain + "\t" + key] as? [String: Any] else { return nil }
        return .some(entry["v"])
    }

    static var count: Int { UserDefaults.standard.dictionary(forKey: storeKey)?.count ?? 0 }
    static var since: Date? { UserDefaults.standard.object(forKey: dateKey) as? Date }

    /// The value as the system has it now, typed, through CFPreferences.
    static func read(_ domain: String, _ key: String) -> Any? {
        let app = (domain == "-g" || domain == "NSGlobalDomain") ? kCFPreferencesAnyApplication : domain as CFString
        CFPreferencesAppSynchronize(app)
        return CFPreferencesCopyAppValue(key as CFString, app)
    }

    /// `defaults` arguments that put a remembered value back, or nil for a value `defaults`
    /// cannot write in one go (a list or a dictionary — none of RetroMac's keys are).
    static func writeArguments(_ domain: String, _ key: String, _ value: Any?) -> [String]? {
        guard let value else { return ["delete", domain, key] }
        if CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() {
            return ["write", domain, key, "-bool", (value as! Bool) ? "true" : "false"]
        }
        if let n = value as? NSNumber {
            return CFNumberIsFloatType(n) ? ["write", domain, key, "-float", n.stringValue]
                                          : ["write", domain, key, "-int", n.stringValue]
        }
        if let s = value as? String { return ["write", domain, key, "-string", s] }
        return nil
    }

    /// Put every remembered setting back as it was. Returns what was done, for the report.
    /// The caller has turned the theme off first, so nothing writes them again behind us.
    @discardableResult
    static func restore() -> [String] {
        let store = UserDefaults.standard.dictionary(forKey: storeKey) ?? [:]
        guard !store.isEmpty else { return [] }
        let sb = SystemBridge.shared
        var refresh = Set<String>()
        var failed = 0
        for (id, raw) in store {
            let parts = id.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2, let entry = raw as? [String: Any],
                  let args = writeArguments(parts[0], parts[1], entry["v"]) else { continue }
            if case .failure = sb.runDefaults(args), args[0] == "write" { failed += 1 }
            switch parts[0] {
            case "com.apple.dock": refresh.insert("Dock")
            case "com.apple.finder", "-g", "NSGlobalDomain": refresh.insert("Finder")
            default: break
            }
        }
        // What reads its setting only through a live path.
        if let hidden = value("-g", "_HIHideMenuBar") {
            SystemUIHelper.setMenuBarAutoHide((hidden as? Bool) ?? false)
        }
        if let style = value("-g", "AppleInterfaceStyle") {
            AppearanceAdapter.setDarkMode((style as? String)?.lowercased() == "dark")
        }
        for app in refresh { _ = sb.killall(app) }
        var lines = ["\(store.count) setting(s) put back as they were before RetroMac changed them."]
        if failed > 0 { lines.append("\(failed) could not be written; Restore macOS defaults still can.") }
        return lines
    }
}

/// What turning a theme on changes on the Mac, as "before → after", for the theme's page in
/// Settings. "Before" is the user's own value (`OriginalSettings`), else the one in place now.
enum ThemeSystemChanges {
    struct Change: Equatable { var what: String; var before: String; var after: String }

    /// The switches that decide what a theme may change, apart from the theme itself.
    struct Switches {
        var hideMenuBar = false, appearance = false, cursor = false, terminal = false
        var finderTweaks = false, titleBarCorners = false, systemIcons = false
        var ownWallpaper: Bool? = nil   // set per theme by the caller: "Keep my wallpaper"
        static var current: Switches {
            let s = AppSettings.shared
            return Switches(hideMenuBar: s.hideMenuBar, appearance: s.themeAdaptAppearance, cursor: s.themeAdaptCursor,
                            terminal: s.themeTerminalProfile, finderTweaks: s.themeApplySystemTweaks,
                            titleBarCorners: s.themeTitleBars, systemIcons: s.applySystemIcons)
        }
    }

    static func list(for config: DockThemeConfig, isBuiltIn: Bool, switches: Switches = .current,
                     hasCursors: Bool, terminalProfile: String?,
                     current: (String, String) -> Any? = { OriginalSettings.read($0, $1) }) -> [Change] {
        func before(_ domain: String, _ key: String) -> Any? {
            if let remembered = OriginalSettings.value(domain, key) { return remembered }
            return current(domain, key)
        }
        var out = [Change(what: "Mac Dock", before: "Shown", after: "Hidden")]
        if config.hideMenuBarDefault ?? switches.hideMenuBar {
            out.append(Change(what: "Menu bar", before: "Shown", after: "Hidden"))
        }
        if switches.ownWallpaper != true {
            out.append(Change(what: "Wallpaper", before: "Your picture", after: "The theme's picture"))
        }
        if switches.appearance {
            if let look = config.appearance {
                let now = (before("-g", "AppleInterfaceStyle") as? String)?.lowercased() == "dark" ? "Dark" : "Light"
                out.append(Change(what: "Appearance", before: now, after: look.capitalized))
            }
            if config.iconStyle == "tinted" {
                out.append(Change(what: "App icons", before: IconStyle.current() == IconStyle.tinted ? "Tinted" : "Yours",
                                  after: "Tinted in the accent colour"))
            }
            if let accent = config.accentColor {
                out.append(Change(what: "Accent colour", before: accentName(before("-g", "AppleAccentColor")), after: accent.capitalized))
            }
        }
        if switches.cursor, hasCursors { out.append(Change(what: "Pointer", before: "macOS", after: "The theme's pointers")) }
        if switches.terminal, let profile = terminalProfile {
            out.append(Change(what: "Terminal profile", before: "Yours", after: profile))
        }
        if switches.titleBarCorners {
            out.append(Change(what: "Window corners", before: "Rounded", after: "Square (apps opened from then on)"))
        }
        if switches.finderTweaks, isBuiltIn {
            for t in config.systemTweaks ?? [] where SystemTweaksAdapter.isTweakAllowed(t) {
                guard let label = tweakLabels[t.domain + "\t" + t.key] else { continue }
                if switches.titleBarCorners, t.key == "NSConvolutionOverride1" { continue }
                out.append(Change(what: label, before: describe(t.key, before(t.domain, t.key)),
                                  after: describe(t.key, t.value)))
            }
        }
        if switches.systemIcons { out.append(Change(what: "App icons in the Finder", before: "macOS", after: "The theme's")) }
        return out
    }

    /// Whether the theme brings pointers of its own; asked once per theme (the set is pictures).
    static func hasCursors(_ themeName: String) -> Bool {
        if let known = cursorCache[themeName] { return known }
        let has = CursorThemeManager.cursorSet(for: themeName) != nil
        cursorCache[themeName] = has
        return has
    }
    private static var cursorCache: [String: Bool] = [:]

    /// The Classic Finder keys, in words.
    static let tweakLabels: [String: String] = [
        "-g\tAppleReduceDesktopTinting": "Wallpaper tint in windows",
        "-g\tAppleShowAllExtensions": "All file extensions",
        "-g\tAppleShowScrollBars": "Scroll bars",
        "-g\tNSAutomaticWindowAnimationsEnabled": "Window animations",
        "-g\tNSConvolutionOverride1": "Window corners",
        "-g\tNSScrollAnimationEnabled": "Smooth scrolling",
        "-g\tNSSplitViewItemGlassMinimumCornerRadius": "Sidebar corners",
        "-g\tNSSplitViewItemSidebarDefaultsToFloatingAppearance": "Floating sidebars",
        "-g\tNSTableViewDefaultSizeMode": "Sidebar icon size",
        "-g\tNSUseAnimatedFocusRing": "Animated focus ring",
        "com.apple.dock\tlaunchanim": "Bouncing app launch",
        "com.apple.dock\tmineffect": "Minimise effect",
        "com.apple.finder\tDisableAllAnimations": "Finder animations off",
        "com.apple.finder\tFXPreferredViewStyle": "Finder view",
        "com.apple.finder\tShowPathbar": "Finder path bar",
        "com.apple.finder\tShowStatusBar": "Finder status bar",
        "com.apple.finder\t_FXShowPosixPathInTitle": "Full path in Finder titles",
        "com.apple.universalaccess\treduceTransparency": "Reduce transparency",
    ]

    static func describe(_ key: String, _ value: Any?) -> String {
        guard let value else { return "macOS default" }
        let text = (value as? String) ?? "\(value)"
        switch key {
        case "FXPreferredViewStyle":
            return ["Nlsv": "List", "icnv": "Icons", "clmv": "Columns", "Flwv": "Gallery"][text] ?? text
        case "NSTableViewDefaultSizeMode": return ["1": "Small", "2": "Medium", "3": "Large"][text] ?? text
        case "AppleShowScrollBars": return ["Always": "Always", "WhenScrolling": "When scrolling", "Automatic": "Automatic"][text] ?? text
        case "mineffect": return text.capitalized
        case "NSConvolutionOverride1", "NSSplitViewItemGlassMinimumCornerRadius":
            return (Double(text) ?? 99) < 1 ? "Square" : "\(text) pt"
        default:
            switch text.lowercased() {
            case "1", "true", "yes": return "On"
            case "0", "false", "no": return "Off"
            default: return text
            }
        }
    }

    private static func accentName(_ value: Any?) -> String {
        guard let n = (value as? NSNumber)?.intValue ?? (value as? String).flatMap(Int.init) else { return "Multicolour" }
        return [-1: "Graphite", 0: "Red", 1: "Orange", 2: "Yellow", 3: "Green", 4: "Blue", 5: "Purple", 6: "Pink"][n] ?? "Multicolour"
    }
}
