import AppKit

/// Auto-downloads and installs emulators that support it.
final class EmulatorInstaller {
    static let shared = EmulatorInstaller()
    private init() {}

    private var isInstalling = false

    /// Install an emulator automatically. Shows progress window.
    /// Calls completion(true) on success, completion(false) on failure.
    func install(_ emulator: EmulatorType, completion: @escaping (Bool) -> Void) {
        guard !isInstalling else {
            completion(false)
            return
        }
        guard let downloadURL = emulator.downloadURL,
              let url = URL(string: downloadURL) else {
            openWebsite(emulator)
            completion(false)
            return
        }

        isInstalling = true
        let progressWindow = InstallProgressWindow.make(
            title: "Installing \(emulator.displayName)…", detail: "Downloading \(emulator.displayName)…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            let tempDir = NSTemporaryDirectory() + "emulator_install_\(emulator.rawValue)"
            try? fm.removeItem(atPath: tempDir)
            try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
            let tempDirURL = URL(fileURLWithPath: tempDir)
            let archive = tempDirURL.appendingPathComponent(emulator.archiveType == .zip ? "emulator.zip" : "emulator.dmg")

            // Download (exit-code + ≥500 KB sanity check).
            guard TrustedDownloadInstaller.download(url, to: archive, minBytes: 500_000) else {
                print("[Installer] Download failed for \(emulator.displayName)")
                self.finishInstall(success: false, emulator: emulator, progressWindow: progressWindow, tempDir: tempDir, completion: completion)
                return
            }

            DispatchQueue.main.async { InstallProgressWindow.update(progressWindow, detail: "Installing \(emulator.displayName)…") }

            // Extract → a local .app copy.
            let foundApp: URL?
            switch emulator.archiveType {
            case .zip:
                let extractDir = tempDirURL.appendingPathComponent("extracted")
                try? fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
                foundApp = TrustedDownloadInstaller.unzip(archive, into: extractDir)
                    ? TrustedDownloadInstaller.findAppBundle(named: emulator.appBundleName, in: extractDir)
                    : nil
            case .dmg:
                foundApp = TrustedDownloadInstaller.withMountedDMG(archive) { mount -> URL? in
                    guard let app = TrustedDownloadInstaller.findAppBundle(named: emulator.appBundleName, in: mount) else { return nil }
                    let localCopy = tempDirURL.appendingPathComponent("\(emulator.appBundleName).app")
                    try? fm.removeItem(at: localCopy)
                    try? fm.copyItem(at: app, to: localCopy)
                    return localCopy
                } ?? nil
            }

            guard let appURL = foundApp else {
                print("[Installer] App bundle not found for \(emulator.displayName)")
                self.finishInstall(success: false, emulator: emulator, progressWindow: progressWindow, tempDir: tempDir, completion: completion)
                return
            }

            // Verify + install (quarantine preserved for verified apps; warn-but-allow otherwise).
            let result = TrustedDownloadInstaller.installVerifiedApp(
                bundleAt: appURL, to: URL(fileURLWithPath: emulator.appPath),
                confirmUnverified: { InstallProgressWindow.confirmUnverified(name: emulator.displayName) })
            switch result {
            case .installed:
                self.finishInstall(success: true, emulator: emulator, progressWindow: progressWindow, tempDir: tempDir, completion: completion)
            case .cancelled:
                try? fm.removeItem(atPath: tempDir)
                DispatchQueue.main.async { self.isInstalling = false; progressWindow.close(); completion(false) }
            case .failed:
                self.finishInstall(success: false, emulator: emulator, progressWindow: progressWindow, tempDir: tempDir, completion: completion)
            }
        }
    }

    // MARK: - Helpers

    private func finishInstall(success: Bool, emulator: EmulatorType, progressWindow: NSWindow, tempDir: String, completion: @escaping (Bool) -> Void) {
        try? FileManager.default.removeItem(atPath: tempDir)
        DispatchQueue.main.async { [weak self] in
            self?.isInstalling = false
            progressWindow.close()
            if !success {
                let alert = NSAlert()
                alert.messageText = "Installation Failed"
                alert.informativeText = "Could not install \(emulator.displayName). Please install manually."
                alert.addButton(withTitle: "Open Website")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    self?.openWebsite(emulator)
                }
            }
            completion(success)
        }
    }

    private func openWebsite(_ emulator: EmulatorType) {
        if let url = URL(string: emulator.websiteURL) {
            NSWorkspace.shared.open(url)
        }
    }
}
