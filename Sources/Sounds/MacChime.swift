import AVFoundation

/// The Mac's start-up chime, synthesised: an F-sharp major chord (F♯3, A♯3, C♯4, F♯4), struck
/// together and left to ring out over four seconds, as Macs from 1998 on sounded it. Built from
/// sine partials like the device chimes, so RetroMac ships no recording of Apple's.
enum MacChime {
    static let buffer: AVAudioPCMBuffer = {
        let sr = SoundEngine.sampleRate, seconds = 4.0
        let notes: [Double] = [185.0, 233.08, 277.18, 369.99]
        let frames = AVAudioFrameCount(sr * seconds)
        let b = AVAudioPCMBuffer(pcmFormat: SoundEngine.mono, frameCapacity: frames)!
        b.frameLength = frames
        let out = b.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            let env = min(1, t / 0.012) * exp(-t / 1.1)
            var v = 0.0
            for hz in notes {
                // A bright strike that mellows: the upper partials die away faster.
                v += sin(2 * .pi * hz * t) + 0.45 * sin(4 * .pi * hz * t) * exp(-t / 0.5)
                    + 0.2 * sin(6 * .pi * hz * t) * exp(-t / 0.3) + 0.15 * sin(2 * .pi * hz * 1.002 * t)
            }
            out[i] = Float(v * env * 0.11)
        }
        return b
    }()
}
