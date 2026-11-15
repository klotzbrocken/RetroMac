import AppKit

/// Borderless, non-activating: clicking the character never takes the focus from the app in front.
final class AgentPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

/// The character on screen: one layer per overlay, the sprite swapped frame by frame, and a queue
/// of things to play the way clippy.js's Agent works. Between actions it rests for a while and
/// then plays an idle; with Reduce Motion it only shows its resting picture.
final class AgentPlayer: NSView {
    let character: AgentCharacter
    var soundsOn = false
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onMoved: ((NSPoint) -> Void)?

    private var layers: [CALayer] = []
    private var animator: AgentAnimator?
    private var current: String?
    private var onEnd: (() -> Void)?
    private var queue: [(String, (() -> Void)?)] = []
    private var frameTimer: Timer?
    private var restTimer: Timer?
    private var exitTimer: Timer?
    private var idling = false
    /// Asleep: held on a sleeping frame, no timers running until something wakes it.
    private(set) var asleep = false
    private var sleepHold: Int?

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(character: AgentCharacter) {
        self.character = character
        super.init(frame: NSRect(origin: .zero, size: character.frameSize))
        wantsLayer = true
        layer?.backgroundColor = .clear
        for _ in 0..<character.overlayCount {
            let l = CALayer()
            l.frame = bounds
            l.magnificationFilter = .nearest
            l.contentsGravity = .resize
            l.actions = ["contents": NSNull(), "hidden": NSNull()]
            layer?.addSublayer(l)
            layers.append(l)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(AgentCatalog.title(character.name))
        setAccessibilityHelp("Click for the clipboard, notes, today's agenda and Wikipedia's article of the day. Double-click for its next animation.")
        showRest()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { stop() }

    func stop() {
        frameTimer?.invalidate(); restTimer?.invalidate(); exitTimer?.invalidate()
        frameTimer = nil; restTimer = nil; exitTimer = nil
        queue.removeAll(); animator = nil; onEnd = nil
    }

    // MARK: - Playing

    /// Queues an animation; `done` runs when it has played out. A name the character lacks is skipped.
    func play(_ name: String?, then done: (() -> Void)? = nil) {
        guard let name, character.animations[name] != nil else { done?(); return }
        queue.append((name, done))
        if asleep { wake(); return }
        if sleepHold != nil { sleepHold = nil; interrupt(); return }   // dozing off: it gets up again
        if idling, var a = animator { a.exiting = true; animator = a; restTimer?.invalidate() }
        else if animator == nil { next() }
    }

    func play(_ moment: AgentCharacter.Moment, then done: (() -> Void)? = nil) {
        play(character.animation(for: moment), then: done)
    }

    /// Ends whatever plays now through its exit branches.
    func interrupt() {
        if var a = animator { a.exiting = true; animator = a }
    }

    private func next() {
        restTimer?.invalidate()
        guard !queue.isEmpty else { scheduleIdle(); return }
        let (name, done) = queue.removeFirst()
        start(name, idle: false, done: done)
    }

    private func start(_ name: String, idle: Bool, done: (() -> Void)?) {
        guard let anim = character.animations[name] else { done?(); next(); return }
        if reduceMotion {
            showRest()
            animator = nil
            DispatchQueue.main.async { [weak self] in done?(); self?.next() }
            return
        }
        idling = idle
        current = name
        onEnd = done
        animator = AgentAnimator(anim)
        // clippy.js gives a looping animation five seconds, then asks it to leave.
        exitTimer?.invalidate()
        if sleepHold == nil {
            exitTimer = Timer.scheduledTimer(withTimeInterval: idle ? 10 : 5, repeats: false) { [weak self] _ in
                self?.interrupt()
            }
        }
        tick()
    }

    private func tick() {
        guard var a = animator else { return }
        let event = a.step(roll: Double.random(in: 0..<100))
        animator = a
        if let f = a.frame {
            draw(f.images ?? [])
            if soundsOn, let s = f.sound, let data = character.sounds[s] { NSSound(data: data)?.play() }
        }
        // Reached the sleeping frame: stay there, nothing ticking.
        if let hold = sleepHold, a.index == hold, !a.exiting {
            asleep = true
            exitTimer?.invalidate()
            return
        }
        switch event {
        case .exited:
            finish()
        case .waiting:
            // Held on its last frame until asked to leave (exit timer or the next action).
            if !queue.isEmpty { a.exiting = true; animator = a }
            fallthrough
        case .none:
            let ms = max(a.frame?.duration ?? 100, 16)
            let t = Timer(timeInterval: Double(ms) / 1000, repeats: false) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            frameTimer = t
        }
    }

    private func finish() {
        exitTimer?.invalidate()
        frameTimer?.invalidate()
        animator = nil
        idling = false
        let done = onEnd
        onEnd = nil
        done?()
        next()
    }

    /// A pause before the next idle, like MS Agent's: idles every few seconds, not nonstop.
    private func scheduleIdle() {
        restTimer?.invalidate()
        guard !reduceMotion, !asleep, window?.isVisible == true else { return }
        restTimer = Timer.scheduledTimer(withTimeInterval: .random(in: 6...14), repeats: false) { [weak self] _ in
            guard let self, self.animator == nil, self.queue.isEmpty,
                  let idle = self.character.idleAnimations.randomElement() else { return }
            self.start(idle, idle: true, done: nil)
        }
    }

    private func draw(_ images: [[Int]]) {
        for (i, l) in layers.enumerated() {
            if i < images.count, let img = character.sprite(images[i]) {
                l.contents = img
                l.isHidden = false
            } else {
                l.isHidden = true
            }
        }
    }

    /// The resting picture: RestPose's first frame, or the first frame of anything.
    private func showRest() {
        let anim = character.animations["RestPose"] ?? character.animations["Idle1_1"] ?? character.animations.values.first
        draw(anim?.frames.first?.images ?? [])
    }

    // MARK: - Sleep

    /// Falls asleep (yawning first, where the character can) and stays on the sleeping frame
    /// until `wake()`. Without a sleep of its own it just stops fidgeting. Only from rest:
    /// false while something plays, and the caller tries again a little later.
    @discardableResult
    func fallAsleep() -> Bool {
        if asleep || sleepHold != nil { return true }
        guard animator == nil, queue.isEmpty else { return false }
        restTimer?.invalidate()
        guard let s = character.sleep, let anim = character.animations[s.sleep] else { asleep = true; return true }
        if reduceMotion {
            draw(anim.frames[s.frame].images ?? [])
            asleep = true
            return true
        }
        let doze = { [weak self] in
            guard let self, self.queue.isEmpty, self.animator == nil else { return }
            self.sleepHold = s.frame
            self.start(s.sleep, idle: false, done: nil)
        }
        if let yawn = s.yawn { play(yawn, then: doze) } else { doze() }
        return true
    }

    /// Wakes up: the sleep animation leaves through its exit branches, then the queue goes on.
    func wake() {
        guard asleep else { return }
        asleep = false
        sleepHold = nil
        guard animator != nil else { showRest(); next(); return }
        if var a = animator { a.exiting = true; animator = a }
        tick()
    }

    // MARK: - Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var grab: (mouse: NSPoint, origin: NSPoint, moved: Bool)?

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        grab = (NSEvent.mouseLocation, window.frame.origin, false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, var g = grab else { return }
        let m = NSEvent.mouseLocation
        let dx = m.x - g.mouse.x, dy = m.y - g.mouse.y
        if !g.moved, hypot(dx, dy) < 3 { return }
        g.moved = true
        grab = g
        window.setFrameOrigin(NSPoint(x: g.origin.x + dx, y: g.origin.y + dy))
        onMoved?(window.frame.origin)
    }

    private var pendingClick: DispatchWorkItem?

    /// A single click waits the double-click interval, so a double click does only its own thing.
    override func mouseUp(with event: NSEvent) {
        defer { grab = nil }
        guard grab?.moved == false else { return }
        pendingClick?.cancel()
        if event.clickCount >= 2 {
            pendingClick = nil
            onDoubleClick?()
            return
        }
        let w = DispatchWorkItem { [weak self] in self?.onClick?() }
        pendingClick = w
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: w)
    }

    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }

    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}
