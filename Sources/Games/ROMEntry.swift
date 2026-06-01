import Foundation

/// A single ROM in the user's library
struct ROMEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var filename: String
    var path: String
    var system: RetroSystem
    var displayName: String
    var presetID: String?       // nil = use system default
    var dateAdded: Date
    var lastPlayed: Date?

    /// The effective CRT shader preset (per-game override or system default)
    var effectivePresetID: String {
        presetID ?? system.defaultPresetID
    }

    /// Create a new ROM entry from a file URL, auto-detecting the system
    init?(url: URL, system: RetroSystem? = nil) {
        guard let detectedSystem = system ?? RetroSystem.detect(from: url) else {
            return nil
        }

        self.id = UUID()
        self.filename = url.lastPathComponent
        self.path = url.path
        self.system = detectedSystem
        self.displayName = Self.cleanDisplayName(from: url.deletingPathExtension().lastPathComponent)
        self.presetID = nil
        self.dateAdded = Date()
        self.lastPlayed = nil
    }

    /// Clean up a ROM filename into a display name
    /// "Super_Mario_Bros_(U) [!]" → "Super Mario Bros"
    private static func cleanDisplayName(from filename: String) -> String {
        var name = filename

        // Remove common ROM tags in brackets/parens
        let tagPatterns = [
            "\\s*\\([^)]*\\)",      // (U), (USA), (Europe), etc.
            "\\s*\\[[^\\]]*\\]",    // [!], [b1], [T+Eng], etc.
        ]
        for pattern in tagPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                name = regex.stringByReplacingMatches(
                    in: name, range: NSRange(name.startIndex..., in: name), withTemplate: ""
                )
            }
        }

        // Replace underscores and dots with spaces
        name = name.replacingOccurrences(of: "_", with: " ")
        name = name.replacingOccurrences(of: ".", with: " ")

        // Trim whitespace
        name = name.trimmingCharacters(in: .whitespaces)

        return name.isEmpty ? filename : name
    }
}
