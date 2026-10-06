import AppKit

/// "Rescue Desktop" (Lastenheft 3.0, RET-01 … RET-14): one action, reached by hotkey, the
/// flyout and the status menu, that takes away everything RetroMac puts on or over the desktop
/// and brings back windows nobody can reach. The user's settings stay: the theme can be turned
/// on again whenever they like (RET-05).
///
/// Built on what exists: the theme going off stops the title bars, whose `unshadeAll` puts every
/// rolled-up window back on the Accessibility queue — after any park still queued there, so a
/// roll-up just before cannot send a window away again (RET-A2) — and keeps a window that would
/// not move on record (RET-10). The wallpaper restore puts back the cursor, appearance, Terminal
/// profile and Finder tweaks with it. New here: the sweep for windows out of reach, the report,
/// and the state that keeps a launch from turning anything on (RET-14).
final class DesktopRescue {

    static let shared = DesktopRescue()

    /// Set from the moment a rescue starts until it has finished. Still set at launch means the
    /// last one never finished: nothing is turned on automatically, and the rescue runs again.
    static let pendingKey = "desktopRescuePending"
    static var pending: Bool {
        get { UserDefaults.standard.bool(forKey: pendingKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingKey) }
    }
    /// `--rescue-desktop` on the command line: the same, on request.
    static var requestedAtLaunch: Bool { CommandLine.arguments.contains("--rescue-desktop") }
    /// Whether the hotkey could be registered; false when another app holds the combination.
    static var hotkeyRegistered = true

    enum Status: String { case done = "✓", skipped = "–", failed = "✗", pending = "…" }
    struct Line: Equatable { var status: Status; var text: String }

    private(set) var isRunning = false
    private var lines: [Line] = []
    private var needsAccessibility = false
    private var panel: RescueReportPanel?

