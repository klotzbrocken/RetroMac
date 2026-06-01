import AppKit

/// Manages the Windows 3.1 Program Manager desktop overlay — a transparent, full-screen
/// panel (desktop-icon level) hosting the custom-drawn Program Manager MDI frame.
/// Parallels DesktopIconsController; only one is active per theme.
final class ProgramManagerController {

    static let shared = ProgramManagerController()

    private var window: NSPanel?
    private var pmView: ProgramManagerView?
    private var isVisible = false

    private init() {}

    // MARK: - Public API

    /// Show the Program Manager for the active theme, or hide if the theme has none.
    func update() {
        guard let theme = ThemeManager.shared.activeTheme,
              let pmConfig = theme.config.programManager else {
            hide()
            return
        }
        registerThemeFont(theme)
        show(config: pmConfig, themeBundle: theme)
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        pmView = nil
        isVisible = false
    }

    // MARK: - Font

    private func registerThemeFont(_ theme: ThemeBundle) {
        let fontsDir = theme.url.appendingPathComponent("fonts")
        guard let files = try? FileManager.default.contentsOfDirectory(at: fontsDir, includingPropertiesForKeys: nil) else { return }
        for f in files where ["ttf", "otf"].contains(f.pathExtension.lowercased()) {
            Win31Chrome.registerFont(at: f)
        }
    }

    // MARK: - Window

    private func show(config: DockThemeConfig.ProgramManagerConfig, themeBundle: ThemeBundle) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let visible = screen.visibleFrame

        if window == nil {
            let panel = NSPanel(
                contentRect: screenFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.ignoresMouseEvents = false
            panel.isMovableByWindowBackground = false
            panel.hidesOnDeactivate = false
            panel.acceptsMouseMovedEvents = false

            // NOTE: intentionally NOT layer-backed. A layer-backed content view forces
            // implicit layer-backing on the whole subtree, and re-ordering group windows
            // (bring-to-front) then clears their layers → transparent title bars / white
            // fills. Classic draw(_:)-based rendering is reliable here.
            let content = NSView(frame: NSRect(origin: .zero, size: screenFrame.size))
            panel.contentView = content
            self.window = panel
        }

        guard let content = window?.contentView else { return }
        window?.setFrame(screenFrame, display: false)
        content.frame = NSRect(origin: .zero, size: screenFrame.size)

        // Remove old PM view
        pmView?.removeFromSuperview()

        // Center the Program Manager frame in the visible area (relative to screen frame origin)
        let pmW = min(visible.width * 0.78, 980)
        let pmH = min(visible.height * 0.78, 680)
        let originX = (screenFrame.width - pmW) / 2
        let originY = (screenFrame.height - pmH) / 2 - 20
        let pmFrame = NSRect(x: originX, y: max(0, originY), width: pmW, height: pmH)

        let view = ProgramManagerView(config: config, themeBundle: themeBundle, frame: pmFrame)
        content.addSubview(view)
        view.performInitialLayout()
        self.pmView = view

        window?.orderFront(nil)
        isVisible = true
    }
}
