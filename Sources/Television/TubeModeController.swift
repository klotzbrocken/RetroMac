import AppKit
import AVFoundation
import MetalKit

/// "Tube Mode": the flyout's one-click retro TV. Plays the user's TV streams inside a
/// photoreal TV bezel with a CRT shader (default joel-gdv-ntsc) — fullscreen on the
/// first external display if one is connected, else on the main screen. Arrow keys zap
/// through the channels (tvBookmarks), ESC turns it off, double-click toggles between
/// fullscreen and a freely movable/resizable borderless window.
final class TubeModeController: NSObject, MTKViewDelegate {

    static let shared = TubeModeController()
    private override init() { super.init() }

    private(set) var isActive = false

    private var window: TubeWindow?
    private var contentView: TubeContentView?
    private var metalView: MTKView?
    private var renderer: RetroRenderer?
    private var textureCache: CVMetalTextureCache?
    private var player: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var channelIndex = 0
    private var savedWindowFrame: NSRect?      // last non-fullscreen frame
    private var isFullscreen = false

    // MARK: - Public

    func toggle() { isActive ? stop() : start() }

    func start() {
        guard !isActive else { return }
        let screen = targetScreen()
        // Start WINDOWED: a floating TV set (scene cropped to the device); double-click
        // goes fullscreen with the whole scene.
        let startW = min(920, screen.visibleFrame.width * 0.45)
        let startFrame = NSRect(x: screen.visibleFrame.midX - startW / 2,
                                y: screen.visibleFrame.midY - startW * 0.42,
                                width: startW, height: startW * 0.84)
        let win = TubeWindow(contentRect: startFrame, styleMask: [.borderless, .resizable],
                             backing: .buffered, defer: false)
        win.level = .normal
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.collectionBehavior = [.fullScreenAuxiliary, .managed]
        win.isMovableByWindowBackground = true
        win.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        win.onDoubleClick = { [weak self] in self?.toggleFullscreen() }

        let content = TubeContentView(frame: NSRect(origin: .zero, size: startFrame.size))
        content.autoresizingMask = [.width, .height]
        win.contentView = content
        contentView = content
        window = win
        isFullscreen = false

        loadBezel()
        setupPlayerPipeline(in: content)
        startChannel(resolveStartIndex())

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        isActive = true
        NotificationCenter.default.post(name: .tubeModeChanged, object: nil)
        print("[Tube] ON — screen \(screen.localizedName), windowed")
    }

    func stop() {
        guard isActive else { return }
        player?.pause()
        player = nil
        videoOutput = nil
        metalView?.isPaused = true
        metalView?.delegate = nil
        metalView = nil
        renderer = nil
        window?.orderOut(nil)
        window = nil
        contentView = nil
        savedWindowFrame = nil
        isActive = false
        NotificationCenter.default.post(name: .tubeModeChanged, object: nil)
        print("[Tube] OFF")
    }

    // MARK: - Screen / fullscreen

