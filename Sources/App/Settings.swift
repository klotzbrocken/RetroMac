import Foundation
import ServiceManagement
import Carbon.HIToolbox

struct TVBookmark: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var url: String
    var presetID: String?  // nil = no preset ("None")
}

/// Performance profile presets that bundle resolution, fps, and overlay settings
enum PerformanceProfile: String, CaseIterable, Identifiable {
    case high = "high"
    case balanced = "balanced"
    case low = "low"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .high: return "High"
        case .balanced: return "Balanced"
        case .low: return "Low"
        }
    }

    var description: String {
        switch self {
        case .high: return "Retina 2×, 30 fps, all overlays"
        case .balanced: return "1× resolution, 30 fps, all overlays"
        case .low: return "1× resolution, 24 fps, no overlays"
        }
    }

    var icon: String {
        switch self {
        case .high: return "hare"
        case .balanced: return "gauge.with.dots.needle.50percent"
        case .low: return "tortoise"
        }
    }

    var halfResolution: Bool {
        switch self {
        case .high: return false
        case .balanced, .low: return true
        }
    }

    var lowLatencyMode: Bool { false }  // 60fps only via manual override

    var targetFPS: Int {
        switch self {
        case .high, .balanced: return 30
        case .low: return 24
        }
    }

    var disableOverlays: Bool {
        switch self {
        case .high, .balanced: return false
        case .low: return true
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let presetsDir: URL

    @Published var defaultPreset: String {
        didSet { defaults.set(defaultPreset, forKey: "defaultPreset") }
    }
    @Published var defaultIntensity: Float {
        didSet { defaults.set(defaultIntensity, forKey: "defaultIntensity") }
    }
    @Published var vignetteIntensity: Float {
        didSet { defaults.set(vignetteIntensity, forKey: "vignetteIntensity") }
    }
    @Published var hideSystemUI: Bool {
        didSet { defaults.set(hideSystemUI, forKey: "hideSystemUI") }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            updateLoginItem()
        }
    }
    @Published var enableOnLaunch: Bool {
        didSet { defaults.set(enableOnLaunch, forKey: "enableOnLaunch") }
    }
    @Published var hotkeyCode: UInt32 {
        didSet { defaults.set(hotkeyCode, forKey: "hotkeyCode") }
    }
    @Published var hotkeyModifiers: UInt32 {
        didSet { defaults.set(hotkeyModifiers, forKey: "hotkeyModifiers") }
    }
    @Published var targetDisplayID: CGDirectDisplayID {
        didSet { defaults.set(targetDisplayID, forKey: "targetDisplayID") }
    }
    @Published var performanceProfile: PerformanceProfile {
        didSet {
            defaults.set(performanceProfile.rawValue, forKey: "performanceProfile")
            applyPerformanceProfile()
        }
    }
    @Published var lowLatencyMode: Bool {
        didSet { defaults.set(lowLatencyMode, forKey: "lowLatencyMode") }
    }
    @Published var halfResolution: Bool {
        didSet { defaults.set(halfResolution, forKey: "halfResolution") }
    }
    @Published var targetFPS: Int {
        didSet { defaults.set(targetFPS, forKey: "targetFPS") }
    }
    @Published var stopOnSleep: Bool {
        didSet { defaults.set(stopOnSleep, forKey: "stopOnSleep") }
    }
    @Published var resumeAfterSleep: Bool {
        didSet { defaults.set(resumeAfterSleep, forKey: "resumeAfterSleep") }
    }
    @Published var resetOnWake: Bool {
        didSet { defaults.set(resetOnWake, forKey: "resetOnWake") }
    }
    @Published var perAppPresets: [String: String] {
        didSet { defaults.set(perAppPresets, forKey: "perAppPresets") }
    }
    @Published var scanlineOverlayName: String {
        didSet { defaults.set(scanlineOverlayName, forKey: "scanlineOverlayName") }
    }
    @Published var scanlineOverlayIntensity: Float {
        didSet { defaults.set(scanlineOverlayIntensity, forKey: "scanlineOverlayIntensity") }
    }
    @Published var reflectionName: String {
        didSet { defaults.set(reflectionName, forKey: "reflectionName") }
    }
    @Published var reflectionIntensity: Float {
        didSet { defaults.set(reflectionIntensity, forKey: "reflectionIntensity") }
    }

    // Onboarding / Features
    @Published var onboardingComplete: Bool {
        didSet { defaults.set(onboardingComplete, forKey: "onboardingComplete") }
    }
    @Published var lastSeenVersion: String {
        didSet { defaults.set(lastSeenVersion, forKey: "lastSeenVersion") }
    }
    /// When the user last ticked "I already bought a coffee" — suppresses the coffee page for 30 days.
    @Published var coffeeAckDate: Date? {
        didSet { defaults.set(coffeeAckDate, forKey: "coffeeAckDate") }
    }

    /// Dock Mode: show a Dock icon (theme-aware) with a launcher popover. When off, the app
    /// stays a menu-bar-only accessory. Posts `.dockModeChanged` so AppDelegate applies it.
    @Published var dockModeEnabled: Bool {
        didSet {
            defaults.set(dockModeEnabled, forKey: "dockModeEnabled")
            NotificationCenter.default.post(name: .dockModeChanged, object: nil)
        }
    }

    /// When a theme is selected, automatically turn on its CRT shader (if it defines one).
    @Published var shaderOnThemeChange: Bool {
        didSet { defaults.set(shaderOnThemeChange, forKey: "shaderOnThemeChange") }
    }
    /// When a theme is selected, also show its desktop widgets (currently the Clock); when
    /// off, themes only apply dock & wallpaper.
    @Published var themeIncludeWidgets: Bool {
        didSet { defaults.set(themeIncludeWidgets, forKey: "themeIncludeWidgets") }
    }
    /// Set once the post-install Setup Assistant has been completed/dismissed.
    @Published var setupWizardComplete: Bool {
        didSet { defaults.set(setupWizardComplete, forKey: "setupWizardComplete") }
    }
    /// Show the floating, draggable launcher button (bottom-right by default).
    @Published var floatingLauncherEnabled: Bool {
        didSet {
            defaults.set(floatingLauncherEnabled, forKey: "floatingLauncherEnabled")
            FloatingLauncherButton.shared.setEnabled(floatingLauncherEnabled)
        }
    }
    /// Quick-access flyout: up to 8 ordered theme names ("" = empty slot).
    @Published var quickAccessSlots: [String] {
        didSet { defaults.set(quickAccessSlots, forKey: "quickAccessSlots") }
    }
    /// Quick-access flyout: when on, activating a theme restyles only the Dock (no wallpaper).
    @Published var dockOnly: Bool {
        didSet { defaults.set(dockOnly, forKey: "dockOnly") }
    }

    // Retro Mode (one-click distraction-free favourite)
    @Published var retroModeTheme: String {
        didSet { defaults.set(retroModeTheme, forKey: "retroModeTheme") }
    }
    @Published var retroModeShader: String {
        didSet { defaults.set(retroModeShader, forKey: "retroModeShader") }
    }
    @Published var retroModeHideDock: Bool {
        didSet { defaults.set(retroModeHideDock, forKey: "retroModeHideDock") }
    }
    @Published var retroModeHideMenuBar: Bool {
        didSet { defaults.set(retroModeHideMenuBar, forKey: "retroModeHideMenuBar") }
    }
    @Published var retroModeHideDesktopIcons: Bool {
        didSet { defaults.set(retroModeHideDesktopIcons, forKey: "retroModeHideDesktopIcons") }
    }
    @Published var retroModeActivateShader: Bool {
        didSet { defaults.set(retroModeActivateShader, forKey: "retroModeActivateShader") }
    }
    /// "Maiks Favourite" dock: animate the Pac-Man around the pellet border.
    @Published var pacmanAnimationEnabled: Bool {
        didSet {
            defaults.set(pacmanAnimationEnabled, forKey: "pacmanAnimationEnabled")
            NotificationCenter.default.post(name: .pacmanAnimationChanged, object: nil)
        }
    }
    /// Desktop pet (Windows XP / 98 themes) — a small sprite that wanders the desktop.
    @Published var desktopPetEnabled: Bool {
        didSet {
            defaults.set(desktopPetEnabled, forKey: "desktopPetEnabled")
            DesktopPetController.shared.applyForCurrentTheme()
        }
    }
    /// Clock mode: dots become 24 hour numbers around the dock; Pac-Man is the hand
    /// (steps every 15 min). Only applies when the animation is enabled.
    @Published var pacmanClockMode: Bool {
        didSet {
            defaults.set(pacmanClockMode, forKey: "pacmanClockMode")
            NotificationCenter.default.post(name: .pacmanAnimationChanged, object: nil)
        }
    }

    @Published var classicMacModeActive: Bool {
        didSet { defaults.set(classicMacModeActive, forKey: "classicMacModeActive") }
    }

    // Doom Slayer (theme "Maiks Favourite II", dock.borderStyle == "doomslayer").
    /// The one knob normally touched — slayer scale.
    @Published var slayerScale: Double {
        didSet { defaults.set(slayerScale, forKey: "slayerScale") }
    }
    @Published var slayerRunSpeed: Double {
        didSet { defaults.set(slayerRunSpeed, forKey: "slayerRunSpeed") }
    }
    /// "Calm" | "Normal" | "Intense" — controls firing & frag frequency.
    @Published var slayerCombat: String {
        didSet { defaults.set(slayerCombat, forKey: "slayerCombat") }
    }
    /// "Auto-cycle" | "Shotgun" | "Chaingun" | "Rocket" | "Plasma".
    @Published var slayerWeapon: String {
        didSet { defaults.set(slayerWeapon, forKey: "slayerWeapon") }
    }
    /// "Right" | "Left" — travel + facing direction.
    @Published var slayerDirection: String {
        didSet { defaults.set(slayerDirection, forKey: "slayerDirection") }
    }
    /// Launch target for the DOOM logo dock tile: an app path (/Applications/…​.app) or a
    /// bundle identifier. Empty = auto-detect an installed DOOM app.
    @Published var doomLaunchTarget: String {
        didSet { defaults.set(doomLaunchTarget, forKey: "doomLaunchTarget") }
    }
    /// Show the dock / deskbar clock in 24-hour (military) time instead of 12-hour AM/PM.
    @Published var clockUse24Hour: Bool {
        didSet {
            defaults.set(clockUse24Hour, forKey: "clockUse24Hour")
            NotificationCenter.default.post(name: .clockFormatChanged, object: nil)
        }
    }
    /// Convert a 12-hour DateFormatter pattern to 24-hour when `clockUse24Hour` is on.
    /// e.g. "h:mm a" → "H:mm", "hh:mm:ss a" → "HH:mm:ss"; already-24h patterns are unchanged.
    static func applyClockFormat(_ base: String) -> String {
        guard shared.clockUse24Hour else { return base }
        var f = base.replacingOccurrences(of: "a", with: "")
        f = f.replacingOccurrences(of: "h", with: "H")
        return f.trimmingCharacters(in: .whitespaces)
    }

    // Television Bookmarks
    @Published var tvBookmarks: [TVBookmark] {
        didSet {
            if let data = try? JSONEncoder().encode(tvBookmarks) {
                defaults.set(data, forKey: "tvBookmarks")
            }
        }
    }

    // Per-theme preset overrides (theme name → preset ID, empty = "None")
    @Published var themePresetOverrides: [String: String] {
        didSet { defaults.set(themePresetOverrides, forKey: "themePresetOverrides") }
    }

    // Per-theme orientation overrides (theme name → "vertical" or "horizontal")
    @Published var themeOrientationOverrides: [String: String] {
        didSet { defaults.set(themeOrientationOverrides, forKey: "themeOrientationOverrides") }
    }
    /// Per-theme dock edge override: "top" / "bottom" / "left" / "right".
    @Published var themeDockPositionOverride: [String: String] {
        didSet { defaults.set(themeDockPositionOverride, forKey: "themeDockPositionOverride") }
    }
    /// Per-theme dock auto-hide enable (only for themes whose original had auto-hide).
    @Published var themeDockAutoHide: [String: Bool] {
        didSet { defaults.set(themeDockAutoHide, forKey: "themeDockAutoHide") }
    }

    // Per-theme wallpaper overrides (theme name → wallpaper filename)
    @Published var themeWallpaperOverrides: [String: String] {
        didSet { defaults.set(themeWallpaperOverrides, forKey: "themeWallpaperOverrides") }
    }
    /// Per-theme custom wallpaper picked via "Browse…" — absolute file path outside the bundle.
    @Published var themeCustomWallpaper: [String: String] {
        didSet { defaults.set(themeCustomWallpaper, forKey: "themeCustomWallpaper") }
    }

    // Re:Amp integration (Win98/XP themes)
    @Published var reampEnabled: Bool {
        didSet { defaults.set(reampEnabled, forKey: "reampEnabled") }
    }

    // Dock
    @Published var dockEnabled: Bool {
        didSet { defaults.set(dockEnabled, forKey: "dockEnabled") }
    }
    @Published var dockHideSystemDock: Bool {
        didSet { defaults.set(dockHideSystemDock, forKey: "dockHideSystemDock") }
    }
    @Published var hideMenuBar: Bool {
        didSet {
            defaults.set(hideMenuBar, forKey: "hideMenuBar")
            SystemUIHelper.setMenuBarAutoHide(hideMenuBar)
            RainbowAppleController.shared.update()   // apple cover depends on menu-bar visibility
        }
    }
    /// Menu-bar Apple cover style: 0 = off, 1 = rainbow, 2 = aqua blue.
    @Published var menuBarAppleStyle: Int {
        didSet {
            defaults.set(menuBarAppleStyle, forKey: "menuBarAppleStyle")
            RainbowAppleController.shared.update()
        }
    }
    @Published var hideDesktopIcons: Bool {
        didSet {
            defaults.set(hideDesktopIcons, forKey: "hideDesktopIcons")
            SystemUIHelper.setDesktopIconsHidden(hideDesktopIcons)
        }
    }
    @Published var dockHotkeyCode: UInt32 {
        didSet { defaults.set(dockHotkeyCode, forKey: "dockHotkeyCode") }
    }
    @Published var dockHotkeyModifiers: UInt32 {
        didSet { defaults.set(dockHotkeyModifiers, forKey: "dockHotkeyModifiers") }
    }
    @Published var dockTransparency: Float {
        didSet { defaults.set(dockTransparency, forKey: "dockTransparency") }
    }
    @Published var dockTheme: String {
        didSet { defaults.set(dockTheme, forKey: "dockTheme") }
    }
    @Published var dockShowRunningApps: Bool {
        didSet { defaults.set(dockShowRunningApps, forKey: "dockShowRunningApps") }
    }
    /// BeOS Classic Deskbar corner: "bottomLeft" / "bottomRight" / "topLeft" / "topRight".
    @Published var deskbarCorner: String {
        didSet {
            defaults.set(deskbarCorner, forKey: "deskbarCorner")
            NotificationCenter.default.post(name: .deskbarSettingsChanged, object: nil)
        }
    }
    /// Maiks Favourite: show the Downloads folder (with file fan) in the dock.
    @Published var dockShowDownloads: Bool {
        didSet {
            defaults.set(dockShowDownloads, forKey: "dockShowDownloads")
            NotificationCenter.default.post(name: .deskbarSettingsChanged, object: nil)
        }
    }
    /// BeOS Deskbar quick-launch shortcuts (bundle IDs) shown above the status view.
    @Published var deskbarShortcuts: [String] {
        didSet {
            defaults.set(deskbarShortcuts, forKey: "deskbarShortcuts")
            NotificationCenter.default.post(name: .deskbarSettingsChanged, object: nil)
        }
    }
    @Published var dockIconScale: Float {
        didSet { defaults.set(dockIconScale, forKey: "dockIconScale") }
    }
    @Published var dockTargetDisplayID: CGDirectDisplayID {
        didSet { defaults.set(dockTargetDisplayID, forKey: "dockTargetDisplayID") }
    }
    @Published var dockMagnification: Bool {
        didSet { defaults.set(dockMagnification, forKey: "dockMagnification") }
    }
    @Published var dockAutoHide: Bool {
        didSet { defaults.set(dockAutoHide, forKey: "dockAutoHide") }
    }
    @Published var dockFix: Bool {
        didSet { defaults.set(dockFix, forKey: "dockFix") }
    }
    @Published var applySystemIcons: Bool {
        didSet { defaults.set(applySystemIcons, forKey: "applySystemIcons") }
    }

    // Virtual Camera — capture source. Empty = automatic (first physical camera).
    // Holds an AVCaptureDevice.uniqueID so a specific camera (e.g. iPhone
    // Continuity Camera) can be pinned even when other webcams are attached.
    @Published var cameraSourceID: String {
        didSet { defaults.set(cameraSourceID, forKey: "cameraSourceID") }
    }

    // Virtual Camera — Lower Third
    @Published var lowerThirdEnabled: Bool {
        didSet { defaults.set(lowerThirdEnabled, forKey: "lowerThirdEnabled") }
    }
    @Published var lowerThirdName: String {
        didSet { defaults.set(lowerThirdName, forKey: "lowerThirdName") }
    }
    @Published var lowerThirdTitle: String {
        didSet { defaults.set(lowerThirdTitle, forKey: "lowerThirdTitle") }
    }
    @Published var lowerThirdStyle: String {
        didSet { defaults.set(lowerThirdStyle, forKey: "lowerThirdStyle") }
    }

    // Games — Doom
    @Published var doomWadFolder: String {
        didSet { defaults.set(doomWadFolder, forKey: "doomWadFolder") }
    }
    /// Single global switch for the CRT look across all bundled PC games (replaces the old
    /// per-game CRT/VHS/Warp toggles). Drives the GZDoom/Raze SH_CRTEnable shader pass.
    @Published var gamesCRTEnabled: Bool {
        didSet { defaults.set(gamesCRTEnabled, forKey: "gamesCRTEnabled") }
    }
    @Published var doomWindowWidth: Int {
        didSet { defaults.set(doomWindowWidth, forKey: "doomWindowWidth") }
    }
    @Published var doomWindowHeight: Int {
        didSet { defaults.set(doomWindowHeight, forKey: "doomWindowHeight") }
    }

    // Games — Duke Nukem 3D (Raze)
    @Published var razeGrpFolder: String {
        didSet { defaults.set(razeGrpFolder, forKey: "razeGrpFolder") }
    }
    @Published var razeWindowWidth: Int {
        didSet { defaults.set(razeWindowWidth, forKey: "razeWindowWidth") }
    }
    @Published var razeWindowHeight: Int {
        didSet { defaults.set(razeWindowHeight, forKey: "razeWindowHeight") }
    }

    // Games — Quake 1 & 2 (vkQuake / Yamagi Quake II + Lite overlay shader)
    @Published var quakeBasePath: String {
        didSet { defaults.set(quakeBasePath, forKey: "quakeBasePath") }
    }
    @Published var quake2BasePath: String {
        didSet { defaults.set(quake2BasePath, forKey: "quake2BasePath") }
    }
    @Published var quakeLitePreset: String {
        didSet { defaults.set(quakeLitePreset, forKey: "quakeLitePreset") }
    }
    @Published var quake2LitePreset: String {
        didSet { defaults.set(quake2LitePreset, forKey: "quake2LitePreset") }
    }

    // Bloom (MPS-based post-process glow)
    @Published var bloomEnabled: Bool {
        didSet { defaults.set(bloomEnabled, forKey: "bloomEnabled") }
    }
    @Published var bloomIntensity: Float {
        didSet { defaults.set(bloomIntensity, forKey: "bloomIntensity") }
    }
    @Published var bloomRadius: Float {
        didSet { defaults.set(bloomRadius, forKey: "bloomRadius") }
    }

    // Retro Viewport
    @Published var viewportPreset: String {
        didSet { defaults.set(viewportPreset, forKey: "viewportPreset") }
    }

    // Settings Redesign — tab persistence
    @Published var lastSettingsTab: String {
        didSet { defaults.set(lastSettingsTab, forKey: "lastSettingsTab") }
    }

    // Settings Redesign — new hotkeys
    @Published var cyclePresetHotkeyCode: UInt32 {
        didSet { defaults.set(cyclePresetHotkeyCode, forKey: "cyclePresetHotkeyCode") }
    }
    @Published var cyclePresetHotkeyModifiers: UInt32 {
        didSet { defaults.set(cyclePresetHotkeyModifiers, forKey: "cyclePresetHotkeyModifiers") }
    }
    @Published var bumpIntensityHotkeyCode: UInt32 {
        didSet { defaults.set(bumpIntensityHotkeyCode, forKey: "bumpIntensityHotkeyCode") }
    }
    @Published var bumpIntensityHotkeyModifiers: UInt32 {
        didSet { defaults.set(bumpIntensityHotkeyModifiers, forKey: "bumpIntensityHotkeyModifiers") }
    }
    @Published var menuBarToggleHotkeyCode: UInt32 {
        didSet { defaults.set(menuBarToggleHotkeyCode, forKey: "menuBarToggleHotkeyCode") }
    }
    @Published var menuBarToggleHotkeyModifiers: UInt32 {
        didSet { defaults.set(menuBarToggleHotkeyModifiers, forKey: "menuBarToggleHotkeyModifiers") }
    }
    @Published var screenshotHotkeyCode: UInt32 {
        didSet { defaults.set(screenshotHotkeyCode, forKey: "screenshotHotkeyCode") }
    }
    @Published var screenshotHotkeyModifiers: UInt32 {
        didSet { defaults.set(screenshotHotkeyModifiers, forKey: "screenshotHotkeyModifiers") }
    }
    @Published var showHotkeyConflictTips: Bool {
        didSet { defaults.set(showHotkeyConflictTips, forKey: "showHotkeyConflictTips") }
    }
    @Published var showSplashScreen: Bool {
        didSet { defaults.set(showSplashScreen, forKey: "showSplashScreen") }
    }
    /// Per-theme boot screen on/off (image or video). Absent = default on for themes that define one.
    @Published var themeBootscreenEnabled: [String: Bool] {
        didSet { defaults.set(themeBootscreenEnabled, forKey: "themeBootscreenEnabled") }
    }
    /// Screensaver master switch.
    @Published var screensaverEnabled: Bool {
        didSet { defaults.set(screensaverEnabled, forKey: "screensaverEnabled") }
    }
    /// Idle minutes before the screensaver starts.
    @Published var screensaverIdleMinutes: Int {
        didSet { defaults.set(screensaverIdleMinutes, forKey: "screensaverIdleMinutes") }
    }
    /// Per-theme chosen screensaver id (overrides the theme's default). "none" disables it.
    @Published var themeScreensaverOverrides: [String: String] {
        didSet { defaults.set(themeScreensaverOverrides, forKey: "themeScreensaverOverrides") }
    }

    // Settings Redesign — per-app rules with reason
    struct PerAppRule: Codable, Equatable {
        var presetID: String   // empty string = "None — overlay off"
        var reason: String?
    }
    @Published var perAppRules: [String: PerAppRule] {
        didSet {
            if let data = try? JSONEncoder().encode(perAppRules) {
                defaults.set(data, forKey: "perAppRules")
            }
        }
    }

    var customPresetsDirectory: URL { presetsDir }

    static let defaultHotkeyCode = UInt32(kVK_ANSI_R)
    static let defaultHotkeyModifiers = UInt32(cmdKey | shiftKey)

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        presetsDir = appSupport.appendingPathComponent("RetroMac/Presets")
        try? FileManager.default.createDirectory(at: presetsDir, withIntermediateDirectories: true)

        defaultPreset = defaults.string(forKey: "defaultPreset") ?? "zfast-crt"
        defaultIntensity = defaults.object(forKey: "defaultIntensity") as? Float ?? 1.0
        vignetteIntensity = defaults.object(forKey: "vignetteIntensity") as? Float ?? 0.0
        hideSystemUI = defaults.bool(forKey: "hideSystemUI")
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        enableOnLaunch = defaults.bool(forKey: "enableOnLaunch")
        hotkeyCode = defaults.object(forKey: "hotkeyCode") as? UInt32 ?? Self.defaultHotkeyCode
        hotkeyModifiers = defaults.object(forKey: "hotkeyModifiers") as? UInt32 ?? Self.defaultHotkeyModifiers
        targetDisplayID = defaults.object(forKey: "targetDisplayID") as? CGDirectDisplayID ?? 0
        let profile = PerformanceProfile(rawValue: defaults.string(forKey: "performanceProfile") ?? "") ?? .balanced
        performanceProfile = profile
        lowLatencyMode = defaults.bool(forKey: "lowLatencyMode")
        halfResolution = defaults.object(forKey: "halfResolution") as? Bool ?? profile.halfResolution
        targetFPS = defaults.object(forKey: "targetFPS") as? Int ?? profile.targetFPS
        stopOnSleep = defaults.object(forKey: "stopOnSleep") as? Bool ?? true
        resumeAfterSleep = defaults.bool(forKey: "resumeAfterSleep")
        resetOnWake = defaults.bool(forKey: "resetOnWake")
        perAppPresets = defaults.dictionary(forKey: "perAppPresets") as? [String: String] ?? [:]
        scanlineOverlayName = defaults.string(forKey: "scanlineOverlayName") ?? ""
        scanlineOverlayIntensity = defaults.object(forKey: "scanlineOverlayIntensity") as? Float ?? 0.5
        reflectionName = defaults.string(forKey: "reflectionName") ?? ""
        reflectionIntensity = defaults.object(forKey: "reflectionIntensity") as? Float ?? 0.3

        // Onboarding / Features
        onboardingComplete = defaults.bool(forKey: "onboardingComplete")
        lastSeenVersion = defaults.string(forKey: "lastSeenVersion") ?? ""
        coffeeAckDate = defaults.object(forKey: "coffeeAckDate") as? Date
        dockModeEnabled = defaults.object(forKey: "dockModeEnabled") as? Bool ?? false
        shaderOnThemeChange = defaults.object(forKey: "shaderOnThemeChange") as? Bool ?? true
        themeIncludeWidgets = defaults.object(forKey: "themeIncludeWidgets") as? Bool ?? false
        setupWizardComplete = defaults.bool(forKey: "setupWizardComplete")
        // Floating launcher defaults ON. One-time migration flips legacy installs
        // (earlier builds shipped it off / persisted false) so this update turns the
        // floating quick-access button on for everyone, once.
        if defaults.object(forKey: "floatingLauncherDefaultOnMigrated") == nil {
            defaults.set(true, forKey: "floatingLauncherEnabled")
            defaults.set(true, forKey: "floatingLauncherDefaultOnMigrated")
        }
        floatingLauncherEnabled = defaults.object(forKey: "floatingLauncherEnabled") as? Bool ?? true
        quickAccessSlots = defaults.stringArray(forKey: "quickAccessSlots") ?? []
        dockOnly = defaults.bool(forKey: "dockOnly")
        retroModeTheme = defaults.string(forKey: "retroModeTheme") ?? "Maiks Favourite"
        retroModeShader = defaults.string(forKey: "retroModeShader") ?? ""
        retroModeHideDock = defaults.object(forKey: "retroModeHideDock") as? Bool ?? true
        retroModeHideMenuBar = defaults.object(forKey: "retroModeHideMenuBar") as? Bool ?? true
        retroModeHideDesktopIcons = defaults.object(forKey: "retroModeHideDesktopIcons") as? Bool ?? true
        retroModeActivateShader = defaults.object(forKey: "retroModeActivateShader") as? Bool ?? true
        pacmanAnimationEnabled = defaults.object(forKey: "pacmanAnimationEnabled") as? Bool ?? true
        // Desktop pet (sheep) NEVER auto-starts: not on app launch, not on theme selection.
        // It only appears when the user explicitly runs sheep.exe (in-memory, not persisted).
        desktopPetEnabled = false
        pacmanClockMode = defaults.object(forKey: "pacmanClockMode") as? Bool ?? false
        classicMacModeActive = defaults.bool(forKey: "classicMacModeActive")
        slayerScale = defaults.object(forKey: "slayerScale") as? Double ?? 0.75
        slayerRunSpeed = defaults.object(forKey: "slayerRunSpeed") as? Double ?? 40
        slayerCombat = defaults.object(forKey: "slayerCombat") as? String ?? "Normal"
        slayerWeapon = defaults.object(forKey: "slayerWeapon") as? String ?? "Auto-cycle"
        slayerDirection = defaults.object(forKey: "slayerDirection") as? String ?? "Right"
        doomLaunchTarget = defaults.object(forKey: "doomLaunchTarget") as? String ?? ""
        clockUse24Hour = defaults.object(forKey: "clockUse24Hour") as? Bool ?? false

        // Per-theme preset overrides
        themePresetOverrides = defaults.dictionary(forKey: "themePresetOverrides") as? [String: String] ?? [:]
        themeOrientationOverrides = defaults.dictionary(forKey: "themeOrientationOverrides") as? [String: String] ?? [:]
        themeDockPositionOverride = defaults.dictionary(forKey: "themeDockPositionOverride") as? [String: String] ?? [:]
        themeDockAutoHide = defaults.dictionary(forKey: "themeDockAutoHide") as? [String: Bool] ?? [:]
        themeWallpaperOverrides = defaults.dictionary(forKey: "themeWallpaperOverrides") as? [String: String] ?? [:]
        themeCustomWallpaper = defaults.dictionary(forKey: "themeCustomWallpaper") as? [String: String] ?? [:]
        themeBootscreenEnabled = defaults.dictionary(forKey: "themeBootscreenEnabled") as? [String: Bool] ?? [:]
        screensaverEnabled = defaults.bool(forKey: "screensaverEnabled")
        screensaverIdleMinutes = defaults.object(forKey: "screensaverIdleMinutes") as? Int ?? 5
        themeScreensaverOverrides = defaults.dictionary(forKey: "themeScreensaverOverrides") as? [String: String] ?? [:]
        reampEnabled = defaults.bool(forKey: "reampEnabled")

        // Television
        if let data = defaults.data(forKey: "tvBookmarks"),
           let bookmarks = try? JSONDecoder().decode([TVBookmark].self, from: data) {
            tvBookmarks = bookmarks
        } else {
            tvBookmarks = [
                TVBookmark(name: "Retro", url: "http://stream.mediawork.cz/retrotv/retrotvHQ1/chunklist_w627639048.m3u8"),
                TVBookmark(name: "Now 90s", url: "https://lightning-now90s-samsungnz.amagi.tv/playlist.m3u8"),
                TVBookmark(name: "Now 80s", url: "https://lightning-now80s-samsunguk.amagi.tv/playlist.m3u8"),
                TVBookmark(name: "Classic Movies", url: "https://rpn.bozztv.com/gusa/gusa-tvsclassicmovies/index.m3u8"),
                TVBookmark(name: "Quiz Show", url: "https://rpn.bozztv.com/gusa/gusa-tvsgameshow/index.m3u8"),
                TVBookmark(name: "Baywatch", url: "https://amg00145-fremantlemedian-baywatch-samsungau-gtsd6.amagi.tv/playlist/amg00145-fremantlemedian-baywatch-samsungau/playlist.m3u8"),
            ]
        }

        // Dock
        dockEnabled = defaults.bool(forKey: "dockEnabled")
        dockHideSystemDock = defaults.object(forKey: "dockHideSystemDock") as? Bool ?? true
        hideMenuBar = defaults.bool(forKey: "hideMenuBar")
        // Menu-bar Apple style (migrate the legacy menuBarRainbowApple bool: true → rainbow).
        if let style = defaults.object(forKey: "menuBarAppleStyle") as? Int {
            menuBarAppleStyle = style
        } else if let legacy = defaults.object(forKey: "menuBarRainbowApple") as? Bool {
            menuBarAppleStyle = legacy ? 1 : 0
        } else {
            menuBarAppleStyle = 0
        }
        hideDesktopIcons = defaults.bool(forKey: "hideDesktopIcons")
        dockHotkeyCode = defaults.object(forKey: "dockHotkeyCode") as? UInt32 ?? UInt32(kVK_ANSI_D)
        dockHotkeyModifiers = defaults.object(forKey: "dockHotkeyModifiers") as? UInt32 ?? UInt32(cmdKey | optionKey | controlKey)
        dockTransparency = defaults.object(forKey: "dockTransparency") as? Float ?? 0.85
        dockShowRunningApps = defaults.object(forKey: "dockShowRunningApps") as? Bool ?? true
        deskbarCorner = defaults.string(forKey: "deskbarCorner") ?? "bottomLeft"
        dockShowDownloads = defaults.object(forKey: "dockShowDownloads") as? Bool ?? true
        deskbarShortcuts = defaults.stringArray(forKey: "deskbarShortcuts")
            ?? ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.MobileSMS", "com.apple.iCal", "com.apple.reminders", "com.apple.Notes"]
        dockTheme = defaults.string(forKey: "dockTheme") ?? "Maiks Favourite"
        dockIconScale = defaults.object(forKey: "dockIconScale") as? Float ?? 1.0
        dockTargetDisplayID = defaults.object(forKey: "dockTargetDisplayID") as? CGDirectDisplayID ?? 0
        dockMagnification = defaults.object(forKey: "dockMagnification") as? Bool ?? true
        dockAutoHide = defaults.bool(forKey: "dockAutoHide")
        dockFix = defaults.bool(forKey: "dockFix")
        applySystemIcons = defaults.bool(forKey: "applySystemIcons")

        // Virtual Camera — capture source
        cameraSourceID = defaults.string(forKey: "cameraSourceID") ?? ""

        // Virtual Camera — Lower Third
        lowerThirdEnabled = defaults.bool(forKey: "lowerThirdEnabled")
        lowerThirdName = defaults.string(forKey: "lowerThirdName") ?? ""
        lowerThirdTitle = defaults.string(forKey: "lowerThirdTitle") ?? ""
        lowerThirdStyle = defaults.string(forKey: "lowerThirdStyle") ?? "latenight"

        // Games — Doom
        let defaultWadDir = NSHomeDirectory() + "/Library/Application Support/gzdoom"
        doomWadFolder = defaults.string(forKey: "doomWadFolder") ?? defaultWadDir
        gamesCRTEnabled = defaults.object(forKey: "gamesCRTEnabled") as? Bool ?? true
        doomWindowWidth = defaults.object(forKey: "doomWindowWidth") as? Int ?? 640
        doomWindowHeight = defaults.object(forKey: "doomWindowHeight") as? Int ?? 480

        // Games — Duke Nukem 3D (Raze)
        let defaultGrpDir = NSHomeDirectory() + "/Library/Application Support/RetroMac/Games"
        razeGrpFolder = defaults.string(forKey: "razeGrpFolder") ?? defaultGrpDir
        razeWindowWidth = defaults.object(forKey: "razeWindowWidth") as? Int ?? 640
        razeWindowHeight = defaults.object(forKey: "razeWindowHeight") as? Int ?? 480

        // Games — Quake 1 & 2 (vkQuake / Yamagi)
        let defaultQuakeDir = NSHomeDirectory() + "/Library/Application Support/RetroMac/Games/Quake"
        quakeBasePath = defaults.string(forKey: "quakeBasePath") ?? defaultQuakeDir
        let defaultQuake2Dir = NSHomeDirectory() + "/Library/Application Support/RetroMac/Games/Quake2"
        quake2BasePath = defaults.string(forKey: "quake2BasePath") ?? defaultQuake2Dir
        quakeLitePreset = defaults.string(forKey: "quakeLitePreset") ?? "crt-lite"
        quake2LitePreset = defaults.string(forKey: "quake2LitePreset") ?? "crt-lite"

        // Bloom
        bloomEnabled = defaults.bool(forKey: "bloomEnabled")
        bloomIntensity = defaults.object(forKey: "bloomIntensity") as? Float ?? 0.3
        bloomRadius = defaults.object(forKey: "bloomRadius") as? Float ?? 8.0

        // Viewport
        viewportPreset = defaults.string(forKey: "viewportPreset") ?? "crt-royale-lite"

        // Settings Redesign
        lastSettingsTab = defaults.string(forKey: "lastSettingsTab") ?? "overview"
        cyclePresetHotkeyCode = defaults.object(forKey: "cyclePresetHotkeyCode") as? UInt32 ?? 0
        cyclePresetHotkeyModifiers = defaults.object(forKey: "cyclePresetHotkeyModifiers") as? UInt32 ?? 0
        bumpIntensityHotkeyCode = defaults.object(forKey: "bumpIntensityHotkeyCode") as? UInt32 ?? 0
        bumpIntensityHotkeyModifiers = defaults.object(forKey: "bumpIntensityHotkeyModifiers") as? UInt32 ?? 0
        menuBarToggleHotkeyCode = defaults.object(forKey: "menuBarToggleHotkeyCode") as? UInt32 ?? 0
        menuBarToggleHotkeyModifiers = defaults.object(forKey: "menuBarToggleHotkeyModifiers") as? UInt32 ?? 0
        screenshotHotkeyCode = defaults.object(forKey: "screenshotHotkeyCode") as? UInt32 ?? 0
        screenshotHotkeyModifiers = defaults.object(forKey: "screenshotHotkeyModifiers") as? UInt32 ?? 0
        showHotkeyConflictTips = defaults.object(forKey: "showHotkeyConflictTips") as? Bool ?? true
        showSplashScreen = defaults.object(forKey: "showSplashScreen") as? Bool ?? true

        // Per-app rules (migrate from old perAppPresets if needed)
        if let data = defaults.data(forKey: "perAppRules"),
           let rules = try? JSONDecoder().decode([String: PerAppRule].self, from: data) {
            perAppRules = rules
        } else {
            // Migrate from old format
            let oldPresets = defaults.dictionary(forKey: "perAppPresets") as? [String: String] ?? [:]
            var migrated: [String: PerAppRule] = [:]
            for (bundleID, presetID) in oldPresets {
                migrated[bundleID] = PerAppRule(presetID: presetID, reason: nil)
            }
            perAppRules = migrated
        }
    }

    func presetForApp(bundleID: String) -> String? {
        perAppPresets[bundleID]
    }

    /// Returns the preset for a theme: user override > theme.json default > nil
    func presetForTheme(name: String) -> String? {
        if let override = themePresetOverrides[name] {
            return override.isEmpty ? nil : override  // empty = "None"
        }
        // Fall back to theme.json defaultPreset
        return ThemeManager.shared.availableThemes.first(where: { $0.name == name })?.config.defaultPreset
    }

    var hotkeyDisplayString: String {
        var parts: [String] = []
        if hotkeyModifiers & UInt32(controlKey) != 0 { parts.append("\u{2303}") }
        if hotkeyModifiers & UInt32(optionKey) != 0 { parts.append("\u{2325}") }
        if hotkeyModifiers & UInt32(shiftKey) != 0 { parts.append("\u{21E7}") }
        if hotkeyModifiers & UInt32(cmdKey) != 0 { parts.append("\u{2318}") }
        parts.append(Self.keyName(for: hotkeyCode))
        return parts.joined()
    }

    static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
            UInt32(kVK_Tab): "Tab", UInt32(kVK_Escape): "Esc",
        ]
        return names[keyCode] ?? "Key\(keyCode)"
    }

    /// Applies a performance profile by updating the individual settings it controls
    func applyPerformanceProfile() {
        let profile = performanceProfile
        halfResolution = profile.halfResolution
        targetFPS = profile.targetFPS

        if profile.disableOverlays {
            scanlineOverlayName = ""
            reflectionName = ""
        }
    }

    private func updateLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[Settings] Login item update failed: \(error)")
            }
        }
    }
}
