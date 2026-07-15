import AppKit

// MARK: - Shared retro window-chrome model
//
// A single value type (`ChromeStyle`) describes a theme's title-bar metrics + look, and a
// small `ChromeButtonTracker` value gives every native chrome view uniform hover/pressed
// state handling. This replaces the per-view hardcoding in `WebAppChromeView` and the
// `BeOSTVChrome` views, and it is where the fidelity work (XP.css glyphs, classic.css
// bevel values) lands.
//
// The model is deliberately Codable-ready but NOT yet driven by `theme.json` — the factory
// below returns hardcoded styles keyed off `RetroFrameTheme.key()`. See the documented hook
// on `ChromeStyle` for the future theme-bundle path (mirrors `DockThemeConfig`).

/// Which window control a hit region / glyph represents.
enum ChromeButtonKind {
    case close, minimize, maximize, restore, collapse, zoom, back, forward
}

/// Interaction state a button renders in.
enum ChromeButtonState {
    case normal, hovered, pressed, disabled
}

/// Side the control cluster sits on. Classic Mac = close LEFT; Windows = RIGHT.
enum ChromeButtonSide {
    case left, right
}

/// How a button's glyph is produced.
enum ChromeButtonRender: Equatable {
    /// Hand-drawn via Core Graphics (Win98 bevel, Platinum box).
    case native
    /// Pre-rendered PNGs in `Resources/Chrome/<dir>/`, e.g. `close.png`, `close-hover.png`,
    /// `close-active.png` (+ optional `-disabled`, `@2x`). Resolved by `ChromeAssets`.
    case asset(dir: String, base: String)
}

/// One caption button's identity + look. Metrics (rects) are resolved by the view; this is
/// the *default composition* for a style. A view may override interactivity when it registers
/// hit regions (e.g. the TV XP chrome wires up functional min/max, while the WebApp XP chrome
/// keeps them decorative).
struct ChromeButton {
    var kind: ChromeButtonKind
    /// `false` → purely decorative (Win98/XP min/max on a fixed-size window): no hit region,
    /// rendered muted so it does not read as clickable.
    var interactive: Bool
    var render: ChromeButtonRender

    init(_ kind: ChromeButtonKind, interactive: Bool = true, render: ChromeButtonRender = .native) {
        self.kind = kind
        self.interactive = interactive
        self.render = render
    }
}

/// A gradient as ordered (color, location) stops, drawn at `angle` degrees.
struct ChromeGradient {
    var stops: [(color: NSColor, location: CGFloat)]
    var angle: CGFloat = -90

    func nsGradient() -> NSGradient? {
        let colors = stops.map { $0.color }
        let locations = stops.map { $0.location }
        return NSGradient(colors: colors, atLocations: locations, colorSpace: .deviceRGB)
    }

    func draw(in rect: NSRect) {
        nsGradient()?.draw(in: NSBezierPath(rect: rect), angle: angle)
    }

    func draw(in path: NSBezierPath) {
        nsGradient()?.draw(in: path, angle: angle)
    }
}

/// Per-theme title-bar metrics + look. One value describes an entire chrome family so the
/// WebApp window and the TV window finally share identical numbers.
struct ChromeStyle {
    // Metrics
    var titleHeight: CGFloat
    var windowBorder: CGFloat          // XP 4, Win98 pad 4, Mac classic 0
    var buttonSize: NSSize             // XP 21×19, Win98 20×18, Mac classic 11×11
    var buttonSpacing: CGFloat         // gap between buttons in the cluster
    var buttonInset: CGFloat           // gap from window edge to the first (outermost) button
    var cornerRadius: CGFloat          // XP 8, others 0
    var buttonSide: ChromeButtonSide

    // Title text
    var titleFont: NSFont
    var titleColor: NSColor
    var titleShadow: Bool
    var titleAlignment: NSTextAlignment    // Mac classic = .center

    // Surfaces
    var windowFill: NSColor
    var captionGradient: ChromeGradient?   // nil → flat `captionFill`
    var captionFill: NSColor?

    /// Buttons in cluster order, outermost (window edge) → inward. Back/forward nav is handled
    /// separately by the view.
    var buttons: [ChromeButton]

    // Hook for the future theme-bundle path — build a style from a decoded theme.json blob.
    // Intentionally unused today; the factory below is the source of truth.
    // init?(config: ChromeStyleConfig, themeBundle: URL) { ... }
}

// MARK: - Factory (RetroFrameTheme.key() → ChromeStyle)

/// Central map from the active theme key to a concrete `ChromeStyle`. Hardcoded for now.
/// Returns `nil` for keys without a modelled style so callers fall back to their legacy
/// draw path.
enum ChromeStyleFactory {

