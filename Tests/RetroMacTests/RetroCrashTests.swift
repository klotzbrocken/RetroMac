import XCTest
import AppKit
@testable import RetroMac

/// The parts of Retro Crashes that can be checked without a screen.
///
/// The most valuable test in here is the last one: it reads the source of `Sources/Crashes/` and
/// fails if it ever learns to touch global system state. That is the property the whole feature
/// rests on — because nothing outside RetroMac is changed, killing the process is always a
/// complete recovery — and it is exactly the kind of property that erodes one convenient call at
/// a time unless something is watching.
final class RetroCrashTests: XCTestCase {

    // MARK: - Catalogue

    func testEveryScenarioHasAWayOut() {
        var rng = CrashRNG(seed: 7)
        for spec in CrashCatalogue.all {
            let scenario = spec.build(&rng)
            XCTAssertFalse(scenario.stages.isEmpty, "\(spec.id) has no stages")
            for (i, stage) in scenario.stages.enumerated() {
                let isLast = i == scenario.stages.count - 1
                // A stage that neither holds nor accepts a key would sit there until the
                // watchdog fired: a minute of blue screen and no way to dismiss it.
                XCTAssertTrue(stage.hold > 0 || !stage.recovery.isEmpty,
                              "\(spec.id) stage \(i) has no hold and no recovery")
                // A shell restart ends by itself: there is no screen to dismiss, the taskbar
                // simply comes back. So does a moment, a boot failure (the boot goes on), and a
                // countdown that restarts the machine when it runs out.
                let endsByItself = stage.surface == .shellRestart
                    || scenario.category == .moment || scenario.category == .bootFailure
                    || scenario.endsWithRestart
                if isLast, !endsByItself {
                    XCTAssertFalse(stage.recovery.isEmpty,
                                   "\(spec.id) ends on a stage the user cannot dismiss")
                }
            }
        }
    }

    func testIDsAreUniqueAndEveryEraHasSomething() {
        var seen = Set<String>()
        for spec in CrashCatalogue.all {
            XCTAssertTrue(seen.insert(spec.id).inserted, "duplicate scenario id \(spec.id)")
            XCTAssertFalse(spec.eras.isEmpty, "\(spec.id) belongs to no era")
            XCTAssertGreaterThan(spec.weight, 0, "\(spec.id) can never be picked")
        }
        for era in CrashEra.allCases {
            XCTAssertFalse(CrashCatalogue.specs(for: era).isEmpty,
                           "\(era.displayName) has no crashes")
        }
    }

    /// Windows 95, 98 and Me share their window chrome, so `RetroFrameTheme.key()` cannot tell
    /// them apart — which is why the era enum exists. Their catalogues differ, and that is the
    /// whole reason.
    func testMeHasTheProtectionErrorAndXPDoesNot() {
        let me = CrashCatalogue.specs(for: .winMe).map(\.id)
        let xp = CrashCatalogue.specs(for: .winXP).map(\.id)
        XCTAssertTrue(me.contains("winme-protection-error"))
        XCTAssertFalse(xp.contains("winme-protection-error"))
        XCTAssertTrue(xp.contains("nt-stop-error"))
        XCTAssertFalse(me.contains("nt-stop-error"))
    }

    /// Asking for a scenario by id must hand back that scenario. The Party-mode buttons and the
    /// QA hook both go through this, and a silent fallback to a random pick looks like the
    /// feature ignoring you.
    func testAskingForAScenarioByIDGivesThatScenario() {
        var rng = CrashRNG(seed: 1)
        for spec in CrashCatalogue.all {
            let found = CrashCatalogue.spec(id: spec.id)
            XCTAssertNotNil(found, "no spec for \(spec.id)")
            XCTAssertEqual(found?.build(&rng).id, spec.id)
        }
    }

    /// Pressing "Crash Now" twice must not give the same screen twice. The generator advances
    /// between picks, so this is really a test that nothing resets it.
    func testRepeatedPicksActuallyDiffer() {
        var rng = CrashRNG(seed: UInt64(UInt32.random(in: 0...UInt32.max)))
        var seen = Set<String>()
        for _ in 0..<25 {
            if let s = CrashCatalogue.pick(for: .win98, using: &rng) { seen.insert(s.id) }
        }
        XCTAssertGreaterThan(seen.count, 2,
                             "25 presses produced \(seen.count) different crashes: \(seen)")
    }

    /// "Surprise me" must not hand back what it just showed. With eight scenarios an honest
    /// weighted draw repeats about one time in eight, which is often enough to look broken.
    func testAPickNeverRepeatsTheOneBefore() {
        var rng = CrashRNG(seed: 77)
        var last: String?
        for _ in 0..<60 {
            guard let s = CrashCatalogue.pick(for: .win98, using: &rng, excluding: last) else {
                return XCTFail("nothing to pick")
            }
            XCTAssertNotEqual(s.id, last, "the same crash came round twice")
            last = s.id
        }
    }

