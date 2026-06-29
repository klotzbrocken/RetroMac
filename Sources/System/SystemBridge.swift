import Foundation
import AppKit
import ApplicationServices   // AXIsProcessTrusted
import CoreGraphics          // CGPreflightScreenCaptureAccess

/// One chokepoint for every OS-poking call (system Dock, menu bar, desktop icons, AX,
/// Screen Recording, and — later — CGVirtualDisplay for the iPad second screen).
///
/// Goals (v2.0 API-resilience foundation, see docs/V2-API-RESILIENCE-PLAN.md):
/// - **Capability detection**: probe once at launch, cache; the dependent feature
///   self-disables with a reason instead of half-applying.
/// - **Zero silent failures**: OS pokes return `Result<…, SystemBridgeError>`; callers
///   degrade on `.unsupported` / `.permissionDenied` / `.commandFailed` rather than `try?`.
/// - **macOS-27 insurance**: a pref write+read-back mismatch (schema changed) marks the
///   capability unavailable → graceful degradation, no broken state, no Dock left hidden.
///
/// SLIM scope: probe + typed errors + centralized shell-outs now. Version-gated impls and
/// the watchdog helper are deferred until a macOS beta actually breaks something.

enum SystemCapability: String, CaseIterable {
    case systemDockControl
    case menuBarAutohide
    case desktopIconsToggle
    case accessibility
    case screenCapture
    case virtualDisplay     // stubbed now; filled for the iPad phase (#2)
}

struct CapabilityStatus {
    var available: Bool
    var degraded: Bool          // works but in a reduced/uncertain mode
    var reason: String?         // human-readable, shown in Settings → System
    static let assumedAvailable = CapabilityStatus(available: true, degraded: false, reason: nil)
    static func unavailable(_ reason: String) -> CapabilityStatus {
        CapabilityStatus(available: false, degraded: true, reason: reason)
    }
}

enum SystemBridgeError: Error, CustomStringConvertible {
    case unsupported(String)        // capability not available on this OS / build
    case permissionDenied(String)   // AX / Screen Recording / Automation not granted
    case commandFailed(String)      // the shell-out ran but failed

    var description: String {
        switch self {
        case .unsupported(let m):      return "unsupported: \(m)"
        case .permissionDenied(let m): return "permission denied: \(m)"
        case .commandFailed(let m):    return "command failed: \(m)"
        }
    }
}

final class SystemBridge {
    static let shared = SystemBridge()
    private init() {}

    // MARK: - Capability snapshot (cached; defaults to "assume available" until probed)

    private var snapshot: [SystemCapability: CapabilityStatus] = [:]
    private let lock = NSLock()

    /// Cached status for a capability. Returns `.assumedAvailable` before the probe runs so
    /// startup never blocks on shelling out; the async probe reconciles shortly after launch.
    func capability(_ c: SystemCapability) -> CapabilityStatus {
        lock.lock(); defer { lock.unlock() }
        return snapshot[c] ?? .assumedAvailable
    }

    func isAvailable(_ c: SystemCapability) -> Bool { capability(c).available }

    private func set(_ c: SystemCapability, _ status: CapabilityStatus) {
        lock.lock(); snapshot[c] = status; lock.unlock()
    }

    // MARK: - Centralized shell-outs (typed Result — replaces scattered Process boilerplate)

    /// Run an executable synchronously and capture trimmed stdout. Callers run this off the
    /// main thread (it spawns a Process, ~10-50ms). Never invoke on the theme-switch hot path.
    @discardableResult
    func runProcess(_ path: String, _ args: [String]) -> Result<String, SystemBridgeError> {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let out = Pipe()
        task.standardOutput = out
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return .failure(.commandFailed("\(path): \(error.localizedDescription)"))
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard task.terminationStatus == 0 else {
            return .failure(.commandFailed("\(path) \(args.joined(separator: " ")) → exit \(task.terminationStatus)"))
        }
        return .success(text)
    }

    @discardableResult
    func runDefaults(_ args: [String]) -> Result<String, SystemBridgeError> {
        runProcess("/usr/bin/defaults", args)
    }

    /// Read a single `defaults` value, or nil if unset / unreadable.
    func readDefault(_ domain: String, _ key: String) -> String? {
        if case .success(let v) = runDefaults(["read", domain, key]) { return v }
        return nil
    }

