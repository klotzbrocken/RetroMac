// Notepad's text files. Adapted from retro98's TextFile (matheushchaves, MIT License,
// github.com/matheushchaves/retro98); RetroMac adds Windows-1252 for old files that are not UTF-8.
import Foundation

enum LineEnding: String, Equatable { case lf = "\n", crlf = "\r\n", cr = "\r" }

enum TextFileError: Error, Equatable {
    case notText, tooLarge, unreadable

    var message: String {
        switch self {
        case .notText: "This file is not a text document; Notepad would show only garbage."
        case .tooLarge: "This file is too large for Notepad."
        case .unreadable: "The file could not be read."
        }
    }
}

/// A plain-text file as the Notepad keeps it: the text with "\n" line breaks, plus what the file
/// on disk used (its line ending, a byte-order mark, its encoding), so saving gives the same kind
/// of file back.
struct TextFile: Equatable {
    static let maximumSize = 10_485_760
    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// Line breaks are always "\n" here.
    var text: String
    var lineEnding: LineEnding = .lf
    var hasBOM = false
    /// UTF-8, or Windows-1252 for a file that is not valid UTF-8 (Windows' own Notepad wrote those).
    var encoding: String.Encoding = .utf8

    /// A zero byte means a binary file.
    static func decode(_ data: Data) throws(TextFileError) -> TextFile {
        guard !data.contains(0) else { throw .notText }
        let hasBOM = data.starts(with: byteOrderMark)
        let body = Data(hasBOM ? data.dropFirst(byteOrderMark.count) : data)
        if let raw = String(data: body, encoding: .utf8) {
            return TextFile(text: normalized(raw), lineEnding: commonestEnding(in: body), hasBOM: hasBOM)
        }
        guard let raw = String(data: body, encoding: .windowsCP1252) else { throw .notText }
        return TextFile(text: normalized(raw), lineEnding: commonestEnding(in: body), hasBOM: false, encoding: .windowsCP1252)
    }

    /// Stray "\r\n" and "\r" in `text` (pasted from elsewhere) count as line breaks too, so a break
    /// is never doubled. A character Windows-1252 cannot hold makes the file UTF-8.
    func encoded() -> Data {
        let unix = Self.normalized(text)
        let body = lineEnding == .lf ? unix : unix.replacingOccurrences(of: "\n", with: lineEnding.rawValue)
        if encoding == .windowsCP1252, let d = body.data(using: .windowsCP1252) { return d }
        return (hasBOM ? Data(Self.byteOrderMark) : Data()) + Data(body.utf8)
    }

    /// Checks the size before reading, so a huge file is refused without loading it.
    static func read(from url: URL) throws(TextFileError) -> TextFile {
        let target = url.resolvingSymlinksInPath()
        guard let size = try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw .unreadable }
        guard size <= maximumSize else { throw .tooLarge }
        guard let data = try? Data(contentsOf: target) else { throw .unreadable }
        guard data.count <= maximumSize else { throw .tooLarge }
        return try decode(data)
    }

    /// Follows a symlink, so the link stays a link. An existing file is swapped for a finished copy
    /// that carries its permissions; when anything fails, the original is left as it was. Only a
    /// regular file is ever swapped.
    func write(to url: URL) throws {
        let files = FileManager.default
        let target = url.resolvingSymlinksInPath()
        let data = encoded()
        guard files.fileExists(atPath: target.path) else {
            try data.write(to: target, options: .withoutOverwriting)
            return
        }
        guard try target.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: target.path])
        }
        let folder = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
        defer { try? files.removeItem(at: folder) }
        let copy = folder.appendingPathComponent(target.lastPathComponent)
        try data.write(to: copy)
        if let permissions = try files.attributesOfItem(atPath: target.path)[.posixPermissions] {
            try files.setAttributes([.posixPermissions: permissions], ofItemAtPath: copy.path)
        }
        _ = try files.replaceItemAt(target, withItemAt: copy)
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    /// The ending the file uses most; a tie goes to the one that shows up first, no break at all is LF.
    private static func commonestEnding(in bytes: Data) -> LineEnding {
        var counts: [LineEnding: Int] = [:]
        var firstSeen: [LineEnding] = []
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            var ending: LineEnding?
            if byte == 0x0D {
                let next = bytes.index(after: index)
                ending = next < bytes.endIndex && bytes[next] == 0x0A ? .crlf : .cr
            } else if byte == 0x0A {
                ending = .lf
            }
            if let ending {
                if counts[ending] == nil { firstSeen.append(ending) }
                counts[ending, default: 0] += 1
            }
            index = bytes.index(index, offsetBy: ending == .crlf ? 2 : 1)
        }
        var best = LineEnding.lf, bestCount = 0
        for ending in firstSeen where counts[ending, default: 0] > bestCount {
            best = ending; bestCount = counts[ending, default: 0]
        }
        return best
    }
}
