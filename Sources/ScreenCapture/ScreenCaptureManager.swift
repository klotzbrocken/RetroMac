import ScreenCaptureKit
import Metal
import CoreMedia
import CoreVideo
import AppKit

final class ScreenCaptureManager: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var textureCache: CVMetalTextureCache?
    private var retainedTexture: CVMetalTexture?   // keeps the latest frame's IOSurface alive
    private let device: MTLDevice
    var onNewFrame: ((MTLTexture) -> Void)?
    private var hasReceivedFirstFrame = false
    var onFirstFrame: (() -> Void)?
    private var targetFPS: Int = 30

    init(device: MTLDevice) {
        self.device = device
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    func setFrameRate(fps: Int) {
        targetFPS = fps
    }

    func start(excludingWindowIDs: [CGWindowID]) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = try buildExclusionFilter(display: display, content: content, excludingWindowIDs: excludingWindowIDs)

        let config = SCStreamConfiguration()
        let (w, h) = await captureSize(for: display)
        config.width = w
        config.height = h
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        config.queueDepth = targetFPS > 30 ? 5 : 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        try await startStream(filter: filter, config: config)
    }

    func startDisplay(_ displayID: CGDirectDisplayID, excludingWindowIDs: [CGWindowID], content: SCShareableContent? = nil) async throws {
        let resolvedContent: SCShareableContent
        if let content = content {
            resolvedContent = content
        } else {
            resolvedContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
        guard let display = resolvedContent.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }

        let filter = try buildExclusionFilter(display: display, content: resolvedContent, excludingWindowIDs: excludingWindowIDs)

        let config = SCStreamConfiguration()
        let (w, h) = await captureSize(for: display)
        config.width = w
        config.height = h
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        config.queueDepth = targetFPS > 30 ? 5 : 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        try await startStream(filter: filter, config: config)
    }

    /// Determine capture size from NSScreen (matches overlay window) rather than
    /// SCDisplay (native CG points). On scaled external displays (e.g. Studio Display XDR
    /// set to "Looks like 2560×1440") SCDisplay.width/height return the unscaled native
    /// resolution, which is larger than the overlay window → content offset bug.
    private func captureSize(for display: SCDisplay) async -> (Int, Int) {
        let halfRes = AppSettings.shared.halfResolution
        let result: (Int, Int) = await MainActor.run {
            // PRIMARY: the display's actual framebuffer pixel resolution. This is what
            // ScreenCaptureKit captures at, so the output buffer matches exactly and the
            // overlay fills the whole screen — even on HiDPI-scaled external monitors
            // where (points × backingScaleFactor) does NOT equal native pixels.
            if let mode = CGDisplayCopyDisplayMode(display.displayID) {
                var w = mode.pixelWidth
                var h = mode.pixelHeight
                if halfRes { w /= 2; h /= 2 }
                print("[Capture] Display \(display.displayID) native pixels: \(w)x\(h) (mode pixelWidth/Height)")
                return (w, h)
            }
            // Fallback: NSScreen points × backing scale
            if let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) {
                let scale = halfRes ? 1.0 : screen.backingScaleFactor
                let w = Int(screen.frame.width * scale)
                let h = Int(screen.frame.height * scale)
                print("[Capture] Fallback NSScreen size for \(display.displayID): \(w)x\(h)")
                return (w, h)
            }
            // Last resort: SCDisplay dimensions
            let scale = halfRes ? 1 : 2
            return (Int(display.width) * scale, Int(display.height) * scale)
        }
        return result
    }

    func startWindow(_ scWindow: SCWindow, excludingWindowIDs: [CGWindowID]) async throws {
        let appName = scWindow.owningApplication?.applicationName ?? "?"
        let title = scWindow.title ?? "?"
        print("[Capture] Window mode: \(appName) — \(title) (id=\(scWindow.windowID), \(Int(scWindow.frame.width))x\(Int(scWindow.frame.height)))")

        // Re-fetch content for a fresh SCWindow reference
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let freshWindow = content.windows.first(where: { $0.windowID == scWindow.windowID }) else {
            print("[Capture] ERROR: Window \(scWindow.windowID) no longer found")
            throw CaptureError.noDisplay
        }
        print("[Capture] Fresh window: \(freshWindow.owningApplication?.applicationName ?? "?") — onScreen=\(freshWindow.isOnScreen), frame=\(freshWindow.frame)")

        let filter = SCContentFilter(desktopIndependentWindow: freshWindow)

        // Use the scale of the display the window is ON, not the main display — otherwise
        // a window on a secondary screen with a different backingScaleFactor is captured
        // at the wrong resolution. SCWindow.frame is in CG global coords, matching CGDisplayBounds.
        let windowFrame = freshWindow.frame
        let scale = await MainActor.run { () -> Int in
            let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
            for screen in NSScreen.screens {
                if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                   CGDisplayBounds(num).contains(center) {
                    return Int(screen.backingScaleFactor)
                }
            }
            return Int(NSScreen.main?.backingScaleFactor ?? 2)
        }
        let w = max(Int(freshWindow.frame.width) * scale, 200)
        let h = max(Int(freshWindow.frame.height) * scale, 200)

        let config = SCStreamConfiguration()
        config.width = w
        config.height = h
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        config.queueDepth = targetFPS > 30 ? 5 : 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        print("[Capture] Window config: \(w)x\(h) @ \(scale)x, \(targetFPS)fps")
        try await startStream(filter: filter, config: config)
    }

    private static let excludedBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
    ]

    static func listWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return content.windows.filter {
            $0.owningApplication?.processID != ownPID &&
            $0.frame.width > 100 && $0.frame.height > 100 &&
            $0.isOnScreen &&
            !excludedBundleIDs.contains($0.owningApplication?.bundleIdentifier ?? "")
        }
    }

    func updateStreamSize(width: Int, height: Int) {
        guard let stream = stream else { return }
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        config.queueDepth = targetFPS > 30 ? 5 : 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        stream.updateConfiguration(config) { error in
            if let error = error {
                print("[Capture] Resize failed: \(error.localizedDescription)")
            } else {
                print("[Capture] Resized to \(width)x\(height) @\(self.targetFPS)fps")
            }
        }
    }

    func stop() {
        let stoppingStream = stream
        stream = nil
        hasReceivedFirstFrame = false
        frameLogCount = 0
        stoppingStream?.stopCapture { error in
            if let error = error {
                print("[Capture] Stop error: \(error.localizedDescription)")
            }
        }
        print("[Capture] Stopped.")
    }

    // MARK: - Private

    private func buildExclusionFilter(display: SCDisplay, content: SCShareableContent, excludingWindowIDs: [CGWindowID]) throws -> SCContentFilter {
        let idSet = Set(excludingWindowIDs)
        let windowsToExclude = content.windows.filter { idSet.contains($0.windowID) }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownBundle = Bundle.main.bundleIdentifier ?? ""
        let excludedApps = content.applications.filter {
            $0.processID == ownPID || $0.bundleIdentifier == ownBundle
        }

        print("[Capture] Display: \(display.width)x\(display.height)")
        print("[Capture] Window exclusion: \(windowsToExclude.count)/\(excludingWindowIDs.count), App exclusion: \(excludedApps.count)")

        if !windowsToExclude.isEmpty {
            print("[Capture] → window-level filter")
            return SCContentFilter(display: display, excludingWindows: windowsToExclude)
        } else if !excludedApps.isEmpty {
            print("[Capture] → app-level filter")
            return SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
        } else {
            let ownWindows = content.windows.filter {
                $0.owningApplication?.processID == ownPID ||
                $0.owningApplication?.bundleIdentifier == ownBundle
            }
            if !ownWindows.isEmpty {
                print("[Capture] → PID-matched window filter (\(ownWindows.count))")
                return SCContentFilter(display: display, excludingWindows: ownWindows)
            }
            print("[Capture] WARNING: no exclusion possible")
            return SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        }
    }

    private func startStream(filter: SCContentFilter, config: SCStreamConfiguration) async throws {
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream.startCapture()
        self.stream = stream
        print("[Capture] Started.")
    }

    // MARK: - SCStreamOutput

    private var frameLogCount = 0

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        guard let pixelBuffer = sampleBuffer.imageBuffer else {
            if frameLogCount < 5 {
                frameLogCount += 1
                print("[Capture] Frame \(frameLogCount): no imageBuffer (status-only)")
            }
            return
        }
        guard let textureCache = textureCache else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTex = cvTexture,
              let texture = CVMetalTextureGetTexture(cvTex) else {
            if frameLogCount < 5 {
                frameLogCount += 1
                print("[Capture] Frame: texture creation failed (status=\(status), \(width)x\(height))")
            }
            return
        }

        // Retain THIS frame's CVMetalTexture so its IOSurface stays alive. ScreenCaptureKit only
        // delivers new frames when the display content changes; a static display (e.g. the
        // built-in) sends one frame then goes idle. Without holding the buffer, SCK recycles it
        // and the cached MTLTexture turns to garbage/black. Holding the latest keeps it valid so
        // the overlay can keep presenting it. (Replaced — and the old one released — each frame.)
        retainedTexture = cvTex

        if !hasReceivedFirstFrame {
            hasReceivedFirstFrame = true
            print("[Capture] First frame: \(width)x\(height)")
            DispatchQueue.main.async { self.onFirstFrame?() }
        }

        onNewFrame?(texture)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[Capture] Error: \(error.localizedDescription)")
    }

    enum CaptureError: Error, LocalizedError {
        case noDisplay
        var errorDescription: String? { "No display found" }
    }
}
