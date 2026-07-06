import AppKit

/// System-wide cursor theming via the private CoreGraphics (CGS) cursor API — the same
/// mechanism MaCursor uses. On macOS 26 (Tahoe) two things are essential and were the
/// reason a naive attempt shows nothing:
///   1. the pointer must be registered under ALL of its aliases
///      (`com.apple.coregraphics.Arrow`, `…ArrowS`, `com.apple.cursor.0`), and
///   2. a refresh must be forced — `CGSSetDockCursorOverride` + a cursor-scale "bump"
///      + `CGSSetSystemDefinedCursor(0)` — because the old CoreCursor refresh hooks were
///      removed and the hardware cursor otherwise keeps the cached image.
///
/// Restore doesn't try to re-supply a captured image (fragile — a wrong point size gives
/// a tiny/blank cursor). Instead it writes AppKit's genuine `NSCursor.arrow`/`.iBeam`
/// back (those are the real system art, independent of what we registered) and drops the
/// wait override. A one-shot flag makes it crash-safe: any leftover on the next launch
/// triggers a restore.
enum CursorSlot: String, CaseIterable { case arrow, ibeam, wait }

struct CursorFrames {
    let frames: [CGImage]   // 1 image = static; N = animated
    let size: CGSize        // logical size in POINTS
    let hotspot: CGPoint
    let frameDuration: CGFloat
}

final class CursorThemeManager {
    static let shared = CursorThemeManager()
    private init() {}

    // MARK: - Private CGS API (resolved at runtime; no link-time dependency)

    private typealias VFn        = @convention(c) () -> Int32
    private typealias RegFn      = @convention(c) (Int32, UnsafePointer<CChar>, Bool, Bool, CGSize, CGPoint, UInt, CGFloat, CFArray, UnsafeMutablePointer<Int32>) -> Int32
    private typealias SetFn      = @convention(c) (Int32, UnsafePointer<CChar>, UnsafeMutablePointer<Int32>) -> Int32
    private typealias GetScaleFn = @convention(c) (Int32, UnsafeMutablePointer<CGFloat>) -> Int32
    private typealias SetScaleFn = @convention(c) (Int32, CGFloat) -> Int32
    private typealias DockOvFn   = @convention(c) (Int32, Bool) -> Void
    private typealias SysCurFn   = @convention(c) (Int32, Int32) -> Int32
    private typealias RemoveFn   = @convention(c) (Int32, UnsafePointer<CChar>, Bool) -> Int32

