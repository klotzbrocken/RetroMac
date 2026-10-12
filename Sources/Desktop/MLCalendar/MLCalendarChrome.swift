import AppKit

// Leather header (traffic lights, title, Calendars / +, Day-Week-Month-Year, search) and the sidebar.

// MARK: - Search field

final class MLSearchField: NSView {
    unowned var ctl: MLController
    let field = NSTextField()

    init(_ ctl: MLController) {
        self.ctl = ctl
        super.init(frame: .zero)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = mlFont(11)
        field.delegate = ctl
        field.cell?.usesSingleLineMode = true
        field.setAccessibilityLabel(L("Suchen", "Search"))
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    private var focused: Bool { (window?.firstResponder as? NSTextView)?.delegate === field }

    override func layout() {
        super.layout()
        field.frame = NSRect(x: 19, y: 1, width: bounds.width - 19 - 17, height: bounds.height - 2)
    }

    override func draw(_ dirty: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let pill = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        mlRGB(255, 255, 255).setFill(); pill.fill()
        NSGraphicsContext.saveGraphicsState(); pill.addClip()
        mlRGB(0, 0, 0, 0.18).setFill(); NSRect(x: 0, y: 0, width: bounds.width, height: 1.5).fill()   // inner top shadow
        NSGraphicsContext.restoreGraphicsState()
        (focused ? mlRGB(61, 120, 178) : mlRGB(104, 78, 36)).setStroke()
        pill.lineWidth = focused ? 2 : 1
        pill.stroke()
        // magnifier
        let c = NSPoint(x: 11.5, y: bounds.midY - 1)
        mlRGB(40, 40, 40).setStroke()
        let lens = NSBezierPath(ovalIn: NSRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)); lens.lineWidth = 1.2; lens.stroke()
        let h = NSBezierPath(); h.move(to: NSPoint(x: c.x + 2.6, y: c.y + 2.6)); h.line(to: NSPoint(x: c.x + 5.4, y: c.y + 5.4)); h.lineWidth = 1.6; h.stroke()
        // clear button
        if !field.stringValue.isEmpty {
            let x = NSRect(x: bounds.width - 15, y: bounds.midY - 5, width: 10, height: 10)
            mlRGB(150, 150, 150).setFill(); NSBezierPath(ovalIn: x).fill()
            let g = NSBezierPath()
            g.move(to: NSPoint(x: x.minX + 3, y: x.minY + 3)); g.line(to: NSPoint(x: x.maxX - 3, y: x.maxY - 3))
            g.move(to: NSPoint(x: x.maxX - 3, y: x.minY + 3)); g.line(to: NSPoint(x: x.minX + 3, y: x.maxY - 3))
            NSColor.white.setStroke(); g.lineWidth = 1.3; g.stroke()
        }
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if !field.stringValue.isEmpty, p.x > bounds.width - 18 { ctl.clearSearch() } else { ctl.focusSearch() }
        needsDisplay = true
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .iBeam) }
    override func isAccessibilityElement() -> Bool { false }
}

// MARK: - Header

final class MLHeaderView: MLView {
    /// The header view reaches 4 units below the leather bar so the paper wisps can overlap the content area.
    static let height: CGFloat = 47
    static let chromeH: CGFloat = 39
    private(set) var plusRect = NSRect.zero
    private var hover: Int?              // 0…2 traffic lights
    private var pressed: String?
    private var groupHover = false

