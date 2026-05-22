import AppKit
import Foundation

/// Checks GitHub Releases for new versions and prompts the user to download.
final class UpdateChecker {
    static let shared = UpdateChecker()

    // MARK: - Configuration
    private let owner = "klotzbrocken"
    private let repo  = "RetroMac"
    private let checkInterval: TimeInterval = 4 * 3600  // every 4 hours

    private var timer: Timer?
    private var lastCheckDate: Date?

    private var releasesURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
    }
    private var downloadPageURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")!
    }

    /// Current app version from Info.plist
    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    // MARK: - Public API

    /// Start periodic background checks.
    func startPeriodicChecks() {
        // Check once shortly after launch (15s delay to not slow startup)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.checkForUpdates(silent: true)
        }
        // Then every 4 hours
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkForUpdates(silent: true)
        }
    }

    /// Manual check (from menu item) — always shows result.
    @objc func checkNow(_ sender: Any? = nil) {
        checkForUpdates(silent: false)
    }

    // MARK: - Implementation

    private func checkForUpdates(silent: Bool) {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            self.lastCheckDate = Date()

            if let error = error {
                if !silent { self.showError("Update-Check fehlgeschlagen: \(error.localizedDescription)") }
                print("[Update] Check failed: \(error.localizedDescription)")
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                if !silent { self.showError("Konnte Release-Info nicht lesen.") }
                print("[Update] Failed to parse response")
                return
            }

            let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let current = self.currentVersion
            print("[Update] Current: \(current), Latest: \(remoteVersion)")

            if self.isNewer(remote: remoteVersion, than: current) {
                let body = json["body"] as? String ?? ""
                let name = json["name"] as? String ?? "RetroMac \(remoteVersion)"
                DispatchQueue.main.async {
                    self.showUpdateAlert(version: remoteVersion, name: name, notes: body)
                }
            } else if !silent {
                DispatchQueue.main.async {
                    self.showUpToDate()
                }
            }
        }.resume()
    }

    /// Simple semantic version comparison (1.2.3 > 1.2.0)
    private func isNewer(remote: String, than current: String) -> Bool {
        let rParts = remote.split(separator: ".").compactMap { Int($0) }
        let cParts = current.split(separator: ".").compactMap { Int($0) }
        let count = max(rParts.count, cParts.count)
        for i in 0..<count {
            let r = i < rParts.count ? rParts[i] : 0
            let c = i < cParts.count ? cParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }

    // MARK: - UI

    private func showUpdateAlert(version: String, name: String, notes: String) {
        let alert = NSAlert()
        alert.messageText = "RetroMac \(version) verfügbar"
        alert.informativeText = notes.isEmpty ? "Eine neue Version ist verfügbar." : String(notes.prefix(500))
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Später")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(downloadPageURL)
        }
    }

    private func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = "RetroMac ist aktuell"
        alert.informativeText = "Du verwendest Version \(currentVersion) — die neueste Version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Update-Check"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
