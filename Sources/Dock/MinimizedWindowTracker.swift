import AppKit
import ApplicationServices

extension Notification.Name {
    static let minimizedWindowsChanged = Notification.Name("minimizedWindowsChanged")
}

/// Tracks minimized windows of regular apps via the Accessibility API so the themed dock
/// can show a tile for each (the system Dock is hidden, so minimized windows would
/// otherwise vanish into nowhere). Clicking a tile de-minimizes the window and activates
/// the app. Poll-based (1.5s) — AX miniaturize notifications would need one observer per
/// app; polling is simpler and plenty fast for a dock.
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
        var found: [Entry] = []
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bid = app.bundleIdentifier, bid != ownBundleID else { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
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
                    ?? app.localizedName ?? bid
                found.append(Entry(pid: app.processIdentifier, bundleID: bid, title: title, window: w))
            }
        }
        let changed = found.count != entries.count
            || zip(found, entries).contains(where: { $0.bundleID != $1.bundleID || $0.title != $1.title })
        entries = found
        if changed { notify() }
    }

    private func notify() {
        NotificationCenter.default.post(name: .minimizedWindowsChanged, object: nil)
    }
}