    /// First external screen (≠ main), the configured one if set, else the main screen.
    private func targetScreen() -> NSScreen {
        let configured = AppSettings.shared.tvTubeDisplayID
        if configured != 0, let s = NSScreen.screens.first(where: { $0.displayID == configured }) { return s }
        if let external = NSScreen.screens.first(where: { $0 != NSScreen.main }) { return external }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func toggleFullscreen() {
        guard let win = window, let content = contentView else { return }
        let screen = win.screen ?? targetScreen()
        if isFullscreen {
            let saved = savedWindowFrame ?? NSRect(x: screen.frame.midX - 460, y: screen.frame.midY - 386,
                                                   width: 920, height: 772)
            isFullscreen = false
            content.windowed = true                     // TV-only crop, transparent around it
            win.isOpaque = false; win.backgroundColor = .clear
            win.setFrame(saved, display: true, animate: true)
        } else {
            savedWindowFrame = win.frame
            isFullscreen = true
            content.windowed = false                    // whole scene, letterboxed
            win.isOpaque = true; win.backgroundColor = .black
            win.setFrame(screen.frame, display: true, animate: true)
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: stop(); return true                        // ESC
        case 126: switchChannel(by: 1); return true         // ↑
        case 125: switchChannel(by: -1); return true        // ↓
        default: return false
        }
    }

    // MARK: - Bezel

    private func loadBezel() {
        guard let content = contentView else { return }
        let store = BezelStore.shared
        // Fullscreen scene: the downloaded Soqueroeu bezel (else drawn fallback).
        if let bezel = store.bezel(named: AppSettings.shared.tvTubeBezel),
           store.isDownloaded(bezel),
           let img = NSImage(contentsOf: store.localURL(for: bezel)) {
            content.setScene(image: img, tubeRect: bezel.rect)
        } else {
            content.setScene(image: nil, tubeRect: [0.09, 0.10, 0.82, 0.72])
        }
        // Windowed mode: Maik's own free-standing TV set (bundled), measured rects.
        if let url = Bundle.main.resourceURL?.appendingPathComponent("TV/window-tv.png"),
           let tv = NSImage(contentsOf: url) {
            content.setWindowTV(image: tv,
                                tubeRect: [0.2409, 0.0903, 0.5182, 0.6644],
                                deviceRect: [0.2227, 0.0255, 0.5612, 0.9352])
        } else {
            content.setWindowTV(image: nil,
                                tubeRect: [0.09, 0.10, 0.82, 0.72],
                                deviceRect: [0, 0, 1, 1])
        }
        // Windowed: the window keeps the TV set's own aspect while resizing.
        if !isFullscreen, let win = window {
            let aspect = content.windowAspect
            win.contentAspectRatio = NSSize(width: aspect, height: 1)
            var f = win.frame
            f.size.height = f.width / aspect
            win.setFrame(f, display: true)
        }
    }

    /// Re-apply bezel + shader while running (Settings changes).
    func refreshAppearance() {
        guard isActive else { return }
        loadBezel()
        try? renderer?.loadShader(named: AppSettings.shared.tvTubePreset)
    }

    // MARK: - Player + shader pipeline (same pattern as TVBrowserWindow.streamDirect)

    private func setupPlayerPipeline(in content: TubeContentView) {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        do {
            let r = try RetroRenderer(device: device)
            try r.loadShader(named: AppSettings.shared.tvTubePreset)
            r.intensity = AppSettings.shared.defaultIntensity
            r.vignetteIntensity = AppSettings.shared.vignetteIntensity
            renderer = r
        } catch {
            print("[Tube] Shader load failed: \(error)")
            return
        }
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        let mv = MTKView(frame: .zero, device: device)
        mv.colorPixelFormat = .bgra8Unorm
        mv.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mv.isPaused = false
        mv.enableSetNeedsDisplay = false
        mv.preferredFramesPerSecond = 30
        mv.delegate = self
        content.installVideoView(mv)
        metalView = mv
    }

    private func resolveStartIndex() -> Int {
        let books = AppSettings.shared.tvBookmarks
        if let idx = books.firstIndex(where: { $0.url == AppSettings.shared.tvLastBookmarkURL }) { return idx }
        return 0
    }

    private func switchChannel(by delta: Int) {
        let count = AppSettings.shared.tvBookmarks.count
        guard count > 0 else { return }
        startChannel((channelIndex + delta + count) % count)
    }

    private func startChannel(_ index: Int) {
        let books = AppSettings.shared.tvBookmarks
        guard !books.isEmpty else {
            contentView?.showHint("No TV streams — add some in Settings ▸ Television")
            return
        }
        channelIndex = min(max(index, 0), books.count - 1)
        let bookmark = books[channelIndex]
        guard let url = URL(string: bookmark.url) else { return }

        player?.pause()
        let avPlayer = AVPlayer(url: url)
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        avPlayer.currentItem?.add(out)
        videoOutput = out
        player = avPlayer
        avPlayer.play()
        AppSettings.shared.tvLastBookmarkURL = bookmark.url
        contentView?.showHint(nil)
        print("[Tube] CH \(channelIndex + 1): \(bookmark.name)")
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let renderer = renderer,
              let drawable = view.currentDrawable,
              let videoOutput = videoOutput,
              let textureCache = textureCache else { return }
        let t = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
        guard videoOutput.hasNewPixelBuffer(forItemTime: t),
              let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) else { return }
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0, &cvTexture)
        guard status == kCVReturnSuccess, let cvTex = cvTexture,
              let texture = CVMetalTextureGetTexture(cvTex) else { return }
        renderer.render(sourceTexture: texture, to: drawable, viewportSize: view.drawableSize, opaque: true)
    }
}

// MARK: - Window (borderless, key-capable, ESC/arrows/double-click)

private final class TubeWindow: NSWindow {
    var onKey: ((NSEvent) -> Bool)?
    var onDoubleClick: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() }
        super.mouseUp(with: event)
    }
}

// MARK: - Content view (letterboxed bezel + video positioned in the tube region)

