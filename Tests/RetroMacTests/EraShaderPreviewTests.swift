import XCTest
import Metal
@testable import RetroMac

/// Not an assertion test: a way to LOOK at a shader before it ships.
///
/// The era shaders trade nostalgia against readability, and where that line sits cannot be
/// reasoned about, only seen. This renders each one over a real desktop screenshot at display
/// resolution and writes a PNG, so the choice is made from the picture rather than from the code.
/// Set RETROMAC_SHADER_PREVIEW to a source image to run it.
final class EraShaderPreviewTests: XCTestCase {

    func testRenderEraShaderPreviews() throws {
        let env = ProcessInfo.processInfo.environment
        guard let src = env["RETROMAC_SHADER_PREVIEW"] else {
            throw XCTSkip("Set RETROMAC_SHADER_PREVIEW=<image path> to render previews.")
        }
        let outDir = env["RETROMAC_SHADER_PREVIEW_OUT"] ?? NSTemporaryDirectory()
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }

        let renderer = try RetroRenderer(device: device)
        renderer.intensity = 1.0
        renderer.vignetteIntensity = 0.0

        let loader = MTKTextureLoaderLite(device: device)
        let texture = try XCTUnwrap(loader.load(from: URL(fileURLWithPath: src)),
                                    "could not load \(src)")
        let size = CGSize(width: texture.width, height: texture.height)

        let names = (ProcessInfo.processInfo.environment["RETROMAC_SHADER_NAMES"]?
            .split(separator: ",").map(String.init))
            ?? ["lcd-tft-fine", "lcd-tft", "crt-readable-fine", "crt-readable"]
        for name in names {
            try renderer.loadShader(named: name)
            let image = try XCTUnwrap(renderer.renderToImage(sourceTexture: texture, viewportSize: size),
                                      "\(name) produced no image")
            let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
            try png.write(to: url)
            print("[preview] \(url.path)")
        }
    }
}