    /// …unless there is genuinely nothing else, in which case it must still return something
    /// rather than nothing at all.
    func testASingleRemainingScenarioIsStillReturned() {
        var rng = CrashRNG(seed: 5)
        let only = "macos6-bomb"
        let picked = CrashCatalogue.pick(for: .macos6, using: &rng, excluding: only) { $0 == only }
        XCTAssertEqual(picked?.id, only)
    }

    /// Two blue screens in a row are two catalogue entries and one experience. The picker must
    /// vary the shape of the failure, not only its name — that is what "always the same crash"
    /// actually meant when the picker itself was demonstrably random.
    func testConsecutiveCrashesDoNotLookAlike() {
        var rng = CrashRNG(seed: 123)
        var lastID: String?
        var lastKind: CrashKind?
        for _ in 0..<40 {
            guard let s = CrashCatalogue.pick(for: .win98, using: &rng,
                                              excluding: lastID, avoiding: lastKind) else {
                return XCTFail("nothing to pick")
            }
            XCTAssertNotEqual(s.kind, lastKind, "\(s.id) looks like the one before it")
            lastID = s.id
            lastKind = s.kind
        }
    }

    /// The warning before the failure has to vary too. Every crash opening with the same
    /// graphics breakdown is the same crash, whatever the screen at the end says.
    func testTheBuildUpVaries() {
        let saved = (AppSettings.shared.crashFullSequence, AppSettings.shared.crashGlitches)
        defer {
            AppSettings.shared.crashFullSequence = saved.0
            AppSettings.shared.crashGlitches = saved.1
        }
        AppSettings.shared.crashFullSequence = true
        AppSettings.shared.crashGlitches = true

        var seen = Set<String>()
        for _ in 0..<40 { seen.insert(String(describing: CrashDirector.shared.chooseBuildUp())) }
        XCTAssertGreaterThan(seen.count, 2, "the build-up is always the same: \(seen)")

        // With the whole scene switched off there is nothing to vary: it must go straight to the
        // error rather than inventing a warning the user asked not to have.
        AppSettings.shared.crashFullSequence = false
        for _ in 0..<10 {
            XCTAssertEqual(CrashDirector.shared.chooseBuildUp(), .none)
        }
    }

    func testPrintCatalogueShape() {
        for era in CrashEra.allCases {
            let ids = CrashCatalogue.specs(for: era).map { "\($0.id)(\($0.weight))" }
            print("[catalogue] \(era.rawValue): \(ids.count) → \(ids.joined(separator: ", "))")
        }
    }

    func testPickIsDeterministicForASeed() {
        var a = CrashRNG(seed: 99), b = CrashRNG(seed: 99)
        let first = CrashCatalogue.pick(for: .win98, using: &a)
        let second = CrashCatalogue.pick(for: .win98, using: &b)
        XCTAssertEqual(first?.id, second?.id)
    }

    func testPickNeverReturnsSomethingTheUserSwitchedOff() {
        let all = Set(CrashCatalogue.specs(for: .win98).map(\.id))
        let allowed = "win9x-general-fault"
        var rng = CrashRNG(seed: 3)
        for _ in 0..<50 {
            let picked = CrashCatalogue.pick(for: .win98, using: &rng) { $0 == allowed }
            XCTAssertEqual(picked?.id, allowed)
        }
        XCTAssertTrue(all.count > 1, "the test is meaningless if there is only one scenario")
    }

    func testPickReturnsNothingWhenEverythingIsSwitchedOff() {
        var rng = CrashRNG(seed: 5)
        XCTAssertNil(CrashCatalogue.pick(for: .win98, using: &rng) { _ in false })
    }

    /// The screens that had no way back must restart, and the ones that offered a way back must
    /// keep it. Before this, everything ended on "any key returns", so the reboot — the whole
    /// second half of the sequence — was unreachable in practice: it needed Ctrl+Alt+Delete, and
    /// any other key quietly took you home first.
    func testTheScreensThatCouldNotReturnRestart() {
        var rng = CrashRNG(seed: 21)
        let restarts = ["nt-stop-error", "winme-protection-error", "macos6-bomb",
                        "macos9-bomb", "macosx-panic-console", "macosx-panic-curtain",
                        "win9x-safe-to-turn-off"]
        for id in restarts {
            let spec = CrashCatalogue.spec(id: id)
            let last = spec?.build(&rng).stages.last
            XCTAssertTrue(last?.recovery.contains(.restartsOnAnyKey) == true,
                          "\(id) should restart on any key")
        }
        // Windows 9x really did offer a way back, in its own words, so it keeps one.
        let ninetyX = CrashCatalogue.spec(id: "win9x-general-fault")?.build(&rng).stages.last
        XCTAssertTrue(ninetyX?.recovery.contains(.anyKey) == true)
        XCTAssertTrue(ninetyX?.recovery.contains(.ctrlAltDelete) == true)
        XCTAssertFalse(ninetyX?.recovery.contains(.restartsOnAnyKey) == true)
    }

