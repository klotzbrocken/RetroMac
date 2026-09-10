import Foundation

/// Which failures each Windows could have, and how likely each one is.
///
/// A scenario is built rather than stored, because half of a period error screen is a random
/// address. The build takes an explicit generator so a test can seed it and get the same screen
/// twice.
enum CrashCatalogue {

    struct Spec: Identifiable {
        let id: String
        let title: String
        let eras: Set<CrashEra>
        let weight: Int
        /// Declared rather than derived: the picker needs it for every candidate on every draw,
        /// and building each scenario just to read its shape was the cost of not declaring it.
        let kind: CrashKind
        let category: CrashScenario.Category
        let build: (inout CrashRNG) -> CrashScenario

        init(id: String, title: String, eras: Set<CrashEra>, weight: Int, kind: CrashKind,
             category: CrashScenario.Category = .failure,
             build: @escaping (inout CrashRNG) -> CrashScenario) {
            self.id = id; self.title = title; self.eras = eras; self.weight = weight
            self.kind = kind; self.category = category; self.build = build
        }
    }

    static let all: [Spec] = [

        Spec(id: "win9x-general-fault",
             title: "Blue screen — an error has occurred",
             eras: [.win95, .win98, .winMe],
             weight: 5, kind: .fullScreen) { rng in
            CrashScenario(id: "win9x-general-fault",
                          title: "Blue screen — an error has occurred",
                          eras: [.win95, .win98, .winMe], weight: 5, freezeHold: 1.6,
                          stages: [
                            // Any key goes back to work, Ctrl+Alt+Del reboots — exactly the choice
                            // the screen offers in its own words.
                            CrashStage(.textScreen(CrashCopy.win9xGeneralFault(using: &rng)),
                                       recovery: [.anyKey, .enterKey, .ctrlAltDelete])
                          ])
        },

        Spec(id: "win9x-fatal-exception",
             title: "Blue screen — fatal exception",
             eras: [.win95, .win98, .winMe],
             weight: 4, kind: .fullScreen) { rng in
            CrashScenario(id: "win9x-fatal-exception",
                          title: "Blue screen — fatal exception",
                          eras: [.win95, .win98, .winMe], weight: 4, freezeHold: 1.2,
                          stages: [
                            CrashStage(.textScreen(CrashCopy.win9xFatalException(using: &rng)),
                                       recovery: [.anyKey, .ctrlAltDelete])
                          ])
        },

        Spec(id: "win9x-illegal-operation",
             title: "Illegal operation",
             eras: [.win95, .win98, .winMe],
             weight: 4, kind: .window) { rng in
            CrashScenario(id: "win9x-illegal-operation",
                          title: "Illegal operation",
                          eras: [.win95, .win98, .winMe], weight: 4, freezeHold: 0.8,
                          stages: [
                            CrashStage(.dialog(CrashCopy.win9xIllegalOperationVaried(using: &rng)),
                                       recovery: .anyKey)
                          ])
        },

        Spec(id: "winme-protection-error",
             title: "Windows protection error",
             eras: [.winMe, .win98],
             weight: 2, kind: .fullScreen) { rng in
            CrashScenario(id: "winme-protection-error",
                          title: "Windows protection error",
                          eras: [.winMe, .win98], weight: 2, freezeHold: 1.0,
                          stages: [
                            // This one only ever ended one way.
                            // "You need to restart your computer" meant exactly that.
                            CrashStage(.textScreen(CrashCopy.winMeProtectionError(using: &rng)),
                                       recovery: [.restartsOnAnyKey])
                          ])
        },

        Spec(id: "nt-stop-error",
             title: "Blue screen — Stop error",
             eras: [.winXP, .win7],
             weight: 5, kind: .fullScreen) { rng in
            let screen = CrashCopy.ntStopScreen(using: &rng)
            // Same screen with the dump appended — and the same palette and typeface. Rebuilding
            // it without them fell back to the 9x defaults, so the blue changed shade halfway
            // through the crash.
            let withDump = TextScreen(grid: screen.grid, topRow: screen.topRow,
                                      leftColumn: screen.leftColumn,
                                      lines: screen.lines + CrashCopy.ntDumpLines(),
                                      font: screen.font, palette: screen.palette)
            var scenario = CrashScenario(id: "nt-stop-error",
                                         title: "Blue screen — Stop error",
                                         eras: [.winXP, .win7], weight: 5, freezeHold: 1.4,
                                         stages: [
                                            // The screen sits there for a beat, then starts writing the
                                            // dump — which is where the counter comes in.
                                            CrashStage(.textScreen(screen), hold: 2.2),
                                            CrashStage(.textScreen(withDump), hold: 6.0),
                                            // A Stop error never came back on a keystroke. Anything you
                                            // press here restarts, which is what people actually did.
                                            CrashStage(.textScreen(withDump), recovery: [.restartsOnAnyKey]),
                                         ])
            // XP had a sequel: a little while after the machine came back, it asked whether
            // Microsoft could hear about it.
            if CrashEra.current() != .win7 {
                scenario.aftermath = .init(id: "xp-recovered-serious-error", delay: 10...30)
            }
            return scenario
        },
        Spec(id: "win9x-runtime-error",
             title: "Visual C++ Runtime Error",
             eras: [.win95, .win98, .winMe],
             weight: 4, kind: .window) { rng in
            CrashScenario(id: "win9x-runtime-error",
                          title: "Visual C++ Runtime Error",
                          eras: [.win95, .win98, .winMe], weight: 4, freezeHold: 0.8,
                          stages: [
                            CrashStage(.dialog(CrashCopy.runtimeError(style: .win9x, using: &rng)),
                                       recovery: .anyKey)
                          ])
        },

        Spec(id: "xp-runtime-error",
             title: "Visual C++ Runtime Error",
             eras: [.winXP],
             weight: 3, kind: .window) { rng in
            CrashScenario(id: "xp-runtime-error",
                          title: "Visual C++ Runtime Error",
                          eras: [.winXP], weight: 3, freezeHold: 0.8,
                          stages: [
                            CrashStage(.dialog(CrashCopy.runtimeError(style: .winXP, using: &rng)),
                                       recovery: .anyKey)
                          ])
        },

        Spec(id: "win9x-virus-found",
             title: "Virus found",
             eras: [.win95, .win98, .winMe],
             weight: 3, kind: .window) { rng in
            CrashScenario(id: "win9x-virus-found",
                          title: "Virus found",
                          eras: [.win95, .win98, .winMe], weight: 3, freezeHold: 0.6,
                          stages: [
                            // Nothing crashes here. The machine is fine; something on it is not.
                            CrashStage(.dialog(CrashCopy.nortonVirusFound(using: &rng)),
                                       recovery: .anyKey)
                          ])
        },

        Spec(id: "xp-virus-found",
             title: "Virus found",
             eras: [.winXP],
             weight: 3, kind: .window) { rng in
            CrashScenario(id: "xp-virus-found",
                          title: "Virus found",
                          eras: [.winXP], weight: 3, freezeHold: 0.6,
                          stages: [
                            CrashStage(.dialog(CrashCopy.symantecVirusFound(using: &rng)),
                                       recovery: .anyKey)
                          ])
        },

        Spec(id: "win9x-system-busy",
             title: "The system is busy",
             eras: [.win95, .win98, .winMe],
             weight: 3, kind: .fullScreen) { _ in
            CrashScenario(id: "win9x-system-busy",
                          title: "The system is busy",
                          eras: [.win95, .win98, .winMe], weight: 3, freezeHold: 1.0,
                          stages: [
                            // The screen you got for pressing Ctrl+Alt+Delete once. It did offer
                            // a way back, and said so.
                            CrashStage(.textScreen(CrashCopy.win9xSystemBusy()),
                                       recovery: [.anyKey, .ctrlAltDelete])
                          ])
        },

        Spec(id: "shell-restart",
             title: "Explorer has stopped responding",
             eras: [.win95, .win98, .winMe, .winXP, .win7],
             weight: 4, kind: .shell) { rng in
            CrashScenario(id: "shell-restart",
                          title: "Explorer has stopped responding",
                          eras: [.win95, .win98, .winMe, .winXP, .win7], weight: 4, freezeHold: 0,
                          stages: [
                            // No screen at all: the taskbar and the desktop icons vanish, the
                            // machine sits there, and then the shell comes back. Far more common
                            // than a blue screen, and the one everybody recognises instantly.
                            // The duration is the stage's hold, not the surface's, so the rule
                            // that every stage either holds or can be dismissed stays literally
                            // true — a test enforces it.
                            CrashStage(.shellRestart, hold: Double.random(in: 4.5...7.0, using: &rng))
                          ])
        },

        Spec(id: "xp-application-error",
             title: "Has encountered a problem",
             eras: [.winXP],
             weight: 5, kind: .window) { rng in
            CrashScenario(id: "xp-application-error",
                          title: "Has encountered a problem",
                          eras: [.winXP], weight: 5, freezeHold: 0.8,
                          stages: [
                            CrashStage(.dialog(CrashCopy.xpApplicationError(using: &rng)),
                                       recovery: .anyKey)
                          ])
        },

        Spec(id: "win7-application-error",
             title: "Has stopped working",
             eras: [.win7],
             weight: 5, kind: .window) { rng in
            CrashScenario(id: "win7-application-error",
                          title: "Has stopped working",
                          eras: [.win7], weight: 5, freezeHold: 0.8,
                          stages: [
                            CrashStage(.dialog(CrashCopy.win7ApplicationError(using: &rng)),
                                       recovery: .anyKey)
                          ])
        },

        Spec(id: "macos9-bomb-named",
             title: "System error — with the program named",
             eras: [.macos9],
             weight: 4, kind: .window) { rng in
            CrashScenario(id: "macos9-bomb-named",
                          title: "System error — with the program named",
                          eras: [.macos9], weight: 4, freezeHold: 1.0,
                          stages: [
                            CrashStage(.macAlert(CrashCopy.macOS9BombNamed(using: &rng)),
                                       recovery: [.restartsOnAnyKey])
                          ])
        },

        Spec(id: "macos9-application-quit",
             title: "Application unexpectedly quit",
             eras: [.macos9],
             weight: 4, kind: .window) { rng in
            CrashScenario(id: "macos9-application-quit",
                          title: "Application unexpectedly quit",
                          eras: [.macos9], weight: 4, freezeHold: 0.8,
                          stages: [
                            // One program died, the machine did not. So this one returns to the
                            // desktop rather than restarting.
                            CrashStage(.macAlert(CrashCopy.macApplicationQuit(style: .platinum, using: &rng)),
                                       recovery: .anyKey)
                          ])
        },

        Spec(id: "macos6-application-quit",
             title: "Application unexpectedly quit",
             eras: [.macos6],
             weight: 3, kind: .window) { rng in
            CrashScenario(id: "macos6-application-quit",
                          title: "Application unexpectedly quit",
                          eras: [.macos6], weight: 3, freezeHold: 0.8,
                          stages: [
                            CrashStage(.macAlert(CrashCopy.macApplicationQuit(style: .system6, using: &rng)),
                                       recovery: .anyKey)
                          ])
        },

        Spec(id: "aqua-application-quit",
             title: "Application unexpectedly quit",
             eras: [.macosxAqua, .macosxModern],
             weight: 4, kind: .window) { rng in
            CrashScenario(id: "aqua-application-quit",
                          title: "Application unexpectedly quit",
                          eras: [.macosxAqua, .macosxModern], weight: 4, freezeHold: 0.8,
                          stages: [
                            CrashStage(.dialog(CrashCopy.aquaApplicationQuit(using: &rng)),
                                       recovery: .anyKey)
                          ])
        },

        Spec(id: "macos6-bomb",
             title: "System error — the bomb",
             eras: [.macos6],
             weight: 5, kind: .window) { rng in
            CrashScenario(id: "macos6-bomb",
                          title: "System error — the bomb",
                          eras: [.macos6], weight: 5, freezeHold: 1.0,
                          stages: [
                            // Restart was the only button that ever did anything; Resume was
                            // greyed out, which is why the alert is remembered as a dead end.
                            CrashStage(.macAlert(CrashCopy.system6Bomb(using: &rng)),
                                       recovery: [.restartsOnAnyKey])
                          ])
        },

        Spec(id: "macos9-bomb",
             title: "System error — bus error",
             eras: [.macos9],
             weight: 5, kind: .window) { rng in
            CrashScenario(id: "macos9-bomb",
                          title: "System error — bus error",
                          eras: [.macos9], weight: 5, freezeHold: 1.0,
                          stages: [
                            CrashStage(.macAlert(CrashCopy.macOS9Bomb(using: &rng)),
                                       recovery: [.restartsOnAnyKey])
                          ])
        },

        Spec(id: "macosx-panic-console",
             title: "Kernel panic — the text console",
             eras: [.macosxAqua],
             weight: 5, kind: .fullScreen) { rng in
            CrashScenario(id: "macosx-panic-console",
                          title: "Kernel panic — the text console",
                          eras: [.macosxAqua], weight: 5, freezeHold: 1.2,
                          stages: [
                            CrashStage(.textScreen(CrashCopy.aquaPanicConsole(using: &rng)),
                                       recovery: [.restartsOnAnyKey])
                          ])
        },

        Spec(id: "macosx-panic-curtain",
             title: "Kernel panic — you need to restart",
             eras: [.macosxModern],
             weight: 5, kind: .fullScreen) { _ in
            CrashScenario(id: "macosx-panic-curtain",
                          title: "Kernel panic — you need to restart",
                          eras: [.macosxModern], weight: 5, freezeHold: 1.4,
                          stages: [
                            // The curtain dropped over whatever was on screen and stayed until
                            // somebody held the power button. There was no key that helped.
                            CrashStage(.kernelPanic(CrashCopy.kernelPanic()),
                                       recovery: [.restartsOnAnyKey])
                          ])
        },

        // MARK: More failures

        Spec(id: "xp-memory-could-not-be-read",
             title: "The memory could not be read",
             eras: [.winXP, .win7],
             weight: 4, kind: .window) { rng in
            // Same words on both, but the era's own furniture around them.
            let style: ErrorDialog.Style = Bool.random(using: &rng) ? .winXP : .win7
            return CrashScenario(id: "xp-memory-could-not-be-read",
                                 title: "The memory could not be read",
                                 eras: [.winXP, .win7], weight: 4, freezeHold: 0.8,
                                 stages: [
                                    CrashStage(.dialog(CrashCopy.xpMemoryCouldNotBeRead(style: style, using: &rng)),
                                               recovery: .anyKey)
                                 ])
        },

        Spec(id: "xp-rpc-countdown",
             title: "System Shutdown — the RPC countdown",
             eras: [.winXP],
             weight: 5, kind: .window) { rng in
            let dialog = CrashCopy.xpSystemShutdown(using: &rng)
            var scenario = CrashScenario(id: "xp-rpc-countdown",
                                         title: "System Shutdown — the RPC countdown",
                                         eras: [.winXP], weight: 5, freezeHold: 0.6,
                                         stages: [
                                            // No button. The clock runs out, and the machine
                                            // restarts, which is what the dialog said it would do.
                                            CrashStage(.dialog(dialog),
                                                       hold: TimeInterval((dialog.countdownSeconds ?? 0) + 1))
                                         ])
            scenario.endsWithRestart = true
            return scenario
        },

        Spec(id: "xp-recovered-serious-error",
             title: "Recovered from a serious error",
             eras: [.winXP],
             weight: 3, kind: .window, category: .aftermath) { _ in
            var scenario = CrashScenario(id: "xp-recovered-serious-error",
                                         title: "Recovered from a serious error",
                                         eras: [.winXP], weight: 3, freezeHold: 0,
                                         stages: [
                                            CrashStage(.dialog(CrashCopy.xpRecoveredFromSeriousError()),
                                                       recovery: .anyKey)
                                         ])
            scenario.category = .aftermath
            return scenario
        },

        Spec(id: "nt-dr-watson",
             title: "Dr. Watson",
             eras: [.winXP],
             weight: 3, kind: .window) { rng in
            CrashScenario(id: "nt-dr-watson",
                          title: "Dr. Watson",
                          eras: [.winXP], weight: 3, freezeHold: 0.8,
                          stages: [
                            CrashStage(.dialog(CrashCopy.drWatson(using: &rng)), recovery: .anyKey)
                          ])
        },

        Spec(id: "win9x-safe-to-turn-off",
             title: "It's now safe to turn off your computer",
             eras: [.win95, .win98, .winMe],
             weight: 4, kind: .fullScreen) { _ in
            CrashScenario(id: "win9x-safe-to-turn-off",
                          title: "It's now safe to turn off your computer",
                          eras: [.win95, .win98, .winMe], weight: 4, freezeHold: 1.0,
                          stages: [
                            // The desktop goes, the orange comes, and nothing on the keyboard
                            // brings Windows back: the machine has shut down, or thinks it has.
                            CrashStage(.black, hold: 0.8),
                            CrashStage(.textScreen(CrashCopy.win9xSafeToTurnOff()),
                                       recovery: [.restartsOnAnyKey])
                          ])
        },

        Spec(id: "mac-disk-unreadable",
             title: "This disk is unreadable",
             eras: [.macos6, .macos9],
             weight: 4, kind: .window) { rng in
            let style: MacAlert.Style = Bool.random(using: &rng) ? .system6 : .platinum
            return CrashScenario(id: "mac-disk-unreadable",
                                 title: "This disk is unreadable",
                                 eras: [.macos6, .macos9], weight: 4, freezeHold: 0.8,
                                 stages: [
                                    // Eject closes it. Initialize is the mistake, and the next two
                                    // stages are what the mistake looked like.
                                    CrashStage(.macAlert(CrashCopy.macDiskUnreadable(style: style)),
                                               recovery: .anyKey),
                                    CrashStage(.macAlert(CrashCopy.macInitializing(style: style)),
                                               hold: Double.random(in: 2.5...4.0, using: &rng),
                                               sound: .floppySeek),
                                    CrashStage(.macAlert(CrashCopy.macInitializationFailed(style: style)),
                                               recovery: .anyKey),
                                 ])
        },

        Spec(id: "xp-cdrom-crc",
             title: "Data error (cyclic redundancy check)",
             eras: [.winXP, .win7],
             weight: 3, kind: .window) { rng in
            let style: ErrorDialog.Style = Bool.random(using: &rng) ? .winXP : .win7
            return CrashScenario(id: "xp-cdrom-crc",
                                 title: "Data error (cyclic redundancy check)",
                                 eras: [.winXP, .win7], weight: 3, freezeHold: 1.2,
                                 stages: [
                                    CrashStage(.dialog(CrashCopy.cdromCRC(style: style, using: &rng)),
                                               recovery: .anyKey)
                                 ])
        },

        Spec(id: "win9x-not-ready-a",
             title: "The device is not ready",
             eras: [.win95, .win98, .winMe],
             weight: 3, kind: .window) { rng in
            let dialog = CrashCopy.win9xDriveNotReady(using: &rng)
            return CrashScenario(id: "win9x-not-ready-a",
                                 title: "The device is not ready",
                                 eras: [.win95, .win98, .winMe], weight: 3, freezeHold: 0.6,
                                 stages: [
                                    // Retry twice, with the drive hunting in between; then the
                                    // same dialog, and only Cancel takes you anywhere.
                                    CrashStage(.dialog(dialog), recovery: .anyKey),
                                    CrashStage(.still, hold: Double.random(in: 1.2...1.8, using: &rng), sound: .floppySeek),
                                    CrashStage(.dialog(dialog), recovery: .anyKey),
                                    CrashStage(.still, hold: Double.random(in: 1.2...1.8, using: &rng), sound: .floppySeek),
                                    CrashStage(.dialog(CrashCopy.win9xDriveNotReadyFinal(dialog)), recovery: .anyKey),
                                 ])
        },

        // MARK: The Zip drive

        Spec(id: "win-zip-click-of-death",
             title: "Iomega Zip — the click of death",
             eras: [.win95, .win98, .winMe, .winXP],
             weight: 3, kind: .fullScreen) { rng in
            let xp = CrashEra.current() == .winXP
            let hunting = Double.random(in: 4.0...7.0, using: &rng)
            var stages: [CrashStage] = [
                // The drive reading the cartridge: the hourglass, and the clicking.
                CrashStage(.moment(.hourglass), hold: hunting, sound: .zipClick),
            ]
            if xp {
                stages += [
                    CrashStage(.dialog(CrashCopy.xpDiskNotFormatted()), recovery: .anyKey),
                    CrashStage(.still, hold: 2.0, sound: .zipClick),
                    CrashStage(.dialog(CrashCopy.xpFormatFailed()), recovery: .anyKey),
                ]
            } else {
                let dialog = CrashCopy.win9xZipNotReady()
                stages += [
                    CrashStage(.dialog(dialog), recovery: .anyKey),
                    CrashStage(.still, hold: 1.6, sound: .zipClick),
                    CrashStage(.dialog(dialog), recovery: .anyKey),
                    CrashStage(.still, hold: 1.6, sound: .zipClick),
                    CrashStage(.dialog(CrashCopy.win9xDriveNotReadyFinal(dialog)), recovery: .anyKey),
                ]
            }
            var scenario = CrashScenario(id: "win-zip-click-of-death",
                                         title: "Iomega Zip — the click of death",
                                         eras: [.win95, .win98, .winMe, .winXP], weight: 3,
                                         freezeHold: 0.3, stages: stages)
            scenario.prelude = .desktopDrive(name: "Iomega Zip (D:)", icon: "zipdrive", timeout: 20...40)
            return scenario
        },

        // MARK: The machine not coming back

        Spec(id: "boot-non-system-disk",
             title: "Non-System disk or disk error",
             eras: [.win95, .win98, .winMe, .winXP, .win7],
             weight: 4, kind: .fullScreen, category: .bootFailure) { _ in
            bootFailure("boot-non-system-disk", "Non-System disk or disk error",
                        [.win95, .win98, .winMe, .winXP, .win7], weight: 4,
                        stages: [CrashStage(.textScreen(CrashCopy.bootNonSystemDisk()), hold: 8, recovery: .anyKey)])
        },

        Spec(id: "boot-ntldr-missing",
             title: "NTLDR is missing",
             eras: [.winXP],
             weight: 4, kind: .fullScreen, category: .bootFailure) { _ in
            bootFailure("boot-ntldr-missing", "NTLDR is missing", [.winXP], weight: 4,
                        stages: [CrashStage(.textScreen(CrashCopy.bootNTLDRMissing()), hold: 8, recovery: .anyKey)])
        },

        Spec(id: "boot-bootmgr-missing",
             title: "BOOTMGR is missing",
             eras: [.win7],
             weight: 4, kind: .fullScreen, category: .bootFailure) { _ in
            bootFailure("boot-bootmgr-missing", "BOOTMGR is missing", [.win7], weight: 4,
                        stages: [CrashStage(.textScreen(CrashCopy.bootBOOTMGRMissing()), hold: 8,
                                            recovery: [.anyKey, .ctrlAltDelete])])
        },

        Spec(id: "boot-invalid-system-disk",
             title: "Invalid system disk",
             eras: [.win95, .win98, .winMe],
             weight: 3, kind: .fullScreen, category: .bootFailure) { _ in
            bootFailure("boot-invalid-system-disk", "Invalid system disk", [.win95, .win98, .winMe], weight: 3,
                        stages: [CrashStage(.textScreen(CrashCopy.bootInvalidSystemDisk()), hold: 8, recovery: .anyKey)])
        },

        Spec(id: "boot-smart-bad",
             title: "S.M.A.R.T. Status BAD",
             eras: [.win95, .win98, .winMe, .winXP, .win7],
             weight: 2, kind: .fullScreen, category: .bootFailure) { rng in
            bootFailure("boot-smart-bad", "S.M.A.R.T. Status BAD", [.win95, .win98, .winMe, .winXP, .win7], weight: 2,
                        stages: [CrashStage(.textScreen(CrashCopy.bootSmartBad(using: &rng)), hold: 8, recovery: .anyKey)])
        },

        Spec(id: "boot-scandisk",
             title: "ScanDisk",
             eras: [.win95, .win98, .winMe],
             weight: 5, kind: .fullScreen, category: .bootFailure) { rng in
            let screens = CrashCopy.bootScanDisk(using: &rng)
            return bootFailure("boot-scandisk", "ScanDisk", [.win95, .win98, .winMe], weight: 5,
                               stages: [
                                CrashStage(.textScreen(screens.checking), hold: Double.random(in: 9...12, using: &rng)),
                                CrashStage(.textScreen(screens.done), hold: 1.5),
                               ])
        },

        Spec(id: "boot-chkdsk",
             title: "CHKDSK",
             eras: [.winXP, .win7],
             weight: 4, kind: .fullScreen, category: .bootFailure) { rng in
            let screens = CrashCopy.bootChkdsk(palette: CrashEra.current() == .win7 ? .console : .nt)
            var stages = [
                // Any key skips it, which is what the screen offers and what everyone did.
                CrashStage(.textScreen(screens.prompt), hold: 10, recovery: .anyKey),
            ]
            for stage in screens.stages {
                stages.append(CrashStage(.textScreen(stage), hold: Double.random(in: 3...4, using: &rng)))
            }
            stages.append(CrashStage(.textScreen(screens.done), hold: 1.5))
            return bootFailure("boot-chkdsk", "CHKDSK", [.winXP, .win7], weight: 4, stages: stages)
        },

        Spec(id: "boot-sad-mac",
             title: "Sad Mac",
             eras: [.macos6, .macos9],
             weight: 4, kind: .fullScreen, category: .bootFailure) { rng in
            bootFailure("boot-sad-mac", "Sad Mac", [.macos6, .macos9], weight: 4,
                        stages: [CrashStage(.bootGlyph(.sadMac(codes: CrashCopy.sadMacCodes(using: &rng))),
                                            hold: 7, recovery: .anyKey)])
        },

        Spec(id: "boot-question-folder",
             title: "The blinking question mark",
             eras: [.macosxAqua, .macosxModern],
             weight: 4, kind: .fullScreen, category: .bootFailure) { rng in
            bootFailure("boot-question-folder", "The blinking question mark", [.macosxAqua, .macosxModern], weight: 4,
                        stages: [CrashStage(.bootGlyph(.questionFolder),
                                            hold: Double.random(in: 5...7, using: &rng), recovery: .anyKey)])
        },

        Spec(id: "boot-prohibitory",
             title: "The prohibitory sign",
             eras: [.macosxAqua, .macosxModern],
             weight: 2, kind: .fullScreen, category: .bootFailure) { rng in
            bootFailure("boot-prohibitory", "The prohibitory sign", [.macosxAqua, .macosxModern], weight: 2,
                        stages: [CrashStage(.bootGlyph(.prohibitory), hold: Double.random(in: 2...5, using: &rng))])
        },

        // MARK: Moments

        Spec(id: "moment-beachball",
             title: "The beach ball",
             eras: [.macosxAqua, .macosxModern],
             weight: 5, kind: .fullScreen, category: .moment) { rng in
            moment("moment-beachball", "The beach ball", [.macosxAqua, .macosxModern], weight: 5,
                   stages: [CrashStage(.moment(.beachball), hold: Double.random(in: 3...8, using: &rng))])
        },

        Spec(id: "moment-watch-cursor",
             title: "The wristwatch",
             eras: [.macos6, .macos9],
             weight: 5, kind: .fullScreen, category: .moment) { rng in
            moment("moment-watch-cursor", "The wristwatch", [.macos6, .macos9], weight: 5,
                   stages: [CrashStage(.moment(.watchCursor), hold: Double.random(in: 2...5, using: &rng))])
        },

        Spec(id: "moment-hourglass",
             title: "The hourglass",
             eras: [.win95, .win98, .winMe, .winXP],
             weight: 5, kind: .fullScreen, category: .moment) { rng in
            moment("moment-hourglass", "The hourglass", [.win95, .win98, .winMe, .winXP], weight: 5,
                   stages: [CrashStage(.moment(.hourglass), hold: Double.random(in: 2...5, using: &rng))])
        },

        Spec(id: "moment-busy-ring",
             title: "The busy ring",
             eras: [.win7],
             weight: 5, kind: .fullScreen, category: .moment) { rng in
            moment("moment-busy-ring", "The busy ring", [.win7], weight: 5,
                   stages: [CrashStage(.moment(.busyRing), hold: Double.random(in: 2...5, using: &rng))])
        },

        Spec(id: "moment-snow",
             title: "Snow",
             eras: [.win95, .win98, .winMe],
             weight: 3, kind: .fullScreen, category: .moment) { rng in
            moment("moment-snow", "Snow", [.win95, .win98, .winMe], weight: 3,
                   stages: [CrashStage(.moment(.snowBurst), hold: Double.random(in: 1.0...2.0, using: &rng))])
        },

        Spec(id: "moment-palette",
             title: "The palette goes",
             eras: [.win95, .win98, .winMe, .macos6, .macos9],
             weight: 3, kind: .fullScreen, category: .moment) { rng in
            moment("moment-palette", "The palette goes", [.win95, .win98, .winMe, .macos6, .macos9], weight: 3,
                   stages: [CrashStage(.moment(.paletteCorruption), hold: Double.random(in: 1.5...3.0, using: &rng))])
        },

        Spec(id: "moment-hsync-roll",
             title: "The picture rolls",
             eras: [.win95, .win98, .winMe, .winXP, .macos6, .macos9, .macosxAqua],
             weight: 3, kind: .fullScreen, category: .moment) { rng in
            moment("moment-hsync-roll", "The picture rolls",
                   [.win95, .win98, .winMe, .winXP, .macos6, .macos9, .macosxAqua], weight: 3,
                   stages: [CrashStage(.moment(.hsyncRoll), hold: Double.random(in: 2...6, using: &rng))])
        },

        Spec(id: "moment-relay",
             title: "The monitor switches modes",
             eras: [.win95, .win98, .winMe, .winXP],
             weight: 2, kind: .fullScreen, category: .moment) { rng in
            moment("moment-relay", "The monitor switches modes", [.win95, .win98, .winMe, .winXP], weight: 2,
                   stages: [CrashStage(.black, hold: Double.random(in: 0.15...0.5, using: &rng)),
                            CrashStage(.still, hold: 0.6)])
        },
    ]

