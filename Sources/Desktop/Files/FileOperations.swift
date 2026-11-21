// The file operations of RetroMac's file windows (Tiger's Finder, the Amiga drawers, the Windows
// Explorer). Adapted from retro98's Retro98FilesCore (FileOperations, FileCopy, FileRules),
// Copyright (c) 2026 matheushchaves, MIT License: github.com/matheushchaves/retro98.
import Foundation

enum FileOperationKind: Equatable { case copy, move }

enum ConflictChoice: Equatable { case replace, replaceAll, skip, cancel }

struct FileConflict: Equatable {
    let source: URL
    let existing: URL
    /// Items after this one ("Yes to All" only makes sense when > 0).
    let remaining: Int
}

/// Bytes while copying; items for everything else.
struct OperationProgress: Equatable {
    let item: URL
    let completed: Int64
    let total: Int64
}

/// One top-level effect of an operation, enough to take it back.
enum FileChange: Equatable {
    /// Undo: send to the Trash.
    case created(URL)
    /// Undo: move back to the exact path (also renames and put-backs).
    case moved(from: URL, to: URL)
    /// Undo: put back where it was.
    case trashed(original: URL, trashed: URL)

    /// The item this change is about, where it is now.
    var item: URL {
        switch self {
        case .created(let url), .moved(_, let url): url
        case .trashed(_, let trashed): trashed
        }
    }
}

enum OperationFailure: Equatable {
    case cancelled
    /// The destination is the item or inside it.
    case intoItself(URL)
    /// Replacing this item would trash the very item being copied or moved.
    case replacesItsOwnSource(URL)
    case alreadyExists(URL)
    case cannotTrash([URL])
    /// The top-level item and the system's reason.
    case failed(URL, String)
}

struct OperationOutcome: Equatable {
    var changes: [FileChange] = []
    var failure: OperationFailure?

    /// Items in their final place (what a window selects afterwards), in order.
    var results: [URL] {
        changes.compactMap { change in
            switch change {
            case .created(let url), .moved(_, let url): url
            case .trashed: nil
            }
        }
    }
}

final class OperationControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    var isCancelled: Bool { lock.withLock { cancelled } }
}

