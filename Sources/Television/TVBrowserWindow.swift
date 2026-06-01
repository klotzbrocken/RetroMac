import AppKit
import AVKit
import MetalKit
import CoreVideo
import WebKit

final class TVBrowserWindow: NSObject {
    private var window: NSWindow?
    private var player: AVPlayer?
    private var playerView: AVPlayerView?
    private var webView: WKWebView?
    private var dockWasRunning = false

    // CRT shader
    private var metalDevice: MTLDevice?
    private var renderer: RetroRenderer?
    private var activePresetID: String?

    // Stream mode: AVPlayerItemVideoOutput feeds frames via MTKView
    private var metalView: MTKView?
    private var textureCache: CVMetalTextureCache?
    private var videoOutput: AVPlayerItemVideoOutput?

    // Aspect ratio lock: set once from stream's native resolution
    private var aspectRatioLocked = false
    private var presentationSizeObserver: NSKeyValueObservation?

    private enum ContentMode {
        case streamDirect      // Stream with CRT shader (AVPlayer → Metal)
        case streamBasic       // Stream without shader (AVPlayerView)
        case webContent        // Web page via WKWebView
    }
    private var contentMode: ContentMode = .streamBasic
    private var drawCallCount = 0

    func open(bookmark: TVBookmark) {
        close()

        guard let url = URL(string: bookmark.url) else { return }

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let size = NSSize(width: min(960, screen.frame.width * 0.6),
                          height: min(640, screen.frame.height * 0.6))
        let origin = NSPoint(x: screen.frame.midX - size.width / 2,
                             y: screen.frame.midY - size.height / 2)
        let contentRect = NSRect(origin: origin, size: size)

        let win = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.backgroundColor = .black
        win.delegate = self
        win.level = NSWindow.Level(rawValue: 25)

        // Hide centered title, show name right-aligned
        win.titleVisibility = .hidden
        win.title = bookmark.name

        let titleLabel = NSTextField(labelWithString: bookmark.name)
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .right

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = titleLabel
        accessory.layoutAttribute = .right
        win.addTitlebarAccessoryViewController(accessory)

        // Determine effective preset: bookmark-specific > active global preset > app default.
        let effectivePresetID: String?
        if let bookmarkPreset = bookmark.presetID {
            effectivePresetID = bookmarkPreset.isEmpty ? nil : bookmarkPreset
        } else if let appDel = NSApp.delegate as? AppDelegate, appDel.isActive,
                  let globalPreset = appDel.currentPresetName {
            effectivePresetID = globalPreset
        } else {
            effectivePresetID = AppSettings.shared.defaultPreset
        }

        // Stop the global overlay — TV renders its own CRT effect inside the window.
        if let appDel = NSApp.delegate as? AppDelegate, appDel.isActive {
            appDel.saveOverlayState()
            appDel.disableAll()
            print("[TV] Stopped global overlay (was '\(appDel.savedPreset ?? "nil")')")
        }

        print("[TV] Opening '\(bookmark.name)' effectivePreset=\(effectivePresetID ?? "none")")

        if Self.isStreamURL(url) {
            // Stream URL — use AVPlayer (with optional CRT shader)
            if let presetID = effectivePresetID {
                setupStreamWithShader(url: url, presetID: presetID, size: size, window: win)
            } else {
                setupStreamBasic(url: url, size: size, window: win)
            }
        } else {
            // Web URL — render with WKWebView
            setupWebView(url: url, size: size, window: win)
        }

        win.makeKeyAndOrderFront(nil)
        self.window = win
    }

    // MARK: - Stream with CRT Shader (AVPlayer → VideoOutput → Metal)