    static func style(forThemeKey key: String) -> ChromeStyle? {
        switch key {
        case "winxp":  return xp()
        case "macos9": return macClassic()   // System 6 + Mac OS 9 share the Platinum chrome
        case "win98":  return win98()
        default:       return nil
        }
    }

    // Values lifted verbatim from `WebAppChromeView.drawXP` + `WinXPTVChromeView`.
    static func xp() -> ChromeStyle {
        let caption = ChromeGradient(stops: [
            (NSColor(srgbRed: 0.27, green: 0.60, blue: 0.99, alpha: 1), 0.0),   // #459AFD bright top
            (NSColor(srgbRed: 0.11, green: 0.47, blue: 0.96, alpha: 1), 0.08),  // gloss
            (NSColor(srgbRed: 0.04, green: 0.38, blue: 0.93, alpha: 1), 0.42),
            (NSColor(srgbRed: 0.02, green: 0.31, blue: 0.86, alpha: 1), 0.50),  // dip
            (NSColor(srgbRed: 0.06, green: 0.27, blue: 0.83, alpha: 1), 0.55),
            (NSColor(srgbRed: 0.10, green: 0.33, blue: 0.88, alpha: 1), 1.0),   // bottom lift
        ])
        let font = NSFont(name: "Trebuchet MS Bold", size: 13) ?? .boldSystemFont(ofSize: 13)
        return ChromeStyle(
            titleHeight: 30, windowBorder: 4,
            buttonSize: NSSize(width: 21, height: 21), buttonSpacing: 2, buttonInset: 6,
            cornerRadius: 8, buttonSide: .right,
            titleFont: font, titleColor: .white, titleShadow: true, titleAlignment: .left,
            windowFill: NSColor(srgbRed: 0.012, green: 0.31, blue: 0.78, alpha: 1),  // #0250C7
            captionGradient: caption, captionFill: nil,
            buttons: [
                // Cluster order right→inward is [close][max][min]; store outermost first.
                ChromeButton(.close, interactive: true,
                             render: .asset(dir: "winxp", base: "close")),
                ChromeButton(.maximize, interactive: false,
                             render: .asset(dir: "winxp", base: "max")),
                ChromeButton(.minimize, interactive: false,
                             render: .asset(dir: "winxp", base: "min")),
            ])
    }

    // Values lifted from `Mac9TVChromeView` (Platinum). classic.css / ChicagoFLF inform the
    // reference look; no Apple-copyrighted pattern bitmaps are used — the pinstripe is drawn.
    static func macClassic() -> ChromeStyle {
        let font = NSFont(name: "Charcoal", size: 12)
            ?? NSFont(name: "ChicagoFLF", size: 12) ?? .boldSystemFont(ofSize: 12)
        return ChromeStyle(
            titleHeight: 22, windowBorder: 0,
            buttonSize: NSSize(width: 11, height: 11), buttonSpacing: 5, buttonInset: 8,
            cornerRadius: 0, buttonSide: .left,
            titleFont: font, titleColor: .black, titleShadow: false, titleAlignment: .center,
            windowFill: NSColor(calibratedWhite: 0.953, alpha: 1),   // #F3F3F3 platinum plate
            captionGradient: nil, captionFill: NSColor(calibratedWhite: 0.953, alpha: 1),
            buttons: [
                // Close sits alone on the LEFT; collapse + zoom cluster on the right (handled
                // by the view's own layout). Listed here for identity/render.
                ChromeButton(.close, interactive: true, render: .native),
                ChromeButton(.collapse, interactive: true, render: .native),
                ChromeButton(.zoom, interactive: true, render: .native),
            ])
    }

    // Values lifted from `WebAppChromeView.drawWin98`.
    static func win98() -> ChromeStyle {
        let caption = ChromeGradient(stops: [
            (NSColor(srgbRed: 0, green: 0, blue: 0.482, alpha: 1), 0.0),      // #00007B
            (NSColor(srgbRed: 0.063, green: 0.522, blue: 0.824, alpha: 1), 1.0),  // #1085D2
        ], angle: 0)
        let font = NSFont(name: "Tahoma-Bold", size: 12) ?? .boldSystemFont(ofSize: 12)
        return ChromeStyle(
            titleHeight: 22, windowBorder: 4,
            buttonSize: NSSize(width: 20, height: 18), buttonSpacing: 0, buttonInset: 2,
            cornerRadius: 0, buttonSide: .right,
            titleFont: font, titleColor: .white, titleShadow: false, titleAlignment: .left,
            windowFill: NSColor(srgbRed: 0.769, green: 0.769, blue: 0.769, alpha: 1),  // #C4C4C4
            captionGradient: caption, captionFill: nil,
            buttons: [
                ChromeButton(.close, interactive: true, render: .native),
                ChromeButton(.maximize, interactive: false, render: .native),
                ChromeButton(.minimize, interactive: false, render: .native),
            ])
    }
}

