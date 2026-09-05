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
    /// Pixel scale used for this capture (backingScaleFactor of the window's display, or 1 in
    /// halfResolution). Persisted so a later window resize reuses the SAME scale instead of
    /// guessing a constant 2×. Defaults to 2 until a stream starts.
    private(set) var captureScale: Int = 2

    /// What `startDisplayIncludingOnly` was asked to keep, and the exclusion list it last handed
    /// to the stream. An `SCContentFilter` built with `excludingWindows:` is a fixed LIST, not a
    /// rule: a window that did not exist when the stream started can never be in it and is
    /// therefore captured. Without a refresh, every application window opened after the effect
    /// starts turns up inside the desktop layer.
    private var scopeDisplayID: CGDirectDisplayID?
    private var scopeKeepIDs: Set<CGWindowID> = []
    /// Re-read on every refresh. The windows to keep are not a fixed set: a Windows start menu
    /// exists only while it is open, and it has to stay in the capture the moment it appears.
    var scopeKeepProvider: (@MainActor () -> [CGWindowID])?
    /// What the last applied filter was built from. Compared, not stored as an exclusion list,
    /// because the filter now keys off APPLICATIONS.
    private var scopeExcludedSignature: String = ""
    private var scopeRefreshTimer: DispatchSourceTimer?
    private var scopeRefreshInFlight = false

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

    /// Capture a display showing ONLY the given windows, over the desktop picture.
    ///
    /// The inverse of `startDisplay`, and the piece that makes a synchronised desktop shader
    /// possible: the effect has to reach the wallpaper and RetroMac's own desktop windows while
    /// leaving every application window alone.
    ///
    /// Built by excluding every application and adding the named windows back — see
    /// `scopeFilter`. Anything not named here is out, this app's own other windows included,
    /// which is also what keeps the overlay from filming itself.
    func startDisplayIncludingOnly(_ displayID: CGDirectDisplayID,
                                   windowIDs: [CGWindowID],
                                   content: SCShareableContent? = nil) async throws {
        // Fetch the window list WITHOUT the desktop windows, and that is the whole point of this
        // call rather than reusing the caller's content. The desktop picture is itself a window;
        // in a list that includes it, "exclude everything I did not name" excludes the wallpaper
        // too and the capture comes back black. Asking for the list without desktop windows means
        // they are never candidates for exclusion, so the wallpaper always survives.
        _ = content
        let resolved = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let display = resolved.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }
        let keep = Set(windowIDs)
        let kept = resolved.windows.filter { keep.contains($0.windowID) }
        print("[Capture] Desktop scope on display \(displayID): asked to keep \(keep.count), found \(kept.count), of \(resolved.windows.count) window(s)")
        // Refuse rather than deliver a capture that is missing the very windows the caller asked
        // to keep. The overlay this feeds is OPAQUE and covers the dock and the desktop icons, so
        // a capture without them in it does not look like a wrong filter, it looks like the dock
        // and the icons have vanished.
        if !keep.isEmpty, kept.isEmpty {
            throw CaptureError.noDisplay
        }
        let filter = Self.scopeFilter(display: display, content: resolved, keeping: keep)
        scopeDisplayID = displayID
        scopeKeepIDs = keep
        scopeExcludedSignature = Self.scopeSignature(content: resolved, keeping: keep)

        let config = SCStreamConfiguration()
        let (w, h) = await captureSize(for: display)
        config.width = w
        config.height = h
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        config.queueDepth = targetFPS > 30 ? 5 : 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        try await startStream(filter: filter, config: config)
        startScopeRefresh()
    }

    /// Exclude every APPLICATION, then add back the handful of windows to keep.
    ///
    /// The first version excluded a list of windows instead, and a list of windows is a snapshot:
    /// a window that did not exist when it was built can never be in it, so every application
    /// window opened afterwards was captured. It then appeared inside the shaded desktop layer,
    /// where — sitting below the real window rather than under it — it showed as a second, offset,
    /// shaded copy of that window wherever the real one did not cover it exactly. Exposé, which
    /// lays a translucent backdrop over everything, made all of them visible at once.
    ///
    /// Applications are the stable key: a new window of an app that is already excluded is
    /// excluded with it, and only a newly LAUNCHED app needs the refresh below.
    private static func scopeFilter(display: SCDisplay, content: SCShareableContent,
                                    keeping keep: Set<CGWindowID>) -> SCContentFilter {
        SCContentFilter(display: display,
                        excludingApplications: content.applications,
                        exceptingWindows: content.windows.filter { keep.contains($0.windowID) })
    }

    /// What the filter depends on: which apps exist, and which of our windows are being kept.
    private static func scopeSignature(content: SCShareableContent, keeping keep: Set<CGWindowID>) -> String {
        let apps = content.applications.map { String($0.processID) }.sorted().joined(separator: ",")
        let kept = keep.map(String.init).sorted().joined(separator: ",")
        return apps + "|" + kept
    }

    /// Keep the filter in step with the applications and windows that actually exist.
    ///
    /// Once a second, not per frame: it costs a `SCShareableContent` fetch, and the stream is only
    /// touched when the set of ids has genuinely changed, so a quiet desktop costs one query and
    /// nothing else.
    private func startScopeRefresh() {
        scopeRefreshTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, !self.scopeRefreshInFlight else { return }
            self.scopeRefreshInFlight = true
            Task { [weak self] in
                await self?.refreshScopeFilter()
                self?.scopeRefreshInFlight = false
            }
        }
        timer.resume()
        scopeRefreshTimer = timer
    }

    private func refreshScopeFilter() async {
        guard let stream, let displayID = scopeDisplayID else { return }
        guard let resolved = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let display = resolved.displays.first(where: { $0.displayID == displayID })
        else { return }

        if let provider = scopeKeepProvider {
            scopeKeepIDs = Set(await MainActor.run { provider() })
        }
        let signature = Self.scopeSignature(content: resolved, keeping: scopeKeepIDs)
        guard signature != scopeExcludedSignature else { return }

        let filter = Self.scopeFilter(display: display, content: resolved, keeping: scopeKeepIDs)
        do {
            try await stream.updateContentFilter(filter)
            // Only once it is actually applied. Recording it before the await meant a single
            // transient failure stuck for good: the next tick compared against the state it had
            // already adopted, found no change, and never retried.
            scopeExcludedSignature = signature
            print("[Capture] Desktop scope filter refreshed")
        } catch {
            print("[Capture] Desktop scope filter refresh failed, will retry: \(error)")
        }
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
        captureScale = max(scale, 1)   // reused by OverlayWindowController.scheduleStreamResize
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

    /// A still of one window, for Exposé's thumbnails.
    ///
    /// `SCScreenshotManager` rather than the old `CGWindowListCreateImage`: that one is deprecated
    /// and has been progressively defanged, and we already hold the Screen Recording permission
    /// this needs. Returns nil rather than throwing — a window that refuses to be captured should
    /// cost one placeholder card, not the whole Exposé.
    /// `points` is how large the thumbnail will actually be drawn and `scale` the display's
    /// backing factor, so the capture comes back at exactly the pixels the card needs.
    static func captureThumbnail(_ window: SCWindow, points: NSSize, scale: CGFloat) async -> NSImage? {
        // Never ask for more than the window has; a card is never drawn larger than life size.
        let w = min(points.width, window.frame.width), h = min(points.height, window.frame.height)
        guard w > 1, h > 1 else { return nil }
        let cfg = SCStreamConfiguration()
        cfg.width  = max(1, Int((w * scale).rounded()))
        cfg.height = max(1, Int((h * scale).rounded()))
        cfg.showsCursor = false
        cfg.scalesToFit = true
        // .automatic is free to hand back a nominal-resolution frame, which on a Retina display
        // is half the pixels and looks exactly as soft as that sounds.
        cfg.captureResolution = .best
        do {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            // Sized in POINTS, not in its own pixel count. Passing the pixel count made a 2x
            // capture claim to be a 2x-larger 1x image, so AppKit resampled it down into the card
            // instead of mapping its pixels one to one onto the backing store.
            return NSImage(cgImage: img, size: NSSize(width: w, height: h))
        } catch {
            return nil
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
        scopeRefreshTimer?.cancel()
        scopeRefreshTimer = nil
        scopeDisplayID = nil
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
