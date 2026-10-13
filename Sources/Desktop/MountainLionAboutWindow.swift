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
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "About This Mac"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.appearance = NSAppearance(named: .aqua)
        let v = NSView(frame: w.contentLayoutRect)
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 0.93, alpha: 1).cgColor
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

        let update = NSButton(title: "Software Update\u{2026}", target: self, action: #selector(softwareUpdate))
        update.bezelStyle = .rounded
        update.frame = NSRect(x: 171 - 70, y: 186, width: 140, height: 28)
        v.addSubview(update)

        var y: CGFloat = 146
        var memoryValue: NSTextField?
        for (name, value) in [("Processor", f.processor), ("Memory", f.memory), ("Startup Disk", f.disk)] {
            _ = label(name, .boldSystemFont(ofSize: 13), .black, y: y, x: 0, width: 128, align: .right)
            let val = label(value, .systemFont(ofSize: 13), .black, y: y, x: 136, width: 200, align: .left)
            if name == "Memory" { memoryValue = val }
            y -= 26
        }
        let more = NSButton(title: "More Info\u{2026}", target: self, action: #selector(moreInfo))
        more.bezelStyle = .rounded
        more.frame = NSRect(x: 171 - 70, y: 40, width: 140, height: 28)
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

    /// The brushed-silver apple of 10.8's About window: the Apple glyph filled with a light
    /// gradient and a thin grey edge, drawn rather than shipped.
    static func silverApple(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            guard let glyph = NSImage(systemSymbolName: "applelogo", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: rect.height * 0.9, weight: .regular)) else { return false }
            let g = glyph.size, s = min(rect.width / g.width, rect.height / g.height)
            let r = NSRect(x: rect.midX - g.width * s / 2, y: rect.midY - g.height * s / 2, width: g.width * s, height: g.height * s)
            // A mask of the glyph, then the gradient through it.
            let mask = NSImage(size: rect.size, flipped: false) { _ in glyph.draw(in: r); return true }
            guard let ctx = NSGraphicsContext.current?.cgContext,
                  let cg = mask.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
            ctx.saveGState()
            ctx.clip(to: rect, mask: cg)
            NSGradient(colors: [NSColor(white: 0.97, alpha: 1), NSColor(white: 0.78, alpha: 1), NSColor(white: 0.9, alpha: 1)],
                       atLocations: [0, 0.6, 1], colorSpace: .sRGB)?.draw(in: rect, angle: -70)
            ctx.restoreGState()
            return true
        }
    }
}