    private static func bootFailure(_ id: String, _ title: String, _ eras: Set<CrashEra>, weight: Int,
                                    stages: [CrashStage]) -> CrashScenario {
        var s = CrashScenario(id: id, title: title, eras: eras, weight: weight, freezeHold: 0, stages: stages)
        s.category = .bootFailure
        return s
    }

    private static func moment(_ id: String, _ title: String, _ eras: Set<CrashEra>, weight: Int,
                               stages: [CrashStage]) -> CrashScenario {
        var s = CrashScenario(id: id, title: title, eras: eras, weight: weight, freezeHold: 0, stages: stages)
        s.category = .moment
        return s
    }

    /// The failures of an era: what the scheduler and the settings list draw from. Boot
    /// failures, aftermaths and moments have their own lists.
    static func specs(for era: CrashEra) -> [Spec] {
        all.filter { $0.eras.contains(era) && $0.category == .failure }
    }

    static func specs(for era: CrashEra, category: CrashScenario.Category) -> [Spec] {
        all.filter { $0.eras.contains(era) && $0.category == category }
    }

    static func spec(id: String) -> Spec? { all.first { $0.id == id } }

    /// The blue screen of an era, for a dialog that escalates into one.
    static func blueScreen(for era: CrashEra, using rng: inout CrashRNG) -> CrashScenario? {
        let ids = ["win9x-fatal-exception", "win9x-general-fault", "nt-stop-error"]
        let candidates = all.filter { ids.contains($0.id) && $0.eras.contains(era) }
        guard let spec = candidates.randomElement(using: &rng) else { return nil }
        return spec.build(&rng)
    }

