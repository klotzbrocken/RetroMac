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

    func start() {
        guard window == nil else { return }
        print("[Dock] Starting")

        ThemeManager.shared.reload()
        createWindow()
        registerHotkey()
        applySystemDockPolicy()

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
    }

    func stop() {
        print("[Dock] Stopping")
        restoreSystemDock()
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

        let longAxis = dockView.requiredWidth()
        let theme = ThemeManager.shared.activeTheme?.config
        let scale = CGFloat(AppSettings.shared.dockIconScale)
        let shortAxis = (theme?.dock.height ?? 80) * scale
        let isVert = theme?.isVertical ?? false
        let width: CGFloat
        let height: CGFloat
        if isVert {
            width = shortAxis
            height = longAxis
        } else if theme?.isFullWidth == true {
            width = screen.frame.width
            height = shortAxis
        } else {
            width = longAxis
            height = shortAxis
        }
        let frame = dockFrame(screen: screen, width: width, height: height)

        let win = DockWindow(contentRect: frame)
        win.alphaValue = CGFloat(AppSettings.shared.dockTransparency)

        dockView.frame = NSRect(origin: .zero, size: frame.size)
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
            isVisible = false
            show()
        }
    }

    private func repositionWindow() {
        guard let window = window, let dockView = dockView else { return }
        let screen = targetScreen()
        let longAxis = dockView.requiredWidth()
        let theme = ThemeManager.shared.activeTheme?.config
        let scale = CGFloat(AppSettings.shared.dockIconScale)
        let shortAxis = (theme?.dock.height ?? 80) * scale
        let isVert = theme?.isVertical ?? false
        let width: CGFloat
        let height: CGFloat
        if isVert {
            width = shortAxis
            height = longAxis
        } else if theme?.isFullWidth == true {
            width = screen.frame.width
            height = shortAxis
        } else {
            width = longAxis
            height = shortAxis
        }
        let frame = dockFrame(screen: screen, width: width, height: height)
        window.setFrame(frame, display: true)
        dockView.frame = NSRect(origin: .zero, size: frame.size)
        dockView.relayoutItems()
    }

    private func dockFrame(screen: NSScreen, width: CGFloat, height: CGFloat) -> NSRect {
        let visible = screen.visibleFrame
        let config = ThemeManager.shared.activeTheme?.config
        if config?.isVertical == true {
            let x = visible.minX + 4
            let y = visible.midY - height / 2
            return NSRect(x: x, y: y, width: width, height: height)
        }
        if config?.isFullWidth == true {
            return NSRect(x: screen.frame.minX, y: visible.minY, width: screen.frame.width, height: height)
        }
        let x = visible.midX - width / 2
        let y = visible.minY + 8
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

        show()
    }

    private func show() {
        guard !isVisible else { return }
        repositionWindow()
        window?.orderFrontRegardless()
        isVisible = true
        if AppSettings.shared.dockHideSystemDock {
            if originalDockAutoHide == nil {
                originalDockAutoHide = readSystemDockAutoHide()
            }
            if !readSystemDockAutoHide() {
                setSystemDockAutoHide(true)
            }
            didHideSystemDock = true
        }
    }

    private func hide() {
        guard isVisible else { return }
        window?.orderOut(nil)
        isVisible = false
        if didHideSystemDock {
            let restoreTo = originalDockAutoHide ?? false
            if readSystemDockAutoHide() != restoreTo {
                setSystemDockAutoHide(restoreTo)
            }
        }
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
            self?.recreateWindow()
        }.store(in: &settingsObservers)

        s.$dockTransparency.dropFirst().sink { [weak self] alpha in
            self?.window?.alphaValue = CGFloat(alpha)
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

        s.$dockHideSystemDock.dropFirst().sink { [weak self] _ in
            self?.applySystemDockPolicy()
        }.store(in: &settingsObservers)
    }

    // MARK: - System Dock

    private func applySystemDockPolicy() {
        let shouldHide = AppSettings.shared.dockHideSystemDock
        if shouldHide {
            if originalDockAutoHide == nil {
                originalDockAutoHide = readSystemDockAutoHide()
                print("[Dock] Saved original autohide state: \(originalDockAutoHide ?? false)")
            }
            setSystemDockAutoHide(true)
            didHideSystemDock = true
            print("[Dock] System dock set to auto-hide")
        } else if didHideSystemDock {
            restoreSystemDock()
        }
    }

    private func restoreSystemDock() {
        guard didHideSystemDock else { return }
        let restoreTo = originalDockAutoHide ?? false
        setSystemDockAutoHide(restoreTo)
        didHideSystemDock = false
        originalDockAutoHide = nil
        print("[Dock] System dock restored (autohide=\(restoreTo))")
    }

    private func readSystemDockAutoHide() -> Bool {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "com.apple.dock", "autohide"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output == "1"
    }

    private func setSystemDockAutoHide(_ hide: Bool) {
        let val = hide ? "true" : "false"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["write", "com.apple.dock", "autohide", "-bool", val]
        try? task.run()
        task.waitUntilExit()

        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["Dock"]
        try? killall.run()
        killall.waitUntilExit()
    }

    // MARK: - Context Menu

    private func showContextMenu(for bundleID: String, at point: NSPoint) {
        let menu = NSMenu()
        let isRunning = AppLauncher.isRunning(bundleID: bundleID)

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

        let remove = NSMenuItem(title: "Remove from Dock", action: #selector(menuRemove(_:)), keyEquivalent: "")
        remove.target = self
        remove.representedObject = bundleID
        menu.addItem(remove)

        if let window = window {
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
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .icns, .tiff, .jpeg]
        panel.message = "Choose a custom icon for current theme"
        panel.prompt = "Set Icon"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ThemeManager.shared.setCustomIcon(for: bid, path: url.path)
        dockView?.rebuildItems()
    }

    @objc private func menuRemove(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        AppManager.shared.removeApp(bundleID: bid)
        repositionWindow()
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
