import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private(set) var overlayController: OverlayWindowController?
    private(set) var isActive = false
    private(set) var currentPresetName: String!
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private(set) var currentIntensity: Float!
    private(set) var currentVignetteIntensity: Float!
    private let settingsWindow = SettingsWindowController()
    private let onboardingWindow = OnboardingWindowController()
    private let fpsOverlay = FPSOverlayController()
    private let windowPicker = WindowPicker()
    private var appLaunchObserver: NSObjectProtocol?
    private var appTerminateObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var perAppBundleID: String?
    private var wasActiveBeforeSleep = false

    var captureModeDescription: String {
        guard let controller = overlayController else { return "—" }
        switch controller.captureMode {
        case .fullScreen: return "Full Screen"
        case .singleDisplay: return "Single Display"
        case .singleWindow: return "Single Window"
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        let settings = AppSettings.shared
        currentPresetName = settings.defaultPreset
        currentIntensity = settings.defaultIntensity
        currentVignetteIntensity = settings.vignetteIntensity

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

        if settings.dockEnabled {
            DockController.shared.start()
        }

        if !settings.onboardingComplete {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.onboardingWindow.show()
            }
        }
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

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let settings = AppSettings.shared
        let hk = settings.hotkeyDisplayString

        // Toggle
        let toggleTitle = isActive ? "Disable (\(hk))" : "Enable (\(hk))"
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleOverlay), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(NSMenuItem.separator())

        // Presets — cascading category submenus
        let presetsItem = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        let presetsMenu = NSMenu()
        for (category, presets) in PresetRegistry.categorizedPresets {
            let catItem = NSMenuItem(title: category.rawValue, action: nil, keyEquivalent: "")
            let catMenu = NSMenu()
            for preset in presets {
                let item = NSMenuItem(title: preset.displayName, action: #selector(selectPreset(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.id
                if preset.id == currentPresetName { item.state = .on }
                catMenu.addItem(item)
            }
            catItem.submenu = catMenu
            // Mark category if current preset is in it
            if presets.contains(where: { $0.id == currentPresetName }) {
                catItem.state = .mixed
            }
            presetsMenu.addItem(catItem)
        }
        let custom = PresetRegistry.customPresets()
        if !custom.isEmpty {
            presetsMenu.addItem(NSMenuItem.separator())
            let catItem = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
            let catMenu = NSMenu()
            for preset in custom {
                let item = NSMenuItem(title: preset.displayName, action: #selector(selectPreset(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.id
                if preset.id == currentPresetName { item.state = .on }
                catMenu.addItem(item)
            }
            catItem.submenu = catMenu
            presetsMenu.addItem(catItem)
        }
        presetsItem.submenu = presetsMenu
        menu.addItem(presetsItem)

        // Intensity submenu
        let intensityItem = NSMenuItem(title: "Intensity", action: nil, keyEquivalent: "")
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
        let overlaysMenu = NSMenu()

        // Scanline sub
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

        // Reflection sub
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
        let displayMenu = NSMenu()
        let allDisplays = NSMenuItem(title: "All Displays", action: #selector(selectDisplay(_:)), keyEquivalent: "")
        allDisplays.target = self
        allDisplays.tag = 0
        if settings.targetDisplayID == 0 { allDisplays.state = .on }
        displayMenu.addItem(allDisplays)
        displayMenu.addItem(NSMenuItem.separator())
        for (i, screen) in NSScreen.screens.enumerated() {
            let displayID = screen.displayID
            let name = screen.localizedName
            let item = NSMenuItem(title: name, action: #selector(selectDisplay(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(displayID)
            item.indentationLevel = 0
            if displayID == settings.targetDisplayID { item.state = .on }
            displayMenu.addItem(item)
        }
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)

        // Window picker
        let pickItem = NSMenuItem(title: "Apply to Window…", action: #selector(pickWindowVisual), keyEquivalent: "")
        pickItem.target = self
        menu.addItem(pickItem)

        if isActive {
            let fullItem = NSMenuItem(title: "Apply to Full Screen", action: #selector(applyFullScreen), keyEquivalent: "")
            fullItem.target = self
            menu.addItem(fullItem)
        }

        menu.addItem(NSMenuItem.separator())

        if isActive {
            let screenshotItem = NSMenuItem(title: "Screenshot with Effect", action: #selector(takeScreenshot), keyEquivalent: "")
            screenshotItem.target = self
            menu.addItem(screenshotItem)
        }

        let fpsTitle = fpsOverlay.isVisible ? "Hide FPS Overlay" : "Show FPS Overlay"
        let fpsItem = NSMenuItem(title: fpsTitle, action: #selector(toggleFPSOverlay), keyEquivalent: "")
        fpsItem.target = self
        menu.addItem(fpsItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Themes submenu
        let themesItem = NSMenuItem(title: "Themes", action: nil, keyEquivalent: "")
        let themesMenu = NSMenu()
        let dockOn = AppSettings.shared.dockEnabled
        let currentTheme = AppSettings.shared.dockTheme

        let offItem = NSMenuItem(title: "Aus", action: #selector(disableTheme), keyEquivalent: "")
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
        menu.addItem(dockItem)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
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

    private func startOverlay(mode: CaptureMode) {
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

        // Per-app preset: check if the target window's app has a configured preset
        var presetName = currentPresetName!
        if case .singleWindow(let scWindow) = effectiveMode,
           let bundleID = scWindow.owningApplication?.bundleIdentifier,
           let appPreset = settings.presetForApp(bundleID: bundleID) {
            presetName = appPreset
            currentPresetName = appPreset
            print("[RetroMac] Per-app preset: \(bundleID) → \(appPreset)")
        }

        Task {
            do {
                let controller = try await OverlayWindowController.create(mode: effectiveMode)
                controller.intensity = self.currentIntensity
                controller.vignetteIntensity = self.currentVignetteIntensity
                try await controller.start(presetName: presetName)
                self.overlayController = controller
                self.isActive = true
                if self.fpsOverlay.isVisible {
                    self.setupFPSTracking()
                }
                await MainActor.run {
                    self.updateMenuBarIcon()
                    self.rebuildMenu()
                }
            } catch {
                print("[RetroMac] ERROR: \(error)")
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
        currentPresetName = presetId
        overlayController?.switchPreset(presetId)
        rebuildMenu()
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

    func showOnboarding() {
        onboardingWindow.show()
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
        if let preset = ThemeManager.shared.activeTheme?.config.defaultPreset {
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

    @objc private func quitApp() {
        let nc = NSWorkspace.shared.notificationCenter
        for obs in [appLaunchObserver, appTerminateObserver, sleepObserver, lockObserver, wakeObserver].compactMap({ $0 }) {
            nc.removeObserver(obs)
        }
        disableAll()
        DockController.shared.stop()
        ThemeManager.shared.restoreWallpapers()
        NSApp.terminate(nil)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}
