import AppKit

/// OS X 10.8's About This Mac, from Mountain Lion's Apple menu: the silver apple, "OS X" and its
/// version, Software Update…, then processor, memory and startup disk — read from this Mac —
/// and More Info…, which opens today's About pane.
final class MountainLionAboutWindow: NSObject, NSWindowDelegate {
    static let shared = MountainLionAboutWindow()
    private var window: NSWindow?

    struct Facts: Equatable { var version: String; var processor: String; var memory: String; var disk: String }

    /// What this Mac says about itself. Memory type comes from System Information, which is slow,
    /// so it is filled in after the window is up (`memoryType`).
    static func facts() -> Facts {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let version = "Version \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var cpu = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &cpu, &size, nil, 0)
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let disk = FileManager.default.displayName(atPath: "/")
        return Facts(version: version, processor: String(cString: cpu), memory: "\(Int(gb.rounded())) GB", disk: disk)
    }

    func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let f = Self.facts()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 342, height: 420),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "About This Mac"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.appearance = NSAppearance(named: .aqua)
        // 10.8's title bar is ours: light grey to mid grey, a darker line under it.
        w.titlebarAppearsTransparent = true
        // The content runs under the title bar now, so the window grows by the bar's height and
        // everything below keeps its 420 pt — the apple sat in the bar before.
        let barH = w.frame.height - w.contentLayoutRect.height
        w.setContentSize(NSSize(width: 342, height: 420 + barH))
        let v = LionWindowBackground(frame: NSRect(origin: .zero, size: w.frame.size))
        w.contentView = v

        let apple = NSImageView(frame: NSRect(x: 171 - 48, y: 300, width: 96, height: 104))
        apple.image = Self.silverApple(size: NSSize(width: 96, height: 104))
        apple.setAccessibilityElement(false)
        v.addSubview(apple)

        func label(_ s: String, _ font: NSFont, _ colour: NSColor, y: CGFloat, x: CGFloat = 0, width: CGFloat = 342, align: NSTextAlignment = .center) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.font = font; l.textColor = colour; l.alignment = align
            l.frame = NSRect(x: x, y: y, width: width, height: font.pointSize + 8)
            v.addSubview(l); return l
        }
        _ = label("OS X", .systemFont(ofSize: 34, weight: .bold), NSColor(white: 0.2, alpha: 1), y: 248)
        _ = label(f.version, .systemFont(ofSize: 15), NSColor(white: 0.45, alpha: 1), y: 222)

        let update = LionButton(title: "Software Update\u{2026}", target: self, action: #selector(softwareUpdate))
        update.frame = NSRect(x: 171 - 68, y: 190, width: 136, height: 22)
        v.addSubview(update)

        var y: CGFloat = 146
        var memoryValue: NSTextField?
        for (name, value) in [("Processor", f.processor), ("Memory", f.memory), ("Startup Disk", f.disk)] {
            _ = label(name, .boldSystemFont(ofSize: 13), .black, y: y, x: 0, width: 128, align: .right)
            let val = label(value, .systemFont(ofSize: 13), .black, y: y, x: 136, width: 200, align: .left)
            if name == "Memory" { memoryValue = val }
            y -= 26
        }
        let more = LionButton(title: "More Info\u{2026}", target: self, action: #selector(moreInfo))
        more.frame = NSRect(x: 171 - 68, y: 44, width: 136, height: 22)
        v.addSubview(more)
        let foot = NSTextField(wrappingLabelWithString: "TM and \u{00A9} 1983\u{2013}2013 Apple Inc.\nAll Rights Reserved.")
        foot.font = .systemFont(ofSize: 10); foot.textColor = NSColor(white: 0.4, alpha: 1); foot.alignment = .center
        foot.frame = NSRect(x: 0, y: 6, width: 342, height: 28)
        v.addSubview(foot)

        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // "16 GB 1600 MHz DDR3": the type, where System Information knows it.
        DispatchQueue.global(qos: .userInitiated).async {
            guard let type = Self.memoryType() else { return }
            DispatchQueue.main.async { memoryValue?.stringValue = "\(f.memory) \(type)" }
        }
    }

    func windowWillClose(_ notification: Notification) { window = nil }

    @objc private func softwareUpdate() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!)
    }
    @objc private func moreInfo() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.SystemProfiler.AboutExtension")!)
    }

    /// LPDDR5 and the like, from `system_profiler`; nil when it does not say.
    static func memoryType() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPMemoryDataType", "-json"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["SPMemoryDataType"] as? [[String: Any]])?.first else { return nil }
        return (first["dimm_type"] as? String) ?? ((first["_items"] as? [[String: Any]])?.first?["dimm_type"] as? String)
    }

    /// The silver apple of 10.8's About window: the Apple glyph in light brushed silver, lit from
    /// the upper left, a soft fold running across it, a thin grey rim and a faint shadow below —
    /// drawn rather than shipped.
    static func silverApple(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            guard let glyph = NSImage(systemSymbolName: "applelogo", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: rect.height * 0.9, weight: .regular)),
                  let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let inner = rect.insetBy(dx: 3, dy: 4)
            let g = glyph.size, s = min(inner.width / g.width, inner.height / g.height)
            let r = NSRect(x: inner.midX - g.width * s / 2, y: inner.midY - g.height * s / 2 + 1, width: g.width * s, height: g.height * s)
            let mask = NSImage(size: rect.size, flipped: false) { _ in glyph.draw(in: r); return true }
            guard let cg = mask.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
            // Rim and shadow: the glyph in grey, a hair larger, with a soft shadow under it.
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 3, color: NSColor.black.withAlphaComponent(0.25).cgColor)
            NSColor(white: 0.62, alpha: 1).set()
            let rim = NSImage(size: rect.size, flipped: false) { _ in glyph.draw(in: r.insetBy(dx: -0.8, dy: -0.8)); return true }
            if let rimCG = rim.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.clip(to: rect, mask: rimCG); ctx.fill(rect)
            }
            ctx.restoreGState()
            // The silver itself, through the glyph.
            ctx.saveGState()
            ctx.clip(to: rect, mask: cg)
            NSGradient(colors: [NSColor(white: 0.99, alpha: 1), NSColor(white: 0.90, alpha: 1), NSColor(white: 0.80, alpha: 1)],
                       atLocations: [0, 0.55, 1], colorSpace: .sRGB)?.draw(in: rect, angle: -60)
            // The fold: a brighter sweep above a soft grey line, corner to corner.
            let fold = NSBezierPath()
            fold.move(to: NSPoint(x: rect.minX, y: rect.maxY * 0.62))
            fold.curve(to: NSPoint(x: rect.maxX, y: rect.minY + rect.height * 0.18),
                       controlPoint1: NSPoint(x: rect.width * 0.45, y: rect.maxY * 0.62),
                       controlPoint2: NSPoint(x: rect.width * 0.6, y: rect.height * 0.3))
            let above = fold.copy() as! NSBezierPath
            above.line(to: NSPoint(x: rect.maxX, y: rect.maxY)); above.line(to: NSPoint(x: rect.minX, y: rect.maxY)); above.close()
            NSColor(white: 1, alpha: 0.35).setFill(); above.fill()
            NSColor(white: 0.55, alpha: 0.55).setStroke(); fold.lineWidth = 1.2; fold.stroke()
            ctx.restoreGState()
            return true
        }
    }
}

