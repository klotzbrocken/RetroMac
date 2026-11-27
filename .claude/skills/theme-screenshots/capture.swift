// Captures the main display with only the desktop picture, the menu bar, RetroMac's own windows
// and the windows of the bundle IDs given after the output path. Everything else on screen
// (the user's own windows) stays out of the picture.
// usage: capture <out.png> [bundle.id ...]
import ScreenCaptureKit
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: capture <out.png> [bundle.id ...]"); exit(2) }
let out = args[1], extra = Set(args.dropFirst(2))
let done = DispatchSemaphore(value: 0)
var failed = false
Task {
    do {
        let c = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let d = c.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { throw CocoaError(.featureUnsupported) }
        let keep = c.windows.filter { w in
            let b = w.owningApplication?.bundleIdentifier ?? "", t = w.title ?? ""
            // the floating launcher button is RetroMac's own helper, not part of a theme
            return (b.hasPrefix("com.retromac.app") && t != "RetroMac") || extra.contains(b) || t == "Wallpaper" || t == "Menubar"
        }
        let cfg = SCStreamConfiguration()
        cfg.width = d.width * 2; cfg.height = d.height * 2; cfg.showsCursor = false
        let img = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: d, including: keep), configuration: cfg)
        try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    } catch { print("capture failed: \(error)"); failed = true }
    done.signal()
}
done.wait()
exit(failed ? 1 : 0)
