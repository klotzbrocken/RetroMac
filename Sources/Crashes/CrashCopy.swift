import Foundation

/// A seedable generator, so a scenario built in a test is the same scenario every time.
/// SplitMix64 — small, and good enough to pick between six stop codes.
struct CrashRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64 = 0x9E3779B97F4A7C15) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// The words on the screens, and the parts of them that vary.
///
/// Everything here is the historical wording, transcribed rather than paraphrased — that is the
/// whole point of the feature. The only invention is `RETROMAC.SYS`, which is deliberately the
/// most frequent driver name in the XP screen: a person who reads it knows within one line that
/// they are looking at a joke, and a person who does not read it never learns anything false
/// about their own machine.
enum CrashCopy {

    // MARK: - Random parts

    /// Exceptions people really saw: page fault, general protection fault, invalid opcode.
    static let exceptions = ["0E", "0D", "06"]
    /// Virtual device drivers, as they were named in the 9x kernel.
    static let vxds = ["VMM(01)", "VWIN32(05)", "IOS(04)", "IFSMGR(01)", "VFAT(04)"]
    /// The modules a 9x invalid page fault liked to blame.
    static let modules = ["KERNEL32.DLL", "USER32.DLL", "GDI32.DLL", "SHELL32.DLL", "MSGSRV32.EXE"]
    /// The programs that did the faulting.
    static let culprits = ["EXPLORER", "IEXPLORE", "WINWORD", "NOTEPAD", "SNDREC32"]

    /// Stop code name and number, paired the way Windows paired them.
    static let stopCodes: [(name: String, code: String)] = [
        ("IRQL_NOT_LESS_OR_EQUAL",        "0x0000000A"),
        ("PAGE_FAULT_IN_NONPAGED_AREA",   "0x00000050"),
        ("KMODE_EXCEPTION_NOT_HANDLED",   "0x0000001E"),
        ("UNEXPECTED_KERNEL_MODE_TRAP",   "0x0000007F"),
        ("INACCESSIBLE_BOOT_DEVICE",      "0x0000007B"),
        ("BAD_POOL_CALLER",               "0x000000C2"),
    ]
    /// Drivers of the period, plus ours. `RETROMAC.SYS` is weighted in by appearing twice.
    static let drivers = ["RETROMAC.SYS", "RETROMAC.SYS", "win32k.sys", "atapi.sys", "nv4_disp.dll", "SPCMDCON.SYS"]

    static func hex(_ digits: Int, using rng: inout CrashRNG) -> String {
        let chars = "0123456789ABCDEF"
        return String((0..<digits).map { _ in chars.randomElement(using: &rng)! })
    }

    static func pick(_ list: [String], using rng: inout CrashRNG) -> String {
        list.randomElement(using: &rng) ?? list[0]
    }

    /// Same, for anything else worth varying — pairs of names, whole message sets.
    static func pick<T>(_ list: [T], using rng: inout CrashRNG) -> T {
        list.randomElement(using: &rng) ?? list[0]
    }

    // MARK: - Windows 9x, the screen everyone remembers

    /// The exact wording of the Windows 9x general fault screen. Left margin and the plaque at
    /// the top are the original's; only the error triple changes.
    static func win9xGeneralFault(using rng: inout CrashRNG) -> TextScreen {
        let code = "\(pick(exceptions, using: &rng)) : \(hex(4, using: &rng)) : \(hex(8, using: &rng))"
        return TextScreen(grid: .vga80x25, topRow: 6, leftColumn: 5, lines: [
            .inverted(" Windows "),
            .blank,
            .text("An error has occurred. To continue:"),
            .blank,
            .text("Press Enter to return to Windows, or"),
            .blank,
            .text("Press CTRL+ALT+DEL to restart your computer. If you do this,"),
            .text("you will lose any unsaved information in all open applications."),
            .blank,
            .text("Error: \(code)"),
            .blank,
            .blank,
            .centred("Press any key to continue _"),
        ])
    }

    /// The other 9x wording: a fatal exception in a virtual device driver.
    static func win9xFatalException(using rng: inout CrashRNG) -> TextScreen {
        let ex = pick(exceptions, using: &rng)
        let vxd = pick(vxds, using: &rng)
        let seg = "0028:C\(hex(6, using: &rng))"
        return TextScreen(grid: .vga80x25, topRow: 5, leftColumn: 3, lines: [
            .text("A fatal exception \(ex) has occurred at \(seg) in VXD \(vxd) +"),
            .text("\(hex(8, using: &rng)). The current application will be terminated."),
            .blank,
            .text("*  Press any key to terminate the current application."),
            .text("*  Press CTRL+ALT+DEL again to restart your computer. You will"),
            .text("   lose any unsaved information in all open applications."),
            .blank,
            .blank,
            .centred("Press any key to continue _"),
        ])
    }

    /// Windows Me and 98 showed this one while starting up, not while running — which is exactly
    /// why it is the one that made people reach for the power switch.
    static func winMeProtectionError(using rng: inout CrashRNG) -> TextScreen {
        let device = pick(["IOS", "VFAT", "VCACHE", "NDIS"], using: &rng)
        return TextScreen(grid: .vga80x25, topRow: 8, leftColumn: 3, lines: [
            .text("While initializing device \(device):"),
            .blank,
            .text("Windows protection error.  You need to restart your computer."),
            .blank,
            .blank,
            .centred("Press any key to continue _"),
        ])
    }

