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
        stop()
        guard isEnabled else { return }
        guard let data = Self.driveFailureWAV(seconds: seconds) else { return }
        let s = NSSound(data: data)
        s?.volume = 0.45
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
        var noiseState: Float = 0

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
            let from = Int(start * sampleRate)
            let length = Int(0.018 * sampleRate)
            guard from + length < n else { continue }
            for k in 0..<length {
                let env = exp(-Double(k) / (Double(length) * 0.22))
                // One-pole low-pass on white noise: a mechanical knock, not a hiss.
                let white = Float.random(in: -1...1, using: &rng)
                noiseState += (white - noiseState) * 0.35
                samples[from + k] += Float(env * strength * 0.5) * noiseState
            }
        }

        // 3. Fade the last 120 ms so the buffer does not end on a click of its own.
        let fade = Int(0.12 * sampleRate)
        for k in 0..<min(fade, n) {
            samples[n - 1 - k] *= Float(k) / Float(fade)
        }

        return wav(samples)
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
