import AppKit
import Metal
import MetalKit

/// Lightweight CRT overlay that draws scanlines, phosphor mask, and vignette
/// as a transparent window on top of the screen — NO ScreenCaptureKit needed.
///
/// This renders purely additive/subtractive effects (darkening patterns) without
/// capturing the content underneath. The shader outputs black with varying alpha
/// to simulate CRT characteristics.
final class CRTLiteOverlay: NSObject, MTKViewDelegate {
    private var window: NSWindow?
    private var metalView: MTKView?
    private var renderer: RetroRenderer?
    private var device: MTLDevice?
    private var clearTexture: MTLTexture?

    /// Whether the lite overlay is currently active
    private(set) var isActive = false

    /// The shader preset name (e.g. "crt-lite" or "lcd-lite")
    private var shaderName: String = "crt-lite"

    /// Forwarded shader intensity (0…1)
    var intensity: Float {
        get { renderer?.intensity ?? 1.0 }
        set { renderer?.intensity = newValue }
    }

    /// Forwarded vignette intensity (0…1)
    var vignetteIntensity: Float {
        get { renderer?.vignetteIntensity ?? 0 }
        set { renderer?.vignetteIntensity = newValue }
    }

    /// Forwarded bloom enabled state
    var bloomEnabled: Bool {
        get { renderer?.bloomEnabled ?? false }
        set { renderer?.bloomEnabled = newValue }
    }

    /// Forwarded bloom intensity (0…1)
    var bloomIntensity: Float {
        get { renderer?.bloomIntensity ?? 0.3 }
        set { renderer?.bloomIntensity = newValue }
    }

    /// Forwarded bloom radius
    var bloomRadius: Float {
        get { renderer?.bloomRadius ?? 5 }
        set { renderer?.bloomRadius = newValue }
    }

    /// Tracking for single-window mode
    private var trackedBundleID: String?
    private var trackingTimer: Timer?

    // MARK: - Public API

    /// Start full-screen Lite overlay on all screens
    func startFullScreen(intensity: Float = 1.0, vignetteIntensity: Float = 0.5, preset: String = "crt-lite") {
        guard !isActive else { return }
        shaderName = preset

        // System color filters via MediaAccessibility
        activateSystemFilter(for: preset)

        do {
            try setup()
        } catch {
            print("[CRTLite] Setup failed: \(error.localizedDescription)")
            DisplayFilterHelper.restoreFilter()
            return
        }

        guard let device = device else { return }

        // Honor the chosen display (Display menu). 0 = all screens (union); otherwise
        // cover just the selected screen. Without this, Lite always spanned the union,
        // so it effectively only appeared on the main display — unlike the full overlay.
        let tid = AppSettings.shared.targetDisplayID
        let frame: NSRect
        if tid != 0, let target = NSScreen.screens.first(where: { $0.displayID == tid }) {
            frame = target.frame
        } else {
            frame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        }
        createWindow(frame: frame, level: 28)

        renderer?.intensity = intensity
        renderer?.vignetteIntensity = vignetteIntensity

        isActive = true
        metalView?.isPaused = false
        window?.orderFrontRegardless()
        print("[CRTLite] Full-screen overlay started")
    }

    /// Start Lite overlay tracking a specific app window by bundle ID
    func startForApp(bundleID: String, intensity: Float = 1.0, vignetteIntensity: Float = 0.5, preset: String = "crt-lite") {
        guard !isActive else { return }
        shaderName = preset

        // System color filters via MediaAccessibility
        activateSystemFilter(for: preset)

        do {
            try setup()
        } catch {
            print("[CRTLite] Setup failed: \(error.localizedDescription)")
            DisplayFilterHelper.restoreFilter()
            return
        }

        trackedBundleID = bundleID
        renderer?.intensity = intensity
        renderer?.vignetteIntensity = vignetteIntensity

        // Find the app window and position overlay on top
        if let appWindow = findAppWindow(bundleID: bundleID) {
            let nsFrame = cgRectToNS(appWindow)
            createWindow(frame: nsFrame, level: 26)
            isActive = true
            metalView?.isPaused = false
            window?.orderFrontRegardless()
            startTracking(bundleID: bundleID)
            print("[CRTLite] App overlay started for \(bundleID)")
        } else {
            // App window not found — start tracking anyway; the timer will
            // pick up the window once it appears and resize the overlay.
            print("[CRTLite] App window not yet visible for \(bundleID), starting with placeholder")
            let placeholderFrame = NSRect(x: 0, y: 0, width: 1, height: 1)
            createWindow(frame: placeholderFrame, level: 26)
            isActive = true
            metalView?.isPaused = false
            startTracking(bundleID: bundleID)
        }
    }

