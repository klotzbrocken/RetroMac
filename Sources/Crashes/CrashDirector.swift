import AppKit

/// Runs a simulated crash from the first stutter to the desktop coming back.
///
/// THE INVARIANT THIS FEATURE RESTS ON: **nothing outside RetroMac is touched.** No application
/// is quit, no document closed, no restart issued. The menu bar and Dock are not hidden, the
/// display is not captured, presentation options are not changed, no event tap is installed and
/// no Accessibility permission is asked for. All that happens is that RetroMac puts its own
/// windows on the screen and takes them away again.
///
/// That is not a stylistic preference, it is the recovery story. Because no global state is
/// changed, killing the process — Force Quit, `kill -9`, a genuine crash of our own — is itself a
/// complete repair: the windows die with it and the desktop underneath was never altered. Every
/// other safety net here (the idempotent teardown, the session that closes its own windows when
/// deallocated, the watchdog, the abort on losing focus) exists to make the normal case pleasant.
/// This invariant is what makes the worst case survivable. Do not trade it away.
final class CrashDirector {

    static let shared = CrashDirector()
    private init() {}

    // MARK: - State

    enum Source { case random, manual, hotkey, aftermath }
    enum AbortReason: String {
        case escape, lostActivation, watchdog, notKey, willSleep, screensChanged, themeStopped, appQuit, finished
    }
    private enum State: Equatable {
        case idle
        case countdown
        /// The pointer starts falling behind while the machine is still "working".
        case stuttering
        /// Nothing answers any more; the drive is hunting.
        case frozen
        case failure(Int)
        case blackout
        case booting
        /// The desktop is back, held as a still for a beat so the return reads as a return.
        case restored
        case tearingDown
    }

    private var state: State = .idle
    private var session: CrashSession?
    private var scenario: CrashScenario?
    /// What is on screen while the machine fails to come back up. Kept apart from `scenario`
    /// so the failure that caused the restart keeps its aftermath.
    private var bootScenario: CrashScenario?
    private var active: CrashScenario? { bootScenario ?? scenario }
    private var stills: [CGImage?] = []
    private var stageTimer: Timer?
    private var counterTimer: Timer?
    private var blinkTimer: Timer?
    private var momentTimer: Timer?
    private var watchdog: Timer?
    private var liveness: Timer?
    private var countdownTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// Kept apart from `observers` because they were vended by a DIFFERENT notification centre.
    /// Handing a workspace token to `NotificationCenter.default.removeObserver` is a silent
    /// no-op, so the sleep observer used to survive every teardown and pile up one per crash.
    private var workspaceObservers: [NSObjectProtocol] = []
    private var armedForResign = false
    private var dumpCounter = 0
    private var blinkOn = true
    /// The clock in a dialog that counts down, in seconds left.
    private var dialogCountdown = 0
    /// Where the counter is stalled, if it is: the end of the stall.
    private var stallUntil: Date?
    /// What was shown last, so the next pick can avoid it — by name and by shape.
    private var lastScenarioID: String?
    private var lastKind: CrashKind?
    private var lastMomentID: String?
    private var cursorTimer: Timer?
    /// Separate from `stageTimer`: the build-up runs its own clock, because the glitch pass
    /// schedules against the stage timer and would otherwise cancel the end of the stutter.
    private var stutterTimer: Timer?
    private var cursorHidden = false
    private var glitchTimer: Timer?
    private var fakeCursor: NSPoint = .zero
    private var stutterStarted = Date()
    /// Whether the 9x dialog's "Details >>" well is open.
    private var dialogExpanded = false
    /// Whether the taskbar and the desktop icons are away for a shell restart, so teardown
    /// knows to put them back.
    private var shellHidden = false
    /// Whether this run went through the simulated restart — the aftermath only follows a
    /// machine that came back.
    private var didRestart = false
    private var rng = CrashRNG(seed: UInt64(UInt32.random(in: 0...UInt32.max)))

    var isStaging: Bool { state != .idle }

    /// The absolute ceiling on one simulation, never reset by a stage change. A user who walks
    /// away mid-crash comes back to their desktop, not to a blue screen. The scenario's own
    /// holds are added on top, because a countdown that runs for a minute is a minute long.
    private static let watchdogSeconds: TimeInterval = 60
    /// Room for a boot failure and the boot screen after the last stage.
    private static let watchdogSlack: TimeInterval = 25

    // MARK: - Trigger

    /// Start a crash. `scenario` nil means "pick one for the current theme".
    @discardableResult
    func trigger(_ chosen: CrashScenario? = nil, source: Source = .manual,
                 countdown: Int = 0) -> Bool {
        guard state == .idle else { return false }
        guard let era = CrashEra.current() else { return false }
        let settings = AppSettings.shared
        let scenario = chosen ?? CrashCatalogue.pick(for: era, using: &rng,
                                                     excluding: lastScenarioID,
                                                     avoiding: lastKind) {
            !settings.crashDisabledScenarios.contains($0)
        }
        guard let scenario else { return false }
        self.scenario = scenario
        bootScenario = nil
        didRestart = false
        switch scenario.category {
        case .failure:
            lastScenarioID = scenario.id
            lastKind = scenario.kind
        case .moment:
            lastMomentID = scenario.id
        case .aftermath, .bootFailure, .onDemand:
            break
        }

        print("[Crash] \(scenario.id) on \(era.displayName), source=\(source)")
        if countdown > 0, scenario.category == .failure {
            beginCountdown(seconds: countdown)
        } else {
            begin()
        }
        return true
    }

