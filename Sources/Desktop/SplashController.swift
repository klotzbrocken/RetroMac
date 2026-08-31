import AppKit
import AVKit
import AVFoundation

/// Shows a theme's boot screen on theme activation: a fullscreen video (with sound) if the
/// theme defines `splashVideo`, otherwise the `splashScreen` image (~3 s). Covers every
/// display; a mouse click or any key skips straight to the desktop. Per-theme on/off via
/// AppSettings.themeBootscreenEnabled (default on for themes with a video or image).
final class SplashController {

    static let shared = SplashController()
    private var windows: [NSWindow] = []          // main content window + black covers on other screens
    /// Every boot screen is on screen for the same length of time, whether it is a still, a
    /// native draw or a video. They used to run 2.5s, 3s, or however long the clip happened to
    /// be — which ranged from 4.9s (Windows XP) to 23s (Mac OS X), a ninefold spread.
    ///
    /// Five seconds rather than four because three of the six clips already sit there: Mac OS 9
    /// is 5.0s, Windows XP 4.9s, Windows 95 6.0s. Four would have clipped XP's closing pulse,
    /// which runs from 4s to the end. The Windows 95/98 progress bars loop, so cutting them
    /// mid-loop is invisible; Snow Leopard's clip is a still frame throughout.
    static let duration: TimeInterval = 5.0

    private var dismissTimer: Timer?
    private var player: AVPlayer?

    private init() {}

    /// Default boot-screen state when the user hasn't toggled it: ON for any theme that
    /// defines a boot video or image.
    private func bootscreenDefaultOn(_ theme: ThemeBundle) -> Bool {
        theme.config.splashVideo != nil || theme.config.splashScreen != nil || theme.config.splashWelcome == true
    }

    /// Show the boot screen for the active theme if enabled. No-op otherwise.
    func showIfEnabled(for theme: ThemeBundle) {
        guard AppSettings.shared.showSplashScreen, let screen = NSScreen.main else { return }
        let enabled = AppSettings.shared.themeBootscreenEnabled[theme.stableID] ?? bootscreenDefaultOn(theme)
        guard enabled else { return }

        // Prefer a boot video (played fullscreen with sound) when present.
        if let videoFile = theme.config.splashVideo {
            let url = theme.url.appendingPathComponent(videoFile)
            if FileManager.default.fileExists(atPath: url.path) {
                showVideo(url: url, on: screen)
                return
            }
        }
        // Classic "Welcome to Macintosh" boot screen (System 6), drawn natively.
        if theme.config.splashWelcome == true {
            showWelcome(on: screen)
            return
        }
        // Fall back to the image splash.
        guard let splashURL = theme.rootResource(theme.config.splashScreen),
              let image = NSImage(contentsOf: splashURL) else { return }
        show(image: image, on: screen, fullscreen: theme.config.splashFullscreen == true)
    }

    /// Borderless boot window that can become key so keystrokes reach BootDismissView.
    private final class BootWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private func bootWindow(_ frame: NSRect, opaque: Bool) -> NSWindow {
        let win = BootWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.level = .screenSaver
        win.isOpaque = opaque
        win.backgroundColor = .black
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        win.ignoresMouseEvents = false   // a click skips straight to the desktop
        return win
    }

    /// Top-level content view that dismisses the boot screen on a mouse click / key (skip to desktop).
    private func dismissView(_ frame: NSRect, content: NSView?) -> BootDismissView {
        let v = BootDismissView(frame: frame)
        v.onDismiss = { [weak self] in self?.dismiss() }
        if let content = content {
            content.frame = v.bounds
            content.autoresizingMask = [.width, .height]
            v.addSubview(content)
        }
        return v
    }

    /// Black, click-to-dismiss cover windows on every screen except the main one.
    private func addCoverScreens(except main: NSScreen) {
        for scr in NSScreen.screens where scr.frame != main.frame {
            let win = bootWindow(scr.frame, opaque: true)
            win.contentView = dismissView(NSRect(origin: .zero, size: scr.frame.size), content: nil)
            win.orderFrontRegardless()
            windows.append(win)
        }
    }

