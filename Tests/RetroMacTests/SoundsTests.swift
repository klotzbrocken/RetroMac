import AVFoundation
import XCTest
@testable import RetroMac

final class SoundsTests: XCTestCase {

    func testEverythingStartsOff() {
        let p = SoundPrefs()
        XCTAssertFalse(p.enabled)
        XCTAssertFalse(p.keyboard.enabled)
        XCTAssertFalse(p.drive.enabled)
        XCTAssertFalse(p.fan.enabled)
        XCTAssertEqual(p.volume, 0.5)
    }

    func testPrefsSurviveARoundTrip() throws {
        var p = SoundPrefs()
        p.enabled = true
        p.drive.profile = 5
        p.fan.response = .fast
        p.keyboard.profile = .typewriter
        let back = try JSONDecoder().decode(SoundPrefs.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }

    func testGateIgnoresBackgroundTrickleAndHoldsABurstOpen() {
        var gate = ActivityGate()
        gate.threshold = 1_000_000
        gate.minDuration = 0.2
        // 40 KB in 0.1 s is 400 KB/s: what the Mac writes to its logs, not heard.
        XCTAssertFalse(gate.admits(bytes: 40_000, seconds: 0.1, at: 10.0))
        // A 5 MB/s burst opens it ...
        XCTAssertTrue(gate.admits(bytes: 500_000, seconds: 0.1, at: 10.1))
        // ... and the trickle after it still gets through for the minimum length,
        XCTAssertTrue(gate.admits(bytes: 1_000, seconds: 0.1, at: 10.2))
        // but not beyond it.
        XCTAssertFalse(gate.admits(bytes: 1_000, seconds: 0.1, at: 10.4))
    }

    func testFanStaysStillBelowTheThresholdAndRunsOnAfterLoad() {
        var curve = FanCurve()
        curve.threshold = 0.35
        curve.decay = 8
        for _ in 0..<30 { _ = curve.step(cpu: 0.2, dt: 1) }
        XCTAssertEqual(curve.speed, 0, accuracy: 0.001)

        for _ in 0..<15 { _ = curve.step(cpu: 0.95, dt: 1) }
        XCTAssertGreaterThan(curve.speed, 0.8)

        // One second after the load is gone it is still clearly running ...
        _ = curve.step(cpu: 0.05, dt: 1)
        XCTAssertGreaterThan(curve.speed, 0.5)
        // ... and after the run-on it has fallen quiet.
        for _ in 0..<12 { _ = curve.step(cpu: 0.05, dt: 1) }
        XCTAssertLessThan(curve.speed, 0.05)
    }

    func testFanIgnoresAShortPeak() {
        var curve = FanCurve()
        for _ in 0..<10 { _ = curve.step(cpu: 0.1, dt: 1) }
        _ = curve.step(cpu: 1, dt: 1)
        _ = curve.step(cpu: 0.1, dt: 1)
        XCTAssertLessThan(curve.speed, 0.15)
    }

    private func peak(_ b: AVAudioPCMBuffer) -> Float {
        (0..<Int(b.frameLength)).reduce(0) { max($0, abs(b.floatChannelData![0][$1])) }
    }

    func testDrivePreviewIsAudibleForEveryDrive() {
        for (id, name) in DriveModule.profiles {
            var p = SoundPrefs.Drive()
            p.profile = id
            let b = DriveModule.previewBuffer(p)
            XCTAssertEqual(Int(b.frameLength), 144_000, name)
            XCTAssertGreaterThan(peak(b), 0.01, name)
            XCTAssertLessThanOrEqual(peak(b), 1.0, name)
        }
    }

    func testClicksAreShortAndAudible() {
        for profile in KeyProfile.allCases {
            for kind in [KeyboardModule.Kind.key, .space, .ret, .modifier, .up] {
                let b = KeyboardModule.click(kind, profile: profile, pitch: 1.03, seed: 42)
                XCTAssertGreaterThan(peak(b), 0.01, "\(profile) \(kind)")
                XCTAssertLessThan(peak(b), 1.0, "\(profile) \(kind)")
                XCTAssertLessThan(Double(b.frameLength) / SoundEngine.sampleRate, 1.0)
            }
        }
        XCTAssertGreaterThan(peak(KeyboardModule.previewBuffer(SoundPrefs.Keyboard())), 0.01)
    }

    func testFanPreviewIsAudible() {
        for profile in FanProfile.allCases {
            XCTAssertGreaterThan(peak(FanModule.previewBuffer(profile)), 0.01, profile.rawValue)
        }
    }
}