    private func beginCountdown(seconds: Int) {
        state = .countdown
        var left = seconds
        installObservers()
        armWatchdog(extra: TimeInterval(seconds))
        CountdownHUD.shared.show(seconds: left)
        countdownTimer = schedule(every: 1.0) { [weak self] in
            left -= 1
            if left <= 0 {
                self?.countdownTimer?.invalidate()
                CountdownHUD.shared.hide()
                self?.begin()
            } else {
                CountdownHUD.shared.show(seconds: left)
            }
        }
    }

    private func begin() {
        guard let scenario else { teardown(.finished); return }
        if state != .countdown { installObservers() }
        armWatchdog(extra: scenario.totalHold + Self.watchdogSlack)

        // Capture first, present second: whatever is on screen must not include our own overlay.
        stills = DesktopFreeze.capture()

        let session = CrashSession()
        self.session = session
        // No still (no Screen Recording, or a capture that came back black): the windowed
        // errors go over the live desktop. It is not frozen, but it is the user's.
        session.setShowsLiveDesktop(!stills.contains(where: { $0 != nil }))
        session.present()
        armedForResign = false
        // The activation churn of presenting counts as a resign on some paths, so the abort-on-
        // focus-loss guard only goes live once the dust has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.armedForResign = true }

        armLiveness()

        showBadge()

        guard stills.contains(where: { $0 != nil }) else {
            // No still, no illusion of a freeze — cut straight to the failure rather than fake it.
            enterStage(0)
            return
        }
        showStills()

        // Only a failure gets the warning. A moment IS the warning with nothing after it, a boot
        // failure happens on a black screen, an aftermath arrives on a machine that has just
        // come back and is working fine, and the Zip drive answers the double-click at once.
        let plan = scenario.category == .failure ? chooseBuildUp() : .none
        print("[Crash] build-up: \(plan)")
        runBuildUp(plan)
    }

    // MARK: - The build-up

    /// Five or six seconds in which the machine slowly stops answering: the pointer falls behind,
    /// then sticks, while the drive spins up and starts hunting. Nothing is actually blocked —
    /// the real pointer is only hidden, never moved, and the real desktop underneath is live.
    /// How a crash announces itself. Not every failure gave you warning, and the ones that did
    /// did not all give the same warning — a machine that dies while the pointer is still moving
    /// is a different memory from one whose picture falls apart first. Picking between these is
    /// what stops every crash from being the same performance with different words at the end.
    enum BuildUp: CaseIterable {
        /// Straight to the error. Plenty of failures arrived with no warning at all.
        case none
        /// The pointer falls behind and sticks, then the error.
        case pointer
        /// The picture comes apart, then the error.
        case glitch
        /// The pointer goes first, then the picture. The full performance.
        case pointerThenGlitch
    }

    func chooseBuildUp() -> BuildUp {
        guard AppSettings.shared.crashFullSequence else { return .none }
        let glitches = AppSettings.shared.crashGlitches
        // Weighted by hand rather than uniformly: "no warning" belongs in the mix but should not
        // dominate, and the full performance is the one worth seeing most often.
        var bag: [BuildUp] = [.none, .pointer, .pointer]
        if glitches { bag += [.glitch, .glitch, .pointerThenGlitch, .pointerThenGlitch, .pointerThenGlitch] }
        return bag.randomElement(using: &rng) ?? .none
    }

    /// Run the chosen warning, then hand over to the failure itself. Everything the build-up
    /// started is stopped in `finishBuildUp` before the error appears — the glitch pass used to
    /// outlive it and paint over the blue screen, which is why every crash looked like the same
    /// graphics fault with something flickering underneath.
    private func runBuildUp(_ plan: BuildUp) {
        switch plan {
        case .none:
            let hold = max(0.35, scenario?.freezeHold ?? 0.8)
            state = .frozen
            stutterTimer = schedule(after: hold) { [weak self] in self?.finishBuildUp() }

        case .pointer:
            let seconds = Double.random(in: 4.0...6.0, using: &rng)
            beginStutter(seconds: seconds)
            stutterTimer = schedule(after: seconds) { [weak self] in self?.finishBuildUp() }

        case .glitch:
            let seconds = Double.random(in: 2.4...3.6, using: &rng)
            state = .frozen
            CrashSound.shared.playDriveFailure(seconds: seconds + 1.0)
            beginGlitches(over: seconds)
            stutterTimer = schedule(after: seconds) { [weak self] in self?.finishBuildUp() }

        case .pointerThenGlitch:
            let pointer = Double.random(in: 3.0...4.5, using: &rng)
            let glitch = Double.random(in: 2.0...3.0, using: &rng)
            beginStutter(seconds: pointer + glitch)
            // The picture starts breaking only once the pointer has been struggling for a while.
            stageTimer = schedule(after: pointer) { [weak self] in
                self?.beginGlitches(over: glitch)
            }
            stutterTimer = schedule(after: pointer + glitch) { [weak self] in self?.finishBuildUp() }
        }
    }