/// Synchronous and blocking: the windows run them off the main thread, tests call them directly.
/// Nothing is ever written over: replaced items go to the Trash first, and a move across volumes
/// removes the source only after the whole item was copied.
struct FileOperations {
    /// Sends an item to the Trash and returns where it went (tests pass a folder of their own).
    var moveToTrash: (URL) throws -> URL = { url in
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        return (trashed as URL?) ?? url
    }
    var isSameVolume: (URL, URL) -> Bool = { a, b in
        func volume(_ u: URL) -> NSObject? {
            (try? u.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        }
        guard let va = volume(a), let vb = volume(b) else { return false }
        return va.isEqual(vb)
    }

    // MARK: Copy and move

    func transfer(_ kind: FileOperationKind, _ items: [URL], to destination: URL, control: OperationControl,
                  resolve: (FileConflict) -> ConflictChoice, progress: @escaping (OperationProgress) -> Void) -> OperationOutcome {
        if let item = items.first(where: { Self.contains($0, destination) }) {
            return OperationOutcome(failure: .intoItself(item))
        }
        let needsCopy = { (item: URL) in kind == .copy || !isSameVolume(item, destination) }
        let copies = items.filter(needsCopy)
        let countsBytes = !copies.isEmpty
        let total = countsBytes ? copies.reduce(0) { $0 + FileCopy.totalSize(of: $1, control: control) } : Int64(items.count)
        var completed: Int64 = 0
        var outcome = OperationOutcome()
        var replaceAll = false

        for (index, item) in items.enumerated() {
            if control.isCancelled { outcome.failure = .cancelled; break }
            let size = countsBytes && needsCopy(item) ? FileCopy.totalSize(of: item, control: control) : 0
            let advance = { (done: Int64) in
                completed += done
                progress(OperationProgress(item: item, completed: completed, total: total))
            }
            // The same folder can be spelled through a link or with other letter case.
            let inPlace = Self.parent(of: item) == destination.standardizedFileURL.path
                || Self.sameFolder(item.deletingLastPathComponent(), destination)
            if kind == .move && inPlace { advance(countsBytes ? size : 1); continue }
            var name = item.lastPathComponent
            if kind == .copy && inPlace {
                name = FileNames.copyName(for: item, isFolder: Self.isPlainFolder(item), existing: Self.names(in: destination))
            }
            let target = destination.appendingPathComponent(name, isDirectory: false)
            let failure: OperationFailure?
            if Self.exists(target) {
                if Self.contains(target, item) { outcome.failure = .replacesItsOwnSource(target); break }
                let choice = replaceAll ? .replace : resolve(FileConflict(source: item, existing: target, remaining: items.count - index - 1))
                if choice == .cancel { outcome.failure = .cancelled; break }
                if choice == .skip { advance(countsBytes ? size : 1); continue }
                replaceAll = replaceAll || choice == .replaceAll
                failure = replace(target, with: item, kind: kind, control: control, onBytes: advance, changes: &outcome.changes)
            } else {
                failure = place(item, at: target, kind: kind, control: control, onBytes: advance, changes: &outcome.changes)
            }
            if let failure { outcome.failure = failure; break }
            if !countsBytes { advance(1) }
        }
        return outcome
    }

    /// Copies or moves one item to a free `target`; records the change, or returns why it stopped.
    private func place(_ item: URL, at target: URL, kind: FileOperationKind, control: OperationControl,
                       onBytes: @escaping (Int64) -> Void, changes: inout [FileChange]) -> OperationFailure? {
        let renames = kind == .move && isSameVolume(item, target.deletingLastPathComponent())
        if let failure = put(item, at: target, renaming: renames, control: control, onBytes: onBytes) { return failure }
        return finish(item, at: target, kind: kind, renamed: renames, changes: &changes)
    }

    /// Replacing: the new item first goes in under a hidden temporary name, so a cancel or a failure
    /// leaves the old one where it was; only then does the old item go to the Trash and the new one
    /// take its name.
    private func replace(_ existing: URL, with item: URL, kind: FileOperationKind, control: OperationControl,
                         onBytes: @escaping (Int64) -> Void, changes: inout [FileChange]) -> OperationFailure? {
        let folder = existing.deletingLastPathComponent()
        let staged = folder.appendingPathComponent(".retromac-\(UUID().uuidString)", isDirectory: false)
        let renames = kind == .move && isSameVolume(item, folder)
        if let failure = put(item, at: staged, renaming: renames, control: control, onBytes: onBytes) { return failure }
        let unstage = {
            if renames { try? FileManager.default.moveItem(at: staged, to: item) } else { try? FileManager.default.removeItem(at: staged) }
        }
        do {
            changes.append(.trashed(original: existing, trashed: try moveToTrash(existing)))
        } catch {
            unstage()
            return .failed(existing, error.localizedDescription)
        }
        guard Darwin.rename(staged.path, existing.path) == 0 else {
            let reason = FileCopy.reason(errno: errno)
            unstage()
            return .failed(item, reason)
        }
        return finish(item, at: existing, kind: kind, renamed: renames, changes: &changes)
    }

    /// Puts `item` itself (`renaming`, a move on the same volume) or a copy of it at `target`,
    /// recording nothing. A cancelled or failed copy removes what it had written.
    private func put(_ item: URL, at target: URL, renaming: Bool, control: OperationControl,
                     onBytes: @escaping (Int64) -> Void) -> OperationFailure? {
        if renaming {
            do { try FileManager.default.moveItem(at: item, to: target); return nil }
            catch { return .failed(item, error.localizedDescription) }
        }
        switch FileCopy.copy(item, to: target, control: control, onBytes: onBytes) {
        case .done: return nil
        case .cancelled:
            try? FileManager.default.removeItem(at: target)
            return .cancelled
        case .failed(let reason):
            try? FileManager.default.removeItem(at: target)
            return .failed(item, reason)
        }
    }

    /// Records what happened; a move across volumes removes the source only now that the copy is whole.
    private func finish(_ item: URL, at target: URL, kind: FileOperationKind, renamed: Bool,
                        changes: inout [FileChange]) -> OperationFailure? {
        guard kind == .move else { changes.append(.created(target)); return nil }
        if renamed { changes.append(.moved(from: item, to: target)); return nil }
        do {
            try FileManager.default.removeItem(at: item)
            changes.append(.moved(from: item, to: target))
            return nil
        } catch {
            changes.append(.created(target))
            return .failed(item, error.localizedDescription)
        }
    }

    // MARK: Trash, new folder, rename

    /// Items the Trash refuses are reported together.
    func trash(_ items: [URL], control: OperationControl, progress: (OperationProgress) -> Void) -> OperationOutcome {
        var outcome = OperationOutcome()
        var refused: [URL] = []
        for (index, item) in items.enumerated() {
            if control.isCancelled { outcome.failure = .cancelled; break }
            do { outcome.changes.append(.trashed(original: item, trashed: try moveToTrash(item))) }
            catch { if Self.exists(item) { refused.append(item) } }
            progress(OperationProgress(item: item, completed: Int64(index + 1), total: Int64(items.count)))
        }
        if outcome.failure == nil && !refused.isEmpty { outcome.failure = .cannotTrash(refused) }
        return outcome
    }

    func newFolder(in folder: URL, base: String) -> OperationOutcome {
        let url = folder.appendingPathComponent(FileNames.available(base, isFolder: true, existing: Self.names(in: folder)), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            return OperationOutcome(changes: [.created(url)])
        } catch {
            return OperationOutcome(failure: .failed(url, error.localizedDescription))
        }
    }

    /// rename(2) in the same folder: a change of case alone works on case-insensitive volumes.
    func rename(_ item: URL, to name: String) -> OperationOutcome {
        let target = item.deletingLastPathComponent().appendingPathComponent(name, isDirectory: false)
        if Self.exists(target) && !Self.sameFile(item, target) { return OperationOutcome(failure: .alreadyExists(target)) }
        guard Darwin.rename(item.path, target.path) == 0 else {
            return OperationOutcome(failure: .failed(item, FileCopy.reason(errno: errno)))
        }
        return OperationOutcome(changes: [.moved(from: item, to: target)])
    }

    // MARK: Revert

    /// Takes changes back in reverse order and stops at the first problem; the outcome lists what it did.
    func revert(_ changes: [FileChange], control: OperationControl) -> OperationOutcome {
        var outcome = OperationOutcome()
        for change in changes.reversed() {
            if control.isCancelled { outcome.failure = .cancelled; break }
            let failure: OperationFailure?
            switch change {
            case .created(let url):
                if Self.isGone(url) { failure = .failed(url, FileCopy.reason(errno: ENOENT)) }
                else {
                    do { outcome.changes.append(.trashed(original: url, trashed: try moveToTrash(url))); failure = nil }
                    catch { failure = .failed(url, error.localizedDescription) }
                }
            case .moved(let from, let to):
                failure = moveBack(to, to: from, control: control, changes: &outcome.changes)
            case .trashed(let original, let trashed):
                failure = moveBack(trashed, to: original, control: control, changes: &outcome.changes)
            }
            if let failure { outcome.failure = failure; break }
        }
        return outcome
    }

    /// Moves `item` to the exact path `target`, recreating missing parent folders.
    private func moveBack(_ item: URL, to target: URL, control: OperationControl, changes: inout [FileChange]) -> OperationFailure? {
        guard !Self.isGone(item) else { return .failed(item, FileCopy.reason(errno: ENOENT)) }
        if Self.exists(target) {
            guard Self.sameFile(item, target) else { return .alreadyExists(target) }
            guard Darwin.rename(item.path, target.path) == 0 else { return .failed(item, FileCopy.reason(errno: errno)) }
            changes.append(.moved(from: item, to: target))
            return nil
        }
        do { try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true) }
        catch { return .failed(item, error.localizedDescription) }
        return place(item, at: target, kind: .move, control: control, onBytes: { _ in }, changes: &changes)
    }

