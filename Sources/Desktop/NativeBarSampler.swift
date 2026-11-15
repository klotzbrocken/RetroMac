import AppKit
import ScreenCaptureKit

/// A small strip of a window's own title bar, photographed, so the patch that hides the real
/// traffic lights can wear the bar's real colour: light or dark, tinted, active or not.
/// Asynchronous, through the Screen Recording permission the shader already holds.
///
/// The picture is of that window alone (a single-window filter), not of the screen: where
/// another window lay over the spot, its colour used to end up in the patch, and the patch
/// itself had to be hidden for the photograph.
enum NativeBarSampler {

    /// Capture `rect` (Quartz global, top-left origin, points) out of window `wid`.
    static func sample(_ rect: CGRect, window wid: CGWindowID, completion: @escaping (NSImage?) -> Void) {
        Task {
            let image = await capture(rect, window: wid)
            await MainActor.run { completion(image) }
        }
    }

    private static func capture(_ rect: CGRect, window wid: CGWindowID) async -> NSImage? {
        // A window opened a moment ago may not be in a list that is still fresh: ask once more.
        var found = await Shareable.shared.content()?.windows.first { $0.windowID == wid }
        if found == nil { found = await Shareable.shared.content(fresh: true)?.windows.first { $0.windowID == wid } }
        guard let window = found else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.ignoreShadowsSingleWindow = true   // so the window's frame is the picture's frame
        config.sourceRect = CGRect(x: rect.minX - window.frame.minX, y: rect.minY - window.frame.minY,
                                   width: rect.width, height: rect.height)
        config.width = max(1, Int(rect.width * scale))
        config.height = max(1, Int(rect.height * scale))
        config.showsCursor = false
        config.captureResolution = .best
        guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        return NSImage(cgImage: cg, size: rect.size)
    }

    /// The list of shareable windows, asked for once a second at most: a theme switch samples
    /// every window at the same moment, and each request used to ask the WindowServer for the
    /// whole list on its own. Requests that arrive while one is under way wait for it.
    private actor Shareable {
        static let shared = Shareable()
        private var cached: (at: Date, content: SCShareableContent)?
        private var inFlight: Task<SCShareableContent?, Never>?

        func content(fresh: Bool = false) async -> SCShareableContent? {
            if !fresh, let c = cached, Date().timeIntervalSince(c.at) < 1 { return c.content }
            if let t = inFlight { return await t.value }
            let t = Task { try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
            inFlight = t
            let value = await t.value
            inFlight = nil
            if let value { cached = (Date(), value) }
            return value
        }
    }
}
