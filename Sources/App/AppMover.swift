import AppKit

/// Started from the DMG or from Downloads, RetroMac offers to move itself to Applications, as
/// many Mac apps do. A user who could not drag it across ran it from the mounted DMG: no menu-bar
/// icon they could find, the app gone from Finder's search once the DMG was ejected, and no way
/// to turn it off.
enum AppMover {
    /// Whether a bundle at `path` is somewhere it should not run from: a disk image, Downloads,
    /// or Gatekeeper's translocated copy of either.
    static func needsMove(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        if path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/") { return false }
        return path.hasPrefix("/Volumes/") || path.hasPrefix(home + "/Downloads/")
            || path.contains("/AppTranslocation/")
    }

    /// Once per launch, early, before anything is themed.
    static func offerIfNeeded() {
        let bundle = Bundle.main.bundleURL
        guard needsMove(bundle.path), let source = originalURL(of: bundle) else { return }
        let target = URL(fileURLWithPath: "/Applications").appendingPathComponent(bundle.lastPathComponent)
        let alert = NSAlert()
        alert.messageText = "Move RetroMac to Applications?"
        alert.informativeText = "RetroMac is running from \(source.deletingLastPathComponent().path.hasPrefix("/Volumes/") ? "the disk image" : "your Downloads folder"). In Applications it stays put, starts again after an eject or a restart, and is easy to find and remove."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // An older RetroMac still running from Applications quits first, or two would run.
        let me = ProcessInfo.processInfo.processIdentifier
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where other.processIdentifier != me { other.terminate() }
        do {
            // An older copy goes to the Trash, not into nothing.
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.trashItem(at: target, resultingItemURL: nil)
            }
            // ditto keeps the signature, the notarization ticket and the extended attributes.
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = [source.path, target.path]
            try ditto.run(); ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            let fail = NSAlert()
            fail.messageText = "RetroMac could not be moved"
            fail.informativeText = "Drag it from the disk image into Applications yourself. (\(error.localizedDescription))"
            fail.runModal()
            return
        }
        // The copy in Applications takes over; this one, on the disk image, goes.
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: target, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// The bundle's real place: Gatekeeper runs a quarantined app from a random read-only copy
    /// (App Translocation), and only Security knows where it came from.
    private static func originalURL(of url: URL) -> URL? {
        guard url.path.contains("/AppTranslocation/") else { return url }
        typealias Original = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let sym = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        let original = unsafeBitCast(sym, to: Original.self)
        return original(url as CFURL, nil)?.takeRetainedValue() as URL?
    }
}