    /// Weighted pick within an era, skipping anything the user switched off — and, when there is
    /// anything else to show, whatever came last.
    ///
    /// Excluding the previous one is not superstition about the generator: with eight scenarios
    /// an honest weighted draw repeats about one time in eight, and two in a row is common enough
    /// that a feature whose whole promise is "surprise me" starts to look broken. Randomness
    /// people are happy with is not the same as uniform randomness.
    static func pick(for era: CrashEra, using rng: inout CrashRNG,
                     excluding lastID: String? = nil,
                     avoiding lastKind: CrashKind? = nil,
                     isEnabled: (String) -> Bool = { _ in true }) -> CrashScenario? {
        var choices = specs(for: era).filter { isEnabled($0.id) }
        if let lastID, choices.count > 1 {
            let withoutLast = choices.filter { $0.id != lastID }
            if !withoutLast.isEmpty { choices = withoutLast }
        }
        // Half of the 9x catalogue is a blue screen with different words on it. Avoiding the
        // same SHAPE as last time, not just the same entry, is what makes the variety visible:
        // a blue screen followed by a dialog followed by the shell dying reads as three
        // different failures, where three blue screens read as one.
        if let lastKind, choices.count > 1 {
            let rest = choices.filter { $0.kind != lastKind }
            if !rest.isEmpty { choices = rest }
        }
        return draw(choices, using: &rng)
    }

