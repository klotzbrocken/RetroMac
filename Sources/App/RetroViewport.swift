import AppKit
import Metal
import MetalKit
import ScreenCaptureKit
import CoreMedia
import CoreVideo

extension Notification.Name {
    static let retroViewportDidClose = Notification.Name("retroViewportDidClose")
}

/// A movable, resizable "retro lens" window that captures the screen region
/// underneath it and applies a CRT/retro shader effect in real-time.
///
/// Inspired by RetroVisor's EffectWindow — a freestanding viewport that
/// works like a magnifying glass with retro shader effects.
///
/// Usage:
///   let viewport = RetroViewport()
///   viewport.show(preset: "crt-lite")
///
/// The window can be dragged anywhere on screen. The content underneath
/// updates in real-time with the selected shader applied.
final class RetroViewport: NSObject, MTKViewDelegate, SCStreamOutput, SCStreamDelegate {

    // MARK: - Metal & Rendering

    private var device: MTLDevice?
    private var metalView: MTKView?
    private var renderer: RetroRenderer?
    private var bloomFilter: BloomFilter?
    private var textureCache: CVMetalTextureCache?

    // MARK: - Window

    private var window: RetroViewportWindow?
    private var currentTexture: MTLTexture?
    private let textureLock = NSLock()

    // MARK: - Capture

    private var stream: SCStream?
    private var displayID: CGDirectDisplayID = CGMainDisplayID()
    private var moveDebounceTimer: DispatchSourceTimer?

    // MARK: - State

    private(set) var isActive = false
    var presetName: String = "crt-royale-lite"
    var bloomEnabled: Bool = true
    var bloomIntensity: Float = 0.25

    /// Forwarded intensity — sets the shader intensity on the renderer.
    var intensity: Float {
        get { renderer?.intensity ?? 1.0 }
        set { renderer?.intensity = newValue }
    }

    /// Forwarded vignette intensity — sets the vignette on the renderer.
    var vignetteIntensity: Float {
        get { renderer?.vignetteIntensity ?? 0 }
        set { renderer?.vignetteIntensity = newValue }
    }

    // MARK: - Public API

    /// Show the viewport window with the given shader preset.
    func show(preset: String = "crt-royale-lite") {
        guard !isActive else {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        presetName = preset

        do {
            try setupMetal()
        } catch {
            print("[Viewport] Metal setup failed: \(error)")
            return
        }

        let frame = NSRect(x: 200, y: 200, width: 640, height: 480)
        createWindow(frame: frame)

        do {
            try renderer?.loadShader(named: presetName)
        } catch {
            print("[Viewport] Shader load failed: \(error)")
        }

        isActive = true
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Start capture after a brief delay to let the window appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startCapture()
        }

        print("[Viewport] Opened with preset: \(preset)")
    }