    /// Every stage of one crash must be painted in the same colours. The Stop screen is built
    /// twice — once plain, once with the memory dump appended — and rebuilding it without its
    /// palette made the blue change shade halfway through.
    func testEveryStageOfAScenarioKeepsTheSamePalette() {
        var rng = CrashRNG(seed: 33)
        for spec in CrashCatalogue.all {
            let scenario = spec.build(&rng)
            var palettes = Set<String>(), fonts = Set<String>()
            for stage in scenario.stages {
                if case .textScreen(let screen) = stage.surface {
                    palettes.insert(String(describing: screen.palette))
                    fonts.insert(String(describing: screen.font))
                }
            }
            XCTAssertLessThanOrEqual(palettes.count, 1, "\(spec.id) changes colour mid-crash")
            XCTAssertLessThanOrEqual(fonts.count, 1, "\(spec.id) changes typeface mid-crash")
        }
    }

    /// Every era should offer more than one thing, or "random" is a fixed show.
    func testEveryEraHasSeveralDifferentFailures() {
        for era in CrashEra.allCases {
            XCTAssertGreaterThanOrEqual(CrashCatalogue.specs(for: era).count, 2,
                                        "\(era.displayName) has only one crash")
        }
    }

    /// The text that varies must actually vary. A "random" screen that prints the same address
    /// every time is a picture with extra steps.
    func testTheVaryingPartsVary() {
        var seen = Set<String>()
        for seed in 0..<40 {
            var rng = CrashRNG(seed: UInt64(seed))
            let screen = CrashCopy.win9xFatalException(using: &rng)
            seen.insert(screen.lines.map { line -> String in
                if case .text(let s) = line { return s }
                return ""
            }.joined())
        }
        XCTAssertGreaterThan(seen.count, 5, "the fatal exception screen barely changes")

        var apps = Set<String>()
        for seed in 0..<40 {
            var rng = CrashRNG(seed: UInt64(seed))
            apps.insert(CrashCopy.win9xFaultingPair(using: &rng).app)
        }
        XCTAssertGreaterThan(apps.count, 2, "always the same program at fault")
    }

    /// Each dialog must reach the painter its era used.
    func testDialogsCarryTheirEraStyle() {
        var rng = CrashRNG(seed: 4)
        XCTAssertEqual(CrashCopy.win9xIllegalOperationVaried(using: &rng).style, .win9x)
        XCTAssertEqual(CrashCopy.xpApplicationError(using: &rng).style, .winXP)
        XCTAssertEqual(CrashCopy.aquaApplicationQuit(using: &rng).style, .aqua)
    }

    /// "Unexpectedly quit" was not a system error: no bomb, and it returns to the desktop.
    func testAnApplicationQuitIsNotASystemError() {
        var rng = CrashRNG(seed: 8)
        let alert = CrashCopy.macApplicationQuit(style: .platinum, using: &rng)
        XCTAssertFalse(alert.showsBomb)
        XCTAssertNil(alert.restartButton)

        let spec = CrashCatalogue.spec(id: "macos9-application-quit")
        let last = spec?.build(&rng).stages.last
        XCTAssertTrue(last?.recovery.contains(.anyKey) == true)
        XCTAssertFalse(last?.recovery.contains(.restartsOnAnyKey) == true)
    }

    /// A dialog you are meant to click must be shown with a pointer. Hiding the cursor for the
    /// whole crash — which is right for a blue screen — made every dialog unclickable.
    func testOnlyTheScreensWithoutButtonsHideThePointer() {
        var rng = CrashRNG(seed: 12)
        for spec in CrashCatalogue.all {
            for stage in spec.build(&rng).stages {
                switch stage.surface {
                case .dialog(let d):
                    // Either a button or the close box: something must be clickable — unless
                    // the dialog is a clock, which ends itself.
                    XCTAssertTrue(!d.buttons.isEmpty || !d.report.isEmpty || d.countdownSeconds != nil,
                                  "\(spec.id) shows a dialog with nothing to do")
                case .macAlert(let a):
                    // "Initializing…" had no button either; it went away on its own.
                    XCTAssertTrue(!a.buttons.isEmpty || stage.hold > 0,
                                  "\(spec.id) shows an alert with no buttons")
                default:
                    break
                }
            }
        }
    }

