import Foundation

/// SETI@home Classic as a simulation: a work unit is "received", analysed in passes and "sent
/// back", the counters climbing as the 1999–2005 client's did. Nothing here analyses anything
/// or talks to a network; every value is made up, but made up consistently — the spectrum, the
/// candidate's curve and its numbers all come from the same seeded state, so a window and the
/// screensaver showing the same moment show the same thing.
///
/// Pure logic: the controller advances it, saves it and draws it. All randomness is derived
/// from `seed` and indices (`rng(_:_:_:)`), so nothing but the state itself needs saving.
struct SETIState: Codable, Equatable {
    static let formatVersion = 1

    var version = SETIState.formatVersion
    var seed: UInt64
    /// Work units started so far; the current one is number `unitIndex`.
    var unitIndex = 0
    var unit: WorkUnit
    var phase = 0
    var phaseProgress = 0.0
    var unitCPU = 0.0
    var unitsDone = 0
    var totalCPU = 0.0
    /// The best result of each kind in this unit (noise most of the time, as in the original).
    var best: [String: Candidate] = [:]
    /// The staged "find" being shown right now, if any.
    var current: Candidate?
    /// Seconds of visible analysis, the clock the random find is scheduled on (spec 6.3).
    var visibleSeconds = 0.0
    var nextEventAt = 0.0
    var eventsSeen = 0
    var paused = false
    /// Waiting for "Connect" (network mode "ask"): the client does not dial out by itself.
    var awaitingConnection = false
    /// Before the first start (Mac OS X: until Preferences and Login are done).
    var started = false

    struct WorkUnit: Codable, Equatable {
        var id: String
        var recordedAt: Date
        var raHours: Double
        var decDegrees: Double
        var baseFrequencyHz: Double
        var source = "Arecibo Radio Observatory"
    }

    struct Candidate: Codable, Equatable {
        enum Kind: String, Codable { case spike, gaussian, pulse, triplet }
        var kind: Kind
        var power: Double
        /// Gaussian: chi-square of the fit (lower is better). Pulse/triplet: the score.
        var score: Double
        /// Pulse and triplet: the period in seconds.
        var period: Double
        /// Where in the spectrum: 0…1 along frequency and along recorded time.
        var frequency: Double
        var time: Double
        var seed: UInt64
        /// `visibleSeconds` when a staged find appeared; nil for an ordinary noise best.
        var appearedAt: Double?
    }

    init(seed: UInt64) {
        self.seed = seed
        unit = SETISimulation.makeUnit(seed: seed, index: 0)
        nextEventAt = SETISimulation.firstEvent(seed: seed, frequency: .standard)
    }
}

enum SETISimulation {

    enum Speed: String, Codable, CaseIterable {
        case historical, demo
        /// Visible seconds for the analysis of one unit. Retromac's choice, not a measurement.
        var unitSeconds: Double { self == .historical ? 2.5 * 3600 : 240 }
    }

    enum Frequency: String, Codable, CaseIterable {
        case rare, standard, often
        var factor: Double { switch self { case .rare: return 2; case .standard: return 1; case .often: return 0.5 } }
    }

    // MARK: Phases

    enum Step: String {
        case header = "Scanning Result Header File"
        case connecting = "Connecting To Server"
        case receiving = "Receiving Data"
        case smoothing = "Doing Baseline Smoothing"
        case chirping = "Chirping Data"
        case fft = "Computing Fast Fourier Transform"
        case gaussians = "Searching For Gaussians"
        case pulses = "Searching For Pulses"
        case triplets = "Searching For Triplets"
        case sending = "Sending Data"

        var isTransfer: Bool { self == .connecting || self == .receiving || self == .sending }
        var isAnalysis: Bool { !isTransfer && self != .header }
    }

    struct Phase { let step: Step; let weight: Double; let pass: Int }

    /// Analysis passes per unit; each looks at the same recording at another chirp rate and
    /// resolution (spec 5.6, 5.8).
    static let passes = 8
    static let resolutions = [0.075, 0.15, 0.3, 0.6, 1.2, 2.4, 4.8, 9.6]

    /// The steps of a unit. Weights are shares of the unit's analysis time; transfers and the
    /// header have their own fixed seconds (`transferSeconds`).
    static let phases: [Phase] = {
        var p = [Phase(step: .header, weight: 0, pass: -1),
                 Phase(step: .connecting, weight: 0, pass: -1),
                 Phase(step: .receiving, weight: 0, pass: -1),
                 Phase(step: .smoothing, weight: 0.04, pass: -1)]
        for i in 0..<passes {
            p += [Phase(step: .chirping, weight: 0.01, pass: i),
                  Phase(step: .fft, weight: 0.07, pass: i),
                  Phase(step: .gaussians, weight: 0.025, pass: i),
                  Phase(step: .pulses, weight: 0.0075, pass: i),
                  Phase(step: .triplets, weight: 0.0075, pass: i)]
        }
        p.append(Phase(step: .sending, weight: 0, pass: -1))
        return p
    }()
    static let analysisWeight = phases.reduce(0) { $0 + $1.weight }
    static func transferSeconds(_ step: Step) -> Double {
        switch step { case .header: return 3; case .connecting: return 4; case .receiving: return 12; case .sending: return 8; default: return 0 }
    }

