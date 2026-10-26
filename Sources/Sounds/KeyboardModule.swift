import AVFoundation
import AppKit

enum KeyProfile: String, Codable, CaseIterable {
    case subtle, clicky, typewriter

    var title: String {
        switch self {
        case .subtle: return "Subtle keyboard"
        case .clicky: return "Clicky keyboard"
        case .typewriter: return "Typewriter"
        }
    }
}

/// A click for every key that goes down, synthesized per keystroke with a slight change of
/// pitch. It listens and nothing else: it learns only which kind of key it was (a letter,
/// Space, Return, a modifier), never what was typed, keeps nothing, and never holds up input.
/// While a password field has secure input on, macOS sends it no keys at all.
final class KeyboardModule {
    enum Kind { case key, space, ret, modifier, up }

    let players = (0..<4).map { _ in AVAudioPlayerNode() }
    private var nextPlayer = 0
    private var monitors: [Any] = []
    private var prefs = SoundPrefs.Keyboard()
    private var lastFlags: NSEvent.ModifierFlags = []

    /// Seeing other apps' keys needs Accessibility; without it the module stays quiet.
    var isTrusted: Bool { AXIsProcessTrusted() }

    func apply(_ p: SoundPrefs.Keyboard, master: Double, active: Bool) {
        prefs = p
        players.forEach { $0.volume = Float(master * p.volume) }
        let listen = active && isTrusted
        if listen && monitors.isEmpty {
            let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0) }) {
                monitors.append(m)
            }
            if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0); return $0 }) {
                monitors.append(m)
            }
        } else if !listen && !monitors.isEmpty {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
        }
    }

    private func handle(_ e: NSEvent) {
        switch e.type {
        case .keyDown:
            guard prefs.keyDown, prefs.repeats || !e.isARepeat else { return }
            play(e.keyCode == 49 ? .space : (e.keyCode == 36 || e.keyCode == 76) ? .ret : .key)
        case .keyUp:
            if prefs.keyUp { play(.up) }
        case .flagsChanged:
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            defer { lastFlags = flags }
            if prefs.modifiers, !flags.subtracting(lastFlags).isEmpty { play(.modifier) }
        default:
            break
        }
    }

    private func play(_ kind: Kind) {
        guard let engine = players[0].engine, engine.isRunning else { return }
        let pitch = 1 + Double.random(in: -1...1) * prefs.pitchVariation * 0.25
        let buffer = Self.click(kind, profile: prefs.profile, pitch: pitch, seed: .random(in: 1...UInt32.max))
        // Round robin; a new click cuts the oldest one off rather than ever waiting.
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    // MARK: - Synthesis

    private struct Spec {
        var length: Double            // seconds
        var thumpHz: Double, thumpDecay: Double, thumpGain: Double
        var clickHz: Double, clickDecay: Double, clickGain: Double
        var bellHz = 0.0, bellGain = 0.0
    }

    private static func spec(_ kind: Kind, _ profile: KeyProfile) -> Spec {
        var s: Spec
        switch profile {
        case .subtle:     s = Spec(length: 0.05, thumpHz: 150, thumpDecay: 0.010, thumpGain: 0.5, clickHz: 1800, clickDecay: 0.006, clickGain: 0.25)
        case .clicky:     s = Spec(length: 0.06, thumpHz: 210, thumpDecay: 0.006, thumpGain: 0.35, clickHz: 3600, clickDecay: 0.004, clickGain: 0.9)
        case .typewriter: s = Spec(length: 0.14, thumpHz: 110, thumpDecay: 0.020, thumpGain: 0.45, clickHz: 1500, clickDecay: 0.015, clickGain: 0.35)
        }
        switch kind {
        case .key: break
        case .space: s.thumpHz *= 0.75; s.thumpGain *= 1.2; s.clickHz *= 0.8; s.length *= 1.3
        case .ret:
            s.thumpGain *= 1.25; s.clickGain *= 1.1
            if profile == .typewriter { s.bellHz = 2200; s.bellGain = 0.35; s.length = 0.7 }
        case .modifier: s.thumpGain *= 0.6; s.clickGain *= 0.6; s.clickHz *= 1.2
        case .up: s.thumpGain = 0; s.clickGain *= 0.45; s.clickHz *= 1.1
        }
        return s
    }

    /// One keystroke: a resonant noise click over a short low thump (and, for a typewriter's
    /// Return, the bell).
    static func click(_ kind: Kind, profile: KeyProfile, pitch: Double, seed: UInt32) -> AVAudioPCMBuffer {
        let s = spec(kind, profile), sr = SoundEngine.sampleRate
        let frames = AVAudioFrameCount(s.length * sr)
        let buffer = AVAudioPCMBuffer(pcmFormat: SoundEngine.mono, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]
        let w = 2 * Double.pi * s.clickHz * pitch / sr, r = 0.97
        let b1 = 2 * r * cos(w), b2 = -r * r
        var y1 = 0.0, y2 = 0.0, rng = seed
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            rng = rng &* 1664525 &+ 1013904223
            let noise = Double(Int32(bitPattern: rng)) / Double(Int32.max)
            let y = (1 - r) * noise * exp(-t / s.clickDecay) + b1 * y1 + b2 * y2
            y2 = y1; y1 = y
            var v = y * 8 * s.clickGain
            v += sin(2 * .pi * s.thumpHz * pitch * t) * exp(-t / s.thumpDecay) * s.thumpGain
            if s.bellGain > 0 { v += sin(2 * .pi * s.bellHz * t) * exp(-(t - 0.04) / 0.25) * s.bellGain * (t > 0.04 ? 1 : 0) }
            out[i] = Float(v * 0.5)
        }
        return buffer
    }

    /// A few keys of typing, ending on Return.
    static func previewBuffer(_ p: SoundPrefs.Keyboard) -> AVAudioPCMBuffer {
        let kinds: [Kind] = [.key, .key, .key, .space, .key, .key, .ret]
        let step = Int(SoundEngine.sampleRate * 0.13)
        let clicks = kinds.enumerated().map { i, k in
            click(k, profile: p.profile, pitch: 1 + Double((i * 7) % 5 - 2) * p.pitchVariation * 0.1, seed: UInt32(i + 1) &* 2654435761)
        }
        let frames = AVAudioFrameCount(step * (kinds.count - 1) + Int(clicks.last!.frameLength))
        let buffer = AVAudioPCMBuffer(pcmFormat: SoundEngine.mono, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]
        out.update(repeating: 0, count: Int(frames))
        for (i, c) in clicks.enumerated() {
            let src = c.floatChannelData![0]
            for j in 0..<Int(c.frameLength) { out[i * step + j] += src[j] }
        }
        return buffer
    }
}