    /// The dialogs that escalate must have a blue screen to escalate into, in their own era.
    func testEveryEscalatingDialogHasABlueScreenToBecome() {
        var rng = CrashRNG(seed: 17)
        for spec in CrashCatalogue.all {
            let scenario = spec.build(&rng)
            let escalates = scenario.stages.contains { stage in
                if case .dialog(let d) = stage.surface { return d.escalatesToBlueScreen }
                return false
            }
            guard escalates else { continue }
            for era in spec.eras {
                XCTAssertNotNil(CrashCatalogue.blueScreen(for: era, using: &rng),
                                "\(spec.id) escalates but \(era.displayName) has no blue screen")
            }
        }
    }

    /// The antivirus notifications are not crashes: nothing restarts, and the machine is fine.
    func testAVirusWarningNeitherRestartsNorEscalates() {
        var rng = CrashRNG(seed: 19)
        for id in ["win9x-virus-found", "xp-virus-found"] {
            let scenario = CrashCatalogue.spec(id: id)?.build(&rng)
            let stage = scenario?.stages.first
            if case .dialog(let d)? = stage?.surface {
                XCTAssertFalse(d.escalatesToBlueScreen, "\(id) should not take the machine down")
                XCTAssertNil(d.restartButton)
            } else {
                XCTFail("\(id) is not a dialog")
            }
            XCTAssertFalse(stage?.recovery.contains(.restartsOnAnyKey) == true)
        }
    }

    /// A full-screen surface must take the dialog with it. The escalation from an illegal
    /// operation into a blue screen showed both at once, because the dialog was a subview and
    /// the blue screen only replaced the layer behind it.
    func testAFullScreenSurfaceRemovesTheDialogOnTopOfIt() throws {
        let view = CrashView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        var rng = CrashRNG(seed: 2)
        let dialog = CrashCopy.win9xIllegalOperationVaried(using: &rng)
        let rendered = CrashDialogRenderer.dialog(dialog, expanded: false, scale: 2)
        view.showOverlay(rendered.image, over: nil, fill: false, buttons: rendered.buttons)
        XCTAssertFalse(view.subviews.isEmpty, "the dialog should be on screen")

        let blue = try XCTUnwrap(CrashRenderer.image(for: CrashCopy.win9xFatalException(using: &rng)))
        view.show(pixelImage: blue, stretchToFill: false)
        XCTAssertTrue(view.subviews.allSatisfy { $0 is NSTextField },
                      "the dialog is still on top of the blue screen")
    }

    // MARK: - Copy

    func testStopScreenFitsItsGrid() {
        var rng = CrashRNG(seed: 11)
        XCTAssertEqual(CrashCopy.ntStopScreen(using: &rng).grid, .vga80x30)
        XCTAssertEqual(CrashCopy.win9xGeneralFault(using: &rng).grid, .vga80x25)
    }

    /// 80 columns is not a suggestion: a longer line is simply cut off by the edge of the
    /// screen, and nobody would notice in review. Every text screen of every scenario, measured
    /// at its widest — the animated lines at 100.
    func testEveryTextScreenFitsItsGrid() {
        var rng = CrashRNG(seed: 13)
        for spec in CrashCatalogue.all {
            for stage in spec.build(&rng).stages {
                guard case .textScreen(let screen) = stage.surface else { continue }
                XCTAssertLessThanOrEqual(screen.topRow + screen.lines.count, screen.grid.rows,
                                         "\(spec.id) is taller than its grid")
                for line in screen.lines {
                    switch line {
                    case .centred, .inverted:
                        XCTAssertLessThanOrEqual(line.width, screen.grid.columns, "\(spec.id) too wide: \(line)")
                    default:
                        XCTAssertLessThanOrEqual(line.width + screen.leftColumn, screen.grid.columns,
                                                 "\(spec.id) too wide: \(line)")
                    }
                }
            }
        }
    }

    func testGridsAreTheRealVideoModes() {
        XCTAssertEqual(CrashGrid.vga80x25.pixelWidth, 720)
        XCTAssertEqual(CrashGrid.vga80x25.pixelHeight, 400)
        XCTAssertEqual(CrashGrid.vga80x30.pixelWidth, 640)
        XCTAssertEqual(CrashGrid.vga80x30.pixelHeight, 480)
    }

    // MARK: - Scheduling

    func testIntensityMathIsSane() {
        for level in CrashScheduler.Intensity.allCases {
            switch level {
            case .off, .manual:
                XCTAssertNil(level.meanInterval)
                XCTAssertEqual(level.dailyBudget, 0)
            default:
                let mean = try? XCTUnwrap(level.meanInterval)
                XCTAssertNotNil(mean)
                // A per-minute Bernoulli trial only behaves like "about once per mean" while the
                // probability stays small.
                let p = 60.0 / (level.meanInterval ?? 1)
                XCTAssertLessThan(p, 0.1, "\(level.rawValue) fires too eagerly per tick")
                XCTAssertGreaterThan(level.dailyBudget, 0)
                // The gap has to be shorter than the mean, or the budget could never be spent.
                XCTAssertLessThan(level.minimumGap, level.meanInterval ?? 0)
            }
        }
    }

