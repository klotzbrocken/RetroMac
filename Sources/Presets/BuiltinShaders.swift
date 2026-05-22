import Foundation

enum BuiltinShaders {
    static func source(for name: String) throws -> String {
        guard let src = shaders[name] else {
            throw ShaderError.notFound(name)
        }
        return header + src
    }

    enum ShaderError: Error {
        case notFound(String)
    }

    private static let header = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float2 position [[attribute(0)]];
        float2 texCoord [[attribute(1)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    struct Uniforms {
        float4x4 mvp;
        float4 outputSize;
        float4 sourceSize;
        float4 originalSize;
        float4 finalViewportSize;
        uint frameCount;
        int frameDirection;
        float intensity;
        float vignetteIntensity;
    };

    float3 applyVignette(float3 color, float2 uv, float vignetteIntensity) {
        if (vignetteIntensity <= 0.001) return color;
        float2 v = uv * (1.0 - uv);
        float vig = v.x * v.y * 15.0;
        float amount = pow(vig, vignetteIntensity * 0.5);
        return color * amount;
    }

    float sampleSourceAlpha(texture2d<float> source, sampler s, float2 uv) {
        return source.sample(s, uv).a;
    }

    struct VertexData {
        packed_float2 position;
        packed_float2 texCoord;
    };

    vertex VertexOut vertex_main(
        uint vid [[vertex_id]],
        const device VertexData* vertices [[buffer(0)]],
        constant Uniforms& uniforms [[buffer(1)]]
    ) {
        VertexOut out;
        out.position = float4(vertices[vid].position, 0.0, 1.0);
        out.texCoord = vertices[vid].texCoord;
        return out;
    }

    """

    private static let shaders: [String: String] = [
        "zfast-crt": zfastCRTShader,
        "crt-lottes": crtLottesShader,
        "crt-geom": crtGeomShader,
        "vhs": vhsShader,
        "s-vhs": sVhsShader,
        "ntsc": ntscShader,
        "pal": palShader,
        "lcd-grid": lcdGridShader,
        "gameboy": gameboyShader,
        "amber-monitor": amberMonitorShader,
        "green-phosphor": greenPhosphorShader,
        "crt-aperture": crtApertureShader,
        "sepia": sepiaShader,
        "crt-hyllian-glow": crtHyllianGlowShader,
        "ntsc-320px": ntsc320pxShader,
        "newpixie-crt": newpixieCrtShader,
        "pvm-2730qm": pvm2730Shader,
        "pvm-20l4": pvm20l4Shader,
        "bo-mx8000": boMx8000Shader,
        "crt-gdv-mini-ultra": crtGdvMiniUltraShader,
        "curvature-x": curvatureXShader,
        "newpixie": newpixieShader,
        "mini-ultra-trinitron": miniUltraTrinitronShader,
        "bw-film": bwFilmShader,
        "bw-noir": bwNoirShader,
        "mac-classic": macClassicShader,
        "apple-ii": appleIIShader,
        "aqua": aquaShader,
        "crt-royale-lite": crtRoyaleLiteShader,
        "trinitron-tv": trinitronTVShader,
        "vcr-tracking": vcrTrackingShader,
        "cinema-film": cinemaFilmShader,
    ]

    // MARK: - zfast CRT — scanlines + chromatic aberration, NO barrel distortion

    private static let zfastCRTShader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;

        float3 original = source.sample(s, uv).rgb;

        // Scanline effect
        float scanlineWeight = 0.25 * intensity;
        float scanline = sin(uv.y * texSize.y * M_PI_F) * 0.5 + 0.5;
        scanline = mix(1.0, scanline, scanlineWeight);

        // Chromatic aberration
        float aberration = 0.0008 * intensity;
        float r = source.sample(s, uv + float2(aberration, 0)).r;
        float g = source.sample(s, uv).g;
        float b = source.sample(s, uv - float2(aberration, 0)).b;
        float3 color = float3(r, g, b);

        color *= scanline;

        // Subtle warm tint
        color *= float3(1.02, 1.0, 0.98);

        // Mix with original based on intensity
        color = mix(original, color, intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);

        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - CRT Lottes — scanlines + shadow mask, subtle curvature

    private static let crtLottesShader = """
    float3 toLinear_l(float3 c) { return pow(c, float3(2.2)); }
    float3 toSRGB_l(float3 c) { return pow(c, float3(1.0 / 2.2)); }

    float3 fetch_l(texture2d<float> tex, sampler s, float2 uv, float2 texSize, float2 off) {
        float2 pos = (floor(uv * texSize + off) + 0.5) / texSize;
        return toLinear_l(tex.sample(s, pos).rgb);
    }

    float scanGauss_l(float dist) {
        return exp2(-6.0 * dist * dist);
    }

    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;

        float3 original = source.sample(s, uv).rgb;

        float2 pos = uv * texSize;
        float2 fp = fract(pos);

        // 3-tap horizontal filter
        float3 c0 = fetch_l(source, s, uv, texSize, float2(-1, 0));
        float3 c1 = fetch_l(source, s, uv, texSize, float2(0, 0));
        float3 c2 = fetch_l(source, s, uv, texSize, float2(1, 0));

        float w0 = scanGauss_l(fp.x + 1.0);
        float w1 = scanGauss_l(fp.x);
        float w2 = scanGauss_l(fp.x - 1.0);
        float wTotal = w0 + w1 + w2;
        float3 color = (c0 * w0 + c1 * w1 + c2 * w2) / wTotal;

        // Scanlines
        float scanline = scanGauss_l(fp.y - 0.5);
        color *= scanline * 1.2 + 0.2;

        // Shadow mask (RGB triad)
        float maskStr = 0.25 * intensity;
        float maskR = 1.0 + maskStr * sin(pos.x * M_PI_F * 2.0 / 3.0);
        float maskG = 1.0 + maskStr * sin(pos.x * M_PI_F * 2.0 / 3.0 + 2.094);
        float maskB = 1.0 + maskStr * sin(pos.x * M_PI_F * 2.0 / 3.0 + 4.189);
        color *= float3(maskR, maskG, maskB);

        color = toSRGB_l(color);

        // Mix with original
        color = mix(original, color, intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);

        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - CRT Geom — scanlines + phosphor mask, NO barrel distortion

    private static let crtGeomShader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;

        float3 original = source.sample(s, uv).rgb;
        float3 color = original;

        // Scanlines
        float scanStr = 0.15 * intensity;
        float scanline = 1.0 - scanStr + scanStr * sin(uv.y * texSize.y * M_PI_F * 2.0);
        color *= scanline;

        // Phosphor mask
        float maskStr = 0.12 * intensity;
        float mask = 1.0 - maskStr + maskStr * sin(uv.x * texSize.x * M_PI_F * 2.0);
        color *= mask;

        // Warm phosphor tint
        color *= mix(float3(1.0), float3(1.04, 1.0, 0.96), intensity);

        // Slight bloom
        float3 bloom = source.sample(s, uv, level(2.0)).rgb;
        color += bloom * 0.03 * intensity;

        color = mix(original, color, intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);

        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - VHS

    private static let vhsShader = """
    float rand_v(float2 co) {
        return fract(sin(dot(co, float2(12.9898, 78.233))) * 43758.5453);
    }

    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float time = float(uniforms.frameCount) / 60.0;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;

        float3 original = source.sample(s, uv).rgb;

        // Tracking noise
        float jitter = rand_v(float2(floor(uv.y * texSize.y), time)) * 0.003 - 0.0015;
        uv.x += jitter * intensity;

        // Occasional glitch bands
        float band = step(0.99, rand_v(float2(floor(time * 3.0), floor(uv.y * 20.0))));
        uv.x += band * (rand_v(float2(time, uv.y)) * 0.02 - 0.01) * intensity;

        // Head-switching noise at bottom
        float headSwitch = smoothstep(0.97, 1.0, uv.y);
        uv.x += headSwitch * sin(time * 30.0 + uv.y * 100.0) * 0.02 * intensity;

        // Chromatic aberration
        float spread = 0.003 * intensity;
        float r = source.sample(s, uv + float2(spread, 0)).r;
        float g = source.sample(s, uv).g;
        float b = source.sample(s, uv - float2(spread, 0)).b;
        float3 color = float3(r, g, b);

        // Noise
        float noise = (rand_v(float2(uv.x * time, uv.y * time)) - 0.5) * 0.06 * intensity;
        color += noise;

        // Scanlines
        float scanline = 1.0 - 0.08 * intensity + 0.08 * intensity * sin(uv.y * texSize.y * M_PI_F * 0.5);
        color *= scanline;

        // Desaturate slightly
        float luma = dot(color, float3(0.299, 0.587, 0.114));
        color = mix(color, float3(luma), 0.15 * intensity);

        // Softness
        float3 blurred = source.sample(s, uv + float2(0.001, 0)).rgb * 0.25
                       + source.sample(s, uv - float2(0.001, 0)).rgb * 0.25
                       + color * 0.5;
        color = mix(color, blurred, 0.3 * intensity);

        color *= 1.0 - headSwitch * 0.4 * intensity;

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);

        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - LCD Grid

    private static let lcdGridShader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 outputSize = uniforms.outputSize.xy;
        float intensity = uniforms.intensity;
        float3 original = source.sample(s, uv).rgb;
        float3 color = original;

        float2 pixelPos = uv * outputSize;
        float subpixel = fmod(pixelPos.x, 3.0);

        float3 mask;
        if (subpixel < 1.0) {
            mask = float3(1.0, 0.3, 0.3);
        } else if (subpixel < 2.0) {
            mask = float3(0.3, 1.0, 0.3);
        } else {
            mask = float3(0.3, 0.3, 1.0);
        }

        float gap = smoothstep(0.0, 0.15, fract(pixelPos.x / 3.0))
                  * smoothstep(1.0, 0.85, fract(pixelPos.x / 3.0));
        float vgap = smoothstep(0.0, 0.1, fract(pixelPos.y))
                   * smoothstep(1.0, 0.9, fract(pixelPos.y));

        float3 lcd = color * mask * gap * vgap * 1.6;
        lcd += float3(0.02, 0.02, 0.025);

        color = mix(original, clamp(lcd, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);

        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - Game Boy

    private static let gameboyShader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 outputSize = uniforms.outputSize.xy;
        float intensity = uniforms.intensity;

        float3 original = source.sample(s, uv).rgb;
        float luma = dot(original, float3(0.299, 0.587, 0.114));

        // Authentic DMG palette (olive/yellow-green LCD, not pure green)
        float3 c0 = float3(0.06, 0.09, 0.06);   // darkest
        float3 c1 = float3(0.19, 0.28, 0.14);   // dark
        float3 c2 = float3(0.52, 0.57, 0.20);   // light
        float3 c3 = float3(0.61, 0.65, 0.32);   // lightest

        // Quantize to 4 shades with hard steps
        float3 result;
        float q = floor(luma * 3.999);
        if (q < 1.0) {
            result = c0;
        } else if (q < 2.0) {
            result = c1;
        } else if (q < 3.0) {
            result = c2;
        } else {
            result = c3;
        }

        // LCD pixel grid
        float2 pixelPos = uv * outputSize / 4.0;
        float gx = smoothstep(0.0, 0.12, fract(pixelPos.x))
                  * smoothstep(1.0, 0.88, fract(pixelPos.x));
        float gy = smoothstep(0.0, 0.12, fract(pixelPos.y))
                  * smoothstep(1.0, 0.88, fract(pixelPos.y));
        float grid = gx * gy;
        result *= 0.6 + 0.4 * grid;

        // LCD response ghosting (slight blur)
        float3 blurred = source.sample(s, uv + float2(0.0015, 0)).rgb * 0.15
                       + source.sample(s, uv - float2(0.0015, 0)).rgb * 0.15
                       + original * 0.7;
        float blurLuma = dot(blurred, float3(0.299, 0.587, 0.114));
        result = mix(result, result * (0.85 + 0.15 * blurLuma), 0.3);

        // Subtle backlight unevenness
        float backlight = 1.0 - length(uv - 0.5) * 0.15;
        result *= backlight;

        result = mix(original, result, intensity);
        result = applyVignette(result, uv, uniforms.vignetteIntensity);

        return float4(result, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - B&W Film — classic film grain look

    private static let bwFilmShader = """
    float rand_bw(float2 co) {
        return fract(sin(dot(co, float2(12.9898, 78.233))) * 43758.5453);
    }

    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float intensity = uniforms.intensity;
        float time = float(uniforms.frameCount) / 60.0;

        float3 original = source.sample(s, uv).rgb;

        // Luminance with slight warm bias
        float luma = dot(original, float3(0.299, 0.587, 0.114));

        // Slight contrast curve (S-curve)
        float contrast = luma * luma * (3.0 - 2.0 * luma);
        luma = mix(luma, contrast, 0.3);

        // Film grain
        float grain = (rand_bw(uv * 500.0 + time) - 0.5) * 0.08 * intensity;
        luma += grain;

        float3 bw = float3(luma);

        bw = mix(original, bw, intensity);
        bw = applyVignette(bw, uv, uniforms.vignetteIntensity);

        return float4(clamp(bw, 0.0, 1.0), sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - B&W Noir — high contrast, deep blacks, slight vignette

    private static let bwNoirShader = """
    float rand_noir(float2 co) {
        return fract(sin(dot(co, float2(12.9898, 78.233))) * 43758.5453);
    }

    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float intensity = uniforms.intensity;
        float time = float(uniforms.frameCount) / 60.0;

        float3 original = source.sample(s, uv).rgb;

        float luma = dot(original, float3(0.299, 0.587, 0.114));

        // High contrast S-curve
        float t = clamp(luma, 0.0, 1.0);
        float noir = t * t * t * (t * (t * 6.0 - 15.0) + 10.0);

        // Crush blacks slightly
        noir = max(noir - 0.05, 0.0) * (1.0 / 0.95);

        // Subtle warm tone in highlights, cool in shadows
        float3 color;
        color.r = noir * 1.02;
        color.g = noir;
        color.b = noir * 0.98;

        // Very subtle vignette (only edges, not oval)
        float2 d = abs(uv - 0.5) * 2.0;
        float edge = max(d.x, d.y);
        float vignette = 1.0 - smoothstep(0.8, 1.0, edge) * 0.2;
        color *= vignette;

        // Film grain
        float grain = (rand_noir(uv * 400.0 + time) - 0.5) * 0.05 * intensity;
        color += grain;

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);

        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - S-VHS — heavily degraded tape look

    private static let sVhsShader = """
    float rand_sv(float2 co) {
        return fract(sin(dot(co, float2(12.9898, 78.233))) * 43758.5453);
    }

    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float time = float(uniforms.frameCount) / 60.0;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;

        float3 original = source.sample(s, uv).rgb;

        // Heavy tracking jitter
        float jitter = rand_sv(float2(floor(uv.y * texSize.y * 0.5), time)) * 0.006 - 0.003;
        uv.x += jitter * intensity;

        // Frequent glitch bands
        float band = step(0.95, rand_sv(float2(floor(time * 5.0), floor(uv.y * 15.0))));
        uv.x += band * (rand_sv(float2(time, uv.y)) * 0.04 - 0.02) * intensity;

        // Tape dropout — horizontal white streaks
        float dropout = step(0.997, rand_sv(float2(floor(uv.y * texSize.y), floor(time * 10.0))));
        float dropoutStrength = dropout * rand_sv(float2(uv.x, time)) * intensity;

        // Heavy head-switching noise at bottom
        float headSwitch = smoothstep(0.94, 1.0, uv.y);
        uv.x += headSwitch * sin(time * 40.0 + uv.y * 120.0) * 0.04 * intensity;

        // Strong color bleed — wide chroma spread
        float spread = 0.006 * intensity;
        float r = source.sample(s, uv + float2(spread, 0)).r;
        float g = source.sample(s, uv).g;
        float b = source.sample(s, uv - float2(spread * 0.8, 0)).b;
        float3 color = float3(r, g, b);

        // Apply dropout
        color = mix(color, float3(0.9), dropoutStrength);

        // Heavy noise
        float noise = (rand_sv(float2(uv.x * time * 2.0, uv.y * time * 2.0)) - 0.5) * 0.12 * intensity;
        color += noise;

        // Scanlines
        float scanline = 1.0 - 0.12 * intensity + 0.12 * intensity * sin(uv.y * texSize.y * M_PI_F * 0.5);
        color *= scanline;

        // Strong desaturation
        float luma = dot(color, float3(0.299, 0.587, 0.114));
        color = mix(color, float3(luma), 0.3 * intensity);

        // Horizontal blur (soft image)
        float3 blurred = source.sample(s, uv + float2(0.002, 0)).rgb * 0.2
                       + source.sample(s, uv - float2(0.002, 0)).rgb * 0.2
                       + source.sample(s, uv + float2(0.001, 0)).rgb * 0.15
                       + source.sample(s, uv - float2(0.001, 0)).rgb * 0.15
                       + color * 0.3;
        color = mix(color, blurred, 0.5 * intensity);

        color *= 1.0 - headSwitch * 0.6 * intensity;

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, in.texCoord, uniforms.vignetteIntensity);

        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - NTSC — composite video artifacts

    private static let ntscShader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;
        float time = float(uniforms.frameCount) / 60.0;

        float3 original = source.sample(s, uv).rgb;

        // NTSC composite: encode RGB to YIQ-like signal, then decode with artifacts
        float3 color = original;

        // Dot crawl pattern (3.58 MHz subcarrier)
        float dotCrawl = sin(uv.x * texSize.x * M_PI_F * 2.0 / 3.0 + time * M_PI_F * 2.0) * 0.03 * intensity;
        color.r += dotCrawl;
        color.b -= dotCrawl;

        // Color fringing from chroma bandwidth limit
        float chromaSpread = 0.0025 * intensity;
        float cr = source.sample(s, uv + float2(chromaSpread, 0)).r;
        float cb = source.sample(s, uv - float2(chromaSpread, 0)).b;
        color.r = mix(color.r, cr, 0.5 * intensity);
        color.b = mix(color.b, cb, 0.5 * intensity);

        // Horizontal blur (limited luma bandwidth)
        float3 tap1 = source.sample(s, uv + float2(1.0 / texSize.x, 0)).rgb;
        float3 tap2 = source.sample(s, uv - float2(1.0 / texSize.x, 0)).rgb;
        color = mix(color, (color * 0.6 + tap1 * 0.2 + tap2 * 0.2), 0.4 * intensity);

        // Rainbow artifacts on sharp edges
        float luma = dot(original, float3(0.299, 0.587, 0.114));
        float lumaR = dot(source.sample(s, uv + float2(1.5 / texSize.x, 0)).rgb, float3(0.299, 0.587, 0.114));
        float edgeStr = abs(luma - lumaR);
        float rainbow = sin(uv.x * texSize.x * M_PI_F + time * 3.0) * edgeStr * 0.15 * intensity;
        color.r += rainbow;
        color.g -= rainbow * 0.5;
        color.b += rainbow;

        // Slight vertical softness
        float3 vTap = source.sample(s, uv + float2(0, 0.5 / texSize.y)).rgb;
        color = mix(color, (color * 0.8 + vTap * 0.2), 0.2 * intensity);

        // NTSC warm tint
        color *= float3(1.03, 1.0, 0.97);

        // Scanlines (NTSC = 525 lines)
        float scanline = 1.0 - 0.08 * intensity + 0.08 * intensity * sin(uv.y * 525.0 * M_PI_F);
        color *= scanline;

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);

        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - PAL — cross-color and Hanover bars

    private static let palShader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;
        float time = float(uniforms.frameCount) / 60.0;

        float3 original = source.sample(s, uv).rgb;
        float3 color = original;

        // PAL subcarrier (4.43 MHz equivalent pattern)
        float subcarrier = sin(uv.x * texSize.x * M_PI_F * 2.0 / 4.0 + uv.y * texSize.y * M_PI_F);

        // Cross-color artifacts
        float luma = dot(original, float3(0.299, 0.587, 0.114));
        float lumaNext = dot(source.sample(s, uv + float2(1.0 / texSize.x, 0)).rgb, float3(0.299, 0.587, 0.114));
        float edge = abs(luma - lumaNext);
        float crossColor = subcarrier * edge * 0.2 * intensity;
        color.r += crossColor;
        color.b -= crossColor;

        // Hanover bars — alternating line color phase
        float line = floor(uv.y * texSize.y);
        float hanover = sin(line * M_PI_F) * 0.02 * intensity;
        color.r += hanover;
        color.g -= hanover * 0.5;

        // Chroma blur (PAL has wider chroma bandwidth than NTSC but still limited)
        float chromaSpread = 0.002 * intensity;
        float cr = source.sample(s, uv + float2(chromaSpread, 0)).r;
        float cb = source.sample(s, uv - float2(chromaSpread, 0)).b;
        color.r = mix(color.r, cr, 0.4 * intensity);
        color.b = mix(color.b, cb, 0.4 * intensity);

        // Horizontal blur
        float3 tap1 = source.sample(s, uv + float2(1.0 / texSize.x, 0)).rgb;
        float3 tap2 = source.sample(s, uv - float2(1.0 / texSize.x, 0)).rgb;
        color = mix(color, (color * 0.65 + tap1 * 0.175 + tap2 * 0.175), 0.35 * intensity);

        // PAL cool tint (European phosphors)
        color *= float3(0.98, 1.0, 1.03);

        // Scanlines (PAL = 625 lines)
        float scanline = 1.0 - 0.07 * intensity + 0.07 * intensity * sin(uv.y * 625.0 * M_PI_F);
        color *= scanline;

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);

        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - Amber Monitor — warm amber phosphor terminal

