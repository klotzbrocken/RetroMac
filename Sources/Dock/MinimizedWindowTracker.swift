import AppKit
import ApplicationServices

extension Notification.Name {
    static let minimizedWindowsChanged = Notification.Name("minimizedWindowsChanged")
}

/// Tracks minimized windows of regular apps via the Accessibility API. The system Dock is
/// hidden while a theme is active, so a minimized window would otherwise vanish with no way
/// back; the themed dock therefore surfaces a tile for any non-pinned app that has minimized
/// windows (see DockView.runningAppsNotInDock), and clicking that tile calls
/// `restoreWindows(for:)` to de-minimize them. Poll-based (1.5s) — AX miniaturize
/// notifications would need one observer per app; polling is simpler and plenty fast.
/// The AX scan runs on a background queue; only the published `entries` are touched on main.
final class MinimizedWindowTracker {

    static let shared = MinimizedWindowTracker()

    struct Entry {
        let pid: pid_t
        let bundleID: String
        let title: String
        let window: AXUIElement
    }

    private(set) var entries: [Entry] = []
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
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        scanGeneration += 1          // invalidate any in-flight scan so it can't republish entries
        scanInProgress = false
        if !entries.isEmpty { entries = []; notify() }
    }

    /// Restore every minimized window of the given app (dock-tile click).
    func restoreWindows(for bundleID: String) {
        let wins = entries.filter { $0.bundleID == bundleID }
        guard !wins.isEmpty else { return }
        for e in wins {
            AXUIElementSetAttributeValue(e.window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.poll() }
    }

    func restore(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        let e = entries[index]
        AXUIElementSetAttributeValue(e.window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        NSRunningApplication(processIdentifier: e.pid)?.activate(options: [.activateIgnoringOtherApps])
        // Re-poll soon so the tile disappears right after the window restores.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.poll() }
    }

    private func poll() {
        guard AXIsProcessTrusted() else { return }
        guard !scanInProgress else { return }   // a scan is still running — don't queue another
        scanInProgress = true
        scanGeneration += 1
        let gen = scanGeneration
        // Snapshot the running apps on main, then do the AX queries off-main: a slow-to-respond
        // app must not stall the main thread every 1.5s.
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let apps: [(pid_t, String, String?)] = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bid = app.bundleIdentifier, bid != ownBundleID else { return nil }
                return (app.processIdentifier, bid, app.localizedName)
            }
        scanQueue.async { [weak self] in
            guard let self = self else { return }
            var found: [Entry] = []
            for (pid, bid, localName) in apps {
                let axApp = AXUIElementCreateApplication(pid)
                var winsRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &winsRef) == .success,
                      let wins = winsRef as? [AXUIElement] else { continue }
                for w in wins {
                    var minRef: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minRef) == .success,
                          (minRef as? Bool) == true else { continue }
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &titleRef)
                    let title = (titleRef as? String).flatMap { $0.isEmpty ? nil : $0 }
                        ?? localName ?? bid
                    found.append(Entry(pid: pid, bundleID: bid, title: title, window: w))
                }
            }
            DispatchQueue.main.async {
                self.scanInProgress = false
                guard gen == self.scanGeneration else { return }   // superseded by stop()/newer scan
                let changed = found.count != self.entries.count
                    || zip(found, self.entries).contains(where: { $0.bundleID != $1.bundleID || $0.title != $1.title })
                self.entries = found
                if changed { self.notify() }
            }
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: .minimizedWindowsChanged, object: nil)
    }
}
