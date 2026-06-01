import Foundation
import Darwin

// MediaAccessibility framework functions — loaded dynamically
// These manage macOS Accessibility → Display → Color Filters
// See: https://github.com/brettferdosi/grayscale
private typealias MAFilterGetEnabled = @convention(c) (Int32) -> Bool
private typealias MAFilterSetEnabled = @convention(c) (Int32, Bool) -> Void
private typealias MAFilterGetType = @convention(c) (Int32) -> Int32
private typealias MAFilterSetType = @convention(c) (Int32, Int32) -> Void
private typealias MAFilterGetFloat = @convention(c) (Int32) -> Float
private typealias MAFilterSetFloat = @convention(c) (Int32, Float) -> Void
private typealias UADStart = @convention(c) (Int32) -> Void

private let SYSTEM_FILTER: Int32 = 0x1
private let GRAYSCALE_TYPE: Int32 = 0x1
private let COLOR_TINT_TYPE: Int32 = 0x10
private let UNIVERSALACCESSD_MAGIC: Int32 = 0x8

/// Which display filter mode is active
enum DisplayFilterMode {
    case none
    case grayscale
    case colorTint(hue: Float, intensity: Float)
}

/// Toggles macOS Accessibility display filters for Lite shaders.
/// Uses MediaAccessibility + UniversalAccess private frameworks
/// (same API as System Settings → Accessibility → Color Filters).
enum DisplayFilterHelper {
    // Saved state for restore
    private static var wasFilterEnabled = false
    private static var wasFilterType: Int32 = 0
    private static var wasColorHue: Float = 0
    private static var wasColorIntensity: Float = 0
    private static var isManaging = false
    private static var currentMode: DisplayFilterMode = .none

    // Dynamically resolved function pointers
    private static let maHandle = dlopen("/System/Library/Frameworks/MediaAccessibility.framework/MediaAccessibility", RTLD_LAZY)
    private static let uaHandle = dlopen("/System/Library/PrivateFrameworks/UniversalAccess.framework/Versions/A/Frameworks/UniversalAccessCore.framework/UniversalAccessCore", RTLD_LAZY)

    private static let _getCategoryEnabled: MAFilterGetEnabled? = {
        guard let h = maHandle, let s = dlsym(h, "MADisplayFilterPrefGetCategoryEnabled") else { return nil }
        return unsafeBitCast(s, to: MAFilterGetEnabled.self)
    }()

    private static let _setCategoryEnabled: MAFilterSetEnabled? = {
        guard let h = maHandle, let s = dlsym(h, "MADisplayFilterPrefSetCategoryEnabled") else { return nil }
        return unsafeBitCast(s, to: MAFilterSetEnabled.self)
    }()

    private static let _getType: MAFilterGetType? = {
        guard let h = maHandle, let s = dlsym(h, "MADisplayFilterPrefGetType") else { return nil }
        return unsafeBitCast(s, to: MAFilterGetType.self)
    }()

    private static let _setType: MAFilterSetType? = {
        guard let h = maHandle, let s = dlsym(h, "MADisplayFilterPrefSetType") else { return nil }
        return unsafeBitCast(s, to: MAFilterSetType.self)
    }()

    private static let _getColorHue: MAFilterGetFloat? = {
        guard let h = maHandle, let s = dlsym(h, "MADisplayFilterPrefGetSingleColorHue") else { return nil }
        return unsafeBitCast(s, to: MAFilterGetFloat.self)
    }()

    private static let _setColorHue: MAFilterSetFloat? = {
        guard let h = maHandle, let s = dlsym(h, "MADisplayFilterPrefSetSingleColorHue") else { return nil }
        return unsafeBitCast(s, to: MAFilterSetFloat.self)
    }()

    private static let _getColorIntensity: MAFilterGetFloat? = {
        guard let h = maHandle, let s = dlsym(h, "MADisplayFilterPrefGetSingleColorIntensity") else { return nil }
        return unsafeBitCast(s, to: MAFilterGetFloat.self)
    }()

    private static let _setColorIntensity: MAFilterSetFloat? = {
        guard let h = maHandle, let s = dlsym(h, "MADisplayFilterPrefSetSingleColorIntensity") else { return nil }
        return unsafeBitCast(s, to: MAFilterSetFloat.self)
    }()

