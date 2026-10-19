import AppKit

/// The Themes tab of RetroHub: themes that are not in the app, offered for download.
///
/// The list lives in the repository, not in the app, so a new theme needs no RetroMac update:
/// `catalog/themes.json` on main, read from raw.githubusercontent.com. Each entry names a .zip
/// holding one .retromactheme and its SHA-256; a download that does not match is not installed,
/// and what is installed goes through the same checks as a theme opened from the Finder.
///
///     { "themes": [ { "id": "com.example.theme", "name": "…", "author": "…",
///                     "summary": "…", "era": "Windows 3.11 · 1993",
///                     "preview": "https://….png", "download": "https://….zip",
///                     "sha256": "…", "minAppVersion": "3.0.1" } ] }
enum ThemeCatalog {
    static let url = URL(string: "https://raw.githubusercontent.com/klotzbrocken/RetroMac/main/catalog/themes.json")!

    struct Entry: Codable, Identifiable {
        let id: String
        let name: String
        let author: String
        let summary: String
        let era: String?
        let preview: URL?
        let download: URL
        let sha256: String
        let minAppVersion: String?
    }
    private struct File: Codable { let themes: [Entry] }

    static func load(completion: @escaping (Result<[Entry], Error>) -> Void) {
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { data, _, error in
            let result = Result { () throws -> [Entry] in
                if let error { throw error }
                return try JSONDecoder().decode(File.self, from: data ?? Data()).themes
                    .filter { $0.download.scheme == "https" }
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    static func isInstalled(_ e: Entry) -> Bool {
        ThemeManager.shared.availableThemes.contains { $0.stableID == e.id }
    }

    /// Nil when this RetroMac can use it; otherwise the version it needs.
    static func needsNewerApp(_ e: Entry) -> String? {
        guard let need = e.minAppVersion,
              let have = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              have.compare(need, options: .numeric) == .orderedAscending else { return nil }
        return need
    }

    /// Download, check the SHA-256, install. `completion(nil)` on success, on the main thread.
    static func install(_ e: Entry, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let zip = fm.temporaryDirectory.appendingPathComponent("theme-\(UUID().uuidString).zip")
            defer { try? fm.removeItem(at: zip) }
            guard TrustedDownloadInstaller.download(e.download, to: zip, minBytes: 1_000, sha256: e.sha256) else {
                DispatchQueue.main.async { completion("The download of \(e.name) did not finish or did not match the catalogue.") }
                return
            }
            DispatchQueue.main.sync {
                do {
                    let id = try ThemeManager.shared.importTheme(from: zip)
                    completion(id == e.id ? nil : "\(e.name) was installed, but it is not the theme the catalogue named.")
                } catch {
                    completion(error.localizedDescription)
                }
            }
        }
    }
}
