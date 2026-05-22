import AppKit
import WebKit
import AVKit
import MetalKit
import CoreVideo

/// NSImageView that passes all mouse events through to views behind it.
final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
    override var acceptsFirstResponder: Bool { false }
}

final class TVBrowserWindow: NSObject {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var player: AVPlayer?
    private var playerView: AVPlayerView?
    private var dockWasRunning = false

    // CRT shader overlay (rendered image on top of WKWebView)
    private var overlayImageView: PassthroughImageView?
    private var metalDevice: MTLDevice?
    private var renderer: RetroRenderer?
    private var activePresetID: String?

    // Stream mode: AVPlayerItemVideoOutput feeds frames via MTKView
    private var metalView: MTKView?
    private var textureCache: CVMetalTextureCache?
    private var videoOutput: AVPlayerItemVideoOutput?

    // Web mode: periodic snapshots → renderToImage → overlay
    private var snapshotTimer: Timer?
    private var snapshotCount = 0

    // Save/restore global overlay state when TV is open
    private var savedGlobalPreset: String?
    private var savedGlobalWasActive = false

    private enum ContentMode {
        case streamDirect      // Stream with CRT shader (AVPlayer → Metal)
        case streamBasic       // Stream without shader (AVPlayerView)
        case webDirect         // Web with CRT shader (WKWebView visible + overlay)
        case webBasic          // Web without shader (WKWebView only)
    }
    private var contentMode: ContentMode = .webBasic
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

        let isStream = url.pathExtension == "m3u8" ||
                       url.absoluteString.contains(".m3u8") ||
                       url.absoluteString.contains(".m3u") ||
                       url.absoluteString.contains(".mp4") ||
                       url.absoluteString.contains(".ts")

