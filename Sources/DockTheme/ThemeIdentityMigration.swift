import Foundation

/// One-time rewrite of every theme-keyed setting from the theme's DISPLAY NAME to its stable id.
///
/// Before Manifest 2.0 the visible name was also the storage key, so renaming a theme silently
/// orphaned its preset, wallpaper, dock position, auto-hide, bootscreen, screensaver, icon
/// overrides and icon sizes — and two themes sharing a name shared those settings.
///
/// This runs at the very TOP of `AppSettings.init`, before any of those values is read. That
/// ordering matters twice over:
///   * `AppSettings` then loads already-migrated values, so no `@Published` setter fires. Writing
///     `dockTheme` later would re-enter DockController's `$dockTheme` sink and replay the whole
///     theme switch (splash, window rebuild) on every launch.
///   * It cannot ask `ThemeManager` for the theme list (that would be circular — `ThemeManager`
///     reads `AppSettings`), so it reads the manifests off disk itself via
///     `ThemeBundle.identity(ofBundleAt:)`, which computes ids exactly as `ThemeBundle` will.
enum ThemeIdentityMigration {

    private static let doneKey = "themeSettingsKeyedByID_v1"

    /// Dictionary defaults whose KEYS are theme identifiers.
    private static let dictionaryKeys = [
        "themePresetOverrides", "themeOrientationOverrides", "themeDockPositionOverride",
        "themeDockAutoHide", "themeWallpaperOverrides", "themeCustomWallpaper",
        "themeBootscreenEnabled", "themeScreensaverOverrides", "dockThemeIconOverrides",
    ]

    /// Stores that are NOT dictionaries but one defaults entry per theme, named `<prefix><theme>`:
    /// the per-theme icon sizes and the desktop-icon customisations (positions, added shortcuts,
    /// per-item icon overrides, removals).
    private static let keyPrefixes = [
        "iconScale_dock_", "iconScale_desktop_", "iconScale_linked_", "desktopCustom.",
    ]

    /// `directories` defaults to the real theme locations; tests inject their own.
    static func runIfNeeded(defaults: UserDefaults = .standard, directories: [URL]? = nil) {
        guard !defaults.bool(forKey: doneKey) else { return }

        let map = nameToID(in: directories ?? searchDirectories())
        guard !map.isEmpty else {
            // No themes readable (first launch before the bundle is in place, or an I/O problem).
            // Do NOT set the flag — without a map we would "migrate" nothing and then never retry.
            print("[ThemeID] Migration skipped — no theme manifests readable yet")
            return
        }

        var changed = 0
        for key in dictionaryKeys {
            guard let old = defaults.dictionary(forKey: key), !old.isEmpty else { continue }
            var new: [String: Any] = [:]
            for (k, v) in old {
                let target = map[k] ?? k          // unknown key → keep verbatim, never drop it
                // An entry already stored under the id wins over one still under the old name.
                if new[target] != nil, target != k { continue }
                if old[target] != nil, target != k { continue }
                new[target] = v
                if target != k { changed += 1 }
            }
            defaults.set(new, forKey: key)
        }

        for prefix in keyPrefixes {
            for (name, id) in map {
                let from = prefix + name
                let to   = prefix + id
                guard from != to, defaults.object(forKey: from) != nil else { continue }
                // An entry already under the id was written by a newer build — it wins.
                if defaults.object(forKey: to) == nil {
                    defaults.set(defaults.object(forKey: from), forKey: to)
                    changed += 1
                }
                defaults.removeObject(forKey: from)
            }
        }

        // The stored selection itself. `legacySelectorAliases` covers names that no longer exist
        // (e.g. the standalone "Mac OS 9.2" that became a Mac OS 9 dock variant).
        if let selection = defaults.string(forKey: "dockTheme") {
            let aliased = ThemeManager.legacySelectorAliases[selection] ?? selection
            if let id = map[aliased], id != selection {
                defaults.set(selection, forKey: "dockThemeLegacyName")   // kept for one release
                defaults.set(id, forKey: "dockTheme")
                changed += 1
            }
        }

        defaults.set(true, forKey: doneKey)
        print("[ThemeID] Migrated \(changed) theme-keyed setting(s) from name to stable id")
    }

    /// display name → stable id, for every theme currently on disk (built-in and user).
    private static func nameToID(in directories: [URL]) -> [String: String] {
        var map: [String: String] = [:]
        for dir in directories {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { continue }
            for bundle in items where bundle.pathExtension == "retromactheme" {
                guard let ident = ThemeBundle.identity(ofBundleAt: bundle) else { continue }
                // Two themes can share a display name. That ambiguity is exactly what stable ids
                // fix, but it means we cannot safely attribute an old name-keyed setting to
                // either of them — so drop the mapping and leave those entries under the name.
                if let existing = map[ident.name], existing != ident.id {
                    map[ident.name] = ident.name
                } else {
                    map[ident.name] = ident.id
                }
            }
        }
        return map.filter { $0.key != $0.value }
    }

    private static func searchDirectories() -> [URL] {
        var dirs: [URL] = []
        if let builtin = Bundle.main.resourceURL?.appendingPathComponent("Themes") { dirs.append(builtin) }
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            dirs.append(appSupport.appendingPathComponent("RetroMac/DockThemes"))
        }
        return dirs
    }
}
