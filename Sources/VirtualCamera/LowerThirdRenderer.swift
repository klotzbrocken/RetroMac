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
    private var cachedHandle: String = ""
    private var cachedAccent: String = ""
    private var cachedLogoPath: String = ""
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
    func texture(name: String, title: String, handle: String, style: String,
                 accentHex: String, logoPath: String, width: Int, height: Int) -> MTLTexture? {
        // Regenerate if parameters changed
        if name != cachedName || title != cachedTitle || style != cachedStyle
            || handle != cachedHandle || accentHex != cachedAccent || logoPath != cachedLogoPath
            || width != cachedWidth || height != cachedHeight {
            // Keep the last good texture if a render transiently fails — otherwise a single
            // failed frame would blank the bar and read as a flicker.
            if let tex = renderTexture(name: name, title: title, handle: handle, style: style,
                                       accentHex: accentHex, logoPath: logoPath, width: width, height: height) {
                cachedTexture = tex
            }
            cachedName = name
            cachedTitle = title
            cachedStyle = style
            cachedHandle = handle
            cachedAccent = accentHex
            cachedLogoPath = logoPath
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

    private func renderTexture(name: String, title: String, handle: String, style: String,
                               accentHex: String, logoPath: String, width: Int, height: Int) -> MTLTexture? {
        guard !name.isEmpty else { return nil }
        let accent = Self.resolveAccent(style: style, hex: accentHex)

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
            drawNewsroomLowerThird(ctx: ctx, name: name, title: title, accent: accent, width: drawW, height: drawH, barHeight: barHeight, barY: barY)
        } else {
            drawLateNightLowerThird(ctx: ctx, name: name, title: title, accent: accent, width: drawW, height: drawH, barHeight: barHeight, barY: barY)
        }

        // Shared extras: optional logo + social handle at the right of the lower third.
        drawHandleAndLogo(ctx: ctx, handle: handle, logoPath: logoPath, accent: accent,
                          width: drawW, height: drawH, barHeight: barHeight, barY: barY)

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

    private func drawLateNightLowerThird(ctx: CGContext, name: String, title: String, accent: NSColor, width: CGFloat, height: CGFloat, barHeight: CGFloat, barY: CGFloat) {
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
            accent.withAlphaComponent(0.92).cgColor,
            Self.shade(accent, -0.18).withAlphaComponent(0.92).cgColor,
        ]
        let goldGrad = CGGradient(colorsSpace: colorSpace, colors: goldColors as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(goldGrad, start: CGPoint(x: barX, y: nameBarY), end: CGPoint(x: barX, y: nameBarY + nameBarHeight), options: [])
        ctx.restoreGState()

        // Title bar: dark navy
        let titleRect = CGRect(x: barX, y: titleBarY, width: barWidth, height: titleBarHeight)
        ctx.setFillColor(CGColor(red: 0.08, green: 0.10, blue: 0.25, alpha: 0.90))
        ctx.fill(titleRect)

        // Thin gold accent line between bars
        ctx.setStrokeColor(Self.shade(accent, 0.28).cgColor)
        ctx.setLineWidth(1.5)
        ctx.move(to: CGPoint(x: barX, y: titleBarY))
        ctx.addLine(to: CGPoint(x: barX + barWidth, y: titleBarY))
        ctx.strokePath()

        // Left accent stripe
        let stripeWidth: CGFloat = 4
        ctx.setFillColor(Self.shade(accent, 0.28).cgColor)
        ctx.fill(CGRect(x: barX, y: nameBarY, width: stripeWidth, height: barHeight))

        // Name + title text, auto-shrunk so a long name never runs off the bar / frame.
        let nameX = barX + stripeWidth + 10
        let availW = barWidth - stripeWidth - 20
        let nameNSCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.current = nameNSCtx

        let nameStr = Self.fittedAttr(name, fontName: "Helvetica-Bold", baseSize: nameBarHeight * 0.55,
                                      color: .white, maxWidth: availW)
        let nameTextY = nameBarY + (nameBarHeight - nameStr.size().height) / 2
        nameStr.draw(at: NSPoint(x: nameX, y: nameTextY))

        if !title.isEmpty {
            let titleStr = Self.fittedAttr(title, fontName: "Helvetica", baseSize: titleBarHeight * 0.55,
                                           color: Self.shade(accent, 0.55),
                                           maxWidth: availW)
            let titleTextY = titleBarY + (titleBarHeight - titleStr.size().height) / 2
            titleStr.draw(at: NSPoint(x: nameX, y: titleTextY))
        }

        NSGraphicsContext.current = nil
    }

    // MARK: - Newsroom 1987 Style (broadcast news, red/blue/white)

    private func drawNewsroomLowerThird(ctx: CGContext, name: String, title: String, accent: NSColor, width: CGFloat, height: CGFloat, barHeight: CGFloat, barY: CGFloat) {
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
            accent.withAlphaComponent(0.93).cgColor,
            Self.shade(accent, -0.22).withAlphaComponent(0.93).cgColor,
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

        // Name + title text, auto-shrunk so it never runs off the bar / frame.
        let nameX = barX + 12
        let availW = barWidth - 24
        let nameNSCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.current = nameNSCtx

        let nameStr = Self.fittedAttr(name.uppercased(), fontName: "Helvetica-Bold",
                                      baseSize: nameBarHeight * 0.58, color: .white, maxWidth: availW)
        let nameTextY = nameBarY + (nameBarHeight - nameStr.size().height) / 2
        nameStr.draw(at: NSPoint(x: nameX, y: nameTextY))

        if !title.isEmpty {
            let titleStr = Self.fittedAttr(title, fontName: "Helvetica", baseSize: titleBarHeight * 0.52,
                                           color: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95),
                                           maxWidth: availW)
            let titleTextY = titleBarY + (titleBarHeight - titleStr.size().height) / 2
            titleStr.draw(at: NSPoint(x: nameX, y: titleTextY))
        }

        NSGraphicsContext.current = nil
    }

    /// Build an attributed string whose font is shrunk so it fits within `maxWidth` (no overflow).
    private static func fittedAttr(_ s: String, fontName: String, baseSize: CGFloat,
                                   color: NSColor, maxWidth: CGFloat) -> NSAttributedString {
        func make(_ size: CGFloat) -> NSAttributedString {
            let f = CTFontCreateWithName(fontName as CFString, size, nil)
            return NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color])
        }
        let attr = make(baseSize)
        let w = attr.size().width
        guard w > maxWidth, w > 0 else { return attr }
        return make(max(7, floor(baseSize * maxWidth / w)))
    }

    /// Optional logo + social handle, right-aligned in the lower-third band. Shared by both styles.
    private func drawHandleAndLogo(ctx: CGContext, handle: String, logoPath: String, accent: NSColor,
                                   width: CGFloat, height: CGFloat, barHeight: CGFloat, barY: CGFloat) {
        guard !handle.isEmpty || !logoPath.isEmpty else { return }
        let nameBarY = height - barY - barHeight
        var rightX = width * 0.96
        let nsctx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.current = nsctx
        defer { NSGraphicsContext.current = nil }

        if !logoPath.isEmpty, let img = NSImage(contentsOfFile: logoPath), img.size.width > 0, img.size.height > 0 {
            let side = barHeight * 0.92
            let scale = min(side / img.size.width, side / img.size.height)
            let w = img.size.width * scale, h = img.size.height * scale
            let x = rightX - w, y = nameBarY + (barHeight - h) / 2
            img.draw(in: NSRect(x: x, y: y, width: w, height: h))
            rightX = x - 10
        }

        if !handle.isEmpty {
            let para = NSMutableParagraphStyle(); para.alignment = .right; para.lineBreakMode = .byTruncatingTail
            let f = NSFont.systemFont(ofSize: max(9, barHeight * 0.22), weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: f, .foregroundColor: NSColor.white.withAlphaComponent(0.92), .paragraphStyle: para
            ]
            let textH = (handle as NSString).size(withAttributes: attrs).height
            let rect = NSRect(x: width * 0.5, y: nameBarY + (barHeight - textH) / 2, width: rightX - width * 0.5, height: textH)
            (handle as NSString).draw(in: rect, withAttributes: attrs)
        }
    }

    /// Resolve the accent colour: the user's hex, or the style's default (gold / red).
    private static func resolveAccent(style: String, hex: String) -> NSColor {
        if let c = hexColor(hex) { return c }
        return style == "newsroom"
            ? NSColor(red: 0.80, green: 0.10, blue: 0.10, alpha: 1)
            : NSColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 1)
    }

    private static func hexColor(_ hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return NSColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                       blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    /// Blend `color` toward white (amount > 0) or black (amount < 0) by |amount|.
    private static func shade(_ color: NSColor, _ amount: CGFloat) -> NSColor {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        let t = min(max(abs(amount), 0), 1)
        let target: CGFloat = amount >= 0 ? 1 : 0
        return NSColor(red: c.redComponent + (target - c.redComponent) * t,
                       green: c.greenComponent + (target - c.greenComponent) * t,
                       blue: c.blueComponent + (target - c.blueComponent) * t,
                       alpha: c.alphaComponent)
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
