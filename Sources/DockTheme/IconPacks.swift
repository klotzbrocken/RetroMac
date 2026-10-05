import AppKit
import CryptoKit

/// Historic icons for modern apps (Lastenheft 3.0, section 9). Maik delivers them by hand as an
/// icon package; RetroMac checks, stores and shows them (ICO-01). A package is a folder with an
/// `icons.json` and its PNG files:
///
///     { "format": 1, "themeID": "com.retromac.sun.solaris8-cde", "source": "Maik",
///       "icons": [ { "appID": "claude", "bundleIDs": ["com.anthropic.claudefordesktop"],
///                    "kind": "era-adaptation", "referenceVersion": "Stiladaption",
///                    "usageStatus": "released",
///                    "variants": [ { "file": "claude-32.png", "size": 32, "scale": 1 },
///                                  { "file": "claude-32@2x.png", "size": 32, "scale": 2 } ] } ] }
///
/// The checksum is worked out on import, not delivered (ICO-05). A package sits beside the theme's
/// own `iconMappings`, which keep working: the delivered package comes first, then the theme's own
/// mapping (ICO-07).
struct IconPackManifest: Codable, Equatable {
    var format: Int
    var themeID: String
    var source: String?
    var icons: [Entry]

    struct Entry: Codable, Equatable {
        var appID: String
        var bundleIDs: [String]
        var kind: Kind
        var referenceVersion: String
        var usageStatus: UsageStatus
        var source: String?
        var variants: [Variant]
        /// SHA-256 over the variants' files, set on import (cache invalidation, ICO-11).
        var checksum: String?
    }
    struct Variant: Codable, Equatable {
        var file: String
        /// Logical size in points, and the scale it is drawn at (1 or 2).
        var size: Int
        var scale: Int
    }
    /// ICO-02: an icon of the era's own app, or a modern app drawn in the era's style. An
    /// adaptation is never shown as an original.
    enum Kind: String, Codable { case historicalOriginal = "historical-original", eraAdaptation = "era-adaptation" }
    enum UsageStatus: String, Codable { case released, unchecked, notForRelease = "not-for-release" }
}

/// What an import did: which apps came in, which were turned away and why, and which kept the
/// icon they had because their new one was faulty (ICO-A2).
struct IconImportReport: Codable, Equatable {
    var accepted: [String] = []
    var invalid: [Problem] = []
    var kept: [String] = []
    struct Problem: Codable, Equatable { var appID: String; var reason: String }
}

enum IconPackError: LocalizedError, Equatable {
    case noManifest, unreadableManifest(String), unknownFormat(Int), unknownTheme(String)
    var errorDescription: String? {
        switch self {
        case .noManifest: return "The folder has no icons.json."
        case .unreadableManifest(let why): return "icons.json cannot be read: \(why)"
        case .unknownFormat(let f): return "icons.json is format \(f); this RetroMac reads format 1."
        case .unknownTheme(let id): return "There is no theme \(id)."
        }
    }
}

final class IconPackStore {
    static let shared = IconPackStore()

    /// Where the checked packages live: one folder per theme, holding its manifest, the last
    /// import's report and the icon files.
    static var root: URL {
        rootForTests ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RetroMac/IconPacks", isDirectory: true)
    }
    static var rootForTests: URL?
    static func folder(for themeID: String) -> URL { root.appendingPathComponent(themeID, isDirectory: true) }

    private let lock = NSLock()
    private var manifests: [String: IconPackManifest?] = [:]
    private var decoded: [String: [String: NSBitmapImageRep]] = [:]   // themeID → file → rep
    private var warming: Set<String> = []
    /// Raised by every change, so a read still under way for the old package is dropped.
    private var generation = 0

    // MARK: Validation (pure, ICO-04/05)

