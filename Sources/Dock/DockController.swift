import AppKit
import Carbon.HIToolbox
import Combine

final class DockController {
    static let shared = DockController()

    private var window: DockWindow?
    private var dockView: DockView?
    private var isStarted = false       // guards re-entrancy for dock-less themes (Win 3.1)
    private var screenObserver: NSObjectProtocol?
    private var fullscreenObserver: NSObjectProtocol?
    private var settingsObservers: [AnyCancellable] = []
    private var isVisible = false
    private var manualToggle: Bool?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var didHideSystemDock = false
    private var lastAppliedHidePosition: String?   // guards against re-running killall Dock per theme switch
    private var dockOpGeneration = 0               // supersedes stale async hide/restore completions
    private var originalDockAutoHide: Bool?
    private var originalDockPosition: String?
    private var originalMinimizeToApp: Bool?
    private var originalMinEffect: String?
    private var originalAutohideDelay: String?

    // Auto-hide state
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var autoHideVisible = false
    private var autoHideAnimating = false
    private let autoHideTriggerHeight: CGFloat = 5    // px from screen bottom to trigger show
    private let autoHideLeaveMargin: CGFloat = 20     // px above dock to trigger hide

    func start() {
        guard !isStarted else { return }
        isStarted = true
        print("[Dock] Starting")

        ThemeManager.shared.reload()
        AppManager.shared.syncAutoDownloads(active: ThemeManager.shared.activeTheme?.config.hasFolderStacks == true && AppSettings.shared.dockShowDownloads)
        // Dock-only changes nothing but the dock — no boot splash (matches the
        // theme-switch path in the $dockTheme sink).
        if !AppSettings.shared.dockOnly, let theme = ThemeManager.shared.activeTheme {
            SplashController.shared.showIfEnabled(for: theme)
        }
        let hidesDock = ThemeManager.shared.activeTheme?.config.hidesDock ?? false
        if !hidesDock {
            createWindow()
        }
        registerHotkey()
        applySystemDockPolicy()
        DesktopIconsController.shared.update()
        ProgramManagerController.shared.update()
        SGIDesktopController.shared.update()
        BeOSDeskbarController.shared.update()
        if AppSettings.shared.hideMenuBar {
            SystemUIHelper.setMenuBarAutoHide(true)
        }
        if AppSettings.shared.hideDesktopIcons {
            SystemUIHelper.setDesktopIconsHidden(true)
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.repositionWindow()
        }

        fullscreenObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // Short delay: wallpaper changes and window recreation can trigger
            // transient space-change notifications where isOnActiveSpace is briefly
            // unreliable. Let the window state settle before evaluating.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.evaluateVisibility()
            }
        }

        observeSettings()
        evaluateVisibility()

        // Track minimized windows (AX): clicking an app's dock tile restores them —
        // with the system Dock hidden, the tile click is how windows come back.
        MinimizedWindowTracker.shared.start()
        // (Screensaver idle-watch is started at app launch, not here — it must work even
        //  when the themed dock is off.)

        if autoHideActive {
            installAutoHideMonitors()
        }

        if AppSettings.shared.dockFix {
            DockFix.shared.start()
        }
    }

    /// Stop the dock. Pass `synchronous: true` from the quit path so the system-Dock restore
    /// completes before the process exits.
    func stop(synchronous: Bool = false) {
        print("[Dock] Stopping")
        removeAutoHideMonitors()
        DockFix.shared.stop()
        MinimizedWindowTracker.shared.stop()
        // (Screensaver idle-watch keeps running while the app lives; it is not tied to the dock.)
        // Un-hide any apps the Win98 "Show Desktop" tile hid — the tile is gone now.
        DockView.restoreShowDesktop()
        restoreSystemDock(synchronous: synchronous)
        DesktopIconsController.shared.hide()
        ProgramManagerController.shared.hide()
        SGIDesktopController.shared.hide()
        BeOSDeskbarController.shared.hide()
        // Restore menu bar and desktop icons
        if AppSettings.shared.hideMenuBar {
            SystemUIHelper.setMenuBarAutoHide(false)
        }
        if AppSettings.shared.hideDesktopIcons {
            SystemUIHelper.setDesktopIconsHidden(false)
        }
        unregisterHotkey()
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
        if let obs = fullscreenObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            fullscreenObserver = nil
        }
        settingsObservers.removeAll()
        window?.orderOut(nil)
        window = nil
        dockView = nil
        isVisible = false
        manualToggle = nil
        isStarted = false
    }

    func toggle() {
        if let manual = manualToggle {
            manualToggle = !manual
        } else {
            manualToggle = !isVisible
        }
        evaluateVisibility()
    }

    // MARK: - Window

    private func createWindow() {
        let screen = targetScreen()
        let dockView = DockView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        dockView.onContextMenu = { [weak self] bundleID, point in
            self?.showContextMenu(for: bundleID, at: point)
        }
        dockView.onDockContextMenu = { [weak self] point in
            self?.showDockPositionMenu(at: point)
        }
        dockView.onRunningAppsChanged = { [weak self] in
            self?.repositionWindow()
        }
        dockView.onControlStripToggle = { [weak self] collapsed in
            self?.animateControlStripToggle(collapsed: collapsed)
        }
        dockView.rebuildItems()

        let (width, height, magOverflow, hMagOverflow, dynScale) = calculateDockSize(dockView: dockView, screen: screen)
        let frame = dockFrame(screen: screen, width: width, height: height)

        let win = DockWindow(contentRect: frame)

        dockView.dynamicScale = dynScale
        dockView.horizontalMagOverflow = hMagOverflow
        dockView.frame = NSRect(origin: .zero, size: frame.size)
        dockView.magnificationOverflow = magOverflow
        if dynScale < 1.0 || hMagOverflow > 0 { dockView.rebuildItems() }
        win.contentView = dockView

        self.window = win
        self.dockView = dockView
    }

    private func recreateWindow() {
        let wasVisible = isVisible
        window?.orderOut(nil)
        window = nil
        dockView = nil

        // Dock-less themes (Windows 3.1 Program Manager): no dock bar, just overlays.
        let hidesDock = ThemeManager.shared.activeTheme?.config.hidesDock ?? false
        if hidesDock {
            isVisible = false
            DesktopIconsController.shared.update()
            ProgramManagerController.shared.update()
            SGIDesktopController.shared.update()
            BeOSDeskbarController.shared.update()
            return
        }

        // Switching to a dock theme — ensure desktop overlays are gone,
        // refresh desktop icons, and show the dock bar.
        ProgramManagerController.shared.hide()
        SGIDesktopController.shared.hide()
        BeOSDeskbarController.shared.hide()
        DesktopIconsController.shared.update()

        createWindow()
        // Use orderFront(nil) instead of show()'s orderFrontRegardless()
        // so the dock (level 24) stays below the shader overlay (level 25).
        repositionWindow()
        window?.orderFront(nil)
        isVisible = true
        // Re-apply unconditionally (not gated on !didHideSystemDock): the dock edge
        // may have changed (position override), so the system Dock must be re-placed
        // to a non-conflicting edge. applySystemDockPolicy() preserves the original
        // saved state (guarded by originalDockAutoHide == nil).
        if AppSettings.shared.dockHideSystemDock {
            applySystemDockPolicy()
        }
        _ = wasVisible
        // Re-evaluate after a short delay to avoid false fullscreen detection
        // on the newly created window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.evaluateVisibility()
        }
    }

    private func repositionWindow() {
        guard let window = window, let dockView = dockView else { return }
        let screen = targetScreen()

        // Temporarily reset dynamicScale to calculate ideal width
        dockView.dynamicScale = 1.0
        dockView.horizontalMagOverflow = 0
        let (width, height, magOverflow, hMagOverflow, dynScale) = calculateDockSize(dockView: dockView, screen: screen)

        let onScreen = dockFrame(screen: screen, width: width, height: height)
        // Respect auto-hide: if the dock is currently hidden, keep it parked
        // offscreen. Otherwise a background reposition (e.g. running-apps change,
        // screen-params change) would yank the hidden dock back into view.
        let frame = (autoHideActive && !autoHideVisible)
            ? offscreenFrame(onScreen, screen: screen)
            : onScreen
        // dockView is laid out at the on-screen size regardless of park position.
        window.setFrame(frame, display: true)
        dockView.dynamicScale = dynScale
        dockView.horizontalMagOverflow = hMagOverflow
        dockView.frame = NSRect(origin: .zero, size: onScreen.size)
        dockView.magnificationOverflow = magOverflow
        dockView.relayoutItems()
    }

    /// Calculate dock dimensions, clamping to screen width and computing dynamic scale if needed
    private func calculateDockSize(dockView: DockView, screen: NSScreen) -> (width: CGFloat, height: CGFloat, magOverflow: CGFloat, hMagOverflow: CGFloat, dynamicScale: CGFloat) {
        let idealWidth = dockView.requiredWidth()
        let theme = ThemeManager.shared.activeTheme?.config
        let scale = CGFloat(AppSettings.shared.dockIconScale)
        let dockBarHeight = (theme?.dock.height ?? 80) * scale
        let iconSize = (theme?.dock.iconSize ?? 64) * scale
        let isVert = theme?.isVertical ?? false
        let hasMag = (theme?.hasMagnification == true) && AppSettings.shared.dockMagnification
        let maxScale = theme?.magnificationMaxScale ?? 2.0

        var dynScale: CGFloat = 1.0

        // ── Vertical dock (left/right edge) ──────────────────────────────
        // The long axis is the screen HEIGHT; clamp the icon stack to fit so
        // icons never run off-screen (fixes Mountain Lion oversize too).
        if isVert {
            let maxLen = screen.visibleFrame.height - 16
            // Headroom (per side) so magnified icons can reflow apart (to avoid
            // overlap) and the end icons don't clip. Covers the worst-case one-sided
            // push when hovering an end icon.
            let vpadU = hasMag ? iconSize * (maxScale - 1.0) * 2.5 : 0
            let needed = idealWidth + 2 * vpadU
            if needed > maxLen { dynScale = maxLen / needed }
            let effectiveIconSize = iconSize * dynScale
            // Perpendicular pop-out room: icons grow toward the interior into this gap.
            // Extra-wide (×1.6) so the magnified icon clearly protrudes OUT of the bar
            // instead of just filling it — like a real Snow Leopard side dock.
            let pop: CGFloat = hasMag ? effectiveIconSize * (maxScale - 1.0) * 1.6 : 0
            let vpad = vpadU * dynScale
            let width = dockBarHeight * dynScale + pop
            let height = idealWidth * dynScale + 2 * vpad
            // magOverflow → perpendicular pop room; hMagOverflow → per-side length pad.
            return (width, height, pop, vpad, dynScale)
        }

        // ── Horizontal dock (bottom edge) ────────────────────────────────
        // Horizontal magnification overflow: extra space on each side for dock bar expansion
        let hMagOverflow: CGFloat = hasMag ? iconSize * (maxScale - 1.0) * 1.2 : 0

        // Calculate dynamic scale to fit screen
        let maxWidth = screen.visibleFrame.width - 20  // 10px margin each side
        let totalWidth = idealWidth + hMagOverflow * 2

        if theme?.isFullWidth != true && totalWidth > maxWidth {
            dynScale = maxWidth / totalWidth
        }

        let effectiveIconSize = iconSize * dynScale
        // Top overflow above the bar: magnification themes need room for popped icons;
        // hover-zoom themes (no magnification) need room too so the enlarged icon — and a
        // pellet/Pac-Man border — aren't clipped at the dock's top edge.
        let hoverScale = theme?.icon.hoverScale ?? 1.0
        let magOverflow: CGFloat = hasMag
            ? effectiveIconSize * (maxScale - 1.0)
            : max(0, effectiveIconSize * (hoverScale - 1.0))
        let effectiveHMagOverflow = hMagOverflow * dynScale
        let shortAxis = dockBarHeight * dynScale + magOverflow

        let width: CGFloat
        let height: CGFloat
        if theme?.isFullWidth == true {
            width = screen.frame.width
            height = shortAxis
        } else {
            width = min(idealWidth * dynScale + effectiveHMagOverflow * 2, maxWidth)
            height = shortAxis
        }

        return (width, height, magOverflow, effectiveHMagOverflow, dynScale)
    }

    private func dockFrame(screen: NSScreen, width: CGFloat, height: CGFloat) -> NSRect {
        let visible = screen.visibleFrame
        let config = ThemeManager.shared.activeTheme?.config
        let position = config?.effectiveDockPosition ?? "bottom"
        let alignment = config?.dockAlignment ?? "center"

        if config?.isVertical == true {
            // Vertical dock — flush against the left/right screen edge (no gap).
            let x = (position == "right") ? (visible.maxX - width) : visible.minX
            let y: CGFloat
            switch alignment {
            case "bottom": y = visible.minY
            case "top":    y = visible.maxY - height
            default:       y = visible.midY - height / 2
            }
            return NSRect(x: x, y: y, width: width, height: height)
        }

        // Horizontal dock — top or bottom edge
        let offset = config?.dockEdgeOffset ?? 8
        // Anchor the bottom edge to the PHYSICAL screen bottom (screen.frame.minY) so a
        // zero-offset dock sits flush against the edge. In the common case this equals
        // visibleFrame.minY (the menu bar only affects the top), so no regression.
        let yBottom = screen.frame.minY + offset
        let yTop = visible.maxY - height - offset
        let y = (position == "top") ? yTop : yBottom

        if config?.isFullWidth == true {
            let fullY = (position == "top") ? (screen.frame.maxY - height) : screen.frame.minY
            return NSRect(x: screen.frame.minX, y: fullY, width: screen.frame.width, height: height)
        }
        let x: CGFloat
        switch alignment {
        // Flush to the PHYSICAL screen edge (screen.frame), not visibleFrame — otherwise a
        // system Dock on the left/right pushes our dock inward and leaves a gap.
        case "left":  x = screen.frame.minX + offset
        case "right": x = screen.frame.maxX - width - offset
        default:      x = visible.midX - width / 2
        }
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func targetScreen() -> NSScreen {
        let displayID = AppSettings.shared.dockTargetDisplayID
        if displayID != 0,
           let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    // MARK: - Visibility

    private func dockLog(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(ts)] \(msg)\n"
        let logURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            .appendingPathComponent("retromac_dock.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    private func evaluateVisibility() {
        let settings = AppSettings.shared
        guard settings.dockEnabled else {
            dockLog("evaluateVisibility: dockEnabled=false → hide")
            hide()
            return
        }

        if let manual = manualToggle {
            dockLog("evaluateVisibility: manual=\(manual)")
            if manual { show() } else { hide() }
            return
        }

        if isFrontmostAppFullscreen() {
            dockLog("evaluateVisibility: fullscreen → hide (isOnActiveSpace=\(window?.isOnActiveSpace ?? false), isVisible=\(window?.isVisible ?? false), windowNum=\(window?.windowNumber ?? -1))")
            hide()
            return
        }

        // When auto-hide is active, don't force-show — let the mouse monitors handle it
        if autoHideActive {
            dockLog("evaluateVisibility: autoHide active, autoHideVisible=\(autoHideVisible)")
            if !autoHideVisible {
                // Position offscreen so it's ready to animate in
                hideOffscreen()
            }
            return
        }

        show()
    }

    private func show() {
        guard !isVisible else { return }
        repositionWindow()
        window?.orderFrontRegardless()
        isVisible = true
        if AppSettings.shared.dockHideSystemDock && !didHideSystemDock {
            applySystemDockPolicy()
        }
    }

    private func hide() {
        guard isVisible else { return }
        window?.orderOut(nil)
        isVisible = false
        autoHideVisible = false
        if didHideSystemDock {
            restoreSystemDock()
        }
    }

    // MARK: - Control Strip Collapse Animation

    /// Animate the Control Strip "reveal" like a roller blind unrolling left→right.
    /// The window instantly resizes to full, then a clip mask animates the reveal.
    private func animateControlStripToggle(collapsed: Bool) {
        guard let window = window, let dockView = dockView else { return }
        let screen = targetScreen()

        // First: recalculate layout at the target state
        dockView.dynamicScale = 1.0
        dockView.horizontalMagOverflow = 0
        let (width, height, magOverflow, hMagOverflow, dynScale) = calculateDockSize(dockView: dockView, screen: screen)
        let targetFrame = dockFrame(screen: screen, width: width, height: height)

        if collapsed {
            // Collapsing: animate clip from full width → left cap only, then resize window
            let startW = window.frame.width
            let endW = targetFrame.width
            dockView.wantsLayer = true
            let mask = CALayer()
            mask.backgroundColor = CGColor.white
            mask.frame = CGRect(x: 0, y: 0, width: startW, height: targetFrame.height)
            dockView.layer?.mask = mask

            CATransaction.begin()
            CATransaction.setAnimationDuration(0.35)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            CATransaction.setCompletionBlock {
                dockView.layer?.mask = nil
                window.setFrame(targetFrame, display: true)
                dockView.dynamicScale = dynScale
                dockView.horizontalMagOverflow = hMagOverflow
                dockView.frame = NSRect(origin: .zero, size: targetFrame.size)
                dockView.magnificationOverflow = magOverflow
                dockView.relayoutItems()
            }
            mask.frame = CGRect(x: 0, y: 0, width: endW, height: targetFrame.height)
            CATransaction.commit()

        } else {
            // Expanding: set window to full size immediately, then animate clip from left cap → full
            let leftCapW = dockView.controlStripLeftCapWidth
            window.setFrame(targetFrame, display: false)
            dockView.dynamicScale = dynScale
            dockView.horizontalMagOverflow = hMagOverflow
            dockView.frame = NSRect(origin: .zero, size: targetFrame.size)
            dockView.magnificationOverflow = magOverflow
            dockView.relayoutItems()

            // Set up clip mask starting at left cap width
            dockView.wantsLayer = true
            let mask = CALayer()
            mask.backgroundColor = CGColor.white
            mask.frame = CGRect(x: 0, y: 0, width: leftCapW, height: targetFrame.height)
            dockView.layer?.mask = mask

            // Force layout before animation
            CATransaction.flush()

            CATransaction.begin()
            CATransaction.setAnimationDuration(0.4)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            CATransaction.setCompletionBlock {
                dockView.layer?.mask = nil
            }
            mask.frame = CGRect(x: 0, y: 0, width: targetFrame.width, height: targetFrame.height)
            CATransaction.commit()
        }
    }

    // MARK: - Auto-Hide

    /// Auto-hide is active if the theme opts in (its original had it) or the global toggle is on.
    private var autoHideActive: Bool {
        if ThemeManager.shared.activeTheme?.config.dockAutoHideEnabled == true { return true }
        return AppSettings.shared.dockAutoHide
    }

    private func dockEdge() -> String {
        ThemeManager.shared.activeTheme?.config.effectiveDockPosition ?? "bottom"
    }

    /// Frame moved fully offscreen perpendicular to the dock's edge.
    private func offscreenFrame(_ frame: NSRect, screen: NSScreen) -> NSRect {
        var f = frame
        switch dockEdge() {
        case "top":   f.origin.y = screen.frame.maxY + frame.height
        case "left":  f.origin.x = screen.frame.minX - frame.width
        case "right": f.origin.x = screen.frame.maxX + frame.width
        default:      f.origin.y = screen.frame.minY - frame.height   // bottom
        }
        return f
    }

    /// Hot zone along the dock's edge that reveals the dock.
    private func autoHideTriggerZone(screen: NSScreen) -> NSRect {
        let t = autoHideTriggerHeight
        let sf = screen.frame
        switch dockEdge() {
        case "top":   return NSRect(x: sf.minX, y: sf.maxY - t, width: sf.width, height: t)
        case "left":  return NSRect(x: sf.minX, y: sf.minY, width: t, height: sf.height)
        case "right": return NSRect(x: sf.maxX - t, y: sf.minY, width: t, height: sf.height)
        default:      return NSRect(x: sf.minX, y: sf.minY, width: sf.width, height: t)
        }
    }

    /// Install or remove auto-hide based on current theme/global setting, then re-evaluate.
    func refreshAutoHide() {
        if autoHideActive {
            installAutoHideMonitors()
        } else {
            removeAutoHideMonitors()
            autoHideVisible = false
            let hidesDock = ThemeManager.shared.activeTheme?.config.hidesDock ?? false
            if isStarted, !hidesDock { show() }
        }
    }

    private func installAutoHideMonitors() {
        removeAutoHideMonitors()
        print("[Dock] Auto-hide monitors installed")

        // Start with dock hidden offscreen
        autoHideVisible = false
        hideOffscreen()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved()
            return event
        }
    }

    private func removeAutoHideMonitors() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }

    private func handleMouseMoved() {
        guard autoHideActive,
              AppSettings.shared.dockEnabled,
              manualToggle == nil || manualToggle == true,
              !isFrontmostAppFullscreen(),
              !autoHideAnimating else { return }

        let screen = targetScreen()
        let mouseLocation = NSEvent.mouseLocation
        let triggerZone = autoHideTriggerZone(screen: screen)

        if !autoHideVisible && triggerZone.contains(mouseLocation) {
            slideIn()
        } else if autoHideVisible, let dockFrame = window?.frame {
            let expandedFrame = dockFrame.insetBy(dx: -autoHideLeaveMargin, dy: -autoHideLeaveMargin)
            if !expandedFrame.contains(mouseLocation) {
                slideOut()
            }
        }
    }

    /// Position the dock window offscreen (perpendicular to its edge) without ordering out
    private func hideOffscreen() {
        guard let window = window else { return }
        let screen = targetScreen()
        window.setFrame(offscreenFrame(window.frame, screen: screen), display: false)
        window.orderFrontRegardless()
        isVisible = true  // Window is technically ordered in (for system dock policy) but offscreen
        autoHideVisible = false
    }

    private func slideIn() {
        guard !autoHideVisible, !autoHideAnimating else { return }
        autoHideAnimating = true
        // Mark visible first so repositionWindow() computes the on-screen target
        // (it parks the window offscreen while autoHideVisible is false).
        autoHideVisible = true

        repositionWindow()
        guard let window = window else {
            autoHideAnimating = false
            return
        }

        let targetFrame = window.frame
        let screen = targetScreen()

        // Start offscreen (perpendicular to the dock's edge)
        let startFrame = offscreenFrame(targetFrame, screen: screen)
        window.setFrame(startFrame, display: false)
        window.orderFrontRegardless()

        // Animate to target
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(targetFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.autoHideVisible = true
            self?.autoHideAnimating = false
            self?.isVisible = true
            if AppSettings.shared.dockHideSystemDock && !(self?.didHideSystemDock ?? false) {
                self?.applySystemDockPolicy()
            }
        })
    }

    private func slideOut() {
        guard autoHideVisible, !autoHideAnimating else { return }
        autoHideAnimating = true

        guard let window = window else {
            autoHideAnimating = false
            return
        }

        let screen = targetScreen()
        let off = offscreenFrame(window.frame, screen: screen)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(off, display: true)
        }, completionHandler: { [weak self] in
            self?.autoHideVisible = false
            self?.autoHideAnimating = false
        })
    }

    private func isFrontmostAppFullscreen() -> Bool {
        // When a fullscreen app is active it occupies its own Mission Control Space.
        // Our dock window lives on the desktop Space, so isOnActiveSpace returns false.
        // This replaces CGWindowListCopyWindowInfo which requires Screen Recording
        // permission (TCC) on macOS 15+ and triggered a dialog on every launch.
        guard let dockWindow = window else { return false }
        // A newly created window may briefly report isOnActiveSpace = false before
        // it is fully ordered on screen. Only trust the check if the window is visible.
        guard dockWindow.isVisible || isVisible else { return false }
        return !dockWindow.isOnActiveSpace
    }

    // MARK: - Settings

    private func observeSettings() {
        let s = AppSettings.shared

        s.$dockEnabled.dropFirst().sink { [weak self] enabled in
            if enabled { self?.start() } else { self?.stop() }
        }.store(in: &settingsObservers)

        s.$dockTheme.dropFirst().sink { [weak self] newTheme in
            // @Published fires in willSet (before the value is stored) — and this is invoked
            // straight from the SwiftUI theme-picker mutation. Doing the heavy theme switch
            // (reload + window rebuild + splash) synchronously here re-enters the SwiftUI
            // update and drops the tile click (the card "loses focus" / needs several tries).
            // Defer to the next runloop tick so the click completes first, like the handlers below.
            DispatchQueue.main.async {
                ThemeManager.shared.reload(selectTheme: newTheme)
                ThemeManager.shared.clearCache()
                // "Dock only": restyle the Dock without touching the desktop wallpaper or
                // showing the theme's boot splash (those are whole-system changes).
                if AppSettings.shared.dockOnly {
                    ThemeManager.shared.restoreWallpapers()
                } else {
                    ThemeManager.shared.applyWallpaper()
                }
                AppManager.shared.syncAutoDownloads(active: ThemeManager.shared.activeTheme?.config.hasFolderStacks == true && AppSettings.shared.dockShowDownloads)
                if !AppSettings.shared.dockOnly, let theme = ThemeManager.shared.activeTheme {
                    SplashController.shared.showIfEnabled(for: theme)
                }
                self?.recreateWindow()
                // Note: no .dockThemeChanged post needed — recreateWindow() already
                // creates a fresh DockView with the new theme's layout.
            }
        }.store(in: &settingsObservers)

        // NOTE: @Published fires in willSet — BEFORE the new value is stored. These
        // handlers re-read the property (effectiveDockPosition / dockAutoHideEnabled),
        // so they must run on the NEXT runloop tick, once the value is committed.
        // Otherwise every change is applied one step late (stale read).
        s.$themeDockPositionOverride.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.recreateWindow() }
        }.store(in: &settingsObservers)

        s.$themeDockAutoHide.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshAutoHide()
                self?.evaluateVisibility()
            }
        }.store(in: &settingsObservers)

        s.$dockTransparency.dropFirst().sink { [weak self] _ in
            self?.dockView?.needsDisplay = true
        }.store(in: &settingsObservers)

        s.$dockTargetDisplayID.dropFirst().sink { [weak self] _ in
            self?.repositionWindow()
        }.store(in: &settingsObservers)

        s.$dockIconScale.dropFirst().sink { [weak self] _ in
            ThemeManager.shared.clearCache()
            self?.recreateWindow()
        }.store(in: &settingsObservers)

        s.$dockShowRunningApps.dropFirst().sink { [weak self] _ in
            self?.repositionWindow()
        }.store(in: &settingsObservers)

        s.$dockShowDownloads.dropFirst().sink { [weak self] show in
            let active = (ThemeManager.shared.activeTheme?.config.hasFolderStacks == true) && show
            AppManager.shared.syncAutoDownloads(active: active)
            self?.recreateWindow()
        }.store(in: &settingsObservers)

        s.$dockMagnification.dropFirst().sink { [weak self] _ in
            self?.recreateWindow()
        }.store(in: &settingsObservers)

        s.$themeOrientationOverrides.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.recreateWindow() }
        }.store(in: &settingsObservers)

        s.$dockFix.dropFirst().sink { enabled in
            if enabled { DockFix.shared.start() } else { DockFix.shared.stop() }
        }.store(in: &settingsObservers)

        s.$dockAutoHide.dropFirst().sink { [weak self] enabled in
            if enabled {
                self?.installAutoHideMonitors()
            } else {
                self?.removeAutoHideMonitors()
                self?.autoHideVisible = false
                // Show dock immediately when auto-hide is disabled
                self?.isVisible = false  // Reset so show() works
                self?.evaluateVisibility()
            }
        }.store(in: &settingsObservers)

        s.$dockHideSystemDock.dropFirst().sink { [weak self] _ in
            self?.applySystemDockPolicy()
        }.store(in: &settingsObservers)
    }

    // MARK: - System Dock

    private func applySystemDockPolicy() {
        let shouldHide = AppSettings.shared.dockHideSystemDock
        if shouldHide {
            if originalDockAutoHide == nil {
                originalDockAutoHide = readSystemDockPref("autohide") == "1"
                originalDockPosition = readSystemDockPref("orientation") ?? "bottom"
                originalMinimizeToApp = readSystemDockPref("minimize-to-application") == "1"
                originalMinEffect = readSystemDockPref("mineffect") ?? "genie"
                originalAutohideDelay = readSystemDockPref("autohide-delay")
                print("[Dock] Saved original dock state: autohide=\(originalDockAutoHide ?? false), position=\(originalDockPosition ?? "bottom")")
            }
            // Move the real macOS Dock to a DIFFERENT screen edge than RetroMac's
            // dock so the two never "double up" on the same edge. macOS only
            // supports left/bottom/right for the Dock orientation (no top), so we
            // map RetroMac's effective edge to a non-conflicting system edge.
            // Use effectiveDockPosition so a user position override (context menu)
            // is honored, not just the theme's baked-in default.
            let themePos = ThemeManager.shared.activeTheme?.config.effectiveDockPosition ?? "bottom"
            let hidePosition = systemDockEdge(forThemeEdge: themePos)
            // Idempotent on INTENT: if we already intend the Dock hidden on this same edge,
            // do nothing — recreateWindow() calls this on every theme switch and re-running
            // `killall Dock` would restore all minimized windows. (Intent-based so a
            // restore→hide sequence still re-applies.)
            if didHideSystemDock && lastAppliedHidePosition == hidePosition { return }
            // Set intent immediately; a generation token guards the async commit so a stale
            // in-flight restore can't flip the Dock back on after this hide.
            didHideSystemDock = true
            lastAppliedHidePosition = hidePosition
            persistDockRecoveryState()
            dockOpGeneration += 1
            let gen = dockOpGeneration
            DockController.dockPrefsQueue.async { [weak self] in
                let ok = self?.setSystemDockPrefs(autohide: true, position: hidePosition,
                                                  minimizeToApp: true, minEffect: "scale",
                                                  autohideDelay: "1000000") ?? false
                DispatchQueue.main.async {
                    guard let self = self, gen == self.dockOpGeneration else { return }  // superseded
                    if !ok {
                        // Partial/failed hide — KEEP the recovery keys + captured original state so a
                        // later restore / quit / relaunch can put the Dock back (the Dock may be left
                        // half-modified). Re-assert intent and reset the idempotency guard so the next
                        // attempt re-applies. Recovery data is only discarded after a CONFIRMED restore.
                        self.didHideSystemDock = true
                        self.lastAppliedHidePosition = nil
                        print("[Dock] ⚠️ System dock hide failed/partial — keeping recovery keys for retry")
                    }
                }
            }
            print("[Dock] System dock moving to \(hidePosition) + auto-hide (theme dock is \(themePos))")
        } else if didHideSystemDock {
            restoreSystemDock()
        }
    }

    /// Serial queue for the `defaults`/`killall Dock` shell-outs so they never block the
    /// main thread during theme/dock switches.
    private static let dockPrefsQueue = DispatchQueue(label: "com.retromac.dock-prefs")

    /// Persist the saved original system-Dock state for crash recovery.
    private func persistDockRecoveryState() {
        let d = UserDefaults.standard
        d.set(true, forKey: "sysDockHidden")
        d.set(originalDockAutoHide ?? false, forKey: "sysDockOrigAutohide")
        d.set(originalDockPosition ?? "bottom", forKey: "sysDockOrigPosition")
        d.set(originalMinimizeToApp ?? false, forKey: "sysDockOrigMinToApp")
        d.set(originalMinEffect ?? "genie", forKey: "sysDockOrigMinEffect")
        if let v = originalAutohideDelay { d.set(v, forKey: "sysDockOrigAutohideDelay") }
        else { d.removeObject(forKey: "sysDockOrigAutohideDelay") }
    }

    /// The system Dock stays on the SAME edge as RetroMac's dock (it is auto-hidden
    /// with a huge autohide-delay, so it never reveals): the minimize animation then
    /// points at our dock's location instead of flying off to another screen edge.
    /// macOS Dock orientation only supports "left", "bottom", "right" (no top).
    private func systemDockEdge(forThemeEdge themeEdge: String) -> String {
        switch themeEdge {
        case "bottom": return "bottom"
        case "left":   return "left"
        case "right":  return "right"
        case "top":    return "bottom"
        default:       return "bottom"
        }
    }

    /// Restore the system Dock to its saved state. Runs off-main by default (so it never
    /// hangs an interactive theme/dock switch); pass `synchronous: true` from the quit path,
    /// where the process must not exit before the `defaults` writes have completed.
    /// The recovery keys are only cleared on SUCCESS — a failed restore is retried next time.
    private func restoreSystemDock(synchronous: Bool = false) {
        guard didHideSystemDock else { return }
        let restoreHide = originalDockAutoHide ?? false
        let restorePos = originalDockPosition ?? "bottom"
        let minToApp = originalMinimizeToApp ?? false
        let minEffect = originalMinEffect ?? "genie"
        let delay = originalAutohideDelay
        let deleteDelay = originalAutohideDelay == nil

        // Drop the hide INTENT immediately so a fast re-hide that arrives before this
        // completes won't be skipped by the idempotency guard.
        didHideSystemDock = false
        lastAppliedHidePosition = nil
        dockOpGeneration += 1
        let gen = dockOpGeneration

        let apply: () -> Bool = { [weak self] in
            self?.setSystemDockPrefs(autohide: restoreHide, position: restorePos,
                                     minimizeToApp: minToApp, minEffect: minEffect,
                                     autohideDelay: delay, deleteAutohideDelay: deleteDelay) ?? false
        }
        let onDone: (Bool) -> Void = { [weak self] ok in
            guard let self = self, gen == self.dockOpGeneration else { return }  // superseded by a newer op
            if ok {
                self.originalDockAutoHide = nil
                self.originalDockPosition = nil
                self.originalMinimizeToApp = nil
                self.originalMinEffect = nil
                self.originalAutohideDelay = nil
                self.clearPersistedDockState()
                print("[Dock] System dock restored (autohide=\(restoreHide), position=\(restorePos))")
            } else {
                // Restore failed → the Dock is still hidden; re-assert intent so a later
                // restore (or quit) retries, and keep the recovery keys.
                self.didHideSystemDock = true
                print("[Dock] ⚠️ System dock restore failed — keeping recovery keys for retry")
            }
        }

        if synchronous {
            // Serialize on the prefs queue so any in-flight hide finishes FIRST — otherwise a
            // pending hide could run after this restore and leave the system Dock hidden after quit.
            let ok = DockController.dockPrefsQueue.sync { apply() }
            onDone(ok)
        } else {
            DockController.dockPrefsQueue.async {
                let ok = apply()
                DispatchQueue.main.async { onDone(ok) }
            }
        }
    }

    private func clearPersistedDockState() {
        let d = UserDefaults.standard
        d.removeObject(forKey: "sysDockHidden")
        d.removeObject(forKey: "sysDockOrigAutohide")
        d.removeObject(forKey: "sysDockOrigPosition")
        d.removeObject(forKey: "sysDockOrigMinToApp")
        d.removeObject(forKey: "sysDockOrigMinEffect")
        d.removeObject(forKey: "sysDockOrigAutohideDelay")
    }

    /// Crash recovery: if a previous session left the system dock hidden (force-quit /
    /// crash before restore), put it back. Safe to call at launch — the theme dock
    /// always starts disabled, so the system dock should be in its original state.
    func restoreSystemDockIfNeeded() {
        let d = UserDefaults.standard
        guard d.bool(forKey: "sysDockHidden") else { return }
        let restoreHide = d.bool(forKey: "sysDockOrigAutohide")
        let restorePos = d.string(forKey: "sysDockOrigPosition") ?? "bottom"
        // Older persisted states may lack the minimize keys — only restore when saved.
        let isNewState = d.object(forKey: "sysDockOrigMinToApp") != nil
        let minToApp = isNewState ? d.bool(forKey: "sysDockOrigMinToApp") : nil
        let minEffect = d.string(forKey: "sysDockOrigMinEffect")
        let delay = d.string(forKey: "sysDockOrigAutohideDelay")
        let ok = setSystemDockPrefs(autohide: restoreHide, position: restorePos,
                                    minimizeToApp: minToApp, minEffect: minEffect,
                                    autohideDelay: delay,
                                    deleteAutohideDelay: isNewState && delay == nil)
        guard ok else {
            print("[Dock] ⚠️ System dock recovery failed — keeping recovery keys for next launch")
            return
        }
        didHideSystemDock = false
        lastAppliedHidePosition = nil
        originalDockAutoHide = nil
        originalDockPosition = nil
        clearPersistedDockState()
        print("[Dock] Recovered system dock from previous session (autohide=\(restoreHide), position=\(restorePos))")
    }

    private func readSystemDockPref(_ key: String) -> String? {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "com.apple.dock", key]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Writes the given system-Dock prefs and restarts the Dock. Returns `true` only if every
    /// `defaults` write succeeded (terminationStatus 0) — callers clear recovery state only on
    /// success. Synchronous: callers wrap it in `dockPrefsQueue` to stay off the main thread.
    @discardableResult
    private func setSystemDockPrefs(autohide: Bool, position: String,
                                    minimizeToApp: Bool? = nil, minEffect: String? = nil,
                                    autohideDelay: String? = nil, deleteAutohideDelay: Bool = false) -> Bool {
        var ok = true
        /// Run one `defaults` invocation; track failure unless it's an ignorable delete.
        func defaultsWrite(_ args: [String], ignoreFailure: Bool = false) {
            let w = Process()
            w.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            w.arguments = args
            if ignoreFailure { w.standardError = FileHandle.nullDevice }
            do {
                try w.run(); w.waitUntilExit()
                if !ignoreFailure && w.terminationStatus != 0 { ok = false }
            } catch { if !ignoreFailure { ok = false } }
        }

        if let delay = autohideDelay {
            defaultsWrite(["write", "com.apple.dock", "autohide-delay", "-float", delay])
        } else if deleteAutohideDelay {
            // The key may not exist — a non-zero status here is expected, not a failure.
            defaultsWrite(["delete", "com.apple.dock", "autohide-delay"], ignoreFailure: true)
        }
        if let m = minimizeToApp {
            defaultsWrite(["write", "com.apple.dock", "minimize-to-application", "-bool", m ? "true" : "false"])
        }
        if let e = minEffect {
            defaultsWrite(["write", "com.apple.dock", "mineffect", "-string", e])
        }
        defaultsWrite(["write", "com.apple.dock", "autohide", "-bool", autohide ? "true" : "false"])
        defaultsWrite(["write", "com.apple.dock", "orientation", "-string", position])

        // Restart the Dock so the prefs take effect; a failed restart means the change
        // hasn't been applied yet, so don't report success (callers keep recovery state).
        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["Dock"]
        do {
            try killall.run(); killall.waitUntilExit()
            if killall.terminationStatus != 0 { ok = false }
        } catch { ok = false }
        return ok
    }

    /// Returns the current dock window frame in screen coordinates (for DockFix)
    func currentDockFrame() -> NSRect? {
        guard isVisible else { return nil }
        return window?.frame
    }

    // MARK: - Context Menu

    /// Right-click on the dock background → move the dock to any edge + auto-hide toggle.
    private func showDockPositionMenu(at point: NSPoint) {
        guard let dockView = dockView else { return }
        let menu = NSMenu()
        // Title row (so the menu isn't empty-looking)
        let header = NSMenuItem(title: "Dock", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        appendDockPositionItems(to: menu)
        menu.popUp(positioning: nil, at: point, in: dockView)
    }

    @objc private func menuSetDockPosition(_ sender: NSMenuItem) {
        guard let pos = sender.representedObject as? String,
              let name = ThemeManager.shared.activeTheme?.config.name else { return }
        AppSettings.shared.themeDockPositionOverride[name] = pos
    }

    @objc private func menuToggleAutoHide(_ sender: NSMenuItem) {
        guard let name = ThemeManager.shared.activeTheme?.config.name else { return }
        let current = AppSettings.shared.themeDockAutoHide[name] ?? false
        AppSettings.shared.themeDockAutoHide[name] = !current
    }

    private func showContextMenu(for bundleID: String, at point: NSPoint) {
        let menu = NSMenu()

        // URL launcher tile: open + edit the target URL
        if bundleID == "__urllauncher__" {
            let open = NSMenuItem(title: "Open Link", action: #selector(menuOpenURLLauncher(_:)), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
            menu.addItem(.separator())
            let setURL = NSMenuItem(title: "Change URL…", action: #selector(menuSetURLLauncher(_:)), keyEquivalent: "")
            setURL.target = self
            menu.addItem(setURL)
            if let window = window {
                window.makeKeyAndOrderFront(nil)
                let localPoint = window.convertPoint(fromScreen: point)
                menu.popUp(positioning: nil, at: localPoint, in: window.contentView)
            }
            return
        }

        // Trash has its own context menu
        if bundleID == "__trash__" {
            let openTrash = NSMenuItem(title: "Open Trash", action: #selector(menuOpenTrash(_:)), keyEquivalent: "")
            openTrash.target = self
            menu.addItem(openTrash)

            menu.addItem(.separator())

            let emptyTrash = NSMenuItem(title: "Empty Trash...", action: #selector(menuEmptyTrash(_:)), keyEquivalent: "")
            emptyTrash.target = self
            menu.addItem(emptyTrash)

            if let window = window {
                window.makeKeyAndOrderFront(nil)
                let localPoint = window.convertPoint(fromScreen: point)
                menu.popUp(positioning: nil, at: localPoint, in: window.contentView)
            }
            return
        }

        let isRunning = AppLauncher.isRunning(bundleID: bundleID)
        let isPinned = AppManager.shared.apps.contains(where: { $0.bundleID == bundleID })

        if isRunning {
            let activate = NSMenuItem(title: "Bring to Front", action: #selector(menuActivate(_:)), keyEquivalent: "")
            activate.target = self
            activate.representedObject = bundleID
            menu.addItem(activate)

            menu.addItem(.separator())

            let quit = NSMenuItem(title: "Quit", action: #selector(menuQuit(_:)), keyEquivalent: "")
            quit.target = self
            quit.representedObject = bundleID
            menu.addItem(quit)

            let forceQuit = NSMenuItem(title: "Force Quit", action: #selector(menuForceQuit(_:)), keyEquivalent: "")
            forceQuit.target = self
            forceQuit.representedObject = bundleID
            menu.addItem(forceQuit)
        } else {
            let open = NSMenuItem(title: "Open", action: #selector(menuOpen(_:)), keyEquivalent: "")
            open.target = self
            open.representedObject = bundleID
            menu.addItem(open)
        }

        menu.addItem(.separator())

        let finder = NSMenuItem(title: "Show in Finder", action: #selector(menuShowInFinder(_:)), keyEquivalent: "")
        finder.target = self
        finder.representedObject = bundleID
        menu.addItem(finder)

        let changeIcon = NSMenuItem(title: "Change Icon...", action: #selector(menuChangeIcon(_:)), keyEquivalent: "")
        changeIcon.target = self
        changeIcon.representedObject = bundleID
        menu.addItem(changeIcon)

        menu.addItem(.separator())

        if isPinned {
            let remove = NSMenuItem(title: "Remove from Dock", action: #selector(menuRemove(_:)), keyEquivalent: "")
            remove.target = self
            remove.representedObject = bundleID
            menu.addItem(remove)
        } else {
            let add = NSMenuItem(title: "Add to Dock", action: #selector(menuAddToDock(_:)), keyEquivalent: "")
            add.target = self
            add.representedObject = bundleID
            menu.addItem(add)
        }

        appendDockPositionItems(to: menu)

        if let window = window {
            window.makeKeyAndOrderFront(nil)
            let localPoint = window.convertPoint(fromScreen: point)
            menu.popUp(positioning: nil, at: localPoint, in: window.contentView)
        }
    }

    /// Adds the "Dock Position ▸" submenu (+ Auto-Hide) to any dock context menu.
    private func appendDockPositionItems(to menu: NSMenu) {
        guard let theme = ThemeManager.shared.activeTheme?.config else { return }
        menu.addItem(.separator())
        let current = theme.effectiveDockPosition
        let posTitle = NSMenuItem(title: "Dock Position", action: nil, keyEquivalent: "")
        let posMenu = NSMenu()
        // Windows XP taskbar is bottom-only — hide the left/right options for that theme.
        let isXP = theme.name.lowercased().contains("windows xp") || theme.name.lowercased().contains("xp")
        var positions = [("Bottom", "bottom"), ("Left", "left"), ("Right", "right")]
        if isXP { positions = [("Bottom", "bottom")] }
        for (label, value) in positions {
            let mi = NSMenuItem(title: label, action: #selector(menuSetDockPosition(_:)), keyEquivalent: "")
            mi.target = self; mi.representedObject = value
            if value == current { mi.state = .on }
            posMenu.addItem(mi)
        }
        posTitle.submenu = posMenu
        menu.addItem(posTitle)
        if theme.supportsAutoHide {
            let ah = NSMenuItem(title: "Auto-Hide Dock", action: #selector(menuToggleAutoHide(_:)), keyEquivalent: "")
            ah.target = self
            ah.state = theme.dockAutoHideEnabled ? .on : .off
            menu.addItem(ah)
        }
        // App-level actions on every dock context menu.
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "RetroMac Settings…", action: #selector(menuRetroMacSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit RetroMac", action: #selector(menuQuitRetroMac), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func menuRetroMacSettings() {
        NSApp.sendAction(Selector(("openSettings")), to: nil, from: nil)
    }
    @objc private func menuQuitRetroMac() {
        // Route through AppDelegate.quitApp so cleanup (wallpaper/dock/menu-bar restore) runs.
        if !NSApp.sendAction(Selector(("quitApp")), to: nil, from: nil) {
            NSApp.terminate(nil)
        }
    }

    @objc private func menuActivate(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        AppLauncher.launchOrActivate(bundleID: bid)
    }

    @objc private func menuOpen(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        AppLauncher.launchOrActivate(bundleID: bid)
    }

    @objc private func menuQuit(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        AppLauncher.terminate(bundleID: bid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.dockView?.updateRunningIndicators()
        }
    }

    @objc private func menuForceQuit(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }

        let appName: String
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            appName = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        } else {
            appName = bid
        }

        let alert = NSAlert()
        alert.messageText = "Force Quit \"\(appName)\"?"
        alert.informativeText = "Unsaved changes may be lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Force Quit")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        AppLauncher.forceTerminate(bundleID: bid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.dockView?.updateRunningIndicators()
        }
    }

    @objc private func menuShowInFinder(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        AppLauncher.showInFinder(bundleID: bid)
    }

    @objc private func menuChangeIcon(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        showIconPicker(for: bid)
    }

    private func showIconPicker(for bundleID: String) {
        guard let theme = ThemeManager.shared.activeTheme else {
            browseCustomIcon(for: bundleID)
            return
        }
        let themeIcons = theme.availableIcons()
        if themeIcons.isEmpty {
            browseCustomIcon(for: bundleID)
            return
        }

        // Build a menu-based icon picker showing theme icons + browse option
        let menu = NSMenu(title: "Choose Icon")

        // Header
        let header = NSMenuItem(title: "Theme Icons (\(theme.name))", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Theme icons in a grid-like list
        for iconInfo in themeIcons {
            let item = NSMenuItem(title: iconInfo.name, action: #selector(menuPickThemeIcon(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [bundleID, iconInfo.url.path]

            // Load thumbnail
            if let img = NSImage(contentsOf: iconInfo.url) {
                img.size = NSSize(width: 20, height: 20)
                item.image = img
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let browseItem = NSMenuItem(title: "Browse...", action: #selector(menuBrowseIcon(_:)), keyEquivalent: "")
        browseItem.target = self
        browseItem.representedObject = bundleID
        browseItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(browseItem)

        // Reset option if there's a custom override
        if ThemeManager.shared.customIconPath(for: bundleID) != nil {
            let resetItem = NSMenuItem(title: "Reset to Default", action: #selector(menuResetIcon(_:)), keyEquivalent: "")
            resetItem.target = self
            resetItem.representedObject = bundleID
            resetItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
            menu.addItem(resetItem)
        }

        if let window = window {
            window.makeKeyAndOrderFront(nil)
            let mousePos = window.mouseLocationOutsideOfEventStream
            menu.popUp(positioning: nil, at: mousePos, in: window.contentView)
        }
    }

    @objc private func menuPickThemeIcon(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String],
              info.count == 2 else { return }
        let bundleID = info[0]
        let iconPath = info[1]
        ThemeManager.shared.setCustomIcon(for: bundleID, path: iconPath)
        dockView?.rebuildItems()
    }

    @objc private func menuBrowseIcon(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        browseCustomIcon(for: bid)
    }

    @objc private func menuResetIcon(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        ThemeManager.shared.setCustomIcon(for: bid, path: nil)
        dockView?.rebuildItems()
    }

    private func browseCustomIcon(for bundleID: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .icns, .tiff, .jpeg]
        panel.message = "Choose a custom icon for current theme"
        panel.prompt = "Set Icon"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ThemeManager.shared.setCustomIcon(for: bundleID, path: url.path)
        dockView?.rebuildItems()
    }

    @objc private func menuRemove(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        AppManager.shared.removeApp(bundleID: bid)
        repositionWindow()
    }

    @objc private func menuAddToDock(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        AppManager.shared.addApp(bundleID: bid)
        repositionWindow()
    }

    @objc private func menuOpenTrash(_ sender: NSMenuItem) {
        if let trashURL = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            NSWorkspace.shared.open(trashURL)
        }
    }

    @objc private func menuEmptyTrash(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Empty Trash?"
        alert.informativeText = "All items in the Trash will be permanently deleted. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Use NSAppleScript to empty trash (same as Finder)
        let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error = error {
            print("[Dock] Empty trash failed: \(error)")
        } else {
            print("[Dock] Trash emptied")
            // Refresh trash icon
            dockView?.rebuildItems()
        }
    }

    @objc private func menuOpenURLLauncher(_ sender: NSMenuItem) {
        if let u = URL(string: DockView.urlLauncherURL) { NSWorkspace.shared.open(u) }
    }

    @objc private func menuSetURLLauncher(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Change Link URL"
        alert.informativeText = "Enter the URL to open when the dock tile is clicked:"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = DockView.urlLauncherURL
        field.placeholderString = DockView.urlLauncherDefault
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var s = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = DockView.urlLauncherDefault }
        if !s.contains("://") { s = "https://" + s }
        UserDefaults.standard.set(s, forKey: "urlLauncherURL")
    }

    // MARK: - Hotkey

    private func registerHotkey() {
        unregisterHotkey()
        let settings = AppSettings.shared
        // Only register if a valid hotkey is configured: must have at least one
        // system modifier (Cmd/Ctrl/Opt/Shift). A bare key without modifier would
        // hijack normal typing (e.g. code=0 mods=0 = the "a" key).
        guard settings.dockHotkeyModifiers != 0 else {
            print("[Dock] No valid hotkey configured — skipping registration")
            return
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x524D444B), id: 2) // "RMDK"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            settings.dockHotkeyCode, settings.dockHotkeyModifiers,
            hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr {
            hotKeyRef = ref
            print("[Dock] Hotkey registered")
        }

        if eventHandlerRef == nil {
            var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(
                GetApplicationEventTarget(),
                { (_, event, userData) -> OSStatus in
                    guard let userData = userData, let event = event else { return OSStatus(eventNotHandledErr) }
                    var hotKeyID = EventHotKeyID()
                    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID),
                                      nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                    if hotKeyID.id == 2 {
                        let ctrl = Unmanaged<DockController>.fromOpaque(userData).takeUnretainedValue()
                        DispatchQueue.main.async { ctrl.toggle() }
                        return noErr
                    }
                    return OSStatus(eventNotHandledErr)
                },
                1, &eventSpec, selfPtr, &eventHandlerRef
            )
        }
    }

    private func unregisterHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
