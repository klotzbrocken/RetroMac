import AppKit

/// Puts the Mac's own Dock, menu bar and desktop icons back when RetroMac ends without doing it
/// itself (a crash, Force Quit, `kill -9`). Until now only the next launch recovered them, so a
/// crash left the real Dock unreachable (autohide-delay 1 000 000) until RetroMac ran again.
/// A second copy of the binary, started at launch with `--watchdog <pid>`, waits for that process
/// to end and runs the same recovery the next launch would. After a normal quit there is nothing
/// left to recover and it just exits.
enum SystemWatchdog {
    static let flag = "--watchdog"

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
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { recover(after: pid) }
        source.resume()
        if kill(pid, 0) != 0, errno == ESRCH { recover(after: pid) }   // gone before the source was armed
        dispatchMain()
    }

    private static func recover(after pid: pid_t) -> Never {
        // A RetroMac started again in the meantime, or the other build (release / dev) still
        // running, has the Dock hidden on purpose (the recovery also acts on the Dock's own
        // fingerprint, which either build leaves): leave it to that one.
        let ids: Set<String> = ["com.retromac.app", "com.retromac.app.dev"]
        let again = NSWorkspace.shared.runningApplications.contains {
            ids.contains($0.bundleIdentifier ?? "") && $0.processIdentifier != getpid() && $0.processIdentifier != pid
        }
        if !again {
            SystemUIHelper.restoreIfNeeded()
            SystemUIHelper.restoreDesktopIconsIfNeeded()
            AppDelegate.restoreRetroModeSystemUI()
            DockController.shared.restoreSystemDockIfNeeded()
        }
        print("[Watchdog] RetroMac \(pid) ended\(again ? "; another RetroMac is running, nothing to do" : "")")
        exit(0)
    }
}