    /// Checks every entry of a package against its folder. Valid entries come back with their
    /// checksums; the others with the reason. Nothing is copied or changed.
    static func validate(_ manifest: IconPackManifest, in folder: URL) -> (valid: [IconPackManifest.Entry], invalid: [IconImportReport.Problem]) {
        var valid: [IconPackManifest.Entry] = [], invalid: [IconImportReport.Problem] = []
        var seenApps = Set<String>(), seenBundles = Set<String>()
        for var e in manifest.icons {
            func reject(_ why: String) { invalid.append(.init(appID: e.appID.isEmpty ? "?" : e.appID, reason: why)) }
            guard !e.appID.isEmpty else { reject("no appID"); continue }
            guard seenApps.insert(e.appID).inserted else { reject("appID twice in the package"); continue }
            guard !e.bundleIDs.isEmpty, e.bundleIDs.allSatisfy({ $0.contains(".") && !$0.contains(" ") }) else {
                reject("needs exact bundle IDs (reverse-DNS, no names)"); continue
            }
            if let twice = e.bundleIDs.first(where: { seenBundles.contains($0) }) { reject("\(twice) belongs to another app in the package"); continue }
            guard !e.referenceVersion.trimmingCharacters(in: .whitespaces).isEmpty else { reject("no referenceVersion"); continue }
            if e.kind == .eraAdaptation, !["stiladaption", "adaptation"].contains(where: e.referenceVersion.lowercased().contains) {
                reject("an era-adaptation names no historical version; referenceVersion must say Stiladaption"); continue
            }
            guard !e.variants.isEmpty else { reject("no image files"); continue }
            var hasher = SHA256()
            var problem: String?
            for v in e.variants {
                guard !v.file.contains(".."), !v.file.hasPrefix("/") else { problem = "\(v.file): path leaves the package"; break }
                guard [1, 2].contains(v.scale), v.size > 0 else { problem = "\(v.file): size and scale 1 or 2 needed"; break }
                let url = folder.appendingPathComponent(v.file)
                guard let data = try? Data(contentsOf: url) else { problem = "\(v.file): missing"; break }
                guard let rep = NSBitmapImageRep(data: data), data.starts(with: [0x89, 0x50, 0x4E, 0x47]) else { problem = "\(v.file): not a PNG"; break }
                guard rep.pixelsWide == v.size * v.scale, rep.pixelsHigh == v.size * v.scale else {
                    problem = "\(v.file): \(rep.pixelsWide)×\(rep.pixelsHigh) pixels, \(v.size * v.scale)×\(v.size * v.scale) declared"; break
                }
                guard rep.hasAlpha else { problem = "\(v.file): no alpha channel"; break }
                hasher.update(data: data)
            }
            if let problem { reject(problem); continue }
            e.checksum = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            seenBundles.formUnion(e.bundleIDs)
            valid.append(e)
        }
        return (valid, invalid)
    }

    /// The new package merged over the installed one: a valid new entry replaces the app's old
    /// one, a faulty new entry leaves the old one in place (ICO-10). Not-for-release entries are
    /// checked but not taken.
    static func merge(installed: [IconPackManifest.Entry], valid: [IconPackManifest.Entry],
                      invalid: [IconImportReport.Problem]) -> (entries: [IconPackManifest.Entry], report: IconImportReport) {
        var report = IconImportReport(invalid: invalid)
        let taken = valid.filter { $0.usageStatus != .notForRelease }
        let newApps = Set(taken.map(\.appID))
        var entries = installed.filter { !newApps.contains($0.appID) }
        report.kept = installed.filter { old in invalid.contains { $0.appID == old.appID } }.map(\.appID)
        // An old entry whose bundle IDs a new app takes over goes, or one ID would mean two icons.
        let newBundles = Set(taken.flatMap(\.bundleIDs))
        entries.removeAll { !Set($0.bundleIDs).isDisjoint(with: newBundles) }
        entries += taken
        report.accepted = taken.map(\.appID)
        return (entries.sorted { $0.appID < $1.appID }, report)
    }

    // MARK: Import (ICO-10)

