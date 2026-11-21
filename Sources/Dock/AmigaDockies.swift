import AppKit

/// AmiDock's Dockies (Amiga Workbench 4.1): small programs living in the dock instead of an icon.
/// The theme names them in `dock.dockies`; the 2008 screenshots show a clock docky at the top of a
/// dock, and the AmigaOS wiki names datetime.docky and winbar.docky. Three are drawn here:
/// an analog clock, a CPU load graph in Ranger's manner, and WinBar, the list of open windows.
enum AmigaDockies {
    static let names: [String: String] = ["clock": "Clock", "cpu": "CPU", "winbar": "WinBar"]
    static func id(_ name: String) -> String { "__docky_\(name)__" }
    static func name(of id: String) -> String? {
        guard id.hasPrefix("__docky_"), id.hasSuffix("__") else { return nil }
        return String(id.dropFirst(8).dropLast(2))
    }

    /// The docky's picture now. Drawn at whatever scale the screen asks (the image draws itself).
    static func image(_ name: String, size: CGFloat, date: Date = Date(), load: [Double] = []) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { r in
            switch name {
            case "clock": drawClock(in: r, date: date)
            case "cpu": drawCPU(in: r, load: load)
            default: drawWinBar(in: r)
            }
            return true
        }
    }

    /// A round clock: a pale face in a blue-grey rim, twelve ticks, dark hands and a red second hand.
    static func drawClock(in r: NSRect, date: Date) {
        let s = r.width, c = NSPoint(x: r.midX, y: r.midY), rad = s * 0.44
        let rim = NSBezierPath(ovalIn: NSRect(x: c.x - rad, y: c.y - rad, width: 2 * rad, height: 2 * rad))
        NSGradient(starting: NSColor(srgbRed: 0.72, green: 0.78, blue: 0.88, alpha: 1),
                   ending: NSColor(srgbRed: 0.28, green: 0.36, blue: 0.52, alpha: 1))?.draw(in: rim, angle: -90)
        let fr = rad * 0.84
        let face = NSBezierPath(ovalIn: NSRect(x: c.x - fr, y: c.y - fr, width: 2 * fr, height: 2 * fr))
        NSGradient(starting: .white, ending: NSColor(white: 0.86, alpha: 1))?.draw(in: face, relativeCenterPosition: NSPoint(x: -0.3, y: -0.4))
        NSColor(white: 0.15, alpha: 1).setStroke(); rim.lineWidth = max(0.6, s / 60); rim.stroke()
        for k in 0..<12 {
            let a = CGFloat(k) * .pi / 6
            let inner = fr * (k % 3 == 0 ? 0.74 : 0.84)
            let p = NSBezierPath()
            p.move(to: NSPoint(x: c.x + inner * sin(a), y: c.y - inner * cos(a)))
            p.line(to: NSPoint(x: c.x + fr * 0.94 * sin(a), y: c.y - fr * 0.94 * cos(a)))
            p.lineWidth = k % 3 == 0 ? s / 26 : s / 50
            NSColor(white: 0.2, alpha: 1).setStroke(); p.stroke()
        }
        let cal = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let sec = CGFloat(cal.second ?? 0), min = CGFloat(cal.minute ?? 0) + sec / 60, hr = CGFloat((cal.hour ?? 0) % 12) + min / 60
        func hand(_ angle: CGFloat, _ length: CGFloat, _ width: CGFloat, _ color: NSColor) {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: c.x - length * 0.16 * sin(angle), y: c.y + length * 0.16 * cos(angle)))
            p.line(to: NSPoint(x: c.x + length * sin(angle), y: c.y - length * cos(angle)))
            p.lineWidth = width; p.lineCapStyle = .round
            color.setStroke(); p.stroke()
        }
        hand(hr * .pi / 6, fr * 0.52, s / 14, NSColor(white: 0.12, alpha: 1))
        hand(min * .pi / 30, fr * 0.78, s / 20, NSColor(white: 0.12, alpha: 1))
        hand(sec * .pi / 30, fr * 0.84, max(0.6, s / 48), NSColor(srgbRed: 0.84, green: 0.12, blue: 0.1, alpha: 1))
        NSColor(srgbRed: 0.84, green: 0.12, blue: 0.1, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - s / 28, y: c.y - s / 28, width: s / 14, height: s / 14)).fill()
    }

    /// CPU load the way Ranger showed it: a dark screen, a grid, the last samples as green bars and
    /// the load now in figures.
    static func drawCPU(in r: NSRect, load: [Double]) {
        let s = r.width
        let screen = NSRect(x: r.minX + s * 0.06, y: r.minY + s * 0.12, width: s * 0.88, height: s * 0.76)
        let bezel = NSBezierPath(roundedRect: screen.insetBy(dx: -s * 0.03, dy: -s * 0.03), xRadius: s * 0.06, yRadius: s * 0.06)
        NSGradient(starting: NSColor(white: 0.85, alpha: 1), ending: NSColor(white: 0.45, alpha: 1))?.draw(in: bezel, angle: -90)
        NSColor(white: 0.15, alpha: 1).setStroke(); bezel.lineWidth = max(0.6, s / 60); bezel.stroke()
        NSColor(srgbRed: 0.03, green: 0.08, blue: 0.03, alpha: 1).setFill(); screen.fill()
        NSColor(srgbRed: 0.12, green: 0.32, blue: 0.12, alpha: 1).setFill()
        for k in 1..<4 { NSRect(x: screen.minX, y: screen.minY + screen.height * CGFloat(k) / 4, width: screen.width, height: max(0.5, s / 96)).fill() }
        let n = 12, w = screen.width / CGFloat(n)
        let recent = Array(load.suffix(n))
        for (i, v) in recent.enumerated() {
            let h = screen.height * CGFloat(max(0, min(100, v))) / 100
            let x = screen.minX + CGFloat(n - recent.count + i) * w
            NSColor(srgbRed: 0.35, green: 0.95, blue: 0.35, alpha: 1).setFill()
            NSRect(x: x + w * 0.15, y: screen.maxY - h, width: w * 0.7, height: h).fill()
        }
        let now = Int((load.last ?? 0).rounded())
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: s * 0.2, weight: .bold),
                                                    .foregroundColor: NSColor(srgbRed: 0.75, green: 1, blue: 0.75, alpha: 1)]
        ("\(now)%" as NSString).draw(at: NSPoint(x: screen.minX + s * 0.04, y: screen.minY + s * 0.02), withAttributes: attrs)
    }

    /// WinBar: three small AmigaOS windows stacked, the front one blue.
    static func drawWinBar(in r: NSRect) {
        let s = r.width
        for (k, active) in [(0, false), (1, false), (2, true)] {
            let o = CGFloat(k) * s * 0.13
            let w = NSRect(x: r.minX + s * 0.1 + o, y: r.minY + s * 0.14 + o, width: s * 0.58, height: s * 0.48)
            NSColor(white: 0.9, alpha: 1).setFill(); w.fill()
            let bar = NSRect(x: w.minX, y: w.minY, width: w.width, height: s * 0.11)
            (active ? NSColor(srgbRed: 0.36, green: 0.53, blue: 0.80, alpha: 1) : NSColor(white: 0.7, alpha: 1)).setFill(); bar.fill()
            NSColor(white: 0.2, alpha: 1).setStroke()
            let p = NSBezierPath(rect: w.insetBy(dx: 0.3, dy: 0.3)); p.lineWidth = max(0.6, s / 64); p.stroke()
        }
    }
}

