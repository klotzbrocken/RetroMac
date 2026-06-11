import AppKit
import AVKit
import MetalKit
import CoreVideo
import WebKit

final class TVBrowserWindow: NSObject {
    private var window: NSWindow?
    private var savedFrame: NSRect?   // non-nil while in manual full-screen
    private var mac9PreCollapseHeight: CGFloat?   // non-nil while Mac OS 9 WindowShade-collapsed
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

        let win = KeyableWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.backgroundColor = .black
        win.delegate = self
        win.level = NSWindow.Level(rawValue: 25)
        // Enable native full-screen (green button / ⌃⌘F). The CRT shader lives in the
        // window's MTKView content view (autoresizes to fill), so it carries into
        // full-screen too.
        win.collectionBehavior = [.fullScreenPrimary]

        // Hide centered title; show a theme-dependent title bar (general hook for our own
        // windows). BeOS → yellow Lasche chip; other themes → plain right-aligned name.
        win.titleVisibility = .hidden
        win.title = bookmark.name

        // Default theme: native right-aligned name. BeOS / Mac OS 9 get a borderless themed
        // frame applied AFTER the content view is set up (see applyBeOSChrome / applyMac9Chrome).
        if RetroFrameTheme.key() == "default" {
            let titleLabel = NSTextField(labelWithString: bookmark.name)
            titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
            titleLabel.textColor = .secondaryLabelColor
            titleLabel.alignment = .right
            let accessory = NSTitlebarAccessoryViewController()
            accessory.view = titleLabel
            accessory.layoutAttribute = .right
            win.addTitlebarAccessoryViewController(accessory)
        }

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

        // BeOS theme: wrap the content in a borderless window with a protruding yellow Lasche.
        applyBeOSChrome(win, title: bookmark.name)
        // Mac OS 9 theme: wrap the content in a borderless Platinum window.
        applyMac9Chrome(win, title: bookmark.name)
        // Windows XP theme: wrap the content in a borderless Luna window.
        applyWinXPChrome(win, title: bookmark.name)

        // Double-click the video toggles full-screen (keeps the CRT shader + float level).
        if let cv = win.contentView {
            let dbl = NSClickGestureRecognizer(target: self, action: #selector(toggleTVFullscreen))
            dbl.numberOfClicksRequired = 2
            dbl.delaysPrimaryMouseButtonEvents = false
            cv.addGestureRecognizer(dbl)
        }

        win.makeKeyAndOrderFront(nil)
        self.window = win
    }