    /// Checks the package, then swaps it in whole: the files of every entry that stays are copied
    /// into a fresh folder, which replaces the old one only when it is complete.
    @discardableResult
    func importPackage(at folder: URL, themes: [String]? = nil) throws -> IconImportReport {
        let manifestURL = folder.appendingPathComponent("icons.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw IconPackError.noManifest }
        let manifest: IconPackManifest
        do { manifest = try JSONDecoder().decode(IconPackManifest.self, from: Data(contentsOf: manifestURL)) }
        catch { throw IconPackError.unreadableManifest(error.localizedDescription) }
        guard manifest.format == 1 else { throw IconPackError.unknownFormat(manifest.format) }
        guard (themes ?? ThemeManager.shared.availableThemes.map(\.stableID)).contains(manifest.themeID) else {
            throw IconPackError.unknownTheme(manifest.themeID)
        }
        let (valid, invalid) = Self.validate(manifest, in: folder)
        let target = Self.folder(for: manifest.themeID)
        let installed = self.manifest(for: manifest.themeID)
        let (entries, report) = Self.merge(installed: installed?.icons ?? [], valid: valid, invalid: invalid)

        let fm = FileManager.default
        let staging = Self.root.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let newApps = Set(valid.map(\.appID))
        for e in entries {
            let from = newApps.contains(e.appID) ? folder : target
            for v in e.variants {
                let dest = staging.appendingPathComponent(v.file)
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: from.appendingPathComponent(v.file), to: dest)
            }
        }
        let out = IconPackManifest(format: 1, themeID: manifest.themeID, source: manifest.source ?? installed?.source, icons: entries)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(out).write(to: staging.appendingPathComponent("icons.json"))
        try enc.encode(report).write(to: staging.appendingPathComponent("report.json"))
        try fm.createDirectory(at: Self.root, withIntermediateDirectories: true)
        if fm.fileExists(atPath: target.path) { _ = try fm.replaceItemAt(target, withItemAt: staging) }
        else { try fm.moveItem(at: staging, to: target) }
        changed(manifest.themeID)
        return report
    }

    func remove(themeID: String) {
        try? FileManager.default.removeItem(at: Self.folder(for: themeID))
        changed(themeID)
    }

    /// Forget what was read and decoded, and let every surface draw again (ICO-A5).
    private func changed(_ themeID: String) {
        lock.lock(); manifests[themeID] = nil; decoded[themeID] = nil; warming.remove(themeID); generation += 1; lock.unlock()
        DispatchQueue.main.async {
            ThemeManager.shared.clearCache()
            NotificationCenter.default.post(name: .dockAppsChanged, object: nil)
        }
    }

    // MARK: Reading

