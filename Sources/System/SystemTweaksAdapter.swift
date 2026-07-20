import AppKit

/// Optionally makes the REAL Finder/system look like the active theme's era by applying a
/// curated set of cosmetic `defaults write` tweaks (Settings ▸ Dock ▸ "Classic Finder").
///
/// Reversibility is the whole point — this mirrors `AppearanceAdapter`: the user's original
/// value for every touched key is snapshotted the first time it's changed and restored when
/// the theme goes off, the switch is disabled, the app quits, or — crash-safe — on the next
/// launch (`restoreIfNeeded`). An empty snapshot value means the key was unset ⇒ restore = delete.
/// A `synchronize()` after each change survives a force-quit so the next launch can still undo.
///
/// STRICTLY cosmetic keys only (transparency, scrollbars, Finder view/chrome, animations,
/// Dock minimize effect). Never touches accent/highlight — those stay owned by
/// `AppearanceAdapter` ("Match appearance") so the two never fight over the same key.
enum SystemTweaksAdapter {

    private static let d = UserDefaults.standard
    private static let snapKey = "systemTweaksSnapshotTaken"
    /// Originals as [[domain,key,type,orig,refresh]]; `orig` == "" means the key was unset.
    private static let origKey = "systemTweaksOriginals"

    /// All reconcile runs (apply / restore / crash-recovery) are serialized here so the snapshot's
    /// read-modify-write can never interleave — a concurrent queue could otherwise snapshot an
    /// already-tweaked value as the "original" and make the change permanently irreversible.
    private static let queue = DispatchQueue(label: "com.retromac.systemtweaks")

    /// The ONLY `(domain, key)` pairs a theme may touch: strictly cosmetic keys the bundled themes
    /// use, across the four Apple UI domains. Anything else in a theme's `systemTweaks` is ignored.
    /// This is defense-in-depth behind the built-in-only gate in `apply` — a theme cannot write to
    /// arbitrary domains/keys even if it somehow reaches `reconcile`.
    private static let allowedKeys: Set<String> = [
        "-g\tAppleReduceDesktopTinting", "-g\tAppleShowAllExtensions", "-g\tAppleShowScrollBars",
        "-g\tNSAutomaticWindowAnimationsEnabled", "-g\tNSConvolutionOverride1",
        "-g\tNSScrollAnimationEnabled", "-g\tNSSplitViewItemGlassMinimumCornerRadius",
        "-g\tNSSplitViewItemSidebarDefaultsToFloatingAppearance", "-g\tNSTableViewDefaultSizeMode",
        "-g\tNSUseAnimatedFocusRing",
        "com.apple.dock\tlaunchanim", "com.apple.dock\tmineffect",
        "com.apple.finder\tDisableAllAnimations", "com.apple.finder\tFXPreferredViewStyle",
        "com.apple.finder\tShowPathbar", "com.apple.finder\tShowStatusBar",
        "com.apple.finder\t_FXShowPosixPathInTitle",
        "com.apple.universalaccess\treduceTransparency",
    ]

    /// Whether a tweak is on the cosmetic allowlist. `internal` so tests can exercise it directly.
    static func isTweakAllowed(_ t: DockThemeConfig.SystemTweak) -> Bool {
        allowedKeys.contains(t.domain + "\t" + t.key)
    }

    /// Apply the theme's tweaks (no-op unless the switch is on). Reconciles to the theme's set,
    /// so switching themes reverts the previous theme's tweaks that the new one doesn't declare.
    ///
    /// Only BUILT-IN themes may apply tweaks: imported (untrusted) themes never mutate the real
    /// system, they just reconcile to an empty set (reverting any previously-applied tweaks).
    static func apply(for config: DockThemeConfig, isBuiltIn: Bool) {
        guard AppSettings.shared.themeApplySystemTweaks else { return }
        let target = isBuiltIn ? (config.systemTweaks ?? []) : []
        queue.async { reconcile(to: target) }
    }

    /// Put every tracked key back to the user's original value. Pass `sync: true` on the quit
    /// path — the app process exits right after `applicationWillTerminate`, so an async restore
    /// would be killed mid-flight and leave the Finder tweaks (font size, corners…) stuck.
    static func restore(sync: Bool = false) {
        if sync { queue.sync { reconcile(to: []) } }
        else { queue.async { reconcile(to: []) } }
    }

