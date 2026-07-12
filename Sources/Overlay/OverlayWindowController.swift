import AppKit
import Metal
import MetalKit
import ScreenCaptureKit
import os

enum CaptureMode {
    case fullScreen
    case singleDisplay(CGDirectDisplayID)
    case singleWindow(SCWindow)
}

final class OverlayWindowController: NSObject, MTKViewDelegate {
    private var windows: [NSWindow] = []
    private var metalViews: [MTKView] = []
    private(set) var renderer: RetroRenderer!
    private var captureManagers: [ScreenCaptureManager] = []
    private var device: MTLDevice!
    private var overlayManager: OverlayManager!
    private(set) var captureMode: CaptureMode = .fullScreen
    private var didHideSystemUI = false
    private var trackingTimer: DispatchSourceTimer?
    private var trackedWindowID: CGWindowID = 0
    private var didReceiveFirstFrame = false
    private var spaceObserver: NSObjectProtocol?   // re-assert overlay onto a new (fullscreen) Space

    private var viewTextures: [ObjectIdentifier: MTLTexture] = [:]
    private var viewDirtyFlags: [ObjectIdentifier: Bool] = [:]
    private let textureLock = OSAllocatedUnfairLock()
    private var resizeDebounceTimer: DispatchSourceTimer?
    private var trackingIsMoving = false

    private var fpsFrameCount = 0
    private var fpsTimer: DispatchSourceTimer?
    var onFPSUpdate: ((Int, CGSize) -> Void)?

    var intensity: Float {
        get { renderer?.intensity ?? 1.0 }
        set { renderer?.intensity = newValue }
    }

    var vignetteIntensity: Float {
        get { renderer?.vignetteIntensity ?? 0.0 }
        set { renderer?.vignetteIntensity = newValue }
    }

    var lastGPUTimeMs: Double {
        renderer?.lastGPUTimeMs ?? 0
    }

    static func create(mode: CaptureMode = .fullScreen) async throws -> OverlayWindowController {
        let controller = OverlayWindowController()
        controller.captureMode = mode
        try controller.setupMetal()
        await controller.setupWindows()
        return controller
    }

