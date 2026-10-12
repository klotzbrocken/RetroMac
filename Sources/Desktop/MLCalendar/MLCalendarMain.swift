import AppKit

// The content area: title, navigation, and the Day / Week / Month / Year renderings with mouse interaction.

private struct Hit {
    enum Kind { case event(MLOcc), day(Date), slot(Int), more(Date), search(MLOcc), dayHeader(Date), resize(MLOcc) }
    var rect: NSRect
    var kind: Kind
}

private struct TimeGeom {
    var viewport: NSRect
    var gutter: CGFloat
    var colW: CGFloat
    var days: [Date]
    var hourH: CGFloat
    var scroll: CGFloat
}

private enum DragKind { case move, resize }
private struct Drag {
    var occ: MLOcc
    var kind: DragKind
    var grabDay: Date           // day under the cursor at mouse-down
    var grabMinutes: Int        // minutes into that day at mouse-down
    var origin: NSPoint
    var active = false
    var newStart: Date
    var newEnd: Date
}

final class MLMainView: MLView {
    private var hits: [Hit] = []
    private var geom: TimeGeom?
    private var drag: Drag?
    private var scrollY: CGFloat = -1
    private let hourH: CGFloat = 39
    private var navRects: (prev: NSRect, today: NSRect, next: NSRect) = (.zero, .zero, .zero)
    private var navPressed = 0

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    private var cal: Calendar { ctl.cal }

    override init(_ ctl: MLController) {
        super.init(ctl)
        setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError() }

    func scrollToDayStart() { scrollY = CGFloat(MLPrefs.dayStart) * hourH }

    private var searching: Bool { !ctl.query.trimmingCharacters(in: .whitespaces).isEmpty }
    private let searchW: CGFloat = 150

    // MARK: data

    private func occs(_ lo: Date, _ hi: Date) -> [MLOcc] {
        var list = ctl.store.occurrences(from: lo, to: hi)
        if let d = drag, d.active, let i = list.firstIndex(where: { $0.id == d.occ.id }) {
            list[i].start = d.newStart; list[i].end = d.newEnd
            if !(d.newStart < hi && d.newEnd > lo) { list.remove(at: i) }
        }
        return list
    }

    private func color(_ o: MLOcc) -> NSColor { ctl.store.calendar(o.ev.calID)?.color ?? .gray }
    private func isBar(_ o: MLOcc) -> Bool { o.ev.allDay || o.end.timeIntervalSince(o.start) >= 86400 }
    private func minutes(_ d: Date) -> Int { let c = cal.dateComponents([.hour, .minute], from: d); return (c.hour ?? 0) * 60 + (c.minute ?? 0) }
    private func dayName(_ d: Date) -> String { MLPrefs.fmt(d, "EEE").replacingOccurrences(of: ".", with: "") }

    private func describe(_ o: MLOcc) -> String {
        let c = ctl.store.calendar(o.ev.calID)?.name ?? ""
        let when = o.ev.allDay ? L("ganztägig", "all-day") : "\(MLPrefs.time(o.start)) – \(MLPrefs.time(o.end))"
        return "\(o.title), \(MLPrefs.fmt(o.start, "yMMMMd")), \(when), \(c)" + (o.ev.location.isEmpty ? "" : ", \(o.ev.location)")
    }

    // MARK: drawing

    override func draw(_ dirty: NSRect) {
        hits = []; geom = nil
        mlRGB(255, 255, 255).setFill(); bounds.fill()
        let panel = searching ? searchW : 0
        let areaW = bounds.width - panel
        let pad: CGFloat = 8

        let timeMode = ctl.mode == .week || ctl.mode == .day
        let left: CGFloat = ctl.mode == .week ? 36 : pad          // week: hour labels live to the left of the frame
        mlText(ctl.title, NSRect(x: left, y: 2, width: areaW - 110 - left, height: 28), mlFont(ctl.mode == .day ? 17 : 19.5), .black)
        drawNav(areaW)

        let g = NSRect(x: timeMode ? left : pad, y: 31, width: areaW - (timeMode ? left : pad) - 9, height: bounds.height - 31 - 11)
        switch ctl.mode {
        case .month: drawMonth(g)
        case .week: drawTime(g, days: (0..<7).map { cal.date(byAdding: .day, value: $0, to: ctl.weekStart(of: ctl.date))! }, header: true)
        case .day: drawDay(g)
        case .year: drawYear(g)
        }
        if searching { drawSearch(NSRect(x: areaW, y: 0, width: panel, height: bounds.height)) }
        drawMenuFocus()
    }

    private func drawMenuFocus() {}

