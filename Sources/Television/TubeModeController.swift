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
    private var loadedShader = ""              // the shader actually running (for safe reverts)

    // MARK: - Public

    func toggle() { isActive ? stop() : start() }

    /// Start (or re-tune) the Tube on a specific stream — used by the dock context
    /// menu / start menu / deskbar "TV Streams" entries.
    func startOnBookmark(url: String) {
        AppSettings.shared.tvLastBookmarkURL = url
        if isActive {
            if let idx = AppSettings.shared.tvBookmarks.firstIndex(where: { $0.url == url }) {
                startChannel(idx)
            }
            window?.makeKeyAndOrderFront(nil)
        } else {
            start()
        }
    }

    func start() {
        guard !isActive else { return }
        AppDelegate.shared?.stopOverlaysForTube()   // no global overlay/lite/viewport/camera on top
        let screen = targetScreen()
        // Start WINDOWED: a floating TV set (scene cropped to the device); double-click
        // goes fullscreen with the whole scene.
        let startW = min(920, screen.visibleFrame.width * 0.45)
        let startFrame = NSRect(x: screen.visibleFrame.midX - startW / 2,
                                y: screen.visibleFrame.midY - startW * 0.42,
                                width: startW, height: startW * 0.84)
        // No .resizable: macOS 26 decorates resizable borderless windows with a system
        // "liquid glass" edge (the stripe Maik saw bottom/right). Resizing is manual via
        // the corner handle in TubeContentView instead.
        let win = TubeWindow(contentRect: startFrame, styleMask: [.borderless],
                             backing: .buffered, defer: false)
        win.level = AppSettings.shared.tvTubeOnTop ? .floating : .normal
        win.isOpaque = false
        win.backgroundColor = .clear
        // No window shadow: on a transparent borderless window macOS renders it as a
        // soft rim on the bottom/right that reads as a "glass" edge.
        win.hasShadow = false
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
        guard setupPlayerPipeline(in: content) else {
            // No Metal / no shader → never pretend to be on: tear the window down,
            // keep the pill off, tell the user.
            window = nil
            contentView = nil
            NotificationCenter.default.post(name: .tubeModeChanged, object: nil)
            let alert = NSAlert()
            alert.messageText = "TV Tube unavailable"
            alert.informativeText = "TV Tube needs a working Metal device and shader pipeline, which this system doesn't provide right now."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
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
        // Windowed mode: the selected free-standing TV cutout (bundled). The device
        // crop (measured TV-silhouette bbox) makes the window hug the TV so there's no
        // transparent margin — no stray "glass"/shadow rim.
        let tvs = store.windowTVs
        let selected = store.windowTV(named: AppSettings.shared.tvTubeWindowTV) ?? tvs.first
        if let sel = selected,
           let url = Bundle.main.resourceURL?.appendingPathComponent("TV/\(sel.file)"),
           let tv = NSImage(contentsOf: url) {
            content.setWindowTV(image: tv, tubeRect: sel.rect, deviceRect: sel.device ?? [0, 0, 1, 1])
        } else {
            content.setWindowTV(image: nil,
                                tubeRect: [0.09, 0.10, 0.82, 0.72],
                                deviceRect: [0, 0, 1, 1])
        }
        // Windowed: snap the frame to the TV set's aspect (resizing itself is manual
        // via the corner handle, which enforces aspect + min size).
        if !isFullscreen, let win = window {
            let aspect = content.windowAspect
            var f = win.frame
            f.size.height = f.width / aspect
            win.setFrame(f, display: true)
        }
    }

    /// Re-apply bezel + shader while running (Settings changes). A failed shader load
    /// keeps the currently-running one AND reverts the stored preset, so the UI never
    /// shows a shader that isn't actually rendering.
    func refreshAppearance() {
        guard isActive else { return }
        loadBezel()
        let want = AppSettings.shared.tvTubePreset
        guard want != loadedShader else { return }
        do {
            try renderer?.loadShader(named: want)
            loadedShader = want
        } catch {
            print("[Tube] Shader '\(want)' failed to load (\(error)) — keeping '\(loadedShader)'")
            AppSettings.shared.tvTubePreset = loadedShader
        }
    }

    // MARK: - Player + shader pipeline (same pattern as TVBrowserWindow.streamDirect)

    @discardableResult
    private func setupPlayerPipeline(in content: TubeContentView) -> Bool {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[Tube] No Metal device")
            return false
        }
        do {
            let r = try RetroRenderer(device: device)
            do {
                try r.loadShader(named: AppSettings.shared.tvTubePreset)
            } catch {
                // Broken/unknown preset id — one fallback attempt before giving up.
                print("[Tube] Shader '\(AppSettings.shared.tvTubePreset)' failed (\(error)) — falling back to trinitron-tv")
                try r.loadShader(named: "trinitron-tv")
                AppSettings.shared.tvTubePreset = "trinitron-tv"
            }
            r.intensity = AppSettings.shared.defaultIntensity
            r.vignetteIntensity = AppSettings.shared.vignetteIntensity
            renderer = r
            loadedShader = AppSettings.shared.tvTubePreset
        } catch {
            print("[Tube] Shader load failed: \(error)")
            return false
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
        return true
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

    // MARK: - Context menu (right-click on the tube)

    fileprivate func showContextMenu(with event: NSEvent, in view: NSView) {
        let menu = NSMenu()

        let chMenu = NSMenu()
        for (i, b) in AppSettings.shared.tvBookmarks.enumerated() {
            let it = NSMenuItem(title: b.name, action: #selector(menuPickChannel(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.state = i == channelIndex ? .on : .off
            chMenu.addItem(it)
        }
        let chItem = NSMenuItem(title: "Channel", action: nil, keyEquivalent: "")
        menu.addItem(chItem)
        menu.setSubmenu(chMenu, for: chItem)

        let shMenu = NSMenu()
        for (category, presets) in PresetRegistry.categorizedPresets where category != .lite {
            for p in presets {
                let it = NSMenuItem(title: p.displayName, action: #selector(menuPickShader(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = p.id
                it.state = p.id == AppSettings.shared.tvTubePreset ? .on : .off
                shMenu.addItem(it)
            }
            shMenu.addItem(.separator())
        }
        let shItem = NSMenuItem(title: "Shader", action: nil, keyEquivalent: "")
        menu.addItem(shItem)
        menu.setSubmenu(shMenu, for: shItem)

        // Show only the picker that applies to the CURRENT mode — windowed uses the
        // free-standing TV cutouts, fullscreen uses the full scene bezels. (Showing both
        // made picks look ignored: a scene bezel does nothing while windowed.)
        if isFullscreen {
            let bzMenu = NSMenu()
            let builtin = NSMenuItem(title: "Simple frame (built-in)", action: #selector(menuPickBezel(_:)), keyEquivalent: "")
            builtin.target = self
            builtin.representedObject = ""
            builtin.state = AppSettings.shared.tvTubeBezel.isEmpty ? .on : .off
            bzMenu.addItem(builtin)
            for b in BezelStore.shared.available {
                let title = BezelStore.shared.isDownloaded(b) ? b.name : "\(b.name)  (download)"
                let it = NSMenuItem(title: title, action: #selector(menuPickBezel(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = b.file
                it.state = b.file == AppSettings.shared.tvTubeBezel ? .on : .off
                bzMenu.addItem(it)
            }
            let bzItem = NSMenuItem(title: "Scene Bezel", action: nil, keyEquivalent: "")
            menu.addItem(bzItem)
            menu.setSubmenu(bzMenu, for: bzItem)
        } else {
            let wtMenu = NSMenu()
            for tv in BezelStore.shared.windowTVs {
                let it = NSMenuItem(title: tv.name, action: #selector(menuPickWindowTV(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = tv.file
                it.state = tv.file == AppSettings.shared.tvTubeWindowTV ? .on : .off
                wtMenu.addItem(it)
            }
            let wtItem = NSMenuItem(title: "TV Set", action: nil, keyEquivalent: "")
            menu.addItem(wtItem)
            menu.setSubmenu(wtMenu, for: wtItem)
        }

        menu.addItem(.separator())
        let onTop = NSMenuItem(title: "Always on Top", action: #selector(menuToggleOnTop), keyEquivalent: "")
        onTop.target = self
        onTop.state = AppSettings.shared.tvTubeOnTop ? .on : .off
        menu.addItem(onTop)
        let classic = NSMenuItem(title: "Classic Themed Window", action: #selector(menuClassicWindow), keyEquivalent: "")
        classic.target = self
        menu.addItem(classic)
        let fs = NSMenuItem(title: isFullscreen ? "Exit Fullscreen" : "Fullscreen",
                            action: #selector(menuToggleFullscreen), keyEquivalent: "")
        fs.target = self
        menu.addItem(fs)
        let off = NSMenuItem(title: "Turn Off", action: #selector(menuTurnOff), keyEquivalent: "")
        off.target = self
        menu.addItem(off)

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func menuPickChannel(_ sender: NSMenuItem) { startChannel(sender.tag) }

    @objc private func menuPickShader(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        AppSettings.shared.tvTubePreset = id
        refreshAppearance()
    }

    @objc private func menuPickBezel(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? String else { return }
        if let bezel = BezelStore.shared.bezel(named: file), !BezelStore.shared.isDownloaded(bezel) {
            AppSettings.shared.tvTubeBezel = file
            BezelStore.shared.download(bezel) { [weak self] result in
                if case .failure = result { AppSettings.shared.tvTubeBezel = "" }
                self?.refreshAppearance()
                self?.enterFullscreenForBezel()
            }
            return
        }
        AppSettings.shared.tvTubeBezel = file
        refreshAppearance()
        enterFullscreenForBezel()
    }

    /// Scene bezels only show in fullscreen (the windowed mode is Maik's own TV set) —
    /// picking one while windowed switches to fullscreen so the choice is visible.
    private func enterFullscreenForBezel() {
        if isActive, !isFullscreen { toggleFullscreen() }
    }

    @objc private func menuToggleFullscreen() { toggleFullscreen() }
    @objc private func menuTurnOff() { stop() }

    @objc private func menuPickWindowTV(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? String else { return }
        AppSettings.shared.tvTubeWindowTV = file
        refreshAppearance()
        // Window TVs only show in windowed mode — leave fullscreen so the pick is visible.
        if isFullscreen { toggleFullscreen() }
    }

    @objc private func menuToggleOnTop() {
        AppSettings.shared.tvTubeOnTop.toggle()
        window?.level = AppSettings.shared.tvTubeOnTop ? .floating : .normal
    }

    /// "TV Bezel off": hand the current channel to the classic THEMED window
    /// (BeOS Lasche / Platinum / Luna chrome — the existing TVBrowserWindow).
    @objc private func menuClassicWindow() {
        let books = AppSettings.shared.tvBookmarks
        let bookmark = books.indices.contains(channelIndex) ? books[channelIndex] : books.first
        stop()
        if let bm = bookmark { AppDelegate.shared?.tvBrowser.open(bookmark: bm) }
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

    private let resizeHandle = TubeResizeHandle()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        bezelLayer.contentsGravity = .resize
        bezelLayer.zPosition = 1                      // bezel BELOW the video: the PNGs are
        layer?.addSublayer(bezelLayer)                // opaque, the video sits in the tube region
        addSubview(resizeHandle)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func rightMouseDown(with event: NSEvent) {
        TubeModeController.shared.showContextMenu(with: event, in: self)
    }

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
        // Windowed: fully transparent around the TV cutout (an opaque black backing
        // showed as a black stripe wherever frame and crop aspect differed by a pixel).
        layer?.backgroundColor = (windowed ? NSColor.clear : NSColor.black).cgColor
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
        // Manual resize grip on the TV's bottom-right corner (windowed only). Kept
        // frontmost so the video layer never swallows its clicks.
        resizeHandle.isHidden = !windowed
        resizeHandle.frame = NSRect(x: bezelFrame.maxX - 46, y: bezelFrame.minY, width: 46, height: 46)
        resizeHandle.tvAspect = CGFloat(crop.w * 16.0) / CGFloat(crop.h * 9.0)
        if resizeHandle.superview != nil {
            resizeHandle.removeFromSuperview()
            addSubview(resizeHandle)   // re-add → above the video view
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

/// Invisible drag grip on the TV's bottom-right corner: resizes the borderless tube
/// window proportionally (top-left anchored). Replaces the system .resizable behaviour,
/// which paints a "liquid glass" edge on macOS 26 borderless windows.
private final class TubeResizeHandle: NSView {
    var tvAspect: CGFloat = 16.0 / 9.0

    override var mouseDownCanMoveWindow: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    override func resetCursorRects() {
        if #available(macOS 15.0, *) {
            addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
        } else {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    /// Small visible grip (three diagonal ticks) so the resize corner is discoverable.
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 1, alpha: 0.55).setStroke()
        let p = NSBezierPath()
        p.lineWidth = 1.5
        let w = bounds.width, inset: CGFloat = 8
        for d in stride(from: 0 as CGFloat, through: 12, by: 5) {
            p.move(to: NSPoint(x: w - inset - d, y: inset))
            p.line(to: NSPoint(x: w - inset, y: inset + d))
        }
        p.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let win = window else { return }
        let startFrame = win.frame
        let startLoc = NSEvent.mouseLocation
        while true {
            guard let ev = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            if ev.type == .leftMouseUp { break }
            let loc = NSEvent.mouseLocation
            var w = startFrame.width + (loc.x - startLoc.x)
            let maxW = win.screen?.visibleFrame.width ?? 4000
            w = min(max(w, 200), maxW)               // can shrink to a small floating TV
            let h = w / tvAspect
            win.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - h, width: w, height: h),
                         display: true)
        }
    }
}

extension Notification.Name {
    static let tubeModeChanged = Notification.Name("TubeModeChanged")
}
