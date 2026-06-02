import AppKit
import Foundation

// Route stdout/stderr to a log in the standard macOS location, owner-only, with a
// simple one-file rotation — instead of the world-readable /tmp/retromac.log, which
// could expose URLs, license errors, window titles or other PII to any local user.
let logDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/RetroMac")
try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
let logPath = (logDir as NSString).appendingPathComponent("retromac.log")
let prevPath = (logDir as NSString).appendingPathComponent("retromac.previous.log")

// Rotate: keep the previous session's log as a single backup.
if FileManager.default.fileExists(atPath: logPath) {
    try? FileManager.default.removeItem(atPath: prevPath)
    try? FileManager.default.moveItem(atPath: logPath, toPath: prevPath)
}

freopen(logPath, "w", stdout)
freopen(logPath, "w", stderr)
setbuf(stdout, nil)
setbuf(stderr, nil)

// Owner-only — logs may contain window titles, URLs, or diagnostic data.
try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logPath)

print("[RetroMac] Starting... PID=\(ProcessInfo.processInfo.processIdentifier)")
fflush(stdout)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
