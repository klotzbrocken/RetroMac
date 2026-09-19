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
    let modules: [ControlStripModule] = [NetworkModule(), SharingModule(), ColourDepthModule(),
                                         ResolutionModule(), VolumeModule(), BatteryModule(), MirroringModule()]

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

    /// Modules that have something to show right now, in Control Strip order.
    var available: [ControlStripModule] { modules.filter { $0.isAvailable } }

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

    func toggleCollapsed() {
        AppSettings.shared.controlStripCollapsed.toggle()
        layout()
    }

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

    func activate(_ module: ControlStripModule, anchor: NSRect) {
        guard let view, let window = view.window else { return }
        let onScreen = window.convertToScreen(view.convert(anchor, to: nil))
        if let menu = module.menu() {
            // The module's menu, drawn Platinum; from the bottom of the screen it opens upward.
            PlatinumMenuController.shared.ignoreClickWindow = window
            PlatinumMenuController.shared.show(PlatinumMenuItem.rows(of: menu), below: onScreen)
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
    /// Drawn at twice its 1× size: the strip was 26 px on a 640×480 screen, and 26 pt on a
    /// 1920-wide display is a sliver nobody can hit. Every measure below is in 1× units; the
    /// view scales its drawing and divides the mouse by `scale`.
    static let scale: CGFloat = 2
    static let baseHeight: CGFloat = 26
    static var height: CGFloat { baseHeight * scale }
    static let scrollCell: CGFloat = 12
    static let groove: CGFloat = 2

    private unowned let controller: ControlStripController
    private let tabImage: NSImage?
    private let sizeBoxImage: NSImage?
    var mirrored = false          // right edge: the tab is on the right, everything reads mirrored
    var scrollIndex = 0

    override var isFlipped: Bool { true }

    init(theme: ThemeBundle, controller: ControlStripController) {
        self.controller = controller
        tabImage = theme.iconResource("controlstrip-left.png").flatMap { NSImage(contentsOf: $0) }
        sizeBoxImage = theme.iconResource("controlstrip-right.png").flatMap { NSImage(contentsOf: $0) }
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: Self.height))
    }
    required init?(coder: NSCoder) { fatalError() }

    private func capWidth(_ img: NSImage?, fallback: CGFloat) -> CGFloat {
        guard let img, img.size.height > 0 else { return fallback }
        return (img.size.width / img.size.height * Self.baseHeight).rounded()
    }
    var tabWidth: CGFloat { capWidth(tabImage, fallback: 16) }
    var sizeBoxWidth: CGFloat { capWidth(sizeBoxImage, fallback: 19) }

    func modulesWidth(_ modules: [ControlStripModule]) -> CGFloat {
        modules.reduce(0) { $0 + $1.width } + CGFloat(max(0, modules.count - 1)) * Self.groove
    }

    /// Window width for a state: the tab alone when collapsed; otherwise tab, arrows, the
    /// visible part of the modules, and the size box.
    func preferredWidth(collapsed: Bool, visible: CGFloat, modules: [ControlStripModule]) -> CGFloat {
        if collapsed { return tabWidth }
        let all = modulesWidth(modules)
        let shown = visible > 0 ? min(visible, all) : all
        return tabWidth + Self.scrollCell + Self.groove + shown + Self.groove + Self.scrollCell + sizeBoxWidth
    }
    /// Window width in points for a 1× layout width.
    static func windowWidth(_ base: CGFloat) -> CGFloat { base * scale }
    /// The 1× bounds the layout works in.
    private var base: NSRect { NSRect(x: 0, y: 0, width: bounds.width / Self.scale, height: Self.baseHeight) }

    // Regions, in unmirrored (tab on the left) coordinates; `x(_:)` mirrors them.
    private func x(_ r: NSRect) -> NSRect { mirrored ? NSRect(x: base.width - r.maxX, y: r.minY, width: r.width, height: r.height) : r }
    private var collapsed: Bool { AppSettings.shared.controlStripCollapsed }
    private var tabRect: NSRect { x(NSRect(x: 0, y: 0, width: tabWidth, height: Self.baseHeight)) }
    private var leftArrowRect: NSRect { x(NSRect(x: tabWidth, y: 0, width: Self.scrollCell, height: Self.baseHeight)) }
    private var moduleArea: NSRect {
        let start = tabWidth + Self.scrollCell + Self.groove
        let end = base.width - sizeBoxWidth - Self.scrollCell - Self.groove
        return x(NSRect(x: start, y: 0, width: max(0, end - start), height: Self.baseHeight))
    }
    private var rightArrowRect: NSRect { x(NSRect(x: base.width - sizeBoxWidth - Self.scrollCell, y: 0, width: Self.scrollCell, height: Self.baseHeight)) }
    private var sizeBoxRect: NSRect { x(NSRect(x: base.width - sizeBoxWidth, y: 0, width: sizeBoxWidth, height: Self.baseHeight)) }

    /// The modules on show, with their cells, from the scroll index on until the area is full.
    private func placedModules() -> [(ControlStripModule, NSRect)] {
        let mods = controller.available
        var out: [(ControlStripModule, NSRect)] = []
        let area = moduleArea
        var cursor: CGFloat = 0
        for m in mods.dropFirst(min(scrollIndex, mods.count)) {
            if cursor + m.width > area.width + 0.5 { break }
            let r = mirrored ? NSRect(x: area.maxX - cursor - m.width, y: 0, width: m.width, height: Self.baseHeight)
                             : NSRect(x: area.minX + cursor, y: 0, width: m.width, height: Self.baseHeight)
            out.append((m, r))
            cursor += m.width + Self.groove
        }
        return out
    }
    private var canScrollBack: Bool { scrollIndex > 0 }
    private var canScrollOn: Bool { placedModules().count + scrollIndex < controller.available.count }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none
        ctx.scaleBy(x: Self.scale, y: Self.scale)   // everything below is in 1× units
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
        // Arrows: dark when there is something to scroll to, faint otherwise.
        drawArrow(in: leftArrowRect, pointsLeft: !mirrored, enabled: mirrored ? canScrollOn : canScrollBack)
        drawArrow(in: rightArrowRect, pointsLeft: mirrored, enabled: mirrored ? canScrollBack : canScrollOn)
        // Grooves either side of the module area.
        drawGroove(at: mirrored ? moduleArea.maxX : moduleArea.minX - Self.groove)
        drawGroove(at: mirrored ? moduleArea.minX - Self.groove : moduleArea.maxX)
        // Modules, each 16 pt tall picture centred, a groove between neighbours.
        let placed = placedModules()
        for (i, (m, r)) in placed.enumerated() {
            m.draw(in: NSRect(x: r.minX + 2, y: (Self.baseHeight - 16) / 2, width: r.width - 2, height: 16))
            if i < placed.count - 1 { drawGroove(at: mirrored ? r.minX - Self.groove : r.maxX) }
        }
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

    private enum Drag { case none, tab(startY: CGFloat, moved: Bool), size(startX: CGFloat, startWidth: CGFloat) }
    private var drag = Drag.none

    override func mouseDown(with event: NSEvent) {
        let raw = convert(event.locationInWindow, from: nil)
        let p = NSPoint(x: raw.x / Self.scale, y: raw.y / Self.scale)
        let screenP = NSEvent.mouseLocation
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
        case .size(let startX, let startWidth):
            let dx = (screenP.x - startX) / Self.scale
            controller.resized(to: startWidth + (mirrored ? -dx : dx))
        case .none: break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if case .tab(_, let moved) = drag, !moved { controller.toggleCollapsed() }
        drag = .none
    }
}