    /// Stop everything the warning started, then show the failure. This is the one place allowed
    /// to end the build-up, so nothing it started can still be drawing afterwards.
    private func finishBuildUp() {
        cursorTimer?.invalidate();  cursorTimer = nil
        glitchTimer?.invalidate();  glitchTimer = nil
        stageTimer?.invalidate();   stageTimer = nil
        stutterTimer?.invalidate(); stutterTimer = nil
        blinkTimer?.invalidate();   blinkTimer = nil
        session?.mainView?.hideFakeCursor()
        state = .frozen
        enterStage(0)
    }

    /// The pointer falling behind. Runs for `seconds`; the caller decides what happens after.
    private func beginStutter(seconds: TimeInterval) {
        state = .stuttering
        stutterStarted = Date()
        fakeCursor = mouseInMainView()
        if !cursorHidden { NSCursor.hide(); cursorHidden = true }
        CrashSound.shared.playDriveFailure(seconds: seconds + 1.5)

        cursorTimer = schedule(every: 1.0 / 30.0) { [weak self] in
            guard let self, let view = self.session?.mainView else { return }
            let progress = min(1, Date().timeIntervalSince(self.stutterStarted) / seconds)
            let target = self.mouseInMainView()
            // Follow closely at first, then in fewer and coarser steps, then hardly at all.
            let follow = max(0.02, 0.55 * (1 - progress))
            // Occasional dead beats: the pointer stops, then jumps to where the hand went.
            let stalled = Double.random(in: 0..<1, using: &self.rng) < progress * 0.55
            if !stalled {
                self.fakeCursor.x += (target.x - self.fakeCursor.x) * follow
                self.fakeCursor.y += (target.y - self.fakeCursor.y) * follow
            }
            view.showFakeCursor(at: self.fakeCursor)
        }
    }

    /// The picture falls apart in steps while the pointer is dying, so the error screen arrives
    /// at the end of a decline rather than out of nowhere.
    private func beginGlitches(over seconds: TimeInterval) {
        guard let era = CrashEra.current() else { return }
        var step = 0
        // Four steps inside the time given, with the last one landing before the end rather than
        // on it: a tick that fires at the same instant as the failure is a race, and it used to
        // win it — the glitched desktop was drawn straight over the blue screen.
        glitchTimer = schedule(every: seconds / 5) { [weak self] in
            guard let self else { return }
            step += 1
            let severity = min(1.0, Double(step) / 4.0)
            for (i, view) in (self.session?.views ?? []).enumerated() {
                guard i < self.stills.count, let still = self.stills[i] else { continue }
                let seed = UInt64(step * 7919 + i)
                if let broken = CrashGlitch.corrupt(still, era: era, severity: severity, seed: seed) {
                    view.show(fullBleed: broken)
                }
            }
            if step >= 4 { self.glitchTimer?.invalidate(); self.glitchTimer = nil }
            // Belt and braces: once the failure is on screen this must not paint over it.
            if case .failure = self.state { self.glitchTimer?.invalidate(); self.glitchTimer = nil }
        }
    }

    private func mouseInMainView() -> NSPoint {
        let global = NSEvent.mouseLocation
        guard let screen = NSScreen.main else { return global }
        return NSPoint(x: global.x - screen.frame.minX, y: global.y - screen.frame.minY)
    }

    /// The shell dying and coming back. No overlay: the taskbar and the desktop icons are simply
    /// taken away for a few seconds and then put back, which is exactly what Explorer restarting
    /// looked like — and it touches nothing but RetroMac's own windows.
    private func runShellRestart(seconds: TimeInterval) {
        session?.close()
        session = nil
        shellHidden = true
        DockController.shared.setSuspendedForCrash(true)
        DesktopIconsController.shared.hide()

        stageTimer = schedule(after: seconds) { [weak self] in
            guard let self else { return }
            self.restoreShell()
            self.teardown(.finished)
        }
    }

    private func restoreShell() {
        guard shellHidden else { return }
        shellHidden = false
        DockController.shared.setSuspendedForCrash(false)
        DesktopIconsController.shared.update()
    }

    /// What happens when a dialog is dismissed. A program that had just performed an illegal
    /// operation quite often took the machine with it a moment later, so some of these dialogs
    /// roll for it rather than always politely returning you to the desktop.
    private func closeDialog(_ stage: CrashStage) {
        var escalates = false
        if case .dialog(let dialog) = stage.surface { escalates = dialog.escalatesToBlueScreen }
        guard escalates, Double.random(in: 0..<1, using: &rng) < 0.35,
              let era = CrashEra.current(),
              let blue = CrashCatalogue.blueScreen(for: era, using: &rng) else {
            teardown(.finished)
            return
        }
        scenario = blue
        enterStage(0)
    }

    private func showBadge() {
        let on = AppSettings.shared.crashShowBadge
        for view in session?.views ?? [] { view.showBadge(on, name: active?.title) }
    }