    // MARK: Paths

    /// Exists without following links (a broken link is still in the way).
    static func exists(_ url: URL) -> Bool { var info = stat(); return lstat(url.path, &info) == 0 }

    /// Known to be missing, as opposed to unreadable (the Trash without Full Disk Access).
    static func isGone(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) != 0 else { return false }
        return errno == ENOENT || errno == ENOTDIR
    }

    /// Device and inode: the same item whatever path spells it.
    static func identity(_ url: URL, following: Bool) -> [UInt64]? {
        var info = stat()
        guard (following ? stat(url.path, &info) : lstat(url.path, &info)) == 0 else { return nil }
        return [UInt64(info.st_dev), info.st_ino]
    }
    static func sameFile(_ a: URL, _ b: URL) -> Bool {
        guard let first = identity(a, following: false) else { return false }
        return first == identity(b, following: false)
    }
    static func sameFolder(_ a: URL, _ b: URL) -> Bool {
        guard let first = identity(a, following: true) else { return false }
        return first == identity(b, following: true)
    }

    /// `inner` is `outer` or inside it: by path, or by file identity when a link or another letter
    /// case spells the same place differently.
    static func contains(_ outer: URL, _ inner: URL) -> Bool {
        let outerPath = outer.standardizedFileURL.path, innerPath = inner.standardizedFileURL.path
        if innerPath == outerPath || innerPath.hasPrefix(outerPath == "/" ? "/" : outerPath + "/") { return true }
        guard let target = identity(outer, following: false) else { return false }
        var current = inner.standardizedFileURL
        if identity(current, following: false) == target { return true }
        while current.path != "/" {
            current = current.deletingLastPathComponent()
            if identity(current, following: true) == target { return true }
        }
        return false
    }

    static func parent(of url: URL) -> String { url.standardizedFileURL.deletingLastPathComponent().path }
    static func names(in folder: URL) -> Set<String> { Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []) }
    static func isPlainFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }
}

