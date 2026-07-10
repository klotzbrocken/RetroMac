import AppKit
import Metal
import MetalKit

/// Renders the CRT/VHS shader onto ONLY the desktop wallpaper.
///
/// Unlike `OverlayWindowController` (which screen-captures the whole display and re-presents
/// it in a window at level 28, ABOVE everything), this controller creates a borderless window
/// per screen that sits BELOW the desktop icons and every app window. Its source texture is the
/// current wallpaper image — not a live capture — so the shader animates the wallpaper (VHS
/// wobble, scanline drift, etc.) while icons, folders, and windows stay crisp and untouched.
///
/// Because it never captures the screen, it needs no Screen Recording permission.
final class WallpaperShaderController: NSObject, MTKViewDelegate {
    private var windows: [NSWindow] = []
    private var metalViews: [MTKView] = []
    private(set) var renderer: RetroRenderer!
    private let device: MTLDevice
    private let textureLoader: MTKTextureLoaderLite
    private let overlayManager: OverlayManager

    /// One wallpaper texture per MTKView (keyed by the view's identity), so multi-monitor
    /// setups can each carry their own wallpaper.
    private var wallpaperTextures: [ObjectIdentifier: MTLTexture] = [:]
    private var screenParamsObserver: NSObjectProtocol?
    private(set) var isActive = false

    var intensity: Float {
        get { renderer?.intensity ?? 1.0 }
        set { renderer?.intensity = newValue }
    }

    var vignetteIntensity: Float {
        get { renderer?.vignetteIntensity ?? 0.0 }
        set { renderer?.vignetteIntensity = newValue }
    }

    init(device: MTLDevice) throws {
        self.device = device
        self.textureLoader = MTKTextureLoaderLite(device: device)
        self.renderer = try RetroRenderer(device: device)
        self.overlayManager = OverlayManager(device: device)
        super.init()
    }

    /// Build a controller ready to render `presetName`. Falls back to a safe built-in shader if
    /// the requested preset can't be compiled (e.g. a "Lite" id that has no full-shader source),
    /// so wallpaper mode never hard-fails on preset choice.
    static func create(presetName: String) throws -> WallpaperShaderController {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw OverlayWindowController.SetupError.noMetalDevice
        }
        let controller = try WallpaperShaderController(device: device)
        do {
            try controller.renderer.loadShader(named: presetName)
        } catch {
            print("[WallpaperShader] Preset '\(presetName)' failed to load (\(error)) — falling back to zfast-crt")
            try controller.renderer.loadShader(named: "zfast-crt")
        }
        controller.loadOverlays()
        return controller
    }

    // MARK: - Lifecycle
    // NOTE: window/MTKView creation must happen on the main thread; callers (AppDelegate) already
    // invoke these on main, matching the rest of the overlay controllers (no @MainActor isolation).

    func start() {
        rebuildWindows()
        for window in windows { window.orderFront(nil) }
        isActive = true

        // Rebuild on display reconfiguration (resolution change, monitor plugged/unplugged).
        if screenParamsObserver == nil {
            screenParamsObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                guard let self = self, self.isActive else { return }
                self.rebuildWindows()
                for window in self.windows { window.orderFront(nil) }
            }
        }
        print("[WallpaperShader] Active on \(windows.count) screen(s).")
    }

    func stop() {
        let doStop = { [weak self] in
            guard let self = self else { return }
            if let obs = self.screenParamsObserver {
                NotificationCenter.default.removeObserver(obs)
                self.screenParamsObserver = nil
            }
            for view in self.metalViews { view.isPaused = true }
            for window in self.windows { window.orderOut(nil) }
            self.windows.removeAll()
            self.metalViews.removeAll()
            self.wallpaperTextures.removeAll()
            self.isActive = false
            print("[WallpaperShader] Stopped.")
        }
        if Thread.isMainThread { doStop() } else { DispatchQueue.main.async { doStop() } }
    }

    // MARK: - Windows

    private func rebuildWindows() {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        metalViews.removeAll()
        wallpaperTextures.removeAll()

        let settings = AppSettings.shared
        let fps = settings.lowLatencyMode ? 60 : settings.targetFPS

        for screen in NSScreen.screens {
            createWindow(for: screen, fps: fps)
        }
    }

    private func createWindow(for screen: NSScreen, fps: Int) {
        let frame = screen.frame
        let metalView = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = false                      // free-run so the shader keeps animating
        metalView.preferredFramesPerSecond = fps
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        metalView.layer?.isOpaque = true
        metalView.delegate = self

        // Create in GLOBAL coordinates (no `screen:` arg) — see OverlayWindowController for the
        // secondary-display offset trap this avoids.
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(frame, display: false)
        // Sit just BELOW the desktop-icons panel (normalWindow-1) — so it covers the OS
        // wallpaper but never the icons, folders, or app windows above it.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) - 2)
        window.isOpaque = true
        window.backgroundColor = .black
        window.ignoresMouseEvents = true                // clicks pass through to the real desktop
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = false
        window.contentView = metalView

        if let texture = loadWallpaperTexture(for: screen) {
            wallpaperTextures[ObjectIdentifier(metalView)] = texture
        }

        windows.append(window)
        metalViews.append(metalView)
    }

    private func loadWallpaperTexture(for screen: NSScreen) -> MTLTexture? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            print("[WallpaperShader] No wallpaper URL for \(screen.localizedName)")
            return nil
        }
        guard let texture = textureLoader.load(from: url) else {
            print("[WallpaperShader] Failed to load wallpaper texture: \(url.lastPathComponent)")
            return nil
        }
        return texture
    }

    /// Re-fetch each screen's current wallpaper (call after a theme/wallpaper change).
    func reloadWallpaper() {
        guard isActive else { return }
        for (index, screen) in NSScreen.screens.enumerated() {
            guard index < metalViews.count else { break }
            if let texture = loadWallpaperTexture(for: screen) {
                wallpaperTextures[ObjectIdentifier(metalViews[index])] = texture
            }
        }
    }

    // MARK: - Preset / overlays (mirrors OverlayWindowController so callers treat both alike)

    func switchPreset(_ name: String) {
        do {
            try renderer.loadShader(named: name)
        } catch {
            print("[WallpaperShader] Switch to '\(name)' failed (\(error)) — keeping current shader")
        }
    }

    func loadOverlays() {
        let settings = AppSettings.shared
        overlayManager.loadScanline(named: settings.scanlineOverlayName)
        overlayManager.loadReflection(named: settings.reflectionName)
        syncOverlayTextures()
    }

    func syncOverlayTextures() {
        let settings = AppSettings.shared
        renderer.scanlineTexture = overlayManager.scanlineTexture
        renderer.reflectionTexture = overlayManager.reflectionTexture
        renderer.scanlineIntensity = settings.scanlineOverlayIntensity
        renderer.reflectionIntensity = settings.reflectionIntensity
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let texture = wallpaperTextures[ObjectIdentifier(view)],
              let drawable = view.currentDrawable else { return }
        renderer.render(sourceTexture: texture, to: drawable, viewportSize: view.drawableSize, opaque: true)
    }
}
