import AppKit
import CoreImage

/// Corrupts the frozen desktop on the way to the error screen.
///
/// The effects are the ones these machines really produced, not a general "glitch art" look:
///
///  - **Redraw trails.** Before a compositor, every program drew straight into the frame buffer.
///    When one stopped answering, anything dragged over it smeared, because nothing repainted the
///    damaged area. This is the single most recognisable symptom of a hung Windows 9x machine —
///    and it stops being possible with Vista's Desktop Window Manager, which draws every window
///    into its own buffer first. So Windows 7 does not get it, and neither does Mac OS X, which
///    had Quartz compositing from the start.
///  - **Torn bands.** Rows displaced sideways when the video read went wrong: a hardware fault,
///    not a software one, so every era gets it.
///  - **Stale blocks.** Rectangles of video memory showing something that was there earlier.
///    Copied from elsewhere in the same picture rather than filled with noise, because that is
///    what stale memory actually looks like.
///  - **Colour breakdown.** In 256-colour modes a corrupted palette repainted the whole screen in
///    the wrong colours. On 32-bit desktops that could not happen, so XP and later get a channel
///    shift — a failing cable or connector — instead.
enum CrashGlitch {

    /// How far gone the picture is, 0…1.
    typealias Severity = Double

    static func corrupt(_ image: CGImage, era: CrashEra, severity: Severity,
                        seed: UInt64) -> CGImage? {
        var rng = CrashRNG(seed: seed)
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        if era.hasRedrawTrails { smear(ctx, image, severity: severity, rng: &rng) }
        tearBands(ctx, image, severity: severity, rng: &rng)
        staleBlocks(ctx, image, severity: severity, rng: &rng)

        guard let torn = ctx.makeImage() else { return nil }
        return colourBreakdown(torn, era: era, severity: severity)
    }

    // MARK: - Effects

    /// A window dragged across a hung desktop, repeated because nothing repainted behind it.
    private static func smear(_ ctx: CGContext, _ image: CGImage,
                              severity: Severity, rng: inout CrashRNG) {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let count = Int(severity * 4)
        for _ in 0..<count {
            let bw = CGFloat.random(in: w * 0.18...w * 0.42, using: &rng)
            let bh = CGFloat.random(in: h * 0.10...h * 0.30, using: &rng)
            let x = CGFloat.random(in: 0...(w - bw), using: &rng)
            let y = CGFloat.random(in: 0...(h - bh), using: &rng)
            guard let slice = image.cropping(to: CGRect(x: x, y: y, width: bw, height: bh)) else { continue }
            let steps = Int(2 + severity * 5)
            let dx = CGFloat.random(in: -18...18, using: &rng)
            let dy = CGFloat.random(in: -14...14, using: &rng)
            for step in 1...steps {
                let k = CGFloat(step)
                ctx.draw(slice, in: CGRect(x: x + dx * k, y: y + dy * k, width: bw, height: bh))
            }
        }
    }

    /// Rows displaced sideways, the tear of a video signal read at the wrong moment.
    private static func tearBands(_ ctx: CGContext, _ image: CGImage,
                                  severity: Severity, rng: inout CrashRNG) {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let count = Int(1 + severity * 8)
        for _ in 0..<count {
            let bh = CGFloat.random(in: 3...max(5, h * 0.04), using: &rng)
            let y = CGFloat.random(in: 0...(h - bh), using: &rng)
            guard let band = image.cropping(to: CGRect(x: 0, y: y, width: w, height: bh)) else { continue }
            // Squared, so the first stage is a twitch and only the last one is a wreck.
            let shift = CGFloat.random(in: -w * 0.10...w * 0.10, using: &rng) * severity * severity
            // The band wraps rather than leaving a hole: the pixels pushed off one edge come
            // back on the other, which is what a mistimed line actually does.
            ctx.draw(band, in: CGRect(x: shift > 0 ? shift - w : shift + w, y: y, width: w, height: bh))
            ctx.draw(band, in: CGRect(x: shift, y: y, width: w, height: bh))
        }
    }

    /// Rectangles of video memory still holding something from before.
    private static func staleBlocks(_ ctx: CGContext, _ image: CGImage,
                                    severity: Severity, rng: inout CrashRNG) {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let count = Int(severity * 12)
        for _ in 0..<count {
            let bw = CGFloat.random(in: w * 0.03...w * 0.18, using: &rng)
            let bh = CGFloat.random(in: h * 0.02...h * 0.12, using: &rng)
            let sx = CGFloat.random(in: 0...(w - bw), using: &rng)
            let sy = CGFloat.random(in: 0...(h - bh), using: &rng)
            let dx = CGFloat.random(in: 0...(w - bw), using: &rng)
            let dy = CGFloat.random(in: 0...(h - bh), using: &rng)
            guard let block = image.cropping(to: CGRect(x: sx, y: sy, width: bw, height: bh)) else { continue }
            ctx.draw(block, in: CGRect(x: dx, y: dy, width: bw, height: bh))
        }
    }

    /// The colour failure of the era: a corrupted palette where the desktop had 256 colours, a
    /// channel shift where it had millions.
    private static func colourBreakdown(_ image: CGImage, era: CrashEra,
                                        severity: Severity) -> CGImage? {
        guard severity > 0.35 else { return image }
        let ci = CIImage(cgImage: image)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        var output: CIImage?

        if era.hasIndexedColour {
            // Palette corruption: far too few levels, and the hues pulled apart.
            let posterize = CIFilter(name: "CIColorPosterize", parameters: [
                kCIInputImageKey: ci,
                "inputLevels": max(3.0, 8.0 - severity * 5.0)])
            let hue = CIFilter(name: "CIHueAdjust", parameters: [
                kCIInputImageKey: posterize?.outputImage ?? ci,
                kCIInputAngleKey: severity * 1.4])
            output = hue?.outputImage
        } else {
            // A connector losing one line: the red channel arrives displaced.
            let matrixR = CIFilter(name: "CIColorMatrix", parameters: [
                kCIInputImageKey: ci,
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0)])
            let shifted = matrixR?.outputImage?.transformed(
                by: CGAffineTransform(translationX: CGFloat(severity * 14), y: 0))
            let rest = CIFilter(name: "CIColorMatrix", parameters: [
                kCIInputImageKey: ci,
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0)])
            if let a = shifted, let b = rest?.outputImage {
                output = CIFilter(name: "CIAdditionCompositing",
                                  parameters: [kCIInputImageKey: a,
                                               kCIInputBackgroundImageKey: b])?.outputImage
            }
        }
        guard let out = output else { return image }
        return context.createCGImage(out, from: CIImage(cgImage: image).extent) ?? image
    }
}

extension CrashEra {
    /// Everything before a compositing window server could smear. Windows gained the Desktop
    /// Window Manager in Vista, so Windows 7 cannot; Mac OS X composited from 10.0, so it never
    /// could either.
    var hasRedrawTrails: Bool {
        switch self {
        case .win95, .win98, .winMe, .winXP, .macos6, .macos9: return true
        case .win7, .macosxAqua, .macosxModern: return false
        }
    }

    /// Desktops that ran in 256 colours, where a corrupted palette repainted everything wrong.
    var hasIndexedColour: Bool {
        switch self {
        case .win95, .win98, .winMe, .macos6, .macos9: return true
        case .winXP, .win7, .macosxAqua, .macosxModern: return false
        }
    }
}
