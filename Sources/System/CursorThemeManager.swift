import AppKit
import ImageIO

/// System-wide cursor theming via the private CoreGraphics (CGS) cursor API — the same
/// mechanism MaCursor uses. Two macOS-26 (Tahoe) essentials, without which nothing changes
/// on screen:
///   1. register each cursor under ALL of its aliases (e.g. the pointer is
///      `com.apple.coregraphics.Arrow`, `…ArrowS` and `com.apple.cursor.0`), and
///   2. force a refresh via a `CGSSetDockCursorOverride` STATE TRANSITION (+ a cursor-scale
///      bump + reset-to-Arrow); the old CoreCursor refresh hooks were removed and the
///      hardware cursor otherwise keeps the cached image.
///
/// The user's ORIGINAL cursors are captured once (via `CGSCopyRegisteredCursorImages` —
/// full image frames + size + hotspot + duration) before the first override and persisted
/// to Application Support, so they can always be restored exactly, even after a crash (a
/// leftover flag on the next launch triggers a restore).
enum CursorSlot: String, CaseIterable {
    case arrow, ibeam, wait, pointingHand, crosshair, move, notAllowed, help
    case resizeEW, resizeNS, resizeNWSE, resizeNESW
}

struct CursorFrames {
    /// One CGImage per scale rep. For animation this is a single VERTICAL sprite sheet
    /// (frames stacked top-to-bottom); `frameCount` tells CGS how to slice it. Images must
    /// be ~2× the point size (Retina density) or the private API stores but never displays
    /// them, and cropped to the artwork so they aren't tiny.
    let images: [CGImage]
    let frameCount: Int
    let size: CGSize        // per-frame logical size in POINTS
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
    private typealias CopyFn     = @convention(c) (Int32, UnsafePointer<CChar>, UnsafeMutablePointer<CGSize>, UnsafeMutablePointer<CGPoint>, UnsafeMutablePointer<Int>, UnsafeMutablePointer<CGFloat>, UnsafeMutablePointer<Unmanaged<CFArray>?>) -> Int32

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
    private lazy var _copy     = Self.sym("CGSCopyRegisteredCursorImages", CopyFn.self)

    var isSupported: Bool { _main != nil && _reg != nil && _set != nil && _dockOv != nil }
    private var cid: Int32 { _main?() ?? 0 }

    /// Every macOS identifier a logical slot maps to. On Tahoe a cursor is shown through
    /// several of these at once, so we register the same image under all of them.
    private let idGroups: [CursorSlot: [String]] = [
        .arrow:        ["com.apple.coregraphics.Arrow", "com.apple.coregraphics.ArrowS", "com.apple.cursor.0"],
        .ibeam:        ["com.apple.coregraphics.IBeam", "com.apple.coregraphics.IBeamS", "com.apple.cursor.1"],
        .wait:         ["com.apple.coregraphics.Wait", "com.apple.cursor.4"],
        .pointingHand: ["com.apple.coregraphics.PointingHand", "com.apple.cursor.13"],
        .crosshair:    ["com.apple.cursor.7", "com.apple.cursor.8", "com.apple.cursor.20"],
        .move:         ["com.apple.coregraphics.Move", "com.apple.cursor.39"],
        .notAllowed:   ["com.apple.coregraphics.NotAllowed", "com.apple.cursor.3"],
        .help:         ["com.apple.coregraphics.Help", "com.apple.cursor.40"],
        .resizeEW:     ["com.apple.coregraphics.ResizeLeftRight", "com.apple.cursor.19", "com.apple.coregraphics.WindowResizeEastWest", "com.apple.cursor.28"],
        .resizeNS:     ["com.apple.coregraphics.ResizeUpDown", "com.apple.cursor.23", "com.apple.coregraphics.WindowResizeNorthSouth", "com.apple.cursor.32"],
        .resizeNWSE:   ["com.apple.coregraphics.WindowResizeNorthwestSoutheast", "com.apple.cursor.34"],
        .resizeNESW:   ["com.apple.coregraphics.WindowResizeNortheastSouthwest", "com.apple.cursor.30"],
    ]

    private let d = UserDefaults.standard
    private let appliedKey = "cursorThemeApplied"
    private let snapKey = "cursorOriginalsCaptured"
    private let legacyKeys = ["cursorSnapshotTaken", "cursorThemeApplied"]

    private var backupDir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RetroMac/CursorBackup", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // MARK: - Public entry points (mirror AppearanceAdapter)

    func apply(for config: DockThemeConfig) {
        guard isSupported, AppSettings.shared.themeAdaptCursor,
              let set = Self.cursorSet(for: config.name) else { restore(); return }
        captureOriginalsIfNeeded()
        for (slot, frames) in set { registerGroup(slot, frames) }
        finalize()
        d.set(true, forKey: appliedKey)
        print("[Cursor] Applied \(set.count)-cursor set for \(config.name)")
    }

