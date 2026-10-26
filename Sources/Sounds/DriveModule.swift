import AVFoundation
import DriveSynth
import IOKit

/// The silent SSD with the sound of a spinning drive. Platter's engine (`DriveSynth`, MIT,
/// hurtz/platter) synthesizes spindle, heads and chassis and services real disk activity the way
/// a drive would; this feeds it the Mac's I/O totals, minus what the Mac does by itself all day.
final class DriveModule {
    static let profiles: [(id: Int32, name: String)] = [
        (DS_PROFILE_FLOPPY35, "3.5″ floppy (1990s)"),
        (DS_PROFILE_FLOPPY525, "5.25″ floppy (1980s)"),
        (DS_PROFILE_STEPPER, "20 MB stepper drive (1986)"),
        (DS_PROFILE_IDE, "IDE desktop drive (1995)"),
        (DS_PROFILE_DESKTOP, "7200 rpm desktop drive (2005)"),
        (DS_PROFILE_SERVER, "15K server drive"),
    ]

    let node: AVAudioSourceNode
    private let synth: OpaquePointer
    private var timer: Timer?
    private var last: DiskTotals?
    private var lastTime = 0.0
    private var gate = ActivityGate()
    private var powered = false
    /// False when macOS reported no block storage statistics: the drive then plays Ambient.
    private(set) var countersFound = true

    init() {
        let s = ds_create(SoundEngine.sampleRate, .random(in: 1...UInt32.max))!
        synth = s
        node = AVAudioSourceNode(format: SoundEngine.mono) { _, _, frames, list in
            if let out = UnsafeMutableAudioBufferListPointer(list).first?.mData?.assumingMemoryBound(to: Float.self) {
                ds_render(s, out, Int32(frames))
            }
            return noErr
        }
    }

    /// `powered` spins it up or parks it; `listening` is whether real activity reaches it now.
    func apply(_ p: SoundPrefs.Drive, master: Double, powered on: Bool, listening: Bool) {
        ds_set_profile(synth, p.profile)
        ds_set_volume(synth, Float(p.volume))
        ds_set_hum(synth, Float(p.hum))
        ds_set_mode(synth, p.ambient || !countersFound ? DS_MODE_AMBIENT : DS_MODE_LIVE)
        node.volume = Float(master)
        gate.threshold = p.threshold
        gate.minDuration = p.minDuration
        if on != powered { powered = on; ds_set_power(synth, on ? 1 : 0) }
        let poll = on && listening && !p.ambient && countersFound
        if poll, timer == nil {
            last = nil
            let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
            t.tolerance = 0.02
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !poll, let t = timer {
            t.invalidate()
            timer = nil
        }
    }

    /// Spinning, or still spinning down after it was turned off.
    var isAudible: Bool {
        var status = DSStatus()
        ds_get_status(synth, &status)
        return status.silent == 0
    }

    private func tick() {
        let now = Self.readTotals(), time = ProcessInfo.processInfo.systemUptime
        defer { last = now; lastTime = time }
        if now.devices == 0 {
            if countersFound { countersFound = false; SoundEngine.shared.update() }
            return
        }
        guard let prev = last else { return }
        func d(_ a: UInt64, _ b: UInt64) -> UInt64 { a >= b ? a - b : 0 }
        let ro = d(now.readOps, prev.readOps), wo = d(now.writeOps, prev.writeOps)
        let rb = d(now.readBytes, prev.readBytes), wb = d(now.writeBytes, prev.writeBytes)
        // A disk attached or ejected between two readings.
        guard ro < 1_000_000, wo < 1_000_000 else { return }
        if gate.admits(bytes: rb + wb, seconds: time - lastTime, at: time) {
            ds_post_activity(synth, ro, wo, rb, wb)
        }
    }

    // MARK: - Disk totals

    struct DiskTotals { var devices = 0, readOps: UInt64 = 0, writeOps: UInt64 = 0, readBytes: UInt64 = 0, writeBytes: UInt64 = 0 }

    /// The I/O statistics of every block storage device, as Activity Monitor shows them: counts
    /// only, nothing about which files or apps. After Platter's `DiskMonitor`.
    static func readTotals() -> DiskTotals {
        var totals = DiskTotals()
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOBlockStorageDriver"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return totals }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                func num(_ key: String) -> UInt64 { (stats[key] as? NSNumber)?.uint64Value ?? 0 }
                totals.devices += 1
                totals.readOps &+= num("Operations (Read)")
                totals.writeOps &+= num("Operations (Write)")
                totals.readBytes &+= num("Bytes (Read)")
                totals.writeBytes &+= num("Bytes (Write)")
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return totals
    }

    // MARK: - Preview

    /// Three seconds of the drive at work, rendered offline from a drive already spun up and
    /// given a steady made-up workload (Busy mode leaves a floppy idle for seconds at a time).
    static func previewBuffer(_ p: SoundPrefs.Drive) -> AVAudioPCMBuffer {
        let s = ds_create(SoundEngine.sampleRate, 7)!
        defer { ds_destroy(s) }
        ds_set_profile(s, p.profile)
        ds_set_volume(s, Float(p.volume))
        ds_set_hum(s, Float(p.hum))
        ds_set_mode(s, DS_MODE_LIVE)
        ds_set_power(s, 1)
        var scratch = [Float](repeating: 0, count: 4800)
        var status = DSStatus()
        for _ in 0..<300 {   // at most 30 s of spin-up, never kept
            ds_render(s, &scratch, 4800)
            ds_get_status(s, &status)
            if status.ready != 0 { break }
        }
        let chunk = 4800, frames = AVAudioFrameCount(chunk * 30)   // 3 s
        let buffer = AVAudioPCMBuffer(pcmFormat: SoundEngine.mono, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]
        for i in 0..<30 {
            if i % 4 == 0 { ds_post_activity(s, 40, 10, 2_000_000, 500_000) }
            ds_render(s, out + i * chunk, Int32(chunk))
        }
        let tail = Int(SoundEngine.sampleRate * 0.3)
        for i in 0..<tail { out[Int(frames) - tail + i] *= Float(tail - i) / Float(tail) }
        return buffer
    }
}

/// Lets disk activity through only above a throughput threshold, and then for at least
/// `minDuration`, so a burst is heard as an access rather than a lone tick.
struct ActivityGate {
    var threshold = 1_000_000.0
    var minDuration = 0.2
    private var openUntil = -Double.infinity

    mutating func admits(bytes: UInt64, seconds: Double, at now: Double) -> Bool {
        if Double(bytes) / max(seconds, 0.001) >= threshold { openUntil = now + minDuration }
        return now < openUntil
    }
}
