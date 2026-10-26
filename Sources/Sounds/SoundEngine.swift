import AVFoundation
import AppKit
import Combine
import CoreAudio
import DriveSynth

/// Settings ▸ Sounds, saved as one record. Everything starts off: no spin-up and no click
/// after an install until someone turns a module on.
// ponytail: one Codable record; a field added later without a decodeIfPresent init resets
// the user's sound settings once. Add the init when the record grows (Part 2).
struct SoundPrefs: Codable, Equatable {
    var enabled = false
    var volume = 0.5
    var startAtLaunch = true
    var pauseOnScreenSharing = true
    var pauseOnRecording = true
    var pauseWhenMuted = true
    var keyboard = Keyboard()
    var drive = Drive()
    var fan = Fan()

    struct Keyboard: Codable, Equatable {
        var enabled = false
        var profile = KeyProfile.subtle
        var keyDown = true
        var keyUp = false
        var modifiers = false
        var repeats = false
        var volume = 0.25
        var pitchVariation = 0.15
    }

    struct Drive: Codable, Equatable {
        var enabled = false
        var profile = DS_PROFILE_IDE
        var volume = 0.6
        var hum = 0.5
        var sensitivity = Sensitivity.balanced
        var customThreshold = 1_000_000.0   // bytes per second
        var minDuration = 0.2
        var ambient = false

        /// Disk throughput below which the drive keeps quiet: what the Mac writes to its logs
        /// all day should not keep it seeking.
        var threshold: Double {
            switch sensitivity {
            case .quiet: return 4_000_000
            case .balanced: return 1_000_000
            case .clear: return 150_000
            case .custom: return customThreshold
            }
        }
    }

    enum Sensitivity: String, Codable, CaseIterable { case quiet, balanced, clear, custom }

    struct Fan: Codable, Equatable {
        var enabled = false
        var profile = FanProfile.desktop
        var baseNoise = false
        var threshold = 0.35
        var volume = 0.30
        var response = Response.medium
        var decay = 8.0
    }

    enum Response: String, Codable, CaseIterable { case slow, medium, fast }
}

/// The one audio engine behind the keyboard, the drive and the fan. It runs only while
/// something should be heard, pauses (rather than powering the modules off) while a microphone
/// is recording, the screen is shared or the Mac sleeps, and follows the Mac's output device.
final class SoundEngine: ObservableObject {
    static let shared = SoundEngine()
    static let sampleRate = 48_000.0
    static let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    enum Module: CaseIterable { case keyboard, drive, fan }

    /// Why the sounds are quiet although they are on; nil while they play or are off.
    @Published private(set) var pauseReason: String?
    /// "Pause all": quiet until resumed or RetroMac quits.
    @Published var held = false { didSet { update() } }

    let drive = DriveModule()
    let fan = FanModule()
    let keyboard = KeyboardModule()

    private let engine = AVAudioEngine()
    private let preview = AVAudioPlayerNode()
    private lazy var graph: Void = build()
    private var subs: Set<AnyCancellable> = []
    private var watch: Timer?
    private var asleep = false
    private var previewing = false
    private var wantsRun = false

    private init() {}

    private var prefs: SoundPrefs { AppSettings.shared.sounds }

