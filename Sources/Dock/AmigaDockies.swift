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
