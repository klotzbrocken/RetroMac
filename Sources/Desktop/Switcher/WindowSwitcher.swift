import AppKit
import Carbon.HIToolbox

/// What each theme's era could do to change windows (Lastenheft 3.0, SW-01): one explicit entry
/// per theme id, with the mode, how sure the reference is and where it comes from. An app
/// switcher, a window switcher, an overview and a plain focus cycle are different things, and a
/// "Mac" or "Windows" family says nothing about which one an era had.
struct SwitcherCapability: Equatable {
    enum Mode: Equatable {
        case none
        /// Each press moves the focus straight to the next window; no panel (CDE's Alt+Tab).
        case focusCycle
        /// The overview RetroMac already draws (Exposé, Snow Leopard).
        case expose
        /// macOS's own Mission Control (Mountain Lion).
        case missionControl
        /// A panel of window icons chosen while the modifiers are held (Windows 95 … XP).
        case altTab
        /// Windows Flip, and Flip 3D on its own entry (Vista, 7).
        case flip
    }
    /// SW-02: a mode without a reference stays off until one is in.
    enum Reference: Equatable { case confirmed, documented, pending }

    let mode: Mode
    let reference: Reference
    let source: String
    /// What the switcher does here, for Settings ▸ Shortcuts.
    let summary: String

    var isAvailable: Bool { mode != .none && reference != .pending }

    static let version = 1
    static let unsupported = SwitcherCapability(mode: .none, reference: .documented, source: "", summary: "This theme has no window switcher.")

    private static func none(_ why: String) -> SwitcherCapability {
        SwitcherCapability(mode: .none, reference: .documented, source: "Lastenheft 3.0, 8.2", summary: why)
    }
    private static func pending(_ mode: Mode, _ what: String) -> SwitcherCapability {
        SwitcherCapability(mode: mode, reference: .pending, source: "Lastenheft 3.0, 8.2",
                           summary: "\(what) comes once its reference screenshots are in.")
    }

    /// The release matrix of Lastenheft 3.0, 8.2.
    static let matrix: [String: SwitcherCapability] = [
        "com.retromac.sun.solaris8-cde": SwitcherCapability(
            mode: .focusCycle, reference: .documented, source: "Solaris CDE User's Guide 806-1360 [S4]",
            summary: "Each press moves to the next window, Shift to the one before, as CDE's Alt+Tab did. No panel."),
        "com.retromac.apple.snow-leopard": SwitcherCapability(
            mode: .expose, reference: .documented, source: "Exposé since Mac OS X 10.3 [A1]",
            summary: "Opens Exposé with every window."),
        "com.retromac.apple.mountain-lion": SwitcherCapability(
            mode: .missionControl, reference: .documented, source: "Mission Control since Mac OS X 10.7",
            summary: "Opens Mission Control."),
        "com.retromac.microsoft.windows95": pending(.altTab, "The Windows 95 Alt+Tab panel"),
        "com.retromac.microsoft.windows98": pending(.altTab, "The Windows 98 Alt+Tab panel"),
        "com.retromac.microsoft.windowsme": pending(.altTab, "The Windows Me Alt+Tab panel"),
        "com.retromac.microsoft.windowsxp": pending(.altTab, "The Windows XP Alt+Tab panel"),
        "com.retromac.microsoft.windowsvista": pending(.flip, "Windows Flip and Flip 3D"),
        "com.retromac.microsoft.windows7": pending(.flip, "Windows 7's Flip and Flip 3D"),
        "com.retromac.apple.aqua-cheetah": none("Mac OS X 10.0 had neither Exposé nor a Command-Tab panel."),
        "com.retromac.apple.system6": none("System 6 keeps its application menu."),
        "com.retromac.apple.system7-authentic": none("System 7 keeps its application menu."),
        "com.retromac.apple.macos9": none("Mac OS 9 keeps its application menu."),
        "com.retromac.apple.macos9-authentic": none("Mac OS 9 keeps its application menu."),
        "com.retromac.microsoft.windows31": none("Windows 3.1 keeps the Task List of its Program Manager."),
        "com.retromac.be.beos5": none("BeOS keeps its Deskbar."),
        "com.retromac.next.nextstep": none("NeXTSTEP keeps its dock."),
        "com.retromac.ibm.os2warp4": none("OS/2 keeps its WarpCenter."),
        "com.retromac.sgi.irix": none("IRIX keeps its Toolchest."),
        "com.retromac.amiga.workbench41": none("Workbench keeps its screens."),
        "com.retromac.tv.futurama": none("A made-up theme gets no made-up switcher."),
        "com.retromac.personal.maiks-favourite": none("A made-up theme gets no made-up switcher."),
        "com.retromac.personal.maiks-favourite-2": none("A made-up theme gets no made-up switcher."),
    ]

