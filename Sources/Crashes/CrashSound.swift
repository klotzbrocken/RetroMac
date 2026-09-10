import AppKit
import AVFoundation

/// The sound of a hard disk in trouble, synthesised rather than sampled.
///
/// Every recording of a dying drive on the internet belongs to whoever recorded it, and a joke
/// feature is a poor reason to ship somebody else's audio under an unclear licence. It is also
/// unnecessary: the sound is three simple ingredients, and building them means they can follow the
/// simulation instead of being a fixed clip.
///
///  - the spindle: a low hum that spins up from rest and then holds,
///  - the seek: a short burst of filtered noise, the actuator swinging the heads across,
///  - the click of death: the same burst, louder and slower, repeating, because the head has hit
///    the stop and the drive is recalibrating and failing and trying again.
///
/// The Zip drive's click of death is the same idea with the spindle left out and the rhythm of
/// its own actuator: a short whirr as the heads run out, and a hard knock as they hit the stop,
/// every half second or so, for as long as the cartridge stays in. The floppy is the same knock
/// with a quicker, lighter stepper behind it.
///
/// Nothing here plays unless the user asked for a crash, and it is one short buffer, so there is
/// no audio session to manage and nothing to leave running.
final class CrashSound {

    static let shared = CrashSound()
    private init() {}

    private var sound: NSSound?

    var isEnabled: Bool { AppSettings.shared.crashSoundEnabled }

    /// Play the drive struggling for `seconds`. Safe to call twice; the second call replaces the
    /// first.
    func playDriveFailure(seconds: TimeInterval) {
        play(Self.driveFailureWAV(seconds: seconds), volume: 0.45)
    }

    /// The Zip drive: heads hunting, hitting the stop, trying again.
    func playZipClick(seconds: TimeInterval) {
        play(Self.zipClickWAV(seconds: seconds), volume: 0.5)
    }

    /// A floppy drive looking for a track that is not there.
    func playFloppySeek(seconds: TimeInterval) {
        play(Self.floppySeekWAV(seconds: seconds), volume: 0.4)
    }

    /// One knock: the picture locking back into place, the relay in a monitor switching modes.
    func playClick() {
        play(Self.clickWAV(), volume: 0.35)
    }

    /// The sound a stage asked for.
    func play(_ which: StageSound, seconds: TimeInterval) {
        switch which {
        case .driveFailure: playDriveFailure(seconds: seconds)
        case .zipClick:     playZipClick(seconds: seconds)
        case .floppySeek:   playFloppySeek(seconds: seconds)
        }
    }

    private func play(_ data: Data?, volume: Float) {
        stop()
        guard isEnabled, let data else { return }
        let s = NSSound(data: data)
        s?.volume = volume
        sound = s
        s?.play()
    }

    func stop() {
        sound?.stop()
        sound = nil
    }

    // MARK: - Synthesis

    private static let sampleRate = 22_050.0

    /// A mono 16-bit WAV of a drive spinning up, seeking, and then clicking.
    static func driveFailureWAV(seconds: TimeInterval) -> Data? {
        let n = Int(seconds * sampleRate)
        guard n > 0 else { return nil }
        var samples = [Float](repeating: 0, count: n)

        var rng = SystemRandomNumberGenerator()

        // 1. Spindle. Starts at rest, sweeps up over the first second and a half, then holds with
        //    a slow wobble — a platter is never perfectly balanced.
        let holdHz = 118.0
        var phase = 0.0, phase2 = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let spin = min(1.0, t / 1.5)
            let hz = holdHz * (0.35 + 0.65 * spin)
            let wobble = 1.0 + 0.012 * sin(2 * .pi * 3.1 * t)
            phase += 2 * .pi * hz * wobble / sampleRate
            phase2 += 2 * .pi * hz * 2.02 / sampleRate
            let body = sin(phase) * 0.55 + sin(phase2) * 0.18
            samples[i] += Float(body * 0.30 * spin)
        }

        // 2. Seeks in the first half, then the click of death: slower, harder, regular. That
        //    change of rhythm is what makes it sound like failure rather than work.
        var clickTimes: [(Double, Double)] = []   // time, strength
        var t = 0.35
        while t < seconds {
            let failing = t > seconds * 0.45
            let gap = failing
                ? Double.random(in: 0.42...0.58, using: &rng)      // the recalibrate-and-retry beat
                : Double.random(in: 0.06...0.22, using: &rng)
            clickTimes.append((t, failing ? Double.random(in: 0.75...1.0, using: &rng)
                                          : Double.random(in: 0.25...0.5, using: &rng)))
            t += gap
        }
        for (start, strength) in clickTimes {
            knock(&samples, at: start, strength: strength, length: 0.018, rng: &rng)
        }

