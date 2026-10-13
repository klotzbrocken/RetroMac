import AppKit

/// The maze's surfaces, generated at launch: red brick walls, a wooden floor, acoustic ceiling
/// tiles, and the smiley at the finish. Each tiles seamlessly over one maze cell.
enum MazeTextures {
    static func brickWall(size: Int = 256) -> CGImage {
        var rng = SplitMix64(seed: 11)
        let grain = FractalNoise(period: 32, octaves: 3, rng: &rng)
        let rows = 4
        let bricksPerRow = 2
        let mortar: Float = 0.035
        // A brightness for every brick, so they don't all look the same.
        let shades = (0..<(rows * bricksPerRow)).map { _ in Float.random(in: 0.82...1.12, using: &rng) }
        return image(size: size) { u, v in
            let row = min(Int(v * Float(rows)), rows - 1)
            let shifted = u + (row % 2 == 0 ? 0 : 0.5 / Float(bricksPerRow))
            let along = shifted * Float(bricksPerRow)
            let column = Int(along.rounded(.down)) % bricksPerRow
            let x = along - along.rounded(.down)
            let y = v * Float(rows) - Float(row)
            let edge = min(min(x, 1 - x) / Float(bricksPerRow), min(y, 1 - y) / Float(rows))
            if edge < mortar / 2 {
                return SIMD3(0.7, 0.67, 0.62) * (0.9 + 0.2 * grain.value(u, v))
            }
            let brick = SIMD3<Float>(0.6, 0.24, 0.16) * shades[row * bricksPerRow + column]
            // Slightly darker towards the mortar, so the bricks look rounded off.
            let rim = min(edge / (mortar * 1.6), 1)
            return brick * (0.75 + 0.25 * rim) * (0.85 + 0.3 * grain.value(u, v))
        }
    }

    static func woodFloor(size: Int = 256) -> CGImage {
        var rng = SplitMix64(seed: 12)
        let fibres = FractalNoise(periodU: 48, periodV: 3, octaves: 3, rng: &rng)
        let planks = 4
        let shades = (0..<planks).map { _ in Float.random(in: 0.85...1.1, using: &rng) }
        return image(size: size) { u, v in
            let along = u * Float(planks)
            let plank = min(Int(along), planks - 1)
            let x = along - Float(plank)
            if x < 0.03 || x > 0.97 {
                return SIMD3(0.18, 0.11, 0.06)
            }
            let base = SIMD3<Float>(0.55, 0.36, 0.2) * shades[plank]
            return base * (0.75 + 0.5 * fibres.value(u, v))
        }
    }

    static func ceilingTiles(size: Int = 256) -> CGImage {
        var rng = SplitMix64(seed: 13)
        let speckles = FractalNoise(period: 64, octaves: 2, rng: &rng)
        let shading = FractalNoise(period: 4, octaves: 2, rng: &rng)
        return image(size: size) { u, v in
            let edge = min(min(u, 1 - u), min(v, 1 - v))
            if edge < 0.02 {
                return SIMD3(0.35, 0.35, 0.36)
            }
            var color = SIMD3<Float>(repeating: 0.78 + 0.1 * shading.value(u, v))
            if speckles.value(u, v) > 0.64 {
                color *= 0.6
            }
            return color
        }
    }

    /// A yellow smiley on a transparent background.
    static func smiley(size: Int = 256) -> CGImage {
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let s = CGFloat(size)
        context.setFillColor(NSColor(srgbRed: 1, green: 0.85, blue: 0.1, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: s * 0.02, y: s * 0.02, width: s * 0.96, height: s * 0.96))
        context.setFillColor(NSColor.black.cgColor)
        context.fillEllipse(in: CGRect(x: s * 0.3, y: s * 0.55, width: s * 0.11, height: s * 0.18))
        context.fillEllipse(in: CGRect(x: s * 0.59, y: s * 0.55, width: s * 0.11, height: s * 0.18))
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(s * 0.06)
        context.setLineCap(.round)
        context.addArc(center: CGPoint(x: s / 2, y: s * 0.5), radius: s * 0.27, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
        context.strokePath()
        return context.makeImage()!
    }

    /// An image from a function of texture coordinates (each 0..<1) to an RGB colour.
    private static func image(size: Int, color: (Float, Float) -> SIMD3<Float>) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let value = color((Float(x) + 0.5) / Float(size), (Float(y) + 0.5) / Float(size))
                let i = (y * size + x) * 4
                for channel in 0..<3 {
                    pixels[i + channel] = UInt8((value[channel].clamped(to: 0...1) * 255).rounded())
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
}