    /// SW-A1: a theme without an entry starts no switcher.
    static func forTheme(_ id: String?) -> SwitcherCapability { id.flatMap { matrix[$0] } ?? unsupported }
}

/// The historic window switcher (Lastenheft 3.0, 8). ⌃⌥Tab by default, Shift the other way. Its
/// hotkeys exist only while the active theme has a switcher and it is on for that theme, so a
/// switcher that is off takes no key (SW-04). Exposé and the switcher never run together, and
/// Rescue Desktop stops it (SW-11).
final class WindowSwitcher {
    static let shared = WindowSwitcher()

    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private static let signature = OSType(0x52535754)   // "RSWT"

    private var capability: SwitcherCapability {
        guard AppSettings.shared.dockEnabled else { return .unsupported }
        return SwitcherCapability.forTheme(ThemeManager.shared.activeTheme?.config.id)
    }

    static var isOnForActiveTheme: Bool {
        guard let id = ThemeManager.shared.activeTheme?.config.id else { return false }
        return !AppSettings.shared.switcherOffThemes.contains(id)
    }

    /// Takes the hotkeys when the theme has a switcher and it is on, lets them go otherwise.
    func update() {
        stop()
        let s = AppSettings.shared
        guard capability.isAvailable, Self.isOnForActiveTheme, s.switcherHotkeyModifiers != 0 else { return }
        installHandler()
        for (id, mods) in [(UInt32(1), s.switcherHotkeyModifiers), (2, s.switcherHotkeyModifiers | UInt32(shiftKey))] {
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(s.switcherHotkeyCode, mods, EventHotKeyID(signature: Self.signature, id: id),
                                   GetApplicationEventTarget(), 0, &ref) == noErr, let ref { hotKeys.append(ref) }
        }
    }

    /// Lets every key go and ends a cycle in progress (theme off, rescue, error).
    func stop() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys = []
        endCycle()
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == WindowSwitcher.signature else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { WindowSwitcher.shared.fire(backward: id.id == 2) }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    private func fire(backward: Bool) {
        guard !ExposeController.shared.isOpen || capability.mode == .expose else { return }   // SW-11
        switch capability.mode {
        case .focusCycle: step(backward: backward)
        case .expose: ExposeController.shared.toggle(.allWindows)
        case .missionControl: CDEActions.missionControl()
        case .none, .altTab, .flip: break
        }
    }

    // MARK: Focus cycle (CDE)

    /// A window the cycle can move to: the WindowServer's id and its owner.
    struct Target: Equatable { let wid: CGWindowID; let pid: pid_t }

    private var cycle: [Target] = []
    private var index = 0
    private var modifierWatch: Timer?

    /// The windows in front-to-back order, as the WindowServer stacks them: ordinary windows of
    /// regular apps, never RetroMac's own (bars, panels, overlays) and nothing tiny (SW-07).
    static func cycleTargets() -> [Target] {
        let own = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let wid = w[kCGWindowNumber as String] as? CGWindowID,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat], (b["Width"] ?? 0) >= 60, (b["Height"] ?? 0) >= 40,
                  NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular else { return nil }
            return Target(wid: wid, pid: pid)
        }
    }

    /// The next index of a cycle over `count` windows, round in either direction.
    static func nextIndex(_ i: Int, count: Int, backward: Bool) -> Int {
        guard count > 0 else { return 0 }
        return ((backward ? i - 1 : i + 1) % count + count) % count
    }

    /// One press: the list is taken at the first press and kept while the modifiers are held
    /// (SW-06), so repeated presses walk through every window; a window that has gone is dropped.
    private func step(backward: Bool) {
        if modifierWatch == nil {
            cycle = Self.cycleTargets()
            index = 0
            let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                if NSEvent.modifierFlags.intersection([.control, .option, .command]).isEmpty { self?.endCycle() }
            }
            RunLoop.main.add(t, forMode: .common)
            modifierWatch = t
        }
        while cycle.count > 1 {
            index = Self.nextIndex(index, count: cycle.count, backward: backward)
            let t = cycle[index]
            if focus(t) { return }
            cycle.remove(at: index)
            if index >= cycle.count { index = 0 }
        }
    }

    private func endCycle() {
        modifierWatch?.invalidate(); modifierWatch = nil
        cycle = []
    }

    /// Raise the window and give its app the focus. False when the window is no longer there.
    private func focus(_ t: Target) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: t.pid), !app.isTerminated,
              let w = TitleBarOverlayController.findAXWindow(t.wid, pid: t.pid) else { return false }
        AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(w, kAXRaiseAction as CFString)
        app.activate(options: [.activateIgnoringOtherApps])
        return true
    }
}
