import Foundation

/// All supported retro console systems with their ROM extensions, default shader presets, and emulator mapping.
enum RetroSystem: String, Codable, CaseIterable, Identifiable {
    case nes = "nes"
    case snes = "snes"
    case n64 = "n64"
    case gameBoy = "gb"
    case gameBoyColor = "gbc"
    case gameBoyAdvance = "gba"
    case familyComputerDisk = "fds"
    case colecoVision = "coleco"
    case gameCube = "gcn"
    case wii = "wii"
    case playStation = "ps1"
    case playStation2 = "ps2"
    case atari2600 = "atari2600"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nes: return "Nintendo Entertainment System"
        case .snes: return "Super Nintendo"
        case .n64: return "Nintendo 64"
        case .gameBoy: return "Game Boy"
        case .gameBoyColor: return "Game Boy Color"
        case .gameBoyAdvance: return "Game Boy Advance"
        case .familyComputerDisk: return "Famicom Disk System"
        case .colecoVision: return "ColecoVision"
        case .gameCube: return "GameCube"
        case .wii: return "Wii"
        case .playStation: return "PlayStation"
        case .playStation2: return "PlayStation 2"
        case .atari2600: return "Atari 2600"
        }
    }

    var shortName: String {
        switch self {
        case .nes: return "NES"
        case .snes: return "SNES"
        case .n64: return "N64"
        case .gameBoy: return "GB"
        case .gameBoyColor: return "GBC"
        case .gameBoyAdvance: return "GBA"
        case .familyComputerDisk: return "FDS"
        case .colecoVision: return "CV"
        case .gameCube: return "GCN"
        case .wii: return "Wii"
        case .playStation: return "PS1"
        case .playStation2: return "PS2"
        case .atari2600: return "2600"
        }
    }

    var sfSymbol: String {
        switch self {
        case .gameBoy, .gameBoyColor, .gameBoyAdvance:
            return "gamecontroller.fill"
        case .nes, .snes, .familyComputerDisk:
            return "tv.fill"
        case .n64, .gameCube, .wii:
            return "gamecontroller"
        case .playStation, .playStation2:
            return "logo.playstation"
        case .atari2600:
            return "arcade.stick"
        case .colecoVision:
            return "tv.fill"
        }
    }

    /// Default CRT shader preset for this system
    var defaultPresetID: String {
        switch self {
        case .nes, .familyComputerDisk: return "ntsc"
        case .snes: return "crt-royale-lite"
        case .gameBoy, .gameBoyColor: return "gameboy"
        case .gameBoyAdvance: return "lcd-grid"
        case .n64: return "trinitron-tv"
        case .atari2600, .colecoVision: return "ntsc"
        case .playStation, .playStation2: return "trinitron-tv"
        case .gameCube, .wii: return "trinitron-tv"
        }
    }

    /// The canonical system name used by the ares emulator's --system flag.
    /// ares uses Japanese/original names (e.g. "Famicom" not "NES").
    var aresSystemName: String? {
        switch self {
        case .nes: return "Famicom"
        case .snes: return "Super Famicom"
        case .n64: return "Nintendo 64"
        case .gameBoy: return "Game Boy"
        case .gameBoyColor: return "Game Boy Color"
        case .gameBoyAdvance: return "Game Boy Advance"
        case .familyComputerDisk: return "Famicom Disk System"
        case .colecoVision: return "ColecoVision"
        default: return nil  // Non-ares systems
        }
    }

    /// Which emulator runs this system
    var emulator: EmulatorType {
        switch self {
        case .nes, .snes, .n64, .gameBoy, .gameBoyColor, .gameBoyAdvance,
             .familyComputerDisk, .colecoVision:
            return .ares
        case .gameCube, .wii:
            return .dolphin
        case .playStation:
            return .duckStation
        case .playStation2:
            return .pcsx2
        case .atari2600:
            return .stella
        }
    }

    /// ROM file extensions for this system (lowercase, without dot)
    var romExtensions: Set<String> {
        switch self {
        case .nes: return ["nes"]
        case .snes: return ["sfc", "smc"]
        case .n64: return ["z64", "n64", "v64", "ndd"]
        case .gameBoy: return ["gb"]
        case .gameBoyColor: return ["gbc"]
        case .gameBoyAdvance: return ["gba"]
        case .familyComputerDisk: return ["fds"]
        case .colecoVision: return ["col"]
        case .gameCube: return ["gcm", "gcz", "rvz", "dol", "elf"]
        case .wii: return ["wbfs", "wad"]
        case .playStation: return ["cue", "pbp", "ecm", "mds", "chd"]
        case .playStation2: return ["cso"]
        case .atari2600: return ["a26"]
        }
    }

    // MARK: - Detection

    /// Shared extensions that appear on multiple systems — resolved by priority
    private static let ambiguousExtensions: [String: [RetroSystem]] = [
        "iso": [.gameCube, .playStation, .playStation2],
        "bin": [.atari2600, .playStation, .playStation2],
        "rom": [.atari2600],
        "img": [.playStation],
        "gz": [.playStation2],
    ]

    /// Detect system from ROM file extension. Returns nil for unknown extensions.
    /// For ambiguous extensions (e.g. .iso, .bin), returns the first match by priority.
    static func detect(from url: URL) -> RetroSystem? {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }

        // First: check unambiguous extensions
        for system in Self.allCases {
            if system.romExtensions.contains(ext) {
                return system
            }
        }

        // Second: check ambiguous extensions (return first match — user can correct)
        if let candidates = ambiguousExtensions[ext], let first = candidates.first {
            return first
        }

        return nil
    }

    /// Detect all candidate systems for a ROM file extension.
    /// Returns multiple candidates for ambiguous extensions (.iso, .bin, etc.)
    /// so the UI can show a picker dialog. Returns a single-element array for
    /// unambiguous extensions, or empty array for unknown extensions.
    static func detectAll(from url: URL) -> [RetroSystem] {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return [] }

        // Check ambiguous extensions first — these have multiple candidates
        if let candidates = ambiguousExtensions[ext] {
            return candidates
        }

        // Check unambiguous extensions
        for system in Self.allCases {
            if system.romExtensions.contains(ext) {
                return [system]
            }
        }

        return []
    }

    /// All supported ROM extensions across all systems
    static var allSupportedExtensions: Set<String> {
        var result = Set<String>()
        for system in Self.allCases {
            result.formUnion(system.romExtensions)
        }
        for ext in ambiguousExtensions.keys {
            result.insert(ext)
        }
        return result
    }
}
