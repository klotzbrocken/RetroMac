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
/// deallocated, the sixty-second watchdog, the abort on losing focus) exists to make the normal
/// case pleasant. This invariant is what makes the worst case survivable. Do not trade it away.
final class CrashDirector {

    static let shared = CrashDirector()
    private init() {}

    // MARK: - State

    enum Source { case random, manual, hotkey }
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
    private var stills: [CGImage?] = []
    private var stageTimer: Timer?
    private var counterTimer: Timer?
    private var watchdog: Timer?
    private var liveness: Timer?
    private var countdownTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var armedForResign = false
    private var dumpCounter = 0
    /// What was shown last, so the next pick can avoid it — by name and by shape.
    private var lastScenarioID: String?
    private var lastKind: CrashKind?
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
    private var rng = CrashRNG(seed: UInt64(UInt32.random(in: 0...UInt32.max)))

    var isStaging: Bool { state != .idle }

    /// The absolute ceiling on one simulation, never reset by a stage change. A user who walks
    /// away mid-crash comes back to their desktop, not to a blue screen.
    private static let watchdogSeconds: TimeInterval = 60

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
        lastScenarioID = scenario.id
        lastKind = scenario.kind

        print("[Crash] \(scenario.id) on \(era.displayName), source=\(source)")
        if countdown > 0 {
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
        if state != .countdown { installObservers(); armWatchdog(extra: 0) }

        // Capture first, present second: whatever is on screen must not include our own overlay.
        stills = DesktopFreeze.capture()

        let session = CrashSession()
        self.session = session
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

        let plan = chooseBuildUp()
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
        DockController.shared.setSuspendedForCrash(true)
        DesktopIconsController.shared.hide()

        stageTimer = schedule(after: seconds) { [weak self] in
            guard let self else { return }
            DockController.shared.setSuspendedForCrash(false)
            DesktopIconsController.shared.update()
            self.teardown(.finished)
        }
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
        for view in session?.views ?? [] { view.showBadge(on, name: scenario?.title) }
    }

    // MARK: - Stages

    private func enterStage(_ index: Int) {
        // Nothing from the warning may still be drawing once a failure is up.
        cursorTimer?.invalidate(); cursorTimer = nil
        glitchTimer?.invalidate(); glitchTimer = nil

        guard let scenario, index < scenario.stages.count else { teardown(.finished); return }
        state = .failure(index)
        let stage = scenario.stages[index]
        dumpCounter = 0
        counterTimer?.invalidate(); counterTimer = nil

        switch stage.surface {
        case .textScreen(let screen):
            render(screen)
            if screen.lines.contains(where: { if case .counter = $0 { return true }; return false }),
               stage.hold > 0 {
                // The dump counter walks 0…100 across the stage's own length.
                let step = max(0.03, stage.hold / 100)
                counterTimer = schedule(every: step) { [weak self] in
                    guard let self, self.dumpCounter < 100 else { return }
                    self.dumpCounter += 1
                    self.render(screen)
                }
            }
        case .dialog(let dialog):
            dialogExpanded = false
            showWindowedError(CrashDialogRenderer.dialog(dialog, expanded: false, scale: backingScale))
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
            for view in session?.views ?? [] { view.show(fullBleed: nil) }
        }

        applyCursorPolicy(for: stage)
        wireInput(for: stage)

        if stage.recovery.isEmpty && stage.hold > 0 {
            stageTimer = schedule(after: stage.hold) { [weak self] in self?.enterStage(index + 1) }
        }
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
        guard let image = CrashRenderer.image(for: screen, counter: dumpCounter) else { return }
        let stretch = AppSettings.shared.crashStretchToFill
        for view in session?.views ?? [] { view.show(pixelImage: image, stretchToFill: stretch) }
    }

    private func showStills() {
        for (i, view) in (session?.views ?? []).enumerated() {
            view.show(fullBleed: i < stills.count ? stills[i] : nil)
        }
    }

