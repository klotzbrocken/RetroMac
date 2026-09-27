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

    /// Pin/unpin the user's Downloads folder automatically for themes that use folder stacks.
    func syncAutoDownloads(active: Bool) {
        syncAutoFolder(path: NSHomeDirectory() + "/Downloads", flag: "autoDownloadsAdded", active: active)
    }

    /// Same for /Applications, which Snow Leopard keeps in the dock as a grid stack.
    func syncAutoApplications(active: Bool) {
        syncAutoFolder(path: "/Applications", flag: "autoApplicationsAdded", active: active)
    }

    /// Pin/unpin a folder automatically for themes that use folder stacks (Maiks Favourite,
    /// Snow Leopard). Tracked with a per-folder flag so we don't fight a manual remove and so
    /// it's taken back out when switching to a non-stack theme.
    private func syncAutoFolder(path: String, flag: String, active: Bool) {
        let id = "__folder__\(path)"
        let present = apps.contains { $0.bundleID == id }
        let added = UserDefaults.standard.bool(forKey: flag)
        if active {
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

    /// `apps` with `id` moved to `slot` of its row. `slot` counts the items `inRow` puts in the
    /// same row, *without* the moved one — the dock counts the icons it drops between the
    /// same way — and the item goes before the one at that slot, or after the row's last.
    static func reordered(_ apps: [DockApp], moving id: String, toSlot slot: Int,
                          inRow: (DockApp) -> Bool) -> [DockApp] {
        var list = apps
        guard let from = list.firstIndex(where: { $0.bundleID == id }) else { return apps }
        let item = list.remove(at: from)
        let row = list.indices.filter { inRow(list[$0]) }
        let to: Int
        if slot < row.count { to = row[max(0, slot)] }
        else { to = row.last.map { $0 + 1 } ?? list.count }
        list.insert(item, at: min(to, list.count))
        return list
    }

    /// Move a pinned item to `slot` of its row — a drag along the dock.
    func move(bundleID: String, toSlot slot: Int, inRow: (DockApp) -> Bool) {
        let next = Self.reordered(apps, moving: bundleID, toSlot: slot, inRow: inRow)
        guard next.map(\.bundleID) != apps.map(\.bundleID) else { return }
        apps = next
        save()
        NotificationCenter.default.post(name: .dockAppsChanged, object: nil)
    }

    /// The whole order at once, as the Settings list leaves it after a drag: one save, one
    /// notice. Ids it does not name keep their place after the named ones.
    func setOrder(bundleIDs: [String]) {
        let rank = Dictionary(uniqueKeysWithValues: bundleIDs.enumerated().map { ($1, $0) })
        let next = apps.enumerated().sorted {
            (rank[$0.element.bundleID] ?? Int.max, $0.offset) < (rank[$1.element.bundleID] ?? Int.max, $1.offset)
        }.map(\.element)
        guard next.map(\.bundleID) != apps.map(\.bundleID) else { return }
        apps = next
        save()
        NotificationCenter.default.post(name: .dockAppsChanged, object: nil)
    }

    /// Pin an app where it was dropped rather than at the end of the row.
    func addApp(bundleID: String, atSlot slot: Int, inRow: (DockApp) -> Bool) {
        addApp(bundleID: bundleID)
        guard apps.last?.bundleID == bundleID else { return }   // already there, or not an app
        move(bundleID: bundleID, toSlot: slot, inRow: inRow)
    }

    /// Pin a folder where it was dropped among the folders.
    func addFolder(path: String, atSlot slot: Int, inRow: (DockApp) -> Bool) {
        addFolder(path: path)
        let id = "__folder__\(path)"
        guard apps.last?.bundleID == id else { return }
        move(bundleID: id, toSlot: slot, inRow: inRow)
    }

    func setCustomIcon(for bundleID: String, path: String?) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        apps[idx].customIconPath = path
        save()
        NotificationCenter.default.post(name: .dockAppsChanged, object: nil)
    }
}

extension NSPasteboard.PasteboardType {
    /// A pinned dock item being dragged along the dock (its bundle id, or `__folder__<path>`).
    static let retromacDockItem = NSPasteboard.PasteboardType("com.retromac.dock-item")
}

extension Notification.Name {
    static let dockAppsChanged = Notification.Name("DockAppsChanged")
    static let dockThemeChanged = Notification.Name("DockThemeChanged")
    /// Posted immediately BEFORE the desktop picture is swapped, by every path that swaps it.
    ///
    /// The desktop-scope overlay is opaque and shows whatever the capture delivers, and macOS
    /// hands out a black frame or two while it exchanges the wallpaper. This is the only moment
    /// that is known in advance, so it is the only place a freeze can start early enough — a
    /// notification sent afterwards arrives when the flash has already been drawn.
    static let desktopPictureWillChange = Notification.Name("DesktopPictureWillChange")
    static let virtualCameraStateChanged = Notification.Name("VirtualCameraStateChanged")
    static let overlayStateChanged = Notification.Name("OverlayStateChanged")
    static let shaderScopeChanged = Notification.Name("ShaderScopeChanged")
    static let pacmanAnimationChanged = Notification.Name("PacmanAnimationChanged")
    static let deskbarSettingsChanged = Notification.Name("DeskbarSettingsChanged")
    static let dockModeChanged = Notification.Name("DockModeChanged")
    static let clockFormatChanged = Notification.Name("ClockFormatChanged")
    static let cameraSceneChanged = Notification.Name("CameraSceneChanged")
}