    private func setupStreamWithShader(url: URL, presetID: String, size: NSSize, window: NSWindow) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[TV] No Metal device — falling back to basic player")
            setupStreamBasic(url: url, size: size, window: window)
            return
        }
        do {
            let r = try RetroRenderer(device: device)
            try r.loadShader(named: presetID)
            r.intensity = AppSettings.shared.defaultIntensity
            r.vignetteIntensity = AppSettings.shared.vignetteIntensity
            self.renderer = r
        } catch {
            print("[TV] Shader load failed: \(error) — falling back to basic player")
            setupStreamBasic(url: url, size: size, window: window)
            return
        }

        self.metalDevice = device
        self.activePresetID = presetID
        self.contentMode = .streamDirect

        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)

        let mv = MTKView(frame: NSRect(origin: .zero, size: size), device: device)
        mv.autoresizingMask = [.width, .height]
        mv.colorPixelFormat = .bgra8Unorm
        mv.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mv.layer?.isOpaque = true
        mv.isPaused = false
        mv.enableSetNeedsDisplay = false
        mv.preferredFramesPerSecond = 30
        mv.delegate = self
        window.contentView = mv
        self.metalView = mv

        let avPlayer = AVPlayer(url: url)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let videoOut = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        avPlayer.currentItem?.add(videoOut)
        self.videoOutput = videoOut
        self.player = avPlayer
        avPlayer.play()
        print("[TV] Stream with CRT shader '\(presetID)': \(url.absoluteString)")
    }

    // MARK: - Stream Basic (AVPlayerView)

    private func setupStreamBasic(url: URL, size: NSSize, window: NSWindow) {
        let avPlayer = AVPlayer(url: url)
        let pv = AVPlayerView(frame: NSRect(origin: .zero, size: size))
        pv.autoresizingMask = [.width, .height]
        pv.player = avPlayer
        pv.controlsStyle = .floating
        pv.showsFullScreenToggleButton = true
        window.contentView = pv
        avPlayer.play()
        self.player = avPlayer
        self.playerView = pv
        self.contentMode = .streamBasic
        observePresentationSize(item: avPlayer.currentItem, window: window)
        print("[TV] Stream basic: \(url.absoluteString)")
    }

    // MARK: - URL Classification

    private static func isStreamURL(_ url: URL) -> Bool {
        let streamExtensions: Set<String> = ["m3u8", "m3u", "mp4", "mov", "ts", "mp3", "aac", "flac", "wav", "avi", "mkv"]
        if streamExtensions.contains(url.pathExtension.lowercased()) { return true }
        if let scheme = url.scheme?.lowercased(), ["rtsp", "rtmp", "mms"].contains(scheme) { return true }
        return false
    }

    // MARK: - Web Content (WKWebView)

    private func setupWebView(url: URL, size: NSSize, window: NSWindow) {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        let wv = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.load(URLRequest(url: url))
        window.contentView = wv
        self.webView = wv
        self.contentMode = .webContent
        print("[TV] Web content: \(url.absoluteString)")
    }

    // MARK: - Aspect Ratio

    private func observePresentationSize(item: AVPlayerItem?, window: NSWindow) {
        guard let item = item else { return }
        presentationSizeObserver = item.observe(\.presentationSize, options: [.new]) { [weak self] item, _ in
            guard let self = self, !self.aspectRatioLocked else { return }
            let size = item.presentationSize
            guard size.width > 0 && size.height > 0 else { return }
            self.aspectRatioLocked = true
            DispatchQueue.main.async {
                self.window?.contentAspectRatio = NSSize(width: size.width, height: size.height)
            }
        }
    }

    // MARK: - Cleanup

    /// Shared resource teardown — safe to call multiple times (idempotent).
    private func cleanupResources() {
        metalView?.isPaused = true
        metalView = nil
        renderer = nil
        videoOutput = nil
        textureCache = nil
        metalDevice = nil
        activePresetID = nil
        drawCallCount = 0

        presentationSizeObserver?.invalidate()
        presentationSizeObserver = nil
        aspectRatioLocked = false

        player?.pause()
        player = nil
        playerView = nil
        webView = nil
        contentMode = .streamBasic
    }

    func close() {
        let win = window
        window = nil
        cleanupResources()
        win?.close()
    }
}

// MARK: - MTKViewDelegate (Stream CRT Rendering)

extension TVBrowserWindow: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        drawCallCount += 1
        guard let renderer = renderer,
              let drawable = view.currentDrawable,
              contentMode == .streamDirect else { return }
        drawStreamFrame(renderer: renderer, drawable: drawable, viewportSize: view.drawableSize)
    }

    private func drawStreamFrame(renderer: RetroRenderer, drawable: CAMetalDrawable, viewportSize: CGSize) {
        guard let videoOutput = videoOutput,
              let textureCache = textureCache else { return }

        let currentTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
        guard videoOutput.hasNewPixelBuffer(forItemTime: currentTime),
              let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else {
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        if !aspectRatioLocked && width > 0 && height > 0 {
            aspectRatioLocked = true
            let ratio = NSSize(width: width, height: height)
            DispatchQueue.main.async { [weak self] in
                self?.window?.contentAspectRatio = ratio
            }
        }

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTexture
        )
        guard status == kCVReturnSuccess,
              let cvTex = cvTexture,
              let texture = CVMetalTextureGetTexture(cvTex) else { return }

        renderer.render(sourceTexture: texture, to: drawable, viewportSize: viewportSize, opaque: true)
    }
}

// MARK: - NSWindowDelegate

extension TVBrowserWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
        cleanupResources()
        print("[TV] Window closed")

        if dockWasRunning {
            DockController.shared.start()
            dockWasRunning = false
        }

        // Restore global overlay if it was active before TV opened
        if let appDel = NSApp.delegate as? AppDelegate {
            appDel.restorePreviousOverlay()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }

    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        return [.autoHideMenuBar, .autoHideDock, .fullScreen]
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        print("[TV] Entering fullscreen")
        if AppSettings.shared.dockEnabled {
            dockWasRunning = true
            DockController.shared.stop()
        }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        print("[TV] Exited fullscreen")
        if dockWasRunning {
            DockController.shared.start()
            dockWasRunning = false
        }
    }
}
