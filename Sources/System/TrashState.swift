import AppKit

/// Whether the trash is empty, answered without crashing the process and without stalling the UI.
///
/// Two places need this and both used to get it wrong. `~/.Trash` is TCC-gated on modern macOS, so
/// without Full Disk Access the count has to come from Finder over AppleScript, and that call has
/// two separate costs. Both were measured on the live process with `sample`, not assumed:
///
///   - **It is not thread safe.** Both callers ran it on a global queue, so a theme switch that
///     rebuilds the dock and the desktop icons at once had two worker threads asking Finder in the
///     same moment, and the process died with a segmentation fault inside AppleEvents.
///   - **Building an NSAppleScript from a string costs ~170 ms every single time**, because macOS
///     runs each script through XProtect (InterpreterSecurity → YARA) before compiling it. The
///     Finder round trip adds ~160 ms on top. With the two callers polling every 3 s and 4 s, that
///     was more than a tenth of all main-thread time, permanently — not just during a switch.
///
/// Hence all four measures here: the direct read stays off-main because it is a plain directory
/// enumeration; the AppleScript hop is always made on the main thread, where the runloop serialises
/// it against every other NSAppleScript in the app; the compiled script is kept and reused; and one
/// answer is shared between callers for a few seconds, so two pollers cost one query, not two.
enum TrashState {

    /// How long an answer is reused. Both callers are also told when the trash really changes and
    /// call `invalidate`, so this only caps how often *polling* can reach Finder.
    private static let freshness: CFAbsoluteTime = 10

    /// Main thread only, like `script`.
    private static var cached: (empty: Bool, at: CFAbsoluteTime)?

    /// Compiled once and reused — see what building one costs, above.
    private static var script: NSAppleScript?

    /// Call on the main thread. `completion` runs on the main thread.
    static func isEmpty(_ completion: @escaping (Bool) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let c = cached, CFAbsoluteTimeGetCurrent() - c.at < freshness {
            completion(c.empty)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            if let direct = directRead() {
                DispatchQueue.main.async { store(direct); completion(direct) }
                return
            }
            DispatchQueue.main.async {
                // The other caller may have filled the cache while this was off-main: a theme
                // switch refreshes the dock and the desktop icons within the same runloop turn.
                if let c = cached, CFAbsoluteTimeGetCurrent() - c.at < freshness {
                    completion(c.empty)
                    return
                }
                // Unknown counts as empty: a wrong "full" icon is the more visible mistake.
                let empty = viaFinder() ?? true
                store(empty)
                completion(empty)
            }
        }
    }

    /// Drop the cached answer. For callers that have been told the trash actually changed, so the
    /// icon updates at once instead of at the end of the freshness window.
    static func invalidate() {
        dispatchPrecondition(condition: .onQueue(.main))
        cached = nil
    }

    private static func store(_ empty: Bool) {
        cached = (empty, CFAbsoluteTimeGetCurrent())
    }

    /// Fast path, only succeeds with Full Disk Access. `nil` means "could not tell".
    private static func directRead() -> Bool? {
        guard let url = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: false),
              let names = try? FileManager.default.contentsOfDirectory(atPath: url.path)
        else { return nil }
        return !names.contains { !$0.hasPrefix(".") }
    }

    /// MAIN THREAD ONLY — see the note above. `nil` means Finder did not answer.
    private static func viaFinder() -> Bool? {
        dispatchPrecondition(condition: .onQueue(.main))
        if script == nil {
            script = NSAppleScript(source: "tell application \"Finder\" to return (count of items of trash)")
        }
        guard let script else { return nil }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        return err == nil ? Int(result.int32Value) == 0 : nil
    }
}
