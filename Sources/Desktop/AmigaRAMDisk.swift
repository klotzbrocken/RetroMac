import Foundation

/// AmigaOS's RAM Disk: a private place for this session's scraps. Here it is a folder in the
/// user's own temporary directory (not the shared /tmp), made when first opened. It outlives a
/// theme switch and a RetroMac restart; macOS clears it when the Mac restarts, as RAM: was
/// gone after a reboot. RetroMac never empties it itself: that would lose someone's file.
enum AmigaRAMDisk {
    static let token = "RAM:"
    static var url: URL { FileManager.default.temporaryDirectory.appendingPathComponent("RetroMac RAM Disk", isDirectory: true) }

    /// A desktop entry's path as a real one: "RAM:" is the RAM Disk, "~" the home folder.
    static func resolve(_ path: String) -> String {
        guard path == token else { return NSString(string: path).expandingTildeInPath }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }
}
