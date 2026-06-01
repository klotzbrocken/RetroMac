import AppKit

/// Shows a theme's boot splash image centered on screen for ~3 seconds on theme
/// activation (when AppSettings.showSplashScreen is enabled and the theme defines one).
final class SplashController {

    static let shared = SplashController()
    private var window: NSWindow?
    private var dismissTimer: Timer?

    private init() {}

    /// Show the splash for the active theme if enabled. No-op otherwise.
    func showIfEnabled(for theme: ThemeBundle) {
        guard AppSettings.shared.showSplashScreen,
              let file = theme.config.splashScreen else { return }
        let url = theme.url.appendingPathComponent(file)
        guard let image = NSImage(contentsOf: url), let screen = NSScreen.main else { return }
        let fullscreen = theme.config.splashFullscreen == true
        show(image: image, on: screen, fullscreen: fullscreen)
    }

    private func show(image: NSImage, on screen: NSScreen, fullscreen: Bool) {
        dismiss()

        let frame: NSRect
        if fullscreen {
            frame = screen.frame                       // fill the whole display (e.g. Win 98 boot)
        } else {
            // Centered box, up to ~640pt wide, keeping aspect ratio
            let maxW: CGFloat = 640
            let scale = min(1, maxW / image.size.width)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            frame = NSRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.midY - size.height / 2,
                           width: size.width, height: size.height)
        }

        let win = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.level = .screenSaver
        win.isOpaque = true
        win.backgroundColor = .black
        win.hasShadow = !fullscreen
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.ignoresMouseEvents = true

        let iv = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        iv.image = image
        // Fullscreen boot screens fill the display (crop slightly); centered ones fit.
        iv.imageScaling = fullscreen ? .scaleProportionallyUpOrDown : .scaleProportionallyUpOrDown
        win.contentView = iv

        win.orderFrontRegardless()
        self.window = win

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTimer?.invalidate(); dismissTimer = nil
        window?.orderOut(nil)
        window = nil
    }
}
