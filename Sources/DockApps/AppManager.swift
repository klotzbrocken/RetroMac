import AppKit

final class AppManager {
    static let shared = AppManager()

    private(set) var apps: [DockApp] = []
    private let configURL: URL

    private static let defaultBundleIDs: [(String, String)] = [
        ("com.apple.finder", "Finder"),
        ("com.apple.Safari", "Safari"),
        ("com.apple.mail", "Mail"),
        ("com.apple.Photos", "Photos"),
        ("com.apple.MobileSMS", "Messages"),
        ("com.apple.Notes", "Notes"),
        ("com.apple.iCal", "Calendar"),
        ("com.apple.systempreferences", "System Settings"),
        ("com.apple.Music", "Music"),
        ("com.apple.Terminal", "Terminal"),
    ]

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("RetroMac")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        configURL = dir.appendingPathComponent("dock-apps.json")
        load()
    }

    func load() {
        if FileManager.default.fileExists(atPath: configURL.path) {
            do {
                let data = try Data(contentsOf: configURL)
                let config = try JSONDecoder().decode(DockAppsConfig.self, from: data)
                apps = config.items.filter { $0.isInstalled }.sorted { $0.order < $1.order }
                print("[Dock] Loaded \(apps.count) dock apps")
            } catch {
                print("[Dock] Failed to load apps config: \(error)")
                initDefaults()
            }
        } else {
            initDefaults()
        }
    }

    private func initDefaults() {
        var items: [DockApp] = []
        for (i, (bundleID, _)) in Self.defaultBundleIDs.enumerated() {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil {
                items.append(DockApp(bundleID: bundleID, customIconPath: nil, order: i))
            }
        }
        apps = items
        save()
        print("[Dock] Initialized default dock apps: \(apps.count) apps")
    }

    func save() {
        // Preserve ALL fields (esp. folderPath) — only renumber `order`. Reconstructing
        // with the 3-arg init silently dropped folderPath, turning folder items into
        // broken "app" entries that vanished on reload.
        let normalized = apps.enumerated().map { i, app -> DockApp in
            var a = app
            a.order = i
            return a
        }
        apps = normalized
        let config = DockAppsConfig(items: normalized)
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            print("[Dock] Failed to save apps config: \(error)")
        }
    }

    func addApp(bundleID: String) {
        guard !apps.contains(where: { $0.bundleID == bundleID }) else { return }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { return }
        apps.append(DockApp(bundleID: bundleID, customIconPath: nil, order: apps.count))
        save()
        NotificationCenter.default.post(name: .dockAppsChanged, object: nil)
    }

    func addFolder(path: String) {
        let folderID = "__folder__\(path)"
        guard !apps.contains(where: { $0.bundleID == folderID }) else { return }
        guard FileManager.default.fileExists(atPath: path) else { return }
        apps.append(DockApp(bundleID: folderID, customIconPath: nil, order: apps.count, folderPath: path))
        save()
        NotificationCenter.default.post(name: .dockAppsChanged, object: nil)
    }

    /// Pin/unpin the user's Downloads folder automatically for themes that use folder stacks
    /// (Maiks Favourite). Tracked with a flag so we don't fight a manual remove and so it's
    /// taken back out when switching to a non-stack theme.
    func syncAutoDownloads(active: Bool) {
        let path = NSHomeDirectory() + "/Downloads"
        let id = "__folder__\(path)"
        let present = apps.contains { $0.bundleID == id }
        let flag = "autoDownloadsAdded"
        let added = UserDefaults.standard.bool(forKey: flag)
        if active {
            // Ensure the Downloads folder is present whenever a folder-stack theme is active.
            guard !present, FileManager.default.fileExists(atPath: path) else { return }
            apps.append(DockApp(bundleID: id, customIconPath: nil, order: apps.count, folderPath: path))
            UserDefaults.standard.set(true, forKey: flag)
            save()
            NotificationCenter.default.post(name: .dockAppsChanged, object: nil)
        } else if added {
            if present { apps.removeAll { $0.bundleID == id }; save() }
            UserDefaults.standard.set(false, forKey: flag)
            NotificationCenter.default.post(name: .dockAppsChanged, object: nil)
        }
    }

    func removeApp(bundleID: String) {
        apps.removeAll { $0.bundleID == bundleID }
        save()
        NotificationCenter.default.post(name: .dockAppsChanged, object: nil)
    }

    func moveApp(from sourceIndex: Int, to destIndex: Int) {
        guard sourceIndex != destIndex,
              sourceIndex >= 0, sourceIndex < apps.count,
              destIndex >= 0, destIndex < apps.count else { return }
        let app = apps.remove(at: sourceIndex)
        apps.insert(app, at: destIndex)
        save()
        NotificationCenter.default.post(name: .dockAppsChanged, object: nil)
    }

    func setCustomIcon(for bundleID: String, path: String?) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        apps[idx].customIconPath = path
        save()
        NotificationCenter.default.post(name: .dockAppsChanged, object: nil)
    }
}

extension Notification.Name {
    static let dockAppsChanged = Notification.Name("DockAppsChanged")
    static let dockThemeChanged = Notification.Name("DockThemeChanged")
    static let virtualCameraStateChanged = Notification.Name("VirtualCameraStateChanged")
    static let pacmanAnimationChanged = Notification.Name("PacmanAnimationChanged")
    static let deskbarSettingsChanged = Notification.Name("DeskbarSettingsChanged")
    static let dockModeChanged = Notification.Name("DockModeChanged")
}
