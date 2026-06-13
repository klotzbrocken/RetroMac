import AppKit
import AVKit
import AVFoundation

/// Shows a theme's boot screen on theme activation: a fullscreen video (with sound) if the
/// theme defines `splashVideo`, otherwise the `splashScreen` image (~3 s). Per-theme on/off
/// via AppSettings.themeBootscreenEnabled (default on for themes with a video or the XP image).
final class SplashController {

    static let shared = SplashController()
    private var window: NSWindow?
    private var dismissTimer: Timer?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    private init() {}

    /// Default boot-screen state when the user hasn't toggled it: ON for any theme that
    /// defines a boot video or image.
    private func bootscreenDefaultOn(_ theme: ThemeBundle) -> Bool {
        theme.config.splashVideo != nil || theme.config.splashScreen != nil
    }

    /// Show the boot screen for the active theme if enabled. No-op otherwise.
    func showIfEnabled(for theme: ThemeBundle) {
        guard AppSettings.shared.showSplashScreen, let screen = NSScreen.main else { return }
        let enabled = AppSettings.shared.themeBootscreenEnabled[theme.config.name] ?? bootscreenDefaultOn(theme)
        guard enabled else { return }

        // Prefer a boot video (played fullscreen with sound) when present.
        if let videoFile = theme.config.splashVideo {
            let url = theme.url.appendingPathComponent(videoFile)
            if FileManager.default.fileExists(atPath: url.path) {
                showVideo(url: url, on: screen)
                return
            }
        }
        // Fall back to the image splash.
        guard let file = theme.config.splashScreen,
              let image = NSImage(contentsOf: theme.url.appendingPathComponent(file)) else { return }
        show(image: image, on: screen, fullscreen: theme.config.splashFullscreen == true)
    }

    private func bootWindow(_ frame: NSRect, opaque: Bool) -> NSWindow {
        let win = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.level = .screenSaver
        win.isOpaque = opaque
        win.backgroundColor = .black
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.ignoresMouseEvents = false   // a click skips straight to the desktop
        return win
    }

    /// Top-level content view that dismisses the boot screen on a mouse click (skip to desktop).
    private func dismissView(_ frame: NSRect, content: NSView) -> NSView {
        let v = BootDismissView(frame: frame)
        v.onDismiss = { [weak self] in self?.dismiss() }
        content.frame = v.bounds
        content.autoresizingMask = [.width, .height]
        v.addSubview(content)
        return v
    }

    private func showVideo(url: URL, on screen: NSScreen) {
        dismiss()
        let frame = screen.frame
        let win = bootWindow(frame, opaque: true)
        win.hasShadow = false

        let player = AVPlayer(url: url)
        let pv = AVPlayerView(frame: NSRect(origin: .zero, size: frame.size))
        pv.player = player
        pv.controlsStyle = .none
        pv.videoGravity = .resizeAspect
        win.contentView = dismissView(NSRect(origin: .zero, size: frame.size), content: pv)
        win.orderFrontRegardless()
        self.window = win
        self.player = player

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { [weak self] _ in self?.dismiss() }

        player.play()
        // Safety cap in case the end notification is missed.
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
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

        let win = bootWindow(frame, opaque: true)
        win.hasShadow = !fullscreen

        let iv = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        iv.image = image
        iv.imageScaling = .scaleProportionallyUpOrDown
        win.contentView = dismissView(NSRect(origin: .zero, size: frame.size), content: iv)

        win.orderFrontRegardless()
        self.window = win

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTimer?.invalidate(); dismissTimer = nil
        if let obs = endObserver { NotificationCenter.default.removeObserver(obs); endObserver = nil }
        player?.pause(); player = nil
        window?.orderOut(nil)
        window = nil
    }
}

/// Covers the boot screen; any mouse click (or key) dismisses it and skips to the desktop.
private final class BootDismissView: NSView {
    var onDismiss: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { onDismiss?() }
    override func rightMouseDown(with event: NSEvent) { onDismiss?() }
    override func keyDown(with event: NSEvent) { onDismiss?() }
}