    // MARK: - Stages

    private func enterStage(_ index: Int) {
        // Nothing from the warning may still be drawing once a failure is up.
        cursorTimer?.invalidate(); cursorTimer = nil
        glitchTimer?.invalidate(); glitchTimer = nil
        blinkTimer?.invalidate(); blinkTimer = nil
        momentTimer?.invalidate(); momentTimer = nil
        counterTimer?.invalidate(); counterTimer = nil
        stageTimer?.invalidate(); stageTimer = nil

        guard let scenario = active else { teardown(.finished); return }
        guard index < scenario.stages.count else { endOfStages(scenario); return }
        state = .failure(index)
        let stage = scenario.stages[index]
        print("[Crash] stage \(index + 1)/\(scenario.stages.count) of \(scenario.id): \(Self.describe(stage))")
        dumpCounter = 0
        blinkOn = true
        stallUntil = nil

        switch stage.surface {
        case .textScreen(let screen):
            render(screen)
            if screen.isAnimated, stage.hold > 0 {
                // The counter walks 0…100 across the stage's own length — pausing where the
                // screen says to, which is where ScanDisk's tension was.
                let step = max(0.03, stage.hold / 100)
                counterTimer = schedule(every: step) { [weak self] in
                    guard let self, self.dumpCounter < 100 else { return }
                    if let until = self.stallUntil {
                        if Date() < until { return }
                        self.stallUntil = nil
                    } else if let stall = screen.counterStall, self.dumpCounter == stall.at {
                        self.stallUntil = Date().addingTimeInterval(stall.seconds)
                        return
                    }
                    self.dumpCounter += 1
                    self.render(screen)
                }
            }
            if screen.blinks {
                blinkTimer = schedule(every: 0.5) { [weak self] in
                    guard let self else { return }
                    self.blinkOn.toggle()
                    self.render(screen)
                }
            }
        case .dialog(let dialog):
            dialogExpanded = false
            dialogCountdown = dialog.countdownSeconds ?? 0
            showWindowedError(CrashDialogRenderer.dialog(dialog, expanded: false, scale: backingScale,
                                                         countdown: dialog.countdownSeconds))
            if dialog.countdownSeconds != nil {
                counterTimer = schedule(every: 1.0) { [weak self] in
                    guard let self, self.dialogCountdown > 0 else { return }
                    self.dialogCountdown -= 1
                    self.showWindowedError(CrashDialogRenderer.dialog(
                        dialog, expanded: self.dialogExpanded, scale: self.backingScale,
                        countdown: self.dialogCountdown))
                    self.wireInput(for: stage, index: index)
                }
            }
        case .shellRestart:
            runShellRestart(seconds: stage.hold)
        case .macAlert(let alert):
            showWindowedError(CrashDialogRenderer.macAlert(alert, scale: backingScale))
        case .kernelPanic(let panic):
            // The curtain is translucent, so every screen gets its own still underneath and its
            // own copy of the message — that is how the real one looked on a second monitor too.
            for (i, view) in (session?.views ?? []).enumerated() {
                let still = i < stills.count ? stills[i] : nil
                view.showOverlay(CrashRenderer.panicImage(panic, size: view.bounds.size),
                                 over: still, fill: true)
            }
        case .black:
            for view in session?.views ?? [] { view.showBlack() }
        case .still:
            showStills()
        case .bootGlyph(let glyph):
            renderGlyph(glyph)
            if glyph == .questionFolder {
                blinkTimer = schedule(every: 0.5) { [weak self] in
                    guard let self else { return }
                    self.blinkOn.toggle()
                    self.renderGlyph(glyph)
                }
            }
        case .moment(let moment):
            runMoment(moment, hold: stage.hold)
        }

        if let sound = stage.sound {
            CrashSound.shared.play(sound, seconds: max(1, stage.hold))
        }

        applyCursorPolicy(for: stage)
        wireInput(for: stage, index: index)

        // The clock runs whether or not a key could also end the stage: a boot failure waits
        // for "any key", and when nobody presses one the machine tries again on its own.
        if stage.hold > 0 {
            stageTimer = schedule(after: stage.hold) { [weak self] in self?.enterStage(index + 1) }
        }
    }

    /// The stages have run out by themselves. What that means depends on what they were.
    private func endOfStages(_ scenario: CrashScenario) {
        if scenario.category == .bootFailure {
            playBootSplash()
        } else if scenario.endsWithRestart {
            restart()
        } else {
            teardown(.finished)
        }
    }

    private static func describe(_ stage: CrashStage) -> String {
        let what: String
        switch stage.surface {
        case .textScreen(let t): what = "text(\(t.palette))"
        case .dialog(let d): what = "dialog(\(d.title))"
        case .macAlert(let a): what = "alert(\(a.lines.first ?? ""))"
        case .kernelPanic: what = "panic"
        case .shellRestart: what = "shellRestart"
        case .black: what = "black"
        case .still: what = "still"
        case .bootGlyph(let g): what = "glyph(\(g))"
        case .moment(let m): what = "moment(\(m))"
        }
        return "\(what) hold=\(stage.hold) recovery=\(stage.recovery.rawValue)\(stage.sound.map { " sound=\($0)" } ?? "")"
    }