/// 10.8's window: the light grey body under a title bar that runs from light to mid grey.
private final class LionWindowBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.93, alpha: 1).setFill(); bounds.fill()
        // As tall as macOS makes the title bar today, so the traffic lights sit in ours.
        let h = window.map { bounds.height - $0.contentLayoutRect.height } ?? 22
        let bar = NSRect(x: 0, y: bounds.maxY - h, width: bounds.width, height: h)
        NSGradient(colors: [NSColor(white: 0.91, alpha: 1), NSColor(white: 0.82, alpha: 1)])?.draw(in: bar, angle: -90)
        NSColor(white: 0.97, alpha: 1).setFill(); NSRect(x: 0, y: bar.maxY - 1, width: bounds.width, height: 1).fill()
        NSColor(white: 0.60, alpha: 1).setFill(); NSRect(x: 0, y: bar.minY, width: bounds.width, height: 1).fill()
    }
}

/// 10.8's push button: white to light grey, a mid-grey rim, rounded, 22 pt high.
private final class LionButton: NSButton {
    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title; self.target = target; self.action = action
        isBordered = false
        font = NSFont(name: "LucidaGrande", size: 13) ?? .systemFont(ofSize: 13)
    }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1.5)
        let shape = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
        let pressed = isHighlighted
        NSGradient(colors: pressed ? [NSColor(white: 0.80, alpha: 1), NSColor(white: 0.88, alpha: 1)]
                                   : [NSColor(white: 1, alpha: 1), NSColor(white: 0.90, alpha: 1)])?.draw(in: shape, angle: -90)
        NSColor(white: 0.58, alpha: 1).setStroke(); shape.lineWidth = 1; shape.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: font ?? .systemFont(ofSize: 13), .foregroundColor: NSColor.black]
        let ts = title.size(withAttributes: attrs)
        title.draw(at: NSPoint(x: bounds.midX - ts.width / 2, y: bounds.midY - ts.height / 2), withAttributes: attrs)
    }
}