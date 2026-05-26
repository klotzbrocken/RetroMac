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
    private var renderer: RetroRenderer!
    private var captureManagers: [ScreenCaptureManager] = []
    private var device: MTLDevice!
    private var overlayManager: OverlayManager!
    private(set) var captureMode: CaptureMode = .fullScreen
    private var didHideSystemUI = false
    private var trackingTimer: DispatchSourceTimer?
    private var trackedWindowID: CGWindowID = 0
    private var didReceiveFirstFrame = false

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
            if let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) {
                createOverlayWindow(frame: screen.frame, screen: screen, fps: fps)
            } else {
                for screen in NSScreen.screens {
                    createOverlayWindow(frame: screen.frame, screen: screen, fps: fps)
                }
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

        let window: NSWindow
        if let screen = screen {
            window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        } else {
            window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        }
        // singleWindow overlay needs level 26 (above TV window at 25, above dock at 24)
        // fullScreen/singleDisplay uses level 25
        let overlayLevel: Int
        if case .singleWindow = captureMode {
            overlayLevel = 26
        } else {
            overlayLevel = 25
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
                            guard let self = self else { return }
                            metalView.isPaused = false
                            self.handleFirstFrame()
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
                    guard let self = self else { return }
                    metalView.isPaused = false
                    self.handleFirstFrame()
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

            let effectiveID: CGDirectDisplayID
            if content.displays.contains(where: { $0.displayID == displayID }) {
                effectiveID = displayID
            } else if let screen = await MainActor.run(body: { NSScreen.screens.first(where: { $0.displayID == displayID }) }),
                      let scDisplay = content.displays.first(where: {
                          Int($0.width) == Int(screen.frame.width) && Int($0.height) == Int(screen.frame.height)
                      }) {
                print("[Overlay] ID mismatch — matched by resolution: \(scDisplay.displayID)")
                effectiveID = scDisplay.displayID
            } else {
                effectiveID = displayID
            }

            let manager = ScreenCaptureManager(device: device)
            captureManagers.append(manager)
            setupSingleStreamCallbacks(manager: manager, metalView: metalViews[0], captureFPS: captureFPS)
            try await manager.startDisplay(effectiveID, excludingWindowIDs: windowIDs, content: content)

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
            guard let self = self else { return }
            for view in self.metalViews { view.isPaused = false }
            if hideSystemUI {
                self.handleFirstFrame()
            } else {
                self.didReceiveFirstFrame = true
                print("[Overlay] First frame → rendering")
            }
        }
        manager.setFrameRate(fps: captureFPS)
    }

    func stop() {
        let doStop = { [self] in
            trackingTimer?.cancel()
            trackingTimer = nil
            resizeDebounceTimer?.cancel()
            resizeDebounceTimer = nil
            stopFPSTracking()
            for manager in captureManagers { manager.stop() }
            captureManagers.removeAll()
            for view in metalViews { view.isPaused = true }
            for window in windows { window.orderOut(nil) }
            textureLock.withLock {
                viewTextures.removeAll()
                viewDirtyFlags.removeAll()
            }
            didReceiveFirstFrame = false

            if didHideSystemUI {
                SystemUIHelper.showMenuBarAndDock()
                didHideSystemUI = false
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
        let (texture, isDirty) = textureLock.withLock {
            let t = viewTextures[viewID]
            let d = viewDirtyFlags[viewID] ?? false
            if d { viewDirtyFlags[viewID] = false }
            return (t, d)
        }
        guard isDirty, let texture = texture,
              let drawable = view.currentDrawable else { return }
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

        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []

        guard let info = windowList.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == trackedWindowID }),
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
            let scale = AppSettings.shared.halfResolution ? 1 : 2
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
