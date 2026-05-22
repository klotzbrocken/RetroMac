import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private(set) var overlayController: OverlayWindowController?
    private(set) var isActive = false
    var currentPresetName: String!
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private(set) var currentIntensity: Float!
    private(set) var currentVignetteIntensity: Float!
    private let settingsWindow = SettingsWindowController()
    private let onboardingWindow = OnboardingWindowController()
    private let fpsOverlay = FPSOverlayController()
    private let windowPicker = WindowPicker()
    private let tvBrowser = TVBrowserWindow()
    private var appLaunchObserver: NSObjectProtocol?
    private var appTerminateObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var perAppBundleID: String?
    private var wasActiveBeforeSleep = false
    private var overlayStartTask: Task<Void, Never>?

    // Save/restore state for TV window overlay
    private var savedPreset: String?
    private var savedWasActive = false

    var captureModeDescription: String {
        guard let controller = overlayController else { return "—" }
        switch controller.captureMode {
        case .fullScreen: return "Full Screen"
        case .singleDisplay: return "Single Display"
        case .singleWindow: return "Single Window"
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Menu-bar app — keep running when TV window closes
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        let settings = AppSettings.shared
        currentPresetName = settings.defaultPreset
        currentIntensity = settings.defaultIntensity
        currentVignetteIntensity = settings.vignetteIntensity

        // Restore system UI if previous session crashed while UI was hidden
        SystemUIHelper.restoreIfNeeded()

        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        registerHotkey()
        startAppLaunchObserver()
        startSleepObserver()

        let hotkeyStr = settings.hotkeyDisplayString
        print("[RetroMac] Ready. \(hotkeyStr) to toggle.")

        if settings.enableOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startOverlay(mode: .fullScreen)
            }
        }

        // Dock never auto-starts — user activates it by selecting a theme
        if settings.dockEnabled {
            settings.dockEnabled = false
        }

        if !settings.onboardingComplete {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.onboardingWindow.show()
            }
        }

        // Friendly nag: "Enjoying RetroMac?" (max once per day, not if licensed)
        if LicenseManager.shared.shouldShowNag {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.showFriendlyNag()
            }
        }

        // Auto-update checks via GitHub Releases
        UpdateChecker.shared.startPeriodicChecks()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateMenuBarIcon()
        rebuildMenu()
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem.button else { return }
        let icon = makeMenuBarIcon(size: NSSize(width: 18, height: 18), active: isActive)
        icon.isTemplate = true
        button.image = icon
    }

    private func makeMenuBarIcon(size: NSSize, active: Bool = false) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            let lw: CGFloat = 1.4

            // Body: rounded rectangle, leaving room for legs + antenna
            let bodyRect = NSRect(x: rect.minX + 1, y: rect.minY + 3, width: rect.width - 2, height: rect.height - 6)
            let body = NSBezierPath(roundedRect: bodyRect, xRadius: 2.5, yRadius: 2.5)
            body.lineWidth = lw
            NSColor.black.setStroke()
            body.stroke()

            // Screen area (left 70% of body)
            let screenW = bodyRect.width * 0.68
            let screenRect = NSRect(
                x: bodyRect.minX + 2,
                y: bodyRect.minY + 2,
                width: screenW,
                height: bodyRect.height - 4
            )
            let screen = NSBezierPath(roundedRect: screenRect, xRadius: 1.5, yRadius: 1.5)

            if active {
                // Filled screen = overlay is active
                NSColor.black.setFill()
                screen.fill()
                // Scanline hints
                NSColor.white.setStroke()
                let lineSpacing: CGFloat = 2.5
                var y = screenRect.minY + lineSpacing
                while y < screenRect.maxY - 1 {
                    let line = NSBezierPath()
                    line.move(to: NSPoint(x: screenRect.minX + 1, y: y))
                    line.line(to: NSPoint(x: screenRect.maxX - 1, y: y))
                    line.lineWidth = 0.5
                    line.stroke()
                    y += lineSpacing
                }
            } else {
                screen.lineWidth = lw
                NSColor.black.setStroke()
                screen.stroke()
            }

            // Two knobs on the right side
            let knobX = screenRect.maxX + (bodyRect.maxX - screenRect.maxX - 1) / 2
            let knobR: CGFloat = 1.3
            let knob1Center = NSPoint(x: knobX, y: bodyRect.midY + 2.5)
            let knob2Center = NSPoint(x: knobX, y: bodyRect.midY - 2.5)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: knob1Center.x - knobR, y: knob1Center.y - knobR, width: knobR * 2, height: knobR * 2)).fill()
            NSBezierPath(ovalIn: NSRect(x: knob2Center.x - knobR, y: knob2Center.y - knobR, width: knobR * 2, height: knobR * 2)).fill()

            // V-antenna from top-right of body
            let antennaBase = NSPoint(x: bodyRect.maxX - 3, y: bodyRect.maxY)
            let antenna = NSBezierPath()
            antenna.move(to: antennaBase)
            antenna.line(to: NSPoint(x: antennaBase.x - 4, y: rect.maxY - 0.5))
            antenna.move(to: antennaBase)
            antenna.line(to: NSPoint(x: antennaBase.x + 2, y: rect.maxY - 0.5))
            antenna.lineWidth = lw
            antenna.stroke()

            // Two legs
            let legs = NSBezierPath()
            let legInset: CGFloat = 3.5
            legs.move(to: NSPoint(x: bodyRect.minX + legInset, y: bodyRect.minY))
            legs.line(to: NSPoint(x: bodyRect.minX + legInset - 1.5, y: rect.minY + 0.5))
            legs.move(to: NSPoint(x: bodyRect.maxX - legInset, y: bodyRect.minY))
            legs.line(to: NSPoint(x: bodyRect.maxX - legInset + 1.5, y: rect.minY + 0.5))
            legs.lineWidth = lw
            legs.stroke()

            return true
        }
        return img
    }

    private func sfIcon(_ name: String, scale: NSImage.SymbolScale = .medium) -> NSImage? {
        let config = NSImage.SymbolConfiguration(scale: scale)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let settings = AppSettings.shared
        let hk = settings.hotkeyDisplayString

        // Toggle
        let toggleTitle = isActive ? "Stop Shader (\(hk))" : "Start Shader (\(hk))"
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleOverlay), keyEquivalent: "")
        toggle.target = self
        toggle.image = sfIcon(isActive ? "power.circle.fill" : "power.circle")
        menu.addItem(toggle)

        menu.addItem(NSMenuItem.separator())

        // Presets — cascading category submenus
        let presetsItem = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        presetsItem.image = sfIcon("slider.horizontal.3")
        let presetsMenu = NSMenu()
        let lm = LicenseManager.shared

        // Monochrome lock icon for premium presets
        let lockIcon = sfIcon("lock.fill", scale: .small)

        // Basic (Free) — quick-access folder with all free presets + Surprise
        let basicItem = NSMenuItem(title: "Basic (Free)", action: nil, keyEquivalent: "")
        basicItem.image = sfIcon("star.circle")
        let basicMenu = NSMenu()

        let surpriseItem = NSMenuItem(title: "Surprise!", action: #selector(selectSurprisePreset), keyEquivalent: "")
        surpriseItem.target = self
        surpriseItem.image = sfIcon("dice")
        basicMenu.addItem(surpriseItem)
        basicMenu.addItem(NSMenuItem.separator())

        let allBuiltin = PresetRegistry.builtinPresets
        for preset in allBuiltin where LicenseManager.freePresetIDs.contains(preset.id) {
            let item = NSMenuItem(title: preset.displayName, action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id
            if preset.id == currentPresetName { item.state = .on }
            basicMenu.addItem(item)
        }
        basicItem.submenu = basicMenu
        if allBuiltin.filter({ LicenseManager.freePresetIDs.contains($0.id) }).contains(where: { $0.id == currentPresetName }) {
            basicItem.state = .mixed
        }
        presetsMenu.addItem(basicItem)
        presetsMenu.addItem(NSMenuItem.separator())

        // Category submenus (all presets, locked ones get lock icon)
        for (category, presets) in PresetRegistry.categorizedPresets {
            let catItem = NSMenuItem(title: category.rawValue, action: nil, keyEquivalent: "")
            let catMenu = NSMenu()
            for preset in presets {
                let isFree = LicenseManager.freePresetIDs.contains(preset.id)
                let locked = !isFree && !lm.hasAllPresets
                let item = NSMenuItem(title: preset.displayName, action: #selector(selectPreset(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.id
                if preset.id == currentPresetName { item.state = .on }
                if locked { item.image = lockIcon }
                catMenu.addItem(item)
            }
            catItem.submenu = catMenu
            if presets.contains(where: { $0.id == currentPresetName }) {
                catItem.state = .mixed
            }
            presetsMenu.addItem(catItem)
        }
        let custom = PresetRegistry.customPresets()
        if !custom.isEmpty {
            presetsMenu.addItem(NSMenuItem.separator())
            let catItem = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
            if !lm.hasAllPresets { catItem.image = lockIcon }
            let catMenu = NSMenu()
            for preset in custom {
                let locked = !lm.hasAllPresets
                let item = NSMenuItem(title: preset.displayName, action: #selector(selectPreset(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.id
                if preset.id == currentPresetName { item.state = .on }
                if locked { item.image = lockIcon }
                catMenu.addItem(item)
            }
            catItem.submenu = catMenu
            presetsMenu.addItem(catItem)
        }
        presetsItem.submenu = presetsMenu
        menu.addItem(presetsItem)

        // Intensity submenu
        let intensityItem = NSMenuItem(title: "Intensity", action: nil, keyEquivalent: "")
        intensityItem.image = sfIcon("sun.max")
        let intensityMenu = NSMenu()
        for pct in stride(from: 10, through: 100, by: 10) {
            let item = NSMenuItem(title: "\(pct)%", action: #selector(setIntensity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = pct
            if abs(Float(pct) / 100.0 - currentIntensity) < 0.01 { item.state = .on }
            intensityMenu.addItem(item)
        }
        intensityItem.submenu = intensityMenu
        menu.addItem(intensityItem)

        // Vignette submenu
        let vignetteItem = NSMenuItem(title: "Vignette", action: nil, keyEquivalent: "")
        vignetteItem.image = sfIcon("circle.circle")
        let vignetteMenu = NSMenu()
        let vigOff = NSMenuItem(title: "Off", action: #selector(setVignette(_:)), keyEquivalent: "")
        vigOff.target = self
        vigOff.tag = 0
        if currentVignetteIntensity < 0.01 { vigOff.state = .on }
        vignetteMenu.addItem(vigOff)
        for pct in stride(from: 20, through: 100, by: 20) {
            let item = NSMenuItem(title: "\(pct)%", action: #selector(setVignette(_:)), keyEquivalent: "")
            item.target = self
            item.tag = pct
            if abs(Float(pct) / 100.0 - currentVignetteIntensity) < 0.01 { item.state = .on }
            vignetteMenu.addItem(item)
        }
        vignetteItem.submenu = vignetteMenu
        menu.addItem(vignetteItem)

        // Overlays submenu
        let overlaysItem = NSMenuItem(title: "Overlays", action: nil, keyEquivalent: "")
        overlaysItem.image = sfIcon("square.3.layers.3d")
        let overlaysMenu = NSMenu()

        let scanItem = NSMenuItem(title: "Scanlines", action: nil, keyEquivalent: "")
        let scanMenu = NSMenu()
        let scanOff = NSMenuItem(title: "None", action: #selector(selectScanline(_:)), keyEquivalent: "")
        scanOff.target = self; scanOff.representedObject = "" as String
        if settings.scanlineOverlayName.isEmpty { scanOff.state = .on }
        scanMenu.addItem(scanOff)
        scanMenu.addItem(NSMenuItem.separator())
        for s in OverlayManager.builtinScanlines {
            let item = NSMenuItem(title: s.displayName, action: #selector(selectScanline(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = s.id
            if s.id == settings.scanlineOverlayName { item.state = .on }
            scanMenu.addItem(item)
        }
        scanItem.submenu = scanMenu
        overlaysMenu.addItem(scanItem)

        let reflItem = NSMenuItem(title: "Reflection", action: nil, keyEquivalent: "")
        let reflMenu = NSMenu()
        let reflOff = NSMenuItem(title: "None", action: #selector(selectReflection(_:)), keyEquivalent: "")
        reflOff.target = self; reflOff.representedObject = "" as String
        if settings.reflectionName.isEmpty { reflOff.state = .on }
        reflMenu.addItem(reflOff)
        reflMenu.addItem(NSMenuItem.separator())
        for r in OverlayManager.builtinReflections {
            let item = NSMenuItem(title: r.displayName, action: #selector(selectReflection(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = r.id
            if r.id == settings.reflectionName { item.state = .on }
            reflMenu.addItem(item)
        }
        reflItem.submenu = reflMenu
        overlaysMenu.addItem(reflItem)

        overlaysItem.submenu = overlaysMenu
        menu.addItem(overlaysItem)

        menu.addItem(NSMenuItem.separator())

        // Display submenu
        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        displayItem.image = sfIcon("display")
        let displayMenu = NSMenu()
        let allDisplays = NSMenuItem(title: "All Displays", action: #selector(selectDisplay(_:)), keyEquivalent: "")
        allDisplays.target = self
        allDisplays.tag = 0
        if settings.targetDisplayID == 0 { allDisplays.state = .on }
        displayMenu.addItem(allDisplays)
        displayMenu.addItem(NSMenuItem.separator())
        for screen in NSScreen.screens {
            let displayID = screen.displayID
            let name = screen.localizedName
            let item = NSMenuItem(title: name, action: #selector(selectDisplay(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(displayID)
            if displayID == settings.targetDisplayID { item.state = .on }
            displayMenu.addItem(item)
        }
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)

        // Window picker
        let pickItem = NSMenuItem(title: "Apply to Window…", action: #selector(pickWindowVisual), keyEquivalent: "")
        pickItem.target = self
        pickItem.image = sfIcon("macwindow")
        menu.addItem(pickItem)

        if isActive {
            let fullItem = NSMenuItem(title: "Apply to Full Screen", action: #selector(applyFullScreen), keyEquivalent: "")
            fullItem.target = self
            fullItem.image = sfIcon("rectangle.inset.filled")
            menu.addItem(fullItem)
        }

        menu.addItem(NSMenuItem.separator())

        if isActive {
            let screenshotItem = NSMenuItem(title: "Screenshot with Effect", action: #selector(takeScreenshot), keyEquivalent: "")
            screenshotItem.target = self
            screenshotItem.image = sfIcon("camera")
            menu.addItem(screenshotItem)
        }

        let fpsTitle = fpsOverlay.isVisible ? "Hide FPS Overlay" : "Show FPS Overlay"
        let fpsItem = NSMenuItem(title: fpsTitle, action: #selector(toggleFPSOverlay), keyEquivalent: "")
        fpsItem.target = self
        fpsItem.image = sfIcon("gauge.with.dots.needle.33percent")
        menu.addItem(fpsItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = sfIcon("gearshape")
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Television submenu
        let tvBookmarks = AppSettings.shared.tvBookmarks
        if !tvBookmarks.isEmpty {
            let tvItem = NSMenuItem(title: "Television", action: nil, keyEquivalent: "")
            tvItem.image = sfIcon("tv")
            let tvMenu = NSMenu()
            for bookmark in tvBookmarks {
                let item = NSMenuItem(title: bookmark.name, action: #selector(openTVBookmark(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = bookmark.id.uuidString
                item.image = sfIcon("antenna.radiowaves.left.and.right")
                tvMenu.addItem(item)
            }
            tvItem.submenu = tvMenu
            menu.addItem(tvItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Themes submenu
        let themesItem = NSMenuItem(title: "Themes", action: nil, keyEquivalent: "")
        themesItem.image = sfIcon("paintpalette")
        let themesMenu = NSMenu()
        let dockOn = AppSettings.shared.dockEnabled
        let currentTheme = AppSettings.shared.dockTheme

        let offItem = NSMenuItem(title: "Off", action: #selector(disableTheme), keyEquivalent: "")
        offItem.target = self
        if !dockOn { offItem.state = .on }
        themesMenu.addItem(offItem)
        themesMenu.addItem(.separator())

        for theme in ThemeManager.shared.availableThemes {
            let item = NSMenuItem(title: theme.name, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme.name
            if dockOn && theme.name == currentTheme { item.state = .on }
            themesMenu.addItem(item)
        }
        themesItem.submenu = themesMenu
        menu.addItem(themesItem)

        // Dock toggle
        let dockTitle = AppSettings.shared.dockEnabled ? "Hide Retro-Dock" : "Show Retro-Dock"
        let dockItem = NSMenuItem(title: dockTitle, action: #selector(toggleDock), keyEquivalent: "")
        dockItem.target = self
        dockItem.image = sfIcon("dock.rectangle")
        menu.addItem(dockItem)

        menu.addItem(NSMenuItem.separator())

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(UpdateChecker.checkNow(_:)), keyEquivalent: "")
        updateItem.target = UpdateChecker.shared
        updateItem.image = sfIcon("arrow.triangle.2.circlepath")
        menu.addItem(updateItem)

        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        quit.image = sfIcon("xmark.circle")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Carbon Global Hotkey

    func registerHotkey() {
        unregisterHotkey()

        let settings = AppSettings.shared
        let hotKeyID = EventHotKeyID(signature: OSType(0x524D4143), id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            settings.hotkeyCode, settings.hotkeyModifiers,
            hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr { hotKeyRef = ref }

        if eventHandlerRef == nil {
            var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(
                GetApplicationEventTarget(),
                { (_, _, userData) -> OSStatus in
                    guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                    let d = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                    DispatchQueue.main.async { d.toggleOverlay() }
                    return noErr
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

    // MARK: - Per-App Launch Observer

    private func startAppLaunchObserver() {
        let ws = NSWorkspace.shared
        appLaunchObserver = ws.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            self?.handleAppLaunch(notification)
        }
        appTerminateObserver = ws.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            self?.handleAppTerminate(notification)
        }
    }

    private func handleAppLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              let preset = AppSettings.shared.presetForApp(bundleID: bundleID) else { return }

        print("[RetroMac] Per-app trigger: \(bundleID) launched → \(preset)")

        // Wait for the app's window to appear, then apply overlay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            self.applyOverlayToApp(bundleID: bundleID, presetName: preset)
        }
    }

    private func handleAppTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }

        if perAppBundleID == bundleID {
            print("[RetroMac] Per-app trigger: \(bundleID) terminated → disableAll")
            disableAll()
        }
    }

    private func applyOverlayToApp(bundleID: String, presetName: String) {
        Task {
            do {
                let windows = try await ScreenCaptureManager.listWindows()
                guard let targetWindow = windows.first(where: {
                    $0.owningApplication?.bundleIdentifier == bundleID
                }) else {
                    print("[RetroMac] Per-app: no window found for \(bundleID)")
                    return
                }
                let appName = targetWindow.owningApplication?.applicationName ?? bundleID
                print("[RetroMac] Per-app: applying \(presetName) to \(appName)")
                await MainActor.run {
                    self.currentPresetName = presetName
                    self.perAppBundleID = bundleID
                    self.startOverlay(mode: .singleWindow(targetWindow))
                }
            } catch {
                print("[RetroMac] Per-app error: \(error)")
            }
        }
    }

    // MARK: - Sleep / Lock Observer

    private func startSleepObserver() {
        let ws = NSWorkspace.shared

        sleepObserver = ws.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleSleep()
        }

        lockObserver = ws.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleSleep()
        }

        wakeObserver = ws.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }
    }

    private func handleSleep() {
        guard isActive, AppSettings.shared.stopOnSleep else { return }
        print("[RetroMac] Sleep/lock → disableAll")
        wasActiveBeforeSleep = true
        disableAll()
    }

    private func handleWake() {
        guard wasActiveBeforeSleep, AppSettings.shared.resumeAfterSleep else {
            wasActiveBeforeSleep = false
            return
        }
        wasActiveBeforeSleep = false
        print("[RetroMac] Wake → resuming overlay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.startOverlay(mode: .fullScreen)
        }
    }

    // MARK: - Actions

    func disableAll() {
        print("[RetroMac] disableAll()")

        overlayStartTask?.cancel()
        overlayStartTask = nil
        overlayController?.stop()
        overlayController = nil
        isActive = false
        perAppBundleID = nil

        if fpsOverlay.isVisible {
            fpsOverlay.hide()
        }

        if AppSettings.shared.classicMacModeActive {
            ClassicMacMode.deactivate()
        }

        updateMenuBarIcon()
        rebuildMenu()
    }

    @objc func toggleOverlay() {
        if isActive {
            disableAll()
        } else {
            startOverlay(mode: .fullScreen)
        }
    }

    private func startOverlay(mode: CaptureMode, presetOverride: String? = nil, parentWindow: NSWindow? = nil) {
        // Cancel any in-flight overlay start
        overlayStartTask?.cancel()
        overlayStartTask = nil

        if isActive {
            overlayController?.stop()
            overlayController = nil
            isActive = false
        }

        let settings = AppSettings.shared
        var effectiveMode = mode
        if case .fullScreen = mode, settings.targetDisplayID != 0 {
            effectiveMode = .singleDisplay(settings.targetDisplayID)
        }

        // Use override if provided (e.g. TV window), otherwise use global preset
        var presetName = presetOverride ?? currentPresetName!
        if case .singleWindow(let scWindow) = effectiveMode,
           let bundleID = scWindow.owningApplication?.bundleIdentifier,
           let appPreset = settings.presetForApp(bundleID: bundleID) {
            presetName = appPreset
            currentPresetName = appPreset
            print("[RetroMac] Per-app preset: \(bundleID) → \(appPreset)")
        }

        overlayStartTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let controller = try await OverlayWindowController.create(mode: effectiveMode)

                // Check cancellation before committing
                guard !Task.isCancelled else {
                    controller.stop()
                    return
                }

                controller.intensity = self.currentIntensity
                controller.vignetteIntensity = self.currentVignetteIntensity
                try await controller.start(presetName: presetName)

                guard !Task.isCancelled else {
                    controller.stop()
                    return
                }

                self.overlayController = controller
                self.isActive = true
                self.overlayStartTask = nil

                // Attach overlay as child of parent window (for TV overlay)
                // Child windows follow parent automatically and ignoresMouseEvents
                // passes clicks through to the parent.
                if let parent = parentWindow {
                    await MainActor.run {
                        controller.attachToParentWindow(parent)
                    }
                }

                if self.fpsOverlay.isVisible {
                    self.setupFPSTracking()
                }
                await MainActor.run {
                    self.updateMenuBarIcon()
                    self.rebuildMenu()
                }
            } catch {
                guard !Task.isCancelled else { return }
                print("[RetroMac] ERROR: \(error)")
                self.overlayStartTask = nil
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "RetroMac Error"
                    alert.informativeText = "\(error)"
                    alert.runModal()
                }
            }
        }
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let presetId = sender.representedObject as? String else { return }

        // License check: block premium presets if not licensed
        if !LicenseManager.shared.isPresetAvailable(presetId) {
            let name = PresetRegistry.builtinPresets.first(where: { $0.id == presetId })?.displayName ?? presetId
            showPresetLockedAlert(presetName: name)
            return
        }

        // Manual selection is highest priority — clear any saved TV state
        savedPreset = nil
        savedWasActive = false
        if !isActive {
            startOverlay(mode: .fullScreen)
        }
        applyPreset(presetId)
    }

    @objc private func setIntensity(_ sender: NSMenuItem) {
        currentIntensity = Float(sender.tag) / 100.0
        overlayController?.intensity = currentIntensity
        rebuildMenu()
    }

    @objc private func setVignette(_ sender: NSMenuItem) {
        currentVignetteIntensity = Float(sender.tag) / 100.0
        overlayController?.vignetteIntensity = currentVignetteIntensity
        rebuildMenu()
    }

    @objc private func selectScanline(_ sender: NSMenuItem) {
        let name = sender.representedObject as? String ?? ""
        AppSettings.shared.scanlineOverlayName = name
        overlayController?.loadOverlays()
        rebuildMenu()
    }

    @objc private func selectReflection(_ sender: NSMenuItem) {
        let name = sender.representedObject as? String ?? ""
        AppSettings.shared.reflectionName = name
        overlayController?.loadOverlays()
        rebuildMenu()
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        let displayID = CGDirectDisplayID(sender.tag)
        AppSettings.shared.targetDisplayID = displayID
        if isActive {
            startOverlay(mode: .fullScreen)
        }
        rebuildMenu()
    }

    @objc private func pickWindowVisual() {
        if isActive {
            disableAll()
        }

        windowPicker.pick { [weak self] scWindow in
            guard let self = self, let window = scWindow else { return }
            self.startOverlay(mode: .singleWindow(window))
        }
    }

    @objc private func applyFullScreen() {
        startOverlay(mode: .fullScreen)
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func openTVBookmark(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let uuid = UUID(uuidString: idString),
              let bookmark = AppSettings.shared.tvBookmarks.first(where: { $0.id == uuid }) else { return }
        tvBrowser.open(bookmark: bookmark)
    }

    func showOnboarding() {
        onboardingWindow.show()
    }

    func applyOverlayToWindowID(_ windowID: CGWindowID, presetName: String, parentWindow: NSWindow? = nil, saveState: Bool = true) {
        if saveState {
            // Save current state so we can restore when the TV window closes
            savedPreset = currentPresetName
            savedWasActive = isActive
            print("[RetroMac] TV overlay: saving state (preset=\(currentPresetName ?? "nil"), active=\(isActive))")
        }

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                    print("[RetroMac] No SCWindow found for windowID \(windowID)")
                    if saveState {
                        self.savedPreset = nil
                        self.savedWasActive = false
                    }
                    return
                }
                await MainActor.run {
                    // Don't modify currentPresetName — pass preset via override
                    // Pass parentWindow so overlay attaches as child (for TV windows)
                    self.startOverlay(mode: .singleWindow(scWindow), presetOverride: presetName, parentWindow: parentWindow)
                }
            } catch {
                print("[RetroMac] Window overlay error: \(error)")
                if saveState {
                    self.savedPreset = nil
                    self.savedWasActive = false
                }
            }
        }
    }

    /// Restore previous overlay state after TV window closes
    func restorePreviousOverlay() {
        guard let preset = savedPreset else {
            // No saved state — just stop if still running
            if isActive {
                disableAll()
            }
            return
        }
        let wasActive = savedWasActive
        savedPreset = nil
        savedWasActive = false

        print("[RetroMac] TV closed: restoring (preset=\(preset), wasActive=\(wasActive))")

        // Stop TV overlay
        overlayStartTask?.cancel()
        overlayStartTask = nil
        overlayController?.stop()
        overlayController = nil
        isActive = false

        // Restore previous preset
        currentPresetName = preset

        // Restore overlay if it was active before TV
        if wasActive {
            startOverlay(mode: .fullScreen)
        } else {
            updateMenuBarIcon()
            rebuildMenu()
        }
    }

    func applyPreset(_ presetID: String) {
        currentPresetName = presetID
        overlayController?.switchPreset(presetID)
        overlayController?.loadOverlays()
        overlayController?.syncOverlayTextures()
        let settings = AppSettings.shared
        currentVignetteIntensity = settings.vignetteIntensity
        overlayController?.vignetteIntensity = currentVignetteIntensity
        rebuildMenu()
    }

    @objc private func toggleFPSOverlay() {
        if fpsOverlay.isVisible {
            fpsOverlay.hide()
            overlayController?.stopFPSTracking()
        } else {
            fpsOverlay.show()
            setupFPSTracking()
        }
        rebuildMenu()
    }

    @objc private func takeScreenshot() {
        guard let image = overlayController?.captureScreenshot() else {
            print("[RetroMac] Screenshot failed: no frame available")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "RetroMac_\(timestamp).png"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let url = desktop.appendingPathComponent(filename)

        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: url)
            print("[RetroMac] Screenshot saved: \(url.path)")

            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])

            NSSound(named: "Tink")?.play()
        }
    }

    private func setupFPSTracking() {
        guard let controller = overlayController else { return }
        controller.onFPSUpdate = { [weak self] fps, resolution in
            guard let self = self else { return }
            let gpuMs = self.overlayController?.lastGPUTimeMs ?? 0
            let resStr = resolution.width > 0 ? "\(Int(resolution.width))×\(Int(resolution.height))" : "—"
            self.fpsOverlay.update(fps: fps, gpuTimeMs: gpuMs, resolution: resStr)
        }
        controller.startFPSTracking()
    }

    @objc private func toggleClassicMacMode() {
        if AppSettings.shared.classicMacModeActive {
            disableAll()
        } else {
            ClassicMacMode.activate()
            rebuildMenu()
        }
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let settings = AppSettings.shared
        ThemeManager.shared.setActiveTheme(name: name)
        if !settings.dockEnabled {
            settings.dockEnabled = true
            DockController.shared.start()
        }
        if let preset = settings.presetForTheme(name: name) {
            if !isActive {
                startOverlay(mode: .fullScreen)
            }
            applyPreset(preset)
        }
        rebuildMenu()
    }

    @objc private func disableTheme() {
        AppSettings.shared.dockEnabled = false
        DockController.shared.stop()
        ThemeManager.shared.restoreWallpapers()
        rebuildMenu()
    }

    @objc private func toggleDock() {
        let settings = AppSettings.shared
        settings.dockEnabled.toggle()
        if settings.dockEnabled {
            DockController.shared.start()
        } else {
            DockController.shared.stop()
        }
        rebuildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanupBeforeQuit()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func cleanupBeforeQuit() {
        let nc = NSWorkspace.shared.notificationCenter
        for obs in [appLaunchObserver, appTerminateObserver, sleepObserver, lockObserver, wakeObserver].compactMap({ $0 }) {
            nc.removeObserver(obs)
        }
        disableAll()
        DockController.shared.stop()
        ThemeManager.shared.restoreWallpapers()
    }

    // MARK: - Surprise Preset

    @objc private func selectSurprisePreset() {
        let presetID = LicenseManager.surprisePresetID
        savedPreset = nil
        savedWasActive = false
        if !isActive {
            startOverlay(mode: .fullScreen)
        }
        applyPreset(presetID)
    }

    // MARK: - License / Nag

    private func showFriendlyNag() {
        let lm = LicenseManager.shared
        lm.markNagDismissed()

        let alert = NSAlert()
        alert.messageText = "Enjoying RetroMac?"
        alert.informativeText = "RetroMac is free. If you like it, buy me a coffee or unlock all \(PresetRegistry.builtinPresets.count) presets!"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Buy me a coffee ☕")
        alert.addButton(withTitle: "Get All Presets")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: LicenseManager.kofiURL) {
                NSWorkspace.shared.open(url)
            }
        } else if response == .alertSecondButtonReturn {
            if let url = URL(string: LicenseManager.purchaseURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showPresetLockedAlert(presetName: String) {
        let alert = NSAlert()
        alert.messageText = "\(presetName) 🔒"
        alert.informativeText = "This preset is part of the All Presets pack. Unlock all \(PresetRegistry.builtinPresets.count) presets + custom shaders!"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Get All Presets")
        alert.addButton(withTitle: "Enter Key")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: LicenseManager.purchaseURL) {
                NSWorkspace.shared.open(url)
            }
        } else if response == .alertSecondButtonReturn {
            settingsWindow.show()
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}