    /// Close the viewport window and stop capture.
    func hide() {
        guard isActive else { return }
        isActive = false

        moveDebounceTimer?.cancel()
        moveDebounceTimer = nil

        NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: window)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: window)

        stopCapture()

        metalView?.isPaused = true
        metalView?.delegate = nil

        window?.orderOut(nil)
        window = nil
        metalView = nil
        renderer = nil
        bloomFilter = nil
        device = nil

        print("[Viewport] Closed")
        NotificationCenter.default.post(name: .retroViewportDidClose, object: nil)
    }

    /// Switch the shader preset while the viewport is active.
    func switchPreset(_ name: String) {
        presetName = name
        do {
            try renderer?.loadShader(named: name)
        } catch {
            print("[Viewport] Shader switch failed: \(error)")
        }
    }

    // MARK: - Metal Setup

    private func setupMetal() throws {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            throw ViewportError.noMetalDevice
        }
        self.device = dev
        self.renderer = try RetroRenderer(device: dev)
        self.bloomFilter = try? BloomFilter(device: dev)
        bloomFilter?.intensity = bloomIntensity

        CVMetalTextureCacheCreate(nil, nil, dev, nil, &textureCache)
    }

    // MARK: - Window

    private func createWindow(frame: NSRect) {
        let mtkView = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 30
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.layer?.isOpaque = true
        mtkView.delegate = self

        let win = RetroViewportWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Retro Viewport"
        win.minSize = NSSize(width: 320, height: 240)
        win.contentView = mtkView
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.backgroundColor = .black
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true

        win.onClose = { [weak self] in
            self?.hide()
        }

        self.window = win
        self.metalView = mtkView

        // Track window move/resize via NotificationCenter (setFrame overrides don't fire during drag)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidMoveOrResize),
            name: NSWindow.didMoveNotification, object: win
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidMoveOrResize),
            name: NSWindow.didResizeNotification, object: win
        )
    }

    @objc private func windowDidMoveOrResize(_ notification: Notification) {
        handleWindowMoved()
    }

    // MARK: - Screen Capture

    private func startCapture() {
        Task {
            do {
                try await setupStream()
            } catch {
                print("[Viewport] Capture failed: \(error)")
            }
        }
    }

    private func setupStream() async throws {
        stopCapture()

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        // Find the display the viewport is on
        let windowCenter: CGPoint = await MainActor.run { self.window?.frame.midPoint ?? .zero }
        let screenInfo: (CGDirectDisplayID, CGFloat) = await MainActor.run {
            let scr = NSScreen.screens.first(where: { $0.frame.contains(windowCenter) }) ?? NSScreen.main!
            return (scr.displayID, scr.backingScaleFactor)
        }
        displayID = screenInfo.0
        let scale = screenInfo.1

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ViewportError.noDisplay
        }

        // Exclude our own window from capture
        let ownWindowID: CGWindowID = await MainActor.run { CGWindowID(self.window?.windowNumber ?? 0) }
        let ownWindows = content.windows.filter { $0.windowID == ownWindowID }

        let filter: SCContentFilter
        if !ownWindows.isEmpty {
            filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        } else {
            // Fallback: exclude by app
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let ownApps = content.applications.filter { $0.processID == ownPID }
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        }

        let config = SCStreamConfiguration()

        // Capture the region under the viewport window
        let sourceRect = await captureRect()

        config.sourceRect = sourceRect
        config.width = max(Int(sourceRect.width * scale), 200)
        config.height = max(Int(sourceRect.height * scale), 200)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream.startCapture()
        self.stream = stream

        // Unpause rendering
        await MainActor.run {
            self.metalView?.isPaused = false
        }

        print("[Viewport] Capture started: \(config.width)x\(config.height) from rect \(sourceRect)")
    }

    private func stopCapture() {
        let stoppingStream = stream
        stream = nil
        stoppingStream?.stopCapture { error in
            if let error = error {
                print("[Viewport] Stop error: \(error)")
            }
        }
    }

    /// Calculate the CG-coordinate rectangle of the viewport window content area.
    private func captureRect() async -> CGRect {
        await MainActor.run {
            guard let win = self.window, let screen = win.screen else {
                return CGRect(x: 200, y: 200, width: 640, height: 480)
            }
            // Convert window content rect from NS coordinates (bottom-left origin)
            // to CG coordinates (top-left origin)
            let contentFrame = win.contentLayoutRect
            let windowFrame = win.frame
            let contentOriginInScreen = NSPoint(
                x: windowFrame.origin.x + contentFrame.origin.x,
                y: windowFrame.origin.y + contentFrame.origin.y
            )
            let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
            let cgX = contentOriginInScreen.x
            let cgY = primaryHeight - contentOriginInScreen.y - contentFrame.height
            return CGRect(x: cgX, y: cgY, width: contentFrame.width, height: contentFrame.height)
        }
    }

    /// Called when the viewport window moves or resizes — update capture region.
    private func handleWindowMoved() {
        // Short debounce — frequent during drag, but we want responsive updates
        moveDebounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.updateCaptureRegion()
        }
        timer.resume()
        moveDebounceTimer = timer
    }

    private func updateCaptureRegion() {
        guard let stream = stream, isActive else { return }

        Task {
            let sourceRect = await captureRect()
            let scale: CGFloat = await MainActor.run {
                self.window?.screen?.backingScaleFactor ?? 2.0
            }

            let config = SCStreamConfiguration()
            config.sourceRect = sourceRect
            config.width = max(Int(sourceRect.width * scale), 200)
            config.height = max(Int(sourceRect.height * scale), 200)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.queueDepth = 3
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true

            do {
                try await stream.updateConfiguration(config)
                print("[Viewport] Region updated: \(config.width)x\(config.height)")
            } catch {
                print("[Viewport] Region update failed: \(error), restarting capture")
                try? await setupStream()
            }
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixelBuffer = sampleBuffer.imageBuffer, let textureCache = textureCache else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTex = cvTexture,
              let texture = CVMetalTextureGetTexture(cvTex) else { return }

        textureLock.lock()
        currentTexture = texture
        textureLock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[Viewport] Stream error: \(error)")
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        textureLock.lock()
        let texture = currentTexture
        textureLock.unlock()

        guard let texture = texture,
              let drawable = view.currentDrawable,
              let renderer = renderer else { return }

        let viewportSize = CGSize(width: view.drawableSize.width, height: view.drawableSize.height)
        renderer.render(sourceTexture: texture, to: drawable, viewportSize: viewportSize, opaque: true)
    }

    // MARK: - Errors

    enum ViewportError: Error, LocalizedError {
        case noMetalDevice
        case noDisplay
        var errorDescription: String? {
            switch self {
            case .noMetalDevice: return "No Metal GPU found"
            case .noDisplay: return "No display found for viewport"
            }
        }
    }
}

// MARK: - Custom Window

/// NSWindow subclass that reports close events.
final class RetroViewportWindow: NSWindow {
    var onClose: (() -> Void)?

    override func close() {
        onClose?()
    }
}

// MARK: - Helpers

private extension NSRect {
    var midPoint: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

// NSScreen.displayID is defined in AppDelegate.swift