/// Copies one item (file, folder or package) with copyfile(3): clones on APFS, keeps links,
/// extended attributes and permissions, and never writes over anything (COPYFILE_EXCL).
enum FileCopy {
    enum Result: Equatable { case done, cancelled, failed(String) }

    static let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_CLONE | COPYFILE_EXCL | COPYFILE_NOFOLLOW_SRC)

    /// `onBytes` gets each increment of copied bytes (a cloned file counts whole when it finishes).
    /// A failed or cancelled copy leaves a partial destination; the caller removes it.
    static func copy(_ source: URL, to destination: URL, control: OperationControl, onBytes: @escaping (Int64) -> Void) -> Result {
        let context = Context(control: control, onBytes: onBytes)
        guard let state = copyfile_state_alloc() else { return .failed(reason(errno: ENOMEM)) }
        defer { copyfile_state_free(state) }
        let callback: copyfile_callback_t = { what, stage, state, source, _, context in
            guard let context else { return COPYFILE_CONTINUE }
            return Unmanaged<Context>.fromOpaque(context).takeUnretainedValue().handle(what: what, stage: stage, state: state, source: source)
        }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(context).toOpaque())
        let result = withExtendedLifetime(context) { copyfile(source.path, destination.path, state, flags) }
        if result == 0 { return .done }
        if control.isCancelled { return .cancelled }
        return .failed(reason(errno: context.error ?? errno))
    }

    static func reason(errno code: Int32) -> String { NSError(domain: NSPOSIXErrorDomain, code: Int(code)).localizedDescription }

    /// Size of one item as lstat sees it (links are not followed); folders count as 0.
    static func size(ofPath path: String) -> Int64 {
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) != S_IFDIR else { return 0 }
        return Int64(info.st_size)
    }

    /// Total bytes of everything inside `item` (the item itself when it is a file).
    static func totalSize(of item: URL, control: OperationControl) -> Int64 {
        var total = size(ofPath: item.path)
        guard let enumerator = FileManager.default.enumerator(atPath: item.path) else { return total }
        while let relative = enumerator.nextObject() as? String, !control.isCancelled {
            total += size(ofPath: item.path + "/" + relative)
        }
        return total
    }

    private final class Context {
        let control: OperationControl
        let onBytes: (Int64) -> Void
        var reportedForFile: Int64 = 0
        var error: Int32?
        init(control: OperationControl, onBytes: @escaping (Int64) -> Void) { self.control = control; self.onBytes = onBytes }

        func handle(what: Int32, stage: Int32, state: copyfile_state_t?, source: UnsafePointer<CChar>?) -> Int32 {
            if stage == COPYFILE_ERR { error = errno; return COPYFILE_QUIT }
            if control.isCancelled { return COPYFILE_QUIT }
            switch (what, stage) {
            case (COPYFILE_RECURSE_FILE, COPYFILE_START):
                reportedForFile = 0
            case (COPYFILE_COPY_DATA, COPYFILE_PROGRESS):
                var copied: off_t = 0
                if let state, copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied) == 0, copied > reportedForFile {
                    onBytes(Int64(copied) - reportedForFile)
                    reportedForFile = Int64(copied)
                }
            case (COPYFILE_RECURSE_FILE, COPYFILE_FINISH):
                let size = source.map { FileCopy.size(ofPath: String(cString: $0)) } ?? 0
                if size > reportedForFile { onBytes(size - reportedForFile) }
                reportedForFile = 0
            default: break
            }
            return COPYFILE_CONTINUE
        }
    }
}