    /// The 9x invalid page fault, which arrived as a window on a working desktop.
    /// The Visual C++ runtime error — the other dialog everyone saw, and the reason so many
    /// screenshots of it exist: it named the executable, in full, with its path.
    static func runtimeError(style: ErrorDialog.Style, using rng: inout CrashRNG) -> ErrorDialog {
        let programs = [
            "C:\\Program Files\\Microsoft Visual Studio\\VSS\\win32\\SSADMIN.EXE",
            "C:\\Program Files\\Internet Explorer\\IEXPLORE.EXE",
            "C:\\WINDOWS\\Explorer.EXE",
            "C:\\Program Files\\Windows Media Player\\wmplayer.exe"]
        let path = pick(programs, using: &rng)
        let shown = path.count > 46 ? "\u{2026}" + String(path.suffix(44)) : path
        return ErrorDialog(
            title: "Microsoft Visual C++ Runtime Library",
            body: ["Runtime Error!",
                   "",
                   "Program: \(shown)",
                   "",
                   "This application has requested the Runtime to terminate it in an",
                   "unusual way. Please contact the application's support team for",
                   "more information."],
            buttons: ["OK"],
            restartButton: nil,
            style: style,
            icon: style == .win9x ? .error9x : .errorXP,
            escalatesToBlueScreen: true)
    }

    /// Norton AntiVirus on Windows 9x, in the shape it had: a triangle, four fields with their
    /// values in a column, and one button.
    static func nortonVirusFound(using rng: inout CrashRNG) -> ErrorDialog {
        let viruses = ["W95.CIH", "W32.Klez.H@mm", "W95.Hybris.gen", "Happy99.Worm", "W32.Magistr"]
        let files = ["R:\\bo2k_1.0_intl.exe", "C:\\WINDOWS\\SYSTEM\\MSCONF.EXE",
                     "A:\\SETUP.EXE", "C:\\WINDOWS\\TEMP\\HAPPY99.EXE"]
        return ErrorDialog(
            title: "Norton AntiVirus",
            body: ["Norton AntiVirus has detected the \(pick(viruses, using: &rng)) virus in:",
                   "",
                   "File Name:        \(pick(files, using: &rng))",
                   "Domain Name:      ********",
                   "System Name:      ****",
                   "User Name:        ****",
                   "",
                   "Access to the file was denied."],
            buttons: ["OK"],
            restartButton: nil,
            style: .win9x,
            icon: .warning)
    }

    /// Symantec's XP-era notification: a toolbar, a scrolling report of the find, and a status
    /// strip counting the notifications.
    static func symantecVirusFound(using rng: inout CrashRNG) -> ErrorDialog {
        let threats = ["W32.Netsky.P@mm!enc", "W32.Beagle.AV@mm", "Trojan.Vundo",
                       "W32.Blaster.Worm", "Backdoor.Sdbot"]
        let users = ["jzawodn", "Administrator", "hgriffith", "mklotz"]
        let user = pick(users, using: &rng)
        return ErrorDialog(
            title: "Symantec AntiVirus Notification",
            body: [],
            buttons: [],
            restartButton: nil,
            style: .winXP,
            icon: .warning,
            report: ["Scan type:  Auto-Protect Scan",
                     "Event:  Threat Found!",
                     "Threat:  \(pick(threats, using: &rng))",
                     "File:  C:\\Documents and Settings\\\(user)\\Application Data\\Thunderbird",
                     "Location:  Quarantine",
                     "Computer:  \(user.uppercased())",
                     "User:  \(user)",
                     "Action taken:  Quarantine succeeded : Access denied",
                     "Date found:  Sunday, January 16, 2005  3:43:12 AM"],
            statusBar: ("Total Notifications: 1", "Currently displayed: 1"))
    }

    static func win9xIllegalOperationVaried(using rng: inout CrashRNG) -> ErrorDialog {
        let pair = win9xFaultingPair(using: &rng)
        let addr = "0\(hex(3, using: &rng)):bf\(hex(6, using: &rng))".lowercased()
        return ErrorDialog(
            title: pair.app,
            body: ["This program has performed an illegal operation",
                   "and will be shut down.",
                   "",
                   "If the problem persists, contact the program",
                   "vendor.",
                   "",
                   "\(pair.app) caused an invalid page fault in",
                   "module \(pair.module) at \(addr)."],
            buttons: ["Close", "Debug", "Details >>"],
            restartButton: nil,
            style: .win9x,
            icon: .error9x,
            buttonLayout: .rightColumn,
            escalatesToBlueScreen: true)
    }

    static func win9xIllegalOperation(using rng: inout CrashRNG) -> ErrorDialog {
        let app = pick(culprits, using: &rng)
        let module = pick(modules, using: &rng)
        let addr = "0\(hex(3, using: &rng)):bf\(hex(6, using: &rng))"
        return ErrorDialog(
            title: "\(app)",
            body: ["This program has performed an illegal operation",
                   "and will be shut down.",
                   "",
                   "If the problem persists, contact the program",
                   "vendor.",
                   "",
                   "\(app) caused an invalid page fault in",
                   "module \(module) at \(addr)."],
            buttons: ["Close", "Details >>"],
            restartButton: nil)
    }

