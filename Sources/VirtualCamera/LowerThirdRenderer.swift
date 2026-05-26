import AppKit
import Metal

/// Renders retro-styled lower-third "Bauchbinde" overlays for the virtual camera.
/// Two styles: "latenight" (warm gold/amber 90s talk show) and "newsroom" (1987 broadcast news).
/// Generates an RGBA texture that is alpha-composited onto the camera output.
final class LowerThirdRenderer {
    private let device: MTLDevice
    private var cachedTexture: MTLTexture?
    private var cachedName: String = ""
    private var cachedTitle: String = ""
    private var cachedStyle: String = ""
    private var cachedWidth: Int = 0
    private var cachedHeight: Int = 0
    private var animationFrame: Int = 0
    private var isVisible = false
    private var slideProgress: CGFloat = 0.0  // 0 = hidden, 1 = fully visible

    // Pipeline for alpha-over compositing
    private(set) var compositePipeline: MTLRenderPipelineState?

    init(device: MTLDevice) {
        self.device = device
        setupPipeline()
    }

    /// Update animation state (call each frame)
    func tick(enabled: Bool) {
        let targetProgress: CGFloat = enabled ? 1.0 : 0.0
        let speed: CGFloat = 0.06  // ~16 frames to slide in/out

        if slideProgress < targetProgress {
            slideProgress = min(slideProgress + speed, 1.0)
        } else if slideProgress > targetProgress {
            slideProgress = max(slideProgress - speed, 0.0)
        }

        isVisible = slideProgress > 0.001
        animationFrame += 1
    }

    /// Whether the lower third has any visible content to composite
    var hasContent: Bool { isVisible }

    /// Get or regenerate the lower-third texture for compositing
    func texture(name: String, title: String, style: String, width: Int, height: Int) -> MTLTexture? {
        // Regenerate if parameters changed
        if name != cachedName || title != cachedTitle || style != cachedStyle
            || width != cachedWidth || height != cachedHeight {
            cachedTexture = renderTexture(name: name, title: title, style: style, width: width, height: height)
            cachedName = name
            cachedTitle = title
            cachedStyle = style
            cachedWidth = width
            cachedHeight = height
        }
        return cachedTexture
    }

    /// Current slide offset (0 = fully visible, negative = slid left off-screen)
    var slideOffset: CGFloat {
        // Ease-out cubic for smooth slide
        let t = slideProgress
        let eased = 1.0 - pow(1.0 - t, 3)
        return -(1.0 - eased)
    }

    // MARK: - Texture Generation

    private func renderTexture(name: String, title: String, style: String, width: Int, height: Int) -> MTLTexture? {
        guard !name.isEmpty else { return nil }

        let scale: CGFloat = 2.0  // Retina
        let texW = width
        let texH = height
        let drawW = CGFloat(texW) / scale
        let drawH = CGFloat(texH) / scale

        // Lower third occupies bottom ~18% of frame
        let barHeight: CGFloat = drawH * 0.15
        let barY: CGFloat = drawH * 0.08  // from bottom

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: texW, height: texH,
            bitsPerComponent: 8, bytesPerRow: texW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Scale for retina
        ctx.scaleBy(x: scale, y: scale)

        // Flip coordinate system (CG is bottom-up, we want top-down for Metal)
        ctx.translateBy(x: 0, y: drawH)
        ctx.scaleBy(x: 1, y: -1)

        // Clear to transparent
        ctx.clear(CGRect(x: 0, y: 0, width: drawW, height: drawH))

        if style == "newsroom" {
            drawNewsroomLowerThird(ctx: ctx, name: name, title: title, width: drawW, height: drawH, barHeight: barHeight, barY: barY)
        } else {
            drawLateNightLowerThird(ctx: ctx, name: name, title: title, width: drawW, height: drawH, barHeight: barHeight, barY: barY)
        }

        guard let image = ctx.makeImage() else { return nil }

        // Create Metal texture
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: texW, height: texH,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }

