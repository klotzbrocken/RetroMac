import AppKit

/// About This Mac of Mac OS X 10.0 and About This Computer of Mac OS 9, opened from those themes'
/// Apple menus. Laid out off a 10.0.4 and a 9.0 screenshot (Maik, 8 Nov 2026), filled with this
/// Mac's own facts. The big X and the "Mac OS" words are drawn from a serif face, not copied: the
/// shapes are close, the letterforms are Baskerville's rather than Apple Garamond's.
enum ClassicAbout {
    case macOSX, macOS9

    private static var open: [ClassicAbout: NSWindow] = [:]

    static func show(_ kind: ClassicAbout) {
        if let w = open[kind] { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let view = makeView(kind)
        let w = AboutWindow(contentRect: NSRect(origin: .zero, size: view.frame.size),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isReleasedWhenClosed = false
        w.title = kind == .macOSX ? "About This Mac" : "About This Computer"
        w.contentView = view
        w.onClose = { open[kind] = nil }
        w.center()
        open[kind] = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The window's content, also for the snapshot test.
    static func makeView(_ kind: ClassicAbout) -> NSView { kind == .macOSX ? CheetahAboutView() : MacOS9AboutView() }

    // MARK: Facts

    /// "Version 26.3 (Build 25D125)", as 10.0 wrote "Version 10.0.4 (Build 4S10)".
    static var versionLine: String { ProcessInfo.processInfo.operatingSystemVersionString }

    /// The processor without the trademark clutter Intel's brand string carries.
    static var processor: String {
        var p = MountainLionAboutWindow.facts().processor
        for junk in ["(R)", "(TM)", " CPU"] { p = p.replacingOccurrences(of: junk, with: "") }
        if let at = p.range(of: " @") { p = String(p[..<at.lowerBound]) }
        return p.split(separator: " ").joined(separator: " ")
    }

    static func size(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return gb >= 1 ? String(format: gb >= 10 ? "%.0f GB" : "%.1f GB", gb) : String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    /// The running apps and what each holds in memory, largest first, with the system's wired
    /// memory first as "macOS" — 9.0 put "Mac OS" at the top of the same list.
    static func memoryList() -> [(name: String, icon: NSImage?, bytes: UInt64)] {
        let page = UInt64(vm_kernel_page_size)
        var rows: [(String, NSImage?, UInt64)] = []
        if let vm = SystemSampler.vmStats() {
            rows.append(("macOS", ThemeManager.shared.activeTheme?.iconResource("finder.png").flatMap(NSImage.init(contentsOf:)),
                         UInt64(vm.wire_count) * page))
        }
        var apps: [(String, NSImage?, UInt64)] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            var ti = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(app.processIdentifier, PROC_PIDTASKINFO, 0, &ti, size) == size else { continue }
            let icon = app.bundleIdentifier.map { ThemeManager.shared.icon(for: $0, size: 16) } ?? app.icon
            apps.append((app.localizedName ?? "?", icon, ti.pti_resident_size))
        }
        return rows + apps.sorted { $0.2 > $1.2 }
    }
}

/// Borderless, so the theme draws the whole window; it still takes keys for ⌘W and Esc.
private final class AboutWindow: NSWindow {
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" { close(); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func close() { onClose?(); super.close() }
}

/// Drag anywhere, the close box closes; both windows share this.
private class AboutChromeView: NSView {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var closeRect: NSRect { .zero }
    var active: Bool { window?.isKeyWindow ?? true }
    private var pressedClose = false { didSet { needsDisplay = true } }
    var closePressed: Bool { pressedClose }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.needsDisplay = true
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard closeRect.insetBy(dx: -2, dy: -2).contains(p) else { window?.performDrag(with: event); return }
        pressedClose = true
        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let q = convert(e.locationInWindow, from: nil)
            pressedClose = closeRect.insetBy(dx: -2, dy: -2).contains(q)
            if e.type == .leftMouseUp { break }
        }
        if pressedClose { pressedClose = false; window?.close() }
    }

    /// A serif word drawn to a box: `capHeight` points tall, squeezed or stretched to `width`.
    static func serifWord(_ text: String, in box: NSRect, weight: String = "Baskerville", colour: NSColor = .black) {
        guard let font = NSFont(name: weight, size: 100) else { return }
        let size = 100 * box.height / font.capHeight
        let f = NSFont(name: weight, size: size)!
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: colour]
        let natural = (text as NSString).size(withAttributes: attrs)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        // Flipped view: the baseline sits on the box's bottom edge.
        ctx.translateBy(x: box.minX, y: box.maxY)
        ctx.scaleBy(x: box.width / natural.width, y: 1)
        (text as NSString).draw(at: NSPoint(x: 0, y: -f.ascender), withAttributes: attrs)
        ctx.restoreGState()
    }
}

