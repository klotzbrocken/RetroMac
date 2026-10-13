import CoreGraphics
import Foundation

/// Built-in textures for savers' textured surface styles. They're generated procedurally and tile
/// seamlessly, so they can be wrapped around shapes the way the Windows originals wrapped a bitmap.
enum RetroTexture: CaseIterable {
    case marble
    case wood
    case granite

    /// Strength of the white specular highlight.
    var specular: CGFloat {
        switch self {
        case .marble: return 0.9
        case .wood: return 0.35
        case .granite: return 0.6
        }
    }

    func makeImage(size: Int = 256) -> CGImage {
        var rng = SplitMix64(seed: seed)
        let shade = makeShader(rng: &rng)
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let color = shade((Float(x) + 0.5) / Float(size), (Float(y) + 0.5) / Float(size))
                let i = (y * size + x) * 4
                for channel in 0..<3 {
                    pixels[i + channel] = UInt8((color[channel].clamped(to: 0...1) * 255).rounded())
                }
            }
        }
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )!
    }

    private var seed: UInt64 {
        switch self {
        case .marble: return 1
        case .wood: return 2
        case .granite: return 3
        }
    }

    /// Returns a function from texture coordinates (each 0..<1) to an RGB colour. Grain and veins run
    /// along `v` (along a pipe, for instance). Anything periodic in both keeps the texture seamless.
    private func makeShader(rng: inout SplitMix64) -> (Float, Float) -> SIMD3<Float> {
        switch self {
        case .marble:
            let turbulence = FractalNoise(period: 4, octaves: 4, rng: &rng)
            let clouds = FractalNoise(period: 8, octaves: 4, rng: &rng)
            let fade = FractalNoise(period: 2, octaves: 3, rng: &rng)
            return { u, v in
                let phase: Float = 2 * u + v + 1.6 * turbulence.value(u, v)
                let vein = pow(1 - abs(sin(2 * .pi * phase)), 5)
                // Let veins fade in and out instead of running at full strength everywhere.
                let strength = ((fade.value(u, v) - 0.3) / 0.4).clamped(to: 0...1)
                let base = lerp([0.95, 0.94, 0.91], [0.74, 0.75, 0.78], clouds.value(u, v))
                return lerp(base, [0.2, 0.22, 0.28], vein * strength)
            }

        case .wood:
            // Varies slowly along the pipe, so the grain runs fairly straight.
            let warp = FractalNoise(periodU: 4, periodV: 1, octaves: 3, rng: &rng)
            // Fine streaks running along the pipe.
            let fibres = FractalNoise(periodU: 64, periodV: 4, octaves: 3, rng: &rng)
            return { u, v in
                let rings: Float = 6 * u + 0.5 * warp.value(u, v)
                let ring = pow(0.5 + 0.5 * sin(2 * .pi * rings), 2.5)
                let color = lerp([0.78, 0.56, 0.32], [0.46, 0.27, 0.12], ring)
                return color * (0.85 + 0.3 * fibres.value(u, v))
            }

        case .granite:
            let grain = FractalNoise(period: 64, octaves: 2, rng: &rng)
            let specks = FractalNoise(period: 48, octaves: 2, rng: &rng)
            return { u, v in
                let g = grain.value(u, v)
                let s = specks.value(u, v)
                if g > 0.7 { return [0.93, 0.92, 0.9] }
                if s > 0.63 { return [0.12, 0.11, 0.12] }
                if s < 0.37 { return [0.74, 0.56, 0.52] }
                return SIMD3(repeating: 0.4 + 0.35 * g)
            }
        }
    }
}

private func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}

/// Value noise on a lattice that wraps around, so it tiles seamlessly over 0..<1.
struct TilingNoise {
    private let periodU: Int
    private let periodV: Int
    private let lattice: [Float]

    init(periodU: Int, periodV: Int, rng: inout SplitMix64) {
        self.periodU = periodU
        self.periodV = periodV
        lattice = (0..<periodU * periodV).map { _ in Float.random(in: 0...1, using: &rng) }
    }

    func value(_ u: Float, _ v: Float) -> Float {
        let x = u * Float(periodU)
        let y = v * Float(periodV)
        let x0 = Int(x.rounded(.down))
        let y0 = Int(y.rounded(.down))
        let sx = smoothstep(x - Float(x0))
        let sy = smoothstep(y - Float(y0))
        let top = lattice(x0, y0) + (lattice(x0 + 1, y0) - lattice(x0, y0)) * sx
        let bottom = lattice(x0, y0 + 1) + (lattice(x0 + 1, y0 + 1) - lattice(x0, y0 + 1)) * sx
        return top + (bottom - top) * sy
    }

    private func lattice(_ i: Int, _ j: Int) -> Float {
        let wrappedI = (i % periodU + periodU) % periodU
        let wrappedJ = (j % periodV + periodV) % periodV
        return lattice[wrappedJ * periodU + wrappedI]
    }

    private func smoothstep(_ t: Float) -> Float {
        t * t * (3 - 2 * t)
    }
}

/// Several octaves of `TilingNoise`, each at double the frequency and half the amplitude.
struct FractalNoise {
    private let octaves: [TilingNoise]

    init(period: Int, octaves: Int, rng: inout SplitMix64) {
        self.init(periodU: period, periodV: period, octaves: octaves, rng: &rng)
    }

    init(periodU: Int, periodV: Int, octaves count: Int, rng: inout SplitMix64) {
        octaves = (0..<count).map { TilingNoise(periodU: periodU << $0, periodV: periodV << $0, rng: &rng) }
    }

    /// 0...1, clustered around 0.5.
    func value(_ u: Float, _ v: Float) -> Float {
        var sum: Float = 0
        var amplitude: Float = 1
        var total: Float = 0
        for octave in octaves {
            sum += octave.value(u, v) * amplitude
            total += amplitude
            amplitude /= 2
        }
        return sum / total
    }
}