    private static let _universalAccessDStart: UADStart? = {
        if let h = uaHandle, let s = dlsym(h, "_UniversalAccessDStart") {
            return unsafeBitCast(s, to: UADStart.self)
        }
        if let h = dlopen("/System/Library/PrivateFrameworks/UniversalAccess.framework/UniversalAccess", RTLD_LAZY),
           let s = dlsym(h, "_UniversalAccessDStart") {
            return unsafeBitCast(s, to: UADStart.self)
        }
        return nil
    }()

    // MARK: - Public API

    /// Enable macOS grayscale filter (saves previous state for restore)
    static func enableGrayscale() {
        guard _setCategoryEnabled != nil, _setType != nil else {
            print("[DisplayFilter] MediaAccessibility functions not available")
            return
        }

        saveCurrentState()
        isManaging = true
        currentMode = .grayscale

        if !isFilterActive(type: GRAYSCALE_TYPE) {
            _setType?(SYSTEM_FILTER, GRAYSCALE_TYPE)
            _setCategoryEnabled?(SYSTEM_FILTER, true)
            applyChanges()
            print("[DisplayFilter] Grayscale enabled")
        } else {
            print("[DisplayFilter] Grayscale was already active")
        }
    }

    /// Enable macOS Color Tint filter with specified hue and intensity
    /// - Parameters:
    ///   - hue: Color hue 0.0–1.0 (0.0=red, 0.08=amber, 0.12=orange, 0.17=yellow, 0.33=green, 0.67=blue)
    ///   - intensity: Tint strength 0.0–1.0
    static func enableColorTint(hue: Float, intensity: Float) {
        guard _setCategoryEnabled != nil, _setType != nil,
              _setColorHue != nil, _setColorIntensity != nil else {
            print("[DisplayFilter] Color Tint functions not available")
            return
        }

        saveCurrentState()
        isManaging = true
        currentMode = .colorTint(hue: hue, intensity: intensity)

        _setType?(SYSTEM_FILTER, COLOR_TINT_TYPE)
        _setColorHue?(SYSTEM_FILTER, hue)
        _setColorIntensity?(SYSTEM_FILTER, intensity)
        _setCategoryEnabled?(SYSTEM_FILTER, true)
        applyChanges()
        print("[DisplayFilter] Color Tint enabled (hue=\(hue), intensity=\(intensity))")
    }

    /// Restore previous filter state (only changes back if we changed it)
    static func restoreFilter() {
        guard isManaging else { return }
        isManaging = false
        currentMode = .none

        if !wasFilterEnabled {
            // Filter was off — turn it off
            _setCategoryEnabled?(SYSTEM_FILTER, false)
            applyChanges()
            print("[DisplayFilter] Filter disabled — restored to off")
        } else {
            // Filter was on with different settings — restore them
            _setType?(SYSTEM_FILTER, wasFilterType)
            if wasFilterType == COLOR_TINT_TYPE {
                _setColorHue?(SYSTEM_FILTER, wasColorHue)
                _setColorIntensity?(SYSTEM_FILTER, wasColorIntensity)
            }
            _setCategoryEnabled?(SYSTEM_FILTER, true)
            applyChanges()
            print("[DisplayFilter] Restored previous filter (type=0x\(String(wasFilterType, radix: 16)))")
        }
    }

    /// Legacy name — calls restoreFilter()
    static func restoreGrayscale() {
        restoreFilter()
    }

    /// Whether we're currently managing a display filter
    static var isActive: Bool { isManaging }

    // MARK: - Private

    private static func saveCurrentState() {
        wasFilterEnabled = _getCategoryEnabled?(SYSTEM_FILTER) ?? false
        wasFilterType = _getType?(SYSTEM_FILTER) ?? 0
        wasColorHue = _getColorHue?(SYSTEM_FILTER) ?? 0
        wasColorIntensity = _getColorIntensity?(SYSTEM_FILTER) ?? 0
    }

    private static func isFilterActive(type: Int32) -> Bool {
        return (_getCategoryEnabled?(SYSTEM_FILTER) ?? false) &&
            (_getType?(SYSTEM_FILTER) ?? 0) == type
    }

    private static func applyChanges() {
        if let start = _universalAccessDStart {
            start(UNIVERSALACCESSD_MAGIC)
        }
    }
}
