import AppKit

struct DockApp: Codable, Identifiable, Equatable {
    var bundleID: String
    var customIconPath: String?
    var order: Int

    var id: String { bundleID }

    var displayName: String {
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
        applicationURL != nil
    }
}

struct DockAppsConfig: Codable {
    var version: Int = 1
    var items: [DockApp]
}
