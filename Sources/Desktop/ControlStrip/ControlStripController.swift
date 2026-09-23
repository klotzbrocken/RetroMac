import AppKit

/// The Mac OS 9 Control Strip as it was: a Platinum ledge along the left (or right) edge of
/// the screen holding system modules — network, sharing, colours, resolution, volume,
/// battery, mirroring — not programs. The tab at the screen edge collapses it and drags it
/// up and down; the size box at the other end sets how much of it shows; the arrows scroll
/// the modules that do not fit. Shown by the "Mac OS 9 (authentic)" theme
/// (`dockStyle: "controlStripModules"`), which has no dock at all.
final class ControlStripController {

    static let shared = ControlStripController()

    private var panel: NSPanel?
    private var view: ControlStripView?
    private var tickTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastRefresh: [String: Date] = [:]
    /// Every module RetroMac has, by id. A theme takes the ones it had (`dock.stripModules`),
    /// in its own order; without the key it gets the Mac OS 9 set below, in the order a fresh
    /// Mac OS 9 strip had them (alphabetical by module name).
    static func makeModule(_ id: String) -> ControlStripModule? {
        switch id {
        case "network", "appletalk": return NetworkModule()
        case "battery":       return BatteryModule()
        case "mediabay":      return MediaBayModule()
        case "sharing":       return SharingModule()
        case "keychain":      return KeychainModule()
        case "colours":       return ColourDepthModule()
        case "resolution":    return ResolutionModule()
        case "printer":       return PrinterModule()
        case "volume":        return VolumeModule()
        case "soundsource":   return SoundSourceModule()
        case "mirroring":     return MirroringModule()
        case "hdspindown":    return HDSpinDownModule()
        case "power":         return PowerModule()
        case "sleep":         return SleepNowModule()
        default:              return nil
        }
    }
    static let macOS9Order = ["network", "battery", "mediabay", "sharing", "keychain",
                              "colours", "resolution", "printer", "volume", "soundsource", "mirroring"]
    private(set) var modules: [ControlStripModule] = macOS9Order.compactMap { makeModule($0) }

    private init() {}

    func update() {
        guard AppSettings.shared.dockEnabled, let theme = ThemeManager.shared.activeTheme, theme.config.isControlStripModules else {
            hide(); return
        }
        show(theme: theme)
    }

    func hide() {
        tickTimer?.invalidate(); tickTimer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        revertPanel?.orderOut(nil); revertPanel = nil
        revertTimer?.invalidate(); revertTimer = nil
        panel?.orderOut(nil)
        panel = nil
        view = nil
    }

    /// The modules the theme asks for, in its order; an unknown id is skipped.
    private func adoptModules(of theme: ThemeBundle) {
        let ids = theme.config.stripModuleIDs ?? Self.macOS9Order
        let built = ids.compactMap { Self.makeModule($0) }
        modules = built.isEmpty ? Self.macOS9Order.compactMap { Self.makeModule($0) } : built
    }

