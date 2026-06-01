import Foundation

/// Supported emulator applications
enum EmulatorType: String, Codable, CaseIterable, Identifiable {
    case ares
    case dolphin
    case duckStation
    case pcsx2
    case stella

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ares: return "ares"
        case .dolphin: return "Dolphin"
        case .duckStation: return "DuckStation"
        case .pcsx2: return "PCSX2"
        case .stella: return "Stella"
        }
    }

    var appPath: String {
        switch self {
        case .ares: return "/Applications/ares.app"
        case .dolphin: return "/Applications/Dolphin.app"
        case .duckStation: return "/Applications/DuckStation.app"
        case .pcsx2: return "/Applications/PCSX2.app"
        case .stella: return "/Applications/Stella.app"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .ares: return "dev.ares.ares"
        case .dolphin: return "org.dolphin-emu.dolphin"
        case .duckStation: return "com.github.stenzek.duckstation"
        case .pcsx2: return "net.pcsx2.PCSX2"
        case .stella: return "net.sourceforge.Stella"
        }
    }

    var websiteURL: String {
        switch self {
        case .ares: return "https://ares-emu.net"
        case .dolphin: return "https://dolphin-emu.org"
        case .duckStation: return "https://www.duckstation.org"
        case .pcsx2: return "https://pcsx2.net"
        case .stella: return "https://stella-emu.github.io"
        }
    }

    /// Systems this emulator supports
    var supportedSystems: [RetroSystem] {
        switch self {
        case .ares: return [.nes, .snes, .n64, .gameBoy, .gameBoyColor, .gameBoyAdvance, .familyComputerDisk, .colecoVision]
        case .dolphin: return [.gameCube, .wii]
        case .duckStation: return [.playStation]
        case .pcsx2: return [.playStation2]
        case .stella: return [.atari2600]
        }
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: appPath)
    }

    /// Build CLI arguments to launch a ROM with this emulator.
    /// For ares, requires the system name via --system flag for correct input mapping.
    func launchArguments(romPath: String, system: RetroSystem? = nil) -> [String] {
        switch self {
        case .ares:
            // ares needs --system to correctly identify the console and map inputs.
            // Without it, keyboard input may not work (wrong system = wrong input mapping).
            if let systemName = system?.aresSystemName {
                return ["--system", systemName, romPath]
            }
            return [romPath]
        case .dolphin:
            // Dolphin uses -e flag for "execute"
            return ["-e", romPath]
        case .duckStation:
            return [romPath]
        case .pcsx2:
            return [romPath]
        case .stella:
            return [romPath]
        }
    }

    /// Path to the executable inside the .app bundle
    var executablePath: String {
        let appName: String
        switch self {
        case .ares: appName = "ares"
        case .dolphin: appName = "Dolphin"
        case .duckStation: appName = "DuckStation"
        case .pcsx2: appName = "PCSX2"
        case .stella: appName = "Stella"
        }
        return "\(appPath)/Contents/MacOS/\(appName)"
    }

    /// Direct download URL for auto-installation (nil = manual only)
    var downloadURL: String? {
        switch self {
        case .ares:
            return "https://github.com/ares-emulator/ares/releases/latest/download/ares-macos-universal.zip"
        case .dolphin:
            return "https://dl.dolphin-emu.org/releases/2503/dolphin-2503-universal.dmg"
        case .duckStation:
            return nil // Distribution changed, manual install recommended
        case .pcsx2:
            return nil // Manual install recommended
        case .stella:
            return "https://github.com/stella-emu/stella/releases/latest/download/Stella-7.0-macos-arm64-x86_64.dmg"
        }
    }

    /// Whether auto-install is available
    var canAutoInstall: Bool { downloadURL != nil }

    /// App name to search for inside the archive after extraction
    var appBundleName: String {
        switch self {
        case .ares: return "ares"
        case .dolphin: return "Dolphin"
        case .duckStation: return "DuckStation"
        case .pcsx2: return "PCSX2"
        case .stella: return "Stella"
        }
    }

    /// Archive type (zip or dmg)
    var archiveType: EmulatorArchiveType {
        guard let url = downloadURL else { return .zip }
        return url.hasSuffix(".dmg") ? .dmg : .zip
    }
}

enum EmulatorArchiveType {
    case zip
    case dmg
}