    private var backingScale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2
    }

    /// A dialog on the frozen desktop: on the main screen, with the other screens showing their
    /// own frozen desktop so a second monitor is not left looking cheerful.
    private func showWindowedError(_ rendered: CrashDialogRenderer.Rendered) {
        session?.mainView?.showOverlay(rendered.image, over: stills.first ?? nil,
                                       fill: false, buttons: rendered.buttons)
        for (i, view) in (session?.views ?? []).enumerated() where view !== session?.mainView {
            view.show(fullBleed: i < stills.count ? stills[i] : nil)
        }
    }

    private func render(_ screen: TextScreen) {
        guard let image = CrashRenderer.image(for: screen, counter: dumpCounter, blinkOn: blinkOn) else { return }
        let ratio = CrashView.PictureRatio(setting: AppSettings.shared.crashPictureRatio)
        for view in session?.views ?? [] { view.show(pixelImage: image, ratio: ratio) }
    }

    private func renderGlyph(_ glyph: BootGlyph) {
        for view in session?.views ?? [] {
            let image = CrashRenderer.bootGlyphImage(glyph, blinkOn: blinkOn, size: view.bounds.size)
            var rect = NSRect(origin: .zero, size: image.size)
            view.show(fullBleed: image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        }
    }

    private func showStills() {
        for (i, view) in (session?.views ?? []).enumerated() {
            view.show(fullBleed: i < stills.count ? stills[i] : nil)
        }
    }

    // MARK: - Moments

    /// A few seconds of something being wrong. The still stays up throughout; only the pointer
    /// or the picture changes, and then the stage's own clock ends it.
    private func runMoment(_ moment: Moment, hold: TimeInterval) {
        guard let era = CrashEra.current() else { return }
        let started = Date()
        switch moment {
        case .beachball, .watchCursor, .hourglass, .busyRing:
            let frames: [CrashRenderer.CursorFrame]
            switch moment {
            case .beachball:   frames = CrashRenderer.beachballFrames(scale: backingScale)
            case .watchCursor: frames = CrashRenderer.watchCursorFrames(scale: backingScale)
            case .busyRing:    frames = CrashRenderer.busyRingFrames(scale: backingScale)
            default:           frames = CrashRenderer.hourglassFrames(scale: backingScale)
            }
            guard !frames.isEmpty else { return }
            if !cursorHidden { NSCursor.hide(); cursorHidden = true }
            let rate: Double = [.beachball, .busyRing].contains(moment) ? 12.0 : 2.0
            cursorTimer = schedule(every: 1.0 / 30.0) { [weak self] in
                guard let self, let view = self.session?.mainView else { return }
                // The pointer is busy, not lagging: it goes exactly where the hand goes.
                let index = Int(Date().timeIntervalSince(started) * rate) % frames.count
                let frame = frames[index]
                view.showFakeCursor(at: self.mouseInMainView(), image: frame.image, hotSpot: frame.hotSpot)
            }

        case .snowBurst:
            // Bursts of a few hundred milliseconds with the picture clean in between: the video
            // memory being read while something wrote to it, not a permanent fault.
            scheduleSnowBurst(era: era, until: started.addingTimeInterval(hold - 0.2))

        case .paletteCorruption:
            let steps: [(TimeInterval, Double)] = [(0, 0.6), (hold * 0.4, 1.0), (hold * 0.75, 0)]
            for (at, severity) in steps {
                let t = schedule(after: max(0.01, at)) { [weak self] in
                    guard let self else { return }
                    for (i, view) in (self.session?.views ?? []).enumerated() {
                        guard i < self.stills.count, let still = self.stills[i] else { continue }
                        view.show(fullBleed: severity == 0 ? still
                                  : CrashGlitch.paletteOnly(still, era: era, severity: severity) ?? still)
                    }
                }
                if at == 0 { momentTimer = t }
            }

        case .hsyncRoll:
            for view in session?.views ?? [] { view.roll(seconds: max(0.5, hold - 0.4)) }
            momentTimer = schedule(after: max(0.5, hold - 0.4)) {
                CrashSound.shared.playClick()
            }
        }
    }

    private func scheduleSnowBurst(era: CrashEra, until end: Date) {
        let gap = Double.random(in: 0.12...0.45, using: &rng)
        momentTimer = schedule(after: gap) { [weak self] in
            guard let self, Date() < end else { return }
            let seed = UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFF
            for (i, view) in (self.session?.views ?? []).enumerated() {
                guard i < self.stills.count, let still = self.stills[i] else { continue }
                view.show(fullBleed: CrashGlitch.snow(still, seed: seed &+ UInt64(i)) ?? still)
            }
            let burst = Double.random(in: 0.10...0.40, using: &self.rng)
            self.momentTimer = self.schedule(after: burst) { [weak self] in
                guard let self else { return }
                self.showStills()
                self.scheduleSnowBurst(era: era, until: end)
            }
        }
    }

    /// Whether this surface needs a pointer. A blue screen never had one — the machine was not
    /// answering — but a dialog with buttons is useless without one, and hiding it there was a
    /// straightforward mistake: you cannot aim at a button you cannot see.
    private func surfaceNeedsPointer(_ surface: CrashSurface) -> Bool {
        switch surface {
        case .dialog, .macAlert, .still: return true
        case .textScreen, .kernelPanic, .shellRestart, .black, .bootGlyph: return false
        // The cursor moments draw their own pointer; the picture moments keep the real one,
        // because the machine is answering, only the picture is wrong.
        case .moment(let m): return ![.beachball, .watchCursor, .hourglass, .busyRing].contains(m)
        }
    }

    private func applyCursorPolicy(for stage: CrashStage) {
        if surfaceNeedsPointer(stage.surface) {
            if cursorHidden { NSCursor.unhide(); cursorHidden = false }
            session?.mainView?.hideFakeCursor()
        } else if !cursorHidden {
            NSCursor.hide(); cursorHidden = true
        }
    }

    private func wireInput(for stage: CrashStage, index: Int) {
        let recovery = stage.recovery
        var nextButton: String?
        if case .dialog(let d) = stage.surface { nextButton = d.nextButton }
        if case .macAlert(let a) = stage.surface { nextButton = a.nextButton }
        for view in session?.views ?? [] {
            view.onEscape = { [weak self] in self?.abort(.escape) }
            view.onButton = { [weak self] label in
                guard let self else { return }
                switch label {
                case "Details >>":
                    // The one thing that button ever did: unfold the register dump.
                    self.dialogExpanded.toggle()
                    if case .dialog(let dialog) = stage.surface {
                        self.showWindowedError(CrashDialogRenderer.dialog(
                            dialog, expanded: self.dialogExpanded, scale: self.backingScale,
                            countdown: self.dialogCountdown))
                        self.wireInput(for: stage, index: index)
                    }
                case "Restart":
                    self.restart()
                case nextButton:
                    // "Retry", "Initialize": the machine tries again, and the next stage is what
                    // trying again got you.
                    self.enterStage(index + 1)
                default:
                    self.dismiss(stage, index: index)
                }
            }
            view.onKey = { [weak self] event in
                guard let self else { return }
                // Ctrl+Alt+Delete: the one gesture this era taught everybody.
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let isCAD = event.keyCode == 51 || event.keyCode == 117   // Delete / Forward Delete
                if recovery.contains(.ctrlAltDelete), isCAD,
                   mods.contains(.control), mods.contains(.option) {
                    self.restart()
                    return
                }
                if recovery.contains(.restartsOnAnyKey) { self.restart(); return }
                // A key and a click on OK mean the same thing, so they must lead to the same
                // place — including the roll for whether the machine survives it.
                if recovery.contains(.enterKey), event.keyCode == 36 { self.dismiss(stage, index: index); return }
                if recovery.contains(.anyKey) { self.dismiss(stage, index: index) }
            }
        }
    }

    /// "Any key" on a boot failure moves the boot along; on anything else it takes the failure
    /// away.
    private func dismiss(_ stage: CrashStage, index: Int) {
        if active?.category == .bootFailure {
            enterStage(index + 1)
        } else {
            closeDialog(stage)
        }
    }

    // MARK: - The simulated restart

    private func restart() {
        guard state != .blackout, state != .booting else { return }
        state = .blackout
        didRestart = true
        stageTimer?.invalidate()
        counterTimer?.invalidate()
        blinkTimer?.invalidate()
        momentTimer?.invalidate()
        CrashSound.shared.stop()
        for view in session?.views ?? [] { view.showBlack() }
        if !cursorHidden { NSCursor.hide(); cursorHidden = true }

        stageTimer = schedule(after: 1.1) { [weak self] in
            guard let self else { return }
            // Sometimes the machine does not come straight back. Same windows, same session:
            // the boot failure is drawn into the blackout, and the boot screen follows it.
            if let boot = self.pickBootFailureIfAny() {
                print("[Crash] boot failure: \(boot.id)")
                self.bootScenario = boot
                self.showBadge()
                self.enterStage(0)
            } else {
                self.playBootSplash()
            }
        }
    }

    private func pickBootFailureIfAny() -> CrashScenario? {
        guard AppSettings.shared.crashBootFailures, let era = CrashEra.current() else { return nil }
        guard Double.random(in: 0..<1, using: &rng) < era.bootFailureChance else { return nil }
        let disabled = AppSettings.shared.crashDisabledScenarios
        return CrashCatalogue.pickBootFailure(for: era, using: &rng) { !disabled.contains($0) }
    }

    /// The boot screen, then the desktop. Works from any session: the blackout after "Restart",
    /// or the one a boot failure was previewed in.
    private func playBootSplash() {
        stageTimer?.invalidate(); stageTimer = nil
        counterTimer?.invalidate(); counterTimer = nil
        blinkTimer?.invalidate(); blinkTimer = nil
        CrashSound.shared.stop()
        state = .booting
        guard let theme = ThemeManager.shared.activeTheme else { teardown(.finished); return }
        // The boot screen comes up BEFORE our windows go away, so there is never a frame in
        // which the real desktop shows through the "reboot".
        // Captured BEFORE the splash starts. `playForced` calls its completion
        // SYNCHRONOUSLY when the theme has no boot screen at all — Mountain Lion is such a
        // theme and is a crash era — and that completion presents the restored still and
        // assigns it to `self.session`. Reading `self.session` in the block below would then
        // close the new session instead of the blackout, and the restored beat would live
        // two frames instead of its 0.9 s.
        let blackout = self.session
        SplashController.shared.playForced(for: theme) { [weak self] in
            guard let self else { return }
            // The desktop was never touched, so it is already back. Holding the still for a
            // beat first is what makes the return read as a return rather than a cut — but
            // only when there IS a still. Without one this would put a black screen between
            // the boot logo and the desktop, which is worse than no beat at all.
            guard self.stills.contains(where: { $0 != nil }) else {
                self.teardown(.finished)
                return
            }
            self.state = .restored
            let session = CrashSession()
            self.session = session
            session.present()
            self.showStills()
            self.showBadge()
            self.stageTimer = self.schedule(after: 0.9) { [weak self] in
                self?.teardown(.finished)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            blackout?.close()
        }
    }

    // MARK: - Teardown

    func abort(_ reason: AbortReason) {
        guard state != .idle, state != .tearingDown else { return }
        print("[Crash] aborted: \(reason.rawValue)")
        teardown(reason)
    }

    /// Idempotent, safe from any state, and the only way out.
    func teardown(_ reason: AbortReason) {
        guard state != .idle else { return }
        state = .tearingDown

        stageTimer?.invalidate();     stageTimer = nil
        counterTimer?.invalidate();   counterTimer = nil
        countdownTimer?.invalidate(); countdownTimer = nil
        blinkTimer?.invalidate();     blinkTimer = nil
        momentTimer?.invalidate();    momentTimer = nil
        watchdog?.invalidate();       watchdog = nil
        liveness?.invalidate();       liveness = nil
        cursorTimer?.invalidate();    cursorTimer = nil
        stutterTimer?.invalidate();   stutterTimer = nil
        glitchTimer?.invalidate();    glitchTimer = nil
        CountdownHUD.shared.hide()
        CrashSound.shared.stop()
        // The pointer must come back from every exit, including the ones nobody plans for.
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        // So must the taskbar and the desktop icons, if a shell restart was interrupted half-way.
        restoreShell()
        DockController.shared.setSuspendedForCrash(false)

        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()
        let wsnc = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers { wsnc.removeObserver(token) }
        workspaceObservers.removeAll()

        session?.close()
        session = nil
        let finished = scenario
        let cameBack = didRestart
        scenario = nil
        bootScenario = nil
        didRestart = false
        stills = []
        armedForResign = false
        state = .idle
        print(reason == .finished ? "[Crash] finished" : "[Crash] ended (\(reason.rawValue))")

        // The machine came back and finished cleanly: some failures had a sequel.
        if reason == .finished, cameBack, let aftermath = finished?.aftermath {
            CrashScheduler.shared.scheduleAftermath(aftermath, using: &rng)
        }
    }

    // MARK: - Safety nets

    private func installObservers() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didResignActiveNotification,
                                        object: NSApp, queue: .main) { [weak self] _ in
            guard let self, self.armedForResign else { return }
            // Mandatory, not decorative: RetroMac is an accessory app and is not in the Cmd-Tab
            // list, so when the user switches away their keystrokes go straight to the app they
            // switched to — while a full-screen window of ours would still be covering it.
            self.abort(.lostActivation)
        })
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.abort(.screensChanged)
        })
        let wsnc = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(wsnc.addObserver(forName: NSWorkspace.willSleepNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
            self?.abort(.willSleep)
        })
    }

    private func armWatchdog(extra: TimeInterval) {
        watchdog?.invalidate()
        watchdog = schedule(after: Self.watchdogSeconds + extra) { [weak self] in
            self?.abort(.watchdog)
        }
    }

    /// Second line of defence: if our window somehow stops being the key window, or RetroMac
    /// stops being active without a notification reaching us, stop pretending.
    private func armLiveness() {
        liveness?.invalidate()
        liveness = schedule(every: 2.0) { [weak self] in
            guard let self, self.state != .idle, self.state != .tearingDown else { return }
            // The splash owns the key window while it plays, and the restored still is a
            // half-second beat with no input of its own.
            if self.state == .booting || self.state == .restored { return }
            // A shell restart has no window at all, on purpose: there is nothing to be key.
            if self.shellHidden { return }
            if !NSApp.isActive || self.session?.isKey != true { self.abort(.notKey) }
        }
    }

    // MARK: - Timer helpers (run-loop common mode: these must fire while a menu is held open)

    private func schedule(after seconds: TimeInterval, _ body: @escaping () -> Void) -> Timer {
        let t = Timer(timeInterval: seconds, repeats: false) { _ in body() }
        RunLoop.main.add(t, forMode: .common)
        return t
    }

    private func schedule(every seconds: TimeInterval, _ body: @escaping () -> Void) -> Timer {
        let t = Timer(timeInterval: seconds, repeats: true) { _ in body() }
        RunLoop.main.add(t, forMode: .common)
        return t
    }
}