    /// Whether this surface needs a pointer. A blue screen never had one — the machine was not
    /// answering — but a dialog with buttons is useless without one, and hiding it there was a
    /// straightforward mistake: you cannot aim at a button you cannot see.
    private func surfaceNeedsPointer(_ surface: CrashSurface) -> Bool {
        switch surface {
        case .dialog, .macAlert: return true
        case .textScreen, .kernelPanic, .shellRestart, .black: return false
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

    private func wireInput(for stage: CrashStage) {
        let recovery = stage.recovery
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
                            dialog, expanded: self.dialogExpanded, scale: self.backingScale))
                        self.wireInput(for: stage)
                    }
                case "Restart":
                    self.restart()
                default:
                    self.closeDialog(stage)
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
                if recovery.contains(.enterKey), event.keyCode == 36 { self.closeDialog(stage); return }
                if recovery.contains(.anyKey) { self.closeDialog(stage) }
            }
        }
    }

    // MARK: - The simulated restart

    private func restart() {
        guard state != .blackout, state != .booting else { return }
        state = .blackout
        stageTimer?.invalidate()
        counterTimer?.invalidate()
        for view in session?.views ?? [] { view.show(fullBleed: nil) }

        stageTimer = schedule(after: 1.1) { [weak self] in
            guard let self else { return }
            self.state = .booting
            guard let theme = ThemeManager.shared.activeTheme else { self.teardown(.finished); return }
            // The boot screen comes up BEFORE our windows go away, so there is never a frame in
            // which the real desktop shows through the "reboot".
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.session?.close()
            }
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
        watchdog?.invalidate();       watchdog = nil
        liveness?.invalidate();       liveness = nil
        cursorTimer?.invalidate();    cursorTimer = nil
        stutterTimer?.invalidate();   stutterTimer = nil
        glitchTimer?.invalidate();    glitchTimer = nil
        CountdownHUD.shared.hide()
        CrashSound.shared.stop()
        // The pointer must come back from every exit, including the ones nobody plans for.
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        // So must the taskbar, if a shell restart was interrupted half-way.
        DockController.shared.setSuspendedForCrash(false)

        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()

        session?.close()
        session = nil
        scenario = nil
        stills = []
        armedForResign = false
        state = .idle
        if reason != .finished { print("[Crash] ended (\(reason.rawValue))") }
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
        observers.append(wsnc.addObserver(forName: NSWorkspace.willSleepNotification,
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
        }
        for spec in CrashCatalogue.all {
            let scenario = spec.build(&rng)
            for (i, stage) in scenario.stages.enumerated() {
                guard case .textScreen(let screen) = stage.surface,
                      let image = CrashRenderer.image(for: screen, counter: 67) else { continue }
                let rep = NSBitmapImageRep(cgImage: image)
                guard let data = rep.representation(using: .png, properties: [:]) else { continue }
                let name = scenario.stages.count > 1 ? "\(spec.id)-\(i).png" : "\(spec.id).png"
                try? data.write(to: directory.appendingPathComponent(name))
                print("[Crash] wrote \(name) \(image.width)x\(image.height)")
            }
            // The windowed surfaces, drawn at their own size.
            var windowed: NSImage?
            switch scenario.stages.first?.surface {
            case .dialog(let dialog):
                windowed = CrashDialogRenderer.dialog(dialog, expanded: false, scale: 2).image
            case .macAlert(let alert):
                windowed = CrashDialogRenderer.macAlert(alert, scale: 2).image
            case .kernelPanic(let panic):
                windowed = CrashRenderer.panicImage(panic, size: NSSize(width: 1280, height: 800))
            default: break
            }
            if let image = windowed,
               let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: directory.appendingPathComponent("\(spec.id).png"))
                print("[Crash] wrote \(spec.id).png (\(image.size.width)x\(image.size.height))")
            }
        }
    }
}
