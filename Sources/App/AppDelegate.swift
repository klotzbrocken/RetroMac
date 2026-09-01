import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import Sparkle
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    // Sparkle only runs in the notarized Developer-ID build. Debug ("…​.dev") bundles are
    // signed with Apple Development and aren't notarized, so Gatekeeper rejects Sparkle's
    // installer helpers ("An error occurred while launching the installer"). Don't start it.
    private static let sparkleEnabled = !(Bundle.main.bundleIdentifier ?? "").hasSuffix(".dev")
    private let updaterController = SPUStandardUpdaterController(startingUpdater: AppDelegate.sparkleEnabled, updaterDelegate: nil, userDriverDelegate: nil)
    private(set) var overlayController: OverlayWindowController?
    private(set) var crtLiteOverlay: CRTLiteOverlay?
    /// Wallpaper-only desktop effect (renders below icons/windows; no screen capture).
    private(set) var wallpaperShaderController: WallpaperShaderController?
    private var shaderScopeObserver: NSObjectProtocol?
    private(set) var isActive = false
    var currentPresetName: String!
    private var hotKeyRef: EventHotKeyRef?
    private var screenshotHotKeyRef: EventHotKeyRef?
    private var menuBarHotKeyRef: EventHotKeyRef?
    private var dashboardHotKeyRef: EventHotKeyRef?
    private var exposeHotKeyRef: EventHotKeyRef?
    private var exposeAppHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var menuBarHiddenByHotkey = false
    private(set) var currentIntensity: Float!
    private(set) var currentVignetteIntensity: Float!
    private let settingsWindow = SettingsWindowController()
    private let welcomeFlow = WelcomeFlowWindowController()
    private let setupWizard = SetupWizardWindowController()
    private let fpsOverlay = FPSOverlayController()
    private let windowPicker = WindowPicker()
    let tvBrowser = TVBrowserWindow()   // internal: Tube Mode's "Classic Themed Window" hands channels over
    private var appLaunchObserver: NSObjectProtocol?
    private var appTerminateObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var tvBookmarkObserver: NSObjectProtocol?
    private var tvTubeObserver: NSObjectProtocol?
    private var tubeStateObserver: NSObjectProtocol?
    private var dockThemeObserver: NSObjectProtocol?
    private var dockModeObserver: NSObjectProtocol?
    private var cameraStateObserver: NSObjectProtocol?
    private var viewportCloseObserver: NSObjectProtocol?
    private var perAppBundleID: String?
    private var wasActiveBeforeSleep = false
    private var overlayStartTask: Task<Void, Never>?
    private var permissionPollTimer: Timer?

    // Retro Viewport (movable shader window)
    private(set) var retroViewport = RetroViewport()

    // Video recording with shader effects
    private var shaderRecorder: ShaderRecorder?
    /// Read by CrashScheduler — a simulated crash must never land in a recording.
    var isRecordingShaderVideo: Bool { shaderRecorder?.isRecording == true }

    // Save/restore state for TV window overlay
    var savedPreset: String?
    var savedWasActive = false

    // Live-updating menu views (updated in-place when toggle state changes)
    private var menuHeaderView: MenuHeaderView?
    private var shaderPillToggle: PillToggleView?
    private var liveWallpaperPillToggle: PillToggleView?
    private var cameraPillToggle: PillToggleView?
    private var viewportPillToggle: PillToggleView?

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
        DiagnosticsLog.shared.start()   // capture console output for the About → Diagnostics view
        AppDelegate.shared = self
        settingsWindow.updater = updaterController.updater
        let settings = AppSettings.shared
        currentPresetName = settings.defaultPreset
        currentIntensity = settings.defaultIntensity
        currentVignetteIntensity = settings.vignetteIntensity

        // Probe OS capabilities once (async, off-main) so features can degrade gracefully.
        SystemBridge.shared.probeAll()

        // Reflect the persisted window-borders flag at launch (gated internally; no-op when off).
        WindowBorderController.shared.update()

        // Restore system UI if previous session crashed while UI was hidden
        SystemUIHelper.restoreIfNeeded()
        SystemUIHelper.restoreDesktopIconsIfNeeded()   // crash/force-quit-safe desktop-icon restore
        AppearanceAdapter.restoreIfNeeded()            // ditto for matched appearance/accent
        CursorThemeManager.shared.restoreIfNeeded()    // ditto for the themed system cursor
        TerminalThemer.restoreIfNeeded()               // ditto for the matched Terminal profile
        SystemTweaksAdapter.restoreIfNeeded()          // ditto for the "Classic Finder" defaults tweaks
        ThemeManager.shared.restoreWallpapersIfNeeded() // ditto for the wallpaper (else it stuck on the theme's after a Mac restart)
        restoreRetroModeSystemUI()
        DockController.shared.restoreSystemDockIfNeeded()
        _ = DesktopPetController.shared   // registers theme observer; auto-shows on XP/98
        ScreensaverController.shared.beginIdleWatch()   // works regardless of the themed dock

        applyDockMode()   // .accessory (menu-bar only) or .regular (Dock icon) per setting
        if AppSettings.shared.floatingLauncherEnabled { FloatingLauncherButton.shared.show() }

        // Re-apply the last webcam scene so the look persists across launches (the camera's
        // shader/intensity aren't otherwise persisted).
        if !AppSettings.shared.activeCameraSceneID.isEmpty,
           let scene = CameraScene.all.first(where: { $0.id == AppSettings.shared.activeCameraSceneID }) {
            scene.apply()
        }
        // Floating scene switcher — observes the camera state; only shows while it's running.
        QuickSwitchController.shared.refreshVisibility()
        setupMenuBar()
        registerHotkey()
        startAppLaunchObserver()
        startSleepObserver()

        // Listen for Start menu TV bookmark requests from DockView
        tvBookmarkObserver = NotificationCenter.default.addObserver(forName: .init("openTVBookmark"), object: nil, queue: .main) { [weak self] note in
            guard let idString = note.object as? String,
                  let uuid = UUID(uuidString: idString),
                  let bookmark = AppSettings.shared.tvBookmarks.first(where: { $0.id == uuid }) else { return }
            AppSettings.shared.tvLastBookmarkURL = bookmark.url   // Tube Mode starts on this channel
            self?.tvBrowser.open(bookmark: bookmark)
        }
        // Keep the menu pill in sync when the Tube exits on its own (ESC / Turn Off /
        // hand-off to the classic window) — stop() posts, but nothing rebuilt the menu.
        tubeStateObserver = NotificationCenter.default.addObserver(forName: .tubeModeChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildMenu()
        }
        // Start-menu / deskbar streams open the immersive Tube Mode instead of the
        // small windowed TV (that one stays reachable via the TV desktop widget).
        tvTubeObserver = NotificationCenter.default.addObserver(forName: .init("openTVBookmarkTube"), object: nil, queue: .main) { note in
            guard let idString = note.object as? String,
                  let uuid = UUID(uuidString: idString),
                  let bookmark = AppSettings.shared.tvBookmarks.first(where: { $0.id == uuid }) else { return }
            TubeModeController.shared.startOnBookmark(url: bookmark.url)
        }

        // Apply theme shader and update desktop overlays when theme changes via Settings
        dockThemeObserver = NotificationCenter.default.addObserver(forName: .dockThemeChanged, object: nil, queue: .main) { [weak self] _ in
            self?.applyThemePresetIfNeeded()
            self?.updateDockIcon()   // Dock Mode: keep the Dock icon in sync with the theme
            DesktopIconsController.shared.update()
            ProgramManagerController.shared.update()
            SGIDesktopController.shared.update()
            BeOSDeskbarController.shared.update()
            NextMenuController.shared.update()
            NextDockController.shared.update()
            NextRunningAppsController.shared.update()
            WindowBorderController.shared.update()   // recolour theme window borders on theme change
            // The active theme drives the menu-bar Apple logo (Mac OS 9 → rainbow, Mac OS X →
            // aqua-classic, Maiks Favourite II → hell); every other theme turns it off.
            // Setting the style triggers RainbowAppleController.update() via its didSet.
            AppSettings.shared.menuBarAppleStyle = ThemeManager.shared.activeTheme?.config.menuBarAppleStyleDefault ?? 0
            RainbowAppleController.shared.update()
            // Menu-bar hiding is tied to the theme: only themes that declare it (Windows 95/98, XP)
            // hide the macOS menu bar; every Mac OS theme AND theme-off (activeTheme == nil) force it
            // back visible. Forced on each change (like menuBarAppleStyle) so it never stays hidden.
            AppSettings.shared.hideMenuBar = ThemeManager.shared.activeTheme?.config.hideMenuBarDefault ?? false
            // The wallpaper-only shader samples the desktop image — refresh its texture when
            // the theme swaps the wallpaper. Slight delay so setDesktopImageURL has landed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.wallpaperShaderController?.reloadWallpaper()
            }
        }

        // Switching "Apply to: Whole screen / Wallpaper only" restarts the running effect in the
        // newly-chosen scope so the change is visible immediately.
        shaderScopeObserver = NotificationCenter.default.addObserver(forName: .shaderScopeChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.isActive else { return }
            let preset = self.currentPresetName ?? AppSettings.shared.defaultPreset
            self.disableAll()
            if self.isWallpaperOnlyScope {
                self.startWallpaperShader(presetID: preset)
            } else if Self.isLitePreset(preset) {
                self.startCRTLite(mode: .fullScreen, presetName: preset)
            } else {
                self.startOverlay(mode: .fullScreen)
            }
        }

        // Apply Dock Mode when the user toggles it in Settings
        dockModeObserver = NotificationCenter.default.addObserver(forName: .dockModeChanged, object: nil, queue: .main) { [weak self] _ in
            self?.applyDockMode()
        }

        // Rebuild menu when virtual camera state changes (start/stop is async)
        cameraStateObserver = NotificationCenter.default.addObserver(forName: .virtualCameraStateChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildMenu()
        }

        // Rebuild menu when viewport is closed via its window close button
        viewportCloseObserver = NotificationCenter.default.addObserver(forName: .retroViewportDidClose, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildMenu()
        }

        // Screen Recording permission is checked lazily when overlay is actually
        // started (line ~759). No upfront check here — both CGPreflight and
        // CGRequest can trigger the TCC dialog / System Settings redirect.

        let hotkeyStr = settings.hotkeyDisplayString
        print("[RetroMac] Ready. \(hotkeyStr) to toggle.")

        // Change request: RetroMac starts CLEAN by default — no theme, dock or shader overlay
        // is auto-activated on launch. The selected theme/preset stay remembered (ThemeManager
        // restored settings.dockTheme in its init), so the user can turn them on manually.
        // dockEnabled is reset so the menu/settings consistently reflect the inactive state.
        settings.dockEnabled = false
        isActive = false

        // Opt-in "start into the last theme": the user setting (Settings ▸ Dock) or the QA env
        // hook RETROMAC_AUTOACTIVATE_THEME immediately turns the remembered theme on at launch
        // (mirrors selecting it from the menu). Default off → clean start is unchanged.
        let autoActivateTheme = settings.activateThemeOnLaunch
            || ProcessInfo.processInfo.environment["RETROMAC_AUTOACTIVATE_THEME"] != nil
        if autoActivateTheme {
            DispatchQueue.main.async {
                ThemeManager.shared.setActiveTheme(name: settings.dockTheme)
                if !settings.dockEnabled { settings.dockEnabled = true; DockController.shared.start() }
                self.isActive = true
                if ProcessInfo.processInfo.environment["RETROMAC_OPEN_APPS"] != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        CPUMonitorController.shared.show()
                        ClockWidgetController.shared.show()
                        NotepadController.shared.show()
                        NextAppsWindowController.shared.show()
                    }
                }
            }
        }

        // Rainbow Apple is theme-independent — show it on launch if the user enabled it.
        RainbowAppleController.shared.update()

        // QA hook: open Settings straight away. The app has no menu bar of its own, so there is
        // otherwise no way to reach the panel without a human clicking the status item.
        if ProcessInfo.processInfo.environment["RETROMAC_OPEN_SETTINGS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.openSettings() }
        }

        // QA hook: stage one crash and take it away again, so a live check can never leave a
        // blue screen sitting on somebody's desktop.
        // RETROMAC_CRASH_NOW=<scenario-id>:<seconds on screen>:<delay before firing>
        if let spec = ProcessInfo.processInfo.environment["RETROMAC_CRASH_NOW"] {
            let parts = spec.split(separator: ":")
            let id = parts.first.map(String.init) ?? ""
            let seconds = parts.count > 1 ? Double(parts[1]) ?? 6 : 6
            let delay = parts.count > 2 ? Double(parts[2]) ?? 2 : 2
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                CrashScheduler.shared.fire(scenarioID: id.isEmpty ? nil : id, source: .manual)
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                    CrashDirector.shared.teardown(.watchdog)
                }
            }
        }

        // QA hook: render every crash screen to PNGs and quit. The screens are pixel art on a
        // fixed grid, so they can be checked against the original screenshots without taking a
        // single pixel of the user's desktop.
        if let dir = ProcessInfo.processInfo.environment["RETROMAC_CRASH_DUMP"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                CrashDirector.dumpScreens(to: URL(fileURLWithPath: dir))
                NSApp.terminate(nil)
            }
        }

        // QA hook: print what the crash picker would choose, without showing anything.
        if let spec = ProcessInfo.processInfo.environment["RETROMAC_CRASH_PICK"] {
            let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
            let count = Int(parts.first ?? "") ?? 10
            let path = parts.count > 1 ? parts[1] : NSTemporaryDirectory() + "crashpicks.txt"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                let picks = CrashDirector.shared.dryRunPicks(count)
                try? picks.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }

        // QA hook: open the Game Library, same reason as the Settings hook above.
        if ProcessInfo.processInfo.environment["RETROMAC_OPEN_GAME_LIBRARY"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.openGameLibrary() }
        }

        // QA hook: force the onboarding coach marks (bypasses the one-time gate).
        if ProcessInfo.processInfo.environment["RETROMAC_FORCE_COACH"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { CoachMarkController.shared.forceShow() }
        }

        // First run: the Setup Assistant is the primary onboarding (incl. permissions).
        // After it finishes, fall through to the welcome flow for What's New / Coffee.
        // On subsequent launches the wizard is skipped and only the welcome flow runs.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if !AppSettings.shared.setupWizardComplete {
                self.setupWizard.onFinishExtra = { [weak self] in
                    self?.welcomeFlow.showIfNeeded()
                    CoachMarkController.shared.showIfNeeded()   // self-defers until onboarding windows close
                }
                self.setupWizard.show()
            } else {
                self.welcomeFlow.showIfNeeded()
                CoachMarkController.shared.showIfNeeded()
            }

            // Honor "Turn the shader on when RetroMac launches" (Settings ▸ System). The clean-start
            // above leaves the shader off; this opts back in for users who asked for it. Only
            // auto-start when it won't pop the Screen-Recording dialog on every launch — i.e. Lite
            // presets / wallpaper scope / already-granted capture. First-time grant stays manual.
            // "off for this theme" outranks the launch switch. The app remembered that choice
            // and then contradicted itself on the next launch, which is what made the setting
            // look as though it were not being saved at all.
            if AppSettings.shared.enableOnLaunch && !self.isActive
                && !AppSettings.shared.shaderDisabledForActiveTheme {
                let preset = self.currentPresetName ?? AppSettings.shared.defaultPreset
                let needsCapture = !Self.isLitePreset(preset) && !self.isWallpaperOnlyScope
                if !needsCapture || CGPreflightScreenCaptureAccess() {
                    self.toggleOverlay()
                }
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

    // MARK: - Dock Mode + Launcher

    /// Toggle the app between menu-bar-only (.accessory) and showing a Dock icon (.regular).
    func applyDockMode() {
        if AppSettings.shared.dockModeEnabled {
            NSApp.setActivationPolicy(.regular)
            updateDockIcon()
        } else {
            NSApp.setActivationPolicy(.accessory)
            LauncherController.shared.close()
            LauncherController.shared.closeWindow()
        }
    }

    /// Set the Dock icon to the active theme's icon (Dock Mode only); nil → default app icon.
    func updateDockIcon() {
        guard AppSettings.shared.dockModeEnabled else { return }
        if let url = ThemeManager.shared.activeTheme?.dockIconURL(),
           let img = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = img
        } else {
            NSApp.applicationIconImage = nil   // fall back to the bundled AppIcon
        }
    }

    /// Left-click on the Dock icon (no windows) → toggle the launcher window (movable).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppSettings.shared.dockModeEnabled {
            LauncherController.shared.toggleWindow()
        }
        return true
    }

    /// Right-click on the Dock icon → a compact native menu (theme / shader / webcam / settings).
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard AppSettings.shared.dockModeEnabled else { return nil }
        let menu = NSMenu()

        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        let active = ThemeManager.shared.activeTheme?.config.name
        for t in ThemeManager.shared.availableThemes {
            let mi = NSMenuItem(title: ThemeManager.displayName(for: t.config.name), action: #selector(selectTheme(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = t.config.name
            mi.state = (t.config.name == active) ? .on : .off
            themeMenu.addItem(mi)
        }
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)

        menu.addItem(.separator())
        let shader = NSMenuItem(title: "Shader", action: #selector(toggleOverlay), keyEquivalent: "")
        shader.target = self
        shader.state = isActive ? .on : .off
        menu.addItem(shader)
        let cam = NSMenuItem(title: "Virtual Camera", action: #selector(toggleVirtualCamera), keyEquivalent: "")
        cam.target = self
        cam.state = VirtualCameraManager.shared.isRunning ? .on : .off
        menu.addItem(cam)
        let borders = NSMenuItem(title: "Window Borders (Theme)", action: #selector(toggleThemeWindowBorders), keyEquivalent: "")
        borders.target = self
        borders.state = AppSettings.shared.themeWindowBorders ? .on : .off
        menu.addItem(borders)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        return menu
    }

    // Internal entry points for the SwiftUI launcher (which lives in another file).
    func launcherActivateTheme(_ name: String) {
        let item = NSMenuItem(); item.representedObject = name
        selectTheme(item)
    }
    func launcherDisableTheme() { disableTheme() }

    /// Double-click on the floating launcher button: toggle the last-used theme. If a theme is
    /// currently active it turns Dock Mode off; otherwise it re-activates the theme ThemeManager
    /// still remembers (falling back to the first available theme on a fresh start).
    func toggleLastActiveTheme() {
        if AppSettings.shared.dockEnabled {
            disableTheme()
        } else if let name = ThemeManager.shared.activeTheme?.config.name {
            launcherActivateTheme(name)
        } else if let first = ThemeManager.shared.availableThemes.first?.config.name {
            launcherActivateTheme(first)
        }
    }
    /// Flyout/menu "CRT Shader" = the whole-screen effect. Forces the scope to whole-screen so it
    /// can't get stuck on wallpaper after "Live Wallpaper" set `shaderWallpaperOnly = true`.
    func launcherToggleShader() {
        if isActive && !isWallpaperOnlyScope {
            disableAll()                                    // already whole-screen → off
            rememberShaderStateForActiveTheme(on: false)    // persist "off" per theme (flyout path)
            return
        }
        let wasActive = isActive
        AppSettings.shared.shaderWallpaperOnly = false   // posts .shaderScopeChanged
        // If wallpaper/Lite was running, the .shaderScopeChanged observer restarts it whole-screen;
        // otherwise nothing is running yet, so start it here.
        if !wasActive { startOverlay(mode: .fullScreen) }
        rememberShaderStateForActiveTheme(on: true)         // persist "on" per theme (flyout path)
    }
    func launcherToggleWebcam() { toggleVirtualCamera() }
    func launcherOpenSettings() { openSettings() }
    func launcherSelectPreset(_ id: String) {
        let item = NSMenuItem(); item.representedObject = id
        selectPreset(item)
    }
    var launcherShaderActive: Bool { isActive }
    var launcherCurrentPreset: String { currentPresetName ?? AppSettings.shared.defaultPreset }

    /// The wallpaper-only ("Live Wallpaper") effect is currently running. Pro-gated.
    var launcherLiveWallpaperActive: Bool {
        isActive && AppSettings.shared.shaderWallpaperOnly && LicenseManager.shared.isLicensed
    }

    /// Flyout "Live Wallpaper" switch: run the shader on the wallpaper only (Pro). Toggling on
    /// sets the scope + starts it; toggling off stops the effect.
    func launcherToggleLiveWallpaper() {
        if launcherLiveWallpaperActive { disableAll(); return }
        guard LicenseManager.shared.isLicensed else { presentUnlockScreen(); return }
        let wasActive = isActive
        AppSettings.shared.shaderWallpaperOnly = true   // posts .shaderScopeChanged
        // If a whole-screen/Lite effect was running, the .shaderScopeChanged observer restarts
        // it in wallpaper scope; otherwise nothing is running yet, so start it here.
        if !wasActive {
            startWallpaperShader(presetID: currentPresetName ?? AppSettings.shared.defaultPreset)
        }
    }

    /// The menu-bar glyph as a template image (used by the floating launcher button).
    func menuBarIconImage(size: NSSize) -> NSImage {
        let icon = makeMenuBarIcon(size: size, active: isActive)
        icon.isTemplate = true
        return icon
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem.button else { return }
        let icon = makeMenuBarIcon(size: NSSize(width: 18, height: 18), active: isActive)
        icon.isTemplate = true
        button.image = icon
        FloatingLauncherButton.shared.refreshIcon()
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

    // MARK: - Menu Custom Views

    /// Header strip showing preset name, status, and gear button
    private final class MenuHeaderView: NSView {
        private let presetLabel = NSTextField(labelWithString: "")
        private let statusLabel = NSTextField(labelWithString: "")
        private let gearButton = NSImageView()
        private let quitButton = NSImageView()
        private let retroButton = NSImageView()
        private let iconView = NSView()
        private let glowDot = NSView(frame: NSRect(x: 9, y: 9, width: 8, height: 8))
        private var onGear: (() -> Void)?
        private var onQuit: (() -> Void)?
        private var onRetro: (() -> Void)?

        init(presetName: String, statusText: String, shaderOn: Bool, retroActive: Bool, onGear: @escaping () -> Void, onQuit: @escaping () -> Void, onRetro: @escaping () -> Void) {
            self.onGear = onGear
            self.onQuit = onQuit
            self.onRetro = onRetro
            super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 50))
            autoresizingMask = .width

            // Icon — rounded square with dark background
            iconView.frame = NSRect(x: 14, y: 12, width: 26, height: 26)
            iconView.wantsLayer = true
            iconView.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
            iconView.layer?.cornerRadius = 6
            addSubview(iconView)

            // Status dot in center
            glowDot.wantsLayer = true
            glowDot.layer?.cornerRadius = 4
            glowDot.layer?.shadowRadius = 4
            glowDot.layer?.shadowOpacity = 0.8
            glowDot.layer?.shadowOffset = .zero
            iconView.addSubview(glowDot)

            // Preset name
            presetLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            presetLabel.frame = NSRect(x: 48, y: 26, width: 180, height: 16)
            presetLabel.lineBreakMode = .byTruncatingTail
            addSubview(presetLabel)

            // Status line
            statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            statusLabel.frame = NSRect(x: 48, y: 9, width: 180, height: 14)
            statusLabel.lineBreakMode = .byTruncatingTail
            addSubview(statusLabel)

            // Gear / quit / retro icons — far right. These use NSImageView, not
            // borderless NSButton: an image-only borderless button renders invisibly
            // inside a vibrant menu-item view on some setups (e.g. dark desktop on
            // Sequoia), while NSImageView honours contentTintColor reliably. Clicks are
            // dispatched from mouseUp(with:) below, mirroring MenuToggleRowView.
            let gearConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            gearButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")?
                .withSymbolConfiguration(gearConfig)
            gearButton.contentTintColor = .secondaryLabelColor
            gearButton.toolTip = "Settings"
            addSubview(gearButton)

            // Quit icon — left of the gear
            quitButton.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit RetroMac")?
                .withSymbolConfiguration(gearConfig)
            quitButton.contentTintColor = .secondaryLabelColor
            quitButton.toolTip = "Quit RetroMac"
            addSubview(quitButton)

            // Retro Mode toggle — left of quit (image + tint set in update())
            retroButton.toolTip = "Retro Mode — hide desktop & apply your favourite"
            addSubview(retroButton)

            // Apply initial state
            update(shaderOn: shaderOn, presetName: presetName, statusText: statusText, retroActive: retroActive)
        }

        /// Update header in-place (while menu is open)
        func update(shaderOn: Bool, presetName: String, statusText: String, retroActive: Bool) {
            let retroConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            retroButton.image = NSImage(systemSymbolName: retroActive ? "wand.and.stars.inverse" : "wand.and.stars",
                                        accessibilityDescription: "Retro Mode")?.withSymbolConfiguration(retroConfig)
            retroButton.contentTintColor = retroActive ? .controlAccentColor : .secondaryLabelColor

            let dotColor: NSColor = shaderOn
                ? NSColor(red: 0.2, green: 0.9, blue: 0.3, alpha: 1)
                : NSColor(red: 0.85, green: 0.25, blue: 0.2, alpha: 1)
            glowDot.layer?.backgroundColor = dotColor.cgColor
            glowDot.layer?.shadowColor = dotColor.cgColor

            presetLabel.stringValue = presetName
            presetLabel.textColor = shaderOn ? NSColor(red: 0.20, green: 0.45, blue: 0.22, alpha: 1) : .labelColor

            statusLabel.stringValue = statusText
            statusLabel.textColor = .secondaryLabelColor
        }

        override func layout() {
            super.layout()
            let gearSize: CGFloat = 24
            gearButton.frame = NSRect(x: bounds.width - gearSize - 12, y: 13, width: gearSize, height: gearSize)
            quitButton.frame = NSRect(x: bounds.width - gearSize * 2 - 16, y: 13, width: gearSize, height: gearSize)
            retroButton.frame = NSRect(x: bounds.width - gearSize * 3 - 20, y: 13, width: gearSize, height: gearSize)
        }

        required init?(coder: NSCoder) { fatalError() }

        /// The three icons are NSImageViews, so route clicks here (same approach as
        /// MenuToggleRowView). Hit areas are padded since the icons are only 24×24.
        override func mouseUp(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            if gearButton.frame.insetBy(dx: -2, dy: -8).contains(p) { gearTapped() }
            else if quitButton.frame.insetBy(dx: -2, dy: -8).contains(p) { quitTapped() }
            else if retroButton.frame.insetBy(dx: -2, dy: -8).contains(p) { retroTapped() }
        }

        @objc private func gearTapped() {
            if let menu = enclosingMenuItem?.menu {
                menu.cancelTracking()
            }
            onGear?()
        }

        @objc private func quitTapped() {
            if let menu = enclosingMenuItem?.menu {
                menu.cancelTracking()
            }
            onQuit?()
        }

        @objc private func retroTapped() {
            if let menu = enclosingMenuItem?.menu {
                menu.cancelTracking()
            }
            onRetro?()
        }
    }

    /// Toggle row with SF Symbol, label, optional hotkey hint, and a custom green pill toggle
    private final class MenuToggleRowView: NSView {
        private let pillToggle: PillToggleView
        private var onToggle: (() -> Void)?
        private let highlightView = NSView()
        private var hotkeyField: NSTextField?

        init(icon: String, label: String, hotkeyHint: String?, pill: PillToggleView, onToggle: @escaping () -> Void) {
            self.pillToggle = pill
            self.onToggle = onToggle
            super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
            autoresizingMask = .width

            // Highlight background (hidden by default)
            highlightView.wantsLayer = true
            highlightView.layer?.cornerRadius = 4
            highlightView.isHidden = true
            addSubview(highlightView)

            // Icon
            let iconImg = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
            let iconConfig = NSImage.SymbolConfiguration(scale: .small)
            let iconView = NSImageView(image: iconImg?.withSymbolConfiguration(iconConfig) ?? NSImage())
            iconView.frame = NSRect(x: 14, y: 5, width: 16, height: 16)
            iconView.contentTintColor = .secondaryLabelColor
            addSubview(iconView)

            // Label
            let labelField = NSTextField(labelWithString: label)
            labelField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            labelField.textColor = .labelColor
            labelField.frame = NSRect(x: 36, y: 5, width: 140, height: 16)
            addSubview(labelField)

            // Hotkey hint
            if let hint = hotkeyHint {
                let hf = NSTextField(labelWithString: hint)
                hf.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                hf.textColor = .tertiaryLabelColor
                hf.alignment = .right
                addSubview(hf)
                hotkeyField = hf
            }

            addSubview(pillToggle)

            // Track mouse for hover
            updateTrackingAreas()
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            let w = bounds.width
            // Position pill toggle at far right — pill is 36×18 (matches NSSwitch mini)
            let toggleW: CGFloat = 36
            let toggleH: CGFloat = 18
            let toggleX = w - toggleW - 12
            pillToggle.frame = NSRect(x: toggleX, y: (26 - toggleH) / 2, width: toggleW, height: toggleH)
            // Hotkey hint before toggle
            if let hf = hotkeyField {
                hf.frame = NSRect(x: toggleX - 52, y: 5, width: 44, height: 16)
            }
            // Highlight fill
            highlightView.frame = NSRect(x: 5, y: 1, width: w - 10, height: 24)
        }

        override func updateTrackingAreas() {
            for area in trackingAreas { removeTrackingArea(area) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
        }

        override func mouseUp(with event: NSEvent) {
            pillToggle.toggle()
            onToggle?()
        }

        override func mouseEntered(with event: NSEvent) {
            highlightView.isHidden = false
            highlightView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        }

        override func mouseExited(with event: NSEvent) {
            highlightView.isHidden = true
        }
    }

    /// A 36×18 pill-shaped toggle: green when on, gray when off, white knob.
    private final class PillToggleView: NSView {
        var isOn: Bool {
            didSet { needsDisplay = true }
        }

        init(isOn: Bool) {
            self.isOn = isOn
            super.init(frame: NSRect(x: 0, y: 0, width: 36, height: 18))
            wantsLayer = true
        }

        required init?(coder: NSCoder) { fatalError() }

        func toggle() {
            isOn.toggle()
        }

        override func draw(_ dirtyRect: NSRect) {
            let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)

            // Track color: green when on, gray when off
            let trackColor: NSColor = isOn
                ? NSColor(red: 0.20, green: 0.58, blue: 0.24, alpha: 1)  // phosphor green
                : NSColor(white: 0.72, alpha: 1)
            trackColor.setFill()
            path.fill()

            // Knob — white circle
            let knobDiameter: CGFloat = 14
            let knobY = (bounds.height - knobDiameter) / 2
            let knobX = isOn ? bounds.width - knobDiameter - 2 : CGFloat(2)
            let knobRect = NSRect(x: knobX, y: knobY, width: knobDiameter, height: knobDiameter)
            let knobPath = NSBezierPath(ovalIn: knobRect)
            NSColor.white.setFill()
            knobPath.fill()

            // Subtle shadow on knob
            NSColor(white: 0, alpha: 0.12).setStroke()
            knobPath.lineWidth = 0.5
            knobPath.stroke()
        }
    }

    // MARK: - Menu Builder Helpers

    /// Create an NSAttributedString with a label and right-aligned value chip
    private func menuTitle(_ label: String, value: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        let tabStop = NSTextTab(textAlignment: .right, location: 250)
        para.tabStops = [tabStop]

        let str = NSMutableAttributedString()
        str.append(NSAttributedString(
            string: label,
            attributes: [
                .font: NSFont.menuFont(ofSize: 14),
                .paragraphStyle: para,
            ]
        ))
        str.append(NSAttributedString(
            string: "\t\(value)",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: para,
            ]
        ))
        return str
    }

    /// Create a section header item (disabled, small-caps style)
    private func sectionLabel(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )
        item.isEnabled = false
        return item
    }

    /// Look up preset display name by ID
    private func presetDisplayName(for id: String?) -> String {
        guard let id = id else { return "—" }
        if let preset = PresetRegistry.builtinPresets.first(where: { $0.id == id }) {
            return preset.displayName
        }
        if let preset = PresetRegistry.customPresets().first(where: { $0.id == id }) {
            return preset.displayName
        }
        return id
    }

    /// Get the current display name for the value chip
    private func currentDisplayName() -> String {
        let tid = AppSettings.shared.targetDisplayID
        if tid == 0 { return "All" }
        for screen in NSScreen.screens {
            if screen.displayID == tid { return screen.localizedName }
        }
        return "Unknown"
    }

    /// Get current bloom value string
    private func bloomValueString() -> String {
        let s = AppSettings.shared
        if !s.bloomEnabled { return "Off" }
        return "\(Int(s.bloomIntensity * 100))%"
    }

    /// Get current vignette value string
    private func vignetteValueString() -> String {
        if currentVignetteIntensity < 0.01 { return "Off" }
        return "\(Int(currentVignetteIntensity * 100))%"
    }

    /// Get current theme value string
    private func themeValueString() -> String {
        let s = AppSettings.shared
        if !s.dockEnabled { return "Off" }
        // dockTheme stores the stable id — show the theme's display name instead.
        return ThemeManager.shared.theme(for: s.dockTheme)?.name ?? s.dockTheme
    }

    private func rebuildMenu() {
        // Overlay/preset state has settled by the time the menu is rebuilt (incl. the
        // async full-overlay completion). Notify the flyout so its shader toggle and
        // preset dropdown reflect the real state even after async activation.
        NotificationCenter.default.post(name: .overlayStateChanged, object: nil)
        let menu = NSMenu()
        menu.autoenablesItems = false
        let settings = AppSettings.shared
        let lm = LicenseManager.shared
        let vcam = VirtualCameraManager.shared

        // ── Header strip ──
        let presetName = presetDisplayName(for: currentPresetName)
        let overlayStatus = isActive ? "Overlay on" : "Overlay off"
        let displayName = currentDisplayName()
        let statusText = "\(overlayStatus) · \(displayName)"

        let headerView = MenuHeaderView(presetName: presetName, statusText: statusText, shaderOn: isActive, retroActive: retroModeActive, onGear: { [weak self] in
            self?.openSettings()
        }, onQuit: { [weak self] in
            self?.quitApp()
        }, onRetro: { [weak self] in
            self?.toggleRetroMode()
        })
        menuHeaderView = headerView
        let headerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        headerItem.view = headerView
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())

        // ── Shader toggle (whole screen) ──
        let shaderPill = PillToggleView(isOn: isActive && !launcherLiveWallpaperActive)
        shaderPillToggle = shaderPill
        let shaderRow = MenuToggleRowView(
            icon: "power.circle",
            label: "Shader",
            hotkeyHint: "\u{21E7}\u{2318}R",
            pill: shaderPill
        ) { [weak self] in
            self?.launcherToggleShader()   // whole-screen (not scope-stuck on wallpaper)
            self?.updateMenuLive()
        }
        let shaderItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        shaderItem.view = shaderRow
        menu.addItem(shaderItem)

        // ── Live Wallpaper toggle (Pro) — run the filter on the wallpaper only ──
        let livePill = PillToggleView(isOn: launcherLiveWallpaperActive)
        liveWallpaperPillToggle = livePill
        let liveRow = MenuToggleRowView(
            icon: "photo.on.rectangle.angled",
            label: LicenseManager.shared.label("Live Wallpaper"),
            hotkeyHint: nil,
            pill: livePill
        ) { [weak self] in
            self?.launcherToggleLiveWallpaper()
            self?.updateMenuLive()
        }
        let liveItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        liveItem.view = liveRow
        menu.addItem(liveItem)

        // ── Virtual Camera toggle (Pro) ──
        let cameraPill = PillToggleView(isOn: vcam.isRunning || vcam.activationPending)
        cameraPillToggle = cameraPill
        let cameraRow = MenuToggleRowView(
            icon: "camera.fill",
            label: LicenseManager.shared.label("Virtual Camera"),
            hotkeyHint: nil,
            pill: cameraPill
        ) { [weak self] in
            self?.toggleVirtualCamera()
            self?.updateMenuLive()
        }
        let cameraItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        cameraItem.view = cameraRow
        menu.addItem(cameraItem)

        // ── Retro Viewport toggle ──
        let viewportPill = PillToggleView(isOn: retroViewport.isActive)
        viewportPillToggle = viewportPill
        let viewportRow = MenuToggleRowView(
            icon: "viewfinder",
            label: "Retro Viewport",
            hotkeyHint: nil,
            pill: viewportPill
        ) { [weak self] in
            self?.toggleViewport()
            self?.updateMenuLive()
        }
        let viewportToggleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        viewportToggleItem.view = viewportRow
        menu.addItem(viewportToggleItem)

        // ── TV Tube toggle ──
        let tubePill = PillToggleView(isOn: TubeModeController.shared.isActive)
        let tubeRow = MenuToggleRowView(
            icon: "tv",
            label: "TV Tube",
            hotkeyHint: nil,
            pill: tubePill
        ) { [weak self] in
            self?.toggleTubeMode()
            self?.updateMenuLive()
        }
        let tubeToggleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        tubeToggleItem.view = tubeRow
        menu.addItem(tubeToggleItem)

        // ── Window Borders (Theme) toggle — prototype ──
        let bordersPill = PillToggleView(isOn: AppSettings.shared.themeWindowBorders)
        let bordersRow = MenuToggleRowView(
            icon: "macwindow",
            label: "Window Borders (Theme)",
            hotkeyHint: nil,
            pill: bordersPill
        ) { [weak self] in
            self?.toggleThemeWindowBorders()
            bordersPill.isOn = AppSettings.shared.themeWindowBorders
            self?.updateMenuLive()
        }
        let bordersToggleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        bordersToggleItem.view = bordersRow
        menu.addItem(bordersToggleItem)

        // ── PRESETS section ──
        menu.addItem(sectionLabel("PRESETS"))

        // Shader Presets submenu
        let presetsItem = NSMenuItem(title: "Shader Presets", action: nil, keyEquivalent: "")
        presetsItem.image = sfIcon("slider.horizontal.3")
        presetsItem.attributedTitle = menuTitle("Shader Presets", value: presetName)
        let presetsMenu = NSMenu()

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
        let byName: (PresetInfo, PresetInfo) -> Bool = { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        for preset in allBuiltin.filter({ LicenseManager.freePresetIDs.contains($0.id) }).sorted(by: byName) {
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

        // "Lite (Permission free)" — directly under Free, ABOVE the divider, with its own icon.
        if let liteEntry = PresetRegistry.categorizedPresets.first(where: { $0.0 == .lite }) {
            let catItem = NSMenuItem(title: liteEntry.0.rawValue, action: nil, keyEquivalent: "")
            catItem.image = sfIcon("bolt.fill")
            let catMenu = NSMenu()
            for preset in liteEntry.1.sorted(by: byName) {
                let item = NSMenuItem(title: preset.displayName, action: #selector(selectPreset(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.id
                if preset.id == currentPresetName { item.state = .on }
                catMenu.addItem(item)
            }
            catItem.submenu = catMenu
            if liteEntry.1.contains(where: { $0.id == currentPresetName }) { catItem.state = .mixed }
            presetsMenu.addItem(catItem)
        }
        presetsMenu.addItem(NSMenuItem.separator())

        // Category submenus (alphabetical within each; Lite already shown above the divider)
        for (category, presets) in PresetRegistry.categorizedPresets where category != .lite {
            let catItem = NSMenuItem(title: category.rawValue, action: nil, keyEquivalent: "")
            let catMenu = NSMenu()
            for preset in presets.sorted(by: byName) {
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

        // ── Shader Options submenu (Intensity / Vignette / Bloom) ──
        let shaderOptionsItem = NSMenuItem(title: "Shader Options", action: nil, keyEquivalent: "")
        shaderOptionsItem.image = sfIcon("slider.horizontal.3")
        let shaderOptionsMenu = NSMenu()
        shaderOptionsItem.submenu = shaderOptionsMenu
        menu.addItem(shaderOptionsItem)

        // Intensity submenu with value chip
        let intensityItem = NSMenuItem(title: "Intensity", action: nil, keyEquivalent: "")
        intensityItem.image = sfIcon("sun.max")
        intensityItem.title = "Intensity — \(Int(currentIntensity * 100))%"
        let intensityMenu = NSMenu()
        for pct in stride(from: 10, through: 100, by: 10) {
            let item = NSMenuItem(title: "\(pct)%", action: #selector(setIntensity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = pct
            if abs(Float(pct) / 100.0 - currentIntensity) < 0.01 { item.state = .on }
            intensityMenu.addItem(item)
        }
        intensityItem.submenu = intensityMenu
        shaderOptionsMenu.addItem(intensityItem)

        // Vignette submenu with value chip (disabled for Lite presets)
        let isLitePreset = Self.isLitePreset(currentPresetName)
        let vignetteItem = NSMenuItem(title: "Vignette", action: nil, keyEquivalent: "")
        vignetteItem.image = sfIcon("circle.circle")
        vignetteItem.title = "Vignette — \(isLitePreset ? "n/a" : vignetteValueString())"
        vignetteItem.isEnabled = !isLitePreset
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
        shaderOptionsMenu.addItem(vignetteItem)

        // Bloom submenu with value chip (disabled for Lite presets)
        let bloomItem = NSMenuItem(title: "Bloom", action: nil, keyEquivalent: "")
        bloomItem.image = sfIcon("sparkles")
        bloomItem.title = "Bloom — \(isLitePreset ? "n/a" : bloomValueString())"
        bloomItem.isEnabled = !isLitePreset
        let bloomMenu = NSMenu()

        let bloomToggle = NSMenuItem(
            title: settings.bloomEnabled ? "\u{2713} Enabled" : "Off",
            action: #selector(toggleBloom),
            keyEquivalent: ""
        )
        bloomToggle.target = self
        bloomMenu.addItem(bloomToggle)
        bloomMenu.addItem(.separator())

        for pct in [10, 20, 30, 50, 75, 100] {
            let item = NSMenuItem(title: "\(pct)%", action: #selector(setBloomIntensity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = pct
            if settings.bloomEnabled && abs(Float(pct) / 100.0 - settings.bloomIntensity) < 0.01 {
                item.state = .on
            }
            bloomMenu.addItem(item)
        }
        bloomItem.submenu = bloomMenu
        shaderOptionsMenu.addItem(bloomItem)

        // Phosphor afterglow — persistence across frames (renderer feature, not a shader preset)
        let phosItem = NSMenuItem(title: "Phosphor Glow", action: nil, keyEquivalent: "")
        phosItem.image = sfIcon("light.max")
        phosItem.title = "Phosphor Glow \u{2014} \(isLitePreset ? "n/a" : phosphorValueString())"
        phosItem.isEnabled = !isLitePreset
        let phosMenu = NSMenu()
        let phosOff = NSMenuItem(title: settings.phosphorPersistence <= 0.001 ? "\u{2713} Off" : "Off",
                                 action: #selector(setPhosphorPersistence(_:)), keyEquivalent: "")
        phosOff.target = self; phosOff.tag = 0
        phosMenu.addItem(phosOff)
        phosMenu.addItem(.separator())
        for pct in [15, 30, 50, 75, 100] {
            let item = NSMenuItem(title: "\(pct)%", action: #selector(setPhosphorPersistence(_:)), keyEquivalent: "")
            item.target = self
            item.tag = pct
            if abs(Float(pct) / 100.0 - settings.phosphorPersistence) < 0.01 { item.state = .on }
            phosMenu.addItem(item)
        }
        phosItem.submenu = phosMenu
        shaderOptionsMenu.addItem(phosItem)

        // Display submenu with value chip
        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        displayItem.image = sfIcon("display")
        displayItem.attributedTitle = menuTitle("Display", value: currentDisplayName())
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

        // Where the effect is drawn. Both entries are listed and the active one is ticked:
        // only the window entry existed, so once a customer had picked a window there was no
        // visible way back to the whole screen, and nothing said which mode they were in.
        let isWindowMode: Bool
        if case .singleWindow = overlayController?.captureMode { isWindowMode = true } else { isWindowMode = false }

        let fullScreenItem = NSMenuItem(title: "Apply to Full Screen", action: #selector(applyFullScreen), keyEquivalent: "")
        fullScreenItem.target = self
        fullScreenItem.image = sfIcon("display")
        fullScreenItem.state = (isActive && !isWindowMode) ? .on : .off
        menu.addItem(fullScreenItem)

        // Window picker
        let pickItem = NSMenuItem(title: "Apply to Window\u{2026}", action: #selector(pickWindowVisual), keyEquivalent: "")
        pickItem.target = self
        pickItem.image = sfIcon("macwindow")
        pickItem.state = (isActive && isWindowMode) ? .on : .off
        menu.addItem(pickItem)

        menu.addItem(NSMenuItem.separator())

        // ── RETROMAC section ──
        menu.addItem(sectionLabel("RETROMAC"))

        // Themes submenu with value chip
        let themesItem = NSMenuItem(title: "Themes", action: nil, keyEquivalent: "")
        themesItem.image = sfIcon("paintpalette")
        themesItem.attributedTitle = menuTitle("Themes", value: themeValueString())
        let themesMenu = NSMenu()
        let dockOn = AppSettings.shared.dockEnabled
        let currentTheme = AppSettings.shared.dockTheme

        let offItem = NSMenuItem(title: "Off", action: #selector(disableTheme), keyEquivalent: "")
        offItem.target = self
        if !dockOn { offItem.state = .on }
        themesMenu.addItem(offItem)
        themesMenu.addItem(.separator())

        func themeCategory(_ name: String) -> String {
            let n = name.lowercased()
            // Check Unix & Amiga first so "BeOS Classic" isn't caught by the Apple "classic" rule.
            if n.contains("beos") || n.contains("os/2") || n.contains("warp") || n.contains("sgi")
                || n.contains("irix") || n.contains("amiga") || n.contains("workbench") { return "Unix & Amiga" }
            if n.contains("mac os") || n.contains("aqua") || n.contains("snow leopard")
                || n.contains("mountain lion") || n.contains("platinum") || n.contains("classic") { return "Apple" }
            if n.contains("windows") { return "Windows" }
            return "Other"
        }
        for category in ["Apple", "Windows", "Unix & Amiga", "Other"] {
            let inCategory = ThemeManager.shared.availableThemes.filter { themeCategory($0.name) == category }
            guard !inCategory.isEmpty else { continue }
            // Each category is its own submenu entry.
            let catItem = NSMenuItem(title: category, action: nil, keyEquivalent: "")
            let catMenu = NSMenu()
            for theme in inCategory.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
                let item = NSMenuItem(title: ThemeManager.displayName(for: theme.name), action: #selector(selectTheme(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = theme.name
                if dockOn && theme.stableID == currentTheme { item.state = .on }
                // The crown (👑) is carried by displayName across all crowned themes —
                // one consistent marker, no separate SF-Symbol image.
                catMenu.addItem(item)
            }
            catItem.submenu = catMenu
            themesMenu.addItem(catItem)
        }
        themesItem.submenu = themesMenu
        menu.addItem(themesItem)

        // About This Theme — a historical readme (with "did you know" curiosities) for the
        // active theme's OS, shown only when the theme ships a readme.html.
        if ThemeReadmeController.activeThemeHasReadme() {
            let aboutTheme = NSMenuItem(title: "About This Theme\u{2026}", action: #selector(showThemeReadme), keyEquivalent: "")
            aboutTheme.image = sfIcon("book")
            aboutTheme.target = self
            menu.addItem(aboutTheme)
        }

        // (Television submenu removed — channels live in the TV Tube toggle + its
        // right-click menu; the dock/start-menu entries start the Tube directly.)

        // Crash now — where a demo can reach it without opening Settings. Only offered when the
        // active theme has crashes, and locked like every other paid feature.
        if CrashEra.current() != nil {
            let crashItem = NSMenuItem(title: LicenseManager.shared.label("Crash Now"),
                                       action: #selector(crashNow), keyEquivalent: "")
            crashItem.target = self
            crashItem.image = sfIcon("exclamationmark.triangle")
            menu.addItem(crashItem)
        }

        // Games: one click, straight into the Library. It used to be a submenu, but since the
        // individual "Play …" entries moved into the Library window there was nothing else in it
        // — a submenu whose only job was to hold a single item.
        let gamesItem = NSMenuItem(title: "Game Library\u{2026}", action: #selector(openGameLibrary), keyEquivalent: "")
        gamesItem.target = self
        gamesItem.image = sfIcon("gamecontroller")
        menu.addItem(gamesItem)

        // Imported ROMs are a different thing from the Library — the user's own files, played
        // through RetroArch — so they keep their own submenu, and only when there are any.
        let romEntries = ROMLibrary.shared.entries
        if !romEntries.isEmpty {
            let retroItem = NSMenuItem(title: "Retro Games", action: nil, keyEquivalent: "")
            retroItem.image = sfIcon("gamecontroller.fill")
            let retroMenu = NSMenu()
            for rom in romEntries.prefix(15) {
                let romItem = NSMenuItem(
                    title: "\(rom.displayName)  (\(rom.system.shortName))",
                    action: #selector(launchRetroGame(_:)),
                    keyEquivalent: ""
                )
                romItem.target = self
                romItem.representedObject = rom.id
                romItem.image = sfIcon(rom.system.sfSymbol)
                romItem.isEnabled = rom.system.emulator.isInstalled
                retroMenu.addItem(romItem)
            }
            retroItem.submenu = retroMenu
            menu.addItem(retroItem)
        }

        menu.addItem(NSMenuItem.separator())

        // ── Screenshot with shader ──
        let screenshotItem = NSMenuItem(title: "Screenshot with Shader", action: #selector(screenshotMenuAction), keyEquivalent: "")
        screenshotItem.target = self
        screenshotItem.image = sfIcon("camera.fill")
        screenshotItem.isEnabled = isActive || retroViewport.isActive
        menu.addItem(screenshotItem)

        menu.addItem(NSMenuItem.separator())
        let wizardItem = NSMenuItem(title: "Setup Assistant\u{2026}", action: #selector(openSetupWizard), keyEquivalent: "")
        wizardItem.target = self
        wizardItem.image = sfIcon("wand.and.stars")
        menu.addItem(wizardItem)

        let floatItem = NSMenuItem(title: "Floating Launcher Button", action: #selector(toggleFloatingLauncher), keyEquivalent: "")
        floatItem.target = self
        floatItem.image = sfIcon("circle.dashed")
        floatItem.state = AppSettings.shared.floatingLauncherEnabled ? .on : .off
        menu.addItem(floatItem)

        // Quit moved to a power symbol in the header; Reset Permissions moved to Settings.
        statusItem.menu = menu
    }

    /// Reset this app's Screen Recording + Camera TCC grants, then point the user at the
    /// right System Settings panes. Useful after a rare update where macOS invalidates a
    /// grant — gives a clean path back into the permission prompts.
    @objc func resetPermissions() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.retromac.app"
        for service in ["ScreenCapture", "Camera"] {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            proc.arguments = ["reset", service, bundleID]
            try? proc.run()
            proc.waitUntilExit()
        }
        let alert = NSAlert()
        alert.messageText = "Permissions reset"
        alert.informativeText = "Screen Recording and Camera permissions for RetroMac were reset.\n\nQuit and reopen RetroMac, then allow them again when prompted (or enable them in System Settings)."
        alert.addButton(withTitle: "Open Screen Recording")
        alert.addButton(withTitle: "Open Camera")
        alert.addButton(withTitle: "Later")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(u) }
        case .alertSecondButtonReturn:
            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") { NSWorkspace.shared.open(u) }
        default: break
        }
    }

    /// Update the live menu views in-place (header dot/text + pill toggles) without rebuilding the menu.
    /// Called from toggle actions so the currently-visible menu popup reflects the new state immediately.
    private func updateMenuLive() {
        let presetName = presetDisplayName(for: currentPresetName)
        let overlayStatus = isActive ? "Overlay on" : "Overlay off"
        let displayName = currentDisplayName()
        let statusText = "\(overlayStatus) · \(displayName)"

        menuHeaderView?.update(shaderOn: isActive, presetName: presetName, statusText: statusText, retroActive: retroModeActive)
        shaderPillToggle?.isOn = isActive && !launcherLiveWallpaperActive
        liveWallpaperPillToggle?.isOn = launcherLiveWallpaperActive
        cameraPillToggle?.isOn = VirtualCameraManager.shared.isRunning || VirtualCameraManager.shared.activationPending
        viewportPillToggle?.isOn = retroViewport.isActive
    }

    // MARK: - Carbon Global Hotkey

    // Hotkey IDs: signature "RMAC", different id per action
    private let hotkeySignature = OSType(0x524D4143) // "RMAC"

    func registerHotkey() {
        unregisterHotkey()

        let settings = AppSettings.shared

        // 1. Toggle overlay hotkey (id: 1) — require at least one system modifier
        if settings.hotkeyModifiers != 0 {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: hotkeySignature, id: 1)
            if RegisterEventHotKey(settings.hotkeyCode, settings.hotkeyModifiers,
                                   hkID, GetApplicationEventTarget(), 0, &ref) == noErr {
                hotKeyRef = ref
            }
        }

        // 2. Screenshot with shader hotkey (id: 6) — require at least one system modifier
        if settings.screenshotHotkeyModifiers != 0 {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: hotkeySignature, id: 6)
            if RegisterEventHotKey(settings.screenshotHotkeyCode, settings.screenshotHotkeyModifiers,
                                   hkID, GetApplicationEventTarget(), 0, &ref) == noErr {
                screenshotHotKeyRef = ref
            }
        }

        // 3. Toggle system menu bar hotkey (id: 7) — require at least one system modifier
        if settings.menuBarToggleHotkeyModifiers != 0 {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: hotkeySignature, id: 7)
            if RegisterEventHotKey(settings.menuBarToggleHotkeyCode, settings.menuBarToggleHotkeyModifiers,
                                   hkID, GetApplicationEventTarget(), 0, &ref) == noErr {
                menuBarHotKeyRef = ref
            }
        }

        // 4. Dashboard layer (id: 8) — require at least one system modifier
        if settings.dashboardHotkeyModifiers != 0 {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: hotkeySignature, id: 8)
            if RegisterEventHotKey(settings.dashboardHotkeyCode, settings.dashboardHotkeyModifiers,
                                   hkID, GetApplicationEventTarget(), 0, &ref) == noErr {
                dashboardHotKeyRef = ref
            }
        }

        // 5. Exposé, all windows (id: 9) and the frontmost app's windows (id: 10)
        if settings.exposeHotkeyModifiers != 0 {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: hotkeySignature, id: 9)
            if RegisterEventHotKey(settings.exposeHotkeyCode, settings.exposeHotkeyModifiers,
                                   hkID, GetApplicationEventTarget(), 0, &ref) == noErr {
                exposeHotKeyRef = ref
            }
        }
        if settings.exposeAppHotkeyModifiers != 0 {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: hotkeySignature, id: 10)
            if RegisterEventHotKey(settings.exposeAppHotkeyCode, settings.exposeAppHotkeyModifiers,
                                   hkID, GetApplicationEventTarget(), 0, &ref) == noErr {
                exposeAppHotKeyRef = ref
            }
        }

        // Install event handler (once)
        if eventHandlerRef == nil {
            var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(
                GetApplicationEventTarget(),
                { (_, event, userData) -> OSStatus in
                    guard let userData = userData, let event = event else { return OSStatus(eventNotHandledErr) }
                    let d = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                    var hkID = EventHotKeyID()
                    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                    switch hkID.id {
                    case 1: DispatchQueue.main.async { d.toggleOverlay() }
                    case 6: DispatchQueue.main.async { d.captureScreenshotWithShader() }
                    case 7: DispatchQueue.main.async { d.toggleMenuBar() }
                    case 8: DispatchQueue.main.async { DashboardController.shared.toggle() }
                    case 9: DispatchQueue.main.async { ExposeController.shared.toggle(.allWindows) }
                    case 10: DispatchQueue.main.async { ExposeController.shared.toggle(.applicationWindows) }
                    default: return OSStatus(eventNotHandledErr)
                    }
                    return noErr
                },
                1, &eventSpec, selfPtr, &eventHandlerRef
            )
        }
    }

    private func unregisterHotkey() {
        if let ref = exposeHotKeyRef {
            UnregisterEventHotKey(ref)
            exposeHotKeyRef = nil
        }
        if let ref = exposeAppHotKeyRef {
            UnregisterEventHotKey(ref)
            exposeAppHotKeyRef = nil
        }
        if let ref = dashboardHotKeyRef {
            UnregisterEventHotKey(ref)
            dashboardHotKeyRef = nil
        }
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = screenshotHotKeyRef {
            UnregisterEventHotKey(ref)
            screenshotHotKeyRef = nil
        }
        if let ref = menuBarHotKeyRef {
            UnregisterEventHotKey(ref)
            menuBarHotKeyRef = nil
        }
    }

    /// Global hotkey: toggle the system menu bar auto-hide on/off.
    func toggleMenuBar() {
        menuBarHiddenByHotkey.toggle()
        SystemUIHelper.setMenuBarAutoHide(menuBarHiddenByHotkey)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, !self.isActive else { return }
            self.startOverlay(mode: .fullScreen)
        }
    }

    // MARK: - Actions

    func disableAll() {
        print("[RetroMac] disableAll()")

        overlayStartTask?.cancel()
        overlayStartTask = nil
        permissionPollTimer?.invalidate()   // stop waiting for Screen Recording if we're turning off
        permissionPollTimer = nil
        overlayController?.stop()
        overlayController = nil
        crtLiteOverlay?.stop()
        crtLiteOverlay = nil
        wallpaperShaderController?.stop()
        wallpaperShaderController = nil
        DisplayFilterHelper.restoreFilter()  // Safety net for B&W / Amber Lite
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

    /// Whether the given preset is a "Lite" overlay (no screen recording needed)
    private static let litePresetIDs: Set<String> = [
        "crt-lite", "lcd-lite", "lcd-retro-lite", "lcd-sharp-lite", "lcd-broken-lite",
        "bw-lite", "amber-lite", "vhs-lite", "scanlines-lite", "grain-lite"
    ]

    static func isLitePreset(_ presetID: String?) -> Bool {
        guard let id = presetID else { return false }
        return litePresetIDs.contains(id)
    }

    /// Wallpaper-only mode renders through the full Metal shader (it never captures the screen,
    /// so the "Lite / no-recording" distinction is moot). Map Lite ids to a full-shader
    /// equivalent so picking e.g. "VHS Lite" still gives an animated VHS wallpaper.
    private static let liteToFullPreset: [String: String] = [
        "crt-lite": "zfast-crt", "lcd-lite": "lcd-grid", "lcd-retro-lite": "zfast-lcd",
        "lcd-sharp-lite": "lcd3x", "lcd-broken-lite": "zfast-lcd", "bw-lite": "bw-film",
        "amber-lite": "amber-monitor", "vhs-lite": "vhs", "scanlines-lite": "zfast-crt",
        "grain-lite": "cinema-film"
    ]

    private static func fullPreset(for presetID: String) -> String {
        isLitePreset(presetID) ? (liteToFullPreset[presetID] ?? "zfast-crt") : presetID
    }

    /// Whether the desktop effect should render on the wallpaper only (vs the whole screen).
    /// Wallpaper mode is a Pro feature — gate on the license so a stale/expired key (or a lapsed
    /// license with the pref still set true) cleanly falls back to the free whole-screen effect.
    private var isWallpaperOnlyScope: Bool {
        AppSettings.shared.shaderWallpaperOnly && LicenseManager.shared.isLicensed
    }

    /// Present the unlock / coffee screen (inline key entry) for a locked Pro feature. Called
    /// from Settings when an unlicensed user tries to turn on a Pro-only control.
    func presentUnlockScreen() { welcomeFlow.showCoffee() }

    /// Start (or restart) the wallpaper-only desktop effect. Tears down any whole-screen /
    /// Lite overlay first — the two scopes are mutually exclusive.
    private func startWallpaperShader(presetID: String) {
        overlayStartTask?.cancel()
        overlayStartTask = nil
        overlayController?.stop()
        overlayController = nil
        crtLiteOverlay?.stop()
        crtLiteOverlay = nil
        wallpaperShaderController?.stop()
        wallpaperShaderController = nil

        let effective = Self.fullPreset(for: presetID)
        do {
            let controller = try WallpaperShaderController.create(presetName: effective)
            controller.intensity = currentIntensity
            controller.vignetteIntensity = currentVignetteIntensity
            let settings = AppSettings.shared
            controller.renderer.bloomEnabled = settings.bloomEnabled
            controller.renderer.bloomIntensity = settings.bloomIntensity
            controller.renderer.phosphorPersistence = settings.phosphorPersistence
            controller.renderer.bloomRadius = settings.bloomRadius
            controller.start()
            wallpaperShaderController = controller
            currentPresetName = presetID
            isActive = true
            updateMenuBarIcon()
            rebuildMenu()
            NotificationCenter.default.post(name: .overlayStateChanged, object: nil)
            print("[RetroMac] Wallpaper-only shader started: \(presetID) → \(effective)")
        } catch {
            print("[RetroMac] Wallpaper shader ERROR: \(error)")
            let alert = NSAlert()
            alert.messageText = "RetroMac Error"
            alert.informativeText = "\(error.localizedDescription)"
            alert.runModal()
        }
    }

    @objc func toggleOverlay() {
        if isActive {
            disableAll()
            rememberShaderStateForActiveTheme(on: false)
        } else {
            // Mutual exclusivity: stop camera and viewport first
            if VirtualCameraManager.shared.isRunning { VirtualCameraManager.shared.stop() }
            if retroViewport.isActive { retroViewport.hide() }

            startCurrentEffect()
            rememberShaderStateForActiveTheme(on: true)
        }
    }

    /// Start whichever effect the current settings call for (wallpaper-only, Lite, or the full
    /// Metal overlay). Split out of `toggleOverlay` so a settings change can re-arm the same
    /// path without duplicating the dispatch.
    private func startCurrentEffect() {
        if isWallpaperOnlyScope {
            startWallpaperShader(presetID: currentPresetName ?? AppSettings.shared.defaultPreset)
        } else if Self.isLitePreset(currentPresetName) {
            // Lite presets use transparent overlay — no screen recording needed
            startCRTLite(mode: .fullScreen)
        } else {
            startOverlay(mode: .fullScreen)
        }
    }

    /// Re-arm the running effect so a changed capture setting (frame rate, quality) takes hold
    /// straight away instead of at the next manual restart. No-op when nothing is running.
    @objc func reapplyCaptureSettings() {
        guard isActive else { return }
        disableAll()
        // Next runloop turn: let the old capture tear down before the new one claims the display.
        DispatchQueue.main.async { [weak self] in self?.startCurrentEffect() }
    }

    /// Persist the shader on/off choice for the currently active theme, so switching away and
    /// back restores it. No-op when no theme is active.
    ///
    /// Off sets a flag and leaves the theme's preset assignment alone. It used to write an empty
    /// preset instead, which meant "off" and "no preset assigned" were the same stored value, so
    /// switching off in the flyout quietly discarded the theme's preset.
    private func rememberShaderStateForActiveTheme(on: Bool) {
        guard AppSettings.shared.dockEnabled,
              let name = ThemeManager.shared.activeTheme?.config.settingsKey else { return }
        if on {
            AppSettings.shared.themeShaderDisabled[name] = nil
            // The preset picked while this theme was up stays with it, as before.
            AppSettings.shared.themePresetOverrides[name] =
                currentPresetName ?? AppSettings.shared.defaultPreset
        } else {
            AppSettings.shared.themeShaderDisabled[name] = true
        }
    }

    private func startOverlay(mode: CaptureMode, presetOverride: String? = nil, parentWindow: NSWindow? = nil) {
        // Redirect to Lite overlay if that's the selected preset
        let effectivePreset = presetOverride ?? currentPresetName ?? ""

        // Wallpaper-only scope supersedes both full-capture and Lite for the DESKTOP modes
        // (full screen / single display). Per-window & TV overlays still capture as before.
        if isWallpaperOnlyScope {
            switch mode {
            case .fullScreen, .singleDisplay:
                startWallpaperShader(presetID: effectivePreset.isEmpty ? AppSettings.shared.defaultPreset : effectivePreset)
                return
            case .singleWindow:
                break
            }
        }
        if Self.isLitePreset(effectivePreset) {
            if case .singleWindow(let scWindow) = mode,
               let bundleID = scWindow.owningApplication?.bundleIdentifier {
                startCRTLite(mode: .forApp(bundleID: bundleID))
            } else {
                startCRTLite(mode: .fullScreen)
            }
            return
        }

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
            alert.messageText = "Screen Recording Permission"
            alert.informativeText = """
                After an update you need to re-grant Screen Recording:

                1. Remove RetroMac with the minus (\u{2212}) button
                2. Re-add RetroMac with the plus (+) button

                The shader will start automatically once granted.
                """
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            let captureMode = effectiveMode
            let capturePreset = presetName
            let captureParent = parentWindow
            permissionPollTimer?.invalidate()
            var pollTicks = 0
            permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                if CGPreflightScreenCaptureAccess() {
                    timer.invalidate()
                    self?.permissionPollTimer = nil
                    self?.startOverlay(mode: captureMode, presetOverride: capturePreset, parentWindow: captureParent)
                    return
                }
                // Give up after ~2 min so a never-granted (or denied) permission doesn't spin the
                // timer forever. The user can retry by toggling the shader again.
                pollTicks += 1
                if pollTicks >= 120 {
                    timer.invalidate()
                    self?.permissionPollTimer = nil
                    print("[RetroMac] Screen Recording not granted within 2 min — stopping permission poll.")
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

                // Apply bloom settings from preferences
                let bloomSettings = AppSettings.shared
                if let renderer = controller.renderer {
                    renderer.bloomEnabled = bloomSettings.bloomEnabled
                    renderer.bloomIntensity = bloomSettings.bloomIntensity
                    renderer.phosphorPersistence = bloomSettings.phosphorPersistence
                    renderer.bloomRadius = bloomSettings.bloomRadius
                }

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

    // MARK: - CRT Lite Overlay (no screen recording)

    enum CRTLiteMode {
        case fullScreen
        case forApp(bundleID: String)
    }

    func startCRTLite(mode: CRTLiteMode, presetName: String? = nil) {
        let preset = presetName ?? currentPresetName ?? "crt-lite"

        // Stop any existing overlay
        overlayController?.stop()
        overlayController = nil
        crtLiteOverlay?.stop()
        let overlay = CRTLiteOverlay()

        switch mode {
        case .fullScreen:
            overlay.startFullScreen(
                intensity: currentIntensity,
                vignetteIntensity: currentVignetteIntensity,
                preset: preset
            )
        case .forApp(let bundleID):
            overlay.startForApp(
                bundleID: bundleID,
                intensity: currentIntensity,
                vignetteIntensity: currentVignetteIntensity,
                preset: preset
            )
        }

        crtLiteOverlay = overlay
        currentPresetName = preset
        isActive = true

        // Apply bloom settings to Lite overlay
        let bloomSettings = AppSettings.shared
        overlay.bloomEnabled = bloomSettings.bloomEnabled
        overlay.bloomIntensity = bloomSettings.bloomIntensity
        overlay.bloomRadius = bloomSettings.bloomRadius

        updateMenuBarIcon()
        rebuildMenu()
        print("[RetroMac] Lite overlay started: \(preset) (mode: \(mode))")
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

        // If the Virtual Camera is running, route preset changes to the camera
        // ONLY — just like the Retro Viewport. Do NOT touch the full-screen overlay.
        // Preset IDs and camera shader names share the same namespace
        // (both resolve through BuiltinShaders.source(for:)), so the preset ID can
        // be passed straight to changeShader. changeShader tolerates shaders with no
        // camera equivalent (it logs the failure rather than crashing).
        if VirtualCameraManager.shared.isRunning {
            currentPresetName = presetId
            VirtualCameraManager.shared.changeShader(presetId)
            rebuildMenu()
            return
        }

        // If Retro Viewport is active, route all preset changes to it
        if retroViewport.isActive {
            currentPresetName = presetId
            AppSettings.shared.defaultPreset = presetId
            AppSettings.shared.viewportPreset = presetId
            retroViewport.switchPreset(presetId)
            rebuildMenu()
            return
        }

        // Wallpaper-only scope: route every preset change to the wallpaper effect (no capture,
        // no Lite/full split — the wallpaper controller handles any preset).
        if isWallpaperOnlyScope {
            currentPresetName = presetId
            AppSettings.shared.defaultPreset = presetId
            if isActive, wallpaperShaderController != nil {
                applyPreset(presetId)
            } else {
                startWallpaperShader(presetID: presetId)
            }
            rebuildMenu()
            return
        }

        // Lite presets: switch overlay type if changing to/from lite
        if Self.isLitePreset(presetId) {
            // Stop full overlay if running, start Lite
            if isActive && overlayController != nil {
                disableAll()
            }
            currentPresetName = presetId
            AppSettings.shared.defaultPreset = presetId
            if !isActive {
                startCRTLite(mode: .fullScreen, presetName: presetId)
            } else {
                // Already running a lite overlay — switch shader
                disableAll()
                startCRTLite(mode: .fullScreen, presetName: presetId)
            }
        } else {
            // Set the preset name BEFORE starting overlay — startOverlay is async
            // and reads currentPresetName to load the correct shader.
            currentPresetName = presetId
            AppSettings.shared.defaultPreset = presetId

            // Stop Lite overlay if running
            if crtLiteOverlay?.isActive == true {
                disableAll()
            }

            if !isActive {
                // Start full overlay — will use currentPresetName (already set above)
                startOverlay(mode: .fullScreen)
            } else {
                // Already running a full overlay — just switch the shader in-place
                applyPreset(presetId)
            }
        }
    }

    @objc private func setIntensity(_ sender: NSMenuItem) {
        currentIntensity = Float(sender.tag) / 100.0
        if retroViewport.isActive {
            retroViewport.intensity = currentIntensity
        }
        overlayController?.intensity = currentIntensity
        crtLiteOverlay?.intensity = currentIntensity
        wallpaperShaderController?.intensity = currentIntensity
        rebuildMenu()
    }

    @objc private func setVignette(_ sender: NSMenuItem) {
        currentVignetteIntensity = Float(sender.tag) / 100.0
        if retroViewport.isActive {
            retroViewport.vignetteIntensity = currentVignetteIntensity
        }
        overlayController?.vignetteIntensity = currentVignetteIntensity
        crtLiteOverlay?.vignetteIntensity = currentVignetteIntensity
        wallpaperShaderController?.vignetteIntensity = currentVignetteIntensity
        rebuildMenu()
    }

    @objc private func selectScanline(_ sender: NSMenuItem) {
        let name = sender.representedObject as? String ?? ""
        AppSettings.shared.scanlineOverlayName = name
        overlayController?.loadOverlays()
        wallpaperShaderController?.loadOverlays()
        rebuildMenu()
    }

    @objc private func selectReflection(_ sender: NSMenuItem) {
        let name = sender.representedObject as? String ?? ""
        AppSettings.shared.reflectionName = name
        overlayController?.loadOverlays()
        wallpaperShaderController?.loadOverlays()
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
            self.rebuildMenu()      // move the tick onto "Apply to Window"
        }
    }

    @objc private func applyFullScreen() {
        // Reachable from the menu now, so it has to cope with being chosen while a single-window
        // overlay is up, or while nothing is running at all.
        if isActive { disableAll() }
        startCurrentEffect()
        rememberShaderStateForActiveTheme(on: true)
        rebuildMenu()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    /// The classic "Windows Update" Start-menu entry: on-theme, it checks for RetroMac updates via
    /// Sparkle. In .dev builds Sparkle is off, so fall back to the GitHub releases page.
    @objc private func windowsUpdate() {
        if AppDelegate.sparkleEnabled {
            updaterController.checkForUpdates(nil)
        } else if let url = URL(string: "https://github.com/klotzbrocken/RetroMac/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Launch the post-install Setup Assistant on demand (menu / Settings ▸ Overview).
    @objc func openSetupWizard() {
        setupWizard.show()
    }

    /// Toggle the floating, draggable launcher button.
    @objc func toggleFloatingLauncher() {
        AppSettings.shared.floatingLauncherEnabled.toggle()
        rebuildMenu()
    }

    @objc private func openTVBookmark(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let uuid = UUID(uuidString: idString),
              let bookmark = AppSettings.shared.tvBookmarks.first(where: { $0.id == uuid }) else { return }
        // Context-menu streams open the immersive Tube Mode directly on that channel
        // (the small windowed TV stays reachable via the TV desktop widget).
        TubeModeController.shared.startOnBookmark(url: bookmark.url)
    }

    /// Flyout / menu "TV Tube" toggle: the one-click retro TV (bezel + streams + shader).
    @objc func toggleTubeMode() {
        TubeModeController.shared.toggle()
        rebuildMenu()
    }

    /// Stop anything that would visually collide with Tube Mode — it renders its own
    /// shader at window level, so a global overlay/lite (level 28) or the viewport/camera
    /// must not run at the same time. Called from TubeModeController.start().
    func stopOverlaysForTube() {
        if isActive { disableAll() }
        if retroViewport.isActive { retroViewport.hide() }
        if VirtualCameraManager.shared.isRunning { VirtualCameraManager.shared.stop() }
    }

    func showOnboarding() {
        welcomeFlow.showSetup()
    }

    /// Opens Settings so the user can enter a license key (from the coffee page).
    func openSettingsForLicense() {
        settingsWindow.show()
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

        // Stop current overlay (full or lite)
        overlayStartTask?.cancel()
        overlayStartTask = nil
        overlayController?.stop()
        overlayController = nil
        crtLiteOverlay?.stop()
        crtLiteOverlay = nil
        isActive = false

        // Restore previous preset
        currentPresetName = preset

        // Restore overlay if it was active before TV
        if wasActive {
            if Self.isLitePreset(preset) {
                startCRTLite(mode: .fullScreen, presetName: preset)
            } else {
                startOverlay(mode: .fullScreen)
            }
        } else {
            updateMenuBarIcon()
            rebuildMenu()
        }
    }

    /// Start shader overlay on a specific window (used by ROMLauncher for emulator windows)
    func startWindowOverlay(window: SCWindow, presetID: String) {
        startOverlay(mode: .singleWindow(window), presetOverride: presetID)
    }

    func applyPreset(_ presetID: String) {
        currentPresetName = presetID

        // Wallpaper-only scope: switch the shader in place on the wallpaper controller.
        if isWallpaperOnlyScope {
            if let wp = wallpaperShaderController, wp.isActive {
                wp.switchPreset(Self.fullPreset(for: presetID))
                wp.loadOverlays()
                let settings = AppSettings.shared
                currentVignetteIntensity = settings.vignetteIntensity
                wp.vignetteIntensity = currentVignetteIntensity
            } else {
                startWallpaperShader(presetID: presetID)
            }
            rebuildMenu()
            return
        }

        // Switching to a Lite preset: need to tear down full overlay and start lite
        if Self.isLitePreset(presetID) {
            overlayController?.stop()
            overlayController = nil
            startCRTLite(mode: .fullScreen, presetName: presetID)
            rebuildMenu()
            return
        }

        // Switching away from Lite to a full preset: tear down lite, start full
        if crtLiteOverlay?.isActive == true {
            crtLiteOverlay?.stop()
            crtLiteOverlay = nil
            isActive = false
            startOverlay(mode: .fullScreen)
            rebuildMenu()
            return
        }

        // Normal full overlay → full overlay switch
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
        // Try the full overlay's captured frame first
        var image: NSImage? = overlayController?.captureScreenshot()

        // Lite overlay: no captured frame — grab the composited screen instead
        if image == nil && crtLiteOverlay?.isActive == true {
            let displayID = CGMainDisplayID()
            if let cgImage = CGDisplayCreateImage(displayID) {
                image = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
            }
        }

        guard let image else {
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

    private func phosphorValueString() -> String {
        let v = AppSettings.shared.phosphorPersistence
        return v <= 0.001 ? "Off" : "\(Int(v * 100))%"
    }

    /// Phosphor afterglow strength. Applied live to every active renderer.
    @objc private func setPhosphorPersistence(_ sender: NSMenuItem) {
        let settings = AppSettings.shared
        settings.phosphorPersistence = Float(sender.tag) / 100.0
        applyPhosphorToRenderers()
        rebuildMenu()
    }

    private func applyPhosphorToRenderers() {
        // Both Metal overlay paths (whole-screen and wallpaper-only). The Lite overlay is
        // deliberately absent: it has no frame history to decay.
        let v = AppSettings.shared.phosphorPersistence
        overlayController?.renderer.phosphorPersistence = v
        wallpaperShaderController?.renderer.phosphorPersistence = v
    }

    // MARK: - Bloom (MPS Glow)

    @objc private func toggleBloom() {
        let settings = AppSettings.shared
        settings.bloomEnabled.toggle()
        applyBloomSettings()
        rebuildMenu()
    }

    @objc private func setBloomIntensity(_ sender: NSMenuItem) {
        let settings = AppSettings.shared
        settings.bloomIntensity = Float(sender.tag) / 100.0
        if !settings.bloomEnabled { settings.bloomEnabled = true }
        applyBloomSettings()
        rebuildMenu()
    }

    private func applyBloomSettings() {
        let settings = AppSettings.shared
        if let renderer = overlayController?.renderer {
            renderer.bloomEnabled = settings.bloomEnabled
            renderer.bloomIntensity = settings.bloomIntensity
            renderer.bloomRadius = settings.bloomRadius
        }
        // Also apply to Lite overlay
        if let lite = crtLiteOverlay, lite.isActive {
            lite.bloomEnabled = settings.bloomEnabled
            lite.bloomIntensity = settings.bloomIntensity
            lite.bloomRadius = settings.bloomRadius
        }
    }

    // MARK: - Retro Viewport

    @objc func toggleViewport() {
        if retroViewport.isActive {
            retroViewport.hide()
        } else {
            // Mutual exclusivity: stop shader and camera first
            if isActive { disableAll() }
            if VirtualCameraManager.shared.isRunning { VirtualCameraManager.shared.stop() }

            let preset = AppSettings.shared.viewportPreset
            retroViewport.show(preset: preset)
        }
        rebuildMenu()
    }

    @objc private func selectViewportPreset(_ sender: NSMenuItem) {
        guard let presetID = sender.representedObject as? String else { return }
        AppSettings.shared.viewportPreset = presetID

        if retroViewport.isActive {
            retroViewport.switchPreset(presetID)
        } else {
            // Open viewport with the selected preset
            retroViewport.show(preset: presetID)
        }
        rebuildMenu()
    }

    // MARK: - Video Recording

    @objc private func toggleRecording() {
        guard let renderer = overlayController?.renderer else { return }

        if let recorder = renderer.recorder, recorder.isRecording {
            // Stop recording
            recorder.stopAndSave()
            renderer.recorder = nil
            rebuildMenu()
        } else {
            // Start recording
            let device = renderer.device
            let recorder = ShaderRecorder(device: device)

            // Get current capture resolution from screen
            let screen = NSScreen.main!
            let scale = screen.backingScaleFactor
            let w = Int(screen.frame.width * scale)
            let h = Int(screen.frame.height * scale)

            do {
                try recorder.startRecording(width: w, height: h)
                renderer.recorder = recorder
                rebuildMenu()
            } catch {
                print("[RetroMac] Recording failed: \(error)")
                let alert = NSAlert()
                alert.messageText = "Recording Failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    @objc private func showThemeReadme() {
        ThemeReadmeController.shared.showForActiveTheme()
    }

    /// The menu-bar status-item icon in screen coordinates (target for the onboarding coach mark).
    var statusButtonScreenRect: NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// Open the GitHub repo (used by the coach mark's "Updates & source" step).
    func openGitHubRepo() {
        if let url = URL(string: "https://github.com/klotzbrocken/RetroMac") { NSWorkspace.shared.open(url) }
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let settings = AppSettings.shared
        ThemeManager.shared.setActiveTheme(name: name, applyWallpaper: !AppSettings.shared.dockOnly)
        // Menu-bar Apple logo is driven by the theme in the .dockThemeChanged handler.
        if !settings.dockEnabled {
            settings.dockEnabled = true
            DockController.shared.start()
        }
        // The menu hands us a DISPLAY name; per-theme settings are keyed by stable id.
        let themeKey = ThemeManager.shared.theme(for: name)?.stableID ?? name
        if settings.themeShaderDisabled[themeKey] == true {
            // Explicit per-theme "off" (user toggled the shader off here, or picked "None"):
            // force the shader off so switching back to this theme restores that choice.
            if isActive { disableAll() }
        } else if let preset = settings.presetForTheme(name: name) {
            if preset == "none" {
                // Theme wants no shader
                if isActive { disableAll() }
            } else if retroViewport.isActive {
                retroViewport.switchPreset(preset)
            } else if isActive {
                applyPreset(preset)
            } else if settings.shaderOnThemeChange && !settings.dockOnly {
                currentPresetName = preset
                startOverlay(mode: .fullScreen)
            } else {
                // Remember the theme's preset but don't auto-activate the shader.
                // Dock-only deliberately skips the full-screen CRT overlay.
                currentPresetName = preset
            }
        }
        applyThemeWidgets(for: name)
        rebuildMenu()
    }

    /// Show or hide the theme's desktop widgets based on the `themeIncludeWidgets`
    /// preference (set in the Setup Assistant). First version = the desktop Clock.
    private func applyThemeWidgets(for themeName: String) {
        // Dock-only deliberately changes nothing but the dock — no desktop widgets.
        if AppSettings.shared.themeIncludeWidgets && !AppSettings.shared.dockOnly
            && !ClockWidgetController.shared.userHidden {   // don't reopen a clock the user closed
            ClockWidgetController.shared.show()
        } else {
            ClockWidgetController.shared.destroy()   // fully release the WebView when widgets are off
        }
    }

    // MARK: - Dock-only policy
    //
    // "Dock only" means a theme restyles ONLY the dock — nothing else on the desktop.
    // It SUPPRESSES: wallpaper, boot splash, the full-screen CRT shader, desktop widgets
    // (e.g. the Clock), and themed desktop icons.
    // EXCEPTION: themes that have no DockView (dockStyle "deskbar"/"none" → `hidesDock`:
    // BeOS, Windows 3.1, SGI IRIX) render their dock AS a desktop overlay (BeOSDeskbar /
    // ProgramManager / SGIDesktop). For those themes that overlay IS the dock, so it is
    // intentionally shown even in dock-only mode (it is the dock, not extra chrome).
    // The decision is enforced at each effect's site; the gates are kept consistent with
    // this policy (selectTheme / applyThemePresetIfNeeded / applyThemeWidgets here,
    // DockController.start + the $dockTheme sink for wallpaper/splash, and the dockOnly
    // guard in DesktopIconsController).

    /// Re-apply the desktop scope when the "Dock only" toggle flips, so it takes
    /// effect immediately on the active theme without a full re-select. Dock-only
    /// keeps only the dock — wallpaper, full-screen shader, widgets and desktop
    /// chrome are removed; turning it off restores them for the active theme.
    func refreshDockOnlyScope() {
        let dockOnly = AppSettings.shared.dockOnly
        if dockOnly {
            ThemeManager.shared.restoreWallpapers()
            if isActive { disableAll() }   // no full-screen CRT overlay in dock-only
        } else if AppSettings.shared.dockEnabled {
            ThemeManager.shared.applyWallpaper()
        }
        DesktopIconsController.shared.update()
        ProgramManagerController.shared.update()
        SGIDesktopController.shared.update()
        BeOSDeskbarController.shared.update()
        NextMenuController.shared.update()
        NextDockController.shared.update()
        NextRunningAppsController.shared.update()
        WindowBorderController.shared.update()
        RainbowAppleController.shared.update()
        applyThemeWidgets(for: AppSettings.shared.dockTheme)
    }

    /// Apply the active theme's shader preset when theme changes (from Settings or menu).
    /// Priority: theme preset > global default. TV overlay state is preserved.
    private func applyThemePresetIfNeeded() {
        let settings = AppSettings.shared
        guard settings.dockEnabled else { return }
        let themeName = settings.dockTheme

        if settings.themeShaderDisabled[themeName] == true {
            // Explicit per-theme "off" (remembered toggle / "None") — force the shader off.
            if isActive { disableAll() }
            rebuildMenu()
            return
        }
        if let preset = settings.presetForTheme(name: themeName) {
            // "none" means no shader for this theme — disable overlay
            if preset == "none" {
                if isActive { disableAll() }
                rebuildMenu()
                return
            }
            // Theme has a shader — apply it
            if retroViewport.isActive {
                retroViewport.switchPreset(preset)
            } else if isActive {
                applyPreset(preset)
            } else if settings.shaderOnThemeChange && !settings.dockOnly {
                currentPresetName = preset
                startOverlay(mode: .fullScreen)
            } else {
                // Dock-only deliberately skips the full-screen CRT overlay.
                currentPresetName = preset
            }
        }
        rebuildMenu()
    }

    /// Public entry point (e.g. Program Manager "Exit Windows") to turn off the active theme.
    func deactivateActiveTheme() { disableTheme() }

    // MARK: - Retro Mode (one-click distraction-free)

    private(set) var retroModeActive = false
    private var retroSavedThemeEnabled = false
    private var retroSavedTheme = ""
    private var retroSavedShaderActive = false
    private var retroSavedPreset = ""
    private var retroHidMenuBar = false
    private var retroHidDock = false
    private var retroHidDesktop = false

    @objc func toggleRetroMode() {
        if retroModeActive { exitRetroMode() } else { enterRetroMode() }
    }

    private func enterRetroMode() {
        let s = AppSettings.shared
        // Snapshot current state for restore
        retroSavedThemeEnabled = s.dockEnabled
        retroSavedTheme = s.dockTheme
        retroSavedShaderActive = isActive
        retroSavedPreset = currentPresetName

        // Favourite theme
        let theme = s.retroModeTheme
        if !theme.isEmpty {
            ThemeManager.shared.setActiveTheme(name: theme)
            s.dockEnabled = true
            DockController.shared.start()
        }
        // Favourite shader
        if s.retroModeActivateShader {
            let preset = !s.retroModeShader.isEmpty ? s.retroModeShader : (s.presetForTheme(name: theme) ?? (currentPresetName ?? ""))
            if !preset.isEmpty && preset != "none" {
                if isActive { applyPreset(preset) } else { currentPresetName = preset; startOverlay(mode: .fullScreen) }
            }
        }
        // Hide system UI — but only what isn't ALREADY hidden by the user's own prefs.
        // Otherwise the exit/crash restore would force menu bar / Dock / desktop icons
        // visible and overwrite a deliberate autohide / hidden-icons choice.
        retroHidMenuBar = s.retroModeHideMenuBar && !SystemUIHelper.isMenuBarAutoHidden()
        retroHidDock = s.retroModeHideDock && !SystemUIHelper.isDockAutoHidden()
        retroHidDesktop = s.retroModeHideDesktopIcons && !SystemUIHelper.areDesktopIconsHidden()
        if retroHidMenuBar { SystemUIHelper.setMenuBarAutoHide(true) }
        if retroHidDock { SystemUIHelper.setDockAutoHide(true) }
        if retroHidDesktop { SystemUIHelper.setDesktopIconsHidden(true) }
        // Persist what we hid so a quit / crash can restore it (the direct
        // setMenuBarAutoHide path is not covered by SystemUIHelper.restoreIfNeeded).
        let d = UserDefaults.standard
        d.set(retroHidMenuBar, forKey: "retroHidMenuBar")
        d.set(retroHidDock, forKey: "retroHidDock")
        d.set(retroHidDesktop, forKey: "retroHidDesktop")

        retroModeActive = true
        rebuildMenu()
    }

    /// Restore any system UI that Retro Mode hid (menu bar / dock / desktop icons),
    /// based on persisted flags. Runs on quit and on launch (crash recovery). No-op
    /// when nothing was hidden, so a normal quit causes no Finder/Dock restart.
    private func restoreRetroModeSystemUI() {
        let d = UserDefaults.standard
        if d.bool(forKey: "retroHidMenuBar") { SystemUIHelper.setMenuBarAutoHide(false) }
        if d.bool(forKey: "retroHidDock") { SystemUIHelper.setDockAutoHide(false) }
        if d.bool(forKey: "retroHidDesktop") { SystemUIHelper.setDesktopIconsHidden(false) }
        d.removeObject(forKey: "retroHidMenuBar")
        d.removeObject(forKey: "retroHidDock")
        d.removeObject(forKey: "retroHidDesktop")
    }

    private func exitRetroMode() {
        // Restore system UI
        if retroHidMenuBar { SystemUIHelper.setMenuBarAutoHide(false) }
        if retroHidDock { SystemUIHelper.setDockAutoHide(false) }
        if retroHidDesktop { SystemUIHelper.setDesktopIconsHidden(false) }
        let d = UserDefaults.standard
        d.removeObject(forKey: "retroHidMenuBar")
        d.removeObject(forKey: "retroHidDock")
        d.removeObject(forKey: "retroHidDesktop")

        let s = AppSettings.shared
        // Restore theme
        if retroSavedThemeEnabled {
            if s.dockTheme != retroSavedTheme { ThemeManager.shared.setActiveTheme(name: retroSavedTheme) }
            s.dockEnabled = true
            DockController.shared.start()
        } else {
            s.dockEnabled = false
            DockController.shared.stop()
            DesktopIconsController.shared.hide()
            ProgramManagerController.shared.hide()
            SGIDesktopController.shared.hide()
            NextMenuController.shared.hide()
            NextDockController.shared.hide()
            NextRunningAppsController.shared.hide()
            ThemeManager.shared.clearActiveTheme()
            ThemeManager.shared.restoreWallpapers()
        }
        // Restore shader
        if retroSavedShaderActive, !retroSavedPreset.isEmpty {
            if isActive { applyPreset(retroSavedPreset) } else { currentPresetName = retroSavedPreset; startOverlay(mode: .fullScreen) }
        } else if isActive {
            disableAll()
        }

        retroModeActive = false
        rebuildMenu()
    }

    @objc private func disableTheme() {
        AppSettings.shared.dockEnabled = false
        AppSettings.shared.menuBarAppleStyle = 0   // menu-bar Apple logo returns to the system one
        DockController.shared.stop()
        DesktopIconsController.shared.hide()
        ProgramManagerController.shared.hide()
        SGIDesktopController.shared.hide()
        NextMenuController.shared.hide()
        NextDockController.shared.hide()
        NextRunningAppsController.shared.hide()
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

    // MARK: - Screenshot with Shader

    @objc private func screenshotMenuAction() {
        captureScreenshotWithShader()
    }

    /// Capture the full screen including the active CRT shader overlay and save to Desktop.
    func captureScreenshotWithShader() {
        guard isActive || retroViewport.isActive else {
            // Flash the menu bar icon to indicate no shader is active
            NSSound.beep()
            print("[Screenshot] No shader active — nothing to capture")
            return
        }

        // Brief delay to let any hotkey UI (key-up flash) settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.performScreenshotCapture()
        }
    }

    private func performScreenshotCapture() {
        // Capture the entire main display including all windows (shader overlay is a window)
        let displayID = CGMainDisplayID()
        guard let cgImage = CGDisplayCreateImage(displayID) else {
            print("[Screenshot] CGDisplayCreateImage failed")
            NSSound.beep()
            return
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
        ))

        // Save to Desktop with timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "RetroMac Screenshot \(timestamp).png"
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let fileURL = desktopURL.appendingPathComponent(filename)

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            print("[Screenshot] Image conversion failed")
            NSSound.beep()
            return
        }

        do {
            try pngData.write(to: fileURL)
            print("[Screenshot] Saved to \(fileURL.path)")

            // Play camera shutter sound
            NSSound(named: "Grab")?.play()

            // Brief white flash on the overlay window for visual feedback
            flashScreenshotFeedback()
        } catch {
            print("[Screenshot] Save failed: \(error)")
            NSSound.beep()
        }
    }

    private func flashScreenshotFeedback() {
        guard let screen = NSScreen.main else { return }
        let flashWindow = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        flashWindow.level = NSWindow.Level(rawValue: 100)
        flashWindow.isOpaque = false
        flashWindow.backgroundColor = NSColor.white.withAlphaComponent(0.4)
        flashWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        flashWindow.ignoresMouseEvents = true
        flashWindow.orderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            flashWindow.orderOut(nil)
        }
    }

    // MARK: - Doom Launcher

    @objc private func launchDoom() {
        // Auto-install GZDoom on demand (same as Raze for Duke Nukem), then retry.
        guard FileManager.default.fileExists(atPath: "/Applications/GZDoom.app") else {
            ensureGZDoom(gameName: "Doom") { [weak self] in self?.launchDoom() }
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
        let crtEnabled = gameSettings.gamesCRTEnabled
        let vhsEnabled = false
        let warpEnabled = gameSettings.gamesCRTEnabled
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

        // NOTE: The RetroMac-CRT.pk3 is deliberately NOT loaded here. It drives its
        // post-process shader from a GZDoom StaticEventHandler/RenderOverlay(RenderEvent)
        // that sets the uniforms each frame — a rendering API Raze's (Build-engine)
        // ZScript VM doesn't implement. Injecting it made Raze abort at script-compile
        // time ("unknown base class StaticEventHandler", "RenderEvent as a type", …), so
        // Duke Nukem 3D / Shadow Warrior wouldn't launch at all. The CRT toggle only
        // applies to the GZDoom-based games (Doom/Freedoom).
        if settings.gamesCRTEnabled {
            print("[\(gameName)] CRT shader skipped — not supported by Raze's Build engine")
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

    /// Same as the menu entry, from the launcher flyout. The flyout has to close first: a crash
    /// screen with a popover still floating over it looks like a bug, not a crash.
    func launcherCrashNow() {
        LauncherController.shared.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.crashNow() }
    }

    @objc private func crashNow() {
        guard LicenseManager.shared.isLicensed else { presentUnlockScreen(); return }
        let hold = CrashScheduler.shared.hold(ignoringSchedule: true)
        guard hold == .ready else {
            let alert = NSAlert()
            alert.messageText = "Not right now"
            alert.informativeText = hold.explanation
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        let countdown = AppSettings.shared.crashMode == "party" ? AppSettings.shared.crashCountdown : 0
        CrashScheduler.shared.fire(source: .manual, countdown: countdown)
    }

    @objc func openGameLibrary() {
        GameLibraryWindowController.shared.show()
    }

    @objc private func launchHeretic() {
        guard FileManager.default.fileExists(atPath: "/Applications/GZDoom.app") else {
            ensureGZDoom(gameName: "Heretic") { [weak self] in self?.launchHeretic() }
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
        let crtEnabled = settings.gamesCRTEnabled
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

    /// Fetch the Heretic shareware WAD.
    ///
    /// `startWhenDone` is what the two callers differ in: launching Heretic without data has
    /// always downloaded and then started the game, which is right there and wrong in the Game
    /// Library, where the press meant "get me the data" and starting a game unasked would be a
    /// surprise. The default keeps the launcher's behaviour.
    private func downloadHereticShareware(startWhenDone: Bool = true,
                                          completion: ((Bool) -> Void)? = nil) {
        let targetDir = AppSettings.shared.doomWadFolder
        let targetWAD = targetDir + "/HERETIC1.WAD"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true, attributes: nil)

        // Never overwrites: a retail HERETIC.WAD and this one live side by side, and a second
        // press must not spend five megabytes to replace a file with itself.
        if fm.fileExists(atPath: targetWAD) {
            if startWhenDone { launchHeretic() }
            completion?(true)
            return
        }

        let progressWindow = createProgressWindow(title: "Downloading Heretic…", detail: "Downloading Heretic Shareware…")

        guard let url = URL(string: "https://archive.org/download/hereticsw/hereticsw.zip") else {
            progressWindow.close(); completion?(false); return
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
                    completion?(false)
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
                    if startWhenDone { self?.launchHeretic() }
                    completion?(true)
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Extraction Failed"
                    alert.informativeText = "HERETIC1.WAD not found in archive."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    completion?(false)
                }
            }
        }.resume()
    }

    /// Fetch the Doom shareware episode.
    ///
    /// The whole 1995 shareware package, `doom.ZIP`, is a plain file in the item rather than a
    /// member to be extracted on the fly, so it arrives with a real Content-Length and one
    /// unzip gets DOOM1.WAD out of it. 2,431,248 bytes in, a 4,196,020-byte IWAD out; both
    /// measured.
    ///
    /// DOOM1.WAD and a retail DOOM.WAD live side by side, and `launchDoomIWAD` sorts its
    /// candidates, so "doom.wad" is still chosen ahead of "doom1.wad" where both are present.
    private func downloadDoomShareware(completion: @escaping (Bool) -> Void) {
        let targetDir = AppSettings.shared.doomWadFolder
        let targetWAD = targetDir + "/DOOM1.WAD"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true, attributes: nil)
        if fm.fileExists(atPath: targetWAD) { completion(true); return }

        let progressWindow = createProgressWindow(title: "Downloading Doom…",
                                                  detail: "Downloading Shareware Episode 1: Knee-Deep in the Dead…")
        guard let url = URL(string: "https://archive.org/download/DoomsharewareEpisode/doom.ZIP") else {
            progressWindow.close(); completion(false); return
        }

        URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            guard let tempURL, error == nil else {
                DispatchQueue.main.async {
                    progressWindow.close()
                    let alert = NSAlert()
                    alert.messageText = "Download Failed"
                    alert.informativeText = error?.localizedDescription ?? "Could not download the Doom shareware episode."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    completion(false)
                }
                return
            }

            let tempDir = NSTemporaryDirectory() + "doom_extract_\(ProcessInfo.processInfo.processIdentifier)"
            try? fm.removeItem(atPath: tempDir)
            try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true, attributes: nil)

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", "-j", tempURL.path, "-d", tempDir]
            unzip.standardOutput = FileHandle.nullDevice
            unzip.standardError = FileHandle.nullDevice
            try? unzip.run()
            unzip.waitUntilExit()

            // The package also carries DOOM.EXE and the order form, so the WAD is picked by name
            // rather than by taking whatever came out first.
            if let contents = try? fm.contentsOfDirectory(atPath: tempDir),
               let wad = contents.first(where: { $0.lowercased() == "doom1.wad" }) {
                try? fm.copyItem(atPath: tempDir + "/" + wad, toPath: targetWAD)
                print("[Doom] Shareware WAD installed to \(targetWAD)")
            }
            try? fm.removeItem(atPath: tempDir)

            DispatchQueue.main.async {
                progressWindow.close()
                if fm.fileExists(atPath: targetWAD) {
                    completion(true)
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Extraction Failed"
                    alert.informativeText = "DOOM1.WAD not found in the archive."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    completion(false)
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

        // Auto-install GZDoom on demand, then retry.
        guard fm.fileExists(atPath: "/Applications/GZDoom.app") else {
            ensureGZDoom(gameName: "Freedoom") { [weak self] in self?.launchFreedoom() }
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
        if settings.gamesCRTEnabled,
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

    // MARK: - Quake Launcher (vkQuake)

    @objc private func launchQuake() {
        let fm = FileManager.default
        let vkQuakePath = "/Applications/vkQuake.app"

        guard fm.fileExists(atPath: vkQuakePath) else {
            ensureEngineApp(named: "vkQuake", gameName: "Quake", size: "~11 MB",
                            source: "github.com/MacSourcePorts/vkQuake",
                            install: installVkQuake) { [weak self] in self?.launchQuake() }
            return
        }

        let settings = AppSettings.shared
        let basePath = settings.quakeBasePath
        let pakPath = basePath + "/id1/PAK0.PAK"

        if fm.fileExists(atPath: pakPath) {
            launchVkQuake(basePath: basePath)
        } else {
            downloadQuakeShareware { [weak self] success in
                if success {
                    self?.launchVkQuake(basePath: basePath)
                }
            }
        }
    }

    private func launchVkQuake(basePath: String) {
        let appURL = URL(fileURLWithPath: "/Applications/vkQuake.app")
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["-basedir", basePath]
        let preset = AppSettings.shared.quakeLitePreset
        print("[Quake] Launching vkQuake with preset=\(preset) basedir=\(basePath)")

        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] app, error in
            if let error = error {
                print("[Quake] Failed to launch vkQuake: \(error)")
                return
            }
            let bundleID = app?.bundleIdentifier ?? "com.macsourceports.vkQuake"
            print("[Quake] Launched vkQuake (bundleID=\(bundleID))")

            guard preset != "none" else {
                print("[Quake] No overlay (preset=none)")
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                print("[Quake] Applying overlay: \(preset) to \(bundleID)")
                self?.applyLiteOverlayToApp(bundleID: bundleID, presetID: preset)
            }
        }
    }

    // MARK: - Quake II Launcher (Yamagi Quake II)

    @objc private func launchQuake2() {
        let fm = FileManager.default
        // `yquake2.app` first: that is what the notarized macOS build is called. Only the two
        // older spellings were checked before, so even a hand-installed engine went unseen.
        let actualPath = InternetArchive.Engine.yquake2.appPaths.first { fm.fileExists(atPath: $0) }

        guard let appPath = actualPath else {
            ensureEngineApp(named: "Yamagi Quake II", gameName: "Quake II", size: "~7 MB",
                            source: "github.com/MacSourcePorts/yquake2",
                            install: installYQuake2) { [weak self] in self?.launchQuake2() }
            return
        }

        let settings = AppSettings.shared
        let basePath = settings.quake2BasePath
        let pakPath = basePath + "/baseq2/pak0.pak"

        if fm.fileExists(atPath: pakPath) {
            launchYamagiQuake2(appPath: appPath, basePath: basePath)
        } else {
            downloadQuake2Demo { [weak self] success in
                if success {
                    self?.launchYamagiQuake2(appPath: appPath, basePath: basePath)
                }
            }
        }
    }

    private func launchYamagiQuake2(appPath: String, basePath: String) {
        let appURL = URL(fileURLWithPath: appPath)
        let config = NSWorkspace.OpenConfiguration()
        // `basePath` was only ever TESTED for baseq2/pak0.pak and never handed to the engine,
        // unlike launchVkQuake. Anything installed outside the engine's own default folder was
        // therefore found by the check and then ignored at launch.
        //
        // The flag is `-datadir`, NOT the `-basedir` vkQuake takes: yquake2 documents `-datadir`
        // as the unicode-safe replacement for the old `+set basedir`, and does not accept a bare
        // `-basedir` at all.
        config.arguments = ["-datadir", basePath]
        let preset = AppSettings.shared.quake2LitePreset
        print("[Quake2] Launching Yamagi Quake II with preset=\(preset) datadir=\(basePath)")

        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] app, error in
            if let error = error {
                print("[Quake2] Failed to launch Yamagi Quake II: \(error)")
                return
            }
            let bundleID = app?.bundleIdentifier ?? "org.yamagi.quake2"
            print("[Quake2] Launched Yamagi Quake II (bundleID=\(bundleID))")

            guard preset != "none" else {
                print("[Quake2] No overlay (preset=none)")
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                print("[Quake2] Applying overlay: \(preset) to \(bundleID)")
                self?.applyLiteOverlayToApp(bundleID: bundleID, presetID: preset)
            }
        }
    }

    /// Apply a Lite overlay to an app by bundle ID (used for Quake engines).
    /// Polls until the app window is found (up to 10 seconds) to avoid the fullscreen fallback.
    private func applyLiteOverlayToApp(bundleID: String, presetID: String, attempt: Int = 0) {
        // Check if the app window is visible yet
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let hasWindow: Bool = {
            guard let pid = apps.first?.processIdentifier,
                  let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
            return windowList.contains { info in
                guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                      ownerPID == pid,
                      let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else { return false }
                var rect = CGRect.zero
                guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect) else { return false }
                return rect.width > 100 && rect.height > 100
            }
        }()

        if !hasWindow && attempt < 10 {
            // Retry in 1 second
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.applyLiteOverlayToApp(bundleID: bundleID, presetID: presetID, attempt: attempt + 1)
            }
            print("[RetroMac] Waiting for \(bundleID) window… (attempt \(attempt + 1))")
            return
        }

        let overlay = CRTLiteOverlay()
        overlay.startForApp(bundleID: bundleID, preset: presetID)
        self.crtLiteOverlay = overlay
        self.isActive = true
        self.currentPresetName = presetID
        updateMenuBarIcon()
        rebuildMenu()
        print("[RetroMac] Applied \(presetID) overlay to \(bundleID)")
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
        // id Software's own FTP tree, mirrored at the GWDG in Göttingen. The `quake-ii-demo`
        // Archive item this used to point at has been taken down — its metadata API returns
        // nothing and the file answers 503 — so this download had stopped working. The mirror
        // serves the original `q2-314-demo-x86.exe`, 39,015,499 bytes, Last-Modified March 1998,
        // and its baseq2/pak0.pak is byte-identical to the one in the official demo installer.
        guard let url = URL(string: "https://ftp.gwdg.de/pub/misc/ftp.idsoftware.com/idstuff/quake2/q2-314-demo-x86.exe") else {
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

    // MARK: - Legacy RetroArch Infrastructure (kept for potential future use)

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
    @discardableResult
    private func runUnzip(_ zipPath: String, into dir: String) -> Bool {
        TrustedDownloadInstaller.unzip(URL(fileURLWithPath: zipPath), into: URL(fileURLWithPath: dir))
    }

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

            let unzipOK = self?.runUnzip(zipPath, into: coresDir) ?? false

            try? fm.removeItem(atPath: tempDir)
            let success = unzipOK && fm.fileExists(atPath: corePath)
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

            let unzipOK = self.runUnzip(zipPath, into: baseShaderDir)

            try? fm.removeItem(atPath: tempDir)
            // Only claim success when the extraction was clean AND the expected shader landed.
            let installed = unzipOK && fm.fileExists(atPath: shadersDir + "/crt-geom.slangp")
            print("[RetroArch] Slang shaders \(installed ? "installed" : "install FAILED")")
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

    /// Download and install Raze.app (Duke Nukem 3D / Shadow Warrior) from GitHub.
    private func installRaze(completion: @escaping (Bool) -> Void) {
        installZDoomApp(repo: "ZDoom/Raze", appName: "Raze", label: "Duke3D", completion: completion)
    }

    /// Download and install GZDoom.app from GitHub — same publisher and macOS packaging
    /// as Raze; Doom, Heretic and Freedoom all run on it.
    private func installGZDoom(completion: @escaping (Bool) -> Void) {
        installZDoomApp(repo: "ZDoom/gzdoom", appName: "GZDoom", label: "Doom", completion: completion)
    }

    /// Download and install vkQuake.app — the MacSourcePorts build, which is what the launcher
    /// has always expected (`com.macsourceports.vkQuake`). Novum/vkQuake itself ships no macOS
    /// binary, so the old "open the releases page" dialog sent people somewhere with nothing to
    /// download for their machine.
    private func installVkQuake(completion: @escaping (Bool) -> Void) {
        installReleaseApp(repo: "MacSourcePorts/vkQuake", appName: "vkQuake", label: "Quake",
                          expectedBundleID: "com.macsourceports.vkQuake", completion: completion)
    }

    /// Download and install yquake2.app (Yamagi Quake II), same publisher as vkQuake.
    private func installYQuake2(completion: @escaping (Bool) -> Void) {
        installReleaseApp(repo: "MacSourcePorts/yquake2", appName: "yquake2", label: "Quake2",
                          expectedBundleID: "com.macsourceports.yquake2", completion: completion)
    }

    /// Generic installer for a ZDoom-family macOS app (Raze / GZDoom): fetch the latest
    /// GitHub release, pick the macOS .dmg/.zip asset, and install <appName>.app to
    /// /Applications. `label` is only a log prefix.
    private func installZDoomApp(repo: String, appName: String, label: String,
                                 completion: @escaping (Bool) -> Void) {
        // ZDoom names its assets "…macos…"; MacSourcePorts just names them after the app.
        installReleaseApp(repo: repo, appName: appName, label: label,
                          matches: { $0.contains("macos") && ($0.hasSuffix(".dmg") || $0.hasSuffix(".zip")) },
                          completion: completion)
    }

    /// Fetch the latest GitHub release of `repo`, pick a macOS asset and install <appName>.app
    /// into /Applications. `expectedBundleID` is enforced where the signed identity is known.
    private func installReleaseApp(repo: String, appName: String, label: String,
                                   matches: @escaping (String) -> Bool = { $0.hasSuffix(".dmg") || $0.hasSuffix(".zip") },
                                   expectedBundleID: String? = nil,
                                   completion: @escaping (Bool) -> Void) {
        let progressWindow = createProgressWindow(title: "Installing \(appName)…", detail: "Fetching latest release from GitHub…")

        TrustedDownloadInstaller.latestReleaseAsset(repo: repo, matches: matches) { [weak self] result in
            switch result {
            case .failure(.fetchFailed(let message)):
                DispatchQueue.main.async {
                    progressWindow.close()
                    let alert = NSAlert()
                    alert.messageText = "Download Failed"
                    alert.informativeText = "Could not fetch \(appName) release info from GitHub.\n\(message ?? "")"
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    completion(false)
                }
            case .failure(.noMatchingAsset(let version)):
                DispatchQueue.main.async {
                    progressWindow.close()
                    let alert = NSAlert()
                    alert.messageText = "No macOS Build Found"
                    alert.informativeText = "The latest \(appName) release (\(version)) does not include a macOS build.\nPlease install \(appName) manually from:\nhttps://github.com/\(repo)/releases"
                    alert.addButton(withTitle: "Open GitHub")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: "https://github.com/\(repo)/releases") {
                        NSWorkspace.shared.open(url)
                    }
                    completion(false)
                }
            case .success(let asset):
                let isDMG = asset.name.lowercased().hasSuffix(".dmg")
                print("[\(label)] Downloading \(appName) \(asset.version): \(asset.name)")
                DispatchQueue.main.async {
                    self?.updateProgressWindow(progressWindow, detail: "Downloading \(appName) \(asset.version) (\(asset.name))…")
                }
                URLSession.shared.downloadTask(with: asset.url) { tempURL, _, dlError in
                    guard let tempURL = tempURL, dlError == nil else {
                        DispatchQueue.main.async {
                            progressWindow.close()
                            let alert = NSAlert()
                            alert.messageText = "Download Failed"
                            alert.informativeText = dlError?.localizedDescription ?? "\(appName) download failed."
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                            completion(false)
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        self?.updateProgressWindow(progressWindow, detail: "Installing \(appName) to /Applications…")
                    }
                    let fm = FileManager.default
                    let tempDir = NSTemporaryDirectory() + "\(appName.lowercased())_install_\(ProcessInfo.processInfo.processIdentifier)"
                    try? fm.removeItem(atPath: tempDir)
                    try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true, attributes: nil)
                    let finish: (Bool) -> Void = { success in
                        try? fm.removeItem(atPath: tempDir)
                        DispatchQueue.main.async { progressWindow.close(); completion(success) }
                    }
                    if isDMG {
                        self?.installAppFromDMG(dmgPath: tempURL.path, tempDir: tempDir, appName: appName,
                                                label: label, expectedBundleID: expectedBundleID, completion: finish)
                    } else {
                        self?.installAppFromZip(zipPath: tempURL.path, tempDir: tempDir, appName: appName,
                                                label: label, expectedBundleID: expectedBundleID, completion: finish)
                    }
                }.resume()
            }
        }
    }

    /// Ask once, then install the engine and carry on into the game. The Quake engines used to
    /// stop here with a link to a web page, which for vkQuake did not even offer a macOS build.
    private func ensureEngineApp(named engineName: String, gameName: String, size: String,
                                 source: String,
                                 install: (@escaping (Bool) -> Void) -> Void,
                                 launch: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "\(engineName) Required"
        alert.informativeText = "\(gameName) runs on \(engineName), which isn't installed yet.\n\nDownload and install it now? (\(size) from \(source))"
        alert.addButton(withTitle: "Install \(engineName)")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        install { success in
            if success { launch() }
        }
    }

    /// Install whatever a Game Library title needs, if it is missing. The gallery calls this so
    /// engine and game data arrive in one go instead of the data landing next to a dead end.
    func ensureEngine(_ engine: InternetArchive.Engine, completion: @escaping (Bool) -> Void) {
        // Always back on the main queue: the installers finish on a URLSession thread, and the
        // gallery updates SwiftUI state in here.
        let done: (Bool) -> Void = { ok in
            if Thread.isMainThread { completion(ok) } else { DispatchQueue.main.async { completion(ok) } }
        }
        guard !engine.isInstalled else { done(true); return }
        switch engine {
        case .gzdoom:  installGZDoom(completion: done)
        case .raze:    installRaze(completion: done)
        case .vkQuake: installVkQuake(completion: done)
        case .yquake2: installYQuake2(completion: done)
        case .bundled: done(false)   // ships with RetroMac; nothing to fetch
        }
    }

    /// Fetch data that does not come out of the Internet Archive catalogue: Freedoom from its own
    /// GitHub release, and the publishers' shareware and demo episodes.
    ///
    /// Every one of these already had a downloader here — they are what happens today when you
    /// start Heretic or Quake with no data at all. Nothing new is downloaded from anywhere; the
    /// Game Library simply gets a way to reach them before the game is started rather than as a
    /// surprise in the middle of launching it.
    ///
    /// Each of them also refuses to overwrite data that is already in place, which is what makes
    /// it safe to offer the shareware Duke GRP and Quake pak beside the retail ones: they carry
    /// the same filenames.
    func fetchBuiltInGame(_ kind: InternetArchive.BuiltIn, completion: @escaping (Bool) -> Void) {
        let done: (Bool) -> Void = { ok in
            if Thread.isMainThread { completion(ok) } else { DispatchQueue.main.async { completion(ok) } }
        }
        switch kind {
        case .freedoom:          downloadFreedoom(completion: done)
        case .shadowWarrior:     downloadSWShareware { done($0 != nil) }
        case .doomShareware:     downloadDoomShareware(completion: done)
        case .hereticShareware:  downloadHereticShareware(startWhenDone: false) { done($0) }
        case .duke3dShareware:   downloadDuke3DShareware { done($0 != nil) }
        case .quakeShareware:    downloadQuakeShareware(completion: done)
        case .quake2Demo:        downloadQuake2Demo(completion: done)
        }
    }

    /// Start a Game Library title, using the same launchers the menu and desktop icons use.
    func launchGame(id: String) {
        switch id {
        case "doom":      launchDoom1()
        case "doom2":     launchDoom2()
        case "heretic":   launchHeretic()
        case "duke3d":    launchDuke3D()
        case "quake":     launchQuake()
        case "quake2":    launchQuake2()
        case "freedoom":  launchFreedoom()
        case "shadowwarrior": launchShadowWarrior()
        case "warcraft1": WarcraftGame.launch(.warcraft1)
        case "warcraft2": WarcraftGame.launch(.warcraft2)
        default:          break
        }
    }

    /// Doom and Doom II are separate games sharing one WAD folder, so the Library needs to start
    /// one specific IWAD. `launchDoom` picks the "best" WAD it can find, which is Doom II when
    /// both are installed — right for a single menu entry, wrong for two cards.
    @objc private func launchDoom1() { launchDoomIWAD(id: "doom", gameName: "Doom") }
    @objc private func launchDoom2() { launchDoomIWAD(id: "doom2", gameName: "Doom II") }

    private func launchDoomIWAD(id: String, gameName: String) {
        guard FileManager.default.fileExists(atPath: "/Applications/GZDoom.app") else {
            ensureGZDoom(gameName: gameName) { [weak self] in self?.launchDoomIWAD(id: id, gameName: gameName) }
            return
        }
        guard let t = InternetArchive.title(id: id),
              let wad = InternetArchive.installedFiles(t).first else {
            launchDoom()   // nothing specific found: fall back to the old broad search
            return
        }
        launchGZDoomGame(wadPath: wad.path, gameName: gameName)
    }

    /// Ensure GZDoom is installed, offering a one-click auto-download (like Raze) if not,
    /// then run `launch`. Used by every GZDoom-based game so none require a manual install.
    private func ensureGZDoom(gameName: String, launch: @escaping () -> Void) {
        if FileManager.default.fileExists(atPath: "/Applications/GZDoom.app") {
            launch()
            return
        }
        let alert = NSAlert()
        alert.messageText = "GZDoom Required"
        alert.informativeText = "\(gameName) runs on GZDoom, which isn't installed yet.\n\nDownload and install the latest GZDoom now? (~40 MB from github.com/ZDoom/gzdoom)"
        alert.addButton(withTitle: "Install GZDoom")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        installGZDoom { success in
            if success { launch() }
        }
    }

    /// Extract <appName>.app from a ZIP and install to /Applications
    private func installAppFromZip(zipPath: String, tempDir: String, appName: String, label: String,
                                   expectedBundleID: String? = nil, completion: @escaping (Bool) -> Void) {
        guard runUnzip(zipPath, into: tempDir) else {
            print("[\(label)] Unzip failed (non-zero exit)")
            completion(false)
            return
        }

        // Find <appName>.app recursively
        guard let appPath = findAppBundle(named: appName, in: tempDir) else {
            print("[\(label)] \(appName).app not found in ZIP")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Installation Failed"
                alert.informativeText = "\(appName).app was not found in the downloaded archive."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            completion(false)
            return
        }

        copyAppToApplications(appPath: appPath, targetName: "\(appName).app",
                              expectedBundleID: expectedBundleID, completion: completion)
    }

    /// Mount a DMG, find <appName>.app, copy it out, install to /Applications.
    private func installAppFromDMG(dmgPath: String, tempDir: String, appName: String, label: String,
                                   expectedBundleID: String? = nil, completion: @escaping (Bool) -> Void) {
        // Copy the app OUT of the read-only volume before it is detached.
        let localApp: URL? = TrustedDownloadInstaller.withMountedDMG(URL(fileURLWithPath: dmgPath)) { mount in
            guard let app = TrustedDownloadInstaller.findAppBundle(named: appName, in: mount) else { return nil }
            let localCopy = URL(fileURLWithPath: tempDir).appendingPathComponent("\(appName).app")
            try? FileManager.default.removeItem(at: localCopy)
            try? FileManager.default.copyItem(at: app, to: localCopy)
            return localCopy
        } ?? nil

        guard let app = localApp else {
            print("[\(label)] \(appName).app not found in DMG (or mount failed)")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Installation Failed"
                alert.informativeText = "\(appName).app was not found in the downloaded DMG."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            completion(false)
            return
        }
        copyAppToApplications(appPath: app.path, targetName: "\(appName).app",
                              expectedBundleID: expectedBundleID, completion: completion)
    }

    private func findAppBundle(named name: String, in directory: String) -> String? {
        TrustedDownloadInstaller.findAppBundle(named: name, in: URL(fileURLWithPath: directory))?.path
    }

    /// Verify + install a downloaded .app to /Applications via the shared TrustedDownloadInstaller.
    /// The warn-but-allow prompt and failure alert (UI) live here; the security policy lives in the layer.
    /// Install a downloaded `.app` to /Applications. `expectedBundleID` enforces a per-download
    /// identity allowlist (rejects a different notarized app from a compromised endpoint). It is
    /// nil for RetroArch / Raze / GZDoom until their real bundle IDs are captured from the signed
    /// binaries (`codesign -dv --verbose=4`) — a wrong guess would hard-fail a legit install. The
    /// emulator path already enforces this (bundle IDs live in EmulatorInfo).
    private func copyAppToApplications(appPath: String, targetName: String,
                                       expectedBundleID: String? = nil,
                                       completion: @escaping (Bool) -> Void) {
        let result = TrustedDownloadInstaller.installVerifiedApp(
            bundleAt: URL(fileURLWithPath: appPath),
            to: URL(fileURLWithPath: "/Applications/" + targetName),
            expectedBundleID: expectedBundleID,
            confirmUnverified: { InstallProgressWindow.confirmUnverified(name: targetName) })
        switch result {
        case .installed: completion(true)
        case .cancelled: completion(false)
        case .failed(let message):
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Installation Failed"
                alert.informativeText = "Could not install \(targetName): \(message)"
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
        InstallProgressWindow.make(title: title, detail: detail)
    }

    private func updateProgressWindow(_ window: NSWindow, detail: String) {
        InstallProgressWindow.update(window, detail: detail)
    }


    // MARK: - Retro ROM Launcher

    @objc private func launchRetroGame(_ sender: NSMenuItem) {
        guard let romID = sender.representedObject as? UUID,
              let rom = ROMLibrary.shared.entries.first(where: { $0.id == romID }) else {
            return
        }
        ROMLauncher.shared.launch(rom)
    }

    // MARK: - Virtual Camera

    @objc private func toggleThemeWindowBorders() {
        // Prototype toggle: theme-coloured border around the focused window of every app.
        // AppSettings.didSet drives WindowBorderController.update(); flip the flag here.
        AppSettings.shared.themeWindowBorders.toggle()
    }

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
            // Mutual exclusivity: stop shader and viewport first
            if isActive { disableAll() }
            if retroViewport.isActive { retroViewport.hide() }

            vcam.start()
        }
        rebuildMenu()
    }

    private func showVirtualCameraLockedAlert() {
        // Unified unlock screen (with inline key entry + buy/unlock), same as locked presets.
        welcomeFlow.showCoffee()
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
        // First, before anything else can take time: never leave a simulated crash on screen.
        CrashDirector.shared.teardown(.appQuit)
        let nc = NSWorkspace.shared.notificationCenter
        for obs in [appLaunchObserver, appTerminateObserver, sleepObserver, lockObserver, wakeObserver].compactMap({ $0 }) {
            nc.removeObserver(obs)
        }
        for obs in [tvBookmarkObserver, tvTubeObserver, tubeStateObserver, dockThemeObserver, dockModeObserver, cameraStateObserver, viewportCloseObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(obs)
        }
        disableAll()
        ScreensaverController.shared.endIdleWatch()
        DockController.shared.stop(synchronous: true)   // must finish before the process exits
        SystemTweaksAdapter.restore(sync: true)         // ditto — revert Classic Finder tweaks before exit
        ThemeManager.shared.restoreWallpapers()
        restoreRetroModeSystemUI()
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
        // Show the unified coffee / unlock screen (with inline key entry) instead of the old alert.
        welcomeFlow.showCoffee()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}
