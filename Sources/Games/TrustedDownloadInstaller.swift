import AppKit
import CryptoKit

/// One place for every "download something from the internet and install it" primitive:
/// download, extract (unzip / mount DMG), locate the `.app`, and the security-critical
/// install-to-/Applications with signature/notarization verification, quarantine policy and
/// atomic rollback. Both `AppDelegate`'s game installers and `EmulatorInstaller` funnel through
/// this, so the Gatekeeper policy lives in exactly one implementation and cannot drift.
///
/// UI-free: the unverified-app prompt and progress window are supplied by the caller.
/// The primitives run synchronously — call them off the main thread.
enum TrustedDownloadInstaller {

    // MARK: - Download

    /// `curl -L` a URL to `dest`. Returns true only on exit 0, a present file, size ≥ `minBytes`,
    /// and — when `sha256` is given — a matching digest (pin known-stable archives).
    @discardableResult
    static func download(_ url: URL, to dest: URL, minBytes: Int = 0, sha256: String? = nil) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        p.arguments = ["-L", "-s", "-o", dest.path,
                       "-H", "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
                       url.absoluteString]
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        let fm = FileManager.default
        guard p.terminationStatus == 0, fm.fileExists(atPath: dest.path) else { return false }
        if minBytes > 0 {
            let size = ((try? fm.attributesOfItem(atPath: dest.path))?[.size] as? Int) ?? 0
            if size < minBytes { return false }
        }
        if let expected = sha256 {
            guard let actual = sha256Hex(of: dest),
                  actual.caseInsensitiveCompare(expected) == .orderedSame else {
                print("[Installer] SHA-256 mismatch for \(url.lastPathComponent)")
                return false
            }
        }
        return true
    }

    // MARK: - Extract

    /// Run `/usr/bin/unzip` and return true only on a clean (exit status 0) extraction.
    /// Callers must still validate that the expected files landed.
    @discardableResult
    static func unzip(_ zip: URL, into dir: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-o", zip.path, "-d", dir.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// Mount a DMG read-only, run `body(mountPoint)`, then always detach. Returns body's result,
    /// or nil if the mount failed.
    static func withMountedDMG<T>(_ dmg: URL, _ body: (URL) -> T) -> T? {
        let fm = FileManager.default
        let mount = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dmg_mount_\(UUID().uuidString)")
        try? fm.createDirectory(at: mount, withIntermediateDirectories: true)

        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attach.arguments = ["attach", "-nobrowse", "-readonly", "-mountpoint", mount.path, dmg.path]
        attach.standardOutput = FileHandle.nullDevice
        attach.standardError = FileHandle.nullDevice
        do { try attach.run() } catch { return nil }
        attach.waitUntilExit()
        guard attach.terminationStatus == 0 else { return nil }
        defer {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mount.path, "-quiet"]
            detach.standardOutput = FileHandle.nullDevice
            detach.standardError = FileHandle.nullDevice
            try? detach.run(); detach.waitUntilExit()
        }
        return body(mount)
    }

    // MARK: - Locate

    /// Recursively find an `.app` bundle whose name contains `name` (case-insensitive).
    static func findAppBundle(named name: String, in directory: URL) -> URL? {
        let fm = FileManager.default
        let dir = directory.path
        let needle = name.lowercased()
        if let contents = try? fm.contentsOfDirectory(atPath: dir),
           let app = contents.first(where: { $0.lowercased().contains(needle) && $0.hasSuffix(".app") }) {
            return directory.appendingPathComponent(app)
        }
        if let e = fm.enumerator(atPath: dir) {
            while let file = e.nextObject() as? String {
                if file.hasSuffix(".app") && file.lowercased().contains(needle) {
                    return directory.appendingPathComponent(file)
                }
            }
        }
        return nil
    }

    // MARK: - GitHub release resolution

    struct ReleaseAsset { let url: URL; let name: String; let version: String }
    enum ReleaseError: Error { case fetchFailed(String?); case noMatchingAsset(version: String) }

    /// Resolve the latest GitHub release's asset whose name satisfies `matches`. Async (URLSession);
    /// `completion` runs on a background queue — hop to main for UI.
    static func latestReleaseAsset(repo: String, matches: @escaping (String) -> Bool,
                                   completion: @escaping (Result<ReleaseAsset, ReleaseError>) -> Void) {
        guard let apiURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            completion(.failure(.fetchFailed(nil))); return
        }
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assets = json["assets"] as? [[String: Any]] else {
                completion(.failure(.fetchFailed(error?.localizedDescription))); return
            }
            let version = json["tag_name"] as? String ?? "latest"
            guard let asset = assets.first(where: { matches(($0["name"] as? String ?? "").lowercased()) }),
                  let urlStr = asset["browser_download_url"] as? String,
                  let url = URL(string: urlStr) else {
                completion(.failure(.noMatchingAsset(version: version))); return
            }
            completion(.success(ReleaseAsset(url: url, name: asset["name"] as? String ?? repo, version: version)))
        }.resume()
    }

    // MARK: - Install (security-critical)

    enum InstallResult { case installed, cancelled, failed(String) }

    /// Verify a downloaded `.app` (codesign + notarization) and install it to /Applications
    /// atomically. On verification failure, `confirmUnverified()` decides whether to proceed
    /// (warn-but-allow). Quarantine is preserved for verified apps (Gatekeeper approves a
    /// notarized app silently); it is stripped only when the user consents to an unverified one.
    /// A failed copy never destroys the previously installed app (staging + `replaceItemAt`).
    static func installVerifiedApp(bundleAt src: URL, to targetURL: URL,
                                   confirmUnverified: () -> Bool) -> InstallResult {
        let fm = FileManager.default
        let name = targetURL.lastPathComponent

        let verified = AppSignatureVerifier.verifyAppSignature(at: src.path)
        if !verified && !confirmUnverified() { return .cancelled }

        // Stage on the SAME volume as the target (its own directory) for an atomic replace.
        let stagingURL = targetURL.deletingLastPathComponent()
            .appendingPathComponent("." + name + ".new-\(UUID().uuidString)")
        do {
            if fm.fileExists(atPath: stagingURL.path) { try fm.removeItem(at: stagingURL) }
            try fm.copyItem(at: src, to: stagingURL)
            if fm.fileExists(atPath: targetURL.path) {
                _ = try fm.replaceItemAt(targetURL, withItemAt: stagingURL)   // atomic; original kept on throw
            } else {
                try fm.moveItem(at: stagingURL, to: targetURL)
            }
            if !verified {   // informed consent → make the unsigned app launchable
                let xattr = Process()
                xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                xattr.arguments = ["-rd", "com.apple.quarantine", targetURL.path]
                xattr.standardOutput = FileHandle.nullDevice
                xattr.standardError = FileHandle.nullDevice
                try? xattr.run(); xattr.waitUntilExit()
            }
            print("[Installer] Installed \(name) to /Applications")
            return .installed
        } catch {
            try? fm.removeItem(at: stagingURL)   // the existing app is untouched
            print("[Installer] Failed to install \(name): \(error)")
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private static func sha256Hex(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
