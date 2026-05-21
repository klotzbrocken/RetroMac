import AppKit

enum AppLauncher {

    static func launchOrActivate(bundleID: String) {
        let ws = NSWorkspace.shared
        guard let url = ws.urlForApplication(withBundleIdentifier: bundleID) else {
            print("[Dock] App not found: \(bundleID)")
            return
        }

        if let running = ws.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            running.activate(options: [.activateAllWindows])
            if !hasVisibleWindows(pid: running.processIdentifier) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                ws.openApplication(at: url, configuration: config) { _, _ in }
            }
            print("[Dock] Activated \(bundleID)")
        } else {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            ws.openApplication(at: url, configuration: config) { _, error in
                if let error = error {
                    print("[Dock] Launch failed for \(bundleID): \(error)")
                } else {
                    print("[Dock] Launched \(bundleID)")
                }
            }
        }
    }

    private static func hasVisibleWindows(pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return list.contains { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w > 1, h > 1 else { return false }
            return true
        }
    }

    static func isRunning(bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    static func runningApp(bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }

    static func terminate(bundleID: String) {
        runningApp(bundleID: bundleID)?.terminate()
    }

    static func forceTerminate(bundleID: String) {
        runningApp(bundleID: bundleID)?.forceTerminate()
    }

    static func showInFinder(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
