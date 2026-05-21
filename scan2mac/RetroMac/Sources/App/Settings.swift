import Foundation
import ServiceManagement
import Carbon.HIToolbox

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
    @Published var lowLatencyMode: Bool {
        didSet { defaults.set(lowLatencyMode, forKey: "lowLatencyMode") }
    }
    @Published var halfResolution: Bool {
        didSet { defaults.set(halfResolution, forKey: "halfResolution") }
    }
    @Published var stopOnSleep: Bool {
        didSet { defaults.set(stopOnSleep, forKey: "stopOnSleep") }
    }
    @Published var resumeAfterSleep: Bool {
        didSet { defaults.set(resumeAfterSleep, forKey: "resumeAfterSleep") }
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
    @Published var showFPSOverlay: Bool {
        didSet { defaults.set(showFPSOverlay, forKey: "showFPSOverlay") }
    }
    @Published var classicMacModeActive: Bool {
        didSet { defaults.set(classicMacModeActive, forKey: "classicMacModeActive") }
    }

    // Dock
    @Published var dockEnabled: Bool {
        didSet { defaults.set(dockEnabled, forKey: "dockEnabled") }
    }
    @Published var dockHideSystemDock: Bool {
        didSet { defaults.set(dockHideSystemDock, forKey: "dockHideSystemDock") }
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
    @Published var dockIconScale: Float {
        didSet { defaults.set(dockIconScale, forKey: "dockIconScale") }
    }
    @Published var dockTargetDisplayID: CGDirectDisplayID {
        didSet { defaults.set(dockTargetDisplayID, forKey: "dockTargetDisplayID") }
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
        lowLatencyMode = defaults.bool(forKey: "lowLatencyMode")
        halfResolution = defaults.bool(forKey: "halfResolution")
        stopOnSleep = defaults.object(forKey: "stopOnSleep") as? Bool ?? true
        resumeAfterSleep = defaults.bool(forKey: "resumeAfterSleep")
        perAppPresets = defaults.dictionary(forKey: "perAppPresets") as? [String: String] ?? [:]
        scanlineOverlayName = defaults.string(forKey: "scanlineOverlayName") ?? ""
        scanlineOverlayIntensity = defaults.object(forKey: "scanlineOverlayIntensity") as? Float ?? 0.5
        reflectionName = defaults.string(forKey: "reflectionName") ?? ""
        reflectionIntensity = defaults.object(forKey: "reflectionIntensity") as? Float ?? 0.3

        // Onboarding / Features
        onboardingComplete = defaults.bool(forKey: "onboardingComplete")
        showFPSOverlay = defaults.bool(forKey: "showFPSOverlay")
        classicMacModeActive = defaults.bool(forKey: "classicMacModeActive")

        // Dock
        dockEnabled = defaults.bool(forKey: "dockEnabled")
        dockHideSystemDock = defaults.bool(forKey: "dockHideSystemDock")
        dockHotkeyCode = defaults.object(forKey: "dockHotkeyCode") as? UInt32 ?? UInt32(kVK_ANSI_D)
        dockHotkeyModifiers = defaults.object(forKey: "dockHotkeyModifiers") as? UInt32 ?? UInt32(cmdKey | optionKey | controlKey)
        dockTransparency = defaults.object(forKey: "dockTransparency") as? Float ?? 0.85
        dockShowRunningApps = defaults.object(forKey: "dockShowRunningApps") as? Bool ?? true
        dockTheme = defaults.string(forKey: "dockTheme") ?? "Mountain Lion"
        dockIconScale = defaults.object(forKey: "dockIconScale") as? Float ?? 1.0
        dockTargetDisplayID = defaults.object(forKey: "dockTargetDisplayID") as? CGDirectDisplayID ?? 0
    }

    func presetForApp(bundleID: String) -> String? {
        perAppPresets[bundleID]
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