    // MARK: - Windows XP and 7

    /// The NT Stop screen. Head and body are fixed — that block of advice is the same on every
    /// Windows from 2000 to 7 — and the technical lines carry the variable part.
    static func ntStopScreen(using rng: inout CrashRNG) -> TextScreen {
        let stop = stopCodes.randomElement(using: &rng) ?? stopCodes[0]
        let driver = pick(drivers, using: &rng)
        let base = "F8A\(hex(2, using: &rng))000"
        let addr = "F8A\(hex(2, using: &rng))\(hex(3, using: &rng))"
        let args = "(0x\(hex(8, using: &rng)),0x0000000\(Int.random(in: 0...2, using: &rng)),0x00000001,0x\(hex(8, using: &rng)))"
        return TextScreen(grid: .vga80x30, topRow: 1, leftColumn: 2, lines: [
            .text("A problem has been detected and Windows has been shut down to prevent damage"),
            .text("to your computer."),
            .blank,
            .text("The problem seems to be caused by the following file: \(driver)"),
            .blank,
            .text(stop.name),
            .blank,
            .text("If this is the first time you've seen this Stop error screen,"),
            .text("restart your computer. If this screen appears again, follow"),
            .text("these steps:"),
            .blank,
            .text("Check to make sure any new hardware or software is properly installed."),
            .text("If this is a new installation, ask your hardware or software manufacturer"),
            .text("for any Windows updates you might need."),
            .blank,
            .text("If problems continue, disable or remove any newly installed hardware"),
            .text("or software. Disable BIOS memory options such as caching or shadowing."),
            .text("If you need to use Safe Mode to remove or disable components, restart"),
            .text("your computer, press F8 to select Advanced Startup Options, and then"),
            .text("select Safe Mode."),
            .blank,
            .text("Technical information:"),
            .blank,
            .text("*** STOP: \(stop.code) \(args)"),
            .blank,
            .text("***  \(driver) - Address \(addr) base at \(base), DateStamp 4a5bc9c1"),
        ], palette: .nt)
    }

    /// The 9x "System is busy" screen — the one that appeared on the first Ctrl+Alt+Delete and
    /// asked whether you really meant it.
    static func win9xSystemBusy() -> TextScreen {
        TextScreen(grid: .vga80x25, topRow: 7, leftColumn: 5, lines: [
            .inverted(" Windows "),
            .blank,
            .text("The system is busy."),
            .blank,
            .text("Press any key to return to Windows, or press CTRL+ALT+DEL"),
            .text("again to restart your computer. You will lose any unsaved"),
            .text("information in all applications."),
            .blank,
            .blank,
            .centred("Press any key to continue _"),
        ])
    }

    /// The programs that fell over most often, and the library each one blamed. All of these were
    /// everyday sights on a 9x machine.
    static func win9xFaultingPair(using rng: inout CrashRNG) -> (app: String, module: String) {
        let pairs = [("EXPLORER", "KERNEL32.DLL"), ("EXPLORER", "SHELL32.DLL"),
                     ("RUNDLL32", "USER32.DLL"),  ("MSGSRV32", "KRNL386.EXE"),
                     ("IEXPLORE", "MSHTML.DLL"),  ("NOTEPAD", "COMDLG32.DLL"),
                     ("SNDREC32", "MMSYSTEM.DLL")]
        return pick(pairs, using: &rng)
    }

    /// XP's "has encountered a problem and needs to close" — the error-reporting dialog, and
    /// almost certainly the most-seen application failure of that decade.
    static func xpApplicationError(using rng: inout CrashRNG) -> ErrorDialog {
        let apps = ["Internet Explorer", "Windows Explorer", "Windows Media Player",
                    "Microsoft Word", "Notepad", "Outlook Express"]
        let app = pick(apps, using: &rng)
        return ErrorDialog(
            title: app,
            body: ["\(app) has encountered a problem and needs to",
                   "close.  We are sorry for the inconvenience.",
                   "",
                   "If you were in the middle of something, the information",
                   "you were working on might be lost."],
            buttons: ["Send Error Report", "Don't Send"],
            restartButton: nil,
            style: .winXP)
    }

    /// Windows 7 changed the wording: a program no longer "encountered a problem", it "stopped
    /// working", and the dialog offered to look for an answer online.
    static func win7ApplicationError(using rng: inout CrashRNG) -> ErrorDialog {
        let apps = ["Windows Explorer", "Internet Explorer", "Windows Media Player",
                    "Notepad", "Calculator"]
        let app = pick(apps, using: &rng)
        return ErrorDialog(
            title: "\(app) has stopped working",
            body: ["Windows is checking for a solution to the problem\u{2026}",
                   "",
                   "A problem caused the program to stop working correctly.",
                   "Windows will close the program and notify you if a",
                   "solution is available."],
            buttons: ["Close the program", "Debug"],
            restartButton: nil,
            style: .win7)
    }