// MARK: - Offline rendering (QA)

extension CrashDirector {
    /// Write every scenario's screens out as PNGs, at their true pixel size. Used to check the
    /// screens against the original screenshots without putting anything on a real desktop.
    /// Run the real selection — the active theme's era, the user's disabled list, the no-repeat
    /// rule and the director's own generator — without staging anything. This is how "it always
    /// picks the same one" becomes an answerable question on the machine where it happens,
    /// without putting a crash on anybody's screen to find out.
    func dryRunPicks(_ count: Int) -> [String] {
        guard let era = CrashEra.current() else { return ["<no era: theme has no crashes>"] }
        let settings = AppSettings.shared
        var last = lastScenarioID
        var lastShape = lastKind
        var out: [String] = []
        for _ in 0..<count {
            let picked = CrashCatalogue.pick(for: era, using: &rng, excluding: last,
                                             avoiding: lastShape) {
                !settings.crashDisabledScenarios.contains($0)
            }
            let plan = chooseBuildUp()
            out.append(picked.map { "\(plan) → \($0.id) [\($0.kind)]" } ?? "<nothing>")
            last = picked?.id
            lastShape = picked?.kind
        }
        return ["era=\(era.rawValue) disabled=\(settings.crashDisabledScenarios)"] + out
    }

