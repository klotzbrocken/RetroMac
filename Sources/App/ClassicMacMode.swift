import AppKit

enum ClassicMacMode {
    private static let snapshotKey = "classicMacModeSnapshot"

    static func activate() {
        let settings = AppSettings.shared
        saveSnapshot(settings)

        settings.dockTheme = "Mac OS 9.2 Classic"
        settings.macos9UseDock = true   // Platinum dock (the merged former "Mac OS 9.2" theme)
        settings.hideSystemUI = true
        settings.vignetteIntensity = 0.4
        settings.scanlineOverlayName = "scanline-fine"
        settings.scanlineOverlayIntensity = 0.5
        settings.classicMacModeActive = true

        if !settings.dockEnabled {
            settings.dockEnabled = true
            DockController.shared.start()
        }

        if let delegate = AppDelegate.shared {
            delegate.applyPreset("mac-classic")
        }

        NSSound(named: "Tink")?.play()
        print("[ClassicMac] Activated")
    }

    static func deactivate() {
        let settings = AppSettings.shared
        settings.classicMacModeActive = false

        restoreSnapshot(settings)

        if let delegate = AppDelegate.shared {
            delegate.applyPreset(settings.defaultPreset)
        }

        print("[ClassicMac] Deactivated")
    }

    private static func saveSnapshot(_ settings: AppSettings) {
        let snapshot: [String: Any] = [
            "dockTheme": settings.dockTheme,
            "hideSystemUI": settings.hideSystemUI,
            "vignetteIntensity": settings.vignetteIntensity,
            "scanlineOverlayName": settings.scanlineOverlayName,
            "scanlineOverlayIntensity": settings.scanlineOverlayIntensity,
            "dockEnabled": settings.dockEnabled,
        ]
        UserDefaults.standard.set(snapshot, forKey: snapshotKey)
    }

    private static func restoreSnapshot(_ settings: AppSettings) {
        guard let snapshot = UserDefaults.standard.dictionary(forKey: snapshotKey) else { return }

        if let v = snapshot["dockTheme"] as? String { settings.dockTheme = v }
        if let v = snapshot["hideSystemUI"] as? Bool { settings.hideSystemUI = v }
        if let v = snapshot["vignetteIntensity"] as? Float { settings.vignetteIntensity = v }
        if let v = snapshot["scanlineOverlayName"] as? String { settings.scanlineOverlayName = v }
        if let v = snapshot["scanlineOverlayIntensity"] as? Float { settings.scanlineOverlayIntensity = v }

        let wasDockEnabled = snapshot["dockEnabled"] as? Bool ?? false
        if !wasDockEnabled && settings.dockEnabled {
            settings.dockEnabled = false
            DockController.shared.stop()
        }

        UserDefaults.standard.removeObject(forKey: snapshotKey)
    }
}