    func manifest(for themeID: String) -> IconPackManifest? {
        lock.lock(); defer { lock.unlock() }
        if let m = manifests[themeID] { return m }
        let url = Self.folder(for: themeID).appendingPathComponent("icons.json")
        let m = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(IconPackManifest.self, from: $0) }
        manifests[themeID] = m
        return m
    }

    func lastReport(for themeID: String) -> IconImportReport? {
        (try? Data(contentsOf: Self.folder(for: themeID).appendingPathComponent("report.json")))
            .flatMap { try? JSONDecoder().decode(IconImportReport.self, from: $0) }
    }

    func entry(themeID: String, bundleID: String) -> IconPackManifest.Entry? {
        manifest(for: themeID)?.icons.first { $0.bundleIDs.contains(bundleID) }
    }

    /// A key that changes with the package, for the icon cache (ICO-11).
    func revision(themeID: String) -> String {
        manifest(for: themeID)?.icons.compactMap(\.checksum).joined().hashValue.description ?? "-"
    }

    /// The variants nearest the size asked for: an exact logical size when the package has one,
    /// else the next larger, else the largest; a 48 is not shrunk to 16 when a 16 exists (ICO-06).
    static func pick(_ variants: [IconPackManifest.Variant], for size: CGFloat) -> [IconPackManifest.Variant] {
        let sizes = Set(variants.map(\.size)).sorted()
        guard let chosen = sizes.first(where: { CGFloat($0) >= size.rounded() }) ?? sizes.last else { return [] }
        return variants.filter { $0.size == chosen }
    }

    /// The app's icon from the package, at `size` points with its 1× and 2× pictures, or nil when
    /// the package has none, or when its pictures are still being read on a background queue
    /// (the surfaces draw again when they are in).
    func image(themeID: String, bundleID: String, size: CGFloat) -> NSImage? {
        guard let e = entry(themeID: themeID, bundleID: bundleID), e.usageStatus != .notForRelease else { return nil }
        lock.lock()
        let reps = decoded[themeID]
        lock.unlock()
        guard let reps else { warm(themeID); return nil }
        let chosen = Self.pick(e.variants, for: size).compactMap { reps[$0.file] }
        guard !chosen.isEmpty else { return nil }
        let img = NSImage(size: NSSize(width: size, height: size))
        for r in chosen { r.size = NSSize(width: size, height: size); img.addRepresentation(r) }
        return img
    }

    /// Reads and decodes a theme's package off the main thread (ICO-11), then lets the surfaces
    /// draw again.
    private func warm(_ themeID: String) {
        lock.lock()
        guard !warming.contains(themeID) else { lock.unlock(); return }
        warming.insert(themeID)
        let started = generation
        lock.unlock()
        let folder = Self.folder(for: themeID)
        let files = manifest(for: themeID)?.icons.flatMap { $0.variants.map(\.file) } ?? []
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var out: [String: NSBitmapImageRep] = [:]
            for f in files {
                guard let data = try? Data(contentsOf: folder.appendingPathComponent(f)),
                      let src = CGImageSourceCreateWithData(data as CFData, nil),
                      let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { continue }
                out[f] = NSBitmapImageRep(cgImage: cg)
            }
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard self.generation == started else { return }   // a newer package came in meanwhile
            self.decoded[themeID] = out; self.warming.remove(themeID)
            DispatchQueue.main.async {
                ThemeManager.shared.clearCache()
                NotificationCenter.default.post(name: .dockAppsChanged, object: nil)
            }
        }
    }

    // MARK: Status (ICO-10)

    struct Status: Equatable { var delivered = 0, mapped = 0, missing = 0, invalid = 0 }

    /// Delivered: icons in the package. Mapped: of those, apps installed here. Missing: catalog
    /// apps installed here with no icon of the theme's own. Invalid: turned away at the last import.
    func status(themeID: String, theme: ThemeBundle?, installed: (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }) -> Status {
        let icons = manifest(for: themeID)?.icons.filter { $0.usageStatus != .notForRelease } ?? []
        var s = Status()
        s.delivered = icons.count
        s.mapped = icons.filter { $0.bundleIDs.contains(where: installed) }.count
        let covered = Set(icons.flatMap(\.bundleIDs)).union(theme?.config.iconMappings.keys.map { $0 } ?? [])
        s.missing = IconCatalog.apps.filter { app in
            let present = app.bundleIDs.filter(installed)
            return !present.isEmpty && present.allSatisfy { !covered.contains($0) }
        }.count
        s.invalid = lastReport(for: themeID)?.invalid.count ?? 0
        return s
    }
}

/// The working catalogue of Lastenheft 3.0, ICO-03: the apps a package is expected to cover,
/// with their bundle IDs. IDs marked verified were found on a real installation.
enum IconCatalog {
    struct App: Codable, Equatable { var appID: String; var name: String; var group: String; var bundleIDs: [String]; var verified: [String] }
    static let apps: [App] = {
        guard let url = Bundle.main.url(forResource: "IconCatalog", withExtension: "json")
                ?? Bundle.sourceTreeResource("IconCatalog"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([App].self, from: data)) ?? []
    }()
}

private extension Bundle {
    /// The catalogue next to the sources, for the test runner, which has no app bundle.
    static func sourceTreeResource(_ name: String) -> URL? {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/\(name).json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