    private static let amberMonitorShader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;

        float3 original = source.sample(s, uv).rgb;
        float luma = dot(original, float3(0.299, 0.587, 0.114));

        // Amber phosphor color
        float3 amber = float3(1.0, 0.69, 0.0) * luma;

        // Phosphor glow — brighter areas bloom slightly
        float glow = smoothstep(0.4, 1.0, luma) * 0.15;
        amber += float3(1.0, 0.8, 0.3) * glow;

        // Scanlines
        float scanline = 1.0 - 0.2 * intensity + 0.2 * intensity * sin(uv.y * texSize.y * M_PI_F);
        amber *= scanline;

        // Slight flicker
        float time = float(uniforms.frameCount) / 60.0;
        amber *= 1.0 - 0.015 * intensity * sin(time * 8.0);

        // CRT phosphor persistence — slight vertical blur
        float3 above = source.sample(s, uv + float2(0, 0.5 / texSize.y)).rgb;
        float lumaAbove = dot(above, float3(0.299, 0.587, 0.114));
        amber += float3(1.0, 0.69, 0.0) * lumaAbove * 0.08 * intensity;

        amber = mix(original, clamp(amber, 0.0, 1.0), intensity);
        amber = applyVignette(amber, uv, uniforms.vignetteIntensity);