    // MARK: - Macintosh

    /// The System 6 system error: a bomb, one sentence, and two buttons of which one was always
    /// greyed out. The ID number was a resource code nobody outside Apple could look up.
    /// The faults the bomb reported. Both spellings are period: early systems named the 68k
    /// exception, later ones printed the numbered "error type" the Finder had turned it into.
    private static let macFaults = ["Address Error", "Bus Error", "Illegal Instruction",
                                    "Division by Zero", "Unimplemented Trap",
                                    "error type 1", "error type 2", "error type 10",
                                    "error type 11"]
    /// Whatever was unlucky enough to be running.
    private static let macApps = ["Finder", "SimpleText", "TeachText", "Sherlock",
                                  "AppleWorks", "Netscape Navigator", "QuickTime Player"]

    static func system6Bomb(using rng: inout CrashRNG) -> MacAlert {
        let ids = ["01", "02", "03", "10", "11", "12", "25", "28"]
        return MacAlert(style: .system6,
                        title: nil,
                        lines: ["Sorry, a system error occurred."],
                        buttons: ["Restart", "Resume"],
                        idCode: "ID = \(pick(ids, using: &rng))",
                        restartButton: "Restart")
    }

    /// The Mac OS 9 bomb in its other shape: the program that died, then the fault, then the
    /// single button. Same alert, different wording between system versions.
    static func macOS9BombNamed(using rng: inout CrashRNG) -> MacAlert {
        MacAlert(style: .platinum,
                 title: nil,
                 // No leading spaces to indent with: the face is proportional, so a run of
                 // them is an arbitrary width, and the renderer already puts every line on one
                 // left margin beside the bomb. They were what pushed the fault line out of line
                 // with the two around it.
                 lines: ["Sorry, a system error occurred.",
                         "",
                         pick(macApps, using: &rng),
                         pick(macFaults, using: &rng)],
                 buttons: ["Restart"],
                 idCode: nil,
                 restartButton: "Restart")
    }

    /// Not every fault took the machine with it. This alert is the reason a classic Mac session
    /// could survive an afternoon: one program died, the rest carried on.
    static func macApplicationQuit(style: MacAlert.Style, using rng: inout CrashRNG) -> MacAlert {
        let types = ["1", "2", "3", "10", "11", "28"]
        let app = pick(macApps, using: &rng)
        return MacAlert(style: style,
                        title: nil,
                        lines: ["The application \u{201C}\(app)\u{201D} has unexpectedly quit,",
                                "because an error of type \(pick(types, using: &rng)) occurred."],
                        buttons: ["OK"],
                        icon: .caution,
                        idCode: nil,
                        restartButton: nil)
    }

    /// Mac OS X's version of the same news, with the sentence that made it bearable.
    static func aquaApplicationQuit(using rng: inout CrashRNG) -> ErrorDialog {
        let apps = ["Safari", "Mail", "iTunes", "Finder", "Preview", "iPhoto"]
        let app = pick(apps, using: &rng)
        return ErrorDialog(
            title: app,
            body: ["The application \(app) has unexpectedly quit.",
                   "",
                   "The system and other applications have not been affected."],
            buttons: ["Close", "Report\u{2026}", "Reopen"],
            restartButton: nil,
            style: .aqua)
    }

    /// Mac OS 9 kept the bomb but started naming the fault, and suggested the one remedy of the
    /// era: hold Shift on the way up and start without extensions.
    static func macOS9Bomb(using rng: inout CrashRNG) -> MacAlert {
        let faults = ["bus error", "address error", "illegal instruction",
                      "privilege violation", "Type 11 error"]
        return MacAlert(style: .platinum,
                        title: nil,
                        lines: ["Sorry, a system error occurred.",
                                "",
                                pick(faults, using: &rng),
                                "",
                                "To temporarily turn off extensions, restart and",
                                "hold down the shift key."],
                        buttons: ["Restart"],
                        idCode: nil,
                        restartButton: "Restart")
    }

    /// Mac OS X 10.0 and 10.1 dropped to a text console. The grey curtain came later.
    static func aquaPanicConsole(using rng: inout CrashRNG) -> TextScreen {
        let addr = hex(8, using: &rng)
        return TextScreen(grid: .vga80x30, topRow: 1, leftColumn: 0,
                          lines: [
                            .text("panic(cpu 0): Unresolved kernel trap (number 4), registers:"),
                            .blank,
                            .text("CR0: 0x8001003b  CR2: 0x0\(addr)  CR3: 0x01a\(hex(5, using: &rng))  CR4: 0x00000660"),
                            .text("EAX: 0x00000000  EBX: 0x0\(hex(7, using: &rng))  ECX: 0x00000001  EDX: 0x00000000"),
                            .text("ESP: 0x0\(hex(7, using: &rng))  EBP: 0x0\(hex(7, using: &rng))  ESI: 0x00000000  EDI: 0x00000000"),
                            .blank,
                            .text("Backtrace, Format - Frame : Return Address (4 potential args on stack)"),
                            .text("0x0\(hex(7, using: &rng)) : 0x1\(hex(5, using: &rng)) (0x456e10 0x1 0x2 0x0)"),
                            .text("0x0\(hex(7, using: &rng)) : 0x1\(hex(5, using: &rng)) (0x456e10 0x0 0x0 0x0)"),
                            .blank,
                            .text("Kernel version:"),
                            .text("Darwin Kernel Version 1.4: Sat Oct 27 12:12:04 PDT 2001; root:xnu/RELEASE_PPC"),
                            .blank,
                            .text("waiting for remote debugger connection."),
                          ],
                          font: .mono, palette: .console)
    }

