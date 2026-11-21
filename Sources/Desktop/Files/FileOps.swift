import AppKit

extension Notification.Name {
    /// A file operation of RetroMac's file windows finished; the windows reload.
    static let fileOperationsDidChange = Notification.Name("fileOperationsDidChange")
}

/// Runs the file operations of RetroMac's file windows off the main thread: a progress window for
/// anything that takes a while, the "Confirm File Replace" question, the error, and one undo
/// history for every window (after retro98's FileUndoStack). Undo and redo wait while anything runs.
/// Used from the main thread only.
final class FileOps {
    static let shared = FileOps()
    var operations = FileOperations()

    enum Name: String { case copy = "Copy", move = "Move", rename = "Rename", newFolder = "New Folder", delete = "Delete", duplicate = "Duplicate" }
    struct Action { let name: Name; let changes: [FileChange] }

    private(set) var undoActions: [Action] = []
    private(set) var redoActions: [Action] = []
    private(set) var busy = 0
    var canUndo: Bool { busy == 0 && !undoActions.isEmpty }
    var canRedo: Bool { busy == 0 && !redoActions.isEmpty }
    var undoTitle: String { undoActions.last.map { "Undo \($0.name.rawValue)" } ?? "Can't Undo" }
    var redoTitle: String { redoActions.last.map { "Redo \($0.name.rawValue)" } ?? "Can't Redo" }

    typealias Work = (FileOperations, OperationControl, _ resolve: (FileConflict) -> ConflictChoice,
                      _ progress: @escaping (OperationProgress) -> Void) -> OperationOutcome