    private func show(theme: ThemeBundle) {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: ControlStripView.height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = NSWindow.Level(rawValue: 24)   // with the dock
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.hidesOnDeactivate = false
            adoptModules(of: theme)
            let v = ControlStripView(theme: theme, controller: self)
            p.contentView = v
            panel = p
            view = v
            applyLevel()
            (modules.first { $0.id == "resolution" } as? ResolutionModule)?.onSwitched = { [weak self] before in self?.offerRevert(to: before) }
        }
        for m in modules { m.refresh(); lastRefresh[m.id] = Date() }
        layout()
        panel?.orderFrontRegardless()
        if tickTimer == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            tickTimer = t
        }
        if observers.isEmpty {
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                for m in self.modules { m.refresh() }
                self.layout()
            })
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.updateVisibilityForSpace()
            })
        }
    }

    /// Under the desktop-scope shader (Live Wallpaper Plus) the strip goes below the
    /// application windows, into the band the shader captures, so it is drawn through the
    /// CRT like the desktop and the dock are — otherwise it sat on top of the effect, sharp.
    private(set) var loweredForDesktopShader = false
    func setLoweredForDesktopShader(_ lowered: Bool) {
        guard loweredForDesktopShader != lowered else { return }
        loweredForDesktopShader = lowered
        applyLevel()
    }
    private func applyLevel() {
        panel?.level = NSWindow.Level(rawValue: loweredForDesktopShader ? Int(CGWindowLevelForKey(.normalWindow)) - 3 : 24)
    }

    /// The screen the strip lives on: the primary display.
    var screen: NSScreen? { NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first }
    private var screenKey: String {
        let id = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
        return String(id)
    }

    /// Modules that have something to show right now, in the user's order (Option-drag), the
    /// default order for the rest.
    var available: [ControlStripModule] {
        let order = AppSettings.shared.controlStripModuleOrder
        let sorted = modules.sorted { a, b in
            let ia = order.firstIndex(of: a.id) ?? (order.count + (modules.firstIndex { $0 === a } ?? 0))
            let ib = order.firstIndex(of: b.id) ?? (order.count + (modules.firstIndex { $0 === b } ?? 0))
            return ia < ib
        }
        return sorted.filter { $0.isAvailable }
    }

    /// Option-drag of a module: it goes where it was dropped, before the module under the pointer.
    func move(_ module: ControlStripModule, before target: ControlStripModule?) {
        var order = available.map { $0.id }
        order.removeAll { $0 == module.id }
        if let target, let i = order.firstIndex(of: target.id) { order.insert(module.id, at: i) } else { order.append(module.id) }
        AppSettings.shared.controlStripModuleOrder = order
        layout()
    }

    /// Option-drag of the strip: to either edge, and up and down it.
    func moved(toScreenPoint p: NSPoint, dy: CGFloat) {
        guard let screen else { return }
        let side = p.x < screen.frame.midX ? "left" : "right"
        if AppSettings.shared.controlStripSide != side { AppSettings.shared.controlStripSide = side }
        dragged(by: dy)
    }

    func layout() {
        guard let panel, let view, let screen else { return }
        if let res = modules.first(where: { $0.id == "resolution" }) as? ResolutionModule,
           let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            res.display = id
        }
        let width = ControlStripView.windowWidth(view.preferredWidth(collapsed: AppSettings.shared.controlStripCollapsed,
                                                                     visible: CGFloat(AppSettings.shared.controlStripVisibleWidth),
                                                                     modules: available))
        let right = AppSettings.shared.controlStripSide == "right"
        let x = right ? screen.frame.maxX - width : screen.frame.minX
        let y = Self.clampedY(offset: CGFloat(AppSettings.shared.controlStripOffsets[screenKey] ?? 0), screen: screen)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: ControlStripView.height), display: true)
        view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: ControlStripView.height))
        view.mirrored = right
        view.needsDisplay = true
    }

    /// The strip's bottom edge: `offset` above the screen's bottom, kept on the visible screen.
    static func clampedY(offset: CGFloat, screen: NSScreen) -> CGFloat {
        let vf = screen.visibleFrame
        return min(max(screen.frame.minY + offset, vf.minY), vf.maxY - ControlStripView.height)
    }

    // MARK: Interaction (from the view)

    /// The tab was clicked: the strip rolls in or out, the way it did — a third of a second,
    /// the modules sliding out from behind the tab (or back under it), not a cut.
    func toggleCollapsed() {
        guard let panel, let view, let screen, rollTimer == nil else { return }
        let right = AppSettings.shared.controlStripSide == "right"
        let collapsing = !AppSettings.shared.controlStripCollapsed
        if !collapsing { AppSettings.shared.controlStripCollapsed = false }   // draw the full strip while it unrolls
        let full = ControlStripView.windowWidth(view.preferredWidth(collapsed: false,
                                                                    visible: CGFloat(AppSettings.shared.controlStripVisibleWidth), modules: available))
        let tab = ControlStripView.windowWidth(view.tabWidth)
        let from = collapsing ? full : tab, to = collapsing ? tab : full
        let y = panel.frame.minY
        // The view keeps the full layout; the window is the roller blind over it.
        view.frame = NSRect(x: 0, y: 0, width: full, height: ControlStripView.height)
        view.mirrored = right
        view.needsDisplay = true
        let start = CACurrentMediaTime()
        let duration = 0.35
        func step(_ w: CGFloat) {
            let x = right ? screen.frame.maxX - w : screen.frame.minX
            panel.setFrame(NSRect(x: x, y: y, width: w, height: ControlStripView.height), display: false)
            view.frame.origin.x = right ? w - full : 0   // right edge: the tab end stays at the edge
        }
        step(from)
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            let p = min(1, (CACurrentMediaTime() - start) / duration)
            let e = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2   // ease in, ease out
            step(from + (to - from) * CGFloat(e))
            if p >= 1 {
                timer.invalidate()
                self?.rollTimer = nil
                if collapsing { AppSettings.shared.controlStripCollapsed = true }
                self?.layout()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        rollTimer = t
    }
    private var rollTimer: Timer?

    func dragged(by dy: CGFloat) {
        guard let screen else { return }
        let now = CGFloat(AppSettings.shared.controlStripOffsets[screenKey] ?? 0)
        let wanted = now + dy
        let clamped = Self.clampedY(offset: wanted, screen: screen) - screen.frame.minY
        AppSettings.shared.controlStripOffsets[screenKey] = Double(clamped)
        layout()
    }

    func resized(to visibleWidth: CGFloat) {
        guard let view else { return }
        let total = view.modulesWidth(available)
        let first = available.first?.width ?? 20
        let clamped = min(max(visibleWidth, first), total)
        AppSettings.shared.controlStripVisibleWidth = clamped >= total ? 0 : Double(clamped)
        layout()
    }

    func scroll(by delta: Int) {
        guard let view else { return }
        view.scrollIndex = max(0, min(max(0, available.count - 1), view.scrollIndex + delta))
        layout()
    }

    private weak var menuModule: ControlStripModule?

    func activate(_ module: ControlStripModule, anchor: NSRect) {
        guard let view, let window = view.window else { return }
        let onScreen = window.convertToScreen(view.convert(anchor, to: nil))
        // A second click on the module whose menu is open closes it.
        if PlatinumMenuController.shared.isOpen, menuModule === module {
            PlatinumMenuController.shared.dismissAll(); menuModule = nil; return
        }
        menuModule = nil
        if let menu = module.menu() {
            // A module with one thing to do does it; only a choice gets a menu.
            let actions = menu.items.filter { $0.isEnabled && $0.action != nil && !$0.isSeparatorItem }
            if actions.count == 1, let only = actions.first, let action = only.action {
                NSApp.sendAction(action, to: only.target, from: only)
                return
            }
            // The module's menu, drawn Platinum; from the bottom of the screen it opens upward.
            PlatinumMenuController.shared.ignoreClickWindow = window
            PlatinumMenuController.shared.show(PlatinumMenuItem.rows(of: menu), below: onScreen)
            menuModule = module
        } else {
            module.click(anchor: onScreen)
        }
    }

    private func tick() {
        var changed = false
        for m in modules where m.refreshInterval > 0 {
            if Date().timeIntervalSince(lastRefresh[m.id] ?? .distantPast) >= m.refreshInterval {
                m.refresh(); lastRefresh[m.id] = Date(); changed = true
            }
        }
        if changed { layout() }
    }

    private func updateVisibilityForSpace() {
        // A full-screen app has its own Space; the strip stays off it.
        guard let panel else { return }
        if !panel.isOnActiveSpace { panel.alphaValue = 0 } else { panel.alphaValue = 1 }
    }

    // MARK: The resolution question

    private var revertPanel: NSPanel?
    private var revertTimer: Timer?

    /// After a resolution switch: keep it, or go back — and go back on its own after 15 s,
    /// the way the Monitors control panel did, in case the new mode shows nothing.
    private func offerRevert(to before: CGDisplayMode) {
        revertPanel?.orderOut(nil); revertTimer?.invalidate()
        guard let screen else { return }
        let w: CGFloat = 320, h: CGFloat = 96
        let p = NSPanel(contentRect: NSRect(x: screen.frame.midX - w / 2, y: screen.frame.midY - h / 2, width: w, height: h),
                        styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        p.title = "Monitor"
        p.level = .floating
        let label = NSTextField(labelWithString: "Keep the new resolution?")
        label.frame = NSRect(x: 20, y: 56, width: 280, height: 20)
        let count = NSTextField(labelWithString: "Reverting in 15 seconds.")
        count.frame = NSRect(x: 20, y: 36, width: 280, height: 18)
        count.textColor = .secondaryLabelColor
        let keep = NSButton(title: "Keep", target: self, action: #selector(keepResolution))
        keep.frame = NSRect(x: 220, y: 8, width: 84, height: 26)
        keep.keyEquivalent = "\r"
        let revert = NSButton(title: "Revert", target: self, action: #selector(revertResolution))
        revert.frame = NSRect(x: 130, y: 8, width: 84, height: 26)
        p.contentView?.addSubview(label); p.contentView?.addSubview(count)
        p.contentView?.addSubview(keep); p.contentView?.addSubview(revert)
        p.orderFrontRegardless()
        revertPanel = p
        revertMode = before
        var left = 15
        revertTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            left -= 1
            count.stringValue = "Reverting in \(left) seconds."
            if left <= 0 { t.invalidate(); self?.revertResolution() }
        }
    }
    private var revertMode: CGDisplayMode?

    @objc private func keepResolution() {
        revertTimer?.invalidate(); revertTimer = nil
        revertPanel?.orderOut(nil); revertPanel = nil
        revertMode = nil
    }

    @objc private func revertResolution() {
        revertTimer?.invalidate(); revertTimer = nil
        revertPanel?.orderOut(nil); revertPanel = nil
        if let mode = revertMode, let res = modules.first(where: { $0.id == "resolution" }) as? ResolutionModule {
            _ = ResolutionModule.set(mode, on: res.display)
        }
        revertMode = nil
    }
}

// MARK: - The view

final class ControlStripView: NSView {
    /// The strip's size: 1× is the 24 pt of a 1× screen, 1.5× (the default, 36 pt) and 2× are
    /// Settings' Medium and Large. Half steps only: on a Retina screen every 1× pixel is then
    /// a whole number of device pixels, and the pixel art stays pixel art. Every measure below
    /// is in 1× units; the view scales its drawing and divides the mouse by `scale`.
    static var scale: CGFloat { Self.scale(for: AppSettings.shared.controlStripScale) }
    static func scale(for setting: Double) -> CGFloat { CGFloat(min(2, max(1, (setting * 2).rounded() / 2))) }
    static let baseHeight: CGFloat = 24
    static var height: CGFloat { baseHeight * scale }
    static let scrollCell: CGFloat = 12
    static let groove: CGFloat = 2

    private unowned let controller: ControlStripController
    private let tabImage: NSImage?
    private let sizeBoxImage: NSImage?
    /// The theme's own pictures for modules (`icons/strip-<id>.png`, 32 px for the 2× strip) and
    /// for the scroll arrows; a module without one draws its built-in pixel art.
    private let pictures: [String: NSImage]
    private let arrowLeft: NSImage?
    private let arrowRight: NSImage?
    /// Every module ends in the small black triangle the originals had; this is its room.
    static let triangleRoom: CGFloat = 8
    var mirrored = false          // right edge: the tab is on the right, everything reads mirrored
    var scrollIndex = 0
    /// System 7.1 (authentic) (`menuBar.palette: "mac256"`): the System 7.5 colour strip,
    /// drawn by `drawPowerBook()` from the original's pixels.
    let mono: Bool

    override var isFlipped: Bool { true }

    init(theme: ThemeBundle, controller: ControlStripController) {
        self.controller = controller
        let isMono = theme.config.hasMac256Palette
        mono = isMono
        // The System 7 strip draws its ends, arrows and pictures itself (`System7Strip`).
        let bit: (NSImage?) -> NSImage? = { img in isMono ? nil : img }
        tabImage = bit(theme.iconResource("controlstrip-left.png").flatMap { NSImage(contentsOf: $0) })
        sizeBoxImage = bit(theme.iconResource("controlstrip-right.png").flatMap { NSImage(contentsOf: $0) })
        var pics: [String: NSImage] = [:]
        for m in controller.modules {
            if !isMono, let u = theme.iconResource("strip-\(m.id).png"), let i = NSImage(contentsOf: u) { pics[m.id] = i }
        }
        pictures = pics
        arrowLeft = bit(theme.iconResource("strip-arrow-left.png").flatMap { NSImage(contentsOf: $0) })
        arrowRight = bit(theme.iconResource("strip-arrow-right.png").flatMap { NSImage(contentsOf: $0) })
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: Self.height))
    }
    required init?(coder: NSCoder) { fatalError() }

    private func capWidth(_ img: NSImage?, fallback: CGFloat) -> CGFloat {
        guard let img, img.size.height > 0 else { return fallback }
        return (img.size.width / img.size.height * Self.baseHeight).rounded()
    }
    /// The System 7 strip draws its ends itself (`System7Strip`): the close box at the left
    /// end, the tab at the right — and collapsed, the tab alone at the edge. Its pieces carry
    /// their own black line, so there is no groove between them.
    var tabWidth: CGFloat { mono ? CGFloat(collapsed ? System7Strip.tabWidth : System7Strip.endWidth) : capWidth(tabImage, fallback: 16) }
    var sizeBoxWidth: CGFloat { mono ? CGFloat(System7Strip.tabWidth) : capWidth(sizeBoxImage, fallback: 19) }
    private var groove: CGFloat { mono ? 0 : Self.groove }
    private var scrollCell: CGFloat { mono ? CGFloat(System7Strip.endWidth) : Self.scrollCell }

    /// A module's cell: its own width and the triangle's room; on the System 7 strip, the
    /// original's 30 px button and its line.
    func cell(_ m: ControlStripModule) -> CGFloat {
        mono ? CGFloat(System7Strip.cellWidth) : m.width + Self.triangleRoom
    }
    func modulesWidth(_ modules: [ControlStripModule]) -> CGFloat {
        modules.reduce(0) { $0 + cell($1) } + CGFloat(max(0, modules.count - 1)) * groove
    }

    /// Window width for a state: the tab alone when collapsed; otherwise tab, arrows, the
    /// visible part of the modules, and the size box.
    func preferredWidth(collapsed: Bool, visible: CGFloat, modules: [ControlStripModule]) -> CGFloat {
        if collapsed { return tabWidth }
        let all = modulesWidth(modules)
        let shown = visible > 0 ? min(visible, all) : all
        return tabWidth + scrollCell + groove + shown + groove + scrollCell + sizeBoxWidth
    }
    /// Window width in points for a 1× layout width.
    static func windowWidth(_ base: CGFloat) -> CGFloat { base * scale }
    /// The 1× bounds the layout works in.
    private var base: NSRect { NSRect(x: 0, y: 0, width: bounds.width / Self.scale, height: Self.baseHeight) }

    // Regions, in unmirrored (tab on the left) coordinates; `x(_:)` mirrors them.
    private func x(_ r: NSRect) -> NSRect { mirrored ? NSRect(x: base.width - r.maxX, y: r.minY, width: r.width, height: r.height) : r }
    private var collapsed: Bool { AppSettings.shared.controlStripCollapsed }
    private var tabRect: NSRect { x(NSRect(x: 0, y: 0, width: tabWidth, height: Self.baseHeight)) }
    private var leftArrowRect: NSRect { x(NSRect(x: tabWidth, y: 0, width: scrollCell, height: Self.baseHeight)) }
    private var moduleArea: NSRect {
        let start = tabWidth + scrollCell + groove
        let end = base.width - sizeBoxWidth - scrollCell - groove
        return x(NSRect(x: start, y: 0, width: max(0, end - start), height: Self.baseHeight))
    }
    private var rightArrowRect: NSRect { x(NSRect(x: base.width - sizeBoxWidth - scrollCell, y: 0, width: scrollCell, height: Self.baseHeight)) }
    private var sizeBoxRect: NSRect { x(NSRect(x: base.width - sizeBoxWidth, y: 0, width: sizeBoxWidth, height: Self.baseHeight)) }

    /// The modules on show, with their cells, from the scroll index on until the area is full.
    private func placedModules() -> [(ControlStripModule, NSRect)] {
        let mods = controller.available
        var out: [(ControlStripModule, NSRect)] = []
        let area = moduleArea
        var cursor: CGFloat = 0
        for m in mods.dropFirst(min(scrollIndex, mods.count)) {
            let cw = cell(m)
            if cursor + cw > area.width + 0.5 { break }
            let r = mirrored ? NSRect(x: area.maxX - cursor - cw, y: 0, width: cw, height: Self.baseHeight)
                             : NSRect(x: area.minX + cursor, y: 0, width: cw, height: Self.baseHeight)
            out.append((m, r))
            cursor += cw + groove
        }
        return out
    }
    private var canScrollBack: Bool { scrollIndex > 0 }
    private var canScrollOn: Bool { placedModules().count + scrollIndex < controller.available.count }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none
        ctx.scaleBy(x: Self.scale, y: Self.scale)   // everything below is in 1× units
        if mono { drawPowerBook(); return }
        let platinum = NSColor(calibratedWhite: 0.733, alpha: 1)
        let border = NSColor(calibratedWhite: 0.149, alpha: 1)
        let light = NSColor.white
        let shadow = NSColor(calibratedWhite: 0.502, alpha: 1)
        // The tab, from the theme's own picture (mirrored on the right edge).
        drawCap(tabImage, in: tabRect, flip: mirrored)
        if collapsed { return }
        // The ledge: platinum with the dark edge and the bevel, between tab and size box.
        let ledge = mirrored
            ? NSRect(x: sizeBoxRect.maxX, y: 0, width: tabRect.minX - sizeBoxRect.maxX, height: Self.baseHeight)
            : NSRect(x: tabRect.maxX, y: 0, width: sizeBoxRect.minX - tabRect.maxX, height: Self.baseHeight)
        platinum.setFill(); ledge.fill()
        border.setFill()
        NSRect(x: ledge.minX, y: 0, width: ledge.width, height: 1).fill()
        NSRect(x: ledge.minX, y: Self.baseHeight - 1, width: ledge.width, height: 1).fill()
        light.setFill(); NSRect(x: ledge.minX, y: 1, width: ledge.width, height: 2).fill()
        shadow.setFill(); NSRect(x: ledge.minX, y: Self.baseHeight - 3, width: ledge.width, height: 2).fill()
        drawCap(sizeBoxImage, in: sizeBoxRect, flip: mirrored)
        // Arrows, from the theme's pictures (the hollow Platinum arrows) when it has them:
        // full when there is something to scroll to, faint otherwise.
        drawArrow(in: leftArrowRect, pointsLeft: !mirrored, enabled: mirrored ? canScrollOn : canScrollBack)
        drawArrow(in: rightArrowRect, pointsLeft: mirrored, enabled: mirrored ? canScrollBack : canScrollOn)
        // Grooves either side of the module area.
        drawGroove(at: mirrored ? moduleArea.maxX : moduleArea.minX - Self.groove)
        drawGroove(at: mirrored ? moduleArea.minX - Self.groove : moduleArea.maxX)
        // Modules, each 16 pt tall picture centred, a groove between neighbours.
        let placed = placedModules()
        for (i, (m, r)) in placed.enumerated() {
            let picture = NSRect(x: r.minX + 2, y: (Self.baseHeight - 16) / 2, width: r.width - 2 - Self.triangleRoom, height: 16)
            if let img = pictures[m.id] {
                img.draw(in: NSRect(x: picture.minX, y: picture.minY, width: 16, height: 16), from: .zero, operation: .sourceOver,
                         fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
                m.drawText(in: picture)
            } else {
                m.draw(in: picture)
            }
            // The module's black triangle, at its right end.
            let t = NSBezierPath()
            let tx = r.maxX - 6, ty = Self.baseHeight / 2
            t.move(to: NSPoint(x: tx, y: ty - 3.5)); t.line(to: NSPoint(x: tx + 4, y: ty)); t.line(to: NSPoint(x: tx, y: ty + 3.5)); t.close()
            NSColor.black.setFill(); t.fill()
            if i < placed.count - 1 { drawGroove(at: mirrored ? r.minX - Self.groove : r.maxX) }
        }
    }

    /// The System 7.5 colour strip, piece by piece from the original's own pixels
    /// (`System7Strip`): close box, arrow, the modules' buttons, arrow, tab.
    private func drawPowerBook() {
        // Pixel art at 1.5×: without antialiasing every pixel lands on whole device pixels,
        // with it the seams between neighbours show as a grid.
        NSGraphicsContext.current?.cgContext.setShouldAntialias(false)
        if collapsed {
            System7Strip.draw(System7Strip.tab, at: NSPoint(x: tabRect.minX, y: 0), flipped: mirrored)
            return
        }
        System7Strip.draw(System7Strip.closeBox, at: tabRect.origin, flipped: mirrored)
        System7Strip.draw(System7Strip.arrow(pointsLeft: true, enabled: mirrored ? canScrollOn : canScrollBack),
                          at: leftArrowRect.origin, flipped: mirrored)
        for (m, r) in placedModules() {
            if let art = System7Strip.cell(for: m) {
                System7Strip.draw(art, at: r.origin, flipped: mirrored)
            } else {
                // A module the colour strip did not have: a plain button, its own picture on it.
                System7Strip.draw(System7Strip.blankCell, at: r.origin, flipped: mirrored)
                m.draw(in: NSRect(x: r.minX + (mirrored ? 5 : 4), y: 4, width: 16, height: 16))
            }
        }
        System7Strip.draw(System7Strip.arrow(pointsLeft: false, enabled: mirrored ? canScrollBack : canScrollOn),
                          at: rightArrowRect.origin, flipped: mirrored)
        System7Strip.draw(System7Strip.tab, at: sizeBoxRect.origin, flipped: mirrored)
    }

    private func drawCap(_ img: NSImage?, in rect: NSRect, flip: Bool) {
        guard let img, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        if flip { ctx.translateBy(x: rect.minX + rect.maxX, y: 0); ctx.scaleBy(x: -1, y: 1) }
        img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
        ctx.restoreGState()
    }

    private func drawGroove(at x: CGFloat) {
        NSColor(calibratedWhite: 0.55, alpha: 1).setFill(); NSRect(x: x, y: 3, width: 1, height: Self.baseHeight - 6).fill()
        NSColor(calibratedWhite: 0.92, alpha: 1).setFill(); NSRect(x: x + 1, y: 3, width: 1, height: Self.baseHeight - 6).fill()
    }

    private func drawArrow(in rect: NSRect, pointsLeft: Bool, enabled: Bool) {
        if let img = pointsLeft ? arrowLeft : arrowRight {
            let s: CGFloat = 12
            img.draw(in: NSRect(x: rect.midX - s / 2, y: rect.midY - s / 2, width: s, height: s), from: .zero, operation: .sourceOver,
                     fraction: enabled ? 1 : 0.4, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
            return
        }
        let p = NSBezierPath()
        let cx = rect.midX, cy = rect.midY
        if pointsLeft {
            p.move(to: NSPoint(x: cx + 3, y: cy - 4)); p.line(to: NSPoint(x: cx - 3, y: cy)); p.line(to: NSPoint(x: cx + 3, y: cy + 4))
        } else {
            p.move(to: NSPoint(x: cx - 3, y: cy - 4)); p.line(to: NSPoint(x: cx + 3, y: cy)); p.line(to: NSPoint(x: cx - 3, y: cy + 4))
        }
        p.close()
        (enabled ? NSColor(calibratedWhite: 0.2, alpha: 1) : NSColor(calibratedWhite: 0.6, alpha: 1)).setFill()
        p.fill()
    }

    // MARK: Mouse

    private enum Drag {
        case none
        case tab(startY: CGFloat, moved: Bool)
        case size(startX: CGFloat, startWidth: CGFloat, moved: Bool = false)
        case module(ControlStripModule, startX: CGFloat)   // Option-drag: rearrange
        case strip(startY: CGFloat)                         // Option-drag: move the strip
    }
    private var dragTarget: ControlStripModule?
    private var drag = Drag.none

    override func mouseDown(with event: NSEvent) {
        let raw = convert(event.locationInWindow, from: nil)
        let p = NSPoint(x: raw.x / Self.scale, y: raw.y / Self.scale)
        let screenP = NSEvent.mouseLocation
        // Option or Control held: rearrange a module, or move the whole strip along the edges.
        if !event.modifierFlags.intersection([.option, .control]).isEmpty {
            if !collapsed, let (m, _) = placedModules().first(where: { $0.1.contains(p) }) { drag = .module(m, startX: screenP.x) }
            else { drag = .strip(startY: screenP.y) }
            return
        }
        if tabRect.contains(p) { drag = .tab(startY: screenP.y, moved: false); return }
        guard !collapsed else { return }
        if sizeBoxRect.contains(p) {
            drag = .size(startX: screenP.x, startWidth: moduleArea.width); return
        }
        if leftArrowRect.contains(p) { controller.scroll(by: mirrored ? 1 : -1); return }
        if rightArrowRect.contains(p) { controller.scroll(by: mirrored ? -1 : 1); return }
        if let (m, r) = placedModules().first(where: { $0.1.contains(p) }) {
            controller.activate(m, anchor: NSRect(x: r.minX * Self.scale, y: r.minY * Self.scale, width: r.width * Self.scale, height: r.height * Self.scale))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let screenP = NSEvent.mouseLocation
        switch drag {
        case .tab(let startY, _):
            let dy = screenP.y - startY
            if abs(dy) >= 1 {
                drag = .tab(startY: screenP.y, moved: true)
                controller.dragged(by: dy)
            }
        case .size(let startX, let startWidth, _):
            let dx = (screenP.x - startX) / Self.scale
            if abs(dx) >= 1 { drag = .size(startX: startX, startWidth: startWidth, moved: true) }
            controller.resized(to: startWidth + (mirrored ? -dx : dx))
        case .module:
            // The module under the pointer is where the dragged one will go.
            let raw = convert(event.locationInWindow, from: nil)
            let p = NSPoint(x: raw.x / Self.scale, y: raw.y / Self.scale)
            dragTarget = placedModules().min { abs($0.1.midX - p.x) < abs($1.1.midX - p.x) }?.0   // the nearest, grooves included
        case .strip(let startY):
            let dy = screenP.y - startY
            drag = .strip(startY: screenP.y)
            controller.moved(toScreenPoint: screenP, dy: dy)
        case .none: break
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch drag {
        case .tab(_, let moved): if !moved { controller.toggleCollapsed() }
        case .size(_, _, let moved): if mono, !moved { controller.toggleCollapsed() }   // the PowerBook tab closes the strip
        case .module(let m, _):
            if let target = dragTarget, target !== m { controller.move(m, before: target) }
        default: break
        }
        dragTarget = nil
        drag = .none
    }
}