    /// Stop the CRT Lite overlay
    func stop() {
        guard isActive else { return }
        isActive = false

        // Restore system display filter if we enabled it (B&W / Amber Lite)
        DisplayFilterHelper.restoreFilter()

        // Stop timers first
        trackingTimer?.invalidate()
        trackingTimer = nil
        trackedBundleID = nil

        // Pause rendering and detach delegate BEFORE closing
        // This prevents draw(in:) from being called on a deallocating renderer
        metalView?.isPaused = true
        metalView?.delegate = nil

        // Hide and close window
        window?.orderOut(nil)
        window = nil
        metalView = nil

        // Release Metal resources AFTER view is detached
        renderer = nil
        clearTexture = nil
        device = nil

        print("[CRTLite] Overlay stopped")
    }

    // MARK: - System Display Filters

    /// Activate macOS Accessibility color filter for presets that need it
    private func activateSystemFilter(for preset: String) {
        switch preset {
        case "bw-lite":
            DisplayFilterHelper.enableGrayscale()
        case "amber-lite":
            // Warm amber/orange hue ≈ 30° on color wheel → 30/360 ≈ 0.083
            DisplayFilterHelper.enableColorTint(hue: 0.08, intensity: 1.0)
        default:
            break
        }
    }

    // MARK: - Setup

    private func setup() throws {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "CRTLite", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Metal device"])
        }
        self.device = dev
        self.renderer = try RetroRenderer(device: dev)
        try renderer?.loadShader(named: shaderName)

        // Create a 1x1 transparent texture as dummy source
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        desc.usage = [.shaderRead]
        self.clearTexture = dev.makeTexture(descriptor: desc)
    }

    private func createWindow(frame: NSRect, level: Int) {
        // Clean up any existing window — detach delegate first
        metalView?.delegate = nil
        metalView?.isPaused = true
        window?.orderOut(nil)

        let mtkView = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 30  // Lite mode doesn't need 60fps
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.layer?.isOpaque = false
        mtkView.presentsWithTransaction = false
        mtkView.delegate = self

        let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.level = NSWindow.Level(rawValue: level)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        win.hasShadow = false

        win.contentView = mtkView

        self.window = win
        self.metalView = mtkView
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard isActive,
              let drawable = view.currentDrawable,
              let renderer = renderer,
              let clearTex = clearTexture else { return }

        let viewportSize = CGSize(width: view.drawableSize.width, height: view.drawableSize.height)
        renderer.render(sourceTexture: clearTex, to: drawable, viewportSize: viewportSize)
    }

    // MARK: - Window Tracking

    /// Track the target app's window position and resize overlay accordingly
    private func startTracking(bundleID: String) {
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self, self.isActive else {
                timer.invalidate()
                return
            }

            // Check if app is still running
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if apps.isEmpty {
                print("[CRTLite] Tracked app quit — stopping overlay")
                self.stop()
                // Restore previous overlay state
                if let appDel = NSApp.delegate as? AppDelegate {
                    appDel.restorePreviousOverlay()
                }
                return
            }

            // Update window position to match app window
            if let appFrame = self.findAppWindow(bundleID: bundleID) {
                let nsFrame = self.cgRectToNS(appFrame)
                if let win = self.window, win.frame != nsFrame {
                    win.setFrame(nsFrame, display: false)
                    self.metalView?.frame = NSRect(origin: .zero, size: nsFrame.size)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Find the main window rect (in CG coordinates) for an app by bundle ID
    private func findAppWindow(bundleID: String) -> CGRect? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard let pid = apps.first?.processIdentifier else {
            print("[CRTLite] No running app with bundleID: \(bundleID)")
            return nil
        }

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            print("[CRTLite] CGWindowListCopyWindowInfo returned nil")
            return nil
        }

        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else { continue }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect),
                  rect.width > 100, rect.height > 100 else { continue }

            print("[CRTLite] Found window for \(bundleID): \(rect)")
            return rect
        }
        print("[CRTLite] No suitable window found for PID \(pid) (\(bundleID))")
        return nil
    }

    private func cgRectToNS(_ cgRect: CGRect) -> NSRect {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return NSRect(
            x: cgRect.origin.x,
            y: primaryHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }
}