    /// The demo setting has to be able to fire during a demo.
    ///
    /// It could not. Somebody who picks "chaotic" then sits and watches stops touching the
    /// machine, their idle time passes the two-minute cap inside `plausibleMoment`, and from
    /// then on every single tick fails that test — while the settings tab cheerfully reads
    /// "Armed". Ten minutes of launch silence on top of that made it look dead for good.
    func testTheDemoLevelDoesNotWaitForTheUserToFidget() {
        XCTAssertFalse(CrashScheduler.Intensity.chaotic.waitsForAQuietMoment)
        XCTAssertLessThanOrEqual(CrashScheduler.Intensity.chaotic.warmUp, 60)
        // Every other level keeps both, because for those the point IS to catch a working day.
        for level in CrashScheduler.Intensity.allCases where level != .chaotic {
            XCTAssertTrue(level.waitsForAQuietMoment, "\(level.rawValue) should wait for a quiet moment")
            XCTAssertEqual(level.warmUp, 10 * 60, "\(level.rawValue) should keep the ten-minute warm-up")
        }
    }

    func testRarerLevelsAreActuallyRarer() {
        let order: [CrashScheduler.Intensity] = [.chaotic, .authentic, .rare, .veryRare]
        let means = order.compactMap { $0.meanInterval }
        XCTAssertEqual(means.count, order.count)
        XCTAssertEqual(means, means.sorted(), "the intensity ladder is out of order")
    }

    // MARK: - The scene

    /// A black capture must be recognised as a failed one. `CGPreflightScreenCaptureAccess()`
    /// can answer yes while `CGDisplayCreateImage` still returns a uniform black frame — a stale
    /// permission after a rebuild does exactly that — and a "frozen desktop" that is a black
    /// rectangle is worse than no freeze at all.
    func testABlackCaptureIsTreatedAsNoCapture() throws {
        let black = try XCTUnwrap(solid(.black))
        XCTAssertTrue(DesktopFreeze.looksBlank(black))
        let pattern = try XCTUnwrap(bars())
        XCTAssertFalse(DesktopFreeze.looksBlank(pattern))
    }

    /// Redraw trails were a consequence of drawing straight into the frame buffer. Windows gained
    /// a compositor in Vista and Mac OS X always had one, so those eras must not smear.
    func testOnlyPreCompositorErasSmear() {
        for era in [CrashEra.win95, .win98, .winMe, .winXP, .macos6, .macos9] {
            XCTAssertTrue(era.hasRedrawTrails, "\(era.displayName) should smear")
        }
        for era in [CrashEra.win7, .macosxAqua, .macosxModern] {
            XCTAssertFalse(era.hasRedrawTrails, "\(era.displayName) had a compositor")
        }
    }

    /// A palette can only be corrupted where there is one.
    func testOnlyIndexedColourErasLosePalette() {
        XCTAssertTrue(CrashEra.win98.hasIndexedColour)
        XCTAssertTrue(CrashEra.macos9.hasIndexedColour)
        XCTAssertFalse(CrashEra.winXP.hasIndexedColour)
        XCTAssertFalse(CrashEra.macosxModern.hasIndexedColour)
    }

    func testGlitchReturnsADifferentPictureOfTheSameSize() throws {
        let source = try XCTUnwrap(bars())
        let broken = try XCTUnwrap(CrashGlitch.corrupt(source, era: .win98, severity: 1.0, seed: 3))
        XCTAssertEqual(broken.width, source.width)
        XCTAssertEqual(broken.height, source.height)
        XCTAssertNotEqual(pixels(broken), pixels(source), "the glitch changed nothing")
    }

    func testGlitchIsDeterministicForASeed() throws {
        let source = try XCTUnwrap(bars())
        let a = try XCTUnwrap(CrashGlitch.corrupt(source, era: .winXP, severity: 0.7, seed: 11))
        let b = try XCTUnwrap(CrashGlitch.corrupt(source, era: .winXP, severity: 0.7, seed: 11))
        XCTAssertEqual(pixels(a), pixels(b))
    }