// MARK: - Mac OS X 10.0

/// 267 × 314: the pinstriped window, the blue X over "Mac OS X", the version and build, memory
/// and processor, the copyright line. Measured off 10.0.4's About This Mac.
private final class CheetahAboutView: AboutChromeView {
    init() { super.init(frame: NSRect(x: 0, y: 0, width: 267, height: 314)) }
    required init?(coder: NSCoder) { fatalError() }

    private var bar: NSRect { NSRect(x: 0, y: 0, width: bounds.width, height: AquaChrome.barHeight) }
    override var closeRect: NSRect { AquaChrome.lightRects(in: bar, flipped: true)[0] }

    override func draw(_ dirtyRect: NSRect) {
        let outline = AquaChrome.outline(bounds, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        // The body's pinstripes, four rows to the period, as 10.0 drew a window's back.
        let rows: [CGFloat] = [234, 241, 255, 241]
        var y = AquaChrome.barHeight
        while y < bounds.height {
            NSColor(white: rows[Int(y) % 4] / 255, alpha: 1).setFill()
            NSRect(x: 0, y: y, width: bounds.width, height: 1).fill()
            y += 1
        }
        AquaChrome.titleBar(bar, active: active, flipped: true)
        NSGraphicsContext.restoreGraphicsState()
        // Only close is live; minimise and zoom stay grey, as on the original.
        let lights = AquaChrome.lightRects(in: bar, flipped: true)
        for (k, r) in zip([SnowLeopardChrome.Light.close, .minimize, .zoom], lights) {
            AquaGem.draw(r, k, active: active && k == .close, pressed: k == .close && closePressed, flipped: true)
        }
        AquaChrome.title("About This Mac", bar: bar, active: active, flipped: true, minX: lights[2].maxX, maxX: bounds.width - lights[2].maxX)
        AquaChrome.edge.setStroke(); outline.lineWidth = 1; outline.stroke()

        drawX(in: NSRect(x: 84, y: 38, width: 99, height: 124))
        Self.serifWord("Mac OS X", in: NSRect(x: 64, y: 170, width: 139, height: 28))

        let lucida = { (size: CGFloat) in NSFont(name: "LucidaGrande", size: size) ?? .systemFont(ofSize: size) }
        let centred = NSMutableParagraphStyle(); centred.alignment = .center
        func line(_ s: String, font: NSFont, top: CGFloat, x: CGFloat = 0, width: CGFloat? = nil, align: NSTextAlignment = .center) {
            let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: p]
            // `top` is where the capitals start, as measured.
            let y = top - (font.ascender - font.capHeight)
            (s as NSString).draw(in: NSRect(x: x, y: y, width: width ?? bounds.width, height: font.ascender - font.descender + 2), withAttributes: attrs)
        }
        line(ClassicAbout.versionLine, font: lucida(10), top: 211)
        let memory = ClassicAbout.size(ProcessInfo.processInfo.physicalMemory)
        for (label, value, top) in [("Memory:", memory, CGFloat(234)), ("Processor:", ClassicAbout.processor, 251)] {
            line(label, font: lucida(13), top: top, x: 0, width: 131, align: .right)
            line(value, font: lucida(13), top: top, x: 141, width: bounds.width - 141 - 8, align: .left)
        }
        line("\u{2122} & \u{00A9} Apple Computer, Inc. 1983\u{2013}2001", font: lucida(10), top: 295)
    }