    private func setupMetal() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SetupError.noMetalDevice
        }
        self.device = device
        self.renderer = try RetroRenderer(device: device)
        self.overlayManager = OverlayManager(device: device)
    }

    private static func cgRectToNS(_ cgRect: CGRect) -> NSRect {
        // Use CGMainDisplayID for correct primary display height in all multi-monitor setups.
        // CG coordinate space has origin at top-left of primary display; NS at bottom-left.
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return NSRect(
            x: cgRect.origin.x,
            y: primaryHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }

    @MainActor
    private func setupWindows() {
        let settings = AppSettings.shared
        let fps = settings.lowLatencyMode ? 60 : settings.targetFPS

        switch captureMode {
        case .fullScreen:
            for screen in NSScreen.screens {
                createOverlayWindow(frame: screen.frame, screen: screen, fps: fps)
            }
        case .singleDisplay(let displayID):
            // Resolve to EXACTLY ONE screen so the single capture stream (which feeds
            // metalViews[0]) always lines up with the single overlay window. A stored
            // targetDisplayID can go stale across reboots / display reconnects — if it no
            // longer matches any screen, fall back to the main display instead of spraying
            // windows over every screen (which left only the main monitor rendering).
            let target = NSScreen.screens.first(where: { $0.displayID == displayID }) ?? NSScreen.main
            if let screen = target {
                if screen.displayID != displayID {
                    print("[Overlay] singleDisplay: stored id \(displayID) not found — falling back to \(screen.localizedName) (id=\(screen.displayID))")
                }
                createOverlayWindow(frame: screen.frame, screen: screen, fps: fps)
            }
        case .singleWindow(let scWindow):
            let nsFrame = Self.cgRectToNS(scWindow.frame)
            let nsMidPoint = CGPoint(x: nsFrame.midX, y: nsFrame.midY)
            let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(nsMidPoint) }) ?? NSScreen.main!
            createOverlayWindow(frame: nsFrame, screen: targetScreen, fps: fps)
        }
    }

    @MainActor
    private func createOverlayWindow(frame: NSRect, screen: NSScreen?, fps: Int) {
        let metalView = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = false
        metalView.preferredFramesPerSecond = fps
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalView.layer?.isOpaque = false
        metalView.presentsWithTransaction = false
        metalView.delegate = self

        // NOTE: do NOT pass `screen:` here. When a screen is supplied, AppKit interprets
        // contentRect RELATIVE to that screen's origin — but `frame` is already in GLOBAL
        // coordinates. On a secondary display (non-zero origin, e.g. the built-in when an
        // external is main) that double-applies the offset and pushes the window offscreen
        // (window.screen == nil), so it renders but is never visible. Create in global
        // coordinates and set the frame explicitly.
        _ = screen
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(frame, display: false)
        // singleWindow overlay needs level 28 (above TV window at 25, above dock at 24, above start menu at 27)
        // fullScreen/singleDisplay uses level 28 (above start menu at 27)
        let overlayLevel: Int
        if case .singleWindow = captureMode {
            overlayLevel = 28
        } else {
            overlayLevel = 28
        }
        window.level = NSWindow.Level(rawValue: overlayLevel)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hasShadow = false
        window.contentView = metalView

        self.windows.append(window)
        self.metalViews.append(metalView)
    }

    private var shouldHideSystemUI = false

    func loadOverlays() {
        let settings = AppSettings.shared
        overlayManager.loadScanline(named: settings.scanlineOverlayName)
        overlayManager.loadReflection(named: settings.reflectionName)
        syncOverlayTextures()

        if let t = overlayManager.scanlineTexture {
            print("[Overlay] Scanline loaded: \(t.width)×\(t.height)")
        } else if !settings.scanlineOverlayName.isEmpty {
            print("[Overlay] Scanline FAILED to load: '\(settings.scanlineOverlayName)'")
        }
        if let t = overlayManager.reflectionTexture {
            print("[Overlay] Reflection loaded: \(t.width)×\(t.height)")
        } else if !settings.reflectionName.isEmpty {
            print("[Overlay] Reflection FAILED to load: '\(settings.reflectionName)'")
        }
    }

    func syncOverlayTextures() {
        let settings = AppSettings.shared
        renderer.scanlineTexture = overlayManager.scanlineTexture
        renderer.reflectionTexture = overlayManager.reflectionTexture
        renderer.scanlineIntensity = settings.scanlineOverlayIntensity
        renderer.reflectionIntensity = settings.reflectionIntensity
    }

    func start(presetName: String) async throws {
        try renderer.loadShader(named: presetName)
        loadOverlays()

        let settings = AppSettings.shared
        let captureFPS = settings.lowLatencyMode ? 60 : settings.targetFPS

        let isFullscreenMode: Bool
        switch captureMode {
        case .fullScreen, .singleDisplay: isFullscreenMode = true
        case .singleWindow: isFullscreenMode = false
        }

        shouldHideSystemUI = isFullscreenMode && settings.hideSystemUI
        didReceiveFirstFrame = false

        await MainActor.run {
            for window in self.windows { window.orderFrontRegardless() }

            // Full-screen overlay sometimes "falls off" when a window enters its own
            // native fullscreen Space. Re-assert the overlay to the front whenever the
            // active Space changes (mirrors the dock controller's space handling).
            if isFullscreenMode, self.spaceObserver == nil {
                self.spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.activeSpaceDidChangeNotification,
                    object: nil, queue: .main
                ) { [weak self] _ in
                    guard let self = self else { return }
                    for window in self.windows { window.orderFrontRegardless() }
                    // Entering fullscreen can drop us briefly; assert again once it settles.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.windows.forEach { $0.orderFrontRegardless() }
                    }
                }
            }
        }

        try await Task.sleep(nanoseconds: 500_000_000)

        let windowIDs = await MainActor.run {
            self.windows.map { CGWindowID($0.windowNumber) }
        }

        switch captureMode {
        case .fullScreen:
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let screens = await MainActor.run { NSScreen.screens }

            print("[Overlay] NSScreen displays: \(screens.map { "\($0.localizedName)(id=\($0.displayID))" })")
            print("[Overlay] SCDisplay displays: \(content.displays.map { "id=\($0.displayID) \($0.width)x\($0.height)" })")

            for (index, screen) in screens.enumerated() {
                guard index < metalViews.count else { break }
                let metalView = metalViews[index]
                let displayID = screen.displayID

                guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
                    print("[Overlay] No SCDisplay match for \(screen.localizedName) (id=\(displayID)) — trying by index")
                    if index < content.displays.count {
                        let fallbackID = content.displays[index].displayID
                        print("[Overlay] Using SCDisplay index \(index) (id=\(fallbackID)) for \(screen.localizedName)")
                        let manager = ScreenCaptureManager(device: device)
                        captureManagers.append(manager)
                        let viewID = ObjectIdentifier(metalView)
                        manager.onNewFrame = { [weak self] texture in
                            self?.textureLock.withLock {
                                self?.viewTextures[viewID] = texture
                                self?.viewDirtyFlags[viewID] = true
                            }
                        }
                        manager.onFirstFrame = { [weak self] in
                            DispatchQueue.main.async {
                                guard let self = self else { return }
                                metalView.isPaused = false
                                self.handleFirstFrame()
                            }
                        }
                        manager.setFrameRate(fps: captureFPS)
                        do {
                            try await manager.startDisplay(fallbackID, excludingWindowIDs: windowIDs, content: content)
                            print("[Overlay] Started capture for display \(fallbackID) (fallback for \(screen.localizedName))")
                        } catch {
                            print("[Overlay] Failed to start display \(fallbackID): \(error)")
                        }
                    }
                    continue
                }

                let manager = ScreenCaptureManager(device: device)
                captureManagers.append(manager)

                let viewID = ObjectIdentifier(metalView)
                manager.onNewFrame = { [weak self] texture in
                    self?.textureLock.withLock {
                        self?.viewTextures[viewID] = texture
                        self?.viewDirtyFlags[viewID] = true
                    }
                }
                manager.onFirstFrame = { [weak self] in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        metalView.isPaused = false
                        self.handleFirstFrame()
                    }
                }
                manager.setFrameRate(fps: captureFPS)
                do {
                    try await manager.startDisplay(displayID, excludingWindowIDs: windowIDs, content: content)
                    print("[Overlay] Started capture for display \(displayID) (\(screen.localizedName))")
                } catch {
                    print("[Overlay] Failed to start display \(displayID) (\(screen.localizedName)): \(error)")
                }
            }

        case .singleDisplay(let displayID):
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            print("[Overlay] singleDisplay requested: \(displayID)")
            print("[Overlay] Available SCDisplays: \(content.displays.map { "id=\($0.displayID) \($0.width)x\($0.height)" })")

            // Resolve to the SAME screen the overlay window landed on (setupWindows uses the
            // identical "match by id, else main" fallback), so a stale targetDisplayID can't
            // make us capture one display while the window sits on another.
            let resolvedScreen: NSScreen? = await MainActor.run {
                let exact = NSScreen.screens.first(where: { $0.displayID == displayID })
                return exact ?? NSScreen.main
            }
            let effectiveID: CGDirectDisplayID
            if content.displays.contains(where: { $0.displayID == displayID }) {
                effectiveID = displayID
            } else if let screen = resolvedScreen,
                      let scDisplay = content.displays.first(where: {
                          Int($0.width) == Int(screen.frame.width) && Int($0.height) == Int(screen.frame.height)
                      }) {
                print("[Overlay] ID mismatch — matched by resolution: \(scDisplay.displayID)")
                effectiveID = scDisplay.displayID
            } else if let mainSC = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) {
                print("[Overlay] singleDisplay: no match for \(displayID) — falling back to main display \(mainSC.displayID)")
                effectiveID = mainSC.displayID
            } else if let firstSC = content.displays.first {
                print("[Overlay] singleDisplay: no match for \(displayID) — falling back to first available display \(firstSC.displayID)")
                effectiveID = firstSC.displayID
            } else {
                effectiveID = displayID
            }

            let manager = ScreenCaptureManager(device: device)
            captureManagers.append(manager)
            setupSingleStreamCallbacks(manager: manager, metalView: metalViews[0], captureFPS: captureFPS)
            do {
                try await manager.startDisplay(effectiveID, excludingWindowIDs: windowIDs, content: content)
                print("[Overlay] Started single-display capture for \(effectiveID)")
            } catch {
                // Don't abort the whole overlay (which would leave a stuck transparent
                // window) — log so the failing display is visible in the user's console.
                print("[Overlay] FAILED single-display capture for \(effectiveID): \(error)")
                throw error
            }

        case .singleWindow(let scWindow):
            let manager = ScreenCaptureManager(device: device)
            captureManagers.append(manager)
            setupSingleStreamCallbacks(manager: manager, metalView: metalViews[0], captureFPS: captureFPS, hideSystemUI: false)
            try await manager.startWindow(scWindow, excludingWindowIDs: windowIDs)
            self.trackedWindowID = scWindow.windowID
            startWindowTracking()
        }

        print("[Overlay] Active (fps=\(captureFPS), lowLatency=\(settings.lowLatencyMode)).")
    }

    private func handleFirstFrame() {
        guard !didReceiveFirstFrame else { return }
        didReceiveFirstFrame = true
        print("[Overlay] First frame → rendering")
        if shouldHideSystemUI {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self, self.didReceiveFirstFrame else { return }
                SystemUIHelper.hideMenuBarAndDock()
                self.didHideSystemUI = true
                print("[Overlay] System UI hidden via System Events")
            }
        }
    }

    private func setupSingleStreamCallbacks(manager: ScreenCaptureManager, metalView: MTKView, captureFPS: Int, hideSystemUI: Bool = true) {
        let viewID = ObjectIdentifier(metalView)
        manager.onNewFrame = { [weak self] texture in
            self?.textureLock.withLock {
                self?.viewTextures[viewID] = texture
                self?.viewDirtyFlags[viewID] = true
            }
        }
        manager.onFirstFrame = { [weak self] in
            // Hop to main: MTKView.isPaused and UI/state must be touched on the main
            // thread — this callback fires on the capture queue.
            DispatchQueue.main.async {
                guard let self = self else { return }
                for view in self.metalViews { view.isPaused = false }
                if hideSystemUI {
                    self.handleFirstFrame()
                } else {
                    self.didReceiveFirstFrame = true
                    print("[Overlay] First frame → rendering")
                }
            }
        }
        manager.setFrameRate(fps: captureFPS)
    }

    func stop() {
        let doStop = { [weak self] in
            guard let self = self else { return }
            self.trackingTimer?.cancel()
            self.trackingTimer = nil
            self.resizeDebounceTimer?.cancel()
            self.resizeDebounceTimer = nil
            if let obs = self.spaceObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(obs)
                self.spaceObserver = nil
            }
            self.stopFPSTracking()
            for manager in self.captureManagers { manager.stop() }
            self.captureManagers.removeAll()
            for view in self.metalViews { view.isPaused = true }
            for window in self.windows { window.orderOut(nil) }
            self.textureLock.withLock {
                self.viewTextures.removeAll()
                self.viewDirtyFlags.removeAll()
            }
            self.didReceiveFirstFrame = false

            if self.didHideSystemUI {
                SystemUIHelper.showMenuBarAndDock()
                self.didHideSystemUI = false
            }
            print("[Overlay] Stopped.")
        }
        if Thread.isMainThread {
            doStop()
        } else {
            DispatchQueue.main.async { doStop() }
        }
    }

    func switchPreset(_ name: String) {
        do {
            try renderer.loadShader(named: name)
        } catch {
            print("[Overlay] Switch failed: \(error)")
            // Show error to user for custom shaders (compile errors etc.)
            if name.hasPrefix("custom:") {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Shader Compile Error"
                    alert.informativeText = "\(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let viewID = ObjectIdentifier(view)
        // Render the last captured texture EVERY tick, not only on a fresh frame. ScreenCaptureKit
        // stops delivering frames once a display is static (it sends status-only frames with no
        // buffer), so a "dirty"-gated draw left such a display (e.g. the built-in) permanently
        // blank after its single frame. The ScreenCaptureManager now retains that frame's buffer,
        // so its texture stays valid and re-presenting it is safe.
        let texture = textureLock.withLock { viewTextures[viewID] }
        guard let texture = texture, let drawable = view.currentDrawable else { return }
        renderer.render(sourceTexture: texture, to: drawable, viewportSize: view.drawableSize)
        fpsFrameCount += 1
    }

    func startFPSTracking() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let count = self.fpsFrameCount
            self.fpsFrameCount = 0
            let resolution: CGSize
            if let tex = self.textureLock.withLock({ self.viewTextures.values.first }) {
                resolution = CGSize(width: tex.width, height: tex.height)
            } else {
                resolution = .zero
            }
            self.onFPSUpdate?(count, resolution)
        }
        timer.resume()
        fpsTimer = timer
    }

    func stopFPSTracking() {
        fpsTimer?.cancel()
        fpsTimer = nil
    }

    func captureScreenshot() -> NSImage? {
        let texture: MTLTexture? = textureLock.withLock {
            viewTextures.values.first
        }
        guard let source = texture else { return nil }
        let size = CGSize(width: source.width, height: source.height)
        return renderer.renderToImage(sourceTexture: source, viewportSize: size)
    }

    // MARK: - Child Window Attachment (for TV overlay)

    /// Attach overlay windows as children of a parent window.
    /// This makes clicks pass through the overlay directly to the parent via ignoresMouseEvents,
    /// and the child automatically moves/resizes with the parent — no tracking timer needed.
    @MainActor
    func attachToParentWindow(_ parent: NSWindow) {
        // Stop position tracking — child windows follow parent automatically
        trackingTimer?.cancel()
        trackingTimer = nil

        for window in windows {
            // Reset level — child windows inherit stacking from parent
            window.level = .normal
            parent.addChildWindow(window, ordered: .above)
        }
        print("[Overlay] Attached as child of window \(parent.windowNumber)")
    }

    // MARK: - Window Tracking (off main thread)

    private func startWindowTracking() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.updateWindowPosition()
        }
        timer.resume()
        self.trackingTimer = timer
    }

    private var lastTrackedFrame: CGRect = .zero

    private func updateWindowPosition() {
        guard trackedWindowID != 0 else { return }

        // Query ONLY the tracked window instead of enumerating every on-screen window —
        // much cheaper when many windows/displays are open.
        let windowList = CGWindowListCopyWindowInfo(.optionIncludingWindow, trackedWindowID) as? [[String: Any]] ?? []

        guard let info = windowList.first,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"],
              let w = bounds["Width"], let h = bounds["Height"] else {
            DispatchQueue.main.async { self.stop() }
            return
        }

        let cgFrame = CGRect(x: x, y: y, width: w, height: h)
        let changed = cgFrame != lastTrackedFrame

        if changed != trackingIsMoving {
            trackingIsMoving = changed
            let ms = changed ? 33 : 100
            trackingTimer?.schedule(deadline: .now() + .milliseconds(ms), repeating: .milliseconds(ms))
        }

        guard changed else { return }

        let sizeChanged = lastTrackedFrame.size != .zero && cgFrame.size != lastTrackedFrame.size
        lastTrackedFrame = cgFrame

        let nsFrame = Self.cgRectToNS(cgFrame)

        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let overlayWindow = self.windows.first else { return }

            overlayWindow.setFrame(nsFrame, display: false, animate: false)
            if let metalView = self.metalViews.first {
                metalView.frame = NSRect(origin: .zero, size: nsFrame.size)
            }
        }

        if sizeChanged {
            scheduleStreamResize(cgFrame: cgFrame)
        }
    }

    private func scheduleStreamResize(cgFrame: CGRect) {
        resizeDebounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + .milliseconds(150))
        timer.setEventHandler { [weak self] in
            // Reuse the scale the capture actually started with (the window display's
            // backingScaleFactor, or 1 in halfResolution) — not a hardcoded 2×, which stretched
            // or mis-cropped the stream on 1×/scaled displays after a resize.
            let scale = self?.captureManagers.first?.captureScale ?? (AppSettings.shared.halfResolution ? 1 : 2)
            let pw = max(Int(cgFrame.width) * scale, 200)
            let ph = max(Int(cgFrame.height) * scale, 200)
            self?.captureManagers.first?.updateStreamSize(width: pw, height: ph)
        }
        timer.resume()
        resizeDebounceTimer = timer
    }

    enum SetupError: Error, LocalizedError {
        case noMetalDevice
        case noScreen
        var errorDescription: String? {
            switch self {
            case .noMetalDevice: return "No Metal GPU found"
            case .noScreen: return "No screen found"
            }
        }
    }
}