    /// The grey curtain, in the four languages it always used. Word for word: it is one of the
    /// few pieces of system text people can quote from memory.
    static func kernelPanic() -> KernelPanic {
        KernelPanic(messages: [
            "You need to restart your computer. Hold down the Power button for several seconds or press the Restart button.",
            "コンピュータを再起動する必要があります。パワーボタンを数秒間押し続けるか、リセットボタンを押してください。",
            "Veuillez redémarrer votre ordinateur. Maintenez la touche de démarrage enfoncée pendant plusieurs secondes ou bien appuyez sur le bouton de réinitialisation.",
            "Sie müssen Ihren Computer neu starten. Halten Sie dazu die Einschalttaste einige Sekunden gedrückt oder drücken Sie die Neustart-Taste.",
        ])
    }

    /// The dump counter that ran underneath the Stop screen while it wrote the memory image out.
    static func ntDumpLines() -> [ScreenLine] {
        [.blank,
         .text("Beginning dump of physical memory"),
         .counter(prefix: "Dumping physical memory to disk: ")]
    }

    // MARK: - More of Windows XP

    /// The user-mode access violation, as the NT family reported it: two addresses and the
    /// verb in quotation marks, which is the detail everybody remembers.
    static func xpMemoryCouldNotBeRead(style: ErrorDialog.Style, using rng: inout CrashRNG) -> ErrorDialog {
        let apps = ["RETROMAC.EXE", "RETROMAC.EXE", "iexplore.exe", "explorer.exe",
                    "wmplayer.exe", "OUTLOOK.EXE", "svchost.exe"]
        let app = pick(apps, using: &rng)
        // ntdll and user32 addresses of the period; the referenced memory is nearly always
        // the null page, because that is what a bad pointer usually is.
        let instruction = pick(["0x7c9\(hex(5, using: &rng))", "0x0040\(hex(4, using: &rng))",
                                "0x77d\(hex(5, using: &rng))"], using: &rng)
        let memory = pick(["0x00000000", "0x00000000", "0x00000000", "0x0000000c",
                           "0x\(hex(8, using: &rng))"], using: &rng)
        let verb = pick(["read", "read", "read", "written"], using: &rng)
        return ErrorDialog(
            title: "\(app) - Application Error",
            body: ["The instruction at \"\(instruction)\" referenced memory at \"\(memory)\". The",
                   "memory could not be \"\(verb)\".",
                   "",
                   "Click on OK to terminate the program",
                   "Click on CANCEL to debug the program"],
            buttons: ["OK", "Cancel"],
            restartButton: nil,
            style: style,
            icon: .errorXP,
            escalatesToBlueScreen: true)
    }

    /// The dialog of the summer of 2003: the RPC service had died, and Windows XP gave you sixty
    /// seconds to save your work before it restarted itself. There was no button. People
    /// learned to type `shutdown -a` in those sixty seconds, which is why the word is in the
    /// text and not in the code.
    static func xpSystemShutdown(using rng: inout CrashRNG) -> ErrorDialog {
        let seconds = pick([59, 44, 29], using: &rng)
        var dialog = ErrorDialog(
            title: "System Shutdown",
            body: ["This system is shutting down. Please save all",
                   "work in progress and log off. Any unsaved",
                   "changes will be lost. This shutdown was",
                   "initiated by NT AUTHORITY\\SYSTEM",
                   "",
                   "Time before shutdown :  \(ErrorDialog.countdownToken)",
                   "",
                   "Message",
                   "Windows must now restart because the",
                   "Remote Procedure Call (RPC) service",
                   "terminated unexpectedly"],
            buttons: [],
            restartButton: nil,
            style: .winXP,
            icon: .errorXP)
        dialog.countdownSeconds = seconds
        return dialog
    }

    /// What XP said after it came back from a Stop error. Same dialog as the application error,
    /// different news.
    static func xpRecoveredFromSeriousError() -> ErrorDialog {
        ErrorDialog(
            title: "Microsoft Windows",
            body: ["The system has recovered from a serious error.",
                   "",
                   "A log of this error has been created.",
                   "",
                   "Please tell Microsoft about this problem.",
                   "We have created an error report that you can send to help us improve",
                   "Microsoft Windows. We will treat this report as confidential and anonymous."],
            buttons: ["Send Error Report", "Don't Send"],
            restartButton: nil,
            style: .winXP,
            icon: .warning)
    }