        // Determine effective preset: bookmark-specific > active global preset > app default.
        // TV is a shader experience — always apply a CRT effect. "None" only if user
        // explicitly sets bookmark.presetID to empty string.
        // IMPORTANT: Resolve this BEFORE stopping the global overlay.
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
            savedGlobalPreset = appDel.currentPresetName
            savedGlobalWasActive = true
            appDel.disableAll()
            print("[TV] Stopped global overlay (was '\(savedGlobalPreset ?? "nil")')")
        }

        print("[TV] Opening '\(bookmark.name)' isStream=\(isStream) effectivePreset=\(effectivePresetID ?? "none")")

        if isStream, let presetID = effectivePresetID {
            setupStreamWithShader(url: url, presetID: presetID, size: size, window: win)
        } else if isStream {
            setupStreamBasic(url: url, size: size, window: win)
        } else if let presetID = effectivePresetID {
            setupWebWithShader(url: url, presetID: presetID, size: size, window: win)
        } else {
            setupWebBasic(url: url, size: size, window: win)
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
        print("[TV] Stream basic: \(url.absoluteString)")
    }

    // MARK: - Web with CRT Shader (WKWebView visible + image overlay)

    private func setupWebWithShader(url: URL, presetID: String, size: NSSize, window: NSWindow) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[TV] No Metal device — falling back to basic web")
            setupWebBasic(url: url, size: size, window: window)
            return
        }
        do {
            let r = try RetroRenderer(device: device)
            try r.loadShader(named: presetID)
            r.intensity = AppSettings.shared.defaultIntensity
            r.vignetteIntensity = AppSettings.shared.vignetteIntensity
            self.renderer = r
        } catch {
            print("[TV] Shader load failed: \(error) — falling back to basic web")
            setupWebBasic(url: url, size: size, window: window)
            return
        }

        self.metalDevice = device
        self.activePresetID = presetID
        self.contentMode = .webDirect

        // Container view holds WKWebView + CRT overlay
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]

        // WKWebView is the interactive content — visible and clickable
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "fullScreenEnabled")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let wv = WKWebView(frame: container.bounds, configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        container.addSubview(wv)
        self.webView = wv

        // CRT overlay on top — shows shader-processed snapshot, passes clicks through
        let overlay = PassthroughImageView(frame: container.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.imageScaling = .scaleAxesIndependently
        overlay.wantsLayer = true
        overlay.layer?.zPosition = 1000  // stay above WKWebView's layer management
        container.addSubview(overlay)
        self.overlayImageView = overlay

        window.contentView = container
        wv.load(URLRequest(url: url))

        // Start periodic snapshot → shader → overlay cycle
        startSnapshotTimer()
        print("[TV] Web with CRT shader '\(presetID)': \(url.absoluteString)")
    }

    // MARK: - Web Basic (WKWebView)

    private func setupWebBasic(url: URL, size: NSSize, window: NSWindow) {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "fullScreenEnabled")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let wv = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        window.contentView = wv
        wv.load(URLRequest(url: url))
        self.webView = wv
        self.contentMode = .webBasic
        print("[TV] Web basic: \(url.absoluteString)")
    }

    // MARK: - Snapshot Timer (Web CRT mode)

    private func startSnapshotTimer() {
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            self?.captureAndRenderSnapshot()
        }
    }

    private func stopSnapshotTimer() {
        snapshotTimer?.invalidate()
        snapshotTimer = nil
    }

    /// Capture WKWebView snapshot → process through CRT shader → display as overlay image
    private func captureAndRenderSnapshot() {
        guard let wv = webView, let renderer = renderer, let device = metalDevice else { return }

        let snapshotConfig = WKSnapshotConfiguration()
        snapshotConfig.rect = wv.bounds

        wv.takeSnapshot(with: snapshotConfig) { [weak self] image, error in
            guard let self = self else { return }
            self.snapshotCount += 1
            if let error = error {
                if self.snapshotCount <= 3 { print("[TV] Snapshot error: \(error.localizedDescription)") }
                return
            }
            guard let image = image else { return }
            if self.snapshotCount <= 3 { print("[TV] Snapshot #\(self.snapshotCount): \(image.size)") }

            // Convert snapshot to Metal texture
            guard let texture = self.textureFromImage(image, device: device) else { return }

            // Render CRT effect to NSImage via GPU
            let viewportSize = CGSize(width: texture.width, height: texture.height)
            guard let rendered = renderer.renderToImage(sourceTexture: texture, viewportSize: viewportSize) else {
                if self.snapshotCount <= 3 { print("[TV] renderToImage failed") }
                return
            }

            // Update the overlay on the main thread
            DispatchQueue.main.async {
                self.overlayImageView?.image = rendered
            }
        }
    }

    private func textureFromImage(_ image: NSImage, device: MTLDevice) -> MTLTexture? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(origin: .zero, size: CGSize(width: width, height: height)))
        guard let data = context.data else { return nil }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: bytesPerRow
        )
        return texture
    }

    // MARK: - Cleanup

    func close() {
        stopSnapshotTimer()
        overlayImageView?.image = nil
        overlayImageView = nil

        metalView?.isPaused = true
        metalView = nil
        renderer = nil
        videoOutput = nil
        textureCache = nil
        metalDevice = nil
        activePresetID = nil
        drawCallCount = 0
        snapshotCount = 0

        player?.pause()
        player = nil
        playerView = nil

        webView?.stopLoading()
        webView?.uiDelegate = nil
        webView?.navigationDelegate = nil
        webView = nil

        window?.close()
        window = nil
        contentMode = .webBasic
    }
}

// MARK: - MTKViewDelegate (Stream CRT Rendering)

extension TVBrowserWindow: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        drawCallCount += 1
        guard let renderer = renderer,
              let drawable = view.currentDrawable else { return }

        if contentMode == .streamDirect {
            drawStreamFrame(renderer: renderer, drawable: drawable, viewportSize: view.drawableSize)
        }
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
        stopSnapshotTimer()
        overlayImageView?.image = nil
        overlayImageView = nil
        metalView?.isPaused = true
        metalView = nil
        renderer = nil
        videoOutput = nil
        textureCache = nil

        player?.pause()
        player = nil
        playerView = nil

        webView?.stopLoading()
        webView?.uiDelegate = nil
        webView?.navigationDelegate = nil
        webView = nil
        window = nil
        print("[TV] Window closed")

        if dockWasRunning {
            DockController.shared.start()
            dockWasRunning = false
        }

        // Restore global overlay if it was active before TV opened
        if savedGlobalWasActive, let preset = savedGlobalPreset {
            print("[TV] Restoring global overlay '\(preset)'")
            if let appDel = NSApp.delegate as? AppDelegate {
                appDel.currentPresetName = preset
                appDel.toggleOverlay()
            }
            savedGlobalWasActive = false
            savedGlobalPreset = nil
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

// MARK: - WKNavigationDelegate

extension TVBrowserWindow: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[TV] Navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[TV] Provisional navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate

extension TVBrowserWindow: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
            print("[TV] Redirected popup/blank link: \(url.absoluteString)")
        }
        return nil
    }
}