    static func phase(_ s: SETIState) -> Phase { phases[min(s.phase, phases.count - 1)] }

    /// Overall share of the unit done, 0…1: monotonic within a unit (spec 4.5, AB-08).
    static func overall(_ s: SETIState) -> Double {
        var done = 0.0
        for (i, p) in phases.enumerated() where i < s.phase { done += p.weight }
        done += phase(s).weight * s.phaseProgress
        return min(1, done / analysisWeight)
    }

    static func drift(_ s: SETIState) -> Double {
        let pass = phase(s).pass
        guard pass >= 0 else { return 0 }
        var r = rng(s.seed, s.unitIndex * 100 + pass, 7)
        return Double.random(in: -10...10, using: &r)
    }
    static func resolution(_ s: SETIState) -> Double {
        let pass = phase(s).pass
        return resolutions[max(0, pass) % resolutions.count]
    }

    // MARK: Advancing

    /// Moves the simulation on by `dt` seconds of processing. `visible`: someone can see it, so
    /// the random find's clock runs (spec 6.3). Long gaps are clamped: coming back after a
    /// while never runs through a pile of units at once (spec 8.3).
    static func advance(_ s: inout SETIState, by rawDT: Double, visible: Bool, speed: Speed,
                        candidates: Bool, frequency: Frequency, askBeforeConnecting: Bool = false) {
        guard s.started, !s.paused, rawDT > 0 else { return }
        let dt = min(rawDT, 1.0)
        if visible { s.visibleSeconds += dt }
        let p = phase(s)

        if p.step.isTransfer || p.step == .header {
            if askBeforeConnecting, needsConnection(s), s.phaseProgress == 0 { s.awaitingConnection = true }
            if s.awaitingConnection { return }
            s.phaseProgress += dt / transferSeconds(p.step)
        } else {
            s.phaseProgress += dt / (p.weight * speed.unitSeconds)
            // CPU time as the era's machine would have spent it: the historical pace, whatever
            // the playback speed.
            let cpu = dt * Speed.historical.unitSeconds / speed.unitSeconds
            s.unitCPU += cpu
            s.totalCPU += cpu
            if candidates, visible { scheduleFind(&s, frequency: frequency) }
        }
        if let c = s.current, let at = c.appearedAt, s.visibleSeconds - at > findSeconds { s.current = nil }
        if s.phaseProgress >= 1 { finishPhase(&s) }
    }

    /// The staged find stays on screen this long: 2–4 s rising, 6–12 s examined, 15–30 s
    /// shown after (spec 6.2), taken at their upper ends.
    static let findSeconds = 46.0

    /// The user's "Connect" for a waiting transfer.
    static func connect(_ s: inout SETIState) {
        guard s.awaitingConnection else { return }
        s.awaitingConnection = false
        s.phaseProgress = 0.0001   // past the point where it asks
    }

    private static func finishPhase(_ s: inout SETIState) {
        // dt is at most a second, so what a phase overshoots is not worth carrying over.
        s.phaseProgress = 0
        let done = phase(s)
        if [.gaussians, .pulses, .triplets].contains(done.step) { recordNoiseBest(&s, step: done.step, pass: done.pass) }
        if done.step == .sending {
            s.unitsDone += 1
            s.unitIndex += 1
            s.unit = makeUnit(seed: s.seed, index: s.unitIndex)
            s.phase = 0
            s.unitCPU = 0
            s.best = [:]
            s.current = nil
            s.phaseProgress = 0
            return
        }
        s.phase += 1
    }

    /// Network mode "ask": a transfer waits for the user's "Connect" (Mac manual: the icon
    /// blinks for attention; the screensaver never dials out by itself).
    static func needsConnection(_ s: SETIState) -> Bool {
        let step = phase(s).step
        return step == .connecting || step == .sending
    }

    // MARK: Results