    /// Dr. Watson, the debugger that shipped with NT and wrote a log nobody read.
    static func drWatson(using rng: inout CrashRNG) -> ErrorDialog {
        let apps = ["RETROMAC.EXE", "RETROMAC.EXE", "iexplore.exe", "winword.exe",
                    "explorer.exe", "msimn.exe"]
        let exceptions = [("access violation", "0xc0000005"), ("access violation", "0xc0000005"),
                          ("access violation", "0xc0000005"), ("stack overflow", "0xc00000fd"),
                          ("illegal instruction", "0xc000001d")]
        let ex = pick(exceptions, using: &rng)
        return ErrorDialog(
            title: "Dr. Watson for Windows",
            body: ["An application error has occurred",
                   "and an application error log is being generated.",
                   "",
                   "\(pick(apps, using: &rng))",
                   "",
                   "Exception: \(ex.0) (\(ex.1)), Address: 0x77f5\(hex(4, using: &rng))"],
            buttons: ["OK"],
            restartButton: nil,
            style: .winXP,
            icon: .errorXP)
    }

    /// The copy error that meant a scratched CD: the cyclic redundancy check had failed. XP
    /// said so in one line; Windows 7 wrapped it in a dialog with three choices.
    static func cdromCRC(style: ErrorDialog.Style, using rng: inout CrashRNG) -> ErrorDialog {
        let files = ["RETROMAC.EXE", "RETROMAC.EXE", "SETUP.EXE", "DATA1.CAB",
                     "VTS_01_1.VOB", "Holiday 2003.avi", "AUTORUN.INF"]
        let file = pick(files, using: &rng)
        if style == .win7 {
            return ErrorDialog(
                title: "Interrupted Action",
                body: ["An unexpected error is keeping you from copying the file. If you",
                       "continue to receive this error, you can use the error code to search",
                       "for help with this problem.",
                       "",
                       "Error 0x80070017: Data error (cyclic redundancy check).",
                       "",
                       "    \(file)"],
                buttons: ["Try Again", "Skip", "Cancel"],
                restartButton: nil,
                style: .win7,
                icon: .errorXP)
        }
        return ErrorDialog(
            title: "Error Copying File or Folder",
            body: ["Cannot copy \(file): Data error (cyclic redundancy check)."],
            buttons: ["OK"],
            restartButton: nil,
            style: .winXP,
            icon: .errorXP)
    }

    // MARK: - More of Windows 9x

    /// The orange screen at the end of a shutdown, in the words 9x used. The real one was a
    /// 320x400 bitmap; a text mode is the honest stand-in.
    static func win9xSafeToTurnOff() -> TextScreen {
        TextScreen(grid: .vga80x25, topRow: 12, leftColumn: 0, lines: [
            .centred("It's now safe to turn off your computer."),
        ], palette: .orange9x)
    }

    /// The floppy that was not there. 9x asked from a small dialog, with the two buttons DOS
    /// had reduced to.
    static func win9xDriveNotReady(using rng: inout CrashRNG) -> ErrorDialog {
        let drive = pick(["A:\\", "A:\\", "A:\\", "D:\\"], using: &rng)
        var dialog = ErrorDialog(
            title: "Error",
            body: ["\(drive) is not accessible.",
                   "",
                   "The device is not ready."],
            buttons: ["Retry", "Cancel"],
            restartButton: nil,
            style: .win9x,
            icon: .error9x)
        dialog.nextButton = "Retry"
        return dialog
    }

    /// The same, after the last retry: only Cancel is left to press.
    static func win9xDriveNotReadyFinal(_ first: ErrorDialog) -> ErrorDialog {
        ErrorDialog(title: first.title, body: first.body, buttons: ["Retry", "Cancel"],
                    restartButton: nil, style: .win9x, icon: .error9x)
    }

    /// The Zip drive in Windows 9x. The cartridge was in, the drive was clicking, and Explorer
    /// reported the only thing it knew: the device was not ready.
    static func win9xZipNotReady() -> ErrorDialog {
        var dialog = ErrorDialog(
            title: "Error",
            body: ["D:\\ is not accessible.",
                   "",
                   "The device is not ready."],
            buttons: ["Retry", "Cancel"],
            restartButton: nil,
            style: .win9x,
            icon: .error9x)
        dialog.nextButton = "Retry"
        return dialog
    }

    /// The Zip drive in Windows XP: the cartridge the drive had just destroyed looked, to
    /// Windows, like a blank one.
    static func xpDiskNotFormatted() -> ErrorDialog {
        var dialog = ErrorDialog(
            title: "Iomega Zip 100 (D:)",
            body: ["The disk in drive D is not formatted.",
                   "",
                   "Do you want to format it now?"],
            buttons: ["Yes", "No"],
            restartButton: nil,
            style: .winXP,
            icon: .warning)
        dialog.nextButton = "Yes"
        return dialog
    }

    static func xpFormatFailed() -> ErrorDialog {
        ErrorDialog(
            title: "Formatting Iomega Zip 100 (D:)",
            body: ["Windows was unable to complete the format."],
            buttons: ["OK"],
            restartButton: nil,
            style: .winXP,
            icon: .errorXP)
    }

    // MARK: - More of the Macintosh

    /// The alert for a disk the Mac could not read, with the two answers it offered: give it
    /// back, or wipe it.
    static func macDiskUnreadable(style: MacAlert.Style) -> MacAlert {
        var alert = MacAlert(style: style,
                             title: nil,
                             lines: ["This disk is unreadable by this Computer.",
                                     "Do you want to initialize the disk?"],
                             buttons: ["Eject", "Initialize"],
                             icon: .disk,
                             idCode: nil,
                             restartButton: nil)
        alert.nextButton = "Initialize"
        return alert
    }