// MARK: - Interaction tracker

/// Tracks hover/press across a set of identified hit regions. A chrome view owns one, feeds it
/// mouse events, and asks it which `ChromeButtonState` to draw each button in. Kept as a value
/// helper (not a base class) because the views differ in coordinate flipping.
struct ChromeButtonTracker {
    private struct Region { let kind: ChromeButtonKind; let rect: CGRect; let interactive: Bool }
    private var regions: [Region] = []

    private(set) var hovered: ChromeButtonKind?
    private(set) var pressed: ChromeButtonKind?

    /// Clear regions before a fresh layout pass (call at the top of `draw`/layout).
    mutating func reset() { regions.removeAll(keepingCapacity: true) }

    mutating func add(_ kind: ChromeButtonKind, _ rect: CGRect, interactive: Bool = true) {
        regions.append(Region(kind: kind, rect: rect, interactive: interactive))
    }

    func state(for kind: ChromeButtonKind) -> ChromeButtonState {
        if let r = regions.first(where: { $0.kind == kind }), !r.interactive { return .disabled }
        if pressed == kind, hovered == kind { return .pressed }
        if pressed == nil, hovered == kind { return .hovered }
        return .normal
    }

    /// Kind under `p` among interactive regions, else nil.
    func hitTest(_ p: CGPoint) -> ChromeButtonKind? {
        for r in regions where r.interactive && r.rect.contains(p) { return r.kind }
        return nil
    }

    // The mutating event helpers return `true` when a redraw is needed.

    mutating func mouseMoved(to p: CGPoint) -> Bool {
        guard pressed == nil else { return false }
        let h = hitTest(p)
        if h != hovered { hovered = h; return true }
        return false
    }

    mutating func mouseDown(at p: CGPoint) -> Bool {
        if let k = hitTest(p) { pressed = k; hovered = k; return true }
        return false
    }

    mutating func mouseDragged(to p: CGPoint) -> Bool {
        guard pressed != nil else { return false }
        let inside = hitTest(p) == pressed
        let newHover: ChromeButtonKind? = inside ? pressed : nil
        if newHover != hovered { hovered = newHover; return true }
        return false
    }

    /// Returns the kind to FIRE (released inside the same pressed button) and whether to redraw.
    mutating func mouseUp(at p: CGPoint) -> (fire: ChromeButtonKind?, needsRedraw: Bool) {
        let fired: ChromeButtonKind? = (pressed != nil && hitTest(p) == pressed) ? pressed : nil
        let hadState = pressed != nil || hovered != nil
        pressed = nil
        hovered = hitTest(p)
        return (fired, hadState || hovered != nil)
    }

    mutating func mouseExited() -> Bool {
        if hovered != nil { hovered = nil; return true }
        return false
    }
}

// MARK: - Asset loader

/// Resolves + caches pre-rendered chrome glyph PNGs from `Contents/Resources/Chrome/<dir>/`.
/// Falls back to the `.normal` variant, then to `nil` (caller then hand-draws the glyph), so
/// the app degrades gracefully if assets are absent.
enum ChromeAssets {
    private static var cache: [String: NSImage] = [:]

    static func image(dir: String, base: String, state: ChromeButtonState) -> NSImage? {
        let suffix: String
        switch state {
        case .normal:   suffix = ""
        case .hovered:  suffix = "-hover"
        case .pressed:  suffix = "-active"
        case .disabled: suffix = "-disabled"
        }
        let name = base + suffix
        let key = "\(dir)/\(name)"
        if let cached = cache[key] { return cached }
        guard let res = Bundle.main.resourceURL else { return nil }
        let dirURL = res.appendingPathComponent("Chrome/\(dir)")

        // Loose PNGs don't auto-associate their @2x sibling (unlike NSImage(named:) in a catalog),
        // so build the image from the 1x rep at point-size, then attach @2x for Retina crispness.
        guard let rep1 = NSImageRep(contentsOf: dirURL.appendingPathComponent("\(name).png")) else {
            if state != .normal { return image(dir: dir, base: base, state: .normal) }  // fall back
            return nil
        }
        let pointSize = NSSize(width: rep1.pixelsWide, height: rep1.pixelsHigh)
        let img = NSImage(size: pointSize)
        rep1.size = pointSize
        img.addRepresentation(rep1)
        if let rep2 = NSImageRep(contentsOf: dirURL.appendingPathComponent("\(name)@2x.png")) {
            rep2.size = pointSize
            img.addRepresentation(rep2)
        }
        cache[key] = img
        return img
    }
}