/// Feeds the clock and CPU dockies once a second while any is in the dock.
final class AmigaDockyTicker {
    static let shared = AmigaDockyTicker()
    private(set) var load: [Double] = []
    private var last: SystemSampler.Ticks?
    private var timer: Timer?
    var onTick: (() -> Void)?

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.sample()
            self?.onTick?()
        }
    }
    func stop() { timer?.invalidate(); timer = nil; onTick = nil }

    private func sample() {
        guard let now = SystemSampler.totalTicks() else { return }
        if let last, let l = SystemSampler.load(from: last, to: now) {
            load.append(l.busy)
            if load.count > 32 { load.removeFirst(load.count - 32) }
        }
        last = now
    }
}

extension AmigaDockies {
    /// WinBar's list: every open window, minimised ones too, in the Workbench's menu look; the
    /// chosen one comes forward (or back out of the dock).
    static func showWindowList(below anchor: NSRect) {
        let windows = MinimizedWindowTracker.shared.allWindows.filter { !$0.isAppLevel }
        var rows: [PlatinumMenuItem] = windows.map { e in
            let app = NSRunningApplication(processIdentifier: e.pid)?.localizedName ?? ""
            var title = e.title.isEmpty ? app : "\(app): \(e.title)"
            if title.count > 46 { title = String(title.prefix(45)) + "\u{2026}" }   // the menu stops at 360 pt and cut the rest off
            return .action(e.isMinimized ? "(\(title))" : title, ticked: e.isFocused) { MinimizedWindowTracker.shared.activate(e) }
        }
        if rows.isEmpty { rows = [.label("No windows")] }
        PlatinumMenuController.shared.show(rows, below: anchor, look: .amiga)
    }
}

