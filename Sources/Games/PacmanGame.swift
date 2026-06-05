import AppKit

/// Launches the bundled BeOS Pac-Man demo (Resources/Games/Pacman.app), passing the active
/// RetroMac theme so the game can draw a matching window frame (BeOS Lasche for BeOS, plain
/// window otherwise).
enum PacmanGame {

    static var appURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Games/Pacman.app")
    }

    static var isAvailable: Bool {
        guard let url = appURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func launch() {
        guard let url = appURL, FileManager.default.fileExists(atPath: url.path) else { NSSound.beep(); return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.environment = RetroFrameTheme.gameEnv()
        NSWorkspace.shared.openApplication(at: url, configuration: cfg, completionHandler: nil)
    }
}
