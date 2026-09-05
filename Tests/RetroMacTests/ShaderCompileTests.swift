import XCTest
import Metal
@testable import RetroMac

/// Every preset the picker offers has to compile, or the user picks a name and silently gets
/// something else: `WallpaperShaderController.create` falls back to zfast-crt when a preset fails
/// to load, and the whole-screen path leaves the previous shader in place. Neither says anything
/// on screen, which is exactly how a broken preset survives a release.
final class ShaderCompileTests: XCTestCase {

    func testEveryPresetInThePickerCompiles() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        let renderer = try RetroRenderer(device: device)

        var failures: [String] = []
        var compiled = 0
        for (category, presets) in PresetRegistry.categorizedPresets {
            for preset in presets where !preset.isCustom {
                do {
                    try renderer.loadShader(named: preset.id)
                    compiled += 1
                } catch {
                    failures.append("[\(category.rawValue)] \(preset.id): \(error)")
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "presets that do not compile:\n" + failures.joined(separator: "\n"))
        XCTAssertGreaterThan(compiled, 50, "the picker lost most of its presets")
    }

    /// A preset in one list and not the other is invisible or broken, and neither shows up at
    /// runtime. They are two hand-maintained lists, so they get an assertion.
    func testPickerAndShaderRegistryAgree() {
        let picker = Set(PresetRegistry.builtinPresets.filter { !$0.isCustom }.map(\.id))
        let registered = Set(BuiltinShaders.allPresetIDs)
        XCTAssertEqual(picker.subtracting(registered), [], "in the picker with no shader behind it")
        XCTAssertEqual(registered.subtracting(picker), [], "compiled but unreachable from the picker")
    }
}