    /// A stand-in desktop for the glitch dump when the machine will not hand over a screenshot.
    private static func testPattern() -> CGImage {
        let w = 1280, h = 800
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for i in 0..<8 {
            let colours: [NSColor] = [.white, .yellow, .cyan, .green, .magenta, .red, .blue, .black]
            ctx.setFillColor(colours[i].cgColor)
            ctx.fill(CGRect(x: CGFloat(i) * CGFloat(w) / 8, y: 0, width: CGFloat(w) / 8, height: CGFloat(h)))
        }
        ctx.setFillColor(NSColor.darkGray.cgColor)
        for row in 0..<10 {
            ctx.fill(CGRect(x: 60, y: CGFloat(row) * 70 + 40, width: CGFloat(w) - 120, height: 24))
        }
        return ctx.makeImage()!
    }

    static func dumpScreens(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var rng = CrashRNG(seed: 42)

        // The glitch pass, over a real still if there is one, so the corruption can be looked at
        // without staging a crash on somebody's desktop.
        // A real still when the machine will give one, a drawn stand-in when it will not, so the
        // glitches can always be looked at.
        let base = DesktopFreeze.capture().compactMap({ $0 }).first ?? testPattern()
        if true {
            let still = base
            for era in [CrashEra.win98, .winXP] {
                for severity in [0.5, 1.0] {
                    guard let broken = CrashGlitch.corrupt(still, era: era, severity: severity, seed: 5),
                          let data = NSBitmapImageRep(cgImage: broken)
                            .representation(using: .png, properties: [:]) else { continue }
                    let name = "glitch-\(era.rawValue)-\(Int(severity * 100)).png"
                    try? data.write(to: directory.appendingPathComponent(name))
                    print("[Crash] wrote \(name)")
                }
            }
            if let snow = CrashGlitch.snow(still, seed: 9),
               let data = NSBitmapImageRep(cgImage: snow).representation(using: .png, properties: [:]) {
                try? data.write(to: directory.appendingPathComponent("moment-snow.png"))
            }
        }
        func write(_ image: NSImage, _ name: String) {
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let data = rep.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: directory.appendingPathComponent(name))
            print("[Crash] wrote \(name) (\(image.size.width)x\(image.size.height))")
        }
        for spec in CrashCatalogue.all {
            let scenario = spec.build(&rng)
            for (i, stage) in scenario.stages.enumerated() {
                let name = scenario.stages.count > 1 ? "\(spec.id)-\(i).png" : "\(spec.id).png"
                switch stage.surface {
                case .textScreen(let screen):
                    guard let image = CrashRenderer.image(for: screen, counter: 67) else { continue }
                    let rep = NSBitmapImageRep(cgImage: image)
                    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
                    try? data.write(to: directory.appendingPathComponent(name))
                    print("[Crash] wrote \(name) \(image.width)x\(image.height)")
                case .dialog(let dialog):
                    write(CrashDialogRenderer.dialog(dialog, expanded: false, scale: 2,
                                                     countdown: dialog.countdownSeconds).image, name)
                case .macAlert(let alert):
                    write(CrashDialogRenderer.macAlert(alert, scale: 2).image, name)
                case .kernelPanic(let panic):
                    write(CrashRenderer.panicImage(panic, size: NSSize(width: 1280, height: 800)), name)
                case .bootGlyph(let glyph):
                    write(CrashRenderer.bootGlyphImage(glyph, blinkOn: true, size: NSSize(width: 1280, height: 800)), name)
                default:
                    break
                }
            }
        }
        for (name, frames) in [("cursor-beachball", CrashRenderer.beachballFrames(scale: 2)),
                               ("cursor-watch", CrashRenderer.watchCursorFrames(scale: 2)),
                               ("cursor-hourglass", CrashRenderer.hourglassFrames(scale: 2))] {
            if let first = frames.first { write(first.image, "\(name).png") }
        }
    }
}