    static func macInitializing(style: MacAlert.Style) -> MacAlert {
        MacAlert(style: style, title: nil,
                 lines: ["Initializing disk\u{2026}"],
                 buttons: [], icon: .disk, idCode: nil, restartButton: nil)
    }

    static func macInitializationFailed(style: MacAlert.Style) -> MacAlert {
        MacAlert(style: style, title: nil,
                 lines: ["Initialization failed!"],
                 buttons: ["OK"], icon: .caution, idCode: nil, restartButton: nil)
    }

    // MARK: - The machine not coming back

    /// The PC before any operating system: light grey on black, top left, no cursor to speak
    /// of except the one waiting for a key.
    static func bootText(_ lines: [String], prompt: Bool = true) -> TextScreen {
        var screenLines = lines.map { ScreenLine.text($0) }
        if prompt { screenLines.append(.prompt("")) }
        return TextScreen(grid: .vga80x25, topRow: 0, leftColumn: 0, lines: screenLines, palette: .dos)
    }

    static func bootNonSystemDisk() -> TextScreen {
        bootText(["Non-System disk or disk error", "Replace and strike any key when ready"])
    }

    /// XP installing updates at shutdown. The count is small because XP's were: a handful of
    /// patches per Tuesday, each with its own progress bar.
    static func bootXPInstallingUpdates(using rng: inout CrashRNG) -> WindowsUpdateScreen {
        let total = Int.random(in: 2...9, using: &rng)
        let current = Int.random(in: 1...total, using: &rng)
        return WindowsUpdateScreen(style: .xp, lines: [
            "Installing update \(current) of \(total)...",
            "Do not turn off or unplug your computer.",
            "It will turn off automatically when installation is complete.",
        ], bar: true)
    }

    /// Windows 7 at the next start: preparing, then a percentage that may well stop at 35, and
    /// on a bad day the sentence that meant another twenty minutes.
    static func bootWin7ConfiguringUpdates(using rng: inout CrashRNG)
        -> (preparing: WindowsUpdateScreen, configuring: WindowsUpdateScreen, reverting: WindowsUpdateScreen) {
        let ceiling = [35, 35, 62, 100].randomElement(using: &rng) ?? 35
        return (
            WindowsUpdateScreen(style: .win7, lines: ["Preparing to configure Windows.", "Do not turn off your computer."], bar: false),
            WindowsUpdateScreen(style: .win7, lines: ["Configuring Windows updates", "\(WindowsUpdateScreen.percentToken)% complete", "Do not turn off your computer."],
                                bar: false, ceiling: ceiling),
            WindowsUpdateScreen(style: .win7, lines: ["Failure configuring Windows updates", "Reverting changes", "Do not turn off your computer."], bar: false)
        )
    }

    static func bootNTLDRMissing() -> TextScreen {
        bootText(["NTLDR is missing", "Press any key to restart"])
    }

    static func bootBOOTMGRMissing() -> TextScreen {
        bootText(["BOOTMGR is missing", "Press Ctrl+Alt+Del to restart"], prompt: false)
    }

    static func bootInvalidSystemDisk() -> TextScreen {
        bootText(["Invalid system disk", "Replace the disk, and then press any key"])
    }

    /// The POST screen with the one line that made people back up: SMART had given up on the
    /// drive. The drive is ours, and says so.
    static func bootSmartBad(using rng: inout CrashRNG) -> TextScreen {
        let sizes = ["8.4GB", "6.4GB", "20.4GB", "40.0GB"]
        let size = pick(sizes, using: &rng)
        let mem = pick(["65536K", "131072K", "262144K"], using: &rng)
        return TextScreen(grid: .vga80x25, topRow: 0, leftColumn: 0, lines: [
            .text("Award Modular BIOS v4.51PG, An Energy Star Ally"),
            .text("Copyright (C) 1984-98, Award Software, Inc."),
            .blank,
            .text("Main Processor : PENTIUM II MMX"),
            .text("Memory Test : \(mem) OK"),
            .blank,
            .text("Award Plug and Play BIOS Extension v1.0A"),
            .text("Copyright (C) 1998, Award Software, Inc."),
            .blank,
            .text("Detecting HDD Primary Master   ... RETROMAC \(size)"),
            .text("Detecting HDD Primary Slave    ... None"),
            .text("Detecting HDD Secondary Master ... CD-ROM"),
            .text("Detecting HDD Secondary Slave  ... None"),
            .blank,
            .text("Primary Master Hard Disk: S.M.A.R.T. Status BAD, Backup and Replace"),
            .blank,
            .text("Press F1 to Resume"),
            .prompt(""),
        ], palette: .dos)
    }