    /// The X: a serif capital filled with Aqua's blue, light along its upper strokes, a deep
    /// rim, and the soft grey halo it sat in.
    private func drawX(in box: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext,
              let base = NSFont(name: "Baskerville", size: 100) else { return }
        let size = 100 * box.height / base.capHeight
        let font = NSFont(name: "Baskerville", size: size)!
        let glyph = CTFontGetGlyphWithName(font as CTFont, "X" as CFString)
        guard glyph != 0, let path = CTFontCreatePathForGlyph(font as CTFont, glyph, nil) else { return }
        let r = path.boundingBox
        var t = CGAffineTransform(translationX: box.minX, y: box.maxY)
            .scaledBy(x: box.width / r.width, y: -box.height / r.height)
            .translatedBy(x: -r.minX, y: -r.minY)
        guard let shape = path.copy(using: &t) else { return }

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 6, color: NSColor(white: 0, alpha: 0.35).cgColor)
        ctx.addPath(shape); ctx.setFillColor(NSColor(srgbRed: 0, green: 0.43, blue: 0.70, alpha: 1).cgColor); ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        let blue = NSGradient(colors: [NSColor(srgbRed: 0.76, green: 0.89, blue: 0.97, alpha: 1),
                                       NSColor(srgbRed: 0.27, green: 0.66, blue: 0.89, alpha: 1),
                                       NSColor(srgbRed: 0.00, green: 0.50, blue: 0.79, alpha: 1),
                                       NSColor(srgbRed: 0.30, green: 0.73, blue: 0.93, alpha: 1)],
                               atLocations: [0, 0.35, 0.7, 1], colorSpace: .sRGB)
        blue?.draw(in: box, angle: -90)
        // The gloss down the left of each stroke.
        ctx.setBlendMode(.screen)
        NSGradient(colors: [NSColor(white: 1, alpha: 0.55), NSColor(white: 1, alpha: 0)])?
            .draw(in: NSRect(x: box.minX, y: box.minY, width: box.width, height: box.height * 0.45), angle: -90)
        ctx.restoreGState()

        ctx.addPath(shape)
        ctx.setStrokeColor(NSColor(srgbRed: 0.05, green: 0.30, blue: 0.55, alpha: 0.8).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
    }
}

// MARK: - Mac OS 9

/// 479 × 281: the white plate with the Mac OS face and "Mac OS 9", Version, Built-in Memory,
/// Virtual Memory and Largest Unused Block, the copyright line, and the list of what is open with
/// a bar for each. Measured off 9.0's About This Computer.
private final class MacOS9AboutView: AboutChromeView {
    private let rows = ClassicAbout.memoryList()
    private var scroll = 0
    private let rowH: CGFloat = 16
    private let list = NSRect(x: 6, y: 189, width: 451, height: 86)   // top and bottom rule included

    init() { super.init(frame: NSRect(x: 0, y: 0, width: 479, height: 281)) }
    required init?(coder: NSCoder) { fatalError() }

    private static func grey(_ v: CGFloat) -> NSColor { NSColor(white: v / 255, alpha: 1) }
    override var closeRect: NSRect { PlatinumBar.boxRects(width: bounds.width).close }

