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
        let build: (inout CrashRNG) -> CrashScenario
    }

    static let all: [Spec] = [

        Spec(id: "win9x-general-fault",
             title: "Blue screen — an error has occurred",
             eras: [.win95, .win98, .winMe],
             weight: 5) { rng in
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
             weight: 4) { rng in
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
             weight: 4) { rng in
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
             weight: 2) { rng in
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
             weight: 5) { rng in
            let screen = CrashCopy.ntStopScreen(using: &rng)
            // Same screen with the dump appended — and the same palette and typeface. Rebuilding
            // it without them fell back to the 9x defaults, so the blue changed shade halfway
            // through the crash.
            let withDump = TextScreen(grid: screen.grid, topRow: screen.topRow,
                                      leftColumn: screen.leftColumn,
                                      lines: screen.lines + CrashCopy.ntDumpLines(),
                                      font: screen.font, palette: screen.palette)
            return CrashScenario(id: "nt-stop-error",
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
        },
        Spec(id: "win9x-runtime-error",
             title: "Visual C++ Runtime Error",
             eras: [.win95, .win98, .winMe],
             weight: 4) { rng in
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
             weight: 3) { rng in
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
             weight: 3) { rng in
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
             weight: 3) { rng in
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
             weight: 3) { _ in
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
             weight: 4) { rng in
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
             weight: 5) { rng in
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
             weight: 5) { rng in
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
             weight: 4) { rng in
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
             weight: 4) { rng in
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
             weight: 3) { rng in
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
             weight: 4) { rng in
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
             weight: 5) { rng in
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
             weight: 5) { rng in
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
             weight: 5) { rng in
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
             weight: 5) { _ in
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
    ]

    static func specs(for era: CrashEra) -> [Spec] {
        all.filter { $0.eras.contains(era) }
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
            var rest = [Spec]()
            var probe = CrashRNG(seed: 1)
            for spec in choices where spec.build(&probe).kind != lastKind { rest.append(spec) }
            if !rest.isEmpty { choices = rest }
        }
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
