import AppKit
import ApplicationServices

extension Notification.Name {
    static let minimizedWindowsChanged = Notification.Name("minimizedWindowsChanged")
    static let windowsChanged = Notification.Name("windowsChanged")
}

/// Tracks the top-level windows of regular apps via the Accessibility API. Two published lists:
/// `entries` (minimized windows only — back-compat: the dock surfaces a tile for non-pinned
/// apps that have minimized windows) and `allWindows` (every top-level window, with focus +
/// minimized state — used by the Win98/XP taskbar's per-window task buttons). Poll-based (1.5s);
/// the AX scan runs on a background queue, only the published lists are touched on main.
final class MinimizedWindowTracker {

    static let shared = MinimizedWindowTracker()

    struct Entry {
        let pid: pid_t
        let bundleID: String
        let title: String
        let window: AXUIElement
        var isMinimized: Bool = false
        var isFocused: Bool = false
    }

    private(set) var entries: [Entry] = []      // minimized windows only (back-compat)
    private(set) var allWindows: [Entry] = []   // every top-level window (task buttons)
    private var timer: Timer?
    private var didPrompt = false
    private var scanInProgress = false   // don't pile up scans if an app responds slowly
    private var scanGeneration = 0       // stop()/new scans invalidate stale in-flight results
    /// Serial queue for the (potentially slow) Accessibility scan so the main thread never blocks.
    private let scanQueue = DispatchQueue(label: "com.retromac.minimized-tracker")

    func start() {
        guard timer == nil else { return }
        // Accessibility is already part of onboarding; prompt once if it's still missing.
        if !AXIsProcessTrusted() && !didPrompt {
            didPrompt = true
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        SystemBridge.shared.ensureAccessibility()   // reconcile the cached capability for Health Check
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        scanGeneration += 1          // invalidate any in-flight scan so it can't republish entries
        scanInProgress = false
        let had = !entries.isEmpty || !allWindows.isEmpty
        entries = []; allWindows = []
        if had { notify() }
    }

    /// Restore every minimized window of the given app (dock-tile click).
    func restoreWindows(for bundleID: String) {
        let wins = entries.filter { $0.bundleID == bundleID }
        guard !wins.isEmpty else { return }
        for e in wins {
            AXUIElementSetAttributeValue(e.window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.poll() }
    }

    /// Bring a specific window to the front (de-minimize, make main, raise, activate the app).
    func activate(_ e: Entry) {
        AXUIElementSetAttributeValue(e.window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(e.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(e.window, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: e.pid)?.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.poll() }
    }

    /// Minimize a specific window (clicking the active window's task button).
    func minimize(_ e: Entry) {
        AXUIElementSetAttributeValue(e.window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.poll() }
    }

    private func poll() {
        guard AXIsProcessTrusted() else { return }
        guard !scanInProgress else { return }   // a scan is still running — don't queue another
        scanInProgress = true
        scanGeneration += 1
        let gen = scanGeneration
        // Snapshot running apps + frontmost pid on main; do the AX queries off-main.
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        let apps: [(pid_t, String, String?)] = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bid = app.bundleIdentifier, bid != ownBundleID else { return nil }
                return (app.processIdentifier, bid, app.localizedName)
            }
        scanQueue.async { [weak self] in
            guard let self = self else { return }
            var all: [Entry] = []
            for (pid, bid, localName) in apps {
                let axApp = AXUIElementCreateApplication(pid)
                var winsRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &winsRef) == .success,
                      let wins = winsRef as? [AXUIElement] else { continue }
                // Focused window of the frontmost app (for the "active" task button).
                var focused: AXUIElement?
                if pid == frontPID {
                    var fRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &fRef) == .success,
                       let f = fRef, CFGetTypeID(f) == AXUIElementGetTypeID() {
                        focused = (f as! AXUIElement)
                    }
                }
                for w in wins {
                    // Skip non-window roles (sheets/popovers sometimes appear here).
                    var roleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(w, kAXRoleAttribute as CFString, &roleRef)
                    if let role = roleRef as? String, role != (kAXWindowRole as String) { continue }
                    var minRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minRef)
                    let isMin = (minRef as? Bool) == true
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &titleRef)
                    let title = (titleRef as? String).flatMap { $0.isEmpty ? nil : $0 } ?? localName ?? bid
                    // A minimized window is never "active" (kAXFocusedWindow can still point at
                    // it), otherwise its task button would re-minimize instead of restoring.
                    let isFocused = !isMin && (focused.map { CFEqual($0, w) } ?? false)
                    all.append(Entry(pid: pid, bundleID: bid, title: title, window: w,
                                     isMinimized: isMin, isFocused: isFocused))
                }
            }
            let minimized = all.filter { $0.isMinimized }
            DispatchQueue.main.async {
                // Check generation FIRST: a stale scan must not clear a newer scan's in-progress
                // flag (that would let a third scan start while the newer one is still running).
                guard gen == self.scanGeneration else { return }   // superseded by stop()/newer scan
                self.scanInProgress = false
                func sig(_ list: [Entry]) -> [String] {
                    list.map { "\($0.bundleID)|\($0.title)|\($0.isMinimized ? 1 : 0)|\($0.isFocused ? 1 : 0)" }
                }
                let changed = sig(all) != sig(self.allWindows)
                self.allWindows = all
                self.entries = minimized
                if changed { self.notify() }
            }
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: .minimizedWindowsChanged, object: nil)
        NotificationCenter.default.post(name: .windowsChanged, object: nil)
    }
}
