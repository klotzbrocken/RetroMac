import AppKit

/// Puts the Mac's own Dock, menu bar, desktop icons, wallpaper, appearance, cursors, Terminal
/// profile and the theme's system defaults back when RetroMac ends without doing it
/// itself (a crash, Force Quit, `kill -9`). Until now only the next launch recovered them, so a
/// crash left the real Dock unreachable (autohide-delay 1 000 000) until RetroMac ran again.
/// A second copy of the binary, started at launch with `--watchdog <pid>`, waits for that process
/// to end and runs the same recovery the next launch would. After a normal quit (marked by
/// `markCleanExit`) there is nothing left to recover and it exits at once, before touching AppKit:
/// once the recovery has used NSWorkspace, Launch Services counts the watchdog as a running
/// RetroMac, and opening RetroMac again failed (-600) until it had finished.
enum SystemWatchdog {
    static let flag = "--watchdog"
    static let cleanExitKey = "watchdogCleanExitPID"

    /// Called at the end of a normal quit, once RetroMac has put everything back itself.
    static func markCleanExit(_ defaults: UserDefaults = .standard) {
        defaults.set(Int(getpid()), forKey: cleanExitKey)
        defaults.synchronize()   // the process ends right after; the watchdog reads it then
    }
    static func endedCleanly(_ pid: pid_t, _ defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: cleanExitKey) == Int(pid)
    }

    /// The process to watch, when this process was started as the watchdog.
    static func watchedPID(in arguments: [String] = CommandLine.arguments) -> pid_t? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count,
              let pid = pid_t(arguments[i + 1]), pid > 1 else { return nil }
        return pid
    }
    static var watchedPID: pid_t? { watchedPID() }

    /// Starts the watchdog for this process; it writes into this process's log.
    static func launch() {
        guard let exe = Bundle.main.executableURL else { return }
        let p = Process()
        p.executableURL = exe
        p.arguments = [flag, String(getpid())]
        do { try p.run() } catch { print("[Watchdog] could not start: \(error)") }
    }

    /// The watchdog's whole life.
    static func run(watching pid: pid_t) -> Never {
        // The inherited stdout/stderr are RetroMac's console pipe, gone with it: writing there
        // would raise SIGPIPE in the middle of the recovery. Write to the log file instead.
        signal(SIGPIPE, SIG_IGN)
        let log = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/RetroMac/retromac.log")
        freopen(log, "a", stdout); freopen(log, "a", stderr)
        setbuf(stdout, nil); setbuf(stderr, nil)
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { source.cancel(); recover(after: pid) }
        source.resume()
        if kill(pid, 0) != 0, errno == ESRCH { source.cancel(); recover(after: pid) }   // gone before the source was armed
        dispatchMain()
    }

    private static func recover(after pid: pid_t) -> Never {
        if endedCleanly(pid) { print("[Watchdog] RetroMac \(pid) quit normally"); exit(0) }
        // A RetroMac started again in the meantime recovers by itself and may already have hidden
        // the Dock again; the other build (release / dev) may be hiding it right now (the recovery
        // also acts on the Dock's own fingerprint, which either build leaves): leave it to them.
        let own = Bundle.main.bundleIdentifier ?? ""
        let again = NSWorkspace.shared.runningApplications.contains { app in
            guard app.processIdentifier != getpid(), app.processIdentifier != pid,
                  let id = app.bundleIdentifier, ["com.retromac.app", "com.retromac.app.dev"].contains(id) else { return false }
            return id == own || UserDefaults(suiteName: id)?.bool(forKey: "sysDockHidden") == true
        }
        if !again {
            SystemUIHelper.restoreIfNeeded()
            SystemUIHelper.restoreDesktopIconsIfNeeded()
            SystemTweaksAdapter.restoreIfNeeded(sync: true)
            // The theme's hidden menu bar: no launch recovery has it (the next start hides it again
            // anyway), so it is put back here as it was before RetroMac first changed it.
            if UserDefaults.standard.bool(forKey: "hideMenuBar") {
                let original = OriginalSettings.value("-g", "_HIHideMenuBar") ?? OriginalSettings.value("NSGlobalDomain", "_HIHideMenuBar")
                SystemUIHelper.setMenuBarAutoHide(((original ?? nil) as? Bool) ?? false)
            }
            AppDelegate.restoreRetroModeSystemUI()
            DockController.shared.restoreSystemDockIfNeeded()
            // The wallpaper goes through the Dock: only once it is back (as Rescue Desktop does).
            DockController.waitUntilRunning()
            ThemeManager.shared.restoreWallpapersIfNeeded()
            AppearanceAdapter.restoreIfNeeded()
            CursorThemeManager.shared.restoreIfNeeded()
            TerminalThemer.restoreIfNeeded()
        }
        print("[Watchdog] RetroMac \(pid) ended\(again ? "; another RetroMac has the Dock, nothing to do" : "")")
        // shortcut: the appearance and Terminal restores finish on a background queue with no
        // handle to wait on; 5 s is ample for their few `defaults` writes, and a cut-off one keeps
        // its snapshot for the next launch. The main thread sleeps rather than running its queue:
        // ThemeManager's screen and Space observers would otherwise put the theme's picture,
        // Terminal profile and accent straight back (they did in the first try).
        if !again { Thread.sleep(forTimeInterval: 5) }
        exit(0)
    }
}
