import AppKit
import CryptoKit

final class ThemeBundle {
    let url: URL
    let baseConfig: DockThemeConfig
    let isBuiltIn: Bool
    /// Permanent identity of this theme — `config.id` when the manifest declares one, otherwise a
    /// generated `legacy.<slug>.<fingerprint>` id. Everything that must survive a rename (the
    /// stored selection, every per-theme setting, icon overrides) keys off this, never off `name`.
    let stableID: String
    /// Optional runtime variant of the config (e.g. Mac OS 6's "real dock instead of
    /// Control Strip" option). Set by ThemeManager on activation; nil = as authored.
    private var configOverride: DockThemeConfig?

    var config: DockThemeConfig { configOverride ?? baseConfig }
    func setConfigOverride(_ cfg: DockThemeConfig?) { configOverride = cfg }

    init(url: URL, isBuiltIn: Bool = false) throws {
        self.url = url
        self.isBuiltIn = isBuiltIn

        let jsonURL = url.appendingPathComponent("theme.json")
        let data = try Data(contentsOf: jsonURL)
        var cfg = try JSONDecoder().decode(DockThemeConfig.self, from: data)

        // Identity: an author-declared `id` wins. A theme predating Manifest 2.0 (or one whose id
        // is malformed) gets a legacy id derived from its name plus a fingerprint of the manifest
        // AS LOADED — the name alone is not enough, since two imported themes can share one.
        let declared = cfg.id.flatMap { Self.isValidID($0) ? $0 : nil }
        let generated = declared == nil ? Self.legacyID(name: cfg.name, manifest: data) : nil
        cfg.id = declared ?? generated
        self.stableID = cfg.id ?? cfg.name
        self.baseConfig = cfg
        assert(self.stableID == Self.identity(name: cfg.name, declaredID: declared, manifest: data),
               "ThemeBundle.init and ThemeBundle.identity must agree — the settings migration relies on it")

        // Persist a generated id so it stops depending on the manifest's bytes: without this the
        // id would move the first time the user edits the theme, taking all their per-theme
        // settings with it. Built-ins are authored with an id and `save` refuses them anyway; a
        // failed write (read-only volume) is harmless — the same id is recomputed next launch.
        if generated != nil, !isBuiltIn {
            try? save(config: cfg)
        }
    }

    /// The stable id for a manifest, from its declared id (if usable) or a generated legacy one.
    /// The settings migration runs BEFORE any `ThemeBundle` exists (it must rewrite stored keys
    /// before `AppSettings` reads them), so it recomputes identities with this same function.
    /// Both paths must produce the same string — the initializer asserts that they do.
    static func identity(name: String, declaredID: String?, manifest: Data) -> String {
        if let declaredID, isValidID(declaredID) { return declaredID }
        return legacyID(name: name, manifest: manifest)
    }