private final class TubeContentView: NSView {
    private let bezelLayer = CALayer()
    private var videoView: MTKView?
    private var hintLabel: NSTextField?
    // Fullscreen: the Soqueroeu scene bezel. Windowed: the dedicated TV-set image
    // (Resources/TV/window-tv.png). All rects top-left relative to their own image.
    private var sceneContents: Any?
    private var sceneTube: [Double] = [0.09, 0.10, 0.82, 0.72]
    private var tvContents: Any?
    private var tvTube: [Double] = [0.2409, 0.0903, 0.5182, 0.6644]
    private var tvDevice: [Double] = [0.2227, 0.0255, 0.5612, 0.9352]
    /// true = floating TV set, false = fullscreen whole scene.
    var windowed = true { didSet { needsLayout = true } }
    /// Aspect the window should keep while resizing (TV-set bbox of the window image).
    var windowAspect: CGFloat { CGFloat((tvDevice[2] * 16.0) / (tvDevice[3] * 9.0)) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        bezelLayer.contentsGravity = .resize
        bezelLayer.zPosition = 1                      // bezel BELOW the video: the PNGs are
        layer?.addSublayer(bezelLayer)                // opaque, the video sits in the tube region
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func installVideoView(_ mv: MTKView) {
        videoView?.removeFromSuperview()
        videoView = mv
        addSubview(mv)
        mv.layer?.zPosition = 5   // above the (opaque) bezel image
        needsLayout = true
    }

    /// Fullscreen scene bezel (nil image → drawn fallback frame).
    func setScene(image: NSImage?, tubeRect: [Double]) {
        sceneTube = tubeRect
        // CALayer.contents needs layerContents()/CGImage — assigning a raw NSImage
        // silently renders nothing on macOS.
        let img = image ?? drawnFallbackBezel()
        sceneContents = img.layerContents(forContentsScale: window?.backingScaleFactor ?? 2)
        needsLayout = true
    }

    /// Windowed TV-set image (Maik's own cover PNG with transparency).
    func setWindowTV(image: NSImage?, tubeRect: [Double], deviceRect: [Double]) {
        tvTube = tubeRect
        tvDevice = deviceRect
        let img = image ?? drawnFallbackBezel()
        tvContents = img.layerContents(forContentsScale: window?.backingScaleFactor ?? 2)
        needsLayout = true
    }

    func showHint(_ text: String?) {
        hintLabel?.removeFromSuperview(); hintLabel = nil
        guard let text = text else { return }
        let l = NSTextField(labelWithString: text)
        l.textColor = .white
        l.font = .systemFont(ofSize: 16, weight: .medium)
        l.alignment = .center
        l.frame = NSRect(x: 0, y: bounds.midY - 20, width: bounds.width, height: 40)
        l.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        addSubview(l)
        hintLabel = l
    }

    /// Fullscreen: whole 16:9 scene letterboxed. Windowed: the scene cropped to the TV
    /// set (contentsRect), aspect-fit — the floating window IS the TV.
    override func layout() {
        super.layout()
        let W = bounds.width, H = bounds.height
        // Pick per mode: contents + its tube rect + the crop applied to the image.
        let contents = windowed ? tvContents : sceneContents
        let tube = windowed ? tvTube : sceneTube
        let crop: (x: Double, y: Double, w: Double, h: Double) = windowed
            ? (tvDevice[0], tvDevice[1], tvDevice[2], tvDevice[3])
            : (0, 0, 1, 1)
        // Aspect of the cropped region (source images are 16:9).
        let cropAspect = (crop.w * 16.0) / (crop.h * 9.0)
        var bw = W, bh = W / cropAspect
        if bh > H { bh = H; bw = H * cropAspect }
        let bezelFrame = NSRect(x: (W - bw) / 2, y: (H - bh) / 2, width: bw, height: bh)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bezelLayer.contents = contents
        bezelLayer.frame = bezelFrame
        // contentsRect is in unit coords with a BOTTOM-LEFT origin (macOS layer space).
        bezelLayer.contentsRect = CGRect(x: crop.x, y: 1 - crop.y - crop.h,
                                         width: crop.w, height: crop.h)
        CATransaction.commit()

        if let mv = videoView {
            // Tube rect remapped into the crop, then into the bezel frame (y-up).
            let tx = (tube[0] - crop.x) / crop.w
            let ty = (tube[1] - crop.y) / crop.h
            let tw = tube[2] / crop.w
            let th = tube[3] / crop.h
            mv.frame = NSRect(x: bezelFrame.minX + CGFloat(tx) * bw,
                              y: bezelFrame.minY + CGFloat(1 - ty - th) * bh,
                              width: CGFloat(tw) * bw,
                              height: CGFloat(th) * bh)
            mv.layer?.cornerRadius = bw * 0.008
            mv.layer?.masksToBounds = true
        }
    }

    /// Simple dark TV frame used before any bezel is downloaded.
    private func drawnFallbackBezel() -> NSImage {
        let size = NSSize(width: 1280, height: 720)
        let img = NSImage(size: size)
        img.lockFocus()
        let full = NSRect(origin: .zero, size: size)
        NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
        NSBezierPath(roundedRect: full, xRadius: 28, yRadius: 28).fill()
        // punch the tube hole (rect matches the fallback tubeRect)
        let hole = NSRect(x: 0.09 * size.width, y: (1 - 0.10 - 0.72) * size.height,
                          width: 0.82 * size.width, height: 0.72 * size.height)
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(roundedRect: hole, xRadius: 12, yRadius: 12).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor(calibratedWhite: 0.25, alpha: 1).setStroke()
        let inner = NSBezierPath(roundedRect: hole.insetBy(dx: -3, dy: -3), xRadius: 14, yRadius: 14)
        inner.lineWidth = 6
        inner.stroke()
        img.unlockFocus()
        return img
    }
}

extension Notification.Name {
    static let tubeModeChanged = Notification.Name("TubeModeChanged")
}