    override func draw(_ dirtyRect: NSRect) {
        let g = Self.grey
        // The frame: black, white, two of light grey, mid grey, black — six points a side.
        for (i, v) in [CGFloat(0), 255, 213, 213, 169, 0].enumerated() {
            g(v).setStroke()
            NSBezierPath(rect: bounds.insetBy(dx: CGFloat(i) + 0.5, dy: CGFloat(i) + 0.5)).stroke()
        }
        g(227).setFill(); NSRect(x: 6, y: 22, width: bounds.width - 12, height: bounds.height - 28).fill()
        // The title bar RetroMac's other Platinum windows wear (`PlatinumBar`), so they match.
        let bar = NSRect(x: 0, y: 0, width: bounds.width, height: PlatinumBar.height)
        PlatinumBar.drawBar(bar, active: active)
        PlatinumBar.drawBox(closeRect, active: active, state: closePressed ? .pressed : .normal)
        PlatinumBar.drawTitle("About This Computer", icon: nil, in: bar, active: active, minX: closeRect.maxX + 8, maxX: bounds.width - closeRect.maxX - 8)

        // The plate: etched (grey above and left, white below and right), a black rule, white.
        g(153).setFill(); NSRect(x: 10, y: 26, width: 457, height: 1).fill(); NSRect(x: 10, y: 26, width: 1, height: 93).fill()
        g(255).setFill(); NSRect(x: 10, y: 119, width: 458, height: 1).fill(); NSRect(x: 467, y: 26, width: 1, height: 94).fill()
        NSColor.black.setStroke(); NSBezierPath(rect: NSRect(x: 11.5, y: 27.5, width: 455, height: 91)).stroke()
        NSColor.white.setFill(); NSRect(x: 12, y: 28, width: 454, height: 90).fill()
        drawFace()
        Self.serifWord("Mac OS 9", in: NSRect(x: 156, y: 44, width: 244, height: 61))

        let geneva = { (size: CGFloat, _: Bool) -> NSFont in NSFont(name: "Geneva", size: size) ?? .systemFont(ofSize: size) }
        func text(_ s: String, top: CGFloat, x: CGFloat, width: CGFloat = 330, bold: Bool = false, right: Bool = false) {
            let f = geneva(10, false)
            let p = NSMutableParagraphStyle(); p.alignment = right ? .right : .left; p.lineBreakMode = .byTruncatingTail
            // Geneva has no bold on macOS; a stroked fill gives the labels 9.0's weight.
            var attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: NSColor.black, .paragraphStyle: p]
            if bold { attrs[.strokeWidth] = -3.5; attrs[.strokeColor] = NSColor.black }
            (s as NSString).draw(in: NSRect(x: x, y: top - (f.ascender - f.capHeight), width: width, height: 14), withAttributes: attrs)
        }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let disk = FileManager.default.displayName(atPath: "/")
        let swap = SystemSampler.swapUsage().used
        let free = SystemSampler.vmStats().map { UInt64($0.free_count) * UInt64(vm_kernel_page_size) } ?? 0
        let info = [("Version:", "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")),
                    ("Built-in Memory:", ClassicAbout.size(ProcessInfo.processInfo.physicalMemory)),
                    ("Virtual Memory:", "\(ClassicAbout.size(swap)) used on \(disk)"),
                    ("Largest Unused Block:", ClassicAbout.size(free))]
        for (i, (label, value)) in info.enumerated() {
            let top = 126 + CGFloat(i) * 16
            text(label, top: top, x: 14, width: 115, bold: true)
            text(value, top: top, x: 130, width: i == 3 ? 115 : 320)
        }
        text("\u{2122} & \u{00A9} Apple Computer, Inc. 1983\u{2013}1999", top: 174, x: 250, width: 204, right: true)

        drawList(geneva(10, false))
    }

    /// The Mac OS face, 71 × 56 at (77, 45): dithered blue and grey halves, the profile running
    /// from above the square to below it, two eyes and the smile. Traced off 9.0's plate.
    private func drawFace() {
        let sq = NSRect(x: 77, y: 45, width: 71, height: 56)
        let split: CGFloat = 116
        for y in Int(sq.minY)..<Int(sq.maxY) {
            for x in Int(sq.minX)..<Int(sq.maxX) {
                let odd = (x + y) % 2 == 1
                let left = CGFloat(x) < split
                (left ? (odd ? NSColor(srgbRed: 64/255, green: 124/255, blue: 213/255, alpha: 1)
                             : NSColor(srgbRed: 121/255, green: 125/255, blue: 213/255, alpha: 1))
                      : (odd ? NSColor(srgbRed: 119/255, green: 172/255, blue: 1, alpha: 1)
                             : NSColor(white: 184/255, alpha: 1))).setFill()
                NSRect(x: x, y: y, width: 1, height: 1).fill()
            }
        }
        let navy = NSColor(srgbRed: 0, green: 0.06, blue: 0.42, alpha: 1)
        navy.setFill(); NSRect(x: 94, y: 52, width: 4, height: 11).fill()
        NSColor.black.setFill(); NSRect(x: 124, y: 52, width: 4, height: 11).fill()
        // The smile: navy on the blue half, black on the grey.
        let smile = NSBezierPath()
        smile.move(to: NSPoint(x: 88, y: 83)); smile.curve(to: NSPoint(x: 136, y: 83), controlPoint1: NSPoint(x: 104, y: 90), controlPoint2: NSPoint(x: 120, y: 90))
        smile.lineWidth = 2.6; smile.lineCapStyle = .round
        NSGraphicsContext.saveGraphicsState(); NSRect(x: 0, y: 0, width: split, height: bounds.height).clip(); navy.setStroke(); smile.stroke(); NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState(); NSRect(x: split, y: 0, width: bounds.width, height: bounds.height).clip(); NSColor.black.setStroke(); smile.stroke(); NSGraphicsContext.restoreGraphicsState()
        // The profile: forehead down to the nose, the nose out, then chin and neck below the square.
        let profile = NSBezierPath()
        profile.move(to: NSPoint(x: 121, y: 36))
        profile.curve(to: NSPoint(x: 105, y: 73), controlPoint1: NSPoint(x: 111, y: 46), controlPoint2: NSPoint(x: 105, y: 60))
        profile.line(to: NSPoint(x: 118, y: 75))
        profile.curve(to: NSPoint(x: 121, y: 108), controlPoint1: NSPoint(x: 115, y: 86), controlPoint2: NSPoint(x: 116, y: 99))
        profile.lineWidth = 3; profile.lineJoinStyle = .round; profile.lineCapStyle = .round
        NSColor.black.setStroke(); profile.stroke()
    }

    private var visibleRows: Int { Int((list.height - 2) / rowH) }

    private func drawList(_ font: NSFont) {
        let g = Self.grey
        g(184).setFill(); NSRect(x: 6, y: 188, width: bounds.width - 12, height: 1).fill()
        NSColor.black.setFill()
        NSRect(x: 6, y: list.minY, width: bounds.width - 12, height: 1).fill()
        NSRect(x: 6, y: list.maxY - 1, width: bounds.width - 12, height: 1).fill()
        g(241).setFill(); NSRect(x: 6, y: list.minY + 1, width: list.width, height: list.height - 2).fill()

        let largest = max(rows.map(\.bytes).max() ?? 1, 1)
        for (n, row) in rows.dropFirst(scroll).prefix(visibleRows).enumerated() {
            let top = list.minY + 1 + CGFloat(n) * rowH
            row.icon?.draw(in: NSRect(x: 22, y: top, width: 16, height: 16), from: .zero, operation: .sourceOver,
                           fraction: 1, respectFlipped: true, hints: nil)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let y = top + 4 - (font.ascender - font.capHeight)
            (row.name as NSString).draw(in: NSRect(x: 44, y: y, width: 150, height: 14), withAttributes: attrs)
            let size = ClassicAbout.size(row.bytes) as NSString
            let sw = size.size(withAttributes: attrs).width
            size.draw(at: NSPoint(x: 252 - sw, y: y), withAttributes: attrs)
            // The bar: a black frame, filled in the blue of 9.0's partition bars, as far as this
            // app's share of the largest one.
            let frame = NSRect(x: 264, y: top + 2, width: 183, height: 12)
            NSColor.black.setStroke(); NSBezierPath(rect: frame.insetBy(dx: 0.5, dy: 0.5)).stroke()
            let fill = NSRect(x: frame.minX + 1, y: frame.minY + 1,
                              width: (frame.width - 2) * CGFloat(Double(row.bytes) / Double(largest)), height: frame.height - 2)
            NSGradient(colors: [NSColor(srgbRed: 0.26, green: 0.28, blue: 0.66, alpha: 1),
                                NSColor(srgbRed: 0.84, green: 0.84, blue: 1, alpha: 1),
                                NSColor(srgbRed: 0.26, green: 0.28, blue: 0.66, alpha: 1)],
                       atLocations: [0, 0.45, 1], colorSpace: .sRGB)?.draw(in: fill, angle: 90)
        }
        // The scroll bar along the right: a track, and a thumb while there is more than fits.
        let track = NSRect(x: 457, y: list.minY, width: 16, height: list.height)
        NSColor.black.setStroke(); NSBezierPath(rect: track.insetBy(dx: 0.5, dy: 0.5)).stroke()
        g(213).setFill(); track.insetBy(dx: 1, dy: 1).fill()
        let extra = rows.count - visibleRows
        if extra > 0 {
            let room = track.height - 2 - 16
            let thumb = NSRect(x: track.minX + 1, y: track.minY + 1 + room * CGFloat(scroll) / CGFloat(extra), width: 14, height: 16)
            g(170).setFill(); thumb.fill()
            NSColor.black.setStroke(); NSBezierPath(rect: thumb.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let extra = max(0, rows.count - visibleRows)
        let step = event.scrollingDeltaY > 0 ? -1 : event.scrollingDeltaY < 0 ? 1 : 0
        let next = min(max(0, scroll + step), extra)
        if next != scroll { scroll = next; needsDisplay = true }
    }
}
