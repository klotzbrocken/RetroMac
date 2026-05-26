import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import Sparkle
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
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
    var savedPreset: String?
    var savedWasActive = false

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
        settingsWindow.updater = updaterController.updater
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

        // Listen for Start menu TV bookmark requests from DockView
        NotificationCenter.default.addObserver(forName: .init("openTVBookmark"), object: nil, queue: .main) { [weak self] note in
            guard let idString = note.object as? String,
                  let uuid = UUID(uuidString: idString),
                  let bookmark = AppSettings.shared.tvBookmarks.first(where: { $0.id == uuid }) else { return }
            self?.tvBrowser.open(bookmark: bookmark)
        }

        // Apply theme shader when theme changes via Settings
        NotificationCenter.default.addObserver(forName: .dockThemeChanged, object: nil, queue: .main) { [weak self] _ in
            self?.applyThemePresetIfNeeded()
        }

        // Rebuild menu when virtual camera state changes (start/stop is async)
        NotificationCenter.default.addObserver(forName: .virtualCameraStateChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildMenu()
        }

        // Screen Recording permission is checked lazily when overlay is actually
        // started (line ~759). No upfront check here — both CGPreflight and
        // CGRequest can trigger the TCC dialog / System Settings redirect.

        let hotkeyStr = settings.hotkeyDisplayString
        print("[RetroMac] Ready. \(hotkeyStr) to toggle.")

        // App always starts deactivated — user must manually enable overlay/theme
        settings.enableOnLaunch = false
        settings.dockEnabled = false

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

        // Sparkle auto-updates (checks automatically on launch)

        // Virtual camera is started on-demand via menu, not at launch
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

        // ── Toggle ──
        let toggleTitle = isActive ? "Stop Shader (\(hk))" : "Start Shader (\(hk))"
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleOverlay), keyEquivalent: "")
        toggle.target = self
        toggle.image = sfIcon(isActive ? "power.circle.fill" : "power.circle")
        menu.addItem(toggle)

        menu.addItem(NSMenuItem.separator())

        // ── Presets Section ──
        let presetsSectionHeader = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        presetsSectionHeader.isEnabled = false
        menu.addItem(presetsSectionHeader)

        // Presets — cascading category submenus
        let presetsItem = NSMenuItem(title: "Shader Presets", action: nil, keyEquivalent: "")
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

        if isActive {
            let screenshotItem = NSMenuItem(title: "Screenshot with Effect", action: #selector(takeScreenshot), keyEquivalent: "")
            screenshotItem.target = self
            screenshotItem.image = sfIcon("camera")
            menu.addItem(screenshotItem)
        }

        menu.addItem(NSMenuItem.separator())

        // ── RetroMac Section ──
        let themeSectionHeader = NSMenuItem(title: "RetroMac", action: nil, keyEquivalent: "")
        themeSectionHeader.isEnabled = false
        menu.addItem(themeSectionHeader)

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

        // Games submenu
        let gamesItem = NSMenuItem(title: "Games", action: nil, keyEquivalent: "")
        gamesItem.image = sfIcon("gamecontroller")
        let gamesMenu = NSMenu()

        let doomItem = NSMenuItem(title: "Play Doom", action: #selector(launchDoom), keyEquivalent: "")
        doomItem.target = self
        doomItem.image = sfIcon("flame")
        gamesMenu.addItem(doomItem)

        let duke3dItem = NSMenuItem(title: "Play Duke Nukem 3D", action: #selector(launchDuke3D), keyEquivalent: "")
        duke3dItem.target = self
        duke3dItem.image = sfIcon("bolt.fill")
        gamesMenu.addItem(duke3dItem)

        gamesMenu.addItem(NSMenuItem.separator())

        let hereticItem = NSMenuItem(title: "Play Heretic", action: #selector(launchHeretic), keyEquivalent: "")
        hereticItem.target = self
        hereticItem.image = sfIcon("wand.and.stars")
        gamesMenu.addItem(hereticItem)

        let swItem = NSMenuItem(title: "Play Shadow Warrior", action: #selector(launchShadowWarrior), keyEquivalent: "")
        swItem.target = self
        swItem.image = sfIcon("figure.martial.arts")
        gamesMenu.addItem(swItem)

        let freedoomItem = NSMenuItem(title: "Play Freedoom", action: #selector(launchFreedoom), keyEquivalent: "")
        freedoomItem.target = self
        freedoomItem.image = sfIcon("shield.fill")
        gamesMenu.addItem(freedoomItem)

        gamesMenu.addItem(NSMenuItem.separator())

        let quakeItem = NSMenuItem(title: "Play Quake", action: #selector(launchQuake), keyEquivalent: "")
        quakeItem.target = self
        quakeItem.image = sfIcon("bolt.horizontal.fill")
        gamesMenu.addItem(quakeItem)

        let quake2Item = NSMenuItem(title: "Play Quake II", action: #selector(launchQuake2), keyEquivalent: "")
        quake2Item.target = self
        quake2Item.image = sfIcon("bolt.horizontal.fill")
        gamesMenu.addItem(quake2Item)

        gamesItem.submenu = gamesMenu
        menu.addItem(gamesItem)

        menu.addItem(NSMenuItem.separator())

        // ── Settings Section ──
        let settingsSectionHeader = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsSectionHeader.isEnabled = false
        menu.addItem(settingsSectionHeader)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = sfIcon("gearshape")
        menu.addItem(settingsItem)

        // Virtual Camera
        let vcam = VirtualCameraManager.shared
        let cameraTitle = vcam.isRunning ? "Stop Virtual Camera" : "Start Virtual Camera"
        let cameraItem = NSMenuItem(title: cameraTitle, action: #selector(toggleVirtualCamera), keyEquivalent: "")
        cameraItem.target = self
        if !lm.isLicensed && !vcam.isRunning {
            cameraItem.image = sfIcon("lock.fill", scale: .small)
        } else {
            cameraItem.image = sfIcon("camera.fill")
        }
        menu.addItem(cameraItem)

        // Camera Shader submenu — always visible when camera is running or was started
        do {
            let shaderItem = NSMenuItem(title: "Camera Shader", action: nil, keyEquivalent: "")
            shaderItem.image = sfIcon("camera.filters")
            let shaderMenu = NSMenu()

            // Webcam Looks (new dedicated shaders)
            let webcamHeader = NSMenuItem(title: "Webcam Looks", action: nil, keyEquivalent: "")
            webcamHeader.isEnabled = false
            shaderMenu.addItem(webcamHeader)
            let webcamShaders = [
                ("Late Night CRT", "late-night-crt"),
                ("Newsroom 1987", "newsroom-1987"),
                ("VHS Tape", "vhs-tape"),
                ("Terminal Green", "terminal-green"),
            ]
            for (name, id) in webcamShaders {
                let item = NSMenuItem(title: name, action: #selector(selectCameraShader(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = id
                if id == vcam.selectedShader { item.state = .on }
                shaderMenu.addItem(item)
            }

            shaderMenu.addItem(.separator())

            let classicHeader = NSMenuItem(title: "Classic Effects", action: nil, keyEquivalent: "")
            classicHeader.isEnabled = false
            shaderMenu.addItem(classicHeader)
            let classicShaders = [
                ("CRT Royale", "crt-royale-lite"),
                ("Trinitron TV", "trinitron-tv"),
                ("VHS", "vhs"),
                ("VCR Tracking", "vcr-tracking"),
                ("Retro LCD", "lcd-grid"),
                ("Game Boy", "gameboy"),
                ("Cinema Film", "cinema-film"),
                ("Amber Monitor", "amber-monitor"),
            ]
            for (name, id) in classicShaders {
                let item = NSMenuItem(title: name, action: #selector(selectCameraShader(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = id
                if id == vcam.selectedShader { item.state = .on }
                shaderMenu.addItem(item)
            }

            shaderItem.submenu = shaderMenu
            menu.addItem(shaderItem)
        }

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updaterController
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

        // Reset to default preset if enabled
        let settings = AppSettings.shared
        if settings.resetOnWake {
            print("[RetroMac] Wake → resetting to default preset: \(settings.defaultPreset)")
            currentPresetName = settings.defaultPreset
            currentIntensity = settings.defaultIntensity
        }

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

        // Check Screen Recording permission before attempting capture.
        // CGPreflightScreenCaptureAccess() is a pure check — no dialog.
        // After Sparkle updates the binary is re-signed and macOS revokes
        // the old grant, so this catches the common post-update case.
        if !CGPreflightScreenCaptureAccess() {
            let alert = NSAlert()
            alert.messageText = "Screen Recording Permission Required"
            alert.informativeText = "RetroMac needs Screen Recording permission to apply shader effects.\n\nAfter an update macOS may require you to re-grant this permission. Please toggle RetroMac ON in System Settings, then try again."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }

        overlayStartTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let controller = try await OverlayWindowController.create(mode: effectiveMode)

                // Check cancellation before committing
                guard !Task.isCancelled else {
                    await MainActor.run { controller.stop() }
                    return
                }

                controller.intensity = self.currentIntensity
                controller.vignetteIntensity = self.currentVignetteIntensity
                try await controller.start(presetName: presetName)

                guard !Task.isCancelled else {
                    await MainActor.run { controller.stop() }
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
                    alert.informativeText = "\(error.localizedDescription)"
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

    /// Save current overlay state so it can be restored later via `restorePreviousOverlay()`.
    func saveOverlayState() {
        savedPreset = currentPresetName
        savedWasActive = isActive
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

    /// Apply the active theme's shader preset when theme changes (from Settings or menu).
    /// Priority: theme preset > global default. TV overlay state is preserved.
    private func applyThemePresetIfNeeded() {
        let settings = AppSettings.shared
        guard settings.dockEnabled else { return }
        let themeName = settings.dockTheme

        if let preset = settings.presetForTheme(name: themeName) {
            // Theme has a shader — apply it
            if isActive {
                applyPreset(preset)
            } else {
                currentPresetName = preset
                startOverlay(mode: .fullScreen)
            }
        }
        rebuildMenu()
    }

    @objc private func disableTheme() {
        AppSettings.shared.dockEnabled = false
        DockController.shared.stop()
        ThemeManager.shared.clearActiveTheme()
        ThemeManager.shared.restoreWallpapers()
        // Also stop the CRT overlay when disabling theme
        if isActive { disableAll() }
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

    // MARK: - Doom Launcher

    @objc private func launchDoom() {
        // Check GZDoom is installed
        guard FileManager.default.fileExists(atPath: "/Applications/GZDoom.app") else {
            let alert = NSAlert()
            alert.messageText = "GZDoom Not Found"
            alert.informativeText = "Install GZDoom to play Doom with RetroMac.\n\nDownload from https://zdoom.org"
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Find a Doom WAD file — check user-configured WAD folder first, then defaults
        let gameSettings = AppSettings.shared
        let wadFolder = gameSettings.doomWadFolder
        let fm = FileManager.default

        // Build WAD search list: user folder contents first, then fallback paths
        var wadSearchPaths: [String] = []
        if let contents = try? fm.contentsOfDirectory(atPath: wadFolder) {
            let wadNames = contents.filter { $0.lowercased().hasSuffix(".wad") }.sorted { a, b in
                // Prefer full WADs: Doom2 > Doom1 > others
                let priority: (String) -> Int = { name in
                    let l = name.lowercased()
                    if l.contains("doom2") { return 0 }
                    if l.contains("plutonia") || l.contains("tnt") { return 1 }
                    if l.contains("doom") { return 2 }
                    return 3
                }
                return priority(a) < priority(b)
            }
            wadSearchPaths += wadNames.map { wadFolder + "/" + $0 }
        }
        wadSearchPaths += [
            "/Applications/GZDoom.app/Contents/MacOS/DOOM1.WAD",
        ]
        if let bundleWad = Bundle.main.resourcePath.map({ $0 + "/DOOM1.WAD" }) {
            wadSearchPaths.append(bundleWad)
        }

        guard let wadPath = wadSearchPaths.first(where: { fm.fileExists(atPath: $0) }) else {
            let alert = NSAlert()
            alert.messageText = "No Doom WAD Found"
            alert.informativeText = "Place a Doom WAD file (DOOM1.WAD, DOOM2.WAD, etc.) in:\n\(wadFolder)\n\nYou can change the WAD folder in Settings → Games."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Read window size from settings
        let winW = gameSettings.doomWindowWidth
        let winH = gameSettings.doomWindowHeight

        // Launch GZDoom via open -a to let macOS handle the app bundle properly
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        var args = [
            "-a", "/Applications/GZDoom.app",
            "--args",
            "-iwad", wadPath,
            "+vid_fullscreen", "0",
            "+win_w", "\(winW)", "+win_h", "\(winH)",
            "-width", "\(winW)", "-height", "\(winH)"
        ]

        // Load native CRT shader PK3 if bundled and any shader is enabled
        let crtEnabled = gameSettings.doomCRTShaderEnabled
        let vhsEnabled = gameSettings.doomVHSEnabled
        let warpEnabled = gameSettings.doomWarpEnabled
        if (crtEnabled || vhsEnabled || warpEnabled),
           let crtPath = Bundle.main.path(forResource: "RetroMac-CRT", ofType: "pk3") {
            args.append(contentsOf: ["-file", crtPath])
            args.append(contentsOf: [
                "+SH_CRTEnable", crtEnabled ? "true" : "false",
                "+SH_VHSEnable", vhsEnabled ? "true" : "false",
                "+SH_WarpEnable", warpEnabled ? "true" : "false"
            ])
            print("[Doom] Loading CRT shader: \(crtPath) (CRT:\(crtEnabled) VHS:\(vhsEnabled) Warp:\(warpEnabled))")
        }

        process.arguments = args
        do {
            try process.run()
            print("[Doom] Launched GZDoom with \(wadPath)")
        } catch {
            print("[Doom] Failed to launch: \(error)")
        }
    }

    // MARK: - Duke Nukem 3D Launcher (Raze)

    /// Entry point: ensures Raze + GRP are present, then launches
    @objc private func launchDuke3D() {
        let fm = FileManager.default

        // Step 1: Ensure Raze is installed
        if !fm.fileExists(atPath: "/Applications/Raze.app") {
            print("[Duke3D] Raze not found — installing automatically…")
            installRaze { [weak self] success in
                guard success else { return }
                self?.ensureDuke3DGRPAndLaunch()
            }
            return
        }

        ensureDuke3DGRPAndLaunch()
    }

    /// Step 2: Ensure DUKE3D.GRP exists, then launch
    private func ensureDuke3DGRPAndLaunch() {
        if let grpPath = findDuke3DGRP() {
            launchRazeWithGRP(grpPath: grpPath, gameName: "Duke Nukem 3D")
        } else {
            print("[Duke3D] GRP not found — downloading shareware…")
            downloadDuke3DShareware { [weak self] grpPath in
                if let grpPath = grpPath {
                    self?.launchRazeWithGRP(grpPath: grpPath, gameName: "Duke Nukem 3D")
                }
            }
        }
    }

    /// Search for DUKE3D.GRP in configured folder, common paths, and bundle
    private func findDuke3DGRP() -> String? {
        let fm = FileManager.default
        let grpFolder = AppSettings.shared.razeGrpFolder
        try? fm.createDirectory(atPath: grpFolder, withIntermediateDirectories: true, attributes: nil)

        var grpSearchPaths: [String] = []

        // User-configured folder
        if let contents = try? fm.contentsOfDirectory(atPath: grpFolder) {
            let grpFiles = contents.filter { $0.lowercased().hasSuffix(".grp") }.sorted { a, b in
                let priority: (String) -> Int = { name in
                    let l = name.lowercased()
                    if l.contains("duke3d") { return 0 }
                    return 1
                }
                return priority(a) < priority(b)
            }
            grpSearchPaths += grpFiles.map { grpFolder + "/" + $0 }
        }

        // Common Raze/Duke3D paths
        let homeDir = NSHomeDirectory()
        grpSearchPaths += [
            homeDir + "/Library/Application Support/Raze/DUKE3D.GRP",
            homeDir + "/Library/Application Support/Raze/duke3d.grp",
            "/Applications/Raze.app/Contents/MacOS/DUKE3D.GRP",
        ]

        // Bundled shareware
        if let bundleGrp = Bundle.main.resourcePath.map({ $0 + "/DUKE3D.GRP" }) {
            grpSearchPaths.append(bundleGrp)
        }

        return grpSearchPaths.first(where: { fm.fileExists(atPath: $0) })
    }

    /// Shared Raze launcher for Duke3D and Shadow Warrior
    private func launchRazeWithGRP(grpPath: String, gameName: String) {
        let settings = AppSettings.shared
        let winW = settings.razeWindowWidth
        let winH = settings.razeWindowHeight

        // Patch raze.ini to force windowed mode and correct size
        patchRazeConfig(width: winW, height: winH)

        // Launch Raze binary directly (open -a doesn't reliably pass args)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/Applications/Raze.app/Contents/MacOS/raze")
        var args = ["-iwad", grpPath]

        // Load native CRT shader PK3 if enabled (Raze supports -file like GZDoom)
        let crtEnabled = gameName == "Shadow Warrior" ? settings.shadowWarriorCRTEnabled : settings.razeCRTShaderEnabled
        if crtEnabled,
           let crtPath = Bundle.main.path(forResource: "RetroMac-CRT", ofType: "pk3") {
            args.append(contentsOf: ["-file", crtPath])
            args.append(contentsOf: ["+SH_CRTEnable", "true", "+SH_VHSEnable", "false", "+SH_WarpEnable", "false"])
            print("[\(gameName)] Loading internal CRT shader: \(crtPath)")
        }

        process.arguments = args

        // Set working directory so Raze finds its pk3
        process.currentDirectoryURL = URL(fileURLWithPath: "/Applications/Raze.app/Contents/MacOS")

        do {
            try process.run()
            print("[\(gameName)] Launched Raze with \(grpPath) (\(winW)x\(winH) windowed)")
        } catch {
            print("[\(gameName)] Failed to launch: \(error)")
        }
    }

    /// Patch raze.ini to enforce windowed mode and window size
    private func patchRazeConfig(width: Int, height: Int) {
        let iniPath = NSHomeDirectory() + "/Library/Preferences/raze.ini"
        let fm = FileManager.default

        guard fm.fileExists(atPath: iniPath),
              var content = try? String(contentsOfFile: iniPath, encoding: .utf8) else {
            // No config yet — Raze will create one on first launch; write a minimal one
            let dir = NSHomeDirectory() + "/Library/Preferences"
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
            let minimal = """
            [GlobalSettings]
            vid_fullscreen=false
            vid_defwidth=\(width)
            vid_defheight=\(height)
            win_w=\(width)
            win_h=\(height)

            """
            try? minimal.write(toFile: iniPath, atomically: true, encoding: .utf8)
            print("[Duke3D] Created raze.ini with windowed \(width)x\(height)")
            return
        }

        let replacements: [(String, String)] = [
            ("vid_fullscreen=true", "vid_fullscreen=false"),
            ("vid_nativefullscreen=true", "vid_nativefullscreen=false"),
        ]
        for (old, new) in replacements {
            content = content.replacingOccurrences(of: old, with: new)
        }

        // Update window size values
        let sizePatterns: [(String, String)] = [
            ("vid_defwidth=", "vid_defwidth=\(width)"),
            ("vid_defheight=", "vid_defheight=\(height)"),
            ("win_w=", "win_w=\(width)"),
            ("win_h=", "win_h=\(height)"),
        ]
        for (prefix, replacement) in sizePatterns {
            if let range = content.range(of: prefix) {
                // Find end of line from prefix
                let lineStart = range.lowerBound
                let afterPrefix = range.upperBound
                let lineEnd = content[afterPrefix...].firstIndex(of: "\n") ?? content.endIndex
                content.replaceSubrange(lineStart..<lineEnd, with: replacement)
            }
        }

        try? content.write(toFile: iniPath, atomically: true, encoding: .utf8)
        print("[Duke3D] Patched raze.ini: windowed \(width)x\(height)")
    }

    // MARK: - Heretic Launcher (GZDoom)

    @objc private func launchHeretic() {
        guard FileManager.default.fileExists(atPath: "/Applications/GZDoom.app") else {
            let alert = NSAlert()
            alert.messageText = "GZDoom Not Found"
            alert.informativeText = "Install GZDoom to play Heretic with RetroMac.\n\nDownload from https://zdoom.org"
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Find HERETIC1.WAD
        let settings = AppSettings.shared
        let wadFolder = settings.doomWadFolder  // shares folder with Doom
        let fm = FileManager.default

        var wadPaths: [String] = []
        if let contents = try? fm.contentsOfDirectory(atPath: wadFolder) {
            wadPaths += contents.filter { $0.lowercased().contains("heretic") && $0.lowercased().hasSuffix(".wad") }
                .map { wadFolder + "/" + $0 }
        }
        // Bundled shareware
        if let bundled = Bundle.main.resourcePath.map({ $0 + "/HERETIC1.WAD" }) {
            wadPaths.append(bundled)
        }

        guard let wadPath = wadPaths.first(where: { fm.fileExists(atPath: $0) }) else {
            // Auto-download shareware
            downloadHereticShareware()
            return
        }

        launchGZDoomGame(wadPath: wadPath, gameName: "Heretic")
    }

    /// Shared GZDoom launcher for Doom-engine games (Heretic, etc.)
    private func launchGZDoomGame(wadPath: String, gameName: String) {
        let settings = AppSettings.shared
        let winW = settings.doomWindowWidth
        let winH = settings.doomWindowHeight

        // Detect shareware WAD — GZDoom blocks -file with shareware IWADs
        let wadName = (wadPath as NSString).lastPathComponent.lowercased()
        let isShareware = wadName.hasPrefix("doom1") || wadName.hasPrefix("heretic1")
            || wadName.hasPrefix("hexen") && wadName.contains("demo")
            || wadName.hasPrefix("strife0")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        var args = [
            "-a", "/Applications/GZDoom.app",
            "--args",
            "-iwad", wadPath,
            "+vid_fullscreen", "0",
            "+win_w", "\(winW)", "+win_h", "\(winH)",
            "-width", "\(winW)", "-height", "\(winH)"
        ]

        // Load CRT shader PK3 if enabled (NOT compatible with shareware WADs —
        // GZDoom blocks -file with shareware IWADs, so shader is simply skipped)
        let crtEnabled = gameName == "Heretic" ? settings.hereticCRTShaderEnabled : settings.doomCRTShaderEnabled
        if isShareware {
            print("[\(gameName)] Shareware WAD detected — native PK3 shader not supported, skipping")
        } else if crtEnabled, let crtPath = Bundle.main.path(forResource: "RetroMac-CRT", ofType: "pk3") {
            args.append(contentsOf: ["-file", crtPath, "+SH_CRTEnable", "true"])
            print("[\(gameName)] Loading CRT shader PK3")
        }

        process.arguments = args
        do {
            try process.run()
            print("[\(gameName)] Launched GZDoom with \(wadPath)")
        } catch {
            print("[\(gameName)] Failed to launch: \(error)")
        }
    }

    private func downloadHereticShareware() {
        let targetDir = AppSettings.shared.doomWadFolder
        let targetWAD = targetDir + "/HERETIC1.WAD"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true, attributes: nil)

        if fm.fileExists(atPath: targetWAD) { launchHeretic(); return }

        let progressWindow = createProgressWindow(title: "Downloading Heretic…", detail: "Downloading Heretic Shareware…")

        guard let url = URL(string: "https://archive.org/download/hereticsw/hereticsw.zip") else {
            progressWindow.close(); return
        }

        URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            guard let tempURL = tempURL, error == nil else {
                DispatchQueue.main.async {
                    progressWindow.close()
                    let alert = NSAlert()
                    alert.messageText = "Download Failed"
                    alert.informativeText = error?.localizedDescription ?? "Download failed."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                return
            }

            let tempDir = NSTemporaryDirectory() + "heretic_extract"
            try? fm.removeItem(atPath: tempDir)
            try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true, attributes: nil)

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", "-j", tempURL.path, "-d", tempDir]
            unzip.standardOutput = FileHandle.nullDevice
            unzip.standardError = FileHandle.nullDevice
            try? unzip.run()
            unzip.waitUntilExit()

            // Find HERETIC1.WAD
            var found: String?
            if let contents = try? fm.contentsOfDirectory(atPath: tempDir) {
                found = contents.first(where: { $0.lowercased().contains("heretic") && $0.lowercased().hasSuffix(".wad") })
                    .map { tempDir + "/" + $0 }
            }

            if let src = found {
                try? fm.copyItem(atPath: src, toPath: targetWAD)
                print("[Heretic] Shareware WAD installed to \(targetWAD)")
            }
            try? fm.removeItem(atPath: tempDir)

            DispatchQueue.main.async {
                progressWindow.close()
                if fm.fileExists(atPath: targetWAD) {
                    self?.launchHeretic()
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Extraction Failed"
                    alert.informativeText = "HERETIC1.WAD not found in archive."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }.resume()
    }

    // MARK: - Shadow Warrior Launcher (Raze)

    @objc private func launchShadowWarrior() {
        let fm = FileManager.default

        if !fm.fileExists(atPath: "/Applications/Raze.app") {
            installRaze { [weak self] success in
                guard success else { return }
                self?.ensureSWGRPAndLaunch()
            }
            return
        }
        ensureSWGRPAndLaunch()
    }

    private func ensureSWGRPAndLaunch() {
        if let grpPath = findSWGRP() {
            launchRazeWithGRP(grpPath: grpPath, gameName: "Shadow Warrior")
        } else {
            downloadSWShareware { [weak self] path in
                if let path = path {
                    self?.launchRazeWithGRP(grpPath: path, gameName: "Shadow Warrior")
                }
            }
        }
    }

    private func findSWGRP() -> String? {
        let fm = FileManager.default
        let grpFolder = AppSettings.shared.razeGrpFolder
        try? fm.createDirectory(atPath: grpFolder, withIntermediateDirectories: true, attributes: nil)

        var paths: [String] = []
        if let contents = try? fm.contentsOfDirectory(atPath: grpFolder) {
            paths += contents.filter { $0.lowercased() == "sw.grp" }.map { grpFolder + "/" + $0 }
        }
        let home = NSHomeDirectory()
        paths += [
            home + "/Library/Application Support/Raze/SW.GRP",
            home + "/Library/Application Support/Raze/sw.grp",
        ]
        return paths.first(where: { fm.fileExists(atPath: $0) })
    }

    private func downloadSWShareware(completion: @escaping (String?) -> Void) {
        let targetDir = AppSettings.shared.razeGrpFolder
        let targetGRP = targetDir + "/SW.GRP"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true, attributes: nil)

        if fm.fileExists(atPath: targetGRP) { completion(targetGRP); return }

        let progressWindow = createProgressWindow(title: "Downloading Shadow Warrior…", detail: "Downloading Shadow Warrior Shareware…")
        guard let url = URL(string: "https://archive.org/download/swp426shadowwarriorshareware/Swp426.zip") else {
            progressWindow.close(); completion(nil); return
        }

        URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            guard let tempURL = tempURL, error == nil else {
                DispatchQueue.main.async {
                    progressWindow.close()
                    let alert = NSAlert(); alert.messageText = "Download Failed"
                    alert.informativeText = error?.localizedDescription ?? "Download failed."
                    alert.addButton(withTitle: "OK"); alert.runModal()
                    completion(nil)
                }
                return
            }

            let tempDir = NSTemporaryDirectory() + "sw_extract"
            try? fm.removeItem(atPath: tempDir)
            try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true, attributes: nil)

            // DO NOT use -j flag — file is in Swp426/ subfolder
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", tempURL.path, "-d", tempDir]
            unzip.standardOutput = FileHandle.nullDevice
            unzip.standardError = FileHandle.nullDevice
            try? unzip.run()
            unzip.waitUntilExit()

            // Find SW.GRP recursively
            var found: String?
            if let enumerator = fm.enumerator(atPath: tempDir) {
                while let file = enumerator.nextObject() as? String {
                    if file.lowercased().hasSuffix("/sw.grp") || file.lowercased() == "sw.grp" {
                        found = tempDir + "/" + file
                        break
                    }
                }
            }

            if let src = found {
                try? fm.removeItem(atPath: targetGRP)
                try? fm.copyItem(atPath: src, toPath: targetGRP)
                print("[ShadowWarrior] Shareware GRP installed to \(targetGRP)")
            }
            try? fm.removeItem(atPath: tempDir)

            DispatchQueue.main.async {
                progressWindow.close()
                completion(fm.fileExists(atPath: targetGRP) ? targetGRP : nil)
            }
        }.resume()
    }

    // MARK: - Freedoom Launcher (GZDoom)

    @objc private func launchFreedoom() {
        let fm = FileManager.default

        // Check GZDoom installed
        guard fm.fileExists(atPath: "/Applications/GZDoom.app") else {
            let alert = NSAlert()
            alert.messageText = "GZDoom Not Found"
            alert.informativeText = "Install GZDoom to play Freedoom.\n\nDownload from https://zdoom.org"
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        ensureFreedoomAndLaunch()
    }

    private func ensureFreedoomAndLaunch() {
        let settings = AppSettings.shared
        let wadDir = settings.doomWadFolder
        let freedoomWAD = wadDir + "/freedoom1.wad"
        let fm = FileManager.default

        if fm.fileExists(atPath: freedoomWAD) {
            launchFreedoomGame(wadPath: freedoomWAD)
        } else {
            downloadFreedoom { [weak self] success in
                if success {
                    self?.launchFreedoomGame(wadPath: freedoomWAD)
                }
            }
        }
    }

    private func launchFreedoomGame(wadPath: String) {
        let settings = AppSettings.shared
        let winW = settings.doomWindowWidth
        let winH = settings.doomWindowHeight

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        var args = [
            "-a", "/Applications/GZDoom.app",
            "--args",
            "-iwad", wadPath,
            "+vid_fullscreen", "0",
            "+win_w", "\(winW)", "+win_h", "\(winH)",
            "-width", "\(winW)", "-height", "\(winH)"
        ]

        // Load native CRT shader PK3 — Freedoom is NOT shareware, -file always works
        if settings.freedoomCRTShaderEnabled,
           let crtPath = Bundle.main.path(forResource: "RetroMac-CRT", ofType: "pk3") {
            args.append(contentsOf: ["-file", crtPath, "+SH_CRTEnable", "true"])
            print("[Freedoom] Loading CRT shader PK3")
        }

        process.arguments = args
        do {
            try process.run()
            print("[Freedoom] Launched GZDoom with \(wadPath)")
        } catch {
            print("[Freedoom] Failed to launch: \(error)")
        }
    }

    private func downloadFreedoom(completion: @escaping (Bool) -> Void) {
        let settings = AppSettings.shared
        let wadDir = settings.doomWadFolder
        let targetWAD = wadDir + "/freedoom1.wad"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: wadDir, withIntermediateDirectories: true, attributes: nil)

        if fm.fileExists(atPath: targetWAD) { completion(true); return }

        let progressWindow = createProgressWindow(title: "Downloading Freedoom…", detail: "Downloading Freedoom Phase 1…")
        guard let url = URL(string: "https://github.com/freedoom/freedoom/releases/download/v0.13.0/freedoom-0.13.0.zip") else {
            progressWindow.close(); completion(false); return
        }

        URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            guard let tempURL = tempURL, error == nil else {
                DispatchQueue.main.async {
                    progressWindow.close()
                    let alert = NSAlert()
                    alert.messageText = "Download Failed"
                    alert.informativeText = error?.localizedDescription ?? "Download failed."
                    alert.addButton(withTitle: "OK"); alert.runModal()
                    completion(false)
                }
                return
            }

            DispatchQueue.main.async {
                self?.updateProgressWindow(progressWindow, detail: "Extracting freedoom1.wad…")
            }

            let tempDir = NSTemporaryDirectory() + "freedoom_extract"
            try? fm.removeItem(atPath: tempDir)
            try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true, attributes: nil)

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", tempURL.path, "-d", tempDir]
            unzip.standardOutput = FileHandle.nullDevice
            unzip.standardError = FileHandle.nullDevice
            try? unzip.run()
            unzip.waitUntilExit()

            // Find freedoom1.wad recursively
            var found: String?
            if let enumerator = fm.enumerator(atPath: tempDir) {
                while let file = enumerator.nextObject() as? String {
                    if file.lowercased().hasSuffix("freedoom1.wad") {
                        found = tempDir + "/" + file
                        break
                    }
                }
            }

            if let src = found {
                try? fm.removeItem(atPath: targetWAD)
                try? fm.copyItem(atPath: src, toPath: targetWAD)
                print("[Freedoom] freedoom1.wad installed to \(targetWAD)")
            }
            try? fm.removeItem(atPath: tempDir)

            DispatchQueue.main.async {
                progressWindow.close()
                completion(fm.fileExists(atPath: targetWAD))
            }
        }.resume()
    }

    // MARK: - Quake Launcher (RetroArch + TyrQuake)

    @objc private func launchQuake() {
        ensureRetroArch { [weak self] success in
            guard success else { return }
            self?.ensureRetroArchCore(coreName: "tyrquake_libretro") { coreSuccess in
                guard coreSuccess else { return }
                self?.ensureQuakePAKAndLaunch()
            }
        }
    }

    private func ensureQuakePAKAndLaunch() {
        let settings = AppSettings.shared
        let basePath = settings.quakeBasePath
        let pakPath = basePath + "/id1/PAK0.PAK"
        let fm = FileManager.default

        if fm.fileExists(atPath: pakPath) {
            launchRetroArchQuake(basePath: basePath)
        } else {
            downloadQuakeShareware { [weak self] success in
                if success {
                    self?.launchRetroArchQuake(basePath: basePath)
                }
            }
        }
    }

    private func launchRetroArchQuake(basePath: String) {
        let coresDir = NSHomeDirectory() + "/Library/Application Support/RetroArch/cores"
        let corePath = coresDir + "/tyrquake_libretro.dylib"
        let pakPath = basePath + "/id1/PAK0.PAK"
        let shaderPath = NSHomeDirectory() + "/Library/Application Support/RetroArch/shaders/shaders_slang/crt/crt-geom.slangp"

        // Write WASD config for Quake 1 if not present
        writeQuake1Config(basePath: basePath)

        // Patch RetroArch main config for mouse + shader + game focus
        writeRetroArchQuakeConfig()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/Applications/RetroArch.app/Contents/MacOS/RetroArch")
        process.arguments = ["-L", corePath, pakPath, "--set-shader", shaderPath]

        do {
            try process.run()
            print("[Quake] Launched RetroArch + TyrQuake with CRT shader")
        } catch {
            print("[Quake] Failed to launch RetroArch: \(error)")
        }
    }

    // MARK: - Quake II Launcher (RetroArch + Vitaquake2)

    @objc private func launchQuake2() {
        ensureRetroArch { [weak self] success in
            guard success else { return }
            self?.ensureRetroArchCore(coreName: "vitaquake2_libretro") { coreSuccess in
                guard coreSuccess else { return }
                self?.ensureQuake2PAKAndLaunch()
            }
        }
    }

    private func ensureQuake2PAKAndLaunch() {
        let settings = AppSettings.shared
        let basePath = settings.quake2BasePath
        let pakPath = basePath + "/baseq2/pak0.pak"
        let fm = FileManager.default

        if fm.fileExists(atPath: pakPath) {
            launchRetroArchQuake2(basePath: basePath)
        } else {
            downloadQuake2Demo { [weak self] success in
                if success {
                    self?.launchRetroArchQuake2(basePath: basePath)
                }
            }
        }
    }

    private func launchRetroArchQuake2(basePath: String) {
        let coresDir = NSHomeDirectory() + "/Library/Application Support/RetroArch/cores"
        let corePath = coresDir + "/vitaquake2_libretro.dylib"
        let pakPath = basePath + "/baseq2/pak0.pak"
        let shaderPath = NSHomeDirectory() + "/Library/Application Support/RetroArch/shaders/shaders_slang/crt/crt-geom.slangp"

        // Write WASD config for Quake 2 if not present
        writeQuake2Config(basePath: basePath)

        writeRetroArchQuakeConfig()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/Applications/RetroArch.app/Contents/MacOS/RetroArch")
        process.arguments = ["-L", corePath, pakPath, "--set-shader", shaderPath]

        do {
            try process.run()
            print("[Quake2] Launched RetroArch + Vitaquake2 with CRT shader")
        } catch {
            print("[Quake2] Failed to launch RetroArch: \(error)")
        }
    }

    private func downloadQuake2Demo(completion: @escaping (Bool) -> Void) {
        let settings = AppSettings.shared
        let basePath = settings.quake2BasePath
        let baseq2Path = basePath + "/baseq2"
        let targetPAK = baseq2Path + "/pak0.pak"
        let fm = FileManager.default

        try? fm.createDirectory(atPath: baseq2Path, withIntermediateDirectories: true, attributes: nil)
        if fm.fileExists(atPath: targetPAK) { completion(true); return }

        let progressWindow = createProgressWindow(title: "Downloading Quake II…", detail: "Downloading Quake II Demo…")
        // Quake 2 demo from archive.org
        guard let url = URL(string: "https://archive.org/download/quake-ii-demo/q2-314-demo-x86.exe") else {
            progressWindow.close(); completion(false); return
        }

        URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            guard let tempURL = tempURL, error == nil else {
                DispatchQueue.main.async {
                    progressWindow.close()
                    let alert = NSAlert()
                    alert.messageText = "Download Failed"
                    alert.informativeText = error?.localizedDescription ?? "Download failed."
                    alert.addButton(withTitle: "OK"); alert.runModal()
                    completion(false)
                }
                return
            }

            DispatchQueue.main.async {
                self?.updateProgressWindow(progressWindow, detail: "Extracting pak0.pak…")
            }

            // The demo .exe is a self-extracting ZIP — unzip works on it
            let tempDir = NSTemporaryDirectory() + "quake2_extract"
            try? fm.removeItem(atPath: tempDir)
            try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true, attributes: nil)

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", tempURL.path, "-d", tempDir]
            unzip.standardOutput = FileHandle.nullDevice
            unzip.standardError = FileHandle.nullDevice
            try? unzip.run()
            unzip.waitUntilExit()

            // Find pak0.pak recursively
            var found: String?
            if let enumerator = fm.enumerator(atPath: tempDir) {
                while let file = enumerator.nextObject() as? String {
                    if file.lowercased().hasSuffix("pak0.pak") {
                        found = tempDir + "/" + file
                        break
                    }
                }
            }

            if let src = found {
                try? fm.removeItem(atPath: targetPAK)
                try? fm.copyItem(atPath: src, toPath: targetPAK)
                print("[Quake2] pak0.pak installed to \(targetPAK)")
            }
            try? fm.removeItem(atPath: tempDir)

            DispatchQueue.main.async {
                progressWindow.close()
                completion(fm.fileExists(atPath: targetPAK))
            }
        }.resume()
    }

    // MARK: - Quake Config Helpers

    /// Write Quake 1 config.cfg with WASD bindings + mouse look
    private func writeQuake1Config(basePath: String) {
        let configPath = basePath + "/id1/config.cfg"
        let fm = FileManager.default
        // Don't overwrite if user already has a config
        if fm.fileExists(atPath: configPath) { return }
        try? fm.createDirectory(atPath: basePath + "/id1", withIntermediateDirectories: true, attributes: nil)

        let config = """
        // RetroMac WASD config for Quake
        bind w "+forward"
        bind s "+back"
        bind a "+moveleft"
        bind d "+moveright"
        bind SPACE "+jump"
        bind SHIFT "+speed"
        bind MOUSE1 "+attack"
        bind MOUSE2 "+jump"
        bind e "+mlook"
        bind 1 "impulse 1"
        bind 2 "impulse 2"
        bind 3 "impulse 3"
        bind 4 "impulse 4"
        bind 5 "impulse 5"
        bind 6 "impulse 6"
        bind 7 "impulse 7"
        bind 8 "impulse 8"
        bind ESCAPE "togglemenu"
        bind ENTER "+jump"
        +mlook
        sensitivity 4
        """
        try? config.write(toFile: configPath, atomically: true, encoding: .utf8)
        print("[Quake] Wrote WASD config to \(configPath)")
    }

    /// Write Quake 2 config.cfg with WASD bindings
    private func writeQuake2Config(basePath: String) {
        let configPath = basePath + "/baseq2/config.cfg"
        let fm = FileManager.default
        if fm.fileExists(atPath: configPath) { return }
        try? fm.createDirectory(atPath: basePath + "/baseq2", withIntermediateDirectories: true, attributes: nil)

        let config = """
        // RetroMac WASD config for Quake II
        bind w "+forward"
        bind s "+back"
        bind a "+moveleft"
        bind d "+moveright"
        bind SPACE "+moveup"
        bind c "+movedown"
        bind SHIFT "+speed"
        bind MOUSE1 "+attack"
        bind MOUSE2 "+moveup"
        bind e "use"
        bind r "reload"
        bind 1 "use Blaster"
        bind 2 "use Shotgun"
        bind 3 "use Super Shotgun"
        bind 4 "use Machinegun"
        bind 5 "use Chaingun"
        bind 6 "use Grenade Launcher"
        bind 7 "use Rocket Launcher"
        bind 8 "use HyperBlaster"
        bind 9 "use Railgun"
        bind 0 "use BFG10K"
        bind ENTER "invuse"
        bind ESCAPE "togglemenu"
        bind TAB "inven"
        set freelook "1"
        set cl_run "1"
        set sensitivity "4"
        """
        try? config.write(toFile: configPath, atomically: true, encoding: .utf8)
        print("[Quake2] Wrote WASD config to \(configPath)")
    }

    /// Patch RetroArch's main config for fullscreen FPS with keyboard+mouse
    private func writeRetroArchQuakeConfig() {
        let fm = FileManager.default
        let mainConfigPath = NSHomeDirectory() + "/Library/Application Support/RetroArch/config/retroarch.cfg"

        guard fm.fileExists(atPath: mainConfigPath),
              var config = try? String(contentsOfFile: mainConfigPath, encoding: .utf8) else {
            print("[RetroArch] Config not found at \(mainConfigPath)")
            return
        }

        let patches: [(String, String)] = [
            ("input_auto_game_focus", "\"2\""),
            ("input_auto_mouse_grab", "\"true\""),
            ("input_game_focus_toggle", "\"nul\""),
            ("input_menu_toggle", "\"f1\""),
            ("video_shader_enable", "\"true\""),
            ("video_fullscreen", "\"true\""),
            ("input_libretro_device_p1", "\"3\""),
        ]

        for (key, value) in patches {
            if let range = config.range(of: "\(key) = .*", options: .regularExpression) {
                config.replaceSubrange(range, with: "\(key) = \(value)")
            } else {
                config.append("\n\(key) = \(value)")
            }
        }

        try? config.write(toFile: mainConfigPath, atomically: true, encoding: .utf8)
        print("[RetroArch] Patched config: fullscreen + keyboard+mouse device + shader")
    }

    // MARK: - RetroArch Infrastructure

    /// Ensure RetroArch is installed, download if missing
    private func ensureRetroArch(completion: @escaping (Bool) -> Void) {
        let fm = FileManager.default
        if fm.fileExists(atPath: "/Applications/RetroArch.app") {
            completion(true)
            return
        }

        let progressWindow = createProgressWindow(title: "Installing RetroArch…", detail: "Downloading RetroArch (Universal)…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let tempDir = NSTemporaryDirectory() + "retroarch_install"
            try? fm.removeItem(atPath: tempDir)
            try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true, attributes: nil)

            let dmgPath = tempDir + "/RetroArch.dmg"
            let mountPoint = tempDir + "/ra_mount"
            try? fm.createDirectory(atPath: mountPoint, withIntermediateDirectories: true, attributes: nil)

            let dmgURL = "https://buildbot.libretro.com/stable/1.22.2/apple/osx/universal/RetroArch_Metal.dmg"

            let download = Process()
            download.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            download.arguments = ["-L", "-s", "-o", dmgPath,
                                  "-H", "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
                                  dmgURL]
            try? download.run()
            download.waitUntilExit()

            guard download.terminationStatus == 0,
                  fm.fileExists(atPath: dmgPath),
                  (try? fm.attributesOfItem(atPath: dmgPath)[.size] as? Int) ?? 0 > 1_000_000 else {
                print("[RetroArch] DMG download failed")
                DispatchQueue.main.async {
                    progressWindow.close()
                    let alert = NSAlert()
                    alert.messageText = "Installation Failed"
                    alert.informativeText = "Could not download RetroArch. Please install manually from retroarch.com."
                    alert.addButton(withTitle: "Open Website")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(URL(string: "https://www.retroarch.com/?page=platforms")!)
                    }
                    completion(false)
                }
                return
            }

            DispatchQueue.main.async {
                self?.updateProgressWindow(progressWindow, detail: "Installing RetroArch…")
            }

            let mount = Process()
            mount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            mount.arguments = ["attach", dmgPath, "-mountpoint", mountPoint, "-nobrowse", "-quiet"]
            try? mount.run()
            mount.waitUntilExit()

            if let appPath = self?.findAppBundle(named: "RetroArch", in: mountPoint) {
                self?.copyAppToApplications(appPath: appPath, targetName: "RetroArch.app") { success in
                    let detach = Process()
                    detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                    detach.arguments = ["detach", mountPoint, "-quiet"]
                    try? detach.run(); detach.waitUntilExit()
                    try? fm.removeItem(atPath: tempDir)

                    // Download Slang shaders after RetroArch is installed
                    if success { self?.ensureRetroArchShaders() }

                    DispatchQueue.main.async { progressWindow.close(); completion(success) }
                }
            } else {
                let detach = Process()
                detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                detach.arguments = ["detach", mountPoint, "-quiet"]
                try? detach.run(); detach.waitUntilExit()
                try? fm.removeItem(atPath: tempDir)
                DispatchQueue.main.async { progressWindow.close(); completion(false) }
            }
        }
    }

    /// Download a RetroArch core from the libretro buildbot
    private func ensureRetroArchCore(coreName: String, completion: @escaping (Bool) -> Void) {
        let coresDir = NSHomeDirectory() + "/Library/Application Support/RetroArch/cores"
        let corePath = coresDir + "/\(coreName).dylib"
        let fm = FileManager.default

        if fm.fileExists(atPath: corePath) {
            completion(true)
            return
        }

        try? fm.createDirectory(atPath: coresDir, withIntermediateDirectories: true, attributes: nil)

        let progressWindow = createProgressWindow(title: "Downloading Core…", detail: "Downloading \(coreName)…")
        let coreURL = "https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/\(coreName).dylib.zip"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let tempDir = NSTemporaryDirectory() + "core_download"
            let zipPath = tempDir + "/core.zip"
            try? fm.removeItem(atPath: tempDir)
            try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true, attributes: nil)

            let download = Process()
            download.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            download.arguments = ["-L", "-s", "-o", zipPath, coreURL]
            try? download.run()
            download.waitUntilExit()

            guard download.terminationStatus == 0, fm.fileExists(atPath: zipPath) else {
                print("[RetroArch] Core download failed: \(coreName)")
                DispatchQueue.main.async { progressWindow.close(); completion(false) }
                return
            }

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", zipPath, "-d", coresDir]
            unzip.standardOutput = FileHandle.nullDevice
            unzip.standardError = FileHandle.nullDevice
            try? unzip.run()
            unzip.waitUntilExit()

            try? fm.removeItem(atPath: tempDir)
            let success = fm.fileExists(atPath: corePath)
            print("[RetroArch] Core \(coreName): \(success ? "installed" : "failed")")
            DispatchQueue.main.async { progressWindow.close(); completion(success) }
        }
    }

    /// Ensure Slang CRT shaders are downloaded
    private func ensureRetroArchShaders() {
        let shadersDir = NSHomeDirectory() + "/Library/Application Support/RetroArch/shaders/shaders_slang/crt"
        let fm = FileManager.default

        // Check if crt-geom shader already exists
        if fm.fileExists(atPath: shadersDir + "/crt-geom.slangp") { return }

        let baseShaderDir = NSHomeDirectory() + "/Library/Application Support/RetroArch/shaders"
        try? fm.createDirectory(atPath: baseShaderDir, withIntermediateDirectories: true, attributes: nil)

        let shadersURL = "https://buildbot.libretro.com/assets/frontend/shaders_slang.zip"
        let tempDir = NSTemporaryDirectory() + "shaders_download"
        let zipPath = tempDir + "/shaders.zip"
        try? fm.removeItem(atPath: tempDir)
        try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true, attributes: nil)

        DispatchQueue.global(qos: .utility).async {
            let download = Process()
            download.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            download.arguments = ["-L", "-s", "-o", zipPath, shadersURL]
            try? download.run()
            download.waitUntilExit()

            guard download.terminationStatus == 0, fm.fileExists(atPath: zipPath) else {
                print("[RetroArch] Shader download failed")
                try? fm.removeItem(atPath: tempDir)
                return
            }

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", zipPath, "-d", baseShaderDir]
            unzip.standardOutput = FileHandle.nullDevice
            unzip.standardError = FileHandle.nullDevice
            try? unzip.run()
            unzip.waitUntilExit()

            try? fm.removeItem(atPath: tempDir)
            print("[RetroArch] Slang shaders installed")
        }
    }

    private func downloadQuakeShareware(completion: @escaping (Bool) -> Void) {
        let settings = AppSettings.shared
        let basePath = settings.quakeBasePath
        let id1Path = basePath + "/id1"
        let targetPAK = id1Path + "/PAK0.PAK"
        let fm = FileManager.default

        try? fm.createDirectory(atPath: id1Path, withIntermediateDirectories: true, attributes: nil)
        if fm.fileExists(atPath: targetPAK) { completion(true); return }

        let progressWindow = createProgressWindow(title: "Downloading Quake…", detail: "Downloading Quake Shareware (Episode 1)…")
        guard let url = URL(string: "https://archive.org/download/quakeshareware/QUAKE_SW.zip") else {
            progressWindow.close(); completion(false); return
        }

        URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            guard let tempURL = tempURL, error == nil else {
                DispatchQueue.main.async {
                    progressWindow.close()
                    let alert = NSAlert()
                    alert.messageText = "Download Failed"
                    alert.informativeText = error?.localizedDescription ?? "Download failed."
                    alert.addButton(withTitle: "OK"); alert.runModal()
                    completion(false)
                }
                return
            }

            DispatchQueue.main.async {
                self?.updateProgressWindow(progressWindow, detail: "Extracting PAK0.PAK…")
            }

            let tempDir = NSTemporaryDirectory() + "quake_extract"
            try? fm.removeItem(atPath: tempDir)
            try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true, attributes: nil)

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", tempURL.path, "-d", tempDir]
            unzip.standardOutput = FileHandle.nullDevice
            unzip.standardError = FileHandle.nullDevice
            try? unzip.run()
            unzip.waitUntilExit()

            // Find PAK0.PAK recursively (it's at QUAKE_SW/ID1/PAK0.PAK)
            var found: String?
            if let enumerator = fm.enumerator(atPath: tempDir) {
                while let file = enumerator.nextObject() as? String {
                    if file.lowercased().hasSuffix("pak0.pak") {
                        found = tempDir + "/" + file
                        break
                    }
                }
            }

            if let src = found {
                try? fm.removeItem(atPath: targetPAK)
                try? fm.copyItem(atPath: src, toPath: targetPAK)
                print("[Quake] PAK0.PAK installed to \(targetPAK)")
            }
            try? fm.removeItem(atPath: tempDir)

            DispatchQueue.main.async {
                progressWindow.close()
                completion(fm.fileExists(atPath: targetPAK))
            }
        }.resume()
    }

    // MARK: - Raze Auto-Install

    /// Download and install Raze.app from GitHub releases
    private func installRaze(completion: @escaping (Bool) -> Void) {
        // Show progress window
        let progressWindow = createProgressWindow(title: "Installing Raze…", detail: "Fetching latest release from GitHub…")

        // Query GitHub API for latest release
        guard let apiURL = URL(string: "https://api.github.com/repos/ZDoom/Raze/releases/latest") else {
            progressWindow.close()
            completion(false)
            return
        }

        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assets = json["assets"] as? [[String: Any]] else {
                DispatchQueue.main.async {
                    progressWindow.close()
                    let alert = NSAlert()
                    alert.messageText = "Download Failed"
                    alert.informativeText = "Could not fetch Raze release info from GitHub.\n\(error?.localizedDescription ?? "")"
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    completion(false)
                }
                return
            }

            let version = json["tag_name"] as? String ?? "latest"

            // Find macOS asset — prefer .dmg, then .zip (Raze ships macOS as DMG)
            let macAsset = assets.first(where: { asset in
                let name = (asset["name"] as? String ?? "").lowercased()
                return name.contains("macos") && (name.hasSuffix(".dmg") || name.hasSuffix(".zip"))
            })

            guard let asset = macAsset,
                  let downloadURLString = asset["browser_download_url"] as? String,
                  let downloadURL = URL(string: downloadURLString) else {
                DispatchQueue.main.async {
                    progressWindow.close()
                    let alert = NSAlert()
                    alert.messageText = "No macOS Build Found"
                    alert.informativeText = "The latest Raze release (\(version)) does not include a macOS build.\nPlease install Raze manually from:\nhttps://github.com/ZDoom/Raze/releases"
                    alert.addButton(withTitle: "Open GitHub")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        if let url = URL(string: "https://github.com/ZDoom/Raze/releases") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    completion(false)
                }
                return
            }

            let assetName = asset["name"] as? String ?? "Raze"
            let isDMG = assetName.lowercased().hasSuffix(".dmg")
            print("[Duke3D] Downloading Raze \(version): \(assetName)")

            DispatchQueue.main.async {
                self?.updateProgressWindow(progressWindow, detail: "Downloading Raze \(version) (\(assetName))…")
            }

            // Download the asset
            URLSession.shared.downloadTask(with: downloadURL) { tempURL, _, dlError in
                guard let tempURL = tempURL, dlError == nil else {
                    DispatchQueue.main.async {
                        progressWindow.close()
                        let alert = NSAlert()
                        alert.messageText = "Download Failed"
                        alert.informativeText = dlError?.localizedDescription ?? "Raze download failed."
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                        completion(false)
                    }
                    return
                }

                DispatchQueue.main.async {
                    self?.updateProgressWindow(progressWindow, detail: "Installing Raze to /Applications…")
                }

                let fm = FileManager.default
                let tempDir = NSTemporaryDirectory() + "raze_install_\(ProcessInfo.processInfo.processIdentifier)"
                try? fm.removeItem(atPath: tempDir)
                try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true, attributes: nil)

                if isDMG {
                    // Mount DMG, copy .app, unmount
                    self?.installRazeFromDMG(dmgPath: tempURL.path, tempDir: tempDir) { success in
                        try? fm.removeItem(atPath: tempDir)
                        DispatchQueue.main.async {
                            progressWindow.close()
                            completion(success)
                        }
                    }
                } else {
                    // Unzip
                    self?.installRazeFromZip(zipPath: tempURL.path, tempDir: tempDir) { success in
                        try? fm.removeItem(atPath: tempDir)
                        DispatchQueue.main.async {
                            progressWindow.close()
                            completion(success)
                        }
                    }
                }
            }.resume()
        }.resume()
    }

    /// Extract Raze.app from a ZIP and install to /Applications
    private func installRazeFromZip(zipPath: String, tempDir: String, completion: @escaping (Bool) -> Void) {
        let fm = FileManager.default

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", zipPath, "-d", tempDir]
        unzip.standardOutput = FileHandle.nullDevice
        unzip.standardError = FileHandle.nullDevice
        do {
            try unzip.run()
            unzip.waitUntilExit()
        } catch {
            print("[Duke3D] Unzip failed: \(error)")
            completion(false)
            return
        }

        // Find Raze.app recursively
        guard let appPath = findAppBundle(named: "Raze", in: tempDir) else {
            print("[Duke3D] Raze.app not found in ZIP")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Installation Failed"
                alert.informativeText = "Raze.app was not found in the downloaded archive."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            completion(false)
            return
        }

        copyAppToApplications(appPath: appPath, targetName: "Raze.app", completion: completion)
    }

    /// Mount a DMG, find Raze.app, copy to /Applications
    private func installRazeFromDMG(dmgPath: String, tempDir: String, completion: @escaping (Bool) -> Void) {
        let mountPoint = tempDir + "/dmg_mount"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: mountPoint, withIntermediateDirectories: true, attributes: nil)

        // Mount DMG
        let mount = Process()
        mount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mount.arguments = ["attach", "-nobrowse", "-readonly", "-mountpoint", mountPoint, dmgPath]
        mount.standardOutput = FileHandle.nullDevice
        mount.standardError = FileHandle.nullDevice
        do {
            try mount.run()
            mount.waitUntilExit()
        } catch {
            print("[Duke3D] DMG mount failed: \(error)")
            completion(false)
            return
        }

        guard mount.terminationStatus == 0 else {
            print("[Duke3D] DMG mount returned status \(mount.terminationStatus)")
            completion(false)
            return
        }

        // Find Raze.app in mounted volume
        let appPath = findAppBundle(named: "Raze", in: mountPoint)

        if let appPath = appPath {
            copyAppToApplications(appPath: appPath, targetName: "Raze.app") { success in
                // Unmount DMG
                let detach = Process()
                detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                detach.arguments = ["detach", mountPoint, "-quiet"]
                detach.standardOutput = FileHandle.nullDevice
                detach.standardError = FileHandle.nullDevice
                try? detach.run()
                detach.waitUntilExit()
                completion(success)
            }
        } else {
            // Unmount and fail
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountPoint, "-quiet"]
            detach.standardOutput = FileHandle.nullDevice
            detach.standardError = FileHandle.nullDevice
            try? detach.run()
            detach.waitUntilExit()

            print("[Duke3D] Raze.app not found in DMG")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Installation Failed"
                alert.informativeText = "Raze.app was not found in the downloaded DMG."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            completion(false)
        }
    }

    /// Find an .app bundle containing the given name in a directory tree
    private func findAppBundle(named name: String, in directory: String) -> String? {
        let fm = FileManager.default
        // Check top level first
        if let contents = try? fm.contentsOfDirectory(atPath: directory) {
            if let app = contents.first(where: { $0.lowercased().contains(name.lowercased()) && $0.hasSuffix(".app") }) {
                return directory + "/" + app
            }
        }
        // Search recursively
        if let enumerator = fm.enumerator(atPath: directory) {
            while let file = enumerator.nextObject() as? String {
                if file.hasSuffix(".app") && file.lowercased().contains(name.lowercased()) {
                    return directory + "/" + file
                }
            }
        }
        return nil
    }

    /// Copy an .app bundle to /Applications
    private func copyAppToApplications(appPath: String, targetName: String, completion: @escaping (Bool) -> Void) {
        let fm = FileManager.default
        let targetPath = "/Applications/" + targetName

        do {
            if fm.fileExists(atPath: targetPath) {
                try fm.removeItem(atPath: targetPath)
            }
            try fm.copyItem(atPath: appPath, toPath: targetPath)

            // Remove quarantine so it launches without Gatekeeper prompt
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-rd", "com.apple.quarantine", targetPath]
            xattr.standardOutput = FileHandle.nullDevice
            xattr.standardError = FileHandle.nullDevice
            try? xattr.run()
            xattr.waitUntilExit()

            print("[Duke3D] Installed \(targetName) to /Applications")
            completion(true)
        } catch {
            print("[Duke3D] Failed to install \(targetName): \(error)")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Installation Failed"
                alert.informativeText = "Could not install \(targetName): \(error.localizedDescription)"
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            completion(false)
        }
    }

    // MARK: - Duke3D Shareware Auto-Download

    /// Download Duke Nukem 3D Shareware GRP, returns path on success.
    /// Archive structure: 3dduke13.zip → DN3DSW13.SHR (self-extracting PKZIP) → DUKE3D.GRP
    private func downloadDuke3DShareware(completion: @escaping (String?) -> Void) {
        let targetDir = AppSettings.shared.razeGrpFolder
        let targetGRP = targetDir + "/DUKE3D.GRP"
        let fm = FileManager.default

        try? fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true, attributes: nil)

        // Already exists?
        if fm.fileExists(atPath: targetGRP) {
            completion(targetGRP)
            return
        }

        // Show progress window
        let progressWindow = createProgressWindow(title: "Downloading Duke Nukem 3D…", detail: "Downloading Shareware Episode 1: L.A. Meltdown…")

        // Duke3D Shareware v1.3D from Internet Archive (lowercase filename!)
        guard let downloadURL = URL(string: "https://archive.org/download/3dduke13/3dduke13.zip") else {
            progressWindow.close()
            completion(nil)
            return
        }

        print("[Duke3D] Downloading shareware from Internet Archive…")

        URLSession.shared.downloadTask(with: downloadURL) { [weak self] tempURL, response, error in
            guard let tempURL = tempURL, error == nil else {
                DispatchQueue.main.async {
                    progressWindow.close()
                    let alert = NSAlert()
                    alert.messageText = "Download Failed"
                    alert.informativeText = error?.localizedDescription ?? "Could not download Duke Nukem 3D Shareware."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    completion(nil)
                }
                return
            }

            DispatchQueue.main.async {
                self?.updateProgressWindow(progressWindow, detail: "Extracting game data…")
            }

            let tempDir = NSTemporaryDirectory() + "duke3d_extract_\(ProcessInfo.processInfo.processIdentifier)"
            let tempDir2 = NSTemporaryDirectory() + "duke3d_grp_\(ProcessInfo.processInfo.processIdentifier)"
            try? fm.removeItem(atPath: tempDir)
            try? fm.removeItem(atPath: tempDir2)
            try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true, attributes: nil)
            try? fm.createDirectory(atPath: tempDir2, withIntermediateDirectories: true, attributes: nil)

            // Step 1: Unzip the outer archive (3dduke13.zip → DN3DSW13.SHR)
            let unzip1 = Process()
            unzip1.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip1.arguments = ["-o", "-j", tempURL.path, "-d", tempDir]
            unzip1.standardOutput = FileHandle.nullDevice
            unzip1.standardError = FileHandle.nullDevice
            do {
                try unzip1.run()
                unzip1.waitUntilExit()
            } catch {
                print("[Duke3D] Outer unzip failed: \(error)")
            }

            // Step 2: Find the .SHR self-extracting archive (it's a PKZIP, unzip can handle it)
            var shrPath: String?
            if let contents = try? fm.contentsOfDirectory(atPath: tempDir) {
                shrPath = contents.first(where: { $0.lowercased().hasSuffix(".shr") })
                    .map { tempDir + "/" + $0 }
            }

            if let shrPath = shrPath {
                // Step 3: Unzip the SHR (DN3DSW13.SHR → DUKE3D.GRP + other files)
                let unzip2 = Process()
                unzip2.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzip2.arguments = ["-o", "-j", shrPath, "-d", tempDir2]
                unzip2.standardOutput = FileHandle.nullDevice
                unzip2.standardError = FileHandle.nullDevice
                do {
                    try unzip2.run()
                    unzip2.waitUntilExit()
                } catch {
                    print("[Duke3D] SHR unzip failed: \(error)")
                }
            }

            // Step 4: Find DUKE3D.GRP (case-insensitive) in either extraction directory
            var foundGRP: String?
            for dir in [tempDir2, tempDir] {
                if let contents = try? fm.contentsOfDirectory(atPath: dir) {
                    if let grp = contents.first(where: { $0.lowercased() == "duke3d.grp" }) {
                        foundGRP = dir + "/" + grp
                        break
                    }
                }
                // Also search subdirectories
                if foundGRP == nil, let enumerator = fm.enumerator(atPath: dir) {
                    while let file = enumerator.nextObject() as? String {
                        if file.lowercased().hasSuffix("duke3d.grp") {
                            foundGRP = dir + "/" + file
                            break
                        }
                    }
                }
                if foundGRP != nil { break }
            }

            // Cleanup helper
            let cleanup = {
                try? fm.removeItem(atPath: tempDir)
                try? fm.removeItem(atPath: tempDir2)
            }

            if let grpSource = foundGRP {
                do {
                    if fm.fileExists(atPath: targetGRP) {
                        try fm.removeItem(atPath: targetGRP)
                    }
                    try fm.copyItem(atPath: grpSource, toPath: targetGRP)
                    print("[Duke3D] Shareware GRP installed to \(targetGRP)")
                    cleanup()

                    DispatchQueue.main.async {
                        progressWindow.close()
                        completion(targetGRP)
                    }
                } catch {
                    print("[Duke3D] Failed to copy GRP: \(error)")
                    cleanup()
                    DispatchQueue.main.async {
                        progressWindow.close()
                        let alert = NSAlert()
                        alert.messageText = "Installation Failed"
                        alert.informativeText = "Could not install DUKE3D.GRP: \(error.localizedDescription)"
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                        completion(nil)
                    }
                }
            } else {
                print("[Duke3D] DUKE3D.GRP not found in downloaded archive")
                cleanup()
                DispatchQueue.main.async {
                    progressWindow.close()
                    let alert = NSAlert()
                    alert.messageText = "Extraction Failed"
                    alert.informativeText = "DUKE3D.GRP was not found in the downloaded archive."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    completion(nil)
                }
            }
        }.resume()
    }

    // MARK: - Progress Window Helper

    private func createProgressWindow(title: String, detail: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 120))

        let spinner = NSProgressIndicator(frame: NSRect(x: 170, y: 75, width: 40, height: 40))
        spinner.style = .spinning
        spinner.startAnimation(nil)
        container.addSubview(spinner)

        let label = NSTextField(labelWithString: detail)
        label.frame = NSRect(x: 20, y: 30, width: 340, height: 36)
        label.alignment = .center
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.tag = 100  // for updateProgressWindow
        container.addSubview(label)

        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }

    private func updateProgressWindow(_ window: NSWindow, detail: String) {
        if let label = window.contentView?.viewWithTag(100) as? NSTextField {
            label.stringValue = detail
        }
    }


    // MARK: - Virtual Camera

    @objc private func toggleVirtualCamera() {
        let vcam = VirtualCameraManager.shared
        if vcam.isRunning {
            vcam.stop()
        } else {
            // Virtual Camera requires license
            if !LicenseManager.shared.isLicensed {
                showVirtualCameraLockedAlert()
                return
            }
            vcam.start()
        }
        rebuildMenu()
    }

    private func showVirtualCameraLockedAlert() {
        let alert = NSAlert()
        alert.messageText = "Virtual Camera 🔒"
        alert.informativeText = "Virtual Camera is part of the All Presets pack. Unlock all \(PresetRegistry.builtinPresets.count) presets + virtual camera + custom shaders!"
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

    @objc private func selectCameraShader(_ sender: NSMenuItem) {
        guard let shaderID = sender.representedObject as? String else { return }
        VirtualCameraManager.shared.changeShader(shaderID)
        rebuildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        VirtualCameraManager.shared.stop()
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