    /// Read just `name` + resulting stable id from a theme bundle on disk, without building a
    /// full `ThemeBundle`. Used by the settings migration to map old name-keyed entries to ids.
    static func identity(ofBundleAt url: URL) -> (name: String, id: String)? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("theme.json")),
              let probe = try? JSONDecoder().decode(IdentityProbe.self, from: data) else { return nil }
        return (probe.name, identity(name: probe.name, declaredID: probe.id, manifest: data))
    }

    /// Minimal decode of the two identity fields — tolerant of anything else in the manifest.
    private struct IdentityProbe: Decodable {
        let name: String
        let id: String?
    }

    /// A manifest id must be stable, non-localised and filesystem/URL-safe.
    static func isValidID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 128 else { return false }
        guard id.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "." || $0 == "-") }) else { return false }
        guard !id.hasPrefix("."), !id.hasSuffix("."), !id.contains("..") else { return false }
        return true
    }

    /// `legacy.<slug of display name>.<first 8 hex of SHA-256 over theme.json>`.
    static func legacyID(name: String, manifest: Data) -> String {
        let slug = slugify(name)
        let digest = SHA256.hash(data: manifest).map { String(format: "%02x", $0) }.joined()
        return "legacy.\(slug).\(digest.prefix(8))"
    }

    /// Lowercase, ASCII-safe, dash-separated form of a display name ("Mac OS 9.2" → "mac-os-9-2").
    static func slugify(_ s: String) -> String {
        var out = ""
        var lastWasDash = false
        for ch in s.lowercased() {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                out.append(ch); lastWasDash = false
            } else if !lastWasDash {
                out.append("-"); lastWasDash = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "theme" : trimmed
    }

    var name: String { config.name }
    var iconsDirectory: URL { url.appendingPathComponent("icons") }

    /// Resolve a theme-relative resource path, confined to `base` (inside the bundle). Returns nil
    /// if the resolved path escapes the bundle via `../` or a symlink, or does not exist. RetroMac
    /// is unsandboxed and imports untrusted themes, so a theme must never reference files outside
    /// its own directory (arbitrary-file-as-icon/wallpaper). `internal` so tests can exercise it.
    static func confinedResource(_ name: String?, under base: URL) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        let root = base.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = base.appendingPathComponent(name).standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }
    /// Confined lookup in the theme's `icons/` directory.
    func iconResource(_ name: String?) -> URL? { Self.confinedResource(name, under: iconsDirectory) }
    /// Confined lookup at the theme bundle root.
    func rootResource(_ name: String?) -> URL? { Self.confinedResource(name, under: url) }

    /// URL to the theme's preview image — prefers the compact preview.jpg, falls back to preview.png.
    var previewImageURL: URL? {
        for name in ["preview.jpg", "preview.png"] {
            let u = url.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// Icon for the app's Dock icon in Dock Mode. Only an explicit per-theme `dock.appIcon`
    /// overrides it; otherwise nil → keep the default RetroMac app icon (theming comes later).
    func dockIconURL() -> URL? {
        return iconResource(config.dock.appIcon)
    }

    /// Small square icon representing the theme (for the launcher's theme strip). Prefers
    /// `dock.appIcon`, then a bundled `appIcon.png` / `icon.png`. Nil → caller shows a
    /// placeholder (per-theme icons are supplied later).
    func themeIconURL() -> URL? {
        if let u = iconResource(config.dock.appIcon) { return u }
        for name in ["appIcon.png", "icon.png"] {
            if let u = rootResource(name) { return u }
        }
        return nil
    }

    func iconURL(for bundleID: String) -> URL? {
        return iconResource(config.iconMappings[bundleID])
    }

    func fallbackIconURL() -> URL? {
        return iconResource(config.fallbackIcon)
    }

    func startButtonIconURL() -> URL? {
        return iconResource(config.dock.startButtonIcon)
    }

    func startButtonImageURL() -> URL? {
        return iconResource(config.dock.startButtonImage)
    }

    /// Returns all icon image files available in this theme's icons directory
    func availableIcons() -> [(name: String, url: URL)] {
        let fm = FileManager.default
        let dir = iconsDirectory
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "icns", "tiff", "tif"]
        return contents
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { (name: $0.deletingPathExtension().lastPathComponent, url: $0) }
    }

    func wallpaperURL() -> URL? {
        return rootResource(config.wallpaper)
    }

    /// Returns all available wallpaper options for this theme
    func wallpaperOptions() -> [(name: String, url: URL)] {
        var options: [(name: String, url: URL)] = []

        // Add wallpapers from the wallpapers array
        if let wallpapers = config.wallpapers {
            for wp in wallpapers {
                if let wpURL = rootResource(wp.file) {
                    options.append((name: wp.name, url: wpURL))
                }
            }
        }

        // If no wallpapers array, use the single wallpaper field
        if options.isEmpty, let filename = config.wallpaper {
            if let wpURL = rootResource(filename) {
                let name = (filename as NSString).deletingPathExtension
                    .replacingOccurrences(of: "wallpaper-", with: "")
                    .replacingOccurrences(of: "wallpaper", with: "Default")
                    .capitalized
                options.append((name: name, url: wpURL))
            }
        }

        return options
    }

    func previewImage() -> NSImage? {
        guard let previewURL = previewImageURL else { return nil }
        return NSImage(contentsOf: previewURL)
    }

    func backgroundImage() -> NSImage? {
        guard let bgURL = rootResource(config.dock.backgroundImage) else { return nil }
        return NSImage(contentsOf: bgURL)
    }

    func save(config: DockThemeConfig) throws {
        guard !isBuiltIn else {
            print("[Theme] Cannot save to built-in theme")
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        let jsonURL = url.appendingPathComponent("theme.json")
        try data.write(to: jsonURL, options: .atomic)
    }

    static func create(name: String, basedOn source: ThemeBundle, at directory: URL) throws -> ThemeBundle {
        let safeName = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let bundleName = "\(safeName).retromactheme"
        let destURL = directory.appendingPathComponent(bundleName)
        let fm = FileManager.default

        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: source.url, to: destURL)

        var newConfig = source.config
        newConfig.name = name
        // A duplicate is a NEW theme, not the source under another name: give it a fresh id so it
        // cannot inherit (or fight over) the source's per-theme settings. The random suffix keeps
        // two copies made under the same display name distinct.
        newConfig.id = "user.\(slugify(name)).\(UUID().uuidString.prefix(8).lowercased())"
        newConfig.schemaVersion = max(source.config.schemaVersion ?? 0, 2)

        // Write the manifest BEFORE constructing the bundle — the initializer derives `stableID`
        // from what is on disk, so creating it first would capture the source's id.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(newConfig).write(to: destURL.appendingPathComponent("theme.json"), options: .atomic)

        return try ThemeBundle(url: destURL, isBuiltIn: false)
    }
}
