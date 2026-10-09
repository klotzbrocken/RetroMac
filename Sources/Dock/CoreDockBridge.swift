import Foundation

/// Thin wrapper over the private **CoreDock** API (HIServices). Toggles the system
/// Dock's auto-hide and orientation **live**, without `killall Dock` — so it never
/// restacks the user's windows the way restarting the Dock does (that was the cause of
/// "all background windows jump to front on a theme/dock switch").
///
/// Symbols are resolved at runtime via `dlsym`. If any is missing (a future macOS that
/// drops them), `isAvailable` is false and callers fall back to the defaults + killall
/// path. Same posture as the rest of RetroMac's private-dock usage.
enum CoreDockBridge {

    private typealias SetAutoHideFn = @convention(c) (DarwinBoolean) -> Void

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil } // RTLD_DEFAULT
        return unsafeBitCast(p, to: T.self)
    }

    static var isAvailable: Bool {
        symbol("CoreDockSetAutoHideEnabled", as: SetAutoHideFn.self) != nil
    }

    @discardableResult
    static func setAutoHide(_ enabled: Bool) -> Bool {
        guard let f = symbol("CoreDockSetAutoHideEnabled", as: SetAutoHideFn.self) else { return false }
        if AppSettings.shared.debugLogging { print("[Spaces] CoreDock auto-hide → \(enabled)") }
        f(DarwinBoolean(enabled))
        return true
    }

}