        return float4(amber, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - Green Phosphor — classic green terminal (P1 phosphor)

    private static let greenPhosphorShader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;

        float3 original = source.sample(s, uv).rgb;
        float luma = dot(original, float3(0.299, 0.587, 0.114));

        // P1 green phosphor
        float3 green = float3(0.2, 1.0, 0.2) * luma;

        // Phosphor afterglow
        float glow = smoothstep(0.3, 1.0, luma) * 0.12;
        green += float3(0.1, 0.6, 0.1) * glow;

        // Scanlines
        float scanline = 1.0 - 0.25 * intensity + 0.25 * intensity * sin(uv.y * texSize.y * M_PI_F);
        green *= scanline;

        // Subtle flicker
        float time = float(uniforms.frameCount) / 60.0;
        green *= 1.0 - 0.01 * intensity * sin(time * 10.0);

        // Phosphor persistence
        float3 above = source.sample(s, uv + float2(0, 0.5 / texSize.y)).rgb;
        float lumaAbove = dot(above, float3(0.299, 0.587, 0.114));
        green += float3(0.15, 0.8, 0.15) * lumaAbove * 0.06 * intensity;

        green = mix(original, clamp(green, 0.0, 1.0), intensity);
        green = applyVignette(green, uv, uniforms.vignetteIntensity);

        return float4(green, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - CRT Aperture — Sony Trinitron aperture grille + bloom

    private static let crtApertureShader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float2 outputSize = uniforms.outputSize.xy;
        float intensity = uniforms.intensity;

        float3 original = source.sample(s, uv).rgb;
        float3 color = original;

        // Vertical aperture grille (Trinitron-style RGB stripes)
        float col = uv.x * outputSize.x;
        float stripe = fmod(col, 3.0);
        float3 mask;
        if (stripe < 1.0) {
            mask = float3(1.0, 0.25, 0.25);
        } else if (stripe < 2.0) {
            mask = float3(0.25, 1.0, 0.25);
        } else {
            mask = float3(0.25, 0.25, 1.0);
        }
        float maskStr = 0.3 * intensity;
        color *= mix(float3(1.0), mask, maskStr);

        // Horizontal scanlines (lighter than shadow mask CRTs)
        float scanStr = 0.12 * intensity;
        float scanline = 1.0 - scanStr + scanStr * sin(uv.y * texSize.y * M_PI_F * 2.0);
        color *= scanline;

        // Bloom — bright areas glow
        float3 blur = source.sample(s, uv + float2(1.5 / texSize.x, 0)).rgb * 0.15
                    + source.sample(s, uv - float2(1.5 / texSize.x, 0)).rgb * 0.15
                    + source.sample(s, uv + float2(0, 1.5 / texSize.y)).rgb * 0.1
                    + source.sample(s, uv - float2(0, 1.5 / texSize.y)).rgb * 0.1
                    + original * 0.5;
        float bloomAmount = smoothstep(0.5, 1.0, dot(blur, float3(0.333))) * 0.2 * intensity;
        color += blur * bloomAmount;

        // Trinitron warm tint
        color *= float3(1.02, 1.0, 0.97);

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);

        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - Sepia — warm vintage photograph look

    private static let sepiaShader = """
    float rand_sep(float2 co) {
        return fract(sin(dot(co, float2(12.9898, 78.233))) * 43758.5453);
    }

    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float intensity = uniforms.intensity;
        float time = float(uniforms.frameCount) / 60.0;

        float3 original = source.sample(s, uv).rgb;
        float luma = dot(original, float3(0.299, 0.587, 0.114));

        // Sepia tone matrix
        float3 sepia;
        sepia.r = luma * 1.1;
        sepia.g = luma * 0.85;
        sepia.b = luma * 0.6;

        // Slight contrast boost
        sepia = (sepia - 0.5) * 1.1 + 0.5;

        // Film grain
        float grain = (rand_sep(uv * 300.0 + time) - 0.5) * 0.06 * intensity;
        sepia += grain;

        // Slight color variation (aged film inconsistency)
        float variation = sin(uv.y * 20.0 + time * 0.5) * 0.02 * intensity;
        sepia.r += variation;
        sepia.b -= variation * 0.5;

        // Corner fade (aged photo edges)
        float2 d = (uv - 0.5) * 2.0;
        float cornerFade = 1.0 - smoothstep(0.7, 1.4, length(d)) * 0.3 * intensity;
        sepia *= cornerFade;

        sepia = mix(original, clamp(sepia, 0.0, 1.0), intensity);
        sepia = applyVignette(sepia, uv, uniforms.vignetteIntensity);

        return float4(sepia, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - CRT Hyllian Glow — phosphor glow with strong scanlines

    private static let crtHyllianGlowShader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;
        float3 original = source.sample(s, uv).rgb;

        // Strong scanlines with gaussian profile
        float2 pos = uv * texSize;
        float fp = fract(pos.y);
        float scanWeight = exp2(-8.0 * (fp - 0.5) * (fp - 0.5)) * 0.4 * intensity;
        float scanline = 1.0 - scanWeight;

        float3 color = original * scanline;

        // Phosphor glow (wide blur)
        float3 glow = float3(0);
        for (int dx = -2; dx <= 2; dx++) {
            for (int dy = -2; dy <= 2; dy++) {
                float2 off = float2(float(dx), float(dy)) / texSize;
                glow += source.sample(s, uv + off * 2.0).rgb;
            }
        }
        glow /= 25.0;
        float glowAmount = 0.25 * intensity;
        color += glow * glowAmount;

        // Slight color boost
        float luma = dot(color, float3(0.299, 0.587, 0.114));
        color = mix(float3(luma), color, 1.15);

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);
        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - NTSC 320px Composite Scanline

    private static let ntsc320pxShader = """
    float rand_ntsc320(float2 co) {
        return fract(sin(dot(co, float2(12.9898, 78.233))) * 43758.5453);
    }

    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;
        float time = float(uniforms.frameCount) / 60.0;
        float3 original = source.sample(s, uv).rgb;

        // Simulate 320px horizontal resolution — quantize + blur
        float hRes = 320.0;
        float2 lowUV = float2(floor(uv.x * hRes + 0.5) / hRes, uv.y);
        float3 color = source.sample(s, lowUV).rgb * 0.5
                      + source.sample(s, lowUV + float2(0.5 / hRes, 0)).rgb * 0.25
                      + source.sample(s, lowUV - float2(0.5 / hRes, 0)).rgb * 0.25;

        // Composite chroma bleed
        float spread = 0.004 * intensity;
        float cr = source.sample(s, uv + float2(spread, 0)).r;
        float cb = source.sample(s, uv - float2(spread, 0)).b;
        color.r = mix(color.r, cr, 0.6 * intensity);
        color.b = mix(color.b, cb, 0.6 * intensity);

        // Dot crawl
        float dotCrawl = sin(uv.x * hRes * M_PI_F * 2.0 / 3.0 + time * M_PI_F * 2.0) * 0.04 * intensity;
        color.r += dotCrawl;
        color.b -= dotCrawl;

        // Strong scanlines (240p)
        float scanStr = 0.3 * intensity;
        float scanline = 1.0 - scanStr + scanStr * sin(uv.y * 240.0 * M_PI_F);
        color *= scanline;

        // Noise
        float noise = (rand_ntsc320(float2(uv.x * time, uv.y * time)) - 0.5) * 0.04 * intensity;
        color += noise;

        // Warm NTSC tint
        color *= float3(1.04, 1.0, 0.96);

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);
        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - NewPixie CRT — soft warm CRT with subtle curvature

