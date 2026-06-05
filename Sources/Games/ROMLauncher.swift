import AppKit
import ScreenCaptureKit

/// Launches ROMs in their respective emulators and applies CRT shader overlays.
final class ROMLauncher {
    static let shared = ROMLauncher()

    private var pollTimer: Timer?
    private var emulatorWatchTimer: Timer?
    private var watchedBundleID: String?
    private var crtLiteOverlay: CRTLiteOverlay?

    private init() {}

    /// Launch a ROM in its emulator with shader overlay
    func launch(_ rom: ROMEntry) {
        let emulator = rom.system.emulator

        guard emulator.isInstalled else {
            // Auto-install if possible, then retry launch
            if emulator.canAutoInstall {
                autoInstallAndLaunch(emulator: emulator, rom: rom)
            } else {
                showEmulatorNotInstalled(emulator)
            }
            return
        }

        guard FileManager.default.fileExists(atPath: rom.path) else {
            showAlert(title: "ROM Not Found", message: "The ROM file could not be found at:\n\(rom.path)")
            return
        }

        // Mark as played
        ROMLibrary.shared.markPlayed(id: rom.id)

        // Configure ares settings (keyboard bindings, defocus) before launch
        if emulator == .ares {
            AresConfigurator.shared.configureIfNeeded()
        }

        // Launch emulator process (pass system for ares --system flag)
        launchEmulator(emulator: emulator, romPath: rom.path, system: rom.system) { [weak self] success in
            guard success else { return }

            print("[ROMLauncher] Launched \(rom.displayName) with \(emulator.displayName)")

            // Start shader overlay after emulator opens its window
            let presetID = rom.effectivePresetID
            let bundleID = emulator.bundleIdentifier
            DispatchQueue.main.async {
                if AppDelegate.isLitePreset(presetID) {
                    // Lite: transparent overlay, no screen recording needed
                    self?.startCRTLiteOverlay(bundleID: bundleID, presetName: presetID)
                } else {
                    // Full shader: captures emulator window via ScreenCaptureKit
                    self?.startShaderOverlay(bundleID: bundleID, presetID: presetID)
                }
            }
        }
    }

    // MARK: - Emulator Launch