    private static func recordNoiseBest(_ s: inout SETIState, step: Step, pass: Int) {
        let kind: SETIState.Candidate.Kind = step == .gaussians ? .gaussian : step == .pulses ? .pulse : .triplet
        var r = rng(s.seed, s.unitIndex * 100 + pass, Int(kindCode(kind)))
        let c = SETIState.Candidate(kind: kind,
                                    power: Double.random(in: 0.4...1.5, using: &r),
                                    score: kind == .gaussian ? Double.random(in: 3...9, using: &r) : Double.random(in: 0.2...1.2, using: &r),
                                    period: Double.random(in: 0.5...12, using: &r),
                                    frequency: Double.random(in: 0.02...0.98, using: &r),
                                    time: Double.random(in: 0.2...0.8, using: &r),
                                    seed: r.next(), appearedAt: nil)
        if isBetter(c, than: s.best[kind.rawValue]) { s.best[kind.rawValue] = c }
    }

    static func isBetter(_ c: SETIState.Candidate, than old: SETIState.Candidate?) -> Bool {
        guard let old else { return true }
        return c.power > old.power
    }

    /// The random find (spec 6.3): first after 2 visible minutes plus 4–12 more, then never
    /// sooner than 5 minutes after the last, on the visible clock only.
    static func firstEvent(seed: UInt64, frequency: Frequency) -> Double {
        var r = rng(seed, -1, 0)
        return 120 + Double.random(in: 240...720, using: &r) * frequency.factor
    }

    private static func scheduleFind(_ s: inout SETIState, frequency: Frequency) {
        guard s.current == nil, s.visibleSeconds >= s.nextEventAt else { return }
        stageFind(&s)
        var r = rng(s.seed, -2, s.eventsSeen)
        s.nextEventAt = s.visibleSeconds + 300 + Double.random(in: 240...720, using: &r) * frequency.factor
    }

    /// Puts a find on screen now, of the kind the current step searches for: a lone spike is
    /// never passed off as a Gaussian or a triplet (spec 6.2).
    static func stageFind(_ s: inout SETIState) {
        let kind: SETIState.Candidate.Kind
        switch phase(s).step {
        case .gaussians: kind = .gaussian
        case .pulses: kind = .pulse
        case .triplets: kind = .triplet
        default: kind = .spike
        }
        s.eventsSeen += 1
        var r = rng(s.seed, -3, s.eventsSeen)
        let c = SETIState.Candidate(kind: kind,
                                    power: Double.random(in: 3...9, using: &r),
                                    score: kind == .gaussian ? Double.random(in: 1.0...2.5, using: &r) : Double.random(in: 2...6, using: &r),
                                    period: Double.random(in: 0.5...12, using: &r),
                                    frequency: Double.random(in: 0.08...0.92, using: &r),
                                    time: Double.random(in: 0.25...0.75, using: &r),
                                    seed: r.next(), appearedAt: s.visibleSeconds)
        s.current = c
        let key = kind == .spike ? "spike" : kind.rawValue
        if isBetter(c, than: s.best[key]) { s.best[key] = c }
    }

    // MARK: Work units

    static func makeUnit(seed: UInt64, index: Int) -> SETIState.WorkUnit {
        var r = rng(seed, index, 1)
        // Recorded in the project's own years: never today's date passed off as 1999 (spec 4.3).
        let from = Date(timeIntervalSince1970: 925_516_800)     // 1 May 1999
        let to = Date(timeIntervalSince1970: 1_133_395_200)     // 1 Dec 2005
        let at = Date(timeIntervalSince1970: Double.random(in: from.timeIntervalSince1970...to.timeIntervalSince1970, using: &r).rounded())
        return SETIState.WorkUnit(
            id: String(format: "%02dmy%02d%c%c.%05d.%04d.%d.%d",
                       Int.random(in: 1...31, using: &r), Int.random(in: 0...5, using: &r),
                       Int.random(in: 97...122, using: &r), Int.random(in: 97...122, using: &r),
                       Int.random(in: 0...99_999, using: &r), Int.random(in: 0...9999, using: &r),
                       Int.random(in: 1...20, using: &r), Int.random(in: 1...250, using: &r)),
            recordedAt: at,
            raHours: Double.random(in: 0..<24, using: &r),
            decDegrees: Double.random(in: -1...35, using: &r),
            baseFrequencyHz: 1.418e9 + Double(Int.random(in: 0...400, using: &r)) * 9765.625)
    }

    // MARK: Randomness

    static func rng(_ seed: UInt64, _ a: Int, _ b: Int) -> CrashRNG {
        CrashRNG(seed: seed ^ (UInt64(bitPattern: Int64(a)) &* 0x9E3779B97F4A7C15) ^ (UInt64(bitPattern: Int64(b)) &* 0xC2B2AE3D27D4EB4F))
    }
    private static func kindCode(_ k: SETIState.Candidate.Kind) -> UInt8 {
        switch k { case .spike: return 1; case .gaussian: return 2; case .pulse: return 3; case .triplet: return 4 }
    }
}