    /// Show the main window key + first-responder so it also receives key events.
    private func present(_ win: NSWindow, dismissView: BootDismissView) {
        windows.append(win)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(dismissView)
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
        pv.videoGravity = .resizeAspect   // fit the whole frame (4:3 boot videos keep their bottom animation; black bars on the sides read as authentic)
        let dv = dismissView(NSRect(origin: .zero, size: frame.size), content: pv)
        win.contentView = dv
        self.player = player

        addCoverScreens(except: screen)
        present(win, dismissView: dv)

        // No dismiss-on-end observer: a clip shorter than `duration` holds its last frame so
        // every boot screen lasts the same time, and a longer one is cut. Both are deliberate.
        player.play()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: Self.duration, repeats: false) { [weak self] _ in
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
        iv.animates = true      // boot screens may be animated GIFs (Windows Me is)
        let dv = dismissView(NSRect(origin: .zero, size: frame.size), content: iv)
        win.contentView = dv

        addCoverScreens(except: screen)
        present(win, dismissView: dv)

        dismissTimer = Timer.scheduledTimer(withTimeInterval: Self.duration, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    /// Classic Mac boot screen: the "Welcome to Macintosh" dialog box on a grey desktop, drawn
    /// natively (ported from metamage_1's Welcome demo — happy Mac icon + text in a dBoxProc frame).
    private func showWelcome(on screen: NSScreen) {
        dismiss()
        let frame = screen.frame
        let win = bootWindow(frame, opaque: true)
        win.hasShadow = false
        let content = WelcomeSplashView(frame: NSRect(origin: .zero, size: frame.size))
        let dv = dismissView(NSRect(origin: .zero, size: frame.size), content: content)
        win.contentView = dv
        addCoverScreens(except: screen)
        present(win, dismissView: dv)
        dismissTimer = Timer.scheduledTimer(withTimeInterval: Self.duration, repeats: false) { [weak self] _ in self?.dismiss() }
    }

    func dismiss() {
        dismissTimer?.invalidate(); dismissTimer = nil
        player?.pause(); player = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

/// The classic "Welcome to Macintosh" boot screen: a happy-Mac dialog box on a 50% grey desktop.
private final class WelcomeSplashView: NSView {
    override var isFlipped: Bool { true }

    private static let grayFill: NSColor = {
        let img = NSImage(size: NSSize(width: 2, height: 2))
        img.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        NSColor.black.setFill(); NSRect(x: 0, y: 0, width: 1, height: 1).fill(); NSRect(x: 1, y: 1, width: 1, height: 1).fill()
        img.unlockFocus()
        return NSColor(patternImage: img)
    }()

    override func draw(_ dirtyRect: NSRect) {
        Self.grayFill.setFill(); bounds.fill()                      // 50% grey desktop

        let bw: CGFloat = 480, bh: CGFloat = 128
        let box = NSRect(x: (bounds.width - bw) / 2, y: (bounds.height - bh) * 0.28, width: bw, height: bh)
        NSColor.white.setFill(); box.fill()
        NSColor.black.setStroke()
        let outer = NSBezierPath(rect: box); outer.lineWidth = 2; outer.stroke()          // dBoxProc double frame
        let inner = NSBezierPath(rect: box.insetBy(dx: 4, dy: 4)); inner.lineWidth = 1; inner.stroke()

        drawHappyMac(in: NSRect(x: box.minX + 30, y: box.midY - 32, width: 64, height: 64))

        let text = "Welcome to Macintosh."
        let font = NSFont(name: "Chicago", size: 26) ?? NSFont.boldSystemFont(ofSize: 24)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: box.minX + 118, y: box.midY - size.height / 2), withAttributes: attrs)
    }

    /// Compact-Macintosh happy face, drawn on a 32-unit grid scaled into `r` (black on the box).
    private func drawHappyMac(in r: NSRect) {
        let s = r.width / 32
        func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: r.minX + x * s, y: r.minY + y * s) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: r.minX + x * s, y: r.minY + y * s, width: w * s, height: h * s) }
        NSColor.black.setStroke(); NSColor.black.setFill()
        let body = NSBezierPath(roundedRect: rect(5, 1, 22, 30), xRadius: 3 * s, yRadius: 3 * s); body.lineWidth = 1.6 * s; body.stroke()   // computer
        let screen = NSBezierPath(rect: rect(8, 4, 16, 13)); screen.lineWidth = 1.4 * s; screen.stroke()                                    // screen
        rect(11, 8, 2.4, 2.4).fill(); rect(18.6, 8, 2.4, 2.4).fill()                                                                         // eyes
        let smile = NSBezierPath(); smile.lineWidth = 1.4 * s; smile.lineCapStyle = .round                                                   // smile
        smile.move(to: P(12, 12.5)); smile.curve(to: P(20, 12.5), controlPoint1: P(14.5, 15), controlPoint2: P(17.5, 15)); smile.stroke()
        let slot = NSBezierPath(); slot.lineWidth = 1.4 * s; slot.move(to: P(10, 21)); slot.line(to: P(22, 21)); slot.stroke()               // floppy slot
    }
}

/// Covers the boot screen; any mouse click or key dismisses it and skips to the desktop.
private final class BootDismissView: NSView {
    var onDismiss: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { onDismiss?() }
    override func rightMouseDown(with event: NSEvent) { onDismiss?() }
    override func keyDown(with event: NSEvent) { onDismiss?() }
    /// Claim every click for ourselves: AVPlayerView (video splash) swallows mouse
    /// events even with controlsStyle == .none, so without this the skip-click never
    /// reached us on the WinXP / Win98 / Mac boot videos.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = superview.map { convert(point, from: $0) } ?? point
        return bounds.contains(p) ? self : nil
    }
}