    override init(_ ctl: MLController) {
        super.init(ctl)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { true }
    /// The wisps overlap the content area; clicks there belong to the views underneath.
    override func hitTest(_ p: NSPoint) -> NSView? { p.y > Self.chromeH ? nil : super.hitTest(p) }

    private var lightCenters: [NSPoint] { (0..<3).map { NSPoint(x: 9 + CGFloat($0) * 13.4, y: 8) } }
    private var calendarsRect: NSRect { NSRect(x: 5, y: 16, width: 48, height: 15) }
    private var segW: CGFloat { 42 }
    private var segRect: NSRect { NSRect(x: (bounds.width / 2 - segW * 2).rounded(), y: 16, width: segW * 4, height: 15) }

    override func layout() {
        super.layout()
        let w: CGFloat = 130
        ctl.searchField.frame = NSRect(x: bounds.width - w - 7, y: 15.5, width: w, height: 16)
    }

    override func draw(_ dirty: NSRect) {
        hots = []
        let w = bounds.width
        MLLeather.fill(NSRect(x: 0, y: 0, width: w, height: 35))
        MLLeather.bar(width: w, y: 35)
        MLLeather.wisps(width: w, y: 35 + MLLeather.barHeight - 0.7)
        drawResizeGlyph(w)

        // title
        let title = L("Kalender", "Calendar")
        mlText(title, NSRect(x: 0, y: 1, width: w, height: 14), mlFont(11), mlRGB(48, 36, 18, ctl.isActive ? 1 : 0.55), align: .center,
               shadow: mlRGB(255, 240, 200, 0.6))

        // traffic lights
        mlTrafficLights(centers: lightCenters, dia: 9, active: ctl.isActive, hover: groupHover)
        for (i, name) in [L("Schließen", "Close"), L("Minimieren", "Minimize"), L("Zoomen", "Zoom")].enumerated() {
            let c = lightCenters[i]
            hots.append(MLHot(rect: NSRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12), label: name) { [weak self] in
                guard let win = self?.window else { return }
                [{ win.close() }, { win.miniaturize(nil) }, { win.zoom(nil) }][i]()
            })
        }

        // Calendars / +
        plusRect = NSRect(x: 59, y: 16, width: 18, height: 15)
        button(calendarsRect, L("Kalender", "Calendars"), on: false, key: "cal")
        button(plusRect, "+", on: false, key: "plus", font: mlFont(14))
        hots.append(MLHot(rect: calendarsRect, label: L("Kalenderliste ein-/ausblenden", "Show or hide calendar list")) { [weak self] in self?.ctl.toggleSidebar() })
        hots.append(MLHot(rect: plusRect, label: L("Neuer Termin (Schnelleingabe)", "New event (quick entry)")) { [weak self] in self?.ctl.showQuickEntry() })

        // Day / Week / Month / Year: one recessed group with dividers (reference crop: 3-unit corners, dark brown outline)
        let names = [L("Tag", "Day"), L("Woche", "Week"), L("Monat", "Month"), L("Jahr", "Year")]
        let g = segRect
        let outline = NSBezierPath(roundedRect: g.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        NSGraphicsContext.saveGraphicsState(); outline.addClip()
        for i in 0..<4 {
            let r = NSRect(x: g.minX + CGFloat(i) * segW, y: g.minY, width: segW, height: g.height)
            if ctl.mode.rawValue == i {
                mlGradient(r, [(0, mlRGB(104, 76, 40)), (1, mlRGB(132, 100, 58))])
                mlRGB(48, 30, 12, 0.55).setFill(); NSRect(x: r.minX, y: r.minY, width: r.width, height: 2).fill()
            } else {
                Self.recessFill(r, pressed: pressed == "seg\(i)")
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        for i in 1..<4 where ctl.mode.rawValue != i && ctl.mode.rawValue != i - 1 {
            let x = g.minX + CGFloat(i) * segW
            mlRGB(132, 94, 50).setFill(); NSRect(x: x, y: g.minY + 3, width: 1, height: g.height - 6).fill()
            mlRGB(255, 232, 186, 0.45).setFill(); NSRect(x: x + 1, y: g.minY + 3, width: 0.7, height: g.height - 6).fill()
        }
        if ctl.mode.rawValue > 0 { let x = g.minX + CGFloat(ctl.mode.rawValue) * segW; mlRGB(86, 60, 30).setFill(); NSRect(x: x, y: g.minY, width: 1, height: g.height).fill() }
        if ctl.mode.rawValue < 3 { let x = g.minX + CGFloat(ctl.mode.rawValue + 1) * segW; mlRGB(86, 60, 30).setFill(); NSRect(x: x - 0.5, y: g.minY, width: 1, height: g.height).fill() }
        mlRGB(255, 232, 186, 0.4).setFill(); NSRect(x: g.minX + 2, y: g.maxY, width: g.width - 4, height: 0.8).fill()      // light lip under the group
        mlRGB(86, 60, 30).setStroke(); outline.lineWidth = 1; outline.stroke()
        for i in 0..<4 {
            let r = NSRect(x: g.minX + CGFloat(i) * segW, y: g.minY, width: segW, height: g.height)
            let on = ctl.mode.rawValue == i
            mlText(names[i], r, mlFont(9.5, bold: on), on ? .white : mlRGB(40, 24, 8), align: .center, shadow: on ? mlRGB(0, 0, 0, 0.55) : mlRGB(255, 232, 186, 0.4))
            hots.append(MLHot(rect: r, label: names[i], role: .radioButton) { [weak self] in self?.ctl.setMode(MLMode(rawValue: i)!) })
        }
    }

    /// Leather seen through a shallow recess: lighter at the top, darker toward a ridge at the bottom.
    static func recessFill(_ r: NSRect, pressed: Bool) {
        mlGradient(r, [(0, mlRGB(255, 240, 200, pressed ? 0.04 : 0.16)), (0.5, mlRGB(255, 240, 200, 0)), (1, mlRGB(70, 44, 12, pressed ? 0.30 : 0.14))])
        mlRGB(255, 240, 200, 0.4).setFill(); NSRect(x: r.minX, y: r.minY + 1, width: r.width, height: 1).fill()
        mlRGB(100, 68, 30, 0.45).setFill(); NSRect(x: r.minX, y: r.maxY - 2, width: r.width, height: 1).fill()
    }

    /// Full-screen / resize glyph in the top-right corner (two small corner arrows).
    private var resizeRect: NSRect { NSRect(x: bounds.width - 15, y: 3, width: 10, height: 10) }
    /// Two small solid corner-arrows pointing apart (reference: blocky, dark brown, one NE and one SW).
    private func drawResizeGlyph(_ w: CGFloat) {
        let r = resizeRect
        func arrow(corner: NSPoint, dx: CGFloat, dy: CGFloat) {
            // dx/dy = direction (+1/-1) the arrow points; head is a right triangle in the corner, shaft runs back diagonally
            let head = NSBezierPath()
            head.move(to: corner); head.line(to: NSPoint(x: corner.x - dx * 3.8, y: corner.y)); head.line(to: NSPoint(x: corner.x, y: corner.y - dy * 3.8)); head.close()
            let shaft = NSBezierPath(); shaft.lineWidth = 1.5
            shaft.move(to: NSPoint(x: corner.x - dx * 1.4, y: corner.y - dy * 1.4)); shaft.line(to: NSPoint(x: corner.x - dx * 3.3, y: corner.y - dy * 3.3))
            mlRGB(255, 232, 186, 0.45).setFill(); head.transform(using: AffineTransform(translationByX: 0, byY: 0.6)); head.fill(); head.transform(using: AffineTransform(translationByX: 0, byY: -0.6))
            mlRGB(98, 70, 30).setFill(); head.fill(); mlRGB(98, 70, 30).setStroke(); shaft.stroke()
        }
        arrow(corner: NSPoint(x: r.maxX, y: r.minY), dx: 1, dy: -1)          // top-right
        arrow(corner: NSPoint(x: r.minX + 1, y: r.maxY), dx: -1, dy: 1)      // bottom-left
        hots.append(MLHot(rect: r.insetBy(dx: -3, dy: -3), label: L("Vollbild", "Full screen")) { [weak self] in self?.window?.toggleFullScreen(nil) })
    }

    private func button(_ r: NSRect, _ t: String, on: Bool, key: String, font: NSFont = mlFont(9.5)) {
        let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        NSGraphicsContext.saveGraphicsState(); path.addClip()
        Self.recessFill(r, pressed: pressed == key)
        NSGraphicsContext.restoreGraphicsState()
        mlRGB(255, 232, 186, 0.4).setFill(); NSRect(x: r.minX + 2, y: r.maxY, width: r.width - 4, height: 0.8).fill()
        mlRGB(86, 60, 30).setStroke(); path.lineWidth = 1; path.stroke()
        mlText(t, r, font, mlRGB(40, 24, 8), align: .center, shadow: mlRGB(255, 232, 186, 0.4))
    }

    private func segment(_ r: NSRect, _ t: String, on: Bool, first: Bool, last: Bool, key: String) {
        let down = pressed == key
        let rad: CGFloat = 4
        let path = NSBezierPath()
        let rr = r.insetBy(dx: 0.5, dy: 0.5)
        if first && last { path.appendRoundedRect(rr, xRadius: rad, yRadius: rad) } else {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: NSRect(x: first ? rr.minX : rr.minX - rad, y: rr.minY, width: rr.width + (first || last ? rad : 2 * rad), height: rr.height), xRadius: rad, yRadius: rad).addClip()
            path.appendRect(rr)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: NSRect(x: first ? r.minX : r.minX - rad, y: r.minY, width: r.width + (first || last ? rad : 2 * rad), height: r.height), xRadius: rad, yRadius: rad).addClip()
        if on {
            mlGradient(r, [(0, mlRGB(104, 72, 30)), (1, mlRGB(138, 100, 48))])
            mlRGB(0, 0, 0, 0.35).setFill(); NSRect(x: r.minX, y: r.minY, width: r.width, height: 2).fill()
        } else {
            let k: CGFloat = down ? 0.25 : 0
            mlGradient(r, [(0, mlMix(mlRGB(205, 168, 108), .black, k)), (1, mlMix(mlRGB(190, 152, 92), .black, k))])
            mlRGB(255, 236, 190, 0.45).setFill(); NSRect(x: r.minX, y: r.minY + 1, width: r.width, height: 1).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        // outline: the group is one rounded rect, with dividers between segments
        mlRGB(110, 76, 16).setFill()
        if first { NSRect(x: r.minX, y: r.minY + 2, width: 1, height: r.height - 4).fill() }
        NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
        NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
        mlText(t, r, mlFont(10, bold: on), on ? .white : .black, align: .center,
               shadow: on ? mlRGB(0, 0, 0, 0.5) : mlRGB(255, 235, 190, 0.5))
    }

    // MARK: mouse

    override func mouseMoved(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let g = NSRect(x: 4, y: 1, width: 50, height: 16).contains(p)
        if g != groupHover { groupHover = g; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { groupHover = false; needsDisplay = true }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard let h = hot(at: p) else { super.mouseDown(with: e); return }
        // Highlight while the button is held; fire on release inside (like an NSButton).
        let key = h.label
        pressed = h.role == .radioButton ? nil : key
        needsDisplay = true
        var inside = true
        while let ev = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            inside = h.rect.contains(convert(ev.locationInWindow, from: nil))
            if ev.type == .leftMouseUp { break }
        }
        pressed = nil; needsDisplay = true
        if inside { h.action() }
    }
}

// MARK: - Sidebar

final class MLSidebarView: MLView {
    static let width: CGFloat = 112
    private var pressedDay: Date?
    private let palette: [UInt32] = [0xD9432B, 0xF08A24, 0xE8C21A, 0x4DA83B, 0x2F6FD6, 0x8A4FC0, 0x8F6B3F]

    override func draw(_ dirty: NSRect) {
        hots = []; localRows = []
        let w = bounds.width
        mlRGB(245, 245, 245).setFill(); bounds.fill()
        mlLine(NSRect(x: w - 1, y: 0, width: 1, height: bounds.height), mlRGB(190, 190, 190))

        var y: CGFloat = 8
        section(L("Auf meinem Mac", "On My Mac"), ctl.store.calendars, system: false, y: &y)
        let add = NSRect(x: 0, y: y, width: w - 1, height: 14)
        mlText("+ " + L("Neuer Kalender…", "New Calendar…"), NSRect(x: 10, y: y, width: w - 14, height: 14), mlFont(10), mlRGB(130, 130, 130))
        hots.append(MLHot(rect: add, label: L("Neuer Kalender", "New Calendar")) { [weak self] in self?.newCalendar() })
        y += 18
        if !MLSystem.shared.isActive {
            let r = NSRect(x: 0, y: y, width: w - 1, height: 14)
            let denied = MLSystem.shared.enabled && MLSystem.shared.status != .notDetermined
            mlText("+ " + (denied ? L("Zugriff erlauben…", "Allow Access…") : L("Systemkalender…", "System Calendars…")),
                   NSRect(x: 10, y: y, width: w - 14, height: 14), mlFont(10), mlRGB(130, 130, 130))
            hots.append(MLHot(rect: r, label: L("Systemkalender verbinden", "Connect system calendars")) { [weak self] in
                if denied { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!) }
                else { MLSystem.shared.setEnabled(true) { self?.ctl.refresh() } }
            })
            y += 18
        }
        if MLSystem.shared.isActive {
            var groups: [(String, [MLCal])] = []
            for c in MLSystem.shared.calendars {
                let g = c.group ?? L("Systemkalender", "System Calendars")
                if let i = groups.firstIndex(where: { $0.0 == g }) { groups[i].1.append(c) } else { groups.append((g, [c])) }
            }
            for (title, cals) in groups { section(title, cals, system: true, y: &y) }
        }
        y = max(y + 14, 118)

        // mini months
        let cal = ctl.cal
        var month = cal.dateInterval(of: .month, for: ctl.date)!.start
        var idx = 0
        while true {
            let weeks = miniWeeks(month)
            let h = 14 + 12 + CGFloat(weeks) * 16 + 8
            if y + 14 > bounds.height { break }
            drawMini(month, y: y, withArrows: idx == 0)
            y += h; idx += 1
            month = cal.date(byAdding: .month, value: 1, to: month)!
            if idx == 6 { break }
        }
    }

    private let rowH: CGFloat = 14
    private var localRows: [(NSRect, MLCal)] = []

    /// Account heading and its calendars, like the reference: grey heading, tinted checkbox when visible, grey when hidden.
    private func section(_ title: String, _ cals: [MLCal], system: Bool, y: inout CGFloat) {
        let w = bounds.width
        guard !cals.isEmpty || !system else { return }
        mlText(title, NSRect(x: 7, y: y, width: w - 12, height: 13), mlFont(10, bold: true), mlRGB(150, 150, 150))
        y += 14
        for c in cals {
            guard y + rowH < bounds.height - 70 else { break }
            let selected = ctl.defaultCalID == c.id
            if selected {
                let row = NSRect(x: 0, y: y, width: w - 1, height: rowH)
                mlGradient(row, [(0, mlRGB(168, 180, 198)), (1, mlRGB(132, 148, 170))])
                mlRGB(100, 112, 134).setFill(); NSRect(x: 0, y: row.minY, width: row.width, height: 1).fill()
            }
            if !system { localRows.append((NSRect(x: 0, y: y, width: w, height: rowH), c)) }
            checkbox(NSRect(x: 12, y: y + 2.5, width: 9, height: 9), on: c.visible, tint: c.color)
            mlText(c.name + (c.readOnly ? " 🔒" : ""), NSRect(x: 26, y: y, width: w - 30, height: rowH), mlFont(10.5, bold: selected),
                   selected ? .white : mlRGB(30, 30, 30), shadow: selected ? mlRGB(0, 0, 0, 0.35) : nil)
            hots.append(MLHot(rect: NSRect(x: 6, y: y, width: 18, height: rowH), label: "\(c.name), " + L("sichtbar", "visible"), role: .checkBox) { [weak self] in
                if system { MLSystem.shared.toggle(c.id) } else { var n = c; n.visible.toggle(); self?.ctl.store.updateCalendar(n) }
            })
            if !c.readOnly {
                hots.append(MLHot(rect: NSRect(x: 24, y: y, width: w - 25, height: rowH), label: c.name, role: .row) { [weak self] in
                    self?.ctl.defaultCalID = c.id; self?.needsDisplay = true
                })
            }
            y += rowH
        }
        y += 4
    }

    private func checkbox(_ r: NSRect, on: Bool, tint: NSColor) {
        let p = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
        if on {
            mlGradient(r, [(0, mlMix(tint, .white, 0.45)), (1, mlMix(tint, .white, 0.05))], radius: 2)
            mlMix(tint, .black, 0.35).setStroke(); p.lineWidth = 1; p.stroke()
            let c = NSBezierPath()
            c.move(to: NSPoint(x: r.minX + 2, y: r.midY + 0.3)); c.line(to: NSPoint(x: r.minX + 3.8, y: r.maxY - 2)); c.line(to: NSPoint(x: r.maxX - 1.5, y: r.minY + 1.5))
            NSColor.white.setStroke(); c.lineWidth = 1.5; c.lineCapStyle = .round; c.lineJoinStyle = .round; c.stroke()
        } else {
            mlGradient(r, [(0, .white), (1, mlRGB(214, 214, 214))], radius: 2)
            mlRGB(140, 140, 140).setStroke(); p.lineWidth = 1; p.stroke()
        }
    }

    private func miniWeeks(_ first: Date) -> Int {
        let cal = ctl.cal
        let off = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        return (off + cal.range(of: .day, in: .month, for: first)!.count + 6) / 7
    }

    private func drawMini(_ first: Date, y: CGFloat, withArrows: Bool) {
        let cal = ctl.cal
        let w = bounds.width
        let cw: CGFloat = 14, x0 = (w - cw * 7) / 2
        mlText(MLPrefs.fmt(first, "yMMMM"), NSRect(x: 0, y: y, width: w - 1, height: 14), mlFont(9, bold: true), mlRGB(120, 120, 120), align: .center)
        if withArrows {
            for (dir, x) in [(-1, CGFloat(8)), (1, w - 16)] {
                let tri = NSBezierPath()
                if dir < 0 { tri.move(to: NSPoint(x: x + 4, y: y + 3.5)); tri.line(to: NSPoint(x: x + 4, y: y + 10.5)); tri.line(to: NSPoint(x: x, y: y + 7)) }
                else { tri.move(to: NSPoint(x: x, y: y + 3.5)); tri.line(to: NSPoint(x: x, y: y + 10.5)); tri.line(to: NSPoint(x: x + 4, y: y + 7)) }
                tri.close(); mlRGB(110, 110, 110).setFill(); tri.fill()
                hots.append(MLHot(rect: NSRect(x: x - 3, y: y, width: 12, height: 14), label: dir < 0 ? L("Vorheriger Monat", "Previous month") : L("Nächster Monat", "Next month")) { [weak self] in
                    guard let s = self else { return }
                    s.ctl.date = cal.date(byAdding: .month, value: dir, to: s.ctl.date)!; s.ctl.refresh()
                })
            }
        }
        // weekday initials
        let sym = cal.veryShortStandaloneWeekdaySymbols, short = cal.shortStandaloneWeekdaySymbols
        for i in 0..<7 {
            let wd = (cal.firstWeekday - 1 + i) % 7
            let t = MLPrefs.isDE ? String(short[wd].prefix(2)) : String(short[wd].prefix(2))
            _ = sym
            mlText(t, NSRect(x: x0 + CGFloat(i) * cw, y: y + 13, width: cw, height: 11), mlFont(8), mlRGB(120, 120, 120), align: .center)
        }
        mlLine(NSRect(x: x0 - 2, y: y + 24, width: cw * 7 + 4, height: 1), mlRGB(215, 215, 215))
        let off = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -off, to: first)!
        let thisMonth = cal.component(.month, from: first)
        for i in 0..<(miniWeeks(first) * 7) {
            let d = cal.date(byAdding: .day, value: i, to: start)!
            let r = NSRect(x: x0 + CGFloat(i % 7) * cw, y: y + 26 + CGFloat(i / 7) * 16, width: cw, height: 16)
            let isToday = cal.isDate(d, inSameDayAs: ctl.today), sel = cal.isDate(d, inSameDayAs: ctl.date)
            let inMonth = cal.component(.month, from: d) == thisMonth
            if sel {
                mlRGB(70, 130, 215, isToday ? 1 : 0.22).setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 0.5), xRadius: 2, yRadius: 2).fill()
            }
            let col: NSColor = isToday ? (sel ? .white : mlRGB(20, 100, 220)) : inMonth ? mlRGB(105, 105, 105) : mlRGB(195, 195, 195)
            mlText("\(cal.component(.day, from: d))", r, mlFont(9, bold: isToday), col, align: .center)
            hots.append(MLHot(rect: r, label: MLPrefs.fmt(d, "yMMMMEEEEd"), role: .button) { [weak self] in self?.ctl.select(date: d) })
        }
    }

    // MARK: calendar management (FUN-03)

    private func newCalendar() {
        guard let name = prompt(L("Name des neuen Kalenders", "Name of the new calendar"), "") else { return }
        let n = ctl.store.calendars.count
        ctl.defaultCalID = ctl.store.addCalendar(name: name, colorHex: palette[n % palette.count])
    }

    private func prompt(_ message: String, _ initial: String) -> String? {
        let a = NSAlert()
        a.messageText = message
        a.addButton(withTitle: "OK"); a.addButton(withTitle: L("Abbrechen", "Cancel"))
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22)); f.stringValue = initial
        a.accessoryView = f
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        let s = f.stringValue.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        hot(at: p)?.action()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        let m = NSMenu()
        for (rect, c) in localRows {
            guard rect.contains(p) else { continue }
            func item(_ t: String, _ f: @escaping () -> Void) { let i = MLBlockItem(t, f); m.addItem(i) }
            item(L("Umbenennen…", "Rename…")) { [weak self] in
                if let n = self?.prompt(L("Neuer Name", "New name"), c.name) { var u = c; u.name = n; self?.ctl.store.updateCalendar(u) }
            }
            let colors = NSMenuItem(title: L("Farbe", "Color"), action: nil, keyEquivalent: ""); let sub = NSMenu()
            for hex in palette {
                let i = MLBlockItem(String(format: "#%06X", hex)) { [weak self] in var u = c; u.colorHex = hex; self?.ctl.store.updateCalendar(u) }
                i.image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { r in
                    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1).setFill(); NSBezierPath(ovalIn: r).fill(); return true
                }
                i.title = ""; sub.addItem(i)
            }
            colors.submenu = sub; m.addItem(colors)
            item(c.readOnly ? L("Schreibschutz aufheben", "Allow Editing") : L("Schreibschützen", "Make Read-Only")) { [weak self] in var u = c; u.readOnly.toggle(); self?.ctl.store.updateCalendar(u) }
            m.addItem(.separator())
            item(L("Kalender löschen…", "Delete Calendar…")) { [weak self] in
                guard let s = self else { return }
                let a = NSAlert(); a.messageText = L("„\(c.name)“ und alle Termine darin löschen?", "Delete “\(c.name)” and all its events?")
                a.informativeText = L("Das lässt sich mit „Rückgängig“ wiederherstellen.", "You can bring it back with Undo.")
                a.addButton(withTitle: L("Löschen", "Delete")); a.addButton(withTitle: L("Abbrechen", "Cancel"))
                if a.runModal() == .alertFirstButtonReturn { s.ctl.store.deleteCalendar(c.id) }
            }
            return m
        }
        let i = MLBlockItem(L("Neuer Kalender…", "New Calendar…")) { [weak self] in self?.newCalendar() }
        m.addItem(i)
        return m
    }

    override func isAccessibilityElement() -> Bool { false }
}

/// NSMenuItem that runs a closure.
final class MLBlockItem: NSMenuItem {
    private let block: () -> Void
    init(_ title: String, key: String = "", _ block: @escaping () -> Void) {
        self.block = block
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { block() }
}