    /// One-time heads-up (shown when the user first enables "Classic Finder" on a theme that
    /// declares window-corner tweaks): the corner radius is a global default each AppKit app reads
    /// only at launch, so it applies to the Finder immediately but to other apps only when they
    /// relaunch — for everything at once the user must log out. Honest, no forced logout.
    static func showCornerHintIfNeeded(for config: DockThemeConfig) {
        let key = "classicCornerHintShown"
        guard !d.bool(forKey: key) else { return }
        let hasCorner = (config.systemTweaks ?? []).contains {
            $0.key == "NSConvolutionOverride1" || $0.key == "NSSplitViewItemGlassMinimumCornerRadius"
        }
        guard hasCorner else { return }
        d.set(true, forKey: key)
        let alert = NSAlert()
        alert.messageText = "Classic window corners"
        alert.informativeText = "The Finder now uses this era's squarer window corners. Other apps pick them up the next time you open them — to apply the corners everywhere at once, log out and back in."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Crash / force-quit recovery: a leftover snapshot at launch means the previous session
    /// never restored — undo unconditionally. If the theme is still active + the switch on,
    /// `applyWallpaper()` → `apply()` re-applies right after, so this can't fight a live theme.
    static func restoreIfNeeded() {
        guard d.bool(forKey: snapKey) else { return }
        restore()
    }

    // MARK: - Core

    /// Make the currently-applied set exactly equal `target`: revert tracked keys not in the
    /// target, snapshot+write new ones, then `killall` each affected app once.
    private static func reconcile(to requested: [DockThemeConfig.SystemTweak]) {
        let sb = SystemBridge.shared
        func id(_ domain: String, _ key: String) -> String { domain + "\t" + key }

        // Enforce the cosmetic allowlist: anything off it is dropped here (the single sink), so a
        // dropped key that was tracked before falls out of `targetIDs` and gets reverted in step 1.
        let target = requested.filter { isTweakAllowed($0) }
        if target.count != requested.count {
            let dropped = requested.filter { !isTweakAllowed($0) }.map { $0.domain + "/" + $0.key }
            print("[SystemTweaks] ignored non-allowlisted tweaks: \(dropped)")
        }

        var stored = (d.array(forKey: origKey) as? [[String: String]]) ?? []
        let targetIDs = Set(target.map { id($0.domain, $0.key) })
        var kill = Set<String>()

        // 1. Revert any tracked key that the new target no longer includes.
        var remaining: [[String: String]] = []
        for e in stored {
            guard let domain = e["domain"], let key = e["key"], let type = e["type"] else { continue }
            if targetIDs.contains(id(domain, key)) { remaining.append(e); continue }
            let orig = e["orig"] ?? ""
            if orig.isEmpty { sb.runDefaults(["delete", domain, key]) }
            else { sb.runDefaults(["write", domain, key, flag(type), orig]) }
            kill.formUnion(refreshTargets(domain: domain, refresh: e["refresh"]))
        }
        stored = remaining
        let storedIDs = Set(stored.compactMap { e -> String? in
            guard let dm = e["domain"], let k = e["key"] else { return nil }
            return id(dm, k)
        })

        // 2. Snapshot (once) + write each target tweak.
        for t in target {
            if !storedIDs.contains(id(t.domain, t.key)) {
                let orig = sb.readDefault(t.domain, t.key) ?? ""   // "" ⇒ was unset ⇒ restore deletes
                stored.append([
                    "domain": t.domain, "key": t.key, "type": t.type,
                    "orig": orig, "refresh": t.refresh ?? ""
                ])
            }
            sb.runDefaults(["write", t.domain, t.key, flag(t.type), t.value])
            kill.formUnion(refreshTargets(domain: t.domain, refresh: t.refresh))
        }

        // 3. Persist the snapshot (or clear it once nothing is applied). Clear keys AFTER the
        //    writes ran, so a crash mid-reconcile still leaves the snapshot for a retry.
        if stored.isEmpty {
            d.removeObject(forKey: origKey)
            d.removeObject(forKey: snapKey)
        } else {
            d.set(stored, forKey: origKey)
            d.set(true, forKey: snapKey)
        }
        d.synchronize()

        // 4. One refresh per affected app + a color/appearance nudge for freshly-launched apps.
        for app in kill.sorted() { sb.killall(app) }
        notifyChanged()
        print("[SystemTweaks] target=\(target.count) tracked=\(stored.count) refreshed=\(kill.sorted())")
    }

    private static func flag(_ type: String) -> String {
        switch type {
        case "bool":  return "-bool"
        case "int":   return "-int"
        case "float": return "-float"
        default:      return "-string"
        }
    }

    /// Which app(s) to `killall` so a change becomes visible. Explicit `refresh` wins; otherwise
    /// derive from the domain. `-g`/NSGlobalDomain chrome shows after refreshing Finder + Dock
    /// (other apps pick it up on their next launch).
    static func refreshTargets(domain: String, refresh: String?) -> Set<String> {
        // Clamp an explicit refresh to Finder/Dock only — a theme must never be able to `killall`
        // an arbitrary process (e.g. loginwindow, WindowServer). Anything else falls back to the
        // domain-derived default.
        if let r = refresh, r == "Finder" || r == "Dock" { return [r] }
        switch domain {
        case "com.apple.finder":         return ["Finder"]
        case "com.apple.dock":           return ["Dock"]
        case "com.apple.universalaccess": return ["Dock"]
        default:                          return ["Finder", "Dock"]
        }
    }

    private static func notifyChanged() {
        for n in ["AppleColorPreferencesChangedNotification", "AppleInterfaceThemeChangedNotification"] {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(n), object: nil, userInfo: nil, deliverImmediately: true)
        }
    }
}
