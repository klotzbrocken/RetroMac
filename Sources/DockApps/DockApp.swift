import AppKit

struct DockApp: Codable, Identifiable, Equatable {
    /// See `displayName`.
    private static var displayNames: [String: String] = [:]

    var bundleID: String
    var customIconPath: String?
    var order: Int
    var folderPath: String?  // non-nil = this is a folder item, not an app

    var id: String { bundleID }

    var isFolder: Bool { folderPath != nil }

    /// The name the dock shows. Looked up once per bundle id and kept: the lookup opens the
    /// app's bundle and reads its localized Info.plist from disk, and the Aqua dock asked for it
    /// on every mouse move while magnifying — measured at a quarter of the main thread's time
    /// during a sweep along the dock, and the stutter that went with it.
    var displayName: String {
        if let folderPath = folderPath {
            return (folderPath as NSString).lastPathComponent
        }
        if let cached = Self.displayNames[bundleID] { return cached }
        let name: String
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            if let bundle = Bundle(url: url) {
                name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
            } else {
                name = url.deletingPathExtension().lastPathComponent
            }
        } else {
            name = bundleID.components(separatedBy: ".").last ?? bundleID
        }
        Self.displayNames[bundleID] = name
        return name
    }

    var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    var isInstalled: Bool {
        if isFolder {
            return FileManager.default.fileExists(atPath: folderPath!)
        }
        return applicationURL != nil
    }
}

struct DockAppsConfig: Codable {
    var version: Int = 1
    var items: [DockApp]
}