    private func drawNav(_ areaW: CGFloat) {
        let r = NSRect(x: areaW - 10 - 74, y: 8, width: 74, height: 16)
        navRects = (NSRect(x: r.minX, y: r.minY, width: 19, height: 16), NSRect(x: r.minX + 19, y: r.minY, width: 36, height: 16), NSRect(x: r.maxX - 19, y: r.minY, width: 19, height: 16))
        let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 3.5, yRadius: 3.5)
        mlGradient(r, [(0, .white), (1, mlRGB(236, 236, 236))], radius: 3.5)
        for (i, rc) in [navRects.prev, navRects.today, navRects.next].enumerated() where navPressed == i + 1 {
            NSGraphicsContext.saveGraphicsState(); path.addClip(); mlRGB(0, 0, 0, 0.12).setFill(); rc.fill(); NSGraphicsContext.restoreGraphicsState()
        }
        mlRGB(190, 190, 190).setStroke(); path.lineWidth = 1; path.stroke()
        mlLine(NSRect(x: r.minX + 19, y: r.minY + 1, width: 1, height: 14), mlRGB(200, 200, 200))
        mlLine(NSRect(x: r.maxX - 20, y: r.minY + 1, width: 1, height: 14), mlRGB(200, 200, 200))
        mlText(L("Heute", "Today"), navRects.today, mlFont(10), .black, align: .center)
        for (dir, rc) in [(-1, navRects.prev), (1, navRects.next)] {
            let c = NSPoint(x: rc.midX, y: rc.midY)
            let t = NSBezierPath()
            t.move(to: NSPoint(x: c.x - CGFloat(dir) * 2.5, y: c.y - 3.5)); t.line(to: NSPoint(x: c.x - CGFloat(dir) * 2.5, y: c.y + 3.5)); t.line(to: NSPoint(x: c.x + CGFloat(dir) * 2.5, y: c.y))
            t.close(); NSColor.black.setFill(); t.fill()
        }
        hots = [
            MLHot(rect: navRects.prev, label: L("Zurück", "Previous")) { [weak self] in self?.ctl.step(-1) },
            MLHot(rect: navRects.today, label: L("Heute", "Today")) { [weak self] in self?.ctl.goToday() },
            MLHot(rect: navRects.next, label: L("Vor", "Next")) { [weak self] in self?.ctl.step(1) },
        ]
    }

    // MARK: month

    private func drawMonth(_ g: NSRect) {
        let first = cal.dateInterval(of: .month, for: ctl.date)!.start
        let off = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let dim = cal.range(of: .day, in: .month, for: first)!.count
        let rows = (off + dim + 6) / 7
        let start = cal.date(byAdding: .day, value: -off, to: first)!
        let end = cal.date(byAdding: .day, value: rows * 7, to: start)!
        let list = occs(start, end)
        func cx(_ i: Int) -> CGFloat { g.minX + (g.width * CGFloat(i) / 7).rounded() }
        func ry(_ i: Int) -> CGFloat { g.minY + (g.height * CGFloat(i) / CGFloat(rows)).rounded() }

        for r in 0..<rows {
            let days = (0..<7).map { cal.date(byAdding: .day, value: r * 7 + $0, to: start)! }
            for c in 0..<7 {
                let d = days[c]
                let cell = NSRect(x: cx(c), y: ry(r), width: cx(c + 1) - cx(c), height: ry(r + 1) - ry(r))
                let isToday = cal.isDate(d, inSameDayAs: ctl.today)
                let inMonth = cal.component(.month, from: d) == cal.component(.month, from: first)
                let sel = cal.isDate(d, inSameDayAs: ctl.date)
                (isToday ? mlRGB(229, 237, 247) : sel ? mlRGB(238, 242, 249) : inMonth ? .white : mlRGB(251, 251, 251)).setFill(); cell.fill()
                hits.append(Hit(rect: cell, kind: .day(d)))
                let num = "\(cal.component(.day, from: d))"
                let label = r == 0 ? "\(dayName(d)) \(num)" : num
                if isToday {
                    mlText(L("Heute", "Today"), NSRect(x: cell.minX + 4, y: cell.minY + 2, width: 50, height: 13), mlFont(10, bold: true), mlRGB(30, 110, 215))
                    mlText(MLPrefs.fmt(d, "MMMd"), NSRect(x: cell.minX, y: cell.minY + 2, width: cell.width - 5, height: 13), mlFont(10), mlRGB(30, 110, 215), align: .right)
                } else {
                    mlText(label, NSRect(x: cell.minX, y: cell.minY + 2, width: cell.width - 5, height: 13), mlFont(10), inMonth ? mlRGB(95, 95, 95) : mlRGB(130, 130, 130), align: .right)
                }
            }
            drawMonthRow(row: r, days: days, list: list, cx: cx, top: ry(r), bottom: ry(r + 1))
        }
        let line = mlRGB(205, 205, 205)
        for i in 0...7 { mlLine(NSRect(x: cx(i) - (i == 7 ? 1 : 0), y: g.minY, width: 1, height: ry(rows) - g.minY), line) }
        for i in 0...rows { mlLine(NSRect(x: g.minX, y: ry(i) - (i == rows ? 1 : 0), width: cx(7) - g.minX, height: 1), line) }
    }

    private func drawMonthRow(row: Int, days: [Date], list: [MLOcc], cx: (Int) -> CGFloat, top: CGFloat, bottom: CGFloat) {
        let rowStart = days[0], rowEnd = cal.date(byAdding: .day, value: 7, to: rowStart)!
        let inRow = list.filter { $0.start < rowEnd && $0.end > rowStart }
        let bars = layoutBars(inRow.filter(isBar), days: days)
        let lineH: CGFloat = 15
        let y0 = top + 17
        let cap = max(1, Int((bottom - y0 - 2) / lineH))
        let lanes = min(bars.map { $0.lane + 1 }.max() ?? 0, cap)
        var hidden = [Int](repeating: 0, count: 7)

        for b in bars {
            if b.lane >= cap { for c in b.c0...b.c1 { hidden[c] += 1 }; continue }
            let r = NSRect(x: cx(b.c0) + 2, y: y0 + CGFloat(b.lane) * lineH, width: cx(b.c1 + 1) - cx(b.c0) - 5, height: lineH - 2)
            pill(r, b.occ, leftOpen: b.occ.start < rowStart, rightOpen: b.occ.end > rowEnd)
            hits.append(Hit(rect: r, kind: .event(b.occ)))
        }
        for c in 0..<7 {
            let ds = days[c], de = cal.date(byAdding: .day, value: 1, to: ds)!
            let timed = inRow.filter { !isBar($0) && $0.start < de && $0.end > ds }
            let free = cap - lanes
            let shown = timed.count > free ? max(0, free - 1) : timed.count
            let cell = NSRect(x: cx(c), y: top, width: cx(c + 1) - cx(c), height: bottom - top)
            for (i, o) in timed.prefix(shown).enumerated() {
                let r = NSRect(x: cell.minX + 2, y: y0 + CGFloat(lanes + i) * lineH, width: cell.width - 5, height: lineH - 2)
                timedLine(r, o)
                hits.append(Hit(rect: r, kind: .event(o)))
            }
            let extra = timed.count - shown + hidden[c]
            if extra > 0 {
                let r = NSRect(x: cell.minX + 2, y: y0 + CGFloat(lanes + shown) * lineH, width: cell.width - 5, height: lineH - 2)
                mlText(L("+\(extra) weitere", "+\(extra) more"), r.insetBy(dx: 3, dy: 0), mlFont(9), mlRGB(110, 110, 110))
                hits.append(Hit(rect: r, kind: .more(ds)))
            }
        }
    }

    private struct Bar { var occ: MLOcc; var c0: Int; var c1: Int; var lane: Int }
    private func layoutBars(_ list: [MLOcc], days: [Date]) -> [Bar] {
        var lanesEnd: [Int] = []
        var out: [Bar] = []
        let n = days.count
        let rowEnd = cal.date(byAdding: .day, value: 1, to: days[n - 1])!
        for o in list.sorted(by: { ($0.start, $1.end) < ($1.start, $0.end) }) {
            let c0 = o.start <= days[0] ? 0 : (days.firstIndex { cal.isDate($0, inSameDayAs: o.start) } ?? 0)
            let lastDay = cal.date(byAdding: .second, value: -1, to: o.end) ?? o.end
            let c1 = o.end >= rowEnd ? n - 1 : (days.firstIndex { cal.isDate($0, inSameDayAs: lastDay) } ?? n - 1)
            guard c1 >= c0 else { continue }
            var lane = lanesEnd.firstIndex { $0 < c0 } ?? lanesEnd.count
            if lane == lanesEnd.count { lanesEnd.append(c1) } else { lanesEnd[lane] = c1 }
            lane = min(lane, lanesEnd.count - 1)
            out.append(Bar(occ: o, c0: c0, c1: c1, lane: lane))
        }
        return out
    }

    // MARK: event renderings

    private func isSel(_ o: MLOcc) -> Bool { ctl.selectedKey == o.id }

    /// All-day / multi-day bar.
    private func pill(_ r: NSRect, _ o: MLOcc, leftOpen: Bool, rightOpen: Bool) {
        let c = color(o), sel = isSel(o)
        let fill = sel ? mlMix(c, .white, 0.1) : mlMix(c, .white, 0.78)
        let border = sel ? mlMix(c, .black, 0.25) : mlMix(c, .white, 0.5)
        let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        fill.setFill(); path.fill(); border.setStroke(); path.lineWidth = 1; path.stroke()
        var x = r.minX + 4
        if !leftOpen { dot(NSPoint(x: x + 3, y: r.midY), c, onFill: sel); x += 9 }
        mlText(o.title, NSRect(x: x, y: r.minY, width: r.maxX - x - 3, height: r.height), mlFont(10), sel ? .white : mlMix(c, .black, 0.6))
    }

    /// Timed event inside a month cell: dot, time, title.
    private func timedLine(_ r: NSRect, _ o: MLOcc) {
        let c = color(o), sel = isSel(o)
        if sel { c.setFill(); NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill() }
        dot(NSPoint(x: r.minX + 6, y: r.midY), c, onFill: sel)
        let t = MLPrefs.time(o.start)
        let tw = mlTextWidth(t, mlFont(9)) + 4
        mlText(o.title, NSRect(x: r.minX + 12, y: r.minY, width: r.width - 12 - tw, height: r.height), mlFont(10), sel ? .white : mlRGB(40, 40, 40))
        mlText(t, NSRect(x: r.maxX - tw - 1, y: r.minY, width: tw, height: r.height), mlFont(9), sel ? .white : mlRGB(130, 130, 130), align: .right)
    }

    private func dot(_ p: NSPoint, _ c: NSColor, onFill: Bool) {
        let r = NSRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)
        (onFill ? NSColor.white : mlMix(c, .white, 0.15)).setFill(); NSBezierPath(ovalIn: r).fill()
        (onFill ? mlMix(c, .white, 0.3) : mlMix(c, .black, 0.35)).setStroke()
        let o = NSBezierPath(ovalIn: r.insetBy(dx: 0.4, dy: 0.4)); o.lineWidth = 0.8; o.stroke()
    }

    // MARK: week / day time grid

    private func drawDay(_ g: NSRect) {
        let infoW: CGFloat = min(190, g.width * 0.32)
        let info = NSRect(x: g.minX, y: g.minY, width: infoW, height: g.height)
        drawDayInfo(info)
        drawTime(NSRect(x: g.minX + infoW + 8 + 36, y: g.minY, width: g.width - infoW - 8 - 36, height: g.height), days: [ctl.date], header: false)
    }

    /// Day information column: date, the day's events, mini overview.
    private func drawDayInfo(_ r: NSRect) {
        mlRGB(247, 247, 247).setFill(); r.fill()
        mlRGB(205, 205, 205).setStroke(); NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
        let d = ctl.date
        mlText(MLPrefs.fmt(d, "EEEE"), NSRect(x: r.minX + 8, y: r.minY + 8, width: r.width - 16, height: 14), mlFont(11, bold: true), mlRGB(110, 110, 110))
        mlText("\(cal.component(.day, from: d))", NSRect(x: r.minX + 8, y: r.minY + 22, width: r.width - 16, height: 44), NSFont(name: "LucidaGrande", size: 40) ?? .systemFont(ofSize: 40, weight: .light),
               cal.isDate(d, inSameDayAs: ctl.today) ? mlRGB(30, 110, 215) : mlRGB(40, 40, 40))
        mlText(MLPrefs.fmt(d, "yMMMM"), NSRect(x: r.minX + 8, y: r.minY + 66, width: r.width - 16, height: 14), mlFont(10), mlRGB(110, 110, 110))
        mlLine(NSRect(x: r.minX + 8, y: r.minY + 88, width: r.width - 16, height: 1), mlRGB(215, 215, 215))
        let day = occs(d, cal.date(byAdding: .day, value: 1, to: d)!)
        var y = r.minY + 94
        if day.isEmpty { mlText(L("Keine Termine", "No events"), NSRect(x: r.minX + 8, y: y, width: r.width - 16, height: 14), mlFont(10), mlRGB(150, 150, 150)) }
        for o in day {
            guard y + 30 < r.maxY else { break }
            let row = NSRect(x: r.minX + 4, y: y, width: r.width - 8, height: 30)
            let sel = isSel(o)
            if sel { color(o).setFill(); NSBezierPath(roundedRect: row, xRadius: 3, yRadius: 3).fill() }
            dot(NSPoint(x: row.minX + 7, y: row.minY + 8), color(o), onFill: sel)
            mlText(o.title, NSRect(x: row.minX + 15, y: row.minY + 1, width: row.width - 18, height: 14), mlFont(10, bold: true), sel ? .white : .black)
            mlText(o.ev.allDay ? L("ganztägig", "all-day") : "\(MLPrefs.time(o.start)) – \(MLPrefs.time(o.end))", NSRect(x: row.minX + 15, y: row.minY + 14, width: row.width - 18, height: 13), mlFont(9), sel ? .white : mlRGB(120, 120, 120))
            hits.append(Hit(rect: row, kind: .event(o)))
            y += 32
        }
    }

    /// Week / day grid after the 2012 reference: hour labels sit left of the frame, number + weekday in the header,
    /// all-day row, solid hour lines with dotted half hours, grey outside the working day.
    private func drawTime(_ g: NSRect, days: [Date], header: Bool) {
        let n = days.count
        let labelW: CGFloat = 36
        let colW = g.width / CGFloat(n)
        func cx(_ i: Int) -> CGFloat { g.minX + (colW * CGFloat(i)).rounded() }
        let rangeEnd = cal.date(byAdding: .day, value: n, to: days[0])!
        let list = occs(days[0], rangeEnd)
        let headH: CGFloat = header ? 13 : 0
        let bars = layoutBars(list.filter(isBar), days: days)
        let lanes = max(1, (bars.map { $0.lane + 1 }.max() ?? 0))
        let stripH = CGFloat(lanes) * 15 + 1
        let vp = NSRect(x: g.minX, y: g.minY + headH + stripH, width: g.width, height: g.maxY - g.minY - headH - stripH)
        if scrollY < 0 { scrollY = CGFloat(MLPrefs.dayStart) * hourH }
        scrollY = min(max(0, scrollY), max(0, 24 * hourH - vp.height))
        geom = TimeGeom(viewport: vp, gutter: 0, colW: colW, days: days, hourH: hourH, scroll: scrollY)

        mlRGB(255, 255, 255).setFill(); g.fill()
        let lineC = mlRGB(208, 208, 208)
        // columns: tints and header
        for i in 0..<n {
            let col = NSRect(x: cx(i), y: g.minY, width: cx(i + 1) - cx(i), height: g.height)
            let d = days[i]
            let isToday = cal.isDate(d, inSameDayAs: ctl.today)
            if isToday { mlRGB(232, 240, 250).setFill(); col.fill() }
            else if cal.isDate(d, inSameDayAs: ctl.date) && n > 1 { mlRGB(244, 247, 252).setFill(); col.fill() }
            if header {
                let num = "\(cal.component(.day, from: d))"
                let nw = mlText(num, NSRect(x: col.minX + 5, y: g.minY, width: 24, height: headH), mlFont(10.5), isToday ? mlRGB(30, 110, 215) : mlRGB(120, 120, 120))
                mlText(MLPrefs.fmt(d, "EEEE"), NSRect(x: col.minX + 7 + nw, y: g.minY, width: col.width - 12 - nw, height: headH), mlFont(9), isToday ? mlRGB(30, 110, 215) : mlRGB(150, 150, 150))
                hits.append(Hit(rect: NSRect(x: col.minX, y: g.minY, width: col.width, height: headH), kind: .dayHeader(d)))
            }
            hits.append(Hit(rect: NSRect(x: col.minX, y: g.minY + headH, width: col.width, height: stripH), kind: .day(d)))
        }
        // labels left of the frame
        mlText(L("Ganztag", "all-day"), NSRect(x: g.minX - labelW, y: g.minY + (header ? 0 : 0), width: labelW - 4, height: header ? headH : stripH), mlFont(9), mlRGB(150, 150, 150), align: .right)
        for b in bars {
            let r = NSRect(x: cx(b.c0) + 1, y: g.minY + headH + 1 + CGFloat(b.lane) * 15, width: cx(b.c1 + 1) - cx(b.c0) - 2, height: 14)
            allDayBar(r, b.occ)
            hits.append(Hit(rect: r, kind: .event(b.occ)))
        }

        // hours
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: g.minX - labelW, y: vp.minY, width: g.width + labelW, height: vp.height)).addClip()
        let wStart = CGFloat(MLPrefs.dayStart) * hourH - scrollY + vp.minY, wEnd = CGFloat(MLPrefs.dayEnd) * hourH - scrollY + vp.minY
        mlRGB(241, 241, 241).setFill()                                              // outside the working day
        NSRect(x: g.minX, y: vp.minY, width: g.width, height: max(0, min(wStart, vp.maxY) - vp.minY)).fill()
        if wEnd < vp.maxY { NSRect(x: g.minX, y: max(wEnd, vp.minY), width: g.width, height: vp.maxY - max(wEnd, vp.minY)).fill() }
        let dash = NSBezierPath(); dash.setLineDash([1, 2], count: 2, phase: 0); dash.lineWidth = 1
        for h in 0...24 {
            let y = (vp.minY + CGFloat(h) * hourH - scrollY).rounded()
            if y < vp.minY - 14 || y > vp.maxY + 14 { continue }
            if h > 0 && h < 24 && y - 7 >= vp.minY - 4 {
                let t: String
                if MLPrefs.hour24 { t = String(format: "%02d:00", h) } else { t = h == 12 ? L("Mittag", "Noon") : "\(h % 12 == 0 ? 12 : h % 12) \(h < 12 ? "AM" : "PM")" }
                mlText(t, NSRect(x: g.minX - labelW, y: y - 7, width: labelW - 5, height: 14), mlFont(9), mlRGB(150, 150, 150), align: .right)
            }
            mlLine(NSRect(x: g.minX, y: y, width: g.width, height: 1), lineC)
            let hy = y + (hourH / 2).rounded()
            dash.removeAllPoints(); dash.move(to: NSPoint(x: g.minX, y: hy + 0.5)); dash.line(to: NSPoint(x: g.maxX, y: hy + 0.5))
            mlRGB(206, 206, 206).setStroke(); dash.stroke()
        }
        for i in 0..<n { hits.append(Hit(rect: NSRect(x: cx(i), y: vp.minY, width: cx(i + 1) - cx(i), height: vp.height), kind: .slot(i))) }

        // events per day, overlapping ones side by side
        for i in 0..<n {
            let ds = days[i], de = cal.date(byAdding: .day, value: 1, to: ds)!
            var segs = list.filter { !isBar($0) && $0.start < de && $0.end > ds }.map { o -> (MLOcc, Date, Date) in (o, max(o.start, ds), min(o.end, de)) }
            segs.sort { ($0.1, $1.2) < ($1.1, $0.2) }
            var cols: [Date] = []
            var placed: [(Int, Int, Int)] = []
            var cluster = 0
            var clusterEnd = Date.distantPast
            var clusterCols: [Int: Int] = [:]
            for (k, s) in segs.enumerated() {
                if s.1 >= clusterEnd { cluster += 1; cols = []; clusterEnd = s.2 }
                clusterEnd = max(clusterEnd, s.2)
                let c = cols.firstIndex { $0 <= s.1 } ?? cols.count
                if c == cols.count { cols.append(s.2) } else { cols[c] = s.2 }
                placed.append((k, c, cluster))
                clusterCols[cluster] = max(clusterCols[cluster] ?? 1, cols.count)
            }
            for (k, c, cl) in placed {
                let s = segs[k]
                let nc = CGFloat(clusterCols[cl] ?? 1)
                let cw = (cx(i + 1) - cx(i) - 2) / nc
                let y = vp.minY + CGFloat(minutes(s.1)) / 60 * hourH - scrollY
                let eMin = s.2 >= de ? 1440 : minutes(s.2)
                let h = max(CGFloat(eMin - minutes(s.1)) / 60 * hourH, 15)
                let r = NSRect(x: cx(i) + 1 + cw * CGFloat(c), y: y, width: cw, height: h)
                eventBlock(r, s.0)
                hits.append(Hit(rect: NSRect(x: r.minX, y: r.maxY - 5, width: r.width, height: 5), kind: .resize(s.0)))
                hits.append(Hit(rect: r, kind: .event(s.0)))
            }
        }
        if let ti = days.firstIndex(where: { cal.isDate($0, inSameDayAs: ctl.now()) }) {
            let y = (vp.minY + CGFloat(minutes(ctl.now())) / 60 * hourH - scrollY).rounded()
            mlRGB(214, 60, 48).setFill(); NSRect(x: cx(ti), y: y, width: cx(ti + 1) - cx(ti), height: 2).fill()
            let t = MLPrefs.time(ctl.now())
            let pr = NSRect(x: g.minX - labelW + 2, y: y - 6, width: labelW - 5, height: 12)
            mlRGB(214, 60, 48).setFill(); NSBezierPath(roundedRect: pr, xRadius: 6, yRadius: 6).fill()
            mlText(t, pr, mlFont(9, bold: true), .white, align: .center)
        }
        NSGraphicsContext.restoreGraphicsState()
        // vertical column lines, header/all-day separators and frame
        for i in 0...n { mlLine(NSRect(x: i == n ? g.maxX - 1 : cx(i), y: g.minY, width: 1, height: g.height), lineC) }
        mlLine(NSRect(x: g.minX, y: g.minY, width: g.width, height: 1), lineC)
        if header { mlLine(NSRect(x: g.minX, y: g.minY + headH, width: g.width, height: 1), mlRGB(226, 226, 226)) }
        mlLine(NSRect(x: g.minX, y: vp.minY - 1, width: g.width, height: 1), lineC)
        mlLine(NSRect(x: g.minX, y: g.maxY - 1, width: g.width, height: 1), lineC)
    }

    private func allDayBar(_ r: NSRect, _ o: MLOcc) {
        let c = color(o), sel = isSel(o)
        let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 1.5, yRadius: 1.5)
        (sel ? c : mlMix(c, .white, 0.62)).setFill(); path.fill()
        (sel ? mlMix(c, .black, 0.3) : mlMix(c, .white, 0.28)).setStroke(); path.lineWidth = 1; path.stroke()
        mlText(o.title, NSRect(x: r.minX + 5, y: r.minY, width: r.width - 8, height: r.height), mlFont(9.5, bold: true), sel ? .white : mlMix(c, .black, 0.12))
    }

    /// Flat pastel block with a darker outline; bold title, place underneath (the time is in the editor, as in Calendar).
    private func eventBlock(_ r: NSRect, _ o: MLOcc) {
        let c = color(o), sel = isSel(o)
        let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 1.5, yRadius: 1.5)
        if sel { mlGradient(r, [(0, mlMix(c, .white, 0.05)), (1, mlMix(c, .black, 0.12))], radius: 1.5) } else { mlMix(c, .white, 0.62).setFill(); path.fill() }
        (sel ? mlMix(c, .black, 0.35) : mlMix(c, .white, 0.28)).setStroke(); path.lineWidth = 1; path.stroke()
        let tc = sel ? NSColor.white : mlMix(c, .black, 0.12)
        mlText(o.title, NSRect(x: r.minX + 5, y: r.minY + 1, width: r.width - 8, height: 12), mlFont(9.5, bold: true), tc)
        if r.height > 24, !o.ev.location.isEmpty { mlText(o.ev.location, NSRect(x: r.minX + 5, y: r.minY + 12, width: r.width - 8, height: 12), mlFont(9.5), tc) }
    }

    // MARK: year

    private func drawYear(_ g: NSRect) {
        let year = cal.component(.year, from: ctl.date)
        let jan = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
        let list = occs(jan, cal.date(byAdding: .year, value: 1, to: jan)!)
        var perDay: [Date: [MLOcc]] = [:]
        for o in list {
            var d = cal.startOfDay(for: o.start)
            let last = cal.startOfDay(for: cal.date(byAdding: .second, value: -1, to: max(o.end, o.start.addingTimeInterval(1)))!)
            while d <= last { perDay[d, default: []].append(o); d = cal.date(byAdding: .day, value: 1, to: d)! }
        }
        let cols = g.width > 520 ? 4 : 3
        let rows = 12 / cols
        let cw = g.width / CGFloat(cols), ch = g.height / CGFloat(rows)
        for m in 0..<12 {
            let first = cal.date(from: DateComponents(year: year, month: m + 1, day: 1))!
            let box = NSRect(x: g.minX + CGFloat(m % cols) * cw, y: g.minY + CGFloat(m / cols) * ch, width: cw, height: ch).insetBy(dx: 8, dy: 4)
            let cellW = box.width / 7, headH: CGFloat = 16, wdH: CGFloat = 12
            let cellH = min(15, (box.height - headH - wdH) / 6)
            mlText(MLPrefs.fmt(first, "MMMM"), NSRect(x: box.minX, y: box.minY, width: box.width, height: headH), mlFont(11, bold: true), mlRGB(70, 70, 70))
            for i in 0..<7 {
                let wd = (cal.firstWeekday - 1 + i) % 7
                mlText(String(cal.shortStandaloneWeekdaySymbols[wd].prefix(2)), NSRect(x: box.minX + CGFloat(i) * cellW, y: box.minY + headH, width: cellW, height: wdH), mlFont(8), mlRGB(130, 130, 130), align: .center)
            }
            mlLine(NSRect(x: box.minX, y: box.minY + headH + wdH, width: box.width, height: 1), mlRGB(215, 215, 215))
            let off = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
            for day in 1...cal.range(of: .day, in: .month, for: first)!.count {
                let d = cal.date(byAdding: .day, value: day - 1, to: first)!
                let k = off + day - 1
                let r = NSRect(x: box.minX + CGFloat(k % 7) * cellW, y: box.minY + headH + wdH + 2 + CGFloat(k / 7) * cellH, width: cellW, height: cellH)
                let isToday = cal.isDate(d, inSameDayAs: ctl.today), sel = cal.isDate(d, inSameDayAs: ctl.date)
                if let o = perDay[d]?.first {      // occupancy: tinted square in the first event's colour
                    mlMix(color(o), .white, perDay[d]!.count > 2 ? 0.5 : 0.7).setFill()
                    NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 0.5), xRadius: 2, yRadius: 2).fill()
                }
                if isToday { mlRGB(30, 110, 215).setFill(); NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 0.5), xRadius: 2, yRadius: 2).fill() }
                if sel { mlRGB(30, 110, 215).setStroke(); let p = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 0.5), xRadius: 2, yRadius: 2); p.lineWidth = 1; p.stroke() }
                mlText("\(day)", r, mlFont(9, bold: isToday), isToday ? .white : mlRGB(60, 60, 60), align: .center)
                hits.append(Hit(rect: r, kind: .day(d)))
                if let n = perDay[d]?.count {
                    hots.append(MLHot(rect: r, label: "\(MLPrefs.fmt(d, "yMMMMEEEEd")), \(n) " + L("Termine", "events"), role: .button) { [weak self] in self?.ctl.select(date: d) })
                }
            }
        }
    }

    // MARK: search results (FUN-09)

    private func drawSearch(_ r: NSRect) {
        mlRGB(250, 250, 250).setFill(); r.fill()
        mlLine(NSRect(x: r.minX, y: 0, width: 1, height: r.height), mlRGB(200, 200, 200))
        let res = ctl.store.search(ctl.query)
        mlText(L("Suchergebnisse", "Search Results"), NSRect(x: r.minX + 8, y: 6, width: r.width - 12, height: 14), mlFont(10, bold: true), mlRGB(120, 120, 120))
        if res.isEmpty {
            mlText(L("Keine Treffer", "No results"), NSRect(x: r.minX + 8, y: 26, width: r.width - 12, height: 16), mlFont(11), mlRGB(130, 130, 130))
            return
        }
        var y: CGFloat = 24
        for o in res {
            guard y + 34 <= r.height else { break }
            let row = NSRect(x: r.minX + 1, y: y, width: r.width - 1, height: 34)
            let sel = ctl.selectedKey == o.id
            if sel { mlGradient(row, [(0, mlRGB(110, 150, 215)), (1, mlRGB(70, 115, 200))]) }
            dot(NSPoint(x: row.minX + 9, y: row.minY + 9), color(o), onFill: sel)
            mlText(o.title, NSRect(x: row.minX + 17, y: row.minY + 2, width: row.width - 21, height: 14), mlFont(10, bold: true), sel ? .white : .black)
            let d = MLPrefs.fmt(o.start, "yMMMd") + (o.ev.allDay ? "" : ", " + MLPrefs.time(o.start))
            mlText(d, NSRect(x: row.minX + 17, y: row.minY + 16, width: row.width - 21, height: 13), mlFont(9), sel ? .white : mlRGB(120, 120, 120))
            mlLine(NSRect(x: row.minX, y: row.maxY - 1, width: row.width, height: 1), mlRGB(228, 228, 228))
            hits.append(Hit(rect: row, kind: .search(o)))
            hots.append(MLHot(rect: row, label: describe(o), role: .row) { [weak self] in self?.ctl.reveal(o) })
            y += 34
        }
    }

    // MARK: geometry helpers for the editor popover

    func rectForSelected() -> NSRect? {
        guard let k = ctl.selectedKey else { return nil }
        for h in hits.reversed() { if case .event(let o) = h.kind, o.id == k { return h.rect } }
        return nil
    }

    private func slot(at p: NSPoint) -> (day: Date, minutes: Int)? {
        guard let g = geom, g.viewport.contains(p) || (p.x > g.viewport.minX) else { return nil }
        let i = min(max(0, Int((p.x - g.viewport.minX) / g.colW)), g.days.count - 1)
        let m = Int((p.y - g.viewport.minY + g.scroll) / g.hourH * 60)
        return (g.days[i], min(max(0, m), 24 * 60 - 1))
    }
    private func dayCell(at p: NSPoint) -> Date? {
        for h in hits.reversed() { if case .day(let d) = h.kind, h.rect.contains(p) { return d } }
        return nil
    }

    // MARK: mouse

    override func scrollWheel(with e: NSEvent) {
        guard geom != nil else { super.scrollWheel(with: e); return }
        scrollY -= e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 1 : 8)
        needsDisplay = true
    }

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(e.locationInWindow, from: nil)
        if let h = hots.last(where: { $0.rect.contains(p) }), [navRects.prev, navRects.today, navRects.next].contains(h.rect) {
            navPressed = h.rect == navRects.prev ? 1 : h.rect == navRects.today ? 2 : 3
            needsDisplay = true
            var inside = true
            while let ev = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
                inside = h.rect.contains(convert(ev.locationInWindow, from: nil))
                if ev.type == .leftMouseUp { break }
            }
            navPressed = 0; needsDisplay = true
            if inside { h.action() }
            return
        }
        guard let hit = hits.last(where: { $0.rect.contains(p) }) else { return }
        let dbl = e.clickCount >= 2
        switch hit.kind {
        case .search(let o): ctl.reveal(o)
        case .more(let d): ctl.select(date: d); ctl.setMode(.day)
        case .dayHeader(let d): ctl.select(date: d); if dbl { ctl.setMode(.day) }
        case .event(let o), .resize(let o):
            ctl.selectedKey = o.id
            if case .event = hit.kind, dbl { ctl.openEditor(o, rect: hit.rect, view: self); needsDisplay = true; return }
            let s = ctl.mode == .month || ctl.mode == .year ? nil : slot(at: p)
            var isResize = false; if case .resize = hit.kind { isResize = !o.ev.allDay }
            drag = Drag(occ: o, kind: isResize ? .resize : .move, grabDay: s?.day ?? dayCell(at: p) ?? o.start, grabMinutes: s?.minutes ?? 0, origin: p, newStart: o.start, newEnd: o.end)
            needsDisplay = true
        case .day(let d):
            if ctl.mode == .year { ctl.select(date: d); if dbl { ctl.setMode(.day) } }
            else if dbl { ctl.date = d; ctl.newEvent(start: d, allDay: true, anchor: hit.rect, in: self) }
            else { ctl.select(date: d) }
        case .slot:
            guard let s = slot(at: p) else { return }
            if dbl {
                let start = cal.date(byAdding: .minute, value: s.minutes / 30 * 30, to: s.day)!
                ctl.date = s.day; ctl.newEvent(start: start, allDay: false, anchor: NSRect(x: p.x, y: p.y, width: 1, height: 1), in: self)
            } else { ctl.select(date: s.day) }
        }
    }

    override func mouseDragged(with e: NSEvent) {
        guard var d = drag else { return }
        let p = convert(e.locationInWindow, from: nil)
        if !d.active { guard hypot(p.x - d.origin.x, p.y - d.origin.y) > 3 else { return }; d.active = true }
        let o = d.occ
        if ctl.mode == .month || ctl.mode == .year || o.ev.allDay || geom == nil {
            guard let day = dayCellOrColumn(at: p) else { drag = d; return }
            let delta = cal.dateComponents([.day], from: cal.startOfDay(for: d.grabDay), to: day).day ?? 0
            d.newStart = cal.date(byAdding: .day, value: delta, to: o.start)!
            d.newEnd = cal.date(byAdding: .day, value: delta, to: o.end)!
        } else if let s = slot(at: p) {
            let snap = { (m: Int) in (m / 15) * 15 }
            switch d.kind {
            case .move:
                let dayDelta = cal.dateComponents([.day], from: cal.startOfDay(for: d.grabDay), to: s.day).day ?? 0
                let minDelta = snap(s.minutes) - snap(d.grabMinutes)
                let shift = cal.date(byAdding: .day, value: dayDelta, to: cal.date(byAdding: .minute, value: minDelta, to: o.start)!)!
                d.newStart = shift
                d.newEnd = shift.addingTimeInterval(o.end.timeIntervalSince(o.start))
            case .resize:
                let end = cal.date(byAdding: .minute, value: snap(s.minutes) + 15, to: cal.startOfDay(for: o.start))!
                d.newStart = o.start; d.newEnd = max(end, o.start.addingTimeInterval(15 * 60))
            }
        }
        drag = d
        needsDisplay = true
    }

    private func dayCellOrColumn(at p: NSPoint) -> Date? {
        if let c = dayCell(at: p) { return c }
        if let g = geom, p.x > g.viewport.minX + g.gutter {
            let i = min(max(0, Int((p.x - g.viewport.minX - g.gutter) / g.colW)), g.days.count - 1)
            return g.days[i]
        }
        return nil
    }

    override func mouseUp(with e: NSEvent) {
        guard let d = drag else { return }
        drag = nil
        needsDisplay = true
        guard d.active, d.newStart != d.occ.start || d.newEnd != d.occ.end else { return }
        ctl.move(d.occ, newStart: d.newStart, newEnd: d.newEnd)
    }

    /// Escape during a drag discards it (FUN-07). Returns true if there was something to cancel.
    func cancelDrag() -> Bool {
        guard drag?.active == true else { return false }
        drag = nil; needsDisplay = true; return true
    }

    override func keyDown(with e: NSEvent) { if !ctl.handleKey(e, shortcutOnly: false) { super.keyDown(with: e) } }

    // MARK: context menu (shortcuts shown, FUN-13)

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        let m = NSMenu()
        let cmd = NSEvent.ModifierFlags.command
        func add(_ t: String, _ key: String, _ mods: NSEvent.ModifierFlags = .command, _ f: @escaping () -> Void) {
            let i = MLBlockItem(t, key: key, f); i.keyEquivalentModifierMask = mods; m.addItem(i)
        }
        if let h = hits.last(where: { $0.rect.contains(p) }), case .event(let o) = h.kind {
            ctl.selectedKey = o.id; needsDisplay = true
            add(L("Bearbeiten", "Edit"), "e") { [weak self] in self?.ctl.editSelected() }
            add(L("Duplizieren", "Duplicate"), "d") { [weak self] in self?.ctl.duplicateSelected() }
            add(L("Löschen", "Delete"), String(UnicodeScalar(NSBackspaceCharacter)!)) { [weak self] in self?.ctl.deleteSelected() }
            m.addItem(.separator())
        }
        add(L("Neuer Termin", "New Event"), "n") { [weak self] in self?.ctl.newEvent() }
        add(L("Schnelleingabe", "Quick Entry"), "n", [.command, .shift]) { [weak self] in self?.ctl.showQuickEntry() }
        m.addItem(.separator())
        for (i, t) in [L("Tag", "Day"), L("Woche", "Week"), L("Monat", "Month"), L("Jahr", "Year")].enumerated() {
            add(t, "\(i + 1)") { [weak self] in self?.ctl.setMode(MLMode(rawValue: i)!) }
        }
        add(L("Heute", "Today"), "t") { [weak self] in self?.ctl.goToday() }
        m.addItem(.separator())
        let um = ctl.store.undoManager
        let u = MLBlockItem(L("Rückgängig", "Undo"), key: "z") { um.undo() }; u.keyEquivalentModifierMask = cmd; u.isEnabled = um.canUndo; m.addItem(u)
        let r = MLBlockItem(L("Wiederholen", "Redo"), key: "z") { um.redo() }; r.keyEquivalentModifierMask = [.command, .shift]; r.isEnabled = um.canRedo; m.addItem(r)
        m.addItem(.separator())
        add(L("Einstellungen…", "Settings…"), ",") { [weak self] in self?.ctl.showSettings() }
        return m
    }

    // MARK: accessibility

    override func accessibilityChildren() -> [Any]? {
        var list = hots
        for h in hits {
            switch h.kind {
            case .event(let o): list.append(MLHot(rect: h.rect, label: describe(o), role: .button) { [weak self] in
                guard let s = self else { return }; s.ctl.selectedKey = o.id; s.ctl.openEditor(o, rect: h.rect, view: s) })
            case .day(let d) where ctl.mode == .month: list.append(MLHot(rect: h.rect, label: MLPrefs.fmt(d, "yMMMMEEEEd"), role: .button) { [weak self] in self?.ctl.select(date: d) })
            default: break
            }
        }
        return axChildren(list)
    }
    override func accessibilityLabel() -> String? { "\(ctl.title), " + [L("Tag", "Day"), L("Woche", "Week"), L("Monat", "Month"), L("Jahr", "Year")][ctl.mode.rawValue] }
    override func isAccessibilityElement() -> Bool { false }
}