    /// Put the user's ORIGINAL cursors back by re-registering the captured images. Turning
    /// the override off doesn't reveal the built-ins on Tahoe, so restore re-registers the
    /// originals and keeps the override on (visually identical to before). Falls back to a
    /// drawn default arrow if nothing was captured.
    func restore() {
        guard isSupported, d.bool(forKey: appliedKey) || d.bool(forKey: snapKey) else { return }
        var restoredAny = false
        for slot in CursorSlot.allCases {
            guard let frames = loadCaptured(slot) else { continue }
            registerGroup(slot, frames)
            restoredAny = true
        }
        if !restoredAny, let fallback = Self.fallbackArrow() {
            registerGroup(.arrow, fallback)
        }
        finalize()
        d.removeObject(forKey: appliedKey)
        d.removeObject(forKey: snapKey)
        legacyKeys.forEach { d.removeObject(forKey: $0) }
        try? FileManager.default.removeItem(at: backupDir)
        print("[Cursor] Restored original cursors")
    }

    /// Crash / force-quit recovery.
    func restoreIfNeeded() {
        guard isSupported, d.bool(forKey: appliedKey) || legacyKeys.contains(where: { d.bool(forKey: $0) }) else { return }
        restore()
    }

    // MARK: - CGS plumbing

    private func registerGroup(_ slot: CursorSlot, _ f: CursorFrames) {
        guard let ids = idGroups[slot], let reg = _reg, let set = _set, !f.images.isEmpty else { return }
        let arr = f.images as CFArray
        for id in ids {
            var seed: Int32 = 0
            _ = id.withCString { reg(cid, $0, true, true, f.size, f.hotspot, UInt(f.frameCount), f.frameDuration, arr, &seed) }
            var activate: Int32 = 0
            _ = id.withCString { set(cid, $0, &activate) }
        }
    }

    /// The Tahoe refresh dance. The hard-won detail: the hardware cursor only re-uploads on
    /// a dock-cursor-override STATE TRANSITION, so we force one (false→true) and finish with
    /// a scale bump + reset-to-Arrow. The override is left ON — that is what makes any
    /// registered image (themed OR the restored originals) actually display.
    private func finalize() {
        _dockOv?(cid, false)
        _dockOv?(cid, true)
        if let get = _getScale, let set = _setScale {
            var scale: CGFloat = 1
            _ = get(cid, &scale)
            _ = set(cid, scale + 0.25)
            _ = set(cid, scale)
        }
        _ = _sysCur?(cid, 0)
    }

    // MARK: - Capture / persist the user's real cursors (once, before first override)

    private func captureOriginalsIfNeeded() {
        guard !d.bool(forKey: snapKey), let copy = _copy else { return }
        for slot in CursorSlot.allCases {
            guard let ids = idGroups[slot] else { continue }
            for id in ids {
                var size = CGSize.zero, hot = CGPoint.zero, count = 0, dur: CGFloat = 0
                var arr: Unmanaged<CFArray>?
                let err = id.withCString { copy(cid, $0, &size, &hot, &count, &dur, &arr) }
                let images = (arr?.takeRetainedValue() as? [CGImage]) ?? []
                guard err == 0, !images.isEmpty, size.width > 0 else { continue }
                for (i, img) in images.enumerated() { savePNG(img, "\(slot.rawValue)_f\(i)") }
                d.set([Double(size.width), Double(size.height)], forKey: "cursorCapSize_\(slot.rawValue)")
                d.set([Double(hot.x), Double(hot.y)], forKey: "cursorCapHot_\(slot.rawValue)")
                d.set([Double(dur)], forKey: "cursorCapDur_\(slot.rawValue)")
                d.set(images.count, forKey: "cursorCapImages_\(slot.rawValue)")   // scale reps
                d.set(max(1, count), forKey: "cursorCapFrames_\(slot.rawValue)")  // real frame count
                break
            }
        }
        d.set(true, forKey: snapKey)
        d.synchronize()
    }

    private func loadCaptured(_ slot: CursorSlot) -> CursorFrames? {
        let imgCount = d.integer(forKey: "cursorCapImages_\(slot.rawValue)")
        guard imgCount > 0,
              let sz = d.array(forKey: "cursorCapSize_\(slot.rawValue)") as? [Double], sz.count == 2 else { return nil }
        var images: [CGImage] = []
        for i in 0..<imgCount { if let img = loadPNG("\(slot.rawValue)_f\(i)") { images.append(img) } }
        guard !images.isEmpty else { return nil }
        let fc = max(1, d.integer(forKey: "cursorCapFrames_\(slot.rawValue)"))
        let hot = (d.array(forKey: "cursorCapHot_\(slot.rawValue)") as? [Double]) ?? [0, 0]
        let dur = (d.array(forKey: "cursorCapDur_\(slot.rawValue)") as? [Double])?.first ?? 0
        return CursorFrames(images: images, frameCount: fc, size: CGSize(width: sz[0], height: sz[1]),
                            hotspot: CGPoint(x: hot.first ?? 0, y: hot.count > 1 ? hot[1] : 0),
                            frameDuration: CGFloat(dur))
    }

    // MARK: - PNG helpers

    private func savePNG(_ img: CGImage, _ name: String) {
        let url = backupDir.appendingPathComponent("\(name).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
    private func loadPNG(_ name: String) -> CGImage? {
        let url = backupDir.appendingPathComponent("\(name).png")
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
