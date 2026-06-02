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
        let progressWindow = createProgressWindow(
            title: "Installing \(emulator.displayName)…",
            detail: "Downloading \(emulator.displayName)…"
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            let tempDir = NSTemporaryDirectory() + "emulator_install_\(emulator.rawValue)"
            try? fm.removeItem(atPath: tempDir)
            try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

            let archivePath: String
            switch emulator.archiveType {
            case .zip: archivePath = tempDir + "/emulator.zip"
            case .dmg: archivePath = tempDir + "/emulator.dmg"
            }

            // Download
            let download = Process()
            download.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            download.arguments = ["-L", "-s", "-o", archivePath,
                                  "-H", "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
                                  url.absoluteString]
            try? download.run()
            download.waitUntilExit()

            guard download.terminationStatus == 0,
                  fm.fileExists(atPath: archivePath),
                  (try? fm.attributesOfItem(atPath: archivePath)[.size] as? Int) ?? 0 > 500_000 else {
                print("[Installer] Download failed for \(emulator.displayName)")
                self?.finishInstall(success: false, emulator: emulator, progressWindow: progressWindow, tempDir: tempDir, completion: completion)
                return
            }

            DispatchQueue.main.async {
                self?.updateProgressWindow(progressWindow, detail: "Installing \(emulator.displayName)…")
            }

            // Extract
            var appBundlePath: String?

            switch emulator.archiveType {
            case .zip:
                let extractDir = tempDir + "/extracted"
                try? fm.createDirectory(atPath: extractDir, withIntermediateDirectories: true)
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzip.arguments = ["-o", archivePath, "-d", extractDir]
                unzip.standardOutput = FileHandle.nullDevice
                unzip.standardError = FileHandle.nullDevice
                try? unzip.run()
                unzip.waitUntilExit()
                appBundlePath = self?.findAppBundle(named: emulator.appBundleName, in: extractDir)

            case .dmg:
                let mountPoint = tempDir + "/mount"
                try? fm.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)
                let mount = Process()
                mount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                mount.arguments = ["attach", archivePath, "-mountpoint", mountPoint, "-nobrowse", "-quiet"]
                try? mount.run()
                mount.waitUntilExit()
                appBundlePath = self?.findAppBundle(named: emulator.appBundleName, in: mountPoint)

                // Copy first, then detach
                if let path = appBundlePath {
                    let localCopy = tempDir + "/\(emulator.appBundleName).app"
                    try? fm.copyItem(atPath: path, toPath: localCopy)
                    appBundlePath = localCopy
                }

                let detach = Process()
                detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                detach.arguments = ["detach", mountPoint, "-quiet"]
                try? detach.run()
                detach.waitUntilExit()
            }

            guard let foundPath = appBundlePath else {
                print("[Installer] App bundle not found for \(emulator.displayName)")
                self?.finishInstall(success: false, emulator: emulator, progressWindow: progressWindow, tempDir: tempDir, completion: completion)
                return
            }

            // SECURITY: verify the downloaded bundle before trusting it. The download
            // is over the network (curl) — a MITM/CDN/DNS compromise could serve a
            // malicious binary. Require an intact code signature AND Gatekeeper approval
            // (Developer ID + notarized). Reject otherwise instead of copying to /Applications.
            guard self?.verifyAppSignature(at: foundPath) == true else {
                print("[Installer] SECURITY: signature/notarization check FAILED for \(emulator.displayName) — aborting")
                self?.finishInstall(success: false, emulator: emulator, progressWindow: progressWindow, tempDir: tempDir, completion: completion)
                return
            }

            // Copy to /Applications
            let targetPath = emulator.appPath
            do {
                if fm.fileExists(atPath: targetPath) {
                    try fm.removeItem(atPath: targetPath)
                }
                try fm.copyItem(atPath: foundPath, toPath: targetPath)

                // Quarantine attribute is intentionally preserved so macOS
                // Gatekeeper can verify the app on first launch.
                print("[Installer] Installed \(emulator.displayName) to \(targetPath)")
                self?.finishInstall(success: true, emulator: emulator, progressWindow: progressWindow, tempDir: tempDir, completion: completion)
            } catch {
                print("[Installer] Copy failed: \(error.localizedDescription)")
                self?.finishInstall(success: false, emulator: emulator, progressWindow: progressWindow, tempDir: tempDir, completion: completion)
            }
        }
    }

    // MARK: - Security

    /// Verify a downloaded .app before installing: (1) intact, unmodified code signature
    /// (`codesign --verify --deep --strict`), and (2) Gatekeeper acceptance
    /// (`spctl --assess --type execute` → Developer ID + notarized). Both must pass.
    /// Runs on the install background queue (no main-thread blocking).
    private func verifyAppSignature(at path: String) -> Bool {
        func run(_ tool: String, _ args: [String]) -> Bool {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return false }
            p.waitUntilExit()
            return p.terminationStatus == 0
        }
        let codesignOK = run("/usr/bin/codesign", ["--verify", "--deep", "--strict", path])
        guard codesignOK else { return false }
        let gatekeeperOK = run("/usr/sbin/spctl", ["--assess", "--type", "execute", path])
        return gatekeeperOK
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

    private func findAppBundle(named name: String, in directory: String) -> String? {
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(atPath: directory) {
            if let app = contents.first(where: { $0.lowercased().contains(name.lowercased()) && $0.hasSuffix(".app") }) {
                return directory + "/" + app
            }
        }
        if let enumerator = fm.enumerator(atPath: directory) {
            while let file = enumerator.nextObject() as? String {
                if file.hasSuffix(".app") && file.lowercased().contains(name.lowercased()) {
                    return directory + "/" + file
                }
            }
        }
        return nil
    }

    private func createProgressWindow(title: String, detail: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 120))

        let spinner = NSProgressIndicator(frame: NSRect(x: 170, y: 75, width: 40, height: 40))
        spinner.style = .spinning
        spinner.startAnimation(nil)
        container.addSubview(spinner)

        let label = NSTextField(labelWithString: detail)
        label.frame = NSRect(x: 20, y: 30, width: 340, height: 36)
        label.alignment = .center
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.tag = 100
        container.addSubview(label)

        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }

    private func updateProgressWindow(_ window: NSWindow, detail: String) {
        if let label = window.contentView?.viewWithTag(100) as? NSTextField {
            label.stringValue = detail
        }
    }
}