    /// Runs `work` in the background; records it for undo, reports a failure, tells the windows.
    func run(_ name: Name, title: String, record: Bool = true, done: ((OperationOutcome) -> Void)? = nil, _ work: @escaping Work) {
        busy += 1
        let control = OperationControl()
        let progress = ProgressWindow(title: title, control: control)
        let ops = operations
        // A short operation finishes before the window would have shown.
        let show = DispatchWorkItem { progress.show() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: show)
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = work(ops, control, { conflict in
                DispatchQueue.main.sync { Self.ask(conflict) }
            }, { p in
                DispatchQueue.main.async { progress.update(p) }
            })
            DispatchQueue.main.async {
                do {
                    show.cancel(); progress.close()
                    self.busy -= 1
                    if record, !outcome.changes.isEmpty {
                        self.undoActions.append(Action(name: name, changes: outcome.changes))
                        self.redoActions.removeAll()
                    }
                    if let failure = outcome.failure { Self.report(failure, verb: name) }
                    NotificationCenter.default.post(name: .fileOperationsDidChange, object: nil)
                    done?(outcome)
                }
            }
        }
    }

    func undo() {
        guard canUndo, let action = undoActions.popLast() else { NSSound.beep(); return }
        run(action.name, title: "Undoing \(action.name.rawValue)…", record: false, done: { [weak self] outcome in
            if !outcome.changes.isEmpty { self?.redoActions.append(Action(name: action.name, changes: outcome.changes)) }
        }) { ops, control, _, _ in ops.revert(action.changes, control: control) }
    }

    func redo() {
        guard canRedo, let action = redoActions.popLast() else { NSSound.beep(); return }
        run(action.name, title: "Redoing \(action.name.rawValue)…", record: false, done: { [weak self] outcome in
            if !outcome.changes.isEmpty { self?.undoActions.append(Action(name: action.name, changes: outcome.changes)) }
        }) { ops, control, _, _ in ops.revert(action.changes, control: control) }
    }

    // MARK: Convenience

    func copy(_ items: [URL], to folder: URL, done: ((OperationOutcome) -> Void)? = nil) {
        guard !items.isEmpty else { return }
        run(.copy, title: "Copying…", done: done) { ops, c, resolve, progress in ops.transfer(.copy, items, to: folder, control: c, resolve: resolve, progress: progress) }
    }
    func move(_ items: [URL], to folder: URL, done: ((OperationOutcome) -> Void)? = nil) {
        guard !items.isEmpty else { return }
        run(.move, title: "Moving…", done: done) { ops, c, resolve, progress in ops.transfer(.move, items, to: folder, control: c, resolve: resolve, progress: progress) }
    }
    func trash(_ items: [URL], done: ((OperationOutcome) -> Void)? = nil) {
        guard !items.isEmpty else { return }
        run(.delete, title: "Moving to the Trash…", done: done) { ops, c, _, progress in ops.trash(items, control: c, progress: progress) }
    }
    func newFolder(in folder: URL, base: String, done: ((OperationOutcome) -> Void)? = nil) {
        run(.newFolder, title: "New Folder", done: done) { ops, _, _, _ in ops.newFolder(in: folder, base: base) }
    }
    func rename(_ item: URL, to name: String, done: ((OperationOutcome) -> Void)? = nil) {
        run(.rename, title: "Renaming…", done: done) { ops, _, _, _ in ops.rename(item, to: name) }
    }

    /// File URLs on the pasteboard (the Finder's own copy works with these too).
    static func pasteboardFiles() -> [URL] {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    static func putOnPasteboard(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
    }

    // MARK: Questions and errors

    private static func ask(_ c: FileConflict) -> ConflictChoice {
        func describe(_ u: URL) -> String {
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
            let size = v?.isDirectory == true ? "folder" : ByteCountFormatter.string(fromByteCount: Int64(v?.fileSize ?? 0), countStyle: .file)
            let date = v?.contentModificationDate.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "?"
            return "\(size), modified \(date)"
        }
        let a = NSAlert()
        a.messageText = "Confirm File Replace"
        a.informativeText = "This folder already contains an item named \u{201C}\(c.existing.lastPathComponent)\u{201D}.\n\n"
            + "Would you like to replace the existing item\n(\(describe(c.existing)))\n\nwith this one?\n(\(describe(c.source)))\n\n"
            + "The existing item goes to the Trash."
        a.addButton(withTitle: "Yes")
        if c.remaining > 0 { a.addButton(withTitle: "Yes to All") }
        a.addButton(withTitle: "No")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        let r = a.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let choices: [ConflictChoice] = c.remaining > 0 ? [.replace, .replaceAll, .skip, .cancel] : [.replace, .skip, .cancel]
        return r >= 0 && r < choices.count ? choices[r] : .cancel
    }

    private static func report(_ failure: OperationFailure, verb: Name) {
        let message: String
        switch failure {
        case .cancelled: return
        case .intoItself(let u): message = "\u{201C}\(u.lastPathComponent)\u{201D} can't go into itself or into a folder inside it."
        case .replacesItsOwnSource(let u): message = "\u{201C}\(u.lastPathComponent)\u{201D} would replace the very item being copied."
        case .alreadyExists(let u): message = "An item named \u{201C}\(u.lastPathComponent)\u{201D} already exists."
        case .cannotTrash(let urls): message = urls.map { "\u{201C}\($0.lastPathComponent)\u{201D}" }.joined(separator: ", ") + " can't be moved to the Trash."
        case .failed(let u, let reason): message = "\u{201C}\(u.lastPathComponent)\u{201D}: \(reason)"
        }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "\(verb.rawValue) failed"
        a.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

/// The small "Copying…" window: the item, a bar and Cancel.
private final class ProgressWindow: NSObject {
    private let title: String
    private let control: OperationControl
    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()

    init(title: String, control: OperationControl) { self.title = title; self.control = control }

    func show() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 104), styleMask: [.titled], backing: .buffered, defer: false)
        p.title = title
        p.level = .floating
        p.hidesOnDeactivate = false
        let v = p.contentView!
        label.frame = NSRect(x: 18, y: 66, width: 324, height: 18); label.lineBreakMode = .byTruncatingMiddle
        bar.frame = NSRect(x: 18, y: 42, width: 324, height: 16); bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 1
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.frame = NSRect(x: 252, y: 8, width: 92, height: 28); cancel.keyEquivalent = "\u{1b}"
        [label, bar, cancel].forEach { v.addSubview($0) }
        p.center()
        p.orderFrontRegardless()
        panel = p
    }
    func update(_ p: OperationProgress) {
        label.stringValue = p.item.lastPathComponent
        bar.doubleValue = p.total > 0 ? Double(p.completed) / Double(p.total) : 0
    }
    @objc private func cancel() { control.cancel() }
    func close() { panel?.orderOut(nil); panel = nil }
}
