import AVFoundation

enum FanProfile: String, Codable, CaseIterable {
    case desktop, laptop, server

    var title: String {
        switch self {
        case .desktop: return "Desktop"
        case .laptop: return "Laptop"
        case .server: return "Server"
        }
    }

    /// Blade tone at full speed, and the noise's low-pass corner from still to full speed.
    var shape: (blade: Float, low: Float, high: Float, gain: Float) {
        switch self {
        case .desktop: return (150, 700, 3200, 1.0)
        case .laptop: return (420, 1400, 6500, 0.75)
        case .server: return (260, 1100, 5200, 1.25)
        }
    }
}

/// CPU load to fan speed, 0…1: smoothed, with hysteresis around the threshold so a short peak
/// does not make the fan jump, a quicker rise than fall, and a run-on of `decay` seconds.
struct FanCurve {
    var threshold = 0.35
    var attack = 2.0
    var decay = 8.0
    var baseNoise = false
    private(set) var load = 0.0
    private(set) var speed = 0.0
    private var running = false

    static func attack(_ r: SoundPrefs.Response) -> Double {
        switch r { case .slow: return 4; case .medium: return 2; case .fast: return 0.7 }
    }

    /// `cpu` 0…1 over the last `dt` seconds.
    mutating func step(cpu: Double, dt: Double) -> Double {
        // Load rises slowly enough that a one-second peak stays below the threshold, and falls
        // quickly, so the run-on is the decay setting rather than the smoothing.
        load += (cpu - load) * (1 - exp(-dt / (cpu > load ? 2 * attack : 1.5)))
        if load > threshold { running = true } else if load < threshold - 0.05 { running = false }
        let floor = baseNoise ? 0.12 : 0
        let above = (load - threshold + 0.05) / max(0.05, 1.05 - threshold)
        let target = running ? max(floor, min(1, 0.25 + 0.75 * above)) : floor
        // The decay is the time to near silence: three time constants.
        let tau = target > speed ? attack : decay / 3
        speed += (target - speed) * (1 - exp(-dt / tau))
        return speed
    }
}

/// The fan's sound: filtered noise whose brightness rises with speed, and a faint blade tone.
/// An effect, not a measurement: it follows CPU load, never the Mac's real fans or temperature.
final class FanModule: ObservableObject {
    struct Sample { var cpu: Double; var fan: Double }
    /// The last minute, once a second, for the chart in Settings.
    @Published private(set) var history: [Sample] = []

    let node: AVAudioSourceNode
    private let voice = FanVoice()
    private var curve = FanCurve()
    private var ticks: SystemSampler.Ticks?
    private var timer: Timer?

    init() {
        let v = voice
        node = AVAudioSourceNode(format: SoundEngine.mono) { _, _, frames, list in
            if let out = UnsafeMutableAudioBufferListPointer(list).first?.mData?.assumingMemoryBound(to: Float.self) {
                v.render(out, Int(frames))
            }
            return noErr
        }
    }

    func apply(_ p: SoundPrefs.Fan, master: Double, active: Bool) {
        curve.threshold = p.threshold
        curve.attack = FanCurve.attack(p.response)
        curve.decay = p.decay
        curve.baseNoise = p.baseNoise
        voice.setShape(p.profile)
        node.volume = Float(master * p.volume)
        if active, timer == nil {
            ticks = SystemSampler.totalTicks()
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            t.tolerance = 0.2
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !active, let t = timer {
            t.invalidate()
            timer = nil
            voice.target.pointee = 0
        }
    }

    private func tick() {
        guard let now = SystemSampler.totalTicks() else { return }
        defer { ticks = now }
        guard let prev = ticks, let load = SystemSampler.load(from: prev, to: now) else { return }
        let speed = curve.step(cpu: load.busy / 100, dt: 1)
        voice.target.pointee = Float(speed)
        history.append(Sample(cpu: load.busy / 100, fan: speed))
        if history.count > 60 { history.removeFirst(history.count - 60) }
    }

    static func previewBuffer(_ profile: FanProfile) -> AVAudioPCMBuffer {
        let v = FanVoice()
        v.setShape(profile)
        v.target.pointee = 0.75
        v.speed = 0.75
        let frames = AVAudioFrameCount(SoundEngine.sampleRate * 2.5)
        let buffer = AVAudioPCMBuffer(pcmFormat: SoundEngine.mono, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]
        v.render(out, Int(frames))
        let edge = Int(SoundEngine.sampleRate * 0.4)
        for i in 0..<edge {
            let g = Float(i) / Float(edge)
            out[i] *= g
            out[Int(frames) - 1 - i] *= g
        }
        return buffer
    }
}

/// Render state of the fan, owned by the audio thread. The target speed and the shape are
/// written from the main thread as single floats.
final class FanVoice {
    let target = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private let shape = UnsafeMutablePointer<Float>.allocate(capacity: 4)
    var speed: Float = 0
    private var phase: Float = 0, lp1: Float = 0, lp2: Float = 0, rumble: Float = 0
    private var rng: UInt32 = 0x2545F491

    init() {
        target.pointee = 0
        setShape(.desktop)
    }

    deinit { target.deallocate(); shape.deallocate() }

    func setShape(_ p: FanProfile) {
        let s = p.shape
        shape[0] = s.blade; shape[1] = s.low; shape[2] = s.high; shape[3] = s.gain
    }

    func render(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        let sr = Float(SoundEngine.sampleRate), glide: Float = 1 / (0.3 * sr)
        let goal = target.pointee
        if goal == 0 && speed < 0.0005 {
            speed = 0
            out.update(repeating: 0, count: n)
            return
        }
        for i in 0..<n {
            speed += (goal - speed) * glide
            rng = rng &* 1664525 &+ 1013904223
            let white = Float(Int32(bitPattern: rng)) / Float(Int32.max)
            let corner = shape[1] + (shape[2] - shape[1]) * speed
            let a = min(1, 2 * .pi * corner / sr)
            lp1 += (white - lp1) * a
            lp2 += (lp1 - lp2) * a
            rumble += (lp2 - rumble) * 0.004
            phase += 2 * .pi * shape[0] * speed / sr
            if phase > 2 * .pi { phase -= 2 * .pi }
            let blade = sinf(phase) * 0.10 + sinf(2 * phase) * 0.03
            out[i] = ((lp2 - rumble) * 1.6 + blade) * speed * sqrtf(speed) * shape[3]
        }
    }
}
