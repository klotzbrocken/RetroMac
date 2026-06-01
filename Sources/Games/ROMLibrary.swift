import Foundation
import Combine

/// Manages the user's ROM library with JSON persistence.
final class ROMLibrary: ObservableObject {
    static let shared = ROMLibrary()

    @Published var entries: [ROMEntry] = []

    private let fileManager = FileManager.default
    private let libraryURL: URL
    private let romsDirectoryURL: URL

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let retroMacDir = appSupport.appendingPathComponent("RetroMac")
        libraryURL = retroMacDir.appendingPathComponent("rom_library.json")
        romsDirectoryURL = retroMacDir.appendingPathComponent("ROMs")

        // Ensure directories exist
        try? fileManager.createDirectory(at: retroMacDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: romsDirectoryURL, withIntermediateDirectories: true)

        load()
        print("[ROMLibrary] Loaded \(entries.count) entries from \(libraryURL.path)")
    }

    // MARK: - CRUD

    /// Add a ROM from a file URL. Copies the file to the ROMs directory.
    /// Returns the created entry, or nil if the system couldn't be detected.
    @discardableResult
    func addROM(from sourceURL: URL, system: RetroSystem? = nil) -> ROMEntry? {
        let detectedSystem = system ?? RetroSystem.detect(from: sourceURL)
        guard let sys = detectedSystem else {
            print("[ROMLibrary] Unknown ROM type: \(sourceURL.pathExtension)")
            return nil
        }

        // Check for duplicate (same filename + system)
        let filename = sourceURL.lastPathComponent
        if entries.contains(where: { $0.filename == filename && $0.system == sys }) {
            print("[ROMLibrary] Duplicate ROM: \(filename)")
            return nil
        }

        // Copy ROM to managed directory
        let systemDir = romsDirectoryURL.appendingPathComponent(sys.rawValue)
        try? fileManager.createDirectory(at: systemDir, withIntermediateDirectories: true)
        let destURL = systemDir.appendingPathComponent(filename)

        do {
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destURL)
        } catch {
            print("[ROMLibrary] Copy failed: \(error.localizedDescription)")
            return nil
        }

        guard var entry = ROMEntry(url: destURL, system: sys) else { return nil }
        entry = ROMEntry(url: destURL, system: sys)!

        entries.append(entry)
        save()
        print("[ROMLibrary] Added: \(entry.displayName) (\(sys.shortName))")
        return entry
    }

    /// Remove a ROM entry and optionally delete the file
    func removeROM(id: UUID, deleteFile: Bool = false) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[index]

        if deleteFile {
            try? fileManager.removeItem(atPath: entry.path)
        }

        entries.remove(at: index)
        save()
        print("[ROMLibrary] Removed: \(entry.displayName)")
    }

    /// Update an existing entry (e.g. rename, change preset)
    func updateROM(_ entry: ROMEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        save()
    }

    /// Mark a ROM as played (updates lastPlayed timestamp)
    func markPlayed(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].lastPlayed = Date()
        save()
    }

    /// All entries grouped by system
    var entriesBySystem: [(system: RetroSystem, roms: [ROMEntry])] {
        let grouped = Dictionary(grouping: entries, by: \.system)
        return RetroSystem.allCases
            .compactMap { system in
                guard let roms = grouped[system], !roms.isEmpty else { return nil }
                return (system: system, roms: roms.sorted { $0.displayName < $1.displayName })
            }
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: libraryURL, options: .atomic)
        } catch {
            print("[ROMLibrary] Save failed: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard fileManager.fileExists(atPath: libraryURL.path) else { return }
        do {
            let data = try Data(contentsOf: libraryURL)
            entries = try JSONDecoder().decode([ROMEntry].self, from: data)
            // Prune entries whose ROM files no longer exist
            let before = entries.count
            entries.removeAll { !fileManager.fileExists(atPath: $0.path) }
            if entries.count < before {
                print("[ROMLibrary] Pruned \(before - entries.count) missing ROMs")
                save()
            }
        } catch {
            print("[ROMLibrary] Load failed: \(error.localizedDescription)")
        }
    }
}
