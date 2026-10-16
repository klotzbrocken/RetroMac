import AppKit
import MetalKit

/// Desktop Glass: a window you place over anything — a video, an emulator, a web page — that
/// shows what lies under it through the current shader. ShaderGlass's idea on Windows; here a
/// ScreenCaptureKit stream of the window's own rectangle, with the window itself left out of it,
/// drawn by the same renderer as the full-screen effect.
///
/// Independent of the overlay: it runs with the shader on or off and with any effect scope.
/// "Click Through" lets the pointer reach what is under the glass; the menu-bar menu turns it off
/// again, since the window then takes no clicks itself.
final class DesktopGlassController: NSObject, NSWindowDelegate, MTKViewDelegate {
    static let shared = DesktopGlassController()

    static let clickThroughKey = "desktopGlassClickThrough"
    private(set) var isOn = false
    var clickThrough: Bool {
        get { UserDefaults.standard.bool(forKey: Self.clickThroughKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.clickThroughKey)
            window?.ignoresMouseEvents = newValue
        }
    }

    private var device: MTLDevice?
    private var window: NSWindow?
    private var view: MTKView?
    private var renderer: RetroRenderer?
    private var capture: ScreenCaptureManager?
    private var captureDisplay: CGDirectDisplayID = 0
    private var preset = ""
    private let lock = NSLock()
    private var texture: MTLTexture?
    private var regionTimer: DispatchWorkItem?
    private var presetObserver: NSObjectProtocol?

    func toggle() { isOn ? close() : open() }

    func open() {
        guard !isOn else { window?.makeKeyAndOrderFront(nil); return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            let a = NSAlert()
            a.messageText = "Desktop Glass needs Screen Recording"
            a.informativeText = "It shows what lies under its window through the shader, so it has to see the screen. Allow RetroMac under System Settings ▸ Privacy & Security ▸ Screen Recording, then turn Desktop Glass on again."
            a.runModal()
            return
        }
        guard let device = MTLCreateSystemDefaultDevice(), let renderer = try? RetroRenderer(device: device) else { return }
        self.renderer = renderer
        self.device = device
        loadCurrentPreset()

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Desktop Glass"
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.collectionBehavior = [.fullScreenAuxiliary]
        w.minSize = NSSize(width: 160, height: 100)
        w.backgroundColor = .black
        w.delegate = self
        let v = MTKView(frame: w.contentLayoutRect, device: device)
        v.colorPixelFormat = .bgra8Unorm
        v.preferredFramesPerSecond = AppSettings.shared.targetFPS
        v.delegate = self
        v.setAccessibilityElement(false)   // a picture of what is behind it; the window has the name
        w.contentView = v
        if !w.setFrameUsingName("RetroMacDesktopGlass") { w.center() }
        w.setFrameAutosaveName("RetroMacDesktopGlass")
        w.ignoresMouseEvents = clickThrough
        window = w; view = v; isOn = true
        w.makeKeyAndOrderFront(nil)

        // The preset follows the menu: every change there rebuilds the menu, which posts this.
        presetObserver = NotificationCenter.default.addObserver(forName: .overlayStateChanged, object: nil, queue: .main) { [weak self] _ in
            self?.loadCurrentPreset()
        }
        restartCapture()
        AppDelegate.shared?.refreshMenu()
    }

    func close() { window?.close() }   // windowWillClose does the rest

    func windowWillClose(_ notification: Notification) {
        capture?.stop(); capture = nil
        if let o = presetObserver { NotificationCenter.default.removeObserver(o) }
        presetObserver = nil
        lock.withLock { texture = nil }
        window = nil; view = nil; renderer = nil; device = nil; preset = ""; isOn = false
        AppDelegate.shared?.refreshMenu()
    }

    private func loadCurrentPreset() {
        let name = AppDelegate.fullPreset(for: AppDelegate.shared?.currentPresetName ?? "crt-lottes")
        guard name != preset else { return }
        do { try renderer?.loadShader(named: name) } catch { try? renderer?.loadShader(named: "crt-lottes") }
        preset = name
    }

    // MARK: - Where the glass is

    /// The content rectangle in its display's points, top-left origin, and the pixels to capture.
    private func region() -> (CGDirectDisplayID, CGRect, Int, Int)? {
        guard let w = window, let screen = w.screen else { return nil }
        let id = screen.displayID
        let r = w.contentRect(forFrameRect: w.frame).intersection(screen.frame)
        guard r.width >= 2, r.height >= 2 else { return nil }
        let local = Self.displayRect(r, in: screen.frame)
        let scale = AppSettings.shared.halfResolution ? 1 : screen.backingScaleFactor
        return (id, local, Int(r.width * scale), Int(r.height * scale))
    }

    /// AppKit's global rectangle (origin bottom left of the main display) as `sourceRect` wants
    /// it: the display's own points, origin top left.
    static func displayRect(_ r: CGRect, in screen: CGRect) -> CGRect {
        CGRect(x: r.minX - screen.minX, y: screen.maxY - r.maxY, width: r.width, height: r.height)
    }

    private func restartCapture() {
        capture?.stop()
        guard let device, let w = window, let (display, rect, pw, ph) = region() else { return }
        let m = ScreenCaptureManager(device: device)
        m.setFrameRate(fps: AppSettings.shared.targetFPS)
        m.onNewFrame = { [weak self] t in self?.lock.withLock { self?.texture = t } }
        capture = m
        captureDisplay = display
        let ownID = CGWindowID(w.windowNumber)
        Task {
            do { try await m.startDisplayRegion(display, rect: rect, width: pw, height: ph, excludingWindowIDs: [ownID]) }
            catch { print("[Glass] Capture failed: \(error.localizedDescription)") }
        }
    }

    /// Moving or resizing sends a stream of changes; the capture follows the last one.
    private func regionChanged() {
        regionTimer?.cancel()
        let job = DispatchWorkItem { [weak self] in
            guard let self, let (display, rect, pw, ph) = self.region() else { return }
            if display != self.captureDisplay { self.restartCapture() }
            else { self.capture?.updateRegion(rect: rect, width: pw, height: ph) }
        }
        regionTimer = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: job)
    }

    func windowDidMove(_ notification: Notification) { regionChanged() }
    func windowDidResize(_ notification: Notification) { regionChanged() }
    func windowDidChangeScreen(_ notification: Notification) { regionChanged() }

    // MARK: - Drawing

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let t = lock.withLock({ texture }), let drawable = view.currentDrawable else { return }
        renderer?.intensity = AppDelegate.shared?.currentIntensity ?? 1
        renderer?.render(sourceTexture: t, to: drawable, viewportSize: view.drawableSize, opaque: true, output: view)
    }
}
