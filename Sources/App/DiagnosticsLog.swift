import Foundation
import AppKit
import Metal

/// In-app diagnostics log. Captures the app's console output (stdout + stderr — i.e. every
/// `print("[Overlay] …")`, `[Dock]`, capture errors, etc.) into a ring buffer that the About
/// tab can show, copy and export. Helps debug issues like "shader doesn't show on display X"
/// without needing Console.app: reproduce the problem, then Copy/Save the report.
final class DiagnosticsLog {

    static let shared = DiagnosticsLog()
    static let didChange = Notification.Name("DiagnosticsLogDidChange")

    private let maxLines = 2000
    private var lines: [String] = []
    private let lock = NSLock()
    private var started = false
    private var originalStdout: Int32 = -1
    private var originalStderr: Int32 = -1
    private var stdoutPipe: Pipe?   // MUST be retained — if released, the read end closes and
    private var stderrPipe: Pipe?   // the next write to the redirected fd raises SIGPIPE → crash.
    private var partial = ""
    private var notifyScheduled = false

    private init() {}

    /// Begin capturing console output. Call once, as early as possible at launch.
    func start() {
        guard !started else { return }
        started = true
        signal(SIGPIPE, SIG_IGN)   // never die if a redirected fd's reader goes away
        append("=== RetroMac diagnostics ===")
        append(systemInfo())
        append("--- console ---")
        stdoutPipe = capture(STDOUT_FILENO, keep: &originalStdout)
        stderrPipe = capture(STDERR_FILENO, keep: &originalStderr)
    }

    private func capture(_ fd: Int32, keep: inout Int32) -> Pipe {
        let pipe = Pipe()
        keep = dup(fd)                                   // remember the real terminal/Console fd
        dup2(pipe.fileHandleForWriting.fileDescriptor, fd)
        let orig = keep
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            data.withUnsafeBytes { _ = write(orig, $0.baseAddress, data.count) }   // tee back out
            if let s = String(data: data, encoding: .utf8) { self?.ingest(s) }
        }
        return pipe   // retained by the caller so the read end stays open
    }

    private func ingest(_ chunk: String) {
        lock.lock()
        partial += chunk
        var fresh: [String] = []
        while let nl = partial.firstIndex(of: "\n") {
            fresh.append(String(partial[..<nl]))
            partial = String(partial[partial.index(after: nl)...])
        }
        if !fresh.isEmpty {
            lines.append(contentsOf: fresh)
            if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        }
        lock.unlock()
        if !fresh.isEmpty { scheduleNotify() }
    }

    /// Append a line directly (also used for the header / system info).
    func append(_ line: String) {
        lock.lock()
        lines.append(contentsOf: line.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        lock.unlock()
        scheduleNotify()
    }

    private func scheduleNotify() {
        DispatchQueue.main.async {
            guard !self.notifyScheduled else { return }
            self.notifyScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.notifyScheduled = false
                NotificationCenter.default.post(name: DiagnosticsLog.didChange, object: nil)
            }
        }
    }

    func snapshot() -> String {
        lock.lock(); let copy = lines; lock.unlock()
        return copy.joined(separator: "\n")
    }

    /// Fresh system + display summary followed by the captured log — what to send for support.
    func fullReport() -> String {
        systemInfo() + "\n--- console ---\n" + snapshot()
    }

    func systemInfo() -> String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        var s = "RetroMac \(v) (build \(b)) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        if let dev = MTLCreateSystemDefaultDevice() { s += "GPU: \(dev.name)\n" }
        s += "Displays (\(NSScreen.screens.count)):\n"
        for scr in NSScreen.screens {
            let id = (scr.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let f = scr.frame
            let main = (scr == NSScreen.main) ? " [main]" : ""
            s += "  • \(scr.localizedName) id=\(id) \(Int(f.width))x\(Int(f.height)) @\(scr.backingScaleFactor)x\(main)\n"
        }
        return s
    }
}