enum FileNames {
    /// "photo copy.jpg", "photo copy 2.jpg"… as the Finder names them. Plain folders have no
    /// extension ("v1.2 copy"); packages do ("Calc copy.app").
    static func copyName(for item: URL, isFolder: Bool, existing: Set<String>, word: String = "copy") -> String {
        let (base, ext) = split(item.lastPathComponent, isFolder: isFolder)
        return first(in: existing) { $0 == 1 ? join("\(base) \(word)", ext) : join("\(base) \(word) \($0)", ext) }
    }

    /// The name itself, or "<base> 2<.ext>", "<base> 3<.ext>"… when it is taken.
    static func available(_ name: String, isFolder: Bool, existing: Set<String>) -> String {
        let (base, ext) = split(name, isFolder: isFolder)
        return first(in: existing) { $0 == 1 ? name : join("\(base) \($0)", ext) }
    }

    private static func split(_ name: String, isFolder: Bool) -> (base: String, ext: String) {
        let ext = (name as NSString).pathExtension
        guard !isFolder, !ext.isEmpty else { return (name, "") }
        return ((name as NSString).deletingPathExtension, ext)
    }
    private static func join(_ base: String, _ ext: String) -> String { ext.isEmpty ? base : "\(base).\(ext)" }

    /// Names are compared the way APFS does: ignoring case and Unicode normalization.
    private static func first(in existing: Set<String>, _ candidate: (Int) -> String) -> String {
        let taken = Set(existing.map { $0.precomposedStringWithCanonicalMapping.lowercased() })
        var number = 1
        while taken.contains(candidate(number).precomposedStringWithCanonicalMapping.lowercased()) { number += 1 }
        return candidate(number)
    }
}

enum RenameCheck: Equatable {
    case unchanged
    case accept(String)
    case invalid(String)
    case confirmExtensionChange(from: String, to: String)
}

enum RenameRules {
    /// Trims spaces at the ends; "unchanged" uses Swift's == (NFC and NFD spellings are equal).
    static func check(original: String, typed: String, isFolder: Bool) -> RenameCheck {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != original else { return .unchanged }
        if name.contains("/") || name.contains(":") { return .invalid("A file name can't contain a slash or a colon.") }
        if name == "." || name == ".." || name.hasPrefix(".") { return .invalid("Names that begin with a dot are reserved for the system.") }
        if name.utf8.count > 255 { return .invalid("The name is too long.") }
        if !isFolder {
            let from = (original as NSString).pathExtension, to = (name as NSString).pathExtension
            if !from.isEmpty && from.lowercased() != to.lowercased() {
                return .confirmExtensionChange(from: "." + from, to: to.isEmpty ? "" : "." + to)
            }
        }
        return .accept(name)
    }
}
