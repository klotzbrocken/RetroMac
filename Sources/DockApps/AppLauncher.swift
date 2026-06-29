import AppKit
import ApplicationServices

enum AppLauncher {

    static func launchOrActivate(bundleID: String) {
        let ws = NSWorkspace.shared
        guard let url = ws.urlForApplication(withBundleIdentifier: bundleID) else {
            print("[Dock] App not found: \(bundleID)")
            return
        }

        if let running = ws.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            // Raise the app's front window via AX first — on Sonoma/Sequoia
            // NSRunningApplication.activate alone often fails to pull a background
            // app's windows forward (this is why the Win98/XP taskbar, which uses AX,
            // worked while plain Dock tiles didn't). Then activate, ignoring others.
            raiseFrontWindow(pid: running.processIdentifier)
            running.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
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

    /// Bring an already-running app's front window forward via Accessibility.
    /// macOS's window list isn't guaranteed front-to-back, but the first non-minimized
    /// window is the app's main window in practice; raising it + marking it main makes
    /// the click behave like the real Dock. No-op without AX trust.
    private static func raiseFrontWindow(pid: pid_t) {
        guard SystemBridge.shared.ensureAccessibility() else { print("[Dock] raise: AX not trusted"); return }
        let axApp = AXUIElementCreateApplication(pid)
        // Mark the whole app frontmost via AX — the reliable cross-app bring-to-front on
        // modern macOS, where NSRunningApplication.activate often won't raise a background
        // app's windows from a background (LSUIElement) agent.
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        var winsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &winsRef) == .success,
              let wins = winsRef as? [AXUIElement] else { print("[Dock] raise: no AX windows for pid \(pid)"); return }
        // Prefer the first non-minimized window; fall back to the first window.
        let target = wins.first { w in
            var minRef: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minRef)
            return (minRef as? Bool) != true
        } ?? wins.first
        guard let window = target else { return }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
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