    /// The drive sound is generated, not shipped: no sample of somebody else's recording, and it
    /// can follow the length of the scene.
    func testDriveSoundIsARealWAVWithSomethingInIt() throws {
        let data = try XCTUnwrap(CrashSound.driveFailureWAV(seconds: 2))
        XCTAssertEqual(String(bytes: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(bytes: data.dropFirst(8).prefix(4), encoding: .ascii), "WAVE")
        // 22050 Hz, 16 bit, mono, 2 seconds, plus a 44-byte header.
        XCTAssertEqual(data.count, 44 + Int(2 * 22_050) * 2)
        let loudest = data.dropFirst(44).max() ?? 0
        XCTAssertGreaterThan(loudest, 0, "the buffer is silent")
    }

    // MARK: - Categories

    /// The picker reads the shape off the spec instead of building the scenario to look; the
    /// two must not drift apart.
    func testDeclaredKindMatchesBuiltKind() {
        var rng = CrashRNG(seed: 31)
        for spec in CrashCatalogue.all {
            let built = spec.build(&rng)
            XCTAssertEqual(built.kind, spec.kind, "\(spec.id) declares \(spec.kind), builds \(built.kind)")
            XCTAssertEqual(built.category, spec.category, "\(spec.id) declares \(spec.category), builds \(built.category)")
        }
    }

    /// Boot failures, aftermaths and moments have their own doors; the main draw must never
    /// open one of them.
    func testOnlyFailuresAreEverPickedAsFailures() {
        var rng = CrashRNG(seed: 41)
        for era in CrashEra.allCases {
            for _ in 0..<200 {
                guard let s = CrashCatalogue.pick(for: era, using: &rng) else { continue }
                XCTAssertEqual(s.category, .failure, "\(s.id) came out of the main draw")
            }
            for _ in 0..<100 {
                if let m = CrashCatalogue.pickMoment(for: era, using: &rng) {
                    XCTAssertEqual(m.category, .moment, "\(m.id) came out of the moment draw")
                }
                if let b = CrashCatalogue.pickBootFailure(for: era, using: &rng) {
                    XCTAssertEqual(b.category, .bootFailure, "\(b.id) came out of the boot draw")
                }
            }
        }
    }

    func testEveryEraCanFailToBoot() {
        for era in CrashEra.allCases {
            XCTAssertFalse(CrashCatalogue.specs(for: era, category: .bootFailure).isEmpty,
                           "\(era.displayName) always comes straight back")
            XCTAssertFalse(CrashCatalogue.specs(for: era, category: .moment).isEmpty,
                           "\(era.displayName) has no moments")
        }
    }

    /// A boot failure sits inside the watchdog's slack, which is what makes the slack enough.
    func testBootFailuresFitTheirCeiling() {
        var rng = CrashRNG(seed: 51)
        for spec in CrashCatalogue.all where spec.category == .bootFailure {
            for _ in 0..<10 {
                XCTAssertLessThanOrEqual(spec.build(&rng).totalHold, 25, "\(spec.id) takes too long to boot")
            }
        }
    }

    /// A moment asks nothing of the user: every stage holds, none waits, and it is over in
    /// seconds.
    func testMomentsEndByThemselves() {
        var rng = CrashRNG(seed: 61)
        for spec in CrashCatalogue.all where spec.category == .moment {
            let scenario = spec.build(&rng)
            XCTAssertLessThanOrEqual(scenario.totalHold, 10, "\(spec.id) is not a moment")
            for stage in scenario.stages {
                XCTAssertGreaterThan(stage.hold, 0, "\(spec.id) has a stage with no clock")
                XCTAssertTrue(stage.recovery.isEmpty, "\(spec.id) waits for a key")
            }
        }
    }

    func testMomentIntervalsAreShorterThanFailures() {
        for level in CrashScheduler.Intensity.allCases {
            guard let mean = level.meanInterval, let momentMean = level.momentMeanInterval else { continue }
            XCTAssertLessThan(momentMean, mean)
            XCTAssertLessThan(level.momentMinimumGap, level.minimumGap)
            XCTAssertLessThan(60.0 / momentMean, 0.2, "\(level.rawValue) fires moments too eagerly")
        }
    }

    /// The picture can only lose sync where there was a beam.
    func testOnlyCRTErasRoll() {
        XCTAssertTrue(CrashEra.win98.hasCRT)
        XCTAssertTrue(CrashEra.macosxAqua.hasCRT)
        XCTAssertFalse(CrashEra.win7.hasCRT)
        XCTAssertFalse(CrashEra.macosxModern.hasCRT)
        let rolls = CrashCatalogue.spec(id: "moment-hsync-roll")?.eras ?? []
        for era in CrashEra.allCases {
            XCTAssertEqual(rolls.contains(era), era.hasCRT, "\(era.displayName) rolls: \(rolls.contains(era))")
        }
    }

    /// Every sequel names a scene that exists, is a sequel, and belongs to the same era.
    func testAftermathTargetsExist() {
        var rng = CrashRNG(seed: 71)
        var found = 0
        for spec in CrashCatalogue.all {
            guard let aftermath = spec.build(&rng).aftermath else { continue }
            found += 1
            let target = CrashCatalogue.spec(id: aftermath.id)
            XCTAssertNotNil(target, "\(spec.id) has a sequel that does not exist")
            XCTAssertEqual(target?.category, .aftermath)
            XCTAssertFalse(target?.eras.isDisjoint(with: spec.eras) ?? true,
                           "\(spec.id) has a sequel from another era")
            XCTAssertGreaterThan(aftermath.delay.lowerBound, 0)
        }
        XCTAssertGreaterThan(found, 0, "no scene has a sequel")
    }

    /// The countdown dialog restarts when it runs out, and holds for exactly as long as it says.
    func testCountdownDialogEndsInARestart() throws {
        var rng = CrashRNG(seed: 81)
        let scenario = try XCTUnwrap(CrashCatalogue.spec(id: "xp-rpc-countdown")?.build(&rng))
        XCTAssertTrue(scenario.endsWithRestart)
        let stage = try XCTUnwrap(scenario.stages.first)
        guard case .dialog(let d) = stage.surface else { return XCTFail("not a dialog") }
        let seconds = try XCTUnwrap(d.countdownSeconds)
        XCTAssertEqual(stage.hold, TimeInterval(seconds + 1))
        XCTAssertTrue(d.body.contains { $0.contains(ErrorDialog.countdownToken) })
        // And the clock is really put into the words.
        let rendered = CrashDialogRenderer.dialog(d, expanded: false, scale: 1, countdown: 59)
        XCTAssertNotNil(rendered.image)
    }

    /// A "next" button must be one of the dialog's buttons, and never on the last stage — there
    /// is nothing after the last stage to go to.
    func testNextButtonsAreRealAndLeadSomewhere() {
        var rng = CrashRNG(seed: 91)
        for spec in CrashCatalogue.all {
            let stages = spec.build(&rng).stages
            for (i, stage) in stages.enumerated() {
                var next: String?, buttons: [String] = []
                if case .dialog(let d) = stage.surface { next = d.nextButton; buttons = d.buttons }
                if case .macAlert(let a) = stage.surface { next = a.nextButton; buttons = a.buttons }
                guard let next else { continue }
                XCTAssertTrue(buttons.contains(next), "\(spec.id) stage \(i): \(next) is not a button")
                XCTAssertLessThan(i, stages.count - 1, "\(spec.id) ends on a stage with a next button")
            }
        }
    }

    /// The Zip drive is opened from the desktop, never drawn, and only on Windows — and every
    /// Windows theme that can crash has one on its desktop.
    func testTheZipDriveIsAWindowsThing() throws {
        var rng = CrashRNG(seed: 101)
        let spec = try XCTUnwrap(CrashCatalogue.spec(id: "win-zip-click-of-death"))
        XCTAssertEqual(spec.category, .onDemand)
        let scenario = spec.build(&rng)
        for era in spec.eras {
            XCTAssertTrue(era.displayName.hasPrefix("Windows"), "\(era.displayName) never had a Zip drive")
        }
        // The first thing you see is the drive reading, with the clicking.
        XCTAssertEqual(scenario.stages.first?.sound, .zipClick)

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for theme in ["Windows95", "Windows98", "WindowsMe", "WindowsXP"] {
            let url = root.appendingPathComponent("Resources/Themes/\(theme).retromactheme/theme.json")
            let data = try Data(contentsOf: url)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let icons = try XCTUnwrap(json["desktopIcons"] as? [[String: Any]])
            XCTAssertEqual(icons.filter { $0["type"] as? String == "zipdrive" }.count, 1,
                           "\(theme) should have exactly one Zip drive on its desktop")
        }
    }

    // MARK: - Rendering

    func testProgressBarFillsWithTheCounter() throws {
        let screen = TextScreen(grid: .vga80x25, topRow: 2, leftColumn: 2, lines: [
            .progressBar(prefix: "[", width: 40, suffix: "]"),
            .percent(prefix: "", suffix: "% complete"),
        ], palette: .scandisk)
        let a = try XCTUnwrap(CrashRenderer.image(for: screen, counter: 0))
        let b = try XCTUnwrap(CrashRenderer.image(for: screen, counter: 50))
        let c = try XCTUnwrap(CrashRenderer.image(for: screen, counter: 100))
        XCTAssertNotEqual(pixels(a), pixels(b))
        XCTAssertNotEqual(pixels(b), pixels(c))
    }

    func testBlinkFramesDiffer() throws {
        let screen = CrashCopy.bootNTLDRMissing()
        XCTAssertTrue(screen.blinks)
        XCTAssertFalse(screen.isAnimated)
        let on = try XCTUnwrap(CrashRenderer.image(for: screen, blinkOn: true))
        let off = try XCTUnwrap(CrashRenderer.image(for: screen, blinkOn: false))
        XCTAssertNotEqual(pixels(on), pixels(off))
    }

    func testPaletteColoursAreDistinct() {
        for palette in [ScreenPalette.win9x, .nt, .console, .dos, .orange9x, .scandisk] {
            XCTAssertNotEqual(CrashPalette.background(palette), CrashPalette.foreground(palette),
                              "\(palette) is invisible")
        }
    }

    func testBootGlyphsDraw() {
        for glyph in [BootGlyph.sadMac(codes: "0000000F 0000000A"), .questionFolder, .prohibitory] {
            let image = CrashRenderer.bootGlyphImage(glyph, blinkOn: true, size: NSSize(width: 640, height: 480))
            XCTAssertEqual(image.size.width, 640)
        }
        let on = CrashRenderer.bootGlyphImage(.questionFolder, blinkOn: true, size: NSSize(width: 320, height: 240))
        let off = CrashRenderer.bootGlyphImage(.questionFolder, blinkOn: false, size: NSSize(width: 320, height: 240))
        XCTAssertNotEqual(on.tiffRepresentation, off.tiffRepresentation, "the question mark does not blink")
    }

    func testBusyPointersHaveFrames() {
        XCTAssertEqual(CrashRenderer.beachballFrames(scale: 2).count, 8)
        XCTAssertEqual(CrashRenderer.watchCursorFrames(scale: 2).count, 2)
        XCTAssertEqual(CrashRenderer.hourglassFrames(scale: 2).count, 2)
        XCTAssertEqual(CrashRenderer.busyRingFrames(scale: 2).count, 8)
    }

    func testTheOtherSoundsAreRealWAVs() throws {
        for data in [try XCTUnwrap(CrashSound.zipClickWAV(seconds: 2)),
                     try XCTUnwrap(CrashSound.floppySeekWAV(seconds: 2)),
                     try XCTUnwrap(CrashSound.clickWAV())] {
            XCTAssertEqual(String(bytes: data.prefix(4), encoding: .ascii), "RIFF")
            XCTAssertGreaterThan(data.dropFirst(44).max() ?? 0, 0, "the buffer is silent")
        }
        XCTAssertEqual(try XCTUnwrap(CrashSound.zipClickWAV(seconds: 2)).count, 44 + Int(2 * 22_050) * 2)
    }

    // MARK: - Helpers

    private func solid(_ colour: NSColor) -> CGImage? {
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        ctx?.setFillColor(colour.cgColor)
        ctx?.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return ctx?.makeImage()
    }

    private func bars() -> CGImage? {
        let ctx = CGContext(data: nil, width: 256, height: 128, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        let colours: [NSColor] = [.white, .yellow, .cyan, .green, .magenta, .red, .blue, .black]
        for (i, c) in colours.enumerated() {
            ctx?.setFillColor(c.cgColor)
            ctx?.fill(CGRect(x: CGFloat(i) * 32, y: 0, width: 32, height: 128))
        }
        return ctx?.makeImage()
    }

    private func pixels(_ image: CGImage) -> Data {
        let w = image.width, h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return Data(buffer)
    }

    // MARK: - The invariant

    /// Retro Crashes must never change anything outside RetroMac's own windows. If this test
    /// fails, do not relax it: the call it caught is the reason a user could end up stuck.
    func testCrashCodeNeverTouchesGlobalSystemState() throws {
        let forbidden = [
            "CGEventTap",            // would swallow input system-wide
            "AXIsProcessTrusted",    // Accessibility, for the same reason
            "presentationOptions",   // hiding the menu bar and Dock is a global change
            "SystemUIHelper",        // ditto, via AppleScript
            "SystemTweaksAdapter",
            "CGDisplayCapture",      // taking the display away from the window server
            "NSAppleScript",         // scripting other apps
            "terminate(",            // quitting anything, including ourselves
            // The CALL shapes, not the bare words: the period screens say "shutdown" in their
            // own text ("This shutdown was initiated by…", "It's now safe to…"), and a colour
            // is named after one. A string that contains the word turns nothing off.
            "shutdown(", "reboot(", "kAEShutDown", "kAERestart", "SMShutdown", "SMRestart",
        ]
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // RetroMacTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/Crashes")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "no sources found at \(dir.path)")

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            // Comments talk about these on purpose — the file header explains why they are not
            // used — so only real code counts.
            let code = source.split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            for symbol in forbidden {
                XCTAssertFalse(code.contains(symbol),
                               "\(file.lastPathComponent) uses \(symbol) — see the invariant in CrashDirector.swift")
            }
        }
    }
}
