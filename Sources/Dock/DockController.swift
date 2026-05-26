import AppKit
import Carbon.HIToolbox
import Combine

final class DockController {
    static let shared = DockController()

    private var window: DockWindow?
    private var dockView: DockView?
    private var screenObserver: NSObjectProtocol?
    private var fullscreenObserver: NSObjectProtocol?
    private var settingsObservers: [AnyCancellable] = []
    private var isVisible = false
    private var manualToggle: Bool?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var didHideSystemDock = false
    private var originalDockAutoHide: Bool?
    private var originalDockPosition: String?

    // Auto-hide state
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var autoHideVisible = false
    private var autoHideAnimating = false
    private let autoHideTriggerHeight: CGFloat = 5    // px from screen bottom to trigger show
    private let autoHideLeaveMargin: CGFloat = 20     // px above dock to trigger hide

    func start() {
        guard window == nil else { return }
        print("[Dock] Starting")

        ThemeManager.shared.reload()
        createWindow()
        registerHotkey()
        applySystemDockPolicy()
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
            self?.evaluateVisibility()
        }

        observeSettings()
        evaluateVisibility()

        if AppSettings.shared.dockAutoHide {
            installAutoHideMonitors()
        }

        if AppSettings.shared.dockFix {
            DockFix.shared.start()
        }
    }

    func stop() {
        print("[Dock] Stopping")
        removeAutoHideMonitors()
        DockFix.shared.stop()
        restoreSystemDock()
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
        dockView.onRunningAppsChanged = { [weak self] in
            self?.repositionWindow()
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
        createWindow()
        if wasVisible {
            // Use orderFront(nil) instead of show()'s orderFrontRegardless()
            // so the dock (level 24) stays below the shader overlay (level 25).
            repositionWindow()
            window?.orderFront(nil)
            isVisible = true
            if AppSettings.shared.dockHideSystemDock && !didHideSystemDock {
                applySystemDockPolicy()
            }
        }
    }

    private func repositionWindow() {
        guard let window = window, let dockView = dockView else { return }
        let screen = targetScreen()

        // Temporarily reset dynamicScale to calculate ideal width
        dockView.dynamicScale = 1.0
        dockView.horizontalMagOverflow = 0
        let (width, height, magOverflow, hMagOverflow, dynScale) = calculateDockSize(dockView: dockView, screen: screen)

        let frame = dockFrame(screen: screen, width: width, height: height)
        window.setFrame(frame, display: true)
        dockView.dynamicScale = dynScale
        dockView.horizontalMagOverflow = hMagOverflow
        dockView.frame = NSRect(origin: .zero, size: frame.size)
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

        // Horizontal magnification overflow: extra space on each side for dock bar expansion
        let hMagOverflow: CGFloat = hasMag
            ? iconSize * ((theme?.magnificationMaxScale ?? 2.0) - 1.0) * 1.2
            : 0

        // Calculate dynamic scale to fit screen
        var dynScale: CGFloat = 1.0
        let maxWidth = screen.visibleFrame.width - 20  // 10px margin each side
        let totalWidth = idealWidth + hMagOverflow * 2

        if !isVert && theme?.isFullWidth != true && totalWidth > maxWidth {
            dynScale = maxWidth / totalWidth
        }

        let effectiveIconSize = iconSize * dynScale
        let magOverflow: CGFloat = hasMag
            ? effectiveIconSize * ((theme?.magnificationMaxScale ?? 2.0) - 1.0)
            : 0
        let effectiveHMagOverflow = hMagOverflow * dynScale
        let shortAxis = dockBarHeight * dynScale + magOverflow

        let width: CGFloat
        let height: CGFloat
        if isVert {
            width = shortAxis
            height = idealWidth
        } else if theme?.isFullWidth == true {
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
        if config?.isVertical == true {
            let offset = config?.dockEdgeOffset ?? 4
            let alignment = config?.dockAlignment ?? "center"
            let x = visible.minX + offset
            let y: CGFloat
            switch alignment {
            case "bottom":
                y = visible.minY + offset
            case "top":
                y = visible.maxY - height - offset
            default: // center
                y = visible.midY - height / 2
            }
            return NSRect(x: x, y: y, width: width, height: height)
        }
        if config?.isFullWidth == true {
            return NSRect(x: screen.frame.minX, y: visible.minY, width: screen.frame.width, height: height)
        }
        let offset = config?.dockEdgeOffset ?? 8
        let alignment = config?.dockAlignment ?? "center"
        let x: CGFloat
        switch alignment {
        case "left":
            x = visible.minX + offset
        case "right":
            x = visible.maxX - width - offset
        default:
            x = visible.midX - width / 2
        }
        let y = visible.minY + offset
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

    private func evaluateVisibility() {
        let settings = AppSettings.shared
        guard settings.dockEnabled else {
            hide()
            return
        }

        if let manual = manualToggle {
            if manual { show() } else { hide() }
            return
        }

        if isFrontmostAppFullscreen() {
            hide()
            return
        }

        // When auto-hide is active, don't force-show — let the mouse monitors handle it
        if settings.dockAutoHide {
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

    // MARK: - Auto-Hide

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
        guard AppSettings.shared.dockAutoHide,
              AppSettings.shared.dockEnabled,
              manualToggle == nil || manualToggle == true,
              !isFrontmostAppFullscreen(),
              !autoHideAnimating else { return }

        let screen = targetScreen()
        let mouseLocation = NSEvent.mouseLocation
        let config = ThemeManager.shared.activeTheme?.config

        if config?.isVertical == true {
            // Vertical dock: trigger on left edge
            let triggerZone = NSRect(
                x: screen.frame.minX,
                y: screen.frame.minY,
                width: autoHideTriggerHeight,
                height: screen.frame.height
            )
            if !autoHideVisible && triggerZone.contains(mouseLocation) {
                slideIn()
            } else if autoHideVisible, let dockFrame = window?.frame {
                let expandedFrame = dockFrame.insetBy(dx: -autoHideLeaveMargin, dy: -autoHideLeaveMargin)
                if !expandedFrame.contains(mouseLocation) {
                    slideOut()
                }
            }
        } else {
            // Horizontal dock (bottom): trigger on bottom edge
            let triggerZone = NSRect(
                x: screen.frame.minX,
                y: screen.frame.minY,
                width: screen.frame.width,
                height: autoHideTriggerHeight
            )
            if !autoHideVisible && triggerZone.contains(mouseLocation) {
                slideIn()
            } else if autoHideVisible, let dockFrame = window?.frame {
                let expandedFrame = dockFrame.insetBy(dx: -autoHideLeaveMargin, dy: -autoHideLeaveMargin)
                if !expandedFrame.contains(mouseLocation) {
                    slideOut()
                }
            }
        }
    }

    /// Position the dock window offscreen (below/left of visible area) without ordering out
    private func hideOffscreen() {
        guard let window = window else { return }
        let screen = targetScreen()
        let config = ThemeManager.shared.activeTheme?.config
        var frame = window.frame

        if config?.isVertical == true {
            frame.origin.x = screen.frame.minX - frame.width
        } else {
            frame.origin.y = screen.frame.minY - frame.height
        }

        window.setFrame(frame, display: false)
        window.orderFrontRegardless()
        isVisible = true  // Window is technically ordered in (for system dock policy) but offscreen
        autoHideVisible = false
    }

    private func slideIn() {
        guard !autoHideVisible, !autoHideAnimating else { return }
        autoHideAnimating = true

        repositionWindow()
        guard let window = window else {
            autoHideAnimating = false
            return
        }

        let targetFrame = window.frame
        let screen = targetScreen()
        let config = ThemeManager.shared.activeTheme?.config

        // Start offscreen
        var startFrame = targetFrame
        if config?.isVertical == true {
            startFrame.origin.x = screen.frame.minX - targetFrame.width
        } else {
            startFrame.origin.y = screen.frame.minY - targetFrame.height
        }
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
        let config = ThemeManager.shared.activeTheme?.config
        var offscreenFrame = window.frame

        if config?.isVertical == true {
            offscreenFrame.origin.x = screen.frame.minX - offscreenFrame.width
        } else {
            offscreenFrame.origin.y = screen.frame.minY - offscreenFrame.height
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(offscreenFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.autoHideVisible = false
            self?.autoHideAnimating = false
        })
    }

    private func isFrontmostAppFullscreen() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier { return false }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let pid = frontApp.processIdentifier
        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"] else { continue }
            if let screen = NSScreen.main,
               w >= screen.frame.width && h >= screen.frame.height {
                return true
            }
        }
        return false
    }

    // MARK: - Settings

    private func observeSettings() {
        let s = AppSettings.shared

        s.$dockEnabled.dropFirst().sink { [weak self] enabled in
            if enabled { self?.start() } else { self?.stop() }
        }.store(in: &settingsObservers)

        s.$dockTheme.dropFirst().sink { [weak self] newTheme in
            ThemeManager.shared.reload(selectTheme: newTheme)
            ThemeManager.shared.clearCache()
            ThemeManager.shared.applyWallpaper()
            self?.recreateWindow()
            // Note: no .dockThemeChanged post needed — recreateWindow() already
            // creates a fresh DockView with the new theme's layout.
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

        s.$dockMagnification.dropFirst().sink { [weak self] _ in
            self?.recreateWindow()
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
                print("[Dock] Saved original dock state: autohide=\(originalDockAutoHide ?? false), position=\(originalDockPosition ?? "bottom")")
            }
            // Move system dock to opposite side of theme dock
            let themePos = ThemeManager.shared.activeTheme?.config.dock.position ?? "bottom"
            let hidePosition: String
            switch themePos {
            case "left":   hidePosition = "right"
            case "right":  hidePosition = "left"
            case "top":    hidePosition = "left"
            default:       hidePosition = "left"  // bottom → left
            }
            setSystemDockPrefs(autohide: true, position: hidePosition)
            didHideSystemDock = true
            print("[Dock] System dock moved to \(hidePosition) + auto-hide (theme dock is \(themePos))")
        } else if didHideSystemDock {
            restoreSystemDock()
        }
    }

    private func restoreSystemDock() {
        guard didHideSystemDock else { return }
        let restoreHide = originalDockAutoHide ?? false
        let restorePos = originalDockPosition ?? "bottom"
        setSystemDockPrefs(autohide: restoreHide, position: restorePos)
        didHideSystemDock = false
        originalDockAutoHide = nil
        originalDockPosition = nil
        print("[Dock] System dock restored (autohide=\(restoreHide), position=\(restorePos))")
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

    private func setSystemDockPrefs(autohide: Bool, position: String) {
        let writeHide = Process()
        writeHide.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        writeHide.arguments = ["write", "com.apple.dock", "autohide", "-bool", autohide ? "true" : "false"]
        try? writeHide.run()
        writeHide.waitUntilExit()

        let writePos = Process()
        writePos.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        writePos.arguments = ["write", "com.apple.dock", "orientation", "-string", position]
        try? writePos.run()
        writePos.waitUntilExit()

        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["Dock"]
        try? killall.run()
        killall.waitUntilExit()
    }

    /// Returns the current dock window frame in screen coordinates (for DockFix)
    func currentDockFrame() -> NSRect? {
        guard isVisible else { return nil }
        return window?.frame
    }

    // MARK: - Context Menu

    private func showContextMenu(for bundleID: String, at point: NSPoint) {
        let menu = NSMenu()

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

        if let window = window {
            window.makeKeyAndOrderFront(nil)
            let localPoint = window.convertPoint(fromScreen: point)
            menu.popUp(positioning: nil, at: localPoint, in: window.contentView)
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

    // MARK: - Hotkey

    private func registerHotkey() {
        unregisterHotkey()
        let settings = AppSettings.shared
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
