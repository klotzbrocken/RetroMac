import AppKit
import ScreenCaptureKit

/// A small strip of a window's own title bar, photographed from the screen, so the patch that
/// hides the real traffic lights can wear the bar's real colour: light or dark, tinted, active
/// or not. One capture per request, asynchronous, through the Screen Recording permission the
/// shader already holds.
enum NativeBarSampler {

    /// Capture `rect` (Quartz global, top-left origin, points) from the display it lies on.
    static func sample(_ rect: CGRect, completion: @escaping (NSImage?) -> Void) {
        Task {
            let image = await capture(rect)
            await MainActor.run { completion(image) }
        }
    }

    private static func capture(_ rect: CGRect) async -> NSImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return nil }
        // The display whose frame holds the rect. SCDisplay.frame is Quartz too.
        guard let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }) else { return nil }
        let scale = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID }?.backingScaleFactor ?? 2
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: rect.minX - display.frame.minX, y: rect.minY - display.frame.minY, width: rect.width, height: rect.height)
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        return NSImage(cgImage: cg, size: rect.size)
    }
}