    private func launchEmulator(emulator: EmulatorType, romPath: String, system: RetroSystem? = nil, completion: @escaping (Bool) -> Void) {
        let appURL = URL(fileURLWithPath: emulator.appPath)

        let config = NSWorkspace.OpenConfiguration()
        config.arguments = emulator.launchArguments(romPath: romPath, system: system)
        config.activates = true
        config.environment = RetroFrameTheme.gameEnv()   // theme hook (engines that support it use it)

        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, error in
            if let error = error {
                print("[ROMLauncher] Launch failed: \(error.localizedDescription)")
                completion(false)
            } else {
                print("[ROMLauncher] Emulator process started: \(app?.processIdentifier ?? -1)")
                completion(true)
            }
        }
    }

    // MARK: - Shader Overlay

    private func startShaderOverlay(bundleID: String, presetID: String) {
        // Poll for the emulator window to appear via ScreenCaptureKit, then attach overlay
        var attempts = 0
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            attempts += 1

            if attempts > 20 { // 10 second timeout
                timer.invalidate()
                self?.pollTimer = nil
                print("[ROMLauncher] Timeout waiting for emulator window")
                return
            }

            // Find emulator window via ScreenCaptureKit
            Task {
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                    let emulatorWindow = content.windows.first { window in
                        window.owningApplication?.bundleIdentifier == bundleID &&
                        window.frame.width > 100 && window.frame.height > 100
                    }

                    guard let scWindow = emulatorWindow else { return }

                    // Found the emulator window — start overlay
                    await MainActor.run {
                        timer.invalidate()
                        self?.pollTimer = nil

                        let appName = scWindow.owningApplication?.applicationName ?? bundleID
                        print("[ROMLauncher] Found \(appName) window (attempt \(attempts)) — starting shader: \(presetID)")

                        guard let appDel = NSApp.delegate as? AppDelegate else { return }

                        // Save current overlay state and start game overlay
                        appDel.saveOverlayState()
                        if appDel.isActive {
                            appDel.disableAll()
                        }

                        // Small delay for the game content to render
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            appDel.startWindowOverlay(window: scWindow, presetID: presetID)

                            // Re-activate the emulator so it keeps keyboard focus
                            // (the overlay window should not steal focus, but ensure it)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                                apps.first?.activate()
                            }

                            // Watch for emulator close to restore previous overlay state
                            self?.watchEmulatorWindow(bundleID: bundleID)
                        }
                    }
                } catch {
                    print("[ROMLauncher] Window query failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - CRT Lite Overlay

    private func startCRTLiteOverlay(bundleID: String, presetName: String = "crt-lite") {
        // Wait briefly for the emulator window to appear
        var attempts = 0
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            attempts += 1
            if attempts > 20 {
                timer.invalidate()
                self?.pollTimer = nil
                print("[ROMLauncher] Timeout waiting for emulator window (CRT Lite)")
                return
            }

            // Check if app window exists via CGWindowList (no screen recording needed)
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            guard let pid = apps.first?.processIdentifier else { return }

            guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }

            let hasWindow = windowList.contains { info in
                guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                      ownerPID == pid,
                      let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                      let w = bounds["Width"], let h = bounds["Height"] else { return false }
                return w > 100 && h > 100
            }

            guard hasWindow else { return }

            timer.invalidate()
            self?.pollTimer = nil

            print("[ROMLauncher] Found emulator window — starting CRT Lite overlay")

            // Save and disable current overlay
            if let appDel = NSApp.delegate as? AppDelegate {
                appDel.saveOverlayState()
                if appDel.isActive {
                    appDel.disableAll()
                }
            }

            let overlay = CRTLiteOverlay()
            overlay.startForApp(bundleID: bundleID, preset: presetName)
            self?.crtLiteOverlay = overlay

            // Re-activate emulator for keyboard focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                apps.first?.activate()
            }
        }
    }

    // MARK: - Emulator Window Watch

    /// Monitor the emulator process — when it quits or its window closes, restore the previous overlay state.
    private func watchEmulatorWindow(bundleID: String) {
        stopWatching()
        watchedBundleID = bundleID

        emulatorWatchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }

            // Check if the emulator process is still running
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if running.isEmpty {
                print("[ROMLauncher] Emulator quit — restoring overlay state")
                timer.invalidate()
                self.emulatorWatchTimer = nil
                self.watchedBundleID = nil
                self.restoreOverlay()
                return
            }

            // Also check via ScreenCaptureKit if the emulator window is still visible
            Task {
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                    let hasWindow = content.windows.contains { window in
                        window.owningApplication?.bundleIdentifier == bundleID &&
                        window.frame.width > 100 && window.frame.height > 100
                    }

                    if !hasWindow {
                        await MainActor.run {
                            print("[ROMLauncher] Emulator window closed — restoring overlay state")
                            timer.invalidate()
                            self.emulatorWatchTimer = nil
                            self.watchedBundleID = nil
                            self.restoreOverlay()
                        }
                    }
                } catch {
                    // Ignore transient errors
                }
            }
        }
    }

    private func stopWatching() {
        emulatorWatchTimer?.invalidate()
        emulatorWatchTimer = nil
        watchedBundleID = nil
    }

    private func restoreOverlay() {
        // Stop CRT Lite overlay if active
        crtLiteOverlay?.stop()
        crtLiteOverlay = nil

        guard let appDel = NSApp.delegate as? AppDelegate else { return }
        appDel.restorePreviousOverlay()
        print("[ROMLauncher] Previous overlay state restored")
    }

    // MARK: - Auto-Install

    private func autoInstallAndLaunch(emulator: EmulatorType, rom: ROMEntry) {
        let systems = emulator.supportedSystems.map(\.shortName).joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = "Install \(emulator.displayName)?"
        alert.informativeText = "\(emulator.displayName) is required to play \(systems) games.\n\nIt will be downloaded and installed automatically.\n\nmacOS will verify this app on first launch."
        alert.addButton(withTitle: "Install \(emulator.displayName)")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        EmulatorInstaller.shared.install(emulator) { [weak self] success in
            if success {
                // Retry launch now that the emulator is installed
                self?.launch(rom)
            }
        }
    }

    // MARK: - Alerts

    private func showEmulatorNotInstalled(_ emulator: EmulatorType) {
        let alert = NSAlert()
        alert.messageText = "\(emulator.displayName) Not Installed"
        alert.informativeText = "Install \(emulator.displayName) to play \(emulator.supportedSystems.map(\.shortName).joined(separator: ", ")) games.\n\nDownload: \(emulator.websiteURL)"
        alert.addButton(withTitle: "Open Website")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: emulator.websiteURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
