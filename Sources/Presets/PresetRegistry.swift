import Foundation
import Metal

struct PresetInfo {
    let id: String
    let displayName: String
    let description: String
    let isCustom: Bool

    init(id: String, displayName: String, description: String, isCustom: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.isCustom = isCustom
    }
}

enum PresetRegistry {
    enum PresetCategory: String, CaseIterable {
        case crt = "CRT / Monitor"
        case proMonitor = "Pro Monitors"
        case video = "Video Signals"
        case retro = "Retro Devices"
        case apple = "Apple"
        case film = "Film / Photo"
        case webcam = "Webcam Looks"
    }

    static let categorizedPresets: [(PresetCategory, [PresetInfo])] = [
        (.crt, [
            PresetInfo(id: "zfast-crt", displayName: "zfast CRT", description: "Scanlines + chromatic aberration"),
            PresetInfo(id: "crt-lottes", displayName: "CRT Lottes", description: "Shadow mask + scanlines"),
            PresetInfo(id: "crt-geom", displayName: "CRT Geom", description: "Phosphor mask + scanlines"),
            PresetInfo(id: "crt-aperture", displayName: "CRT Aperture", description: "Aperture grille + bloom"),
            PresetInfo(id: "crt-hyllian-glow", displayName: "CRT Hyllian Glow", description: "Phosphor glow + scanlines"),
            PresetInfo(id: "crt-gdv-mini-ultra", displayName: "CRT GDV Mini Ultra", description: "GDV curvature + mask + glow"),
            PresetInfo(id: "crt-royale-lite", displayName: "CRT Royale Lite", description: "Phosphor triad + halation bloom"),
            PresetInfo(id: "trinitron-tv", displayName: "Trinitron TV", description: "Consumer Trinitron, warm vivid"),
            PresetInfo(id: "newpixie-crt", displayName: "NewPixie CRT", description: "Soft warm CRT + curvature"),
            PresetInfo(id: "newpixie", displayName: "NewPixie", description: "Soft pixelation + warm color"),
            PresetInfo(id: "curvature-x", displayName: "CurvatureX 0.01", description: "Very subtle barrel distortion"),
        ]),
        (.proMonitor, [
            PresetInfo(id: "pvm-2730qm", displayName: "Sony PVM 2730QM", description: "Pro monitor, sharp aperture grille"),
            PresetInfo(id: "pvm-20l4", displayName: "Sony PVM 20L4", description: "Pro monitor, fine slot mask"),
            PresetInfo(id: "mini-ultra-trinitron", displayName: "Mini Ultra Trinitron", description: "Ultra-fine Trinitron stripes"),
            PresetInfo(id: "bo-mx8000", displayName: "B&O MX8000", description: "Hi-end consumer, warm European"),
        ]),
        (.video, [
            PresetInfo(id: "ntsc", displayName: "NTSC", description: "Composite video artifacts"),
            PresetInfo(id: "ntsc-320px", displayName: "NTSC 320px Composite", description: "Low-res NTSC composite"),
            PresetInfo(id: "pal", displayName: "PAL", description: "Cross-color + Hanover bars"),
            PresetInfo(id: "vhs", displayName: "VHS", description: "VHS tape distortion + noise"),
            PresetInfo(id: "s-vhs", displayName: "S-VHS", description: "Degraded tape + dropouts"),
            PresetInfo(id: "vcr-tracking", displayName: "VCR Tracking", description: "Jitter + tracking lines + head noise"),
        ]),
        (.retro, [
            PresetInfo(id: "lcd-grid", displayName: "LCD Grid", description: "RGB subpixel grid"),
            PresetInfo(id: "lcd3x", displayName: "LCD 3x", description: "Sine-based subpixel columns, early TFT look"),
            PresetInfo(id: "zfast-lcd", displayName: "zfast LCD", description: "Pixel grid + border darkening, 2000s LCD"),
            PresetInfo(id: "gameboy", displayName: "Game Boy", description: "DMG LCD palette + pixel grid"),
            PresetInfo(id: "amber-monitor", displayName: "Amber Monitor", description: "Amber phosphor terminal"),
            PresetInfo(id: "green-phosphor", displayName: "Green Phosphor", description: "P1 green terminal"),
        ]),
        (.apple, [
            PresetInfo(id: "mac-classic", displayName: "Macintosh Classic", description: "Warm white phosphor, subtle scanlines"),
            PresetInfo(id: "apple-ii", displayName: "Apple II", description: "Green phosphor, NTSC color bleed"),
            PresetInfo(id: "aqua", displayName: "Mac OS X Aqua", description: "Glossy bloom, Cinema Display"),
        ]),
        (.film, [
            PresetInfo(id: "cinema-film", displayName: "Cinema Film", description: "Cinematic grading + grain + halation"),
            PresetInfo(id: "sepia", displayName: "Sepia", description: "Warm vintage photograph"),
            PresetInfo(id: "bw-film", displayName: "B&W Film", description: "Classic film grain"),
            PresetInfo(id: "bw-noir", displayName: "B&W Noir", description: "High contrast noir"),
        ]),
        (.webcam, [
            PresetInfo(id: "late-night-crt", displayName: "Late Night CRT", description: "Warm 90s late-night TV studio"),
            PresetInfo(id: "newsroom-1987", displayName: "Newsroom 1987", description: "1987 broadcast newsroom look"),
            PresetInfo(id: "vhs-tape", displayName: "VHS Tape", description: "Well-worn rental VHS tape"),
            PresetInfo(id: "terminal-green", displayName: "Terminal Green", description: "Green phosphor terminal"),
        ]),
    ]

    static let builtinPresets: [PresetInfo] = categorizedPresets.flatMap { $0.1 }

    static var availablePresets: [PresetInfo] {
        builtinPresets + customPresets()
    }

    static func customPresets() -> [PresetInfo] {
        let dir = AppSettings.shared.customPresetsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "metal" }
            .map { url in
                let name = url.deletingPathExtension().lastPathComponent
                return PresetInfo(id: "custom:\(name)", displayName: name, description: "Custom shader", isCustom: true)
            }
            .sorted { $0.displayName < $1.displayName }
    }

    static func loadShader(named name: String, device: MTLDevice) throws -> MTLLibrary {
        if name.hasPrefix("custom:") {
            let fileName = String(name.dropFirst("custom:".count))
            let url = AppSettings.shared.customPresetsDirectory.appendingPathComponent("\(fileName).metal")
            let source = try String(contentsOf: url, encoding: .utf8)
            return try device.makeLibrary(source: source, options: nil)
        } else {
            let source = try BuiltinShaders.source(for: name)
            return try device.makeLibrary(source: source, options: nil)
        }
    }
}