        fadeOut(&samples, seconds: 0.12)
        return wav(samples)
    }

    /// The Zip drive. No spindle: what you heard was the actuator, a short run-out and a knock,
    /// again and again, about twice a second, sometimes twice in a row.
    static func zipClickWAV(seconds: TimeInterval) -> Data? {
        let n = Int(seconds * sampleRate)
        guard n > 0 else { return nil }
        var samples = [Float](repeating: 0, count: n)
        var rng = SystemRandomNumberGenerator()

        var t = 0.15
        var cycle = 0
        while t < seconds {
            // The whirr: a quarter second of the actuator motor, rising slightly as it speeds up.
            let run = Double.random(in: 0.15...0.25, using: &rng)
            whirr(&samples, from: t, length: run, hz: 62, rise: 1.25, strength: 0.22, rng: &rng)
            // The knock: the heads hitting the stop. Harder and lower than a hard disk's.
            knock(&samples, at: t + run, strength: 1.0, length: 0.026, rng: &rng)
            thud(&samples, at: t + run, hz: 190, length: 0.045, strength: 0.55)
            cycle += 1
            // Every third to fifth cycle the heads bounce: a second, softer knock right after.
            if cycle % Int.random(in: 3...5, using: &rng) == 0 {
                knock(&samples, at: t + run + 0.07, strength: 0.6, length: 0.018, rng: &rng)
                thud(&samples, at: t + run + 0.07, hz: 220, length: 0.03, strength: 0.3)
            }
            t += run + Double.random(in: 0.35...0.75, using: &rng)
        }

        fadeOut(&samples, seconds: 0.08)
        return wav(samples)
    }

    /// The floppy drive: a quick stepper buzz, a light knock at the end of travel, three or four
    /// times while DOS decides the disk is not there.
    static func floppySeekWAV(seconds: TimeInterval) -> Data? {
        let n = Int(seconds * sampleRate)
        guard n > 0 else { return nil }
        var samples = [Float](repeating: 0, count: n)
        var rng = SystemRandomNumberGenerator()

        var t = 0.1
        while t < seconds {
            let run = Double.random(in: 0.28...0.45, using: &rng)
            whirr(&samples, from: t, length: run, hz: 140, rise: 1.0, strength: 0.16, rng: &rng)
            knock(&samples, at: t + run, strength: 0.45, length: 0.012, rng: &rng)
            t += run + Double.random(in: 0.25...0.5, using: &rng)
        }

        fadeOut(&samples, seconds: 0.08)
        return wav(samples)
    }

    /// One short mechanical knock, on its own.
    static func clickWAV() -> Data? {
        let n = Int(0.12 * sampleRate)
        var samples = [Float](repeating: 0, count: n)
        var rng = SystemRandomNumberGenerator()
        knock(&samples, at: 0.005, strength: 0.9, length: 0.016, rng: &rng)
        thud(&samples, at: 0.005, hz: 240, length: 0.03, strength: 0.35)
        fadeOut(&samples, seconds: 0.03)
        return wav(samples)
    }

    // MARK: - Ingredients

    /// One-pole low-passed white noise under a sharp envelope: a mechanical knock, not a hiss.
    private static func knock(_ samples: inout [Float], at start: Double, strength: Double,
                              length seconds: Double, rng: inout SystemRandomNumberGenerator) {
        let from = Int(start * sampleRate)
        let length = Int(seconds * sampleRate)
        guard from >= 0, from + length < samples.count else { return }
        var noiseState: Float = 0
        for k in 0..<length {
            let env = exp(-Double(k) / (Double(length) * 0.22))
            let white = Float.random(in: -1...1, using: &rng)
            noiseState += (white - noiseState) * 0.35
            samples[from + k] += Float(env * strength * 0.5) * noiseState
        }
    }

    /// The body of a knock: a low sine that dies fast. What makes a Zip drive's stop sound like
    /// a piece of metal rather than a tap on a desk.
    private static func thud(_ samples: inout [Float], at start: Double, hz: Double,
                             length seconds: Double, strength: Double) {
        let from = Int(start * sampleRate)
        let length = Int(seconds * sampleRate)
        guard from >= 0, from + length < samples.count else { return }
        for k in 0..<length {
            let t = Double(k) / sampleRate
            let env = exp(-Double(k) / (Double(length) * 0.3))
            samples[from + k] += Float(sin(2 * .pi * hz * t) * env * strength)
        }
    }

    /// A small motor running: a buzz with a little noise on it, rising by `rise` over its run.
    private static func whirr(_ samples: inout [Float], from start: Double, length seconds: Double,
                              hz: Double, rise: Double, strength: Double,
                              rng: inout SystemRandomNumberGenerator) {
        let from = Int(start * sampleRate)
        let length = Int(seconds * sampleRate)
        guard from >= 0, from + length < samples.count else { return }
        var phase = 0.0
        var noiseState: Float = 0
        for k in 0..<length {
            let p = Double(k) / Double(length)
            let f = hz * (1 + (rise - 1) * p)
            phase += 2 * .pi * f / sampleRate
            // Attack and release so the motor does not start and stop with a click of its own.
            let env = min(1, Double(k) / (0.02 * sampleRate)) * min(1, Double(length - k) / (0.03 * sampleRate))
            let white = Float.random(in: -1...1, using: &rng)
            noiseState += (white - noiseState) * 0.12
            let buzz = sin(phase) * 0.6 + sin(phase * 2) * 0.25 + sin(phase * 3) * 0.1
            samples[from + k] += Float((buzz + Double(noiseState) * 0.5) * env * strength)
        }
    }

    /// Fade the tail so the buffer does not end on a click of its own.
    private static func fadeOut(_ samples: inout [Float], seconds: Double) {
        let n = samples.count
        let fade = Int(seconds * sampleRate)
        for k in 0..<min(fade, n) {
            samples[n - 1 - k] *= Float(k) / Float(fade)
        }
    }

    /// Minimal 16-bit PCM WAV container.
    private static func wav(_ samples: [Float]) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            let clipped = max(-1, min(1, s))
            var v = Int16(clipped * 32_000)
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }
        let rate = UInt32(sampleRate)
        var data = Data()
        func ascii(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        ascii("RIFF"); u32(UInt32(36 + pcm.count)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1)
        u32(rate); u32(rate * 2); u16(2); u16(16)
        ascii("data"); u32(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}