    /// A mild moment for the era, never the one just shown.
    static func pickMoment(for era: CrashEra, using rng: inout CrashRNG,
                           excluding lastID: String? = nil,
                           isEnabled: (String) -> Bool = { _ in true }) -> CrashScenario? {
        var choices = specs(for: era, category: .moment).filter { isEnabled($0.id) }
        if let lastID, choices.count > 1 {
            let withoutLast = choices.filter { $0.id != lastID }
            if !withoutLast.isEmpty { choices = withoutLast }
        }
        return draw(choices, using: &rng)
    }

    /// What goes wrong on the way back up, for the simulated restart.
    static func pickBootFailure(for era: CrashEra, using rng: inout CrashRNG,
                                isEnabled: (String) -> Bool = { _ in true }) -> CrashScenario? {
        draw(specs(for: era, category: .bootFailure).filter { isEnabled($0.id) }, using: &rng)
    }

    private static func draw(_ choices: [Spec], using rng: inout CrashRNG) -> CrashScenario? {
        guard !choices.isEmpty else { return nil }
        let total = choices.reduce(0) { $0 + $1.weight }
        var roll = Int.random(in: 0..<max(1, total), using: &rng)
        for spec in choices {
            roll -= spec.weight
            if roll < 0 { return spec.build(&rng) }
        }
        return choices[0].build(&rng)
    }
}
