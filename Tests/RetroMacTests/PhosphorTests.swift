import XCTest
import Metal
@testable import RetroMac

/// The afterglow fades like the preset's monitor did, and its shader compiles.
final class PhosphorTests: XCTestCase {
    func testMonochromePresetsHaveTheirPhosphor() {
        XCTAssertEqual(PhosphorPersistence.phosphor(forPreset: "amber-monitor"), PhosphorPersistence.p3)
        XCTAssertEqual(PhosphorPersistence.phosphor(forPreset: "green-phosphor"), PhosphorPersistence.p39)
        XCTAssertEqual(PhosphorPersistence.phosphor(forPreset: "terminal-green"), PhosphorPersistence.p1)
        XCTAssertNil(PhosphorPersistence.phosphor(forPreset: "crt-geom"))   // colour tube: an effect, no phosphor
        for id in ["amber-monitor", "green-phosphor", "terminal-green"] {
            XCTAssertTrue(BuiltinShaders.allPresetIDs.contains(id), id)
        }
    }

    /// RCA's times: 10 % of the light is left after 13 ms (P3), 24.5 ms (P1), 150 ms (P39).
    func testTenPercentTimes() {
        func tenth(_ p: PhosphorPersistence.Phosphor) -> Double { p.hyperbolic ? 9 * p.tau : p.tau * log(10) }
        XCTAssertEqual(tenth(PhosphorPersistence.p3), 0.013, accuracy: 0.0005)
        XCTAssertEqual(tenth(PhosphorPersistence.p1), 0.0245, accuracy: 0.0005)
        XCTAssertEqual(tenth(PhosphorPersistence.p39), 0.150, accuracy: 0.001)
    }

    func testShaderCompiles() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        XCTAssertNoThrow(try PhosphorPersistence(device: device))
    }
}