    private static let newpixieCrtShader = """
    float2 curveUV_np(float2 uv, float amount) {
        uv = uv * 2.0 - 1.0;
        float2 offset = abs(uv.yx) / float2(6.0, 4.0) * amount;
        uv = uv + uv * offset * offset;
        uv = uv * 0.5 + 0.5;
        return uv;
    }

    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = curveUV_np(in.texCoord, 0.5 * uniforms.intensity);
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;

        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
            return float4(0, 0, 0, sampleSourceAlpha(source, s, in.texCoord));

        float3 original = source.sample(s, uv).rgb;

        // Soft horizontal blur (warm look)
        float3 color = source.sample(s, uv).rgb * 0.4
                      + source.sample(s, uv + float2(1.0 / texSize.x, 0)).rgb * 0.2
                      + source.sample(s, uv - float2(1.0 / texSize.x, 0)).rgb * 0.2
                      + source.sample(s, uv + float2(2.0 / texSize.x, 0)).rgb * 0.1
                      + source.sample(s, uv - float2(2.0 / texSize.x, 0)).rgb * 0.1;

        // Scanlines
        float scanStr = 0.18 * intensity;
        float scanline = 1.0 - scanStr + scanStr * sin(uv.y * texSize.y * M_PI_F);
        color *= scanline;

        // Slight bloom
        float3 bloom = source.sample(s, uv, level(2.0)).rgb;
        color += bloom * 0.08 * intensity;

        // Warm tint
        color *= float3(1.05, 1.0, 0.95);

        // Slight saturation boost
        float luma = dot(color, float3(0.299, 0.587, 0.114));
        color = mix(float3(luma), color, 1.1);

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);
        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - Sony PVM 2730QM — professional broadcast monitor, sharp aperture grille

    private static let pvm2730Shader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float2 outputSize = uniforms.outputSize.xy;
        float intensity = uniforms.intensity;
        float3 original = source.sample(s, uv).rgb;

        // Sharp image — minimal blur
        float3 color = original;

        // Fine aperture grille (Trinitron)
        float col = uv.x * outputSize.x;
        float stripe = fmod(col, 3.0);
        float3 mask;
        if (stripe < 1.0) {
            mask = float3(1.0, 0.18, 0.18);
        } else if (stripe < 2.0) {
            mask = float3(0.18, 1.0, 0.18);
        } else {
            mask = float3(0.18, 0.18, 1.0);
        }
        color *= mix(float3(1.0), mask, 0.35 * intensity);

        // Tight scanlines (high TVL)
        float scanStr = 0.15 * intensity;
        float scanPos = uv.y * texSize.y;
        float scanline = 1.0 - scanStr * (1.0 - smoothstep(0.35, 0.5, abs(fract(scanPos) - 0.5)));
        color *= scanline;

        // PVM color accuracy — slight saturation boost
        float luma = dot(color, float3(0.299, 0.587, 0.114));
        color = mix(float3(luma), color, 1.2);

        // Slight phosphor bloom on bright areas
        float brightness = dot(original, float3(0.333));
        float bloom = smoothstep(0.6, 1.0, brightness) * 0.08 * intensity;
        color += original * bloom;

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);
        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - Sony PVM 20L4 — 20" pro monitor, fine slot mask

    private static let pvm20l4Shader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float2 outputSize = uniforms.outputSize.xy;
        float intensity = uniforms.intensity;
        float3 original = source.sample(s, uv).rgb;
        float3 color = original;

        // Slot mask pattern (groups of 3 with vertical gaps)
        float2 pixelPos = uv * outputSize;
        float col = fmod(pixelPos.x, 3.0);
        float row = fmod(pixelPos.y, 2.0);
        float3 mask;
        if (col < 1.0) {
            mask = float3(1.0, 0.22, 0.22);
        } else if (col < 2.0) {
            mask = float3(0.22, 1.0, 0.22);
        } else {
            mask = float3(0.22, 0.22, 1.0);
        }
        // Vertical slot gap
        float slotGap = smoothstep(0.0, 0.3, row) * smoothstep(2.0, 1.7, row);
        mask = mix(float3(0.15), mask, slotGap);
        color *= mix(float3(1.0), mask, 0.3 * intensity);

        // Scanlines
        float scanStr = 0.2 * intensity;
        float fp = fract(uv.y * texSize.y);
        float scanline = 1.0 - scanStr * exp2(-4.0 * (fp - 0.5) * (fp - 0.5));
        color *= scanline;

        // Color temperature: slightly cool (20L4 has cooler phosphors)
        color *= float3(0.98, 1.0, 1.03);

        // Saturation boost
        float luma = dot(color, float3(0.299, 0.587, 0.114));
        color = mix(float3(luma), color, 1.15);

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);
        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - Bang & Olufsen MX8000 — high-end European consumer TV

    private static let boMx8000Shader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float2 outputSize = uniforms.outputSize.xy;
        float intensity = uniforms.intensity;
        float3 original = source.sample(s, uv).rgb;

        // B&O: clean, refined image with subtle processing
        float3 color = original;

        // Gentle horizontal smoothing (B&O's comb filter)
        float3 tap1 = source.sample(s, uv + float2(0.7 / texSize.x, 0)).rgb;
        float3 tap2 = source.sample(s, uv - float2(0.7 / texSize.x, 0)).rgb;
        color = color * 0.6 + tap1 * 0.2 + tap2 * 0.2;

        // Very subtle shadow mask (high quality tube)
        float col = fmod(uv.x * outputSize.x, 3.0);
        float3 mask;
        if (col < 1.0) {
            mask = float3(1.0, 0.85, 0.85);
        } else if (col < 2.0) {
            mask = float3(0.85, 1.0, 0.85);
        } else {
            mask = float3(0.85, 0.85, 1.0);
        }
        color *= mix(float3(1.0), mask, 0.12 * intensity);

        // Very light scanlines (100Hz set = less visible)
        float scanStr = 0.06 * intensity;
        float scanline = 1.0 - scanStr + scanStr * sin(uv.y * texSize.y * M_PI_F * 2.0);
        color *= scanline;

        // B&O warm European tint
        color *= float3(1.02, 1.005, 0.97);

        // Slight contrast enhancement (B&O picture processing)
        color = (color - 0.5) * (1.0 + 0.08 * intensity) + 0.5;

        // Gentle bloom
        float3 bloom = source.sample(s, uv, level(1.5)).rgb;
        color += bloom * 0.04 * intensity;

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);
        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - CRT GDV Mini Ultra — curvature + mask + glow

    private static let crtGdvMiniUltraShader = """
    float2 curveUV_gdv(float2 uv, float cx, float cy) {
        uv = uv * 2.0 - 1.0;
        uv *= float2(1.0 + (uv.y * uv.y) * cx, 1.0 + (uv.x * uv.x) * cy);
        return uv * 0.5 + 0.5;
    }

    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float intensity = uniforms.intensity;
        float2 uv = curveUV_gdv(in.texCoord, 0.03 * intensity, 0.04 * intensity);
        float2 texSize = uniforms.sourceSize.xy;
        float2 outputSize = uniforms.outputSize.xy;

        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
            return float4(0, 0, 0, sampleSourceAlpha(source, s, in.texCoord));