    /// BeOS theme: convert the TV window to a borderless window with a protruding yellow
    /// Lasche (drag to move, click the box to close); the content sits below the tab.
    private func applyBeOSChrome(_ win: NSWindow, title: String) {
        guard RetroFrameTheme.key() == "beos", let content = win.contentView else { return }
        let tab = BeOSTVChromeView.tabH
        let size = win.frame.size
        win.styleMask = [.borderless, .resizable]
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        content.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height - tab)
        content.autoresizingMask = [.width, .height]
        let chrome = BeOSTVChromeView(frame: NSRect(origin: .zero, size: size))
        chrome.wantsLayer = true
        chrome.title = title
        chrome.onClose = { [weak self] in self?.window?.close() }
        chrome.addSubview(content)
        win.contentView = chrome
    }

    /// Mac OS 9 theme: borderless Platinum window — pinstripe title bar with close box left
    /// and collapse (WindowShade) + zoom boxes right; content below.
    private func applyMac9Chrome(_ win: NSWindow, title: String) {
        guard RetroFrameTheme.key() == "macos9", let content = win.contentView else { return }
        let bar = Mac9TVChromeView.barH
        let size = win.frame.size
        win.styleMask = [.borderless, .resizable]
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        content.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height - bar)
        content.autoresizingMask = [.width, .height]
        let chrome = Mac9TVChromeView(frame: NSRect(origin: .zero, size: size))
        chrome.wantsLayer = true
        chrome.title = title
        chrome.onClose = { [weak self] in self?.window?.close() }
        chrome.onCollapse = { [weak self] in self?.toggleMac9Collapse() }
        chrome.onZoom = { [weak self] in self?.toggleTVFullscreen() }
        chrome.addSubview(content)
        win.contentView = chrome
    }

    /// Windows XP theme: borderless Luna window — gradient title bar with system icon left
    /// and minimise / maximise / close caption buttons right; content inset by the 4px frame.
    private func applyWinXPChrome(_ win: NSWindow, title: String) {
        guard RetroFrameTheme.key() == "winxp", let content = win.contentView else { return }
        let bar = WinXPTVChromeView.barH, b = WinXPTVChromeView.border
        let size = win.frame.size
        win.styleMask = [.borderless, .resizable]
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        content.frame = NSRect(x: b, y: b, width: size.width - 2 * b, height: size.height - bar - b)
        content.autoresizingMask = [.width, .height]
        let chrome = WinXPTVChromeView(frame: NSRect(origin: .zero, size: size))
        chrome.wantsLayer = true
        chrome.title = title
        chrome.onClose = { [weak self] in self?.window?.close() }
        chrome.onMin = { [weak self] in self?.toggleMac9Collapse() }   // roll up (no taskbar for the float window)
        chrome.onMax = { [weak self] in self?.toggleTVFullscreen() }
        chrome.addSubview(content)
        win.contentView = chrome
    }

    /// Mac OS 9 WindowShade: roll the TV window up to just the title bar, or restore.
    private func toggleMac9Collapse() {
        guard let win = window else { return }
        let bar = Mac9TVChromeView.barH
        if let h = mac9PreCollapseHeight {
            var f = win.frame; let top = f.maxY; f.size.height = h; f.origin.y = top - h
            win.setFrame(f, display: true, animate: true)
            mac9PreCollapseHeight = nil
        } else {
            mac9PreCollapseHeight = win.frame.height
            var f = win.frame; let top = f.maxY; f.size.height = bar; f.origin.y = top - bar
            win.setFrame(f, display: true, animate: true)
        }
    }

    /// Manual full-screen: fill the current screen and hide the title bar, keeping the
    /// window's MTKView (CRT shader) as content. Reversible. Used instead of native
    /// full-screen because the TV window floats at an elevated level.
    @objc private func toggleTVFullscreen() {
        guard let win = window, let screen = win.screen ?? NSScreen.main else { return }
        if savedFrame == nil {
            savedFrame = win.frame
            win.styleMask.insert(.fullSizeContentView)
            win.titlebarAppearsTransparent = true
            win.standardWindowButton(.closeButton)?.superview?.isHidden = true
            win.setFrame(screen.frame, display: true, animate: true)
        } else {
            win.standardWindowButton(.closeButton)?.superview?.isHidden = false
            win.titlebarAppearsTransparent = false
            win.styleMask.remove(.fullSizeContentView)
            if let f = savedFrame { win.setFrame(f, display: true, animate: true) }
            savedFrame = nil
        }
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

        // Web bookmarks can't run the real Metal CRT shader (no pixel-buffer stream like
        // AVPlayer), so give them a lightweight scanline + vignette OVERLAY for a retro look.
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(wv)
        let overlay = CRTWebOverlay(frame: NSRect(origin: .zero, size: size))
        overlay.autoresizingMask = [.width, .height]
        container.addSubview(overlay)
        window.contentView = container

        self.webView = wv
        self.contentMode = .webContent
        print("[TV] Web content (CRT overlay): \(url.absoluteString)")
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

/// Lightweight CRT look for web bookmarks: horizontal scanlines + edge vignette, drawn over
/// the WKWebView. Click-through (hitTest returns nil) so the page stays interactive. This is
/// NOT the full Metal shader (web content has no pixel-buffer stream) — just a tasteful overlay.
final class CRTWebOverlay: NSView {
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // pass all clicks through

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds
        let intensity = max(0, min(1, CGFloat(AppSettings.shared.defaultIntensity)))
        let vig = max(0, min(1, CGFloat(AppSettings.shared.vignetteIntensity)))

        // Scanlines: a 1pt dark line every 3pt, alpha scaled by intensity.
        let lineAlpha = 0.10 + 0.18 * intensity
        NSColor.black.withAlphaComponent(lineAlpha).setFill()
        var y = b.minY
        while y < b.maxY {
            ctx.fill(CGRect(x: b.minX, y: y, width: b.width, height: 1))
            y += 3
        }

        // Vignette: radial darkening toward the corners.
        if vig > 0.01 {
            let colors = [NSColor.clear.cgColor,
                          NSColor.black.withAlphaComponent(0.55 * vig).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0.55, 1.0]) {
                let center = CGPoint(x: b.midX, y: b.midY)
                let radius = max(b.width, b.height) * 0.72
                ctx.drawRadialGradient(grad, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: radius,
                                       options: [.drawsAfterEndLocation])
            }
        }
    }
}
