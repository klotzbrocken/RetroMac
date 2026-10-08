import AppKit

/// Launches the bundled BeOS Pac-Man demo (Resources/Games/Pacman.app), passing the active
/// RetroMac theme so the game can draw a matching window frame (BeOS Lasche for BeOS, plain
/// window otherwise).
enum PacmanGame {

    static var appURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Games/Pacman.app")
    }

    /// The game itself, not just its folder: a build without SDL2_ttf/SDL2_mixer left an empty
    /// Pacman.app behind, and the click on Pac-Man then did nothing at all.
    static var isAvailable: Bool {
        guard let url = appURL else { return false }
        return FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/pacman").path)
    }

    static func launch() {
        guard isAvailable, let url = appURL else { NSSound.beep(); return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.environment = RetroFrameTheme.gameEnv()
        NSWorkspace.shared.openApplication(at: url, configuration: cfg, completionHandler: nil)
    }
}
