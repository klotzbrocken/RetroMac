import AppKit

// Redirect stdout/stderr to log file for when launched as .app bundle
import Foundation
freopen("/tmp/retromac.log", "w", stdout)
freopen("/tmp/retromac.log", "w", stderr)
setbuf(stdout, nil)
setbuf(stderr, nil)

print("[RetroMac] Starting... PID=\(ProcessInfo.processInfo.processIdentifier)")
fflush(stdout)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