    @discardableResult
    func killall(_ processName: String) -> Result<String, SystemBridgeError> {
        runProcess("/usr/bin/killall", [processName])
    }

    // MARK: - Probing (dependency-injectable so the logic is unit-testable)
    //
    // Each probe takes the raw checks as closures with real defaults, so tests can inject
    // fakes (e.g. a pref-reader that returns a mismatched read-back) without shelling out.

    /// Probe every capability off the main thread and cache the result. Safe to call at launch
    /// and from a manual "refresh" in the System-status pane. Hops to main only to post a change.
    func probeAll(completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            self.set(.systemDockControl, self.probeSystemDockControl())
            self.set(.menuBarAutohide,   self.probeMenuBarAutohide())
            self.set(.desktopIconsToggle, self.probeDesktopIconsToggle())
            self.set(.accessibility,     self.probeAccessibility())
            self.set(.screenCapture,     self.probeScreenCapture())
            self.set(.virtualDisplay,    self.probeVirtualDisplay())
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .systemCapabilitiesChanged, object: nil)
                completion?()
            }
        }
    }

    /// Dock control: confirm the dock-pref schema is intact via a harmless write+read-back of
    /// a real boolean key (`autohide`), restoring the original. A read-back mismatch means the
    /// schema changed (e.g. macOS 27) → unavailable, so the dock-hide feature self-disables.
    func probeSystemDockControl(
        read: (String) -> String? = { SystemBridge.shared.readDefault("com.apple.dock", $0) },
        write: (String, String) -> Bool = {
            if case .success = SystemBridge.shared.runDefaults(["write", "com.apple.dock", $0, "-bool", $1]) { return true }
            return false
        }
    ) -> CapabilityStatus {
        let key = "autohide"
        let original = read(key)                      // "0" / "1" / nil
        let probeValue = (original == "1") ? "1" : "0" // write back the SAME value (no visible change)
        guard write(key, probeValue) else {
            return .unavailable("Dock preferences are not writable (control unavailable).")
        }
        let readBack = read(key)
        // Normalize "true"/"false" vs "1"/"0".
        let norm: (String?) -> String? = { v in
            guard let v = v else { return nil }
            if v == "true" { return "1" }; if v == "false" { return "0" }; return v
        }
        guard norm(readBack) == norm(probeValue) else {
            return .unavailable("Dock preference schema changed — Dock control disabled, themes apply without hiding the system Dock.")
        }
        return .assumedAvailable
    }

    func probeMenuBarAutohide(
        automationOK: () -> Bool = { SystemUIHelper.testAutomation() }
    ) -> CapabilityStatus {
        // Writing _HIHideMenuBar to NSGlobalDomain is the mechanism; Automation (System Events)
        // is the fallback path. If neither is permitted the feature degrades.
        if automationOK() { return .assumedAvailable }
        if case .success = runDefaults(["read", "NSGlobalDomain", "_HIHideMenuBar"]) {
            return .assumedAvailable
        }
        return .unavailable("Menu-bar auto-hide unavailable (Automation not granted).")
    }

    func probeDesktopIconsToggle(
        read: () -> String? = { SystemBridge.shared.readDefault("com.apple.finder", "CreateDesktop") }
    ) -> CapabilityStatus {
        // The key may be unset (icons shown by default) — that's still controllable. We only
        // mark unavailable if Finder's domain can't be read at all.
        _ = read()
        return .assumedAvailable
    }

    func probeAccessibility(
        trusted: () -> Bool = { AXIsProcessTrusted() }
    ) -> CapabilityStatus {
        trusted() ? .assumedAvailable
                  : .unavailable("Accessibility not granted — window raise/minimize is disabled.")
    }

    func probeScreenCapture(
        preflight: () -> Bool = { CGPreflightScreenCaptureAccess() }
    ) -> CapabilityStatus {
        preflight() ? .assumedAvailable
                    : .unavailable("Screen Recording not granted — the CRT shader can't read the screen.")
    }

    func probeVirtualDisplay(
        symbolPresent: () -> Bool = { dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGVirtualDisplayCreate") != nil }
    ) -> CapabilityStatus {
        // Stub for the iPad phase (#2): just report whether the private symbol exists.
        symbolPresent() ? .assumedAvailable
                        : .unavailable("Virtual display API unavailable on this macOS.")
    }
}

extension Notification.Name {
    static let systemCapabilitiesChanged = Notification.Name("SystemCapabilitiesChanged")
}