    func run() {
        // A second call while one runs shows that one, it does not start another (RET-03).
        if isRunning { panel?.present(); return }
        isRunning = true
        WindowSwitcher.shared.stop()   // the rescue comes first (SW-11)
        Self.pending = true
        lines = []
        needsAccessibility = false

        // What lies over the desktop or holds the input.
        ScreensaverController.shared.dismiss()
        ExposeController.shared.hide()
        DashboardController.shared.hide()
        if CrashDirector.shared.isStaging { CrashDirector.shared.abort(.themeStopped) }
        if SplashController.shared.isPresenting { SplashController.shared.dismiss() }

        // Theme, shader, Retro Mode and the desktop effects off. This also stops the title bars,
        // whose stop puts every rolled-up window back and restores the wallpaper, the cursor,
        // the appearance and the Finder tweaks from their snapshots.
        AppDelegate.shared?.rescueTurnEverythingOff()
        add(.done, "Theme, shader and desktop effects are off. Your settings are kept.")

        let stillRolledUp = TitleBarOverlayController.shadeRecordsOnFile
        add(stillRolledUp == 0 ? .done : .failed,
            stillRolledUp == 0 ? "Rolled-up windows are back in place."
                               : "\(stillRolledUp) rolled-up window(s) would not move. They stay on record for the next try.")

        // The rest of the system look, each from the backup RetroMac took when it changed it.
        SystemUIHelper.restoreIfNeeded()
        SystemUIHelper.restoreDesktopIconsIfNeeded()
        DockController.shared.restoreSystemDockIfNeeded()
        // The menu bar is checked, not assumed: a theme or the shortcut may have hidden it, and
        // macOS may not take the change (no Automation permission for System Events).
        switch AppDelegate.shared?.rescueShowMenuBar() {
        case true?: add(.done, "The menu bar shows again.")
        case false?: add(.failed, "The menu bar is still set to hide. Turn it off in System Settings ▸ Control Center ▸ Automatically hide and show the menu bar.")
        case nil: break
        }
        add(.done, "Dock and desktop icons are back as they were.")
        // macOS reports a new desktop picture a moment after it was set: asked at once, the
        // theme's still showed. Settled in finish().
        wallpaperLine = lines.count
        add(.pending, "Wallpaper…")
        add(CursorThemeManager.shared.isSupported ? .done : .skipped,
            CursorThemeManager.shared.isSupported ? "Cursor is the system's again."
                                                  : "Cursor: not touched (RetroMac cannot change cursors on this Mac).")

        // Windows out of reach: Accessibility only. Without it, the rest has still been done
        // and the report says what was not (RET-11).
        guard AXIsProcessTrusted() else {
            needsAccessibility = true
            add(.skipped, "Windows were not checked: RetroMac has no Accessibility permission.")
            finish()
            return
        }
        let sweepLine = lines.count
        add(.pending, "Looking for windows out of reach…")
        let screens = Self.quartzVisibleFrames()
        TitleBarOverlayController.axQueue.async {
            let result = Self.bringBackUnreachableWindows(screens: screens)
            DispatchQueue.main.async {
                self.lines[sweepLine] = Self.sweepLine(result)
                self.finish()
            }
        }
        // A hung app must not keep the report away: show what is known after five seconds,
        // the window line still running (RET-12).
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if self.isRunning { self.showReport(finished: false) }
        }
    }

    private func add(_ status: Status, _ text: String) { lines.append(Line(status: status, text: text)) }

    private var wallpaperLine = 0

    private func finish() {
        isRunning = false
        Self.pending = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.lines[self.wallpaperLine] = ThemeManager.shared.anyScreenShowsOwnWallpaper()
                ? Line(status: .failed, text: "Wallpaper: a RetroMac picture is still showing.")
                : Line(status: .done, text: "Wallpaper is your own again.")
            self.showReport(finished: true)
        }
    }

    private func showReport(finished: Bool) {
        if panel == nil { panel = RescueReportPanel() }
        panel?.update(lines: lines, finished: finished, needsAccessibility: needsAccessibility)
        panel?.present()
    }

    // MARK: - Windows out of reach

    struct SweepResult: Equatable { var moved = 0; var failed = 0 }

    static func sweepLine(_ r: SweepResult) -> Line {
        switch (r.moved, r.failed) {
        case (0, 0): return Line(status: .done, text: "Every window is within reach.")
        case (_, 0): return Line(status: .done, text: "\(r.moved) window(s) out of reach brought back on screen.")
        default:     return Line(status: .failed, text: "\(r.moved) window(s) brought back, \(r.failed) did not answer.")
        }
    }

    /// The usable part of each screen in Quartz coordinates (origin top-left of the main
    /// display, y downwards), main display first.
    static func quartzVisibleFrames() -> [CGRect] {
        guard let top = NSScreen.screens.first?.frame.maxY else { return [] }
        return NSScreen.screens.map { s in
            let f = s.visibleFrame
            return CGRect(x: f.minX, y: top - f.maxY, width: f.width, height: f.height)
        }
    }

    /// Whether a window's title bar can be grabbed: at least 120 × 24 points of its top strip
    /// on one screen, or as much as a smaller window has (RET-08). Quartz coordinates.
    static func titleBarReachable(_ window: CGRect, screens: [CGRect]) -> Bool {
        let needW = min(120, window.width), needH = min(24, window.height)
        let strip = CGRect(x: window.minX, y: window.minY, width: window.width, height: needH)
        return screens.contains { s in
            let i = strip.intersection(s)
            return !i.isNull && i.width >= needW && i.height >= needH
        }
    }

    /// Where an unreachable window goes: onto the screen nearest to it (the main display when
    /// none is near), its size kept, its top-left corner just far enough in that the title bar
    /// is whole on screen.
    static func rescueOrigin(for window: CGRect, screens: [CGRect]) -> CGPoint {
        guard let first = screens.first else { return window.origin }
        func distance(_ s: CGRect) -> CGFloat {
            let dx = max(s.minX - window.midX, 0, window.midX - s.maxX)
            let dy = max(s.minY - window.midY, 0, window.midY - s.maxY)
            return dx * dx + dy * dy
        }
        let s = screens.min { distance($0) < distance($1) } ?? first
        let x = min(max(window.minX, s.minX), s.maxX - min(window.width, s.width))
        let y = min(max(window.minY, s.minY), s.maxY - min(24, window.height))
        return CGPoint(x: x, y: y)
    }

    /// Ordinary windows of the current Space whose title bar is on no screen, moved back.
    /// Identity: the window number together with its owner, read again right before the move,
    /// so a number reused by another app's window is left alone (RET-06). Minimised windows and
    /// other Spaces are not in the list at all (RET-09). Accessibility queue only.
    static func bringBackUnreachableWindows(screens: [CGRect]) -> SweepResult {
        var result = SweepResult()
        // A hung app answers nothing for six seconds by default; half a second is enough (RET-12).
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        guard !screens.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return result }
        let me = ProcessInfo.processInfo.processIdentifier
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.width >= 40, bounds.height >= 24,
                  !titleBarReachable(bounds, screens: screens) else { continue }
            guard ownerPID(of: wid) == pid,
                  let w = TitleBarOverlayController.findAXWindow(wid, pid: pid),
                  TitleBarOverlayController.move(w, to: rescueOrigin(for: bounds, screens: screens))
            else { result.failed += 1; continue }
            result.moved += 1
        }
        return result
    }

    private static func ownerPID(of wid: CGWindowID) -> pid_t? {
        (CGWindowListCopyWindowInfo(.optionIncludingWindow, wid) as? [[String: Any]])?.first?[kCGWindowOwnerPID as String] as? pid_t
    }
}

/// The report: what was done, skipped, failed or is still running. Not modal, so a hung app
/// cannot hold the menu, and it updates when the last step comes in.
private final class RescueReportPanel: NSPanel {
    private let text = NSTextField(wrappingLabelWithString: "")
    private let accessibility = NSButton(title: "Open Accessibility Settings", target: nil, action: nil)

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 200),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "Rescue Desktop"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false   // a panel hides with the app; this one must stay until read
        level = .floating
        text.preferredMaxLayoutWidth = 400
        text.font = .systemFont(ofSize: 13)
        accessibility.target = self
        accessibility.action = #selector(openAccessibility)
        let ok = NSButton(title: "OK", target: self, action: #selector(dismiss))
        ok.keyEquivalent = "\r"
        let buttons = NSStackView(views: [accessibility, ok])
        let container = NSView()
        for v in [text, buttons] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(v) }
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            text.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            text.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            text.widthAnchor.constraint(equalToConstant: 400),
            buttons.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])
        contentView = container
    }

    func update(lines: [DesktopRescue.Line], finished: Bool, needsAccessibility: Bool) {
        let head = finished ? "Your desktop is back. Turn a theme on again whenever you like."
                            : "Still working on the windows — one app is slow to answer."
        text.stringValue = ([head, ""] + lines.map { "\($0.status.rawValue)  \($0.text)" }).joined(separator: "\n")
        accessibility.isHidden = !needsAccessibility
        setContentSize(contentView?.fittingSize ?? frame.size)
    }

    func present() {
        if !isVisible { center() }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    @objc private func dismiss() { orderOut(nil) }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
