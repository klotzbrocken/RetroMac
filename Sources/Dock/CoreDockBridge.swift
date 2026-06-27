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

    /// kCoreDockOrientation*: top=1, bottom=2, left=3, right=4.
    enum Orientation: Int32 {
        case top = 1, bottom = 2, left = 3, right = 4
        init?(edge: String) {
            switch edge {
            case "top": self = .top
            case "bottom": self = .bottom
            case "left": self = .left
            case "right": self = .right
            default: return nil
            }
        }
        var edge: String {
            switch self {
            case .top: return "top"; case .bottom: return "bottom"
            case .left: return "left"; case .right: return "right"
            }
        }
    }

    private typealias SetAutoHideFn = @convention(c) (DarwinBoolean) -> Void
    private typealias GetAutoHideFn = @convention(c) () -> DarwinBoolean
    private typealias SetOrientFn   = @convention(c) (Int32, Int32) -> Void
    private typealias GetOrientFn   = @convention(c) (UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Void

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil } // RTLD_DEFAULT
        return unsafeBitCast(p, to: T.self)
    }

    static var isAvailable: Bool {
        symbol("CoreDockSetAutoHideEnabled", as: SetAutoHideFn.self) != nil
    }

    static func getAutoHide() -> Bool? {
        symbol("CoreDockGetAutoHideEnabled", as: GetAutoHideFn.self)?().boolValue
    }

    @discardableResult
    static func setAutoHide(_ enabled: Bool) -> Bool {
        guard let f = symbol("CoreDockSetAutoHideEnabled", as: SetAutoHideFn.self) else { return false }
        f(DarwinBoolean(enabled))
        return true
    }

    static func getOrientation() -> Orientation? {
        guard let f = symbol("CoreDockGetOrientationAndPinning", as: GetOrientFn.self) else { return nil }
        var o: Int32 = 0, p: Int32 = 0
        f(&o, &p)
        return Orientation(rawValue: o)
    }

    /// pinning 2 = middle (the usual default).
    @discardableResult
    static func setOrientation(_ orientation: Orientation, pinning: Int32 = 2) -> Bool {
        guard let f = symbol("CoreDockSetOrientationAndPinning", as: SetOrientFn.self) else { return false }
        f(orientation.rawValue, pinning)
        return true
    }
}
