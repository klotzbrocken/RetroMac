import AppKit
import CoreGraphics

/// The still that makes the desktop look frozen.
///
/// Nothing is actually frozen: a photograph of the screen is laid over the screen, and the living
/// desktop carries on underneath it. That is the whole trick, and it is why the illusion costs
/// nothing and can be taken away at any instant.
enum DesktopFreeze {

    /// One image per screen, in `NSScreen.screens` order. Entries are nil where the capture
    /// failed, and the caller falls back to black for those.
    ///
    /// Without Screen Recording consent `CGDisplayCreateImage` does not fail loudly on current
    /// macOS — it hands back a picture of the wallpaper and nothing else, which would put a
    /// "frozen desktop" on screen that is visibly not the user's. So consent is checked first,
    /// and the freeze stage is skipped rather than faked. This path never prompts for permission:
    /// being asked for Screen Recording by a joke is not a good moment for anyone.
    static func capture() -> [CGImage?] {
        guard CGPreflightScreenCaptureAccess() else {
            return Array(repeating: nil, count: NSScreen.screens.count)
        }
        return NSScreen.screens.map { screen in
            guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber,
                  let image = CGDisplayCreateImage(CGDirectDisplayID(number.uint32Value)),
                  !looksBlank(image) else { return nil }
            return image
        }
    }

    /// Whether a capture came back empty.
    ///
    /// `CGPreflightScreenCaptureAccess()` is not enough on its own: it can answer yes while the
    /// capture still hands back a uniform black frame — a stale TCC grant after a rebuild does
    /// exactly that. A "frozen desktop" that is a black rectangle is worse than no freeze at all,
    /// so the picture itself is checked rather than the permission that was supposed to promise
    /// it. Sixty-four samples is enough to tell a desktop from a void.
    static func looksBlank(_ image: CGImage) -> Bool {
        let side = 8
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var lowest = 255, highest = 0
        for i in stride(from: 0, to: side * side * 4, by: 4) {
            let luma = (Int(pixels[i]) * 3 + Int(pixels[i + 1]) * 6 + Int(pixels[i + 2])) / 10
            lowest = min(lowest, luma); highest = max(highest, luma)
        }
        return highest < 8 || (highest - lowest) < 3
    }

    /// Whether the machine will really hand over a picture of the screen. Takes one and looks at
    /// it, because the permission API alone lies (see `looksBlank`). Used by the settings pane to
    /// explain why the build-up is missing rather than leaving it silently absent.
    static func canFreeze() -> Bool {
        guard CGPreflightScreenCaptureAccess(),
              let screen = NSScreen.main,
              let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber,
              let image = CGDisplayCreateImage(CGDirectDisplayID(number.uint32Value)) else { return false }
        return !looksBlank(image)
    }

    /// Only ever a hint: see `looksBlank`. The capture is what decides.
    static var isAvailable: Bool { CGPreflightScreenCaptureAccess() }
}