    /// Called once at launch. Builds no audio graph until a sound is wanted.
    func start() {
        guard subs.isEmpty else { return }
        if prefs.enabled && !prefs.startAtLaunch { held = true }
        AppSettings.shared.$sounds.dropFirst().removeDuplicates()
            .sink { [weak self] p in self?.update(p) }.store(in: &subs)
        let ws = NSWorkspace.shared.notificationCenter
        for (name, sleeping) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false),
                                 (NSWorkspace.sessionDidResignActiveNotification, true),
                                 (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
            ws.publisher(for: name).sink { [weak self] _ in self?.setAsleep(sleeping) }.store(in: &subs)
        }
        let dist = DistributedNotificationCenter.default()
        dist.publisher(for: .init("com.apple.screenIsLocked")).sink { [weak self] _ in self?.setAsleep(true) }.store(in: &subs)
        dist.publisher(for: .init("com.apple.screenIsUnlocked")).sink { [weak self] _ in self?.setAsleep(false) }.store(in: &subs)
        // The output device changed: the engine stopped itself and comes back on the new one.
        NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange, object: engine)
            .delay(for: .seconds(0.25), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.restart() }.store(in: &subs)
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.prefs.enabled || self.engine.isRunning else { return }
            self.update()
        }
        RunLoop.main.add(t, forMode: .common)
        watch = t
        update()
    }

    private func setAsleep(_ value: Bool) {
        asleep = value
        if !value { restart() } else { update() }
    }

    private func build() {
        let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        let bus = AVAudioMixerNode()
        engine.attach(limiter)
        engine.attach(bus)
        engine.connect(limiter, to: engine.mainMixerNode, format: nil)
        engine.connect(bus, to: limiter, format: nil)
        for node in [drive.node, fan.node, preview] + keyboard.players {
            engine.attach(node)
            engine.connect(node, to: bus, format: Self.mono)
        }
    }

    func update(_ given: SoundPrefs? = nil) {
        let p = given ?? prefs
        let reason = p.enabled ? pauseReason(p) : nil
        if reason != pauseReason { pauseReason = reason }
        let playing = p.enabled && !held && reason == nil
        drive.apply(p.drive, master: p.volume, powered: p.enabled && p.drive.enabled, listening: playing)
        fan.apply(p.fan, master: p.volume, active: playing && p.fan.enabled)
        keyboard.apply(p.keyboard, master: p.volume, active: playing && p.keyboard.enabled)
        // A drive turned off still parks and spins down; the master switch cuts it at once.
        let audible = p.drive.enabled || p.fan.enabled || p.keyboard.enabled || drive.isAudible
        setRunning((playing && audible) || previewing, release: !p.enabled)
        objectWillChange.send()
    }

    private func pauseReason(_ p: SoundPrefs) -> String? {
        if asleep { return "Paused while the Mac sleeps or is locked." }
        if p.pauseOnRecording && Self.inputInUse() { return "Paused: a microphone or audio input is in use." }
        if p.pauseOnScreenSharing && Self.screenShared() { return "Paused: the screen is being shared." }
        if p.pauseWhenMuted && SystemVolume.isMuted { return "Paused: the Mac is muted." }
        return nil
    }

    // MARK: - Running

    var isRunning: Bool { engine.isRunning }

    private func setRunning(_ run: Bool, release: Bool) {
        wantsRun = run
        if run {
            guard !engine.isRunning else { return }
            _ = graph
            engine.mainMixerNode.outputVolume = 0
            engine.prepare()
            do { try engine.start() } catch { NSLog("RetroMac sounds: engine did not start: \(error)"); return }
            keyboard.players.forEach { $0.play() }
            fade(to: 1) {}
        } else if engine.isRunning {
            // A short fade instead of a click when everything stops at once.
            fade(to: 0) { [weak self] in
                guard let self, !self.wantsRun else { return }
                release ? self.engine.stop() : self.engine.pause()
            }
        }
    }

    private func restart() {
        guard wantsRun else { return update() }
        engine.stop()
        wantsRun = false
        update()
    }

    private var fadeGeneration = 0

    private func fade(to target: Float, steps: Int = 8, then done: @escaping () -> Void) {
        fadeGeneration += 1
        let mixer = engine.mainMixerNode, start = mixer.outputVolume, generation = fadeGeneration
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(15 * i)) { [weak self] in
                guard self?.fadeGeneration == generation else { return }
                mixer.outputVolume = start + (target - start) * Float(i) / Float(steps)
                if i == steps { done() }
            }
        }
    }

    // MARK: - Preview

    /// A few seconds of a module, whether it is on or not, at its own and the master volume.
    func preview(_ module: Module) {
        let p = prefs
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let buffer: AVAudioPCMBuffer
            let volume: Double
            switch module {
            case .keyboard: buffer = KeyboardModule.previewBuffer(p.keyboard); volume = p.keyboard.volume
            case .drive: buffer = DriveModule.previewBuffer(p.drive); volume = 1
            case .fan: buffer = FanModule.previewBuffer(p.fan.profile); volume = p.fan.volume
            }
            DispatchQueue.main.async { self?.play(buffer, volume: Float(volume * p.volume)) }
        }
    }

    private func play(_ buffer: AVAudioPCMBuffer, volume: Float) {
        previewing = true
        update()
        guard engine.isRunning else { previewing = false; return }
        preview.volume = volume
        preview.scheduleBuffer(buffer, at: nil, options: .interrupts)
        preview.play()
        let seconds = Double(buffer.frameLength) / Self.sampleRate + 0.2
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.previewing = false
            self?.update()
        }
    }

    // MARK: - What pauses it

    /// Whether some app records from the default input. Where input and output are one device
    /// (a USB headset), our own playback keeps it running, so that case cannot tell.
    static func inputInUse() -> Bool {
        func device(_ selector: AudioObjectPropertySelector) -> AudioDeviceID {
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
            var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
            return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr ? id : 0
        }
        let input = device(kAudioHardwarePropertyDefaultInputDevice)
        guard input != 0, input != device(kAudioHardwarePropertyDefaultOutputDevice) else { return false }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(input, &addr, 0, nil, &size, &running) == noErr && running != 0
    }

    /// macOS Screen Sharing serving a viewer: launchd starts screensharingd for a session only.
    /// Sharing from a video call app has no public tell; the microphone pause covers calls.
    static func screenShared() -> Bool {
        var name = [CChar](repeating: 0, count: 64)
        return SystemSampler.allPIDs().contains { proc_name($0, &name, 64) > 0 && String(cString: name) == "screensharingd" }
    }
}