        float3 original = source.sample(s, uv).rgb;
        float3 color = original;

        // Aperture grille mask
        float col = fmod(uv.x * outputSize.x, 3.0);
        float3 mask;
        if (col < 1.0) {
            mask = float3(1.0, 0.2, 0.2);
        } else if (col < 2.0) {
            mask = float3(0.2, 1.0, 0.2);
        } else {
            mask = float3(0.2, 0.2, 1.0);
        }
        color *= mix(float3(1.0), mask, 0.3 * intensity);

        // Scanlines
        float scanStr = 0.22 * intensity;
        float fp = fract(uv.y * texSize.y);
        float scanline = 1.0 - scanStr * exp2(-6.0 * (fp - 0.5) * (fp - 0.5));
        color *= scanline;

        // Glow / bloom
        float3 glow = float3(0);
        for (int i = -2; i <= 2; i++) {
            float2 off = float2(float(i) * 1.5 / texSize.x, 0);
            glow += source.sample(s, uv + off).rgb;
        }
        glow /= 5.0;
        color += glow * 0.15 * intensity;

        // Corner shadow
        float2 d = abs(uv - 0.5) * 2.0;
        float corner = 1.0 - smoothstep(0.85, 1.05, length(d)) * 0.5;
        color *= corner;

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);
        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - CurvatureX 0.01 — very subtle barrel distortion only

    private static let curvatureXShader = """
    float2 curveUV_cx(float2 uv, float amount) {
        uv = uv * 2.0 - 1.0;
        uv *= 1.0 + float2(amount * uv.y * uv.y, amount * uv.x * uv.x);
        return uv * 0.5 + 0.5;
    }

    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float intensity = uniforms.intensity;
        float2 uv = curveUV_cx(in.texCoord, 0.01 * intensity);

        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
            return float4(0, 0, 0, sampleSourceAlpha(source, s, in.texCoord));

        float3 color = source.sample(s, uv).rgb;

        // Minimal scanlines
        float scanStr = 0.05 * intensity;
        float scanline = 1.0 - scanStr + scanStr * sin(uv.y * uniforms.sourceSize.y * M_PI_F);
        color *= scanline;

        color = applyVignette(color, uv, uniforms.vignetteIntensity);
        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - NewPixie — soft pixelation with warm color processing

    private static let newpixieShader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;
        float3 original = source.sample(s, uv).rgb;

        // Soft multi-tap horizontal blur
        float3 color = source.sample(s, uv).rgb * 0.3
                      + source.sample(s, uv + float2(1.0 / texSize.x, 0)).rgb * 0.175
                      + source.sample(s, uv - float2(1.0 / texSize.x, 0)).rgb * 0.175
                      + source.sample(s, uv + float2(2.0 / texSize.x, 0)).rgb * 0.1
                      + source.sample(s, uv - float2(2.0 / texSize.x, 0)).rgb * 0.1
                      + source.sample(s, uv + float2(0, 1.0 / texSize.y)).rgb * 0.075
                      + source.sample(s, uv - float2(0, 1.0 / texSize.y)).rgb * 0.075;

        // Warm color shift
        color *= float3(1.06, 1.01, 0.93);

        // Gentle contrast boost
        color = (color - 0.5) * 1.08 + 0.5;

        // Saturation boost
        float luma = dot(color, float3(0.299, 0.587, 0.114));
        color = mix(float3(luma), color, 1.15);

        // Subtle bloom
        float3 bloom = source.sample(s, uv, level(2.0)).rgb;
        color += bloom * 0.06 * intensity;

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);
        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - Mini Ultra Trinitron — ultra-fine aperture grille

    private static let miniUltraTrinitronShader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float2 outputSize = uniforms.outputSize.xy;
        float intensity = uniforms.intensity;
        float3 original = source.sample(s, uv).rgb;
        float3 color = original;

        // Ultra-fine Trinitron stripes (every pixel)
        float col = fmod(uv.x * outputSize.x, 3.0);
        float3 mask;
        if (col < 1.0) {
            mask = float3(1.3, 0.6, 0.6);
        } else if (col < 2.0) {
            mask = float3(0.6, 1.3, 0.6);
        } else {
            mask = float3(0.6, 0.6, 1.3);
        }
        // Smooth transitions between stripes
        float transition = smoothstep(0.0, 0.3, fract(col))
                         * smoothstep(1.0, 0.7, fract(col));
        color *= mix(float3(0.85), mask, transition * 0.4 * intensity);

        // Light scanlines (high TVL = less visible)
        float scanStr = 0.1 * intensity;
        float scanPos = uv.y * texSize.y;
        float scanline = 1.0 - scanStr * (1.0 - smoothstep(0.3, 0.5, abs(fract(scanPos) - 0.5)));
        color *= scanline;

        // Phosphor bloom
        float brightness = dot(original, float3(0.333));
        float bloom = smoothstep(0.5, 1.0, brightness) * 0.1 * intensity;
        color += original * bloom;

        // Trinitron neutral-warm tone
        color *= float3(1.01, 1.0, 0.99);

        // Slight saturation enhancement
        float luma = dot(color, float3(0.299, 0.587, 0.114));
        color = mix(float3(luma), color, 1.12);

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);
        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - Macintosh Classic — 1-bit B&W, 512×342 pixel grid, warm phosphor

    private static let macClassicShader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;
        float time = float(uniforms.frameCount) / 60.0;

        float3 original = source.sample(s, uv).rgb;

        // Subtle barrel distortion on UV
        float2 cuv = uv * 2.0 - 1.0;
        float r2 = dot(cuv, cuv);
        float2 distUV = uv + cuv * r2 * 0.008 * intensity;
        float3 sampled = source.sample(s, distUV).rgb;

        // Convert to luminance — warm white phosphor like a compact Mac
        float luma = dot(sampled, float3(0.299, 0.587, 0.114));

        // Crisp contrast for sharp Mac text
        luma = clamp((luma - 0.5) * 1.5 + 0.5, 0.0, 1.0);

        // Classic Mac warm phosphor: beige paper, dark ink
        float3 paper = float3(0.93, 0.90, 0.82);
        float3 ink   = float3(0.06, 0.05, 0.04);
        float3 color = mix(ink, paper, luma);

        // Faint pixel grid overlay
        float2 pixFrac = fract(distUV * texSize);
        float gridX = smoothstep(0.0, 0.06, pixFrac.x) * smoothstep(0.0, 0.06, 1.0 - pixFrac.x);
        float gridY = smoothstep(0.0, 0.06, pixFrac.y) * smoothstep(0.0, 0.06, 1.0 - pixFrac.y);
        color *= mix(0.95, 1.0, gridX * gridY * intensity);

        // Subtle scanlines — not heavy, just enough to hint at CRT
        float scanline = sin(distUV.y * texSize.y * M_PI_F) * 0.5 + 0.5;
        color *= mix(1.0, scanline, 0.12 * intensity);

        // Phosphor glow on bright areas
        float glow = smoothstep(0.5, 1.0, luma) * 0.08;
        color += float3(1.0, 0.95, 0.88) * glow * intensity;

        // Edge curvature darkening
        float curveDark = 1.0 - r2 * 0.04 * intensity;
        color *= curveDark;

        // Very subtle CRT flicker
        color *= 1.0 + sin(time * 4.0) * 0.003 * intensity;

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);
        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - Apple II — green/amber phosphor with lo-res color bleed

    private static let appleIIShader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;
        float time = float(uniforms.frameCount) / 60.0;

        float3 original = source.sample(s, uv).rgb;

        // Per-channel chromatic aberration — NTSC artifact coloring
        float ca = 0.0008 * intensity;
        float r = source.sample(s, uv + float2(ca, 0)).r;
        float g = source.sample(s, uv).g;
        float b = source.sample(s, uv - float2(ca, 0)).b;
        float3 sampled = float3(r, g, b);

        // 3-tap horizontal softness — simulates NTSC bandwidth
        float bleed = 1.0 / texSize.x;
        float3 left  = source.sample(s, uv + float2(-bleed, 0)).rgb;
        float3 right = source.sample(s, uv + float2( bleed, 0)).rgb;
        float3 color = sampled * 0.6 + left * 0.2 + right * 0.2;

        // Convert to yellow-green phosphor
        float luma = dot(color, float3(0.299, 0.587, 0.114));
        float3 phosphor = float3(luma * 0.25, luma * 1.0, luma * 0.15);

        // Amber warmth in bright areas
        phosphor.r += luma * luma * 0.12;

        // Phosphor glow on bright areas — enhanced bloom on bright chars
        float glow = smoothstep(0.3, 0.9, luma) * 0.14;
        phosphor += float3(0.1, 0.55, 0.08) * glow * intensity;

        // Scanlines
        float scanline = sin(uv.y * texSize.y * M_PI_F) * 0.5 + 0.5;
        phosphor *= mix(1.0, scanline, 0.2 * intensity);

        // Phosphor persistence — slight vertical smear
        float3 above = source.sample(s, uv + float2(0, 0.5 / texSize.y)).rgb;
        float lumaAbove = dot(above, float3(0.299, 0.587, 0.114));
        phosphor += float3(0.12, 0.7, 0.08) * lumaAbove * 0.05 * intensity;

        // CRT flicker
        phosphor *= 1.0 + sin(time * 3.5) * 0.006 * intensity;

        // Edge curvature darkening
        float2 edge = uv * 2.0 - 1.0;
        phosphor *= 1.0 - dot(edge, edge) * 0.05 * intensity;

        phosphor = mix(original, clamp(phosphor, 0.0, 1.0), intensity);
        phosphor = applyVignette(phosphor, uv, uniforms.vignetteIntensity);
        return float4(phosphor, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - Aqua — early Mac OS X glossy Cinema Display look

    private static let aquaShader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float intensity = uniforms.intensity;
        float2 res = uniforms.outputSize.xy;

        float3 original = source.sample(s, uv).rgb;
        float3 color = original;

        // Saturation boost — Aqua was famously vibrant
        float luma = dot(color, float3(0.299, 0.587, 0.114));
        color = mix(float3(luma), color, 1.35);

        // Slight blue tint in shadows (Apple Cinema Display characteristic)
        color.b += (1.0 - luma) * 0.04;

        // Gentle highlight bloom — the "glossy" Aqua glow
        float3 bloom = float3(0.0);
        float bloomSize = 2.0 / res.x;
        float totalWeight = 0.0;
        for (int i = -3; i <= 3; i++) {
            for (int j = -3; j <= 3; j++) {
                float2 off = float2(float(i), float(j)) * bloomSize;
                float3 ns = source.sample(s, uv + off).rgb;
                float nl = dot(ns, float3(0.299, 0.587, 0.114));
                // Only bloom bright areas (specular highlights, glossy UI elements)
                float w = smoothstep(0.6, 1.0, nl);
                bloom += ns * w;
                totalWeight += w;
            }
        }
        if (totalWeight > 0.0) {
            bloom /= totalWeight;
            float bloomLuma = dot(original, float3(0.299, 0.587, 0.114));
            float bloomAmount = smoothstep(0.5, 0.9, bloomLuma) * 0.15;
            color += bloom * bloomAmount;
        }

        // Subtle backlight bleed — brighter center, slight falloff at edges
        // (characteristic of early LCD Cinema Displays)
        float2 center = uv - 0.5;
        float dist = length(center);
        float backlight = 1.0 - dist * dist * 0.15;
        color *= backlight;

        // Very subtle IPS glow in corners (warm tone)
        float cornerDist = length(max(abs(center) - 0.35, 0.0));
        float ipsGlow = cornerDist * 0.08;
        color += float3(ipsGlow * 0.5, ipsGlow * 0.3, ipsGlow * 0.6);

        // Gamma curve — Cinema Displays had a characteristic gentle S-curve
        color = pow(color, float3(0.95));

        // Slight contrast enhancement
        color = (color - 0.5) * 1.08 + 0.5;

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);
        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - CRT Royale Lite — phosphor mask + halation bloom + scanlines

    private static let crtRoyaleLiteShader = """
    float royaleScanGauss(float dist) {
        return exp2(-6.0 * dist * dist);
    }

    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;

        float3 original = source.sample(s, uv).rgb;

        // Linear space
        float3 color = pow(original, float3(2.2));

        // Phosphor triad mask — RGB vertical stripes
        float maskPos = uv.x * texSize.x * 3.0;
        int maskPhase = int(maskPos) % 3;
        float3 mask = float3(0.3);
        if (maskPhase == 0) mask.r = 1.0;
        else if (maskPhase == 1) mask.g = 1.0;
        else mask.b = 1.0;
        mask = mix(float3(1.0), mask, 0.35 * intensity);
        color *= mask;

        // Scanlines with brightness-dependent depth
        float scanPos = uv.y * texSize.y;
        float scanFrac = fract(scanPos);
        float scanWeight = royaleScanGauss(scanFrac - 0.5);
        float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
        float scanDepth = mix(0.35, 0.12, clamp(luma * 2.0, 0.0, 1.0));
        color *= mix(1.0, scanWeight, scanDepth * intensity);

        // Halation bloom — bright areas bleed softly
        float3 bloom = float3(0.0);
        for (int i = -3; i <= 3; i++) {
            for (int j = -1; j <= 1; j++) {
                if (i == 0 && j == 0) continue;
                float2 off = float2(float(i), float(j)) / texSize;
                float3 ns = pow(source.sample(s, uv + off * 2.0).rgb, float3(2.2));
                float w = exp(-float(i*i + j*j) * 0.4);
                bloom += ns * w;
            }
        }
        bloom /= 14.0;
        color += bloom * 0.12 * intensity;

        // Back to sRGB
        color = pow(clamp(color, 0.0, 1.0), float3(1.0 / 2.2));

        // Slight barrel curvature darkening
        float2 edge = uv * 2.0 - 1.0;
        color *= 1.0 - dot(edge, edge) * 0.03 * intensity;

        color = mix(original, color, intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);
        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - Trinitron TV — consumer Trinitron slot mask + warm colors

    private static let trinitronTVShader = """
    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;

        float3 original = source.sample(s, uv).rgb;

        // Slight chromatic aberration — consumer Trinitrons had this
        float ca = 0.0006 * intensity;
        float r = source.sample(s, uv + float2(ca, 0)).r;
        float g = source.sample(s, uv).g;
        float b = source.sample(s, uv - float2(ca, 0)).b;
        float3 color = float3(r, g, b);

        // Aperture grille — vertical RGB stripes (Trinitron signature)
        float grillePitch = texSize.x * 1.0;
        float grillePos = uv.x * grillePitch;
        float grilleFrac = fract(grillePos);
        float3 grille;
        if (grilleFrac < 0.333) grille = float3(1.0, 0.7, 0.7);
        else if (grilleFrac < 0.666) grille = float3(0.7, 1.0, 0.7);
        else grille = float3(0.7, 0.7, 1.0);
        grille = mix(float3(1.0), grille, 0.25 * intensity);
        color *= grille;

        // Scanlines — moderate depth
        float scanline = sin(uv.y * texSize.y * M_PI_F) * 0.5 + 0.5;
        color *= mix(1.0, scanline, 0.18 * intensity);

        // Warm consumer TV color shift
        color *= float3(1.06, 1.0, 0.94);

        // Slight saturation boost (consumer TVs were vivid)
        float luma = dot(color, float3(0.299, 0.587, 0.114));
        color = mix(float3(luma), color, 1.12);

        // Phosphor glow
        float glow = smoothstep(0.5, 1.0, luma) * 0.06;
        color += float3(1.0, 0.95, 0.85) * glow * intensity;

        // Barrel curvature darkening at edges
        float2 edge = uv * 2.0 - 1.0;
        color *= 1.0 - dot(edge, edge) * 0.04 * intensity;

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);
        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - VCR Tracking — horizontal jitter, tracking lines, head-switch noise

    private static let vcrTrackingShader = """
    float vcrHash(float n) {
        return fract(sin(n) * 43758.5453);
    }

    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;
        float time = float(uniforms.frameCount) / 60.0;

        float3 original = source.sample(s, uv).rgb;

        // Horizontal jitter — random scanline offset
        float lineIdx = floor(uv.y * texSize.y);
        float jitter = (vcrHash(lineIdx + time * 37.0) - 0.5) * 0.003 * intensity;

        // Tracking wave — slow sine wobble
        float trackWave = sin(uv.y * 8.0 + time * 1.5) * 0.001 * intensity;

        float2 distUV = uv + float2(jitter + trackWave, 0);

        // Color separation from bad cable
        float sep = 0.002 * intensity;
        float r = source.sample(s, distUV + float2(sep, 0)).r;
        float g = source.sample(s, distUV).g;
        float b = source.sample(s, distUV - float2(sep, 0)).b;
        float3 color = float3(r, g, b);

        // Tracking line — white horizontal band that scrolls
        float trackY = fract(time * 0.15);
        float trackDist = abs(uv.y - trackY);
        float trackLine = smoothstep(0.02, 0.0, trackDist) * 0.3 * intensity;
        color += trackLine;

        // Head-switch noise at bottom
        float headSwitch = smoothstep(0.92, 0.98, uv.y) * intensity;
        float hsNoise = vcrHash(uv.x * 100.0 + time * 200.0);
        color = mix(color, float3(hsNoise * 0.8), headSwitch * 0.5);
        float hsJitter = (vcrHash(uv.y * 500.0 + time * 100.0) - 0.5) * 0.05;
        color = mix(color, source.sample(s, uv + float2(hsJitter, 0)).rgb, headSwitch * 0.3);

        // Scanlines
        float scanline = sin(uv.y * texSize.y * M_PI_F) * 0.5 + 0.5;
        color *= mix(1.0, scanline, 0.1 * intensity);

        // VHS color degradation — reduce saturation slightly
        float luma = dot(color, float3(0.299, 0.587, 0.114));
        color = mix(float3(luma), color, 0.85);

        // Slight warm shift
        color *= float3(1.02, 1.0, 0.96);

        // Film grain noise
        float grain = (vcrHash(uv.x * texSize.x + uv.y * texSize.y * texSize.x + time * 1000.0) - 0.5) * 0.04 * intensity;
        color += grain;

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);
        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """

    // MARK: - Cinema Film — cinematic color grading + grain + halation

    private static let cinemaFilmShader = """
    float filmNoise(float2 uv, float time) {
        return fract(sin(dot(uv + time, float2(12.9898, 78.233))) * 43758.5453);
    }

    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]],
        texture2d<float> source [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 uv = in.texCoord;
        float2 texSize = uniforms.sourceSize.xy;
        float intensity = uniforms.intensity;
        float time = float(uniforms.frameCount) / 60.0;

        float3 original = source.sample(s, uv).rgb;
        float3 color = original;

        // Cinematic color grading — lift shadows to blue, push highlights warm
        float luma = dot(color, float3(0.2126, 0.7152, 0.0722));

        // Shadow lift: cool blue-teal tint
        float3 shadows = float3(0.04, 0.05, 0.08) * (1.0 - luma);
        // Highlight push: warm golden
        float3 highlights = float3(0.06, 0.03, -0.02) * luma;
        color += (shadows + highlights) * intensity;

        // Gentle halation — bright areas softly bloom
        float3 bloom = float3(0.0);
        for (int i = -2; i <= 2; i++) {
            for (int j = -2; j <= 2; j++) {
                if (i == 0 && j == 0) continue;
                float2 off = float2(float(i), float(j)) / texSize * 3.0;
                float3 ns = source.sample(s, uv + off).rgb;
                float nl = dot(ns, float3(0.2126, 0.7152, 0.0722));
                float w = exp(-float(i*i + j*j) * 0.5);
                bloom += ns * w * smoothstep(0.6, 1.0, nl);
            }
        }
        bloom /= 8.0;
        color += bloom * 0.08 * intensity;

        // S-curve contrast (filmic tone)
        color = clamp(color, 0.0, 1.0);
        color = color * color * (3.0 - 2.0 * color);
        color = mix(original, color, 0.4 * intensity);

        // Film grain — per-frame noise
        float grain = (filmNoise(uv * texSize, time) - 0.5) * 0.035 * intensity;
        color += grain;

        // Subtle gate weave — very slight vertical shift
        float weave = sin(time * 2.0) * 0.0003 * intensity;
        float3 weaved = source.sample(s, uv + float2(0, weave)).rgb;
        color = mix(color, weaved, 0.3);

        // Slight desaturation (film stock look)
        float lumaFinal = dot(color, float3(0.2126, 0.7152, 0.0722));
        color = mix(float3(lumaFinal), color, mix(1.0, 0.9, intensity));

        color = mix(original, clamp(color, 0.0, 1.0), intensity);
        color = applyVignette(color, uv, uniforms.vignetteIntensity);
        return float4(color, sampleSourceAlpha(source, s, in.texCoord));
    }
    """
}