    /// ScanDisk after an unclean shutdown: the full-screen check Windows 9x ran before it would
    /// start, in a window drawn out of box characters. Two screens: the check, and the result.
    static func bootScanDisk(using rng: inout CrashRNG) -> (checking: TextScreen, done: TextScreen) {
        let inner = 68
        let top    = "\u{2554}" + String(repeating: "\u{2550}", count: inner) + "\u{2557}"
        let bottom = "\u{255A}" + String(repeating: "\u{2550}", count: inner) + "\u{255D}"
        func boxed(_ s: String) -> ScreenLine {
            let padded = " " + s + String(repeating: " ", count: max(0, inner - s.count - 1))
            return .text("\u{2551}" + padded + "\u{2551}")
        }
        func boxedCentred(_ s: String) -> ScreenLine {
            let left = (inner - s.count) / 2
            let padded = String(repeating: " ", count: left) + s
                + String(repeating: " ", count: max(0, inner - left - s.count))
            return .text("\u{2551}" + padded + "\u{2551}")
        }
        let stall = CounterStall(at: Int.random(in: 37...88, using: &rng),
                                 seconds: Double.random(in: 2...4, using: &rng))
        let head: [ScreenLine] = [
            .text(top),
            boxedCentred("Microsoft ScanDisk"),
            boxed(""),
            boxed("Because Windows was not properly shut down, one or more of your"),
            boxed("disk drives may have errors on it."),
            boxed(""),
            boxed("To avoid seeing this message again, always shut down your computer"),
            boxed("by selecting Shut Down from the Start menu."),
            boxed(""),
        ]
        // Sized for the two-digit count it shows nearly all the time; the box edge steps out
        // one cell at 100, for the frame it is there.
        let percentSuffix = "% complete" + String(repeating: " ", count: inner - 15) + "\u{2551}"
        let checking = TextScreen(grid: .vga80x25, topRow: 3, leftColumn: 5, lines: head + [
            boxed("ScanDisk is now checking the following areas of drive C:"),
            boxed(""),
            boxed("  Media descriptor"),
            boxed("  File allocation tables"),
            boxed("  Directory structure"),
            boxed("  File system"),
            boxed("  Surface scan"),
            boxed(""),
            .progressBar(prefix: "\u{2551} ", width: inner - 2, suffix: " \u{2551}"),
            .percent(prefix: "\u{2551}   ", suffix: percentSuffix),
            .text(bottom),
        ], palette: .scandisk, counterStall: stall)
        let done = TextScreen(grid: .vga80x25, topRow: 3, leftColumn: 5, lines: head + [
            boxed("ScanDisk did not find any errors on this drive."),
            boxed(""),
            boxed(""),
            boxed(""),
            boxed(""),
            boxed(""),
            boxed(""),
            boxed(""),
            boxedCentred("Windows will now start."),
            boxed(""),
            .text(bottom),
        ], palette: .scandisk)
        return (checking, done)
    }

    /// CHKDSK at boot, the NT family's version of the same ritual: a countdown to skip it, and
    /// three stages that reported in percent.
    static func bootChkdsk(palette: ScreenPalette) -> (prompt: TextScreen, stages: [TextScreen], done: TextScreen) {
        let head: [ScreenLine] = [
            .text("Checking file system on C:"),
            .text("The type of the file system is NTFS."),
            .text("The volume is dirty."),
            .blank,
            .text("One of your disks needs to be checked for consistency. You"),
            .text("may cancel the disk check, but it is strongly recommended"),
            .text("that you continue."),
        ]
        let prompt = TextScreen(grid: .vga80x30, topRow: 1, leftColumn: 0, lines: head + [
            .countdown(prefix: "To skip disk checking, press any key within ", seconds: 10, suffix: " second(s)."),
        ], palette: palette)
        let names = ["verifying files", "verifying indexes", "verifying security descriptors"]
        var stages: [TextScreen] = []
        var sofar: [ScreenLine] = head + [.text("Windows will now check the disk."), .blank]
        for (i, name) in names.enumerated() {
            let line = ScreenLine.percent(prefix: "CHKDSK is \(name) (stage \(i + 1) of 3)... ",
                                          suffix: " percent complete.")
            stages.append(TextScreen(grid: .vga80x30, topRow: 1, leftColumn: 0,
                                     lines: sofar + [line], palette: palette))
            sofar.append(.text("CHKDSK is \(name) (stage \(i + 1) of 3)... 100 percent complete."))
        }
        let done = TextScreen(grid: .vga80x30, topRow: 1, leftColumn: 0, lines: sofar + [
            .text("Windows has checked the file system and found no problems."),
            .blank,
            .text("  20972857 KB total disk space."),
            .text("  14203112 KB in 61829 files."),
            .text("     19540 KB in 4406 indexes."),
            .text("         0 KB in bad sectors."),
            .text("    163377 KB in use by the system."),
            .text("   6586828 KB available on disk."),
            .blank,
            .text("Windows has finished checking your disk."),
            .text("Please wait while your computer restarts."),
        ], palette: palette)
        return (prompt, stages, done)
    }

    /// The Sad Mac's codes: the first word says what failed, the second where. These are the
    /// ones people photographed.
    static func sadMacCodes(using rng: inout CrashRNG) -> String {
        pick(["0000000F 0000000A", "0000000F 00000001", "00000003 0000FFFF",
              "0000000E 00000001", "0000000F 00000003"], using: &rng)
    }
}