    private static func sym<T>(_ name: String, _ type: T.Type) -> T? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: T.self) }
    }
    private lazy var _main     = Self.sym("CGSMainConnectionID", VFn.self)
    private lazy var _reg      = Self.sym("CGSRegisterCursorWithImages", RegFn.self)
    private lazy var _set      = Self.sym("CGSSetRegisteredCursor", SetFn.self)
    private lazy var _getScale = Self.sym("CGSGetCursorScale", GetScaleFn.self)
    private lazy var _setScale = Self.sym("CGSSetCursorScale", SetScaleFn.self)
    private lazy var _dockOv   = Self.sym("CGSSetDockCursorOverride", DockOvFn.self)
    private lazy var _sysCur   = Self.sym("CGSSetSystemDefinedCursor", SysCurFn.self)
    private lazy var _remove   = Self.sym("CGSRemoveRegisteredCursor", RemoveFn.self)

    /// The whole feature is a no-op if the private symbols aren't present (belt-and-braces
    /// for a future macOS that removes them).
    var isSupported: Bool { _main != nil && _reg != nil && _set != nil && _dockOv != nil }
    private var cid: Int32 { _main?() ?? 0 }

    /// Every macOS identifier a given logical slot maps to. On Tahoe the pointer is shown
    /// through several of these at once, so we register the same image under all of them.
    private let idGroups: [CursorSlot: [String]] = [
        .arrow: ["com.apple.coregraphics.Arrow", "com.apple.coregraphics.ArrowS", "com.apple.cursor.0"],
        .ibeam: ["com.apple.coregraphics.IBeam", "com.apple.coregraphics.IBeamS", "com.apple.cursor.1"],
        .wait:  ["com.apple.coregraphics.Wait", "com.apple.cursor.4"],
    ]

    private let d = UserDefaults.standard
    private let appliedKey = "cursorThemeApplied"
    private let legacyKey = "cursorSnapshotTaken"   // cleared if an older build left it

    /// Legacy capture location — removed on restore so an old red-polluted PNG can't linger.
    private var legacyBackupDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RetroMac/CursorBackup", isDirectory: true)
    }

    // MARK: - Public entry points (mirror AppearanceAdapter)

    /// Apply the theme's cursor set if the toggle is on and the theme has one; otherwise
    /// put the user's cursors back. Safe to call on every theme switch.
    func apply(for config: DockThemeConfig) {
        guard isSupported, AppSettings.shared.themeAdaptCursor,
              let set = Self.cursorSet(for: config.name) else { restore(); return }
        for (slot, frames) in set { registerGroup(slot, frames) }
        finalize(dockOverride: true)
        d.set(true, forKey: appliedKey)
        print("[Cursor] Applied cursor set for \(config.name)")
    }

    /// Put a normal-looking cursor back. Turning the override off doesn't reliably reveal
    /// the built-in cursors on Tahoe (the slot just goes blank/white), so we register a
    /// standard arrow + I-beam and keep the override on — visually identical to the default
    /// for an uncustomised cursor. The wait override is dropped. No-op unless we'd applied.
    func restore() {
        guard isSupported, d.bool(forKey: appliedKey) || d.bool(forKey: legacyKey) else { return }
        for (slot, frames) in Self.standardCursorSet() { registerGroup(slot, frames) }
        removeGroup(.wait)
        finalize(dockOverride: true)
        d.removeObject(forKey: appliedKey)
        d.removeObject(forKey: legacyKey)
        try? FileManager.default.removeItem(at: legacyBackupDir)
        print("[Cursor] Restored system cursors")
    }

    /// Crash / force-quit recovery: any leftover flag at launch means the previous session
    /// never restored — put the user's cursors back. If a cursor theme is still active,
    /// apply() re-applies right after launch.
    func restoreIfNeeded() {
        guard isSupported, d.bool(forKey: appliedKey) || d.bool(forKey: legacyKey) else { return }
        restore()
    }

    // MARK: - CGS plumbing

    private func registerGroup(_ slot: CursorSlot, _ f: CursorFrames) {
        guard let ids = idGroups[slot], let reg = _reg, let set = _set, !f.frames.isEmpty else { return }
        let arr = f.frames as CFArray
        for id in ids {
            var seed: Int32 = 0
            _ = id.withCString { reg(cid, $0, true, true, f.size, f.hotspot, UInt(f.frames.count), f.frameDuration, arr, &seed) }
            var activate: Int32 = 0
            _ = id.withCString { set(cid, $0, &activate) }
        }
    }

    private func removeGroup(_ slot: CursorSlot) {
        guard let ids = idGroups[slot] else { return }
        for id in ids { _ = id.withCString { _remove?(cid, $0, false) } }
    }

    /// The Tahoe refresh dance. The critical, hard-won detail: the hardware cursor only
    /// re-uploads on a dock-cursor-override STATE TRANSITION — so we force one to the
    /// opposite value first, then to the target — followed by a cursor-scale bump and a
    /// reset to Arrow. Without the transition the registered image is stored but the
    /// on-screen cursor never changes.
    private func finalize(dockOverride target: Bool) {
        _dockOv?(cid, !target)
        _dockOv?(cid, target)
        if let get = _getScale, let set = _setScale {
            var scale: CGFloat = 1
            _ = get(cid, &scale)
            _ = set(cid, scale + 0.25)
            _ = set(cid, scale)
        }
        _ = _sysCur?(cid, 0)   // reset to Arrow
    }
}
