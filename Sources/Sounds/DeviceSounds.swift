import AVFoundation
import AppKit
import IOKit

/// Windows 2000 and later chimed when a USB device came or went. Under the XP, Vista and 7 themes
/// RetroMac does too, with a chime of its own (rising for a device in, falling for one out), and
/// only where macOS itself would play interface sounds.
///
/// IOKit matching notifications on IOUSBHostDevice; after macOS 7 Ultimate SP1's
/// DeviceSoundMonitor (github.com/kaganisildak/macOS-7-Ultimate-SP1, GPL-3.0).
final class DeviceSounds {
    static let shared = DeviceSounds()
    static let themes: Set<String> = ["com.retromac.microsoft.windowsxp", "com.retromac.microsoft.windowsvista",
                                      "com.retromac.microsoft.windows7"]

    private var port: IONotificationPortRef?
    private var added: io_iterator_t = 0
    private var removed: io_iterator_t = 0
    private var gate = DeviceSoundGate()

    func start() {
        guard port == nil, let p = IONotificationPortCreate(kIOMainPortDefault) else { return }
        port = p
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.gate.willSleep()
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.gate.didWake(at: ProcessInfo.processInfo.systemUptime)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(p).takeUnretainedValue(), .defaultMode)
        let me = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            Unmanaged<DeviceSounds>.fromOpaque(refcon).takeUnretainedValue().fired(iterator)
        }
        IOServiceAddMatchingNotification(p, kIOFirstMatchNotification, IOServiceMatching("IOUSBHostDevice"), callback, me, &added)
        IOServiceAddMatchingNotification(p, kIOTerminatedNotification, IOServiceMatching("IOUSBHostDevice"), callback, me, &removed)
        // Arm both; what is plugged in already makes no sound.
        _ = Self.drain(added)
        _ = Self.drain(removed)
    }

    private func fired(_ iterator: io_iterator_t) {
        guard Self.drain(iterator) > 0 else { return }
        let connect = iterator == added
        guard gate.shouldPlay(connect: connect, at: ProcessInfo.processInfo.systemUptime), Self.wanted else { return }
        SoundEngine.shared.playEvent(Self.chime(connect: connect))
    }

    private static func drain(_ iterator: io_iterator_t) -> Int {
        var n = 0
        while case let obj = IOIteratorNext(iterator), obj != 0 {
            IOObjectRelease(obj)
            n += 1
        }
        return n
    }

    static var wanted: Bool {
        let p = AppSettings.shared.sounds
        return p.enabled && p.deviceSounds && uiSoundsOn
            && themes.contains(ThemeManager.shared.activeTheme?.config.id ?? "")
    }

    /// System Settings ▸ Sound ▸ "Play user interface sound effects", which lives in
    /// com.apple.systemsound (then the global domain) and is on when unset.
    static var uiSoundsOn: Bool {
        let key = "com.apple.sound.uiaudio.enabled" as CFString
        let value = CFPreferencesCopyAppValue(key, "com.apple.systemsound" as CFString)
            ?? CFPreferencesCopyAppValue(key, kCFPreferencesAnyApplication)
        return (value as? NSNumber)?.boolValue ?? true
    }

    /// Two soft bell tones, a fourth apart: up for a device in, down for one out.
    static func chime(connect: Bool) -> AVAudioPCMBuffer {
        let sr = SoundEngine.sampleRate, notes: [Double] = connect ? [784, 1046.5] : [1046.5, 784]
        let frames = AVAudioFrameCount(sr * 0.75)
        let buffer = AVAudioPCMBuffer(pcmFormat: SoundEngine.mono, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            var v = 0.0
            for (n, hz) in notes.enumerated() {
                let tn = t - Double(n) * 0.14
                guard tn >= 0 else { continue }
                let env = min(1, tn / 0.005) * exp(-tn / 0.18)
                v += (sin(2 * .pi * hz * tn) + 0.3 * sin(4 * .pi * hz * tn) + 0.1 * sin(6 * .pi * hz * tn)) * env
            }
            out[i] = Float(v * 0.3)
        }
        return buffer
    }
}

/// One chime per kind per second (a device fires a notification per interface), and none from
/// sleep until five seconds after waking, when USB devices drop and come back.
struct DeviceSoundGate {
    static let wakeQuiet = 5.0
    private var last: [Bool: Double] = [:]
    private var quietUntil = -Double.infinity

    mutating func willSleep() { quietUntil = .infinity }
    mutating func didWake(at now: Double) { quietUntil = now + Self.wakeQuiet }

    mutating func shouldPlay(connect: Bool, at now: Double) -> Bool {
        defer { last[connect] = now }
        let debounced = last[connect].map { now - $0 >= 1 } ?? true
        return debounced && now >= quietUntil
    }
}