        // Copy pixel data
        let region = MTLRegionMake2D(0, 0, texW, texH)
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        texture.replace(region: region, mipmapLevel: 0, withBytes: ptr, bytesPerRow: texW * 4)

        return texture
    }

    // MARK: - Late Night Style (warm gold/amber, 90s talk show)

    private func drawLateNightLowerThird(ctx: CGContext, name: String, title: String, width: CGFloat, height: CGFloat, barHeight: CGFloat, barY: CGFloat) {
        let nameBarHeight = barHeight * 0.60
        let titleBarHeight = barHeight * 0.40
        let nameBarY = height - barY - barHeight
        let titleBarY = nameBarY + nameBarHeight
        let barWidth = width * 0.45
        let barX: CGFloat = width * 0.04

        // Name bar: warm gold gradient
        let nameRect = CGRect(x: barX, y: nameBarY, width: barWidth, height: nameBarHeight)
        ctx.saveGState()
        ctx.clip(to: nameRect)
        let goldColors = [
            CGColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 0.92),
            CGColor(red: 0.72, green: 0.52, blue: 0.04, alpha: 0.92),
        ]
        let goldGrad = CGGradient(colorsSpace: colorSpace, colors: goldColors as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(goldGrad, start: CGPoint(x: barX, y: nameBarY), end: CGPoint(x: barX, y: nameBarY + nameBarHeight), options: [])
        ctx.restoreGState()

        // Title bar: dark navy
        let titleRect = CGRect(x: barX, y: titleBarY, width: barWidth, height: titleBarHeight)
        ctx.setFillColor(CGColor(red: 0.08, green: 0.10, blue: 0.25, alpha: 0.90))
        ctx.fill(titleRect)

        // Thin gold accent line between bars
        ctx.setStrokeColor(CGColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1.0))
        ctx.setLineWidth(1.5)
        ctx.move(to: CGPoint(x: barX, y: titleBarY))
        ctx.addLine(to: CGPoint(x: barX + barWidth, y: titleBarY))
        ctx.strokePath()

        // Left accent stripe
        let stripeWidth: CGFloat = 4
        ctx.setFillColor(CGColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1.0))
        ctx.fill(CGRect(x: barX, y: nameBarY, width: stripeWidth, height: barHeight))

        // Name text (white, bold)
        let nameFont = CTFontCreateWithName("Helvetica-Bold" as CFString, nameBarHeight * 0.55, nil)
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: nameFont,
            .foregroundColor: NSColor.white,
        ]
        let nameStr = NSAttributedString(string: name, attributes: nameAttrs)
        let nameSize = nameStr.size()
        let nameX = barX + stripeWidth + 10
        let nameTextY = nameBarY + (nameBarHeight - nameSize.height) / 2
        let nameNSCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.current = nameNSCtx
        nameStr.draw(at: NSPoint(x: nameX, y: nameTextY))

        // Title text (gold/amber, regular)
        if !title.isEmpty {
            let titleFont = CTFontCreateWithName("Helvetica" as CFString, titleBarHeight * 0.55, nil)
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: NSColor(red: 1.0, green: 0.88, blue: 0.45, alpha: 1.0),
            ]
            let titleStr = NSAttributedString(string: title, attributes: titleAttrs)
            let titleTextY = titleBarY + (titleBarHeight - titleStr.size().height) / 2
            titleStr.draw(at: NSPoint(x: nameX, y: titleTextY))
        }

        NSGraphicsContext.current = nil
    }

    // MARK: - Newsroom 1987 Style (broadcast news, red/blue/white)

    private func drawNewsroomLowerThird(ctx: CGContext, name: String, title: String, width: CGFloat, height: CGFloat, barHeight: CGFloat, barY: CGFloat) {
        let nameBarHeight = barHeight * 0.58
        let titleBarHeight = barHeight * 0.42
        let nameBarY = height - barY - barHeight
        let titleBarY = nameBarY + nameBarHeight
        let barWidth = width * 0.50
        let barX: CGFloat = width * 0.04

        // Name bar: broadcast red gradient
        let nameRect = CGRect(x: barX, y: nameBarY, width: barWidth, height: nameBarHeight)
        ctx.saveGState()
        ctx.clip(to: nameRect)
        let redColors = [
            CGColor(red: 0.80, green: 0.10, blue: 0.10, alpha: 0.93),
            CGColor(red: 0.60, green: 0.05, blue: 0.05, alpha: 0.93),
        ]
        let redGrad = CGGradient(colorsSpace: colorSpace, colors: redColors as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(redGrad, start: CGPoint(x: barX, y: nameBarY), end: CGPoint(x: barX, y: nameBarY + nameBarHeight), options: [])
        ctx.restoreGState()

        // Title bar: dark blue
        let titleRect = CGRect(x: barX, y: titleBarY, width: barWidth, height: titleBarHeight)
        ctx.setFillColor(CGColor(red: 0.05, green: 0.10, blue: 0.40, alpha: 0.92))
        ctx.fill(titleRect)

        // White separator line
        ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.8))
        ctx.setLineWidth(2.0)
        ctx.move(to: CGPoint(x: barX, y: titleBarY))
        ctx.addLine(to: CGPoint(x: barX + barWidth, y: titleBarY))
        ctx.strokePath()

        // Thin white border around entire lower third
        ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.5))
        ctx.setLineWidth(1.0)
        ctx.stroke(CGRect(x: barX, y: nameBarY, width: barWidth, height: barHeight))

        // Name text (white, bold, slightly larger — broadcast style)
        let nameFont = CTFontCreateWithName("Helvetica-Bold" as CFString, nameBarHeight * 0.58, nil)
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: nameFont,
            .foregroundColor: NSColor.white,
        ]
        let nameStr = NSAttributedString(string: name.uppercased(), attributes: nameAttrs)
        let nameSize = nameStr.size()
        let nameX = barX + 12
        let nameTextY = nameBarY + (nameBarHeight - nameSize.height) / 2

        let nameNSCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.current = nameNSCtx
        nameStr.draw(at: NSPoint(x: nameX, y: nameTextY))

        // Title text (white, regular)
        if !title.isEmpty {
            let titleFont = CTFontCreateWithName("Helvetica" as CFString, titleBarHeight * 0.52, nil)
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95),
            ]
            let titleStr = NSAttributedString(string: title, attributes: titleAttrs)
            let titleTextY = titleBarY + (titleBarHeight - titleStr.size().height) / 2
            titleStr.draw(at: NSPoint(x: nameX, y: titleTextY))
        }

        NSGraphicsContext.current = nil
    }

    private var colorSpace: CGColorSpace { CGColorSpaceCreateDeviceRGB() }

    // MARK: - Metal Compositing Pipeline

    private func setupPipeline() {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct LTVertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        struct LTVertexData {
            packed_float2 position;
            packed_float2 texCoord;
        };

        vertex LTVertexOut lt_vertex(
            uint vid [[vertex_id]],
            const device LTVertexData* vertices [[buffer(0)]],
            constant float& slideX [[buffer(1)]]
        ) {
            LTVertexOut out;
            float2 pos = vertices[vid].position;
            pos.x += slideX * 2.0;  // slide in NDC space
            out.position = float4(pos, 0.0, 1.0);
            out.texCoord = vertices[vid].texCoord;
            return out;
        }

        fragment float4 lt_fragment(
            LTVertexOut in [[stage_in]],
            texture2d<float> tex [[texture(0)]],
            sampler s [[sampler(0)]]
        ) {
            return tex.sample(s, in.texCoord);
        }
        """

        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vertexFn = library.makeFunction(name: "lt_vertex"),
              let fragmentFn = library.makeFunction(name: "lt_fragment") else { return }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFn
        desc.fragmentFunction = fragmentFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0].isBlendingEnabled = true
        // Standard alpha-over: src.rgb * src.a + dst.rgb * (1 - src.a)
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        compositePipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }
}
