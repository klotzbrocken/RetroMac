import XCTest
@testable import RetroMac

/// `defaults read` prints a boolean as `1`/`0`, but `defaults write … -bool 1` is REJECTED
/// (exit 255 — it only accepts true/false/yes/no). Writing a snapshotted original back verbatim
/// therefore failed every time, so the user's setting was never restored and the snapshot entry
/// could never be retired. These tests pin the translation that fixes it.
final class SystemTweaksLiteralTests: XCTestCase {

    func testBoolReadBackFormIsTranslatedToAWritableLiteral() {
        // Exactly what `defaults read` hands back for a bool.
        XCTAssertEqual(SystemTweaksAdapter.literal("bool", "1"), "true")
        XCTAssertEqual(SystemTweaksAdapter.literal("bool", "0"), "false")
    }

    func testBoolWordFormsArePassedThroughInWritableForm() {
        for v in ["true", "TRUE", "True", "yes", "YES"] {
            XCTAssertEqual(SystemTweaksAdapter.literal("bool", v), "true", "input \(v)")
        }
        for v in ["false", "FALSE", "no", "NO"] {
            XCTAssertEqual(SystemTweaksAdapter.literal("bool", v), "false", "input \(v)")
        }
    }

    func testBoolValueIsTrimmed() {
        XCTAssertEqual(SystemTweaksAdapter.literal("bool", " 1 "), "true")
    }

    func testNonBoolTypesAreUntouched() {
        // int / float / string round-trip through `defaults read` unchanged and must not be
        // rewritten — "1" stays "1" for an int, and a string like "Nlsv" must survive verbatim.
        XCTAssertEqual(SystemTweaksAdapter.literal("int", "1"), "1")
        XCTAssertEqual(SystemTweaksAdapter.literal("float", "2"), "2")
        XCTAssertEqual(SystemTweaksAdapter.literal("string", "Nlsv"), "Nlsv")
        XCTAssertEqual(SystemTweaksAdapter.literal("string", "1"), "1")
        XCTAssertEqual(SystemTweaksAdapter.literal("string", "Always"), "Always")
    }

    func testUnrecognisedBoolValueIsLeftAlone() {
        // Don't invent a value we can't justify — pass it through and let `defaults` reject it.
        XCTAssertEqual(SystemTweaksAdapter.literal("bool", "maybe"), "maybe")
    }

    /// Every bool tweak the shipped themes declare must already be in a writable form, so
    /// applying a theme never hits the same rejection from the other direction.
    func testShippedThemeBoolTweaksAreWritable() throws {
        let themesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes")
        let bundles = try FileManager.default.contentsOfDirectory(at: themesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "retromactheme" }

        for url in bundles {
            let cfg = try ThemeBundle(url: url, isBuiltIn: true).config
            for t in cfg.systemTweaks ?? [] where t.type == "bool" {
                XCTAssertTrue(["true", "false"].contains(SystemTweaksAdapter.literal(t.type, t.value)),
                              "\(cfg.name): \(t.domain)/\(t.key) has unwritable bool value \(t.value)")
            }
        }
    }
}
