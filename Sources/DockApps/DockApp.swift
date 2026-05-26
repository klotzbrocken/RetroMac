import AppKit

struct DockApp: Codable, Identifiable, Equatable {
    var bundleID: String
    var customIconPath: String?
    var order: Int
    var folderPath: String?  // non-nil = this is a folder item, not an app

    var id: String { bundleID }

    var isFolder: Bool { folderPath != nil }

    var displayName: String {
        if let folderPath = folderPath {
            return (folderPath as NSString).lastPathComponent
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            if let bundle = Bundle(url: url) {
                return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
            }
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID.components(separatedBy: ".").last ?? bundleID
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
