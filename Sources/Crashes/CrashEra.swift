import Foundation

/// Which machine is pretending to fail.
///
/// This is the only place that maps a theme to an era, and it deliberately does NOT use
/// `RetroFrameTheme.key()`: that key collapses Windows 95, 98 and Me into one `win98`
/// (RetroFrameTheme.swift:38-40) because they share their window chrome. Their failures do not.
/// Me alone shows "Windows protection error", and 95 never saw a Stop screen worded like XP's.
///
/// Resolution goes through the manifest's stable id, which every shipped theme declares
/// (`com.retromac.microsoft.windows95` and friends), with the release year as a fallback for
/// themes imported before ids existed.
enum CrashEra: String, CaseIterable {
    case win95, win98, winMe, winXP, win7
    case macos6, macos9, macosxAqua, macosxModern

    var displayName: String {
        switch self {
        case .win95: return "Windows 95"
        case .win98: return "Windows 98"
        case .winMe: return "Windows Me"
        case .winXP: return "Windows XP"
        case .win7:  return "Windows 7"
        case .macos6: return "System 6"
        case .macos9: return "Mac OS 9"
        case .macosxAqua: return "Mac OS X"
        case .macosxModern: return "Mac OS X (Snow Leopard and later)"
        }
    }

    /// The era of the theme that is on screen right now, or nil when RetroMac is not dressed as
    /// anything that could crash.
    static func current() -> CrashEra? {
        guard AppSettings.shared.dockEnabled,
              let config = ThemeManager.shared.activeTheme?.config else { return nil }

        switch config.id {
        case "com.retromac.microsoft.windows95": return .win95
        case "com.retromac.microsoft.windows98": return .win98
        case "com.retromac.microsoft.windowsme": return .winMe
        case "com.retromac.microsoft.windowsxp": return .winXP
        case "com.retromac.microsoft.windows7":  return .win7
        case "com.retromac.apple.system6":       return .macos6
        case "com.retromac.apple.macos9":        return .macos9
        // Cheetah's panic was still a text console; the grey curtain everyone pictures arrived
        // with Panther and stayed through Snow Leopard and Mountain Lion.
        case "com.retromac.apple.aqua-cheetah":  return .macosxAqua
        case "com.retromac.apple.snow-leopard",
             "com.retromac.apple.mountain-lion": return .macosxModern
        default: break
        }

        // Pre-2.0 imports have no id. Fall back to the display name, which is what those
        // manifests do carry.
        let name = config.name.lowercased()
        if name.contains("windows 95") { return .win95 }
        if name.contains("windows 98") { return .win98 }
        if name.contains("windows me") { return .winMe }
        if name.contains("windows xp") { return .winXP }
        if name.contains("windows 7")  { return .win7 }
        if name.contains("system 6") || name.contains("mac os 6") { return .macos6 }
        if name.contains("mac os 9")   { return .macos9 }
        if name.contains("snow leopard") || name.contains("mountain lion") { return .macosxModern }
        if name.contains("mac os x")   { return .macosxAqua }
        return nil
    }
}