/// AmiDock's sub-docks (Extras, Internet, Players): a column of apps that opens above its tile.
/// The real AmiDock opened it at a fixed place on the screen, which no longer matched once the
/// dock changed; this one follows its tile.
enum AmigaSubdock {
    static func id(_ name: String) -> String { "__subdock_\(name)__" }
    static func name(of id: String) -> String? {
        guard id.hasPrefix("__subdock_"), id.hasSuffix("__") else { return nil }
        return String(id.dropFirst(10).dropLast(2))
    }

    private static var panel: NSPanel?
    private static var shown: String?
    private static var monitors: [Any] = []

    /// Opens the column above `anchor` (the tile, in screen points), or closes it when it is open.
    static func toggle(_ sub: DockThemeConfig.Subdock, theme: DockThemeConfig, above anchor: NSRect) {
        let wasOpen = shown == sub.name
        close()
        guard !wasOpen else { return }
        let apps = sub.apps.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        guard !apps.isEmpty else { NSSound.beep(); return }
        let icon = theme.dock.iconSize, pad: CGFloat = 6, cellW = icon + 28, cellH = icon + 16
        let size = NSSize(width: cellW + 2 * pad, height: CGFloat(apps.count) * cellH + 2 * pad)
        var origin = NSPoint(x: (anchor.midX - size.width / 2).rounded(), y: anchor.maxY + 6)
        if let vf = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX), vf.maxX - size.width)
        }
        let p = NSPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        let box = BoxView(frame: NSRect(origin: .zero, size: size), style: theme.dock)
        let font = RetroFonts.dejaVu(9.5, bold: true)
        for (i, bid) in apps.enumerated() {
            let b = AppButton(frame: NSRect(x: pad, y: size.height - pad - CGFloat(i + 1) * cellH, width: cellW, height: cellH))
            b.isBordered = false
            b.imagePosition = .imageAbove
            b.image = ThemeManager.shared.icon(for: bid, size: icon)
            let name = theme.dock.labelNames?[bid] ?? DockApp(bundleID: bid, customIconPath: nil, order: 0).displayName
            // White with a black outline, as the AmiDock wrote its names.
            b.attributedTitle = NSAttributedString(string: name, attributes: [.font: font, .foregroundColor: NSColor.white,
                                                                                .strokeColor: NSColor.black, .strokeWidth: -3])
            b.setAccessibilityLabel(name)
            b.onClick = {
                close()
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
            box.addSubview(b)
        }
        p.contentView = box
        p.orderFrontRegardless()
        panel = p
        shown = sub.name
        // A click anywhere else puts it away; a click on the dock is the tile's own (toggle).
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in close() }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { e in
            if e.window !== panel, !(e.window is DockWindow) { close() }
            return e
        }) { monitors.append(l) }
    }

    static func close() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        panel?.orderOut(nil)
        panel = nil
        shown = nil
    }

    private final class AppButton: NSButton {
        var onClick: (() -> Void)?
        override func mouseDown(with event: NSEvent) { onClick?() }
    }

    /// The column's box in the dock's own colours and bevel.
    private final class BoxView: NSView {
        let style: DockThemeConfig.DockStyle
        init(frame: NSRect, style: DockThemeConfig.DockStyle) { self.style = style; super.init(frame: frame) }
        required init?(coder: NSCoder) { nil }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.fromHex(style.backgroundColor).setFill(); bounds.fill()
            let w = max(1, style.bevelWidth)
            if let top = style.bevelTopColor {
                NSColor.fromHex(top).setFill()
                NSRect(x: 0, y: bounds.maxY - w, width: bounds.width, height: w).fill()
                NSRect(x: 0, y: 0, width: w, height: bounds.height).fill()
            }
            if let bottom = style.bevelBottomColor {
                NSColor.fromHex(bottom).setFill()
                NSRect(x: 0, y: 0, width: bounds.width, height: w).fill()
                NSRect(x: bounds.maxX - w, y: 0, width: w, height: bounds.height).fill()
            }
            NSColor.fromHex(style.borderColor).setStroke()
            NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
    }
}
