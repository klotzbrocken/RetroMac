import XCTest
@testable import RetroMac

/// Frame-rate resolution and per-app preset lookup. Both used to be tangled into
/// `AppSettings.init` / the singleton; the pure parts are split out so they can be checked
/// without touching the real user defaults.
final class FrameRateTests: XCTestCase {

    /// Every value the frame-rate picker offers (AdvancedTab). A profile that falls back to a
    /// value outside this set leaves the control with no selection at all.
    private let pickerTags: Set<Int> = [30, 60, 120]

    func testClampRejectsValuesThatWouldMakeAnInvalidCMTime() {
        // targetFPS reaches SCStreamConfiguration.minimumFrameInterval as a CMTimeScale,
        // where 0 or a negative value is not a valid CMTime.
        XCTAssertEqual(AppSettings.clampFPS(0), 15)
        XCTAssertEqual(AppSettings.clampFPS(-5), 15)
        XCTAssertEqual(AppSettings.clampFPS(1), 15)
        XCTAssertEqual(AppSettings.clampFPS(9_999), 240)
    }

    func testClampLeavesEveryOfferedRateAlone() {
        for fps in pickerTags {
            XCTAssertEqual(AppSettings.clampFPS(fps), fps)
        }
    }

    func testEveryPerformanceProfileFallsBackToAnOfferedRate() {
        for profile in PerformanceProfile.allCases {
            XCTAssertTrue(pickerTags.contains(profile.targetFPS),
                          "\(profile) falls back to \(profile.targetFPS) fps, which the picker does not offer")
        }
    }

    func testFreshInstallTakesTheProfileRateAndIsNotUserSet() {
        let r = AppSettings.resolveFPS(stored: nil, lowLatency: false, userSet: false, profileFPS: 30)
        XCTAssertEqual(r.fps, 30)
        XCTAssertFalse(r.userSet)
    }

    func testStoredValueIsClampedOnLoad() {
        XCTAssertEqual(AppSettings.resolveFPS(stored: 0, lowLatency: false, userSet: false, profileFPS: 30).fps, 15)
        XCTAssertEqual(AppSettings.resolveFPS(stored: -1, lowLatency: false, userSet: true, profileFPS: 30).fps, 15)
    }

    func testOldLowLatencySwitchMigratesToSixtyAndCountsAsDeliberate() {
        // "Low-latency mode" was a hidden 60 fps toggle. Anyone who had it on chose 60 on purpose.
        let r = AppSettings.resolveFPS(stored: 30, lowLatency: true, userSet: false, profileFPS: 30)
        XCTAssertEqual(r.fps, 60)
        XCTAssertTrue(r.userSet)
    }

    func testLowLatencyDoesNotDowngradeAHigherChoice() {
        let r = AppSettings.resolveFPS(stored: 120, lowLatency: true, userSet: true, profileFPS: 30)
        XCTAssertEqual(r.fps, 120)
        XCTAssertTrue(r.userSet)
    }

    func testAnExplicitChoiceSurvivesReload() {
        let r = AppSettings.resolveFPS(stored: 60, lowLatency: false, userSet: true, profileFPS: 30)
        XCTAssertEqual(r.fps, 60)
        XCTAssertTrue(r.userSet, "a deliberate frame rate must stay marked as deliberate, or the quality picker resets it")
    }
}

/// `presetForApp` reads the current rule model and falls back to the dictionary it was
/// migrated from. It used to read only the legacy dictionary, so rules added through the
/// settings UI never took effect.
final class PerAppPresetTests: XCTestCase {

    private func rule(_ id: String) -> AppSettings.PerAppRule { .init(presetID: id, reason: nil) }

    func testRuleWinsOverTheLegacyDictionary() {
        let got = AppSettings.preset(for: "com.apple.Safari",
                                     rules: ["com.apple.Safari": rule("crt-royale")],
                                     legacy: ["com.apple.Safari": "ntsc"])
        XCTAssertEqual(got, "crt-royale")
    }

    func testLegacyDictionaryIsUsedWhenNoRuleExists() {
        let got = AppSettings.preset(for: "com.apple.Safari", rules: [:],
                                     legacy: ["com.apple.Safari": "ntsc"])
        XCTAssertEqual(got, "ntsc")
    }

    func testUnknownAppHasNoPreset() {
        XCTAssertNil(AppSettings.preset(for: "com.example.nothing", rules: [:], legacy: [:]))
    }

    func testEmptyPresetIDIsPreservedNotTreatedAsMissing() {
        // "" is a real choice: "None — overlay off". It must not fall through to the legacy value.
        let got = AppSettings.preset(for: "com.apple.Safari",
                                     rules: ["com.apple.Safari": rule("")],
                                     legacy: ["com.apple.Safari": "ntsc"])
        XCTAssertEqual(got, "")
    }
}
