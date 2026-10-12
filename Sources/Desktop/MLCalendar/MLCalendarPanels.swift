import AppKit

private func lbl(_ t: String, _ r: NSRect, align: NSTextAlignment = .right, bold: Bool = false, color: NSColor = mlRGB(140, 140, 142), size: CGFloat = 10.5) -> NSTextField {
    let l = NSTextField(labelWithString: t)
    l.frame = r; l.alignment = align; l.font = mlPF(size, bold: bold || align == .right); l.textColor = color
    l.lineBreakMode = .byTruncatingTail
    return l
}

private func plainField(_ f: NSTextField, _ r: NSRect, _ text: String, size: CGFloat = 11, placeholder: String? = L("Keine", "None"), accessibility: String) {
    f.frame = r; f.stringValue = text; f.font = mlPF(size)
    f.isBordered = false; f.drawsBackground = false; f.focusRingType = .none
    f.placeholderString = placeholder
    f.setAccessibilityLabel(accessibility)
    f.cell?.usesSingleLineMode = true
}

/// The graphical month dropdown of the reference's date field (Jul 2012 ◀ ● ▶, weekday row, day grid).
final class MLCalDropdown: NSView {
    private let cal: Calendar
    private var month: Date
    private let selected: Date
    var onPick: ((Date) -> Void)?
    private let cellW: CGFloat = 25, cellH: CGFloat = 19
    override var isFlipped: Bool { true }
    private var hits: [(NSRect, () -> Void)] = []

    init(cal: Calendar, selected: Date) {
        self.cal = cal; self.selected = selected
        month = cal.dateInterval(of: .month, for: selected)!.start
        super.init(frame: NSRect(x: 0, y: 0, width: 7 * 25 + 16, height: 16 + 18 + 16 + 6 * 19 + 14))
        wantsLayer = true
        shadow = { let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.4); sh.shadowBlurRadius = 6; sh.shadowOffset = NSSize(width: 0, height: -3); return sh }()
        setAccessibilityLabel(L("Datum wählen", "Choose date"))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirty: NSRect) {
        hits = []
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5)
        NSColor.white.setFill(); path.fill(); mlRGB(190, 190, 194).setStroke(); path.lineWidth = 1; path.stroke()
        mlText(MLPrefs.fmt(month, "yMMM"), NSRect(x: 10, y: 8, width: 110, height: 18), mlPF(12, bold: true), mlRGB(110, 110, 112))
        // ◀ ● ▶
        let bx = bounds.maxX - 60
        for (i, kind) in ["prev", "today", "next"].enumerated() {
            let c = NSPoint(x: bx + CGFloat(i) * 20 + 8, y: 17)
            let p = NSBezierPath()
            switch kind {
            case "prev": p.move(to: NSPoint(x: c.x + 3, y: c.y - 4)); p.line(to: NSPoint(x: c.x + 3, y: c.y + 4)); p.line(to: NSPoint(x: c.x - 3, y: c.y)); p.close()
            case "next": p.move(to: NSPoint(x: c.x - 3, y: c.y - 4)); p.line(to: NSPoint(x: c.x - 3, y: c.y + 4)); p.line(to: NSPoint(x: c.x + 3, y: c.y)); p.close()
            default: p.appendOval(in: NSRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7))
            }
            mlRGB(30, 30, 30).setFill(); p.fill()
            let rect = NSRect(x: c.x - 9, y: 4, width: 18, height: 26)
            hits.append((rect, { [weak self] in
                guard let s = self else { return }
                switch kind {
                case "prev": s.month = s.cal.date(byAdding: .month, value: -1, to: s.month)!
                case "next": s.month = s.cal.date(byAdding: .month, value: 1, to: s.month)!
                default: s.month = s.cal.dateInterval(of: .month, for: Date())!.start
                }
                s.needsDisplay = true
            }))
        }
        // weekday initials
        let sym = cal.shortStandaloneWeekdaySymbols
        for i in 0..<7 {
            let wd = (cal.firstWeekday - 1 + i) % 7
            mlText(String(sym[wd].prefix(2)), NSRect(x: 8 + CGFloat(i) * cellW, y: 30, width: cellW, height: 14), mlPF(9.5, bold: true), mlRGB(160, 168, 176), align: .center)
        }
        mlLine(NSRect(x: 8, y: 46, width: 7 * cellW, height: 1), mlRGB(205, 205, 208))
        let off = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -off, to: month)!
        let today = cal.startOfDay(for: Date()), cur = cal.component(.month, from: month)
        for i in 0..<42 {
            let d = cal.date(byAdding: .day, value: i, to: start)!
            let cell = NSRect(x: 8 + CGFloat(i % 7) * cellW, y: 49 + CGFloat(i / 7) * cellH, width: cellW, height: cellH)
            let isSel = cal.isDate(d, inSameDayAs: selected)
            if isSel { mlRGB(176, 176, 178).setFill(); NSBezierPath(roundedRect: cell.insetBy(dx: 1.5, dy: 1), xRadius: 2.5, yRadius: 2.5).fill() }
            let col: NSColor = isSel ? .white : cal.isDate(d, inSameDayAs: today) ? mlRGB(20, 110, 235) : cal.component(.month, from: d) == cur ? .black : mlRGB(190, 190, 192)
            mlText("\(cal.component(.day, from: d))", cell, mlPF(11.5), col, align: .center)
            hits.append((cell, { [weak self] in self?.onPick?(d) }))
        }
    }
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        hits.last { $0.0.contains(p) }?.1()
    }
}

final class MLEditorRoot: MLFlip {
    var onBackgroundClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onBackgroundClick?() }
}

/// NSDatePicker that tells the editor when its date field was clicked (to show the month dropdown).
final class MLDatePicker: NSDatePicker {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { super.mouseDown(with: event); onClick?() }
}

// MARK: - Event editor (FUN-05)

final class MLEditorVC: NSViewController, NSTextFieldDelegate {
    static let footerH: CGFloat = 42
    unowned let ctl: MLController
    let occ: MLOcc
    let isNew: Bool
    private var cal: Calendar { ctl.cal }
    private var done = false

    private let title_ = NSTextField(), location = NSTextField(), url = NSTextField(), notes = NSTextField()
    private var allDay: MLCheck!
    private let from = MLDatePicker(), to = MLDatePicker()
    private var dropdown: MLCalDropdown?
    private var repeatPop: MLPopup!, calPop: MLPopup!
    private let error = NSTextField(labelWithString: "")
    private var doneBtn: MLButton!
    private var calIDs: [UUID] = []
    private let readOnly: Bool

    init(_ ctl: MLController, occ: MLOcc, isNew: Bool) {
        self.ctl = ctl; self.occ = occ; self.isNew = isNew
        readOnly = ctl.store.calendar(occ.ev.calID)?.readOnly ?? false
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let W: CGFloat = 290
        var y: CGFloat = 12
        let e = occ.ev
        let lx: CGFloat = 6, lw: CGFloat = 72, fx: CGFloat = 86, fw: CGFloat = 192
        // Rows are laid out first so the height follows from the content.
        var views: [NSView] = []
        func add(_ v: NSView) { views.append(v) }

        let well = MLFlip(frame: NSRect(x: 8, y: y - 2, width: W - 8 - 19, height: 28))
        well.wantsLayer = true
        well.layer?.backgroundColor = NSColor.white.cgColor
        well.layer?.shadowColor = NSColor.black.cgColor; well.layer?.shadowOpacity = 0.35; well.layer?.shadowOffset = CGSize(width: 0, height: -2); well.layer?.shadowRadius = 2
        if isNew { add(well) }
        plainField(title_, NSRect(x: 12, y: y + 1, width: W - 12 - 23, height: 22), e.title, size: 14, placeholder: L("Neuer Termin", "New Event"), accessibility: L("Titel", "Title"))
        title_.font = mlPF(14, bold: true); title_.textColor = mlRGB(18, 38, 120)
        add(title_); y += 38

        func row(_ name: String, _ h: CGFloat = 22, gap: CGFloat = 6, _ build: (NSRect) -> Void) {
            add(lbl(name, NSRect(x: lx, y: y + (min(h, 22) - 15) / 2 + 1, width: lw, height: 15)))
            build(NSRect(x: fx, y: y, width: fw, height: h))
            y += h + gap
        }
        row(L("Ort", "location")) { plainField(self.location, $0, e.location, accessibility: L("Ort", "Location")); add(self.location) }
        row(L("ganztägig", "all-day")) { r in
            self.allDay = MLCheck(on: e.allDay) { [weak self] in self?.allDayChanged() }
            self.allDay.frame = NSRect(x: r.minX, y: r.minY + 2, width: 18, height: 18); self.allDay.setAccessibilityLabel(L("Ganztägig", "All-day"))
            add(self.allDay)
        }
        let loc = Locale(identifier: MLPrefs.hour24 ? (MLPrefs.isDE ? "de_DE" : "en_GB") : "en_US")
        for (p, name, lab) in [(from, L("von", "from"), L("Beginn", "Starts")), (to, L("bis", "to"), L("Ende", "Ends"))] {
            row(name, 21, gap: 1) { r in
                p.frame = NSRect(x: r.minX, y: r.minY, width: 186, height: 22)
                p.datePickerStyle = .textField
                p.isBezeled = false; p.isBordered = false; p.drawsBackground = false
                p.font = mlPF(11)
                p.calendar = cal; p.timeZone = cal.timeZone; p.locale = loc
                p.setAccessibilityLabel(lab)
                let c = MLClosure { [weak self] in self?.validate() }
                closures.append(c); p.target = c; p.action = #selector(MLClosure.run)
                p.onClick = { [weak self, weak p] in if let p { self?.showDropdown(for: p) } }
                add(p)
            }
        }
        let endShown = e.allDay ? cal.date(byAdding: .day, value: -1, to: occ.end)! : occ.end
        from.dateValue = occ.start; to.dateValue = e.allDay ? max(endShown, occ.start) : occ.end

        row(L("Wiederholung", "repeat")) { r in
            self.repeatPop = MLPopup(MLRepeat.allCases.map { $0.title }, index: MLRepeat.allCases.firstIndex(of: e.repeatRule) ?? 0) { _ in }
            self.repeatPop.plain = true; self.repeatPop.frame = NSRect(x: r.minX, y: r.minY, width: 150, height: 22)
            self.repeatPop.setAccessibilityLabel(L("Wiederholung", "Repeat")); add(self.repeatPop)
        }
        row(L("Kalender", "calendar")) { r in
            let usable = ctl.store.allCalendars.filter { !$0.readOnly || $0.id == e.calID }
            self.calIDs = usable.map { $0.id }
            self.calPop = MLPopup(usable.map { $0.name }, index: self.calIDs.firstIndex(of: e.calID) ?? 0) { _ in }
            self.calPop.colors = usable.map { $0.color }; self.calPop.plain = true
            self.calPop.frame = NSRect(x: r.minX, y: r.minY, width: 180, height: 22); self.calPop.setAccessibilityLabel(L("Kalender", "Calendar")); add(self.calPop)
        }
        row("url") { plainField(self.url, $0, e.url, accessibility: "URL"); add(self.url) }
        row(L("Notiz", "note"), 52) { r in
            plainField(self.notes, r, e.notes, accessibility: L("Notiz", "Note"))
            self.notes.cell?.usesSingleLineMode = false; self.notes.cell?.wraps = true; self.notes.maximumNumberOfLines = 3
            self.notes.alignment = .left
            add(self.notes)
        }
        error.frame = NSRect(x: 10, y: y, width: W - 31, height: 28)
        error.font = mlPF(10); error.textColor = mlRGB(190, 40, 30); error.maximumNumberOfLines = 2; error.lineBreakMode = .byWordWrapping
        error.setAccessibilityLabel(L("Hinweis", "Notice")); add(error)
        y += 32
        let H = y + Self.footerH

        let v = MLEditorRoot(frame: NSRect(x: 0, y: 0, width: W, height: H))
        v.onBackgroundClick = { [weak self] in self?.dropdown?.removeFromSuperview(); self?.dropdown = nil }
        views.forEach { v.addSubview($0) }
        v.setAccessibilityLabel(L("Termin bearbeiten", "Edit event"))

        doneBtn = MLButton(L("Fertig", "Done")) { [weak self] in self?.finish() }
        doneBtn.frame = NSRect(x: W - 11 - 64 - 12, y: H - Self.footerH + 11, width: 64, height: 20)
        let del = MLButton(L("Löschen", "Delete")) { [weak self] in
            guard let s = self else { return }; s.done = true; s.ctl.popover?.close(); s.ctl.delete(s.occ)
        }
        del.frame = NSRect(x: 12, y: H - Self.footerH + 11, width: 64, height: 20)
        v.addSubview(doneBtn); v.addSubview(del)
        del.isHidden = readOnly

        if readOnly {
            for c in [title_, location, url, notes] as [NSTextField] { c.isEditable = false }
            allDay.isEnabled = false; repeatPop.isEnabled = false; calPop.isEnabled = false; doneBtn.isEnabled = false
            from.isEnabled = false; to.isEnabled = false
            error.stringValue = L("Dieser Kalender ist schreibgeschützt.", "This calendar is read-only.")
        }
        view = v
        updateElements()
        validate()
    }
    private var closures: [MLClosure] = []

    private func showDropdown(for p: MLDatePicker) {
        dropdown?.removeFromSuperview()
        guard !readOnly else { return }
        let d = MLCalDropdown(cal: cal, selected: p.dateValue)
        d.frame.origin = NSPoint(x: p.frame.minX - 6, y: p.frame.maxY + 2)
        d.onPick = { [weak self, weak p] day in
            guard let self, let p else { return }
            let t = self.cal.dateComponents([.hour, .minute], from: p.dateValue)
            var c = self.cal.dateComponents([.year, .month, .day], from: day); c.hour = t.hour; c.minute = t.minute
            p.dateValue = self.cal.date(from: c) ?? day
            self.dropdown?.removeFromSuperview(); self.dropdown = nil
            self.validate()
        }
        view.addSubview(d)
        dropdown = d
    }

    func focusTitleIfNew() {
        guard isNew else { return }
        view.window?.makeFirstResponder(title_)
        title_.currentEditor()?.selectAll(nil)
    }

    private func updateElements() {
        let el: NSDatePicker.ElementFlags = allDay.on ? [.yearMonthDay] : [.yearMonthDay, .hourMinute]
        from.datePickerElements = el; to.datePickerElements = el
    }

    private func allDayChanged() {
        if !allDay.on {
            let a = cal.startOfDay(for: from.dateValue)
            if from.dateValue == a { from.dateValue = cal.date(byAdding: .hour, value: 9, to: a)! }
            let b = cal.startOfDay(for: to.dateValue)
            to.dateValue = cal.date(byAdding: .hour, value: 10, to: b)!
            if to.dateValue <= from.dateValue { to.dateValue = from.dateValue.addingTimeInterval(3600) }
        }
        updateElements(); validate()
    }

    /// FUN-05: an invalid interval is explained, and cannot be saved.
    @discardableResult
    private func validate() -> Bool {
        guard !readOnly else { return false }
        let bad = allDay.on ? cal.startOfDay(for: to.dateValue) < cal.startOfDay(for: from.dateValue) : to.dateValue <= from.dateValue
        error.stringValue = bad ? L("Das Ende liegt vor dem Beginn. Bitte „bis“ oder „von“ ändern.", "The end is before the start. Please change “to” or “from”.") : ""
        doneBtn.isEnabled = !bad
        return !bad
    }

    private func finish() {
        guard validate() else { NSSound.beep(); return }
        done = true
        if commit() { ctl.popover?.close() } else { done = false }
    }

    /// Clicking away saves, too (Calendar saves as you go).
    func popoverClosed() {
        if !done, validate() { done = true; _ = commit() }
    }

    /// Returns false when the user cancelled the series question.
    private func commit() -> Bool {
        var n = occ.ev
        n.title = title_.stringValue.trimmingCharacters(in: .whitespaces)
        n.location = location.stringValue; n.url = url.stringValue; n.notes = notes.stringValue
        n.allDay = allDay.on
        n.calID = calIDs.indices.contains(calPop.index) ? calIDs[calPop.index] : n.calID
        n.repeatRule = MLRepeat.allCases[repeatPop.index]
        let s: Date, en: Date
        if n.allDay { s = cal.startOfDay(for: from.dateValue); en = cal.startOfDay(for: to.dateValue) } else { s = from.dateValue; en = to.dateValue }
        let oldEnd = occ.ev.allDay ? cal.date(byAdding: .day, value: -1, to: occ.end)! : occ.end
        let timesSame = s == occ.start && en == oldEnd && n.allDay == occ.ev.allDay
        var plain = occ.ev; plain.title = n.title; plain.location = n.location; plain.url = n.url; plain.notes = n.notes; plain.calID = n.calID; plain.repeatRule = n.repeatRule
        if plain == n && timesSame { return true }                       // nothing changed

        let store = ctl.store
        if occ.isRecurring && n.repeatRule == occ.ev.repeatRule {
            switch ctl.recurrenceChoice(L("Dies ist ein Serientermin.", "This is a repeating event."), verb: L("Ändern", "Change"), system: MLSystem.shared.owns(occ.ev.id)) {
            case .cancel: return false
            case .this:
                n.start = s; n.end = en
                if let d = store.detach(occ, as: n) { ctl.selectedKey = "\(d.id)|\(Int(MLStore.interval(d, cal: cal).0.timeIntervalSince1970))" }
            case .all:
                let shift = s.timeIntervalSince(occ.start)
                n.start = occ.ev.start.addingTimeInterval(shift)
                if n.allDay {
                    n.start = cal.startOfDay(for: n.start)
                    n.end = cal.date(byAdding: .day, value: cal.dateComponents([.day], from: s, to: en).day ?? 0, to: n.start)!
                } else { n.end = n.start.addingTimeInterval(en.timeIntervalSince(s)) }
                n.exceptions = timesSame ? n.exceptions : []
                let saved = store.update(n, series: true)
                ctl.selectedKey = "\(saved.id)|\(Int(MLStore.interval(saved, cal: cal).0.timeIntervalSince1970))"
            }
        } else {
            n.start = s; n.end = en
            n.exceptions = []
            let saved = store.update(n)
            ctl.selectedKey = "\(saved.id)|\(Int(MLStore.interval(saved, cal: cal).0.timeIntervalSince1970))"
        }
        ctl.refresh()
        return true
    }
}

// MARK: - Quick entry (FUN-10)

final class MLQuickVC: NSViewController, NSTextFieldDelegate {
    static let footerH: CGFloat = 42
    unowned let ctl: MLController
    private let field = NSTextField()
    private let info = NSTextField(labelWithString: "")

    init(_ ctl: MLController) { self.ctl = ctl; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let W: CGFloat = 340, H: CGFloat = 126
        let v = MLFlip(frame: NSRect(x: 0, y: 0, width: W, height: H))
        v.setAccessibilityLabel(L("Schnelleingabe", "Quick entry"))
        v.addSubview(lbl(L("Neuer Termin", "New Event"), NSRect(x: 12, y: 10, width: 200, height: 18), align: .left, bold: true, color: mlRGB(18, 28, 108), size: 12))
        plainField(field, NSRect(x: 12, y: 32, width: W - 35, height: 22), "", size: 12, placeholder: L("z. B. Zahnarzt morgen 15:30", "e.g. Dentist tomorrow 3:30pm"), accessibility: L("Termin in einem Satz", "Event in one sentence"))
        field.delegate = self; field.target = self; field.action = #selector(save)
        v.addSubview(field)
        let sep = NSView(frame: NSRect(x: 12, y: 55, width: W - 35, height: 1)); sep.wantsLayer = true; sep.layer?.backgroundColor = mlRGB(210, 210, 210).cgColor
        v.addSubview(sep)
        info.frame = NSRect(x: 12, y: 60, width: W - 35, height: 26)
        info.font = mlPF(10); info.textColor = mlRGB(100, 100, 100); info.maximumNumberOfLines = 2; info.lineBreakMode = .byWordWrapping
        info.setAccessibilityLabel(L("Erkannter Termin", "Interpreted event"))
        v.addSubview(info)
        let add = MLButton(L("Hinzufügen", "Add")) { [weak self] in self?.save() }
        add.isDefault = true; add.frame = NSRect(x: W - 11 - 92 - 8, y: H - Self.footerH + 9, width: 92, height: 24)
        v.addSubview(add)
        view = v
        update()
    }
    func focus() { view.window?.makeFirstResponder(field) }
    func controlTextDidChange(_ obj: Notification) { update() }

    private func summary(_ q: MLQuick) -> String {
        let day = MLPrefs.fmt(q.start, "yMMMEEEEd")
        let when = q.allDay ? day + ", " + L("ganztägig", "all-day") : "\(day), \(MLPrefs.time(q.start))–\(MLPrefs.time(q.end))"
        let cname = ctl.writableCalID.flatMap { ctl.store.calendar($0)?.name } ?? ""
        return "→ \(when)\n" + L("Kalender: ", "Calendar: ") + cname + (q.hasDate ? "" : "  ·  " + L("kein Datum erkannt, heute", "no date found, using today"))
    }

    private func update() {
        let q = MLQuickParser.parse(field.stringValue, now: ctl.now(), cal: ctl.cal)
        let missing = q.title.isEmpty && !field.stringValue.isEmpty
        info.stringValue = field.stringValue.isEmpty ? L("Titel mit Datum und Uhrzeit eingeben, mit Return sichern.", "Type a title with date and time, press Return to save.")
            : q.title.isEmpty ? L("Der Titel fehlt.", "The title is missing.") : summary(q)
        info.textColor = missing ? mlRGB(190, 40, 30) : mlRGB(100, 100, 100)
    }

    @objc private func save() {
        let q = MLQuickParser.parse(field.stringValue, now: ctl.now(), cal: ctl.cal)
        guard !q.title.isEmpty, let cid = ctl.writableCalID else { NSSound.beep(); return }
        var ev = MLEvent(calID: cid, title: q.title, start: q.start, end: q.allDay ? q.start : q.end, allDay: q.allDay)
        ev = ctl.store.add(ev)
        ctl.date = ctl.cal.startOfDay(for: q.start)
        ctl.selectedKey = "\(ev.id)|\(Int(MLStore.interval(ev, cal: ctl.cal).0.timeIntervalSince1970))"
        ctl.popover?.close()
        ctl.refresh()
    }
}

// MARK: - Settings window (FUN-14), styled after the OS X 10.8 preferences window

private final class MLPrefsRoot: NSView {
    unowned let owner: MLPrefsController
    init(_ o: MLPrefsController) { owner = o; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
    static let headerH: CGFloat = 78
    private var hover = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let h = NSRect(x: 8, y: 4, width: 64, height: 18).contains(p)
        if h != hover { hover = h; needsDisplay = true }
    }
    override func mouseExited(with e: NSEvent) { hover = false; needsDisplay = true }

    static let lights: [NSPoint] = (0..<3).map { NSPoint(x: 20 + CGFloat($0) * 20, y: 13) }

    override func draw(_ dirty: NSRect) {
        let w = bounds.width
        mlRGB(237, 237, 237).setFill(); bounds.fill()
        let head = NSRect(x: 0, y: 0, width: w, height: Self.headerH)
        mlGradient(head, [(0, mlRGB(238, 238, 238)), (0.45, mlRGB(218, 218, 218)), (1, mlRGB(196, 196, 196))])
        mlLine(NSRect(x: 0, y: 0, width: w, height: 1), .white)
        mlLine(NSRect(x: 0, y: Self.headerH - 1, width: w, height: 1), mlRGB(118, 118, 118))
        let active = window?.isKeyWindow ?? false
        mlText(owner.currentTitle, NSRect(x: 0, y: 4, width: w, height: 18), mlPF(12), mlRGB(50, 50, 50, active ? 1 : 0.5), align: .center, shadow: mlRGB(255, 255, 255, 0.8))
        mlTrafficLights(centers: Self.lights, dia: 12, active: active, hover: hover)
        // toolbar items
        let n = owner.tabs.count
        let itemW: CGFloat = 76, x0 = (w - itemW * CGFloat(n)) / 2
        for (i, t) in owner.tabs.enumerated() {
            let r = NSRect(x: x0 + CGFloat(i) * itemW, y: 26, width: itemW, height: 50)
            if owner.selected == i {
                mlRGB(0, 0, 0, 0.14).setFill(); NSBezierPath(roundedRect: r.insetBy(dx: 2, dy: 0), xRadius: 5, yRadius: 5).fill()
                mlRGB(0, 0, 0, 0.18).setStroke(); NSBezierPath(roundedRect: r.insetBy(dx: 2.5, dy: 0.5), xRadius: 5, yRadius: 5).stroke()
            }
            t.icon(NSRect(x: r.midX - 16, y: r.minY + 4, width: 32, height: 32))
            mlText(t.title, NSRect(x: r.minX, y: r.minY + 34, width: r.width, height: 14), mlPF(10), .black, align: .center)
        }
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        for (i, c) in Self.lights.enumerated() where hypot(p.x - c.x, p.y - c.y) < 8 {
            guard let w = window else { return }
            [{ w.close() }, { w.miniaturize(nil) }, { w.zoom(nil) }][i](); return
        }
        let n = owner.tabs.count, itemW: CGFloat = 76, x0 = (bounds.width - itemW * CGFloat(n)) / 2
        if p.y > 26, p.y < Self.headerH { let i = Int((p.x - x0) / itemW); if i >= 0, i < n { owner.select(i); return } }
        super.mouseDown(with: e)
    }
}

final class MLPrefsController: NSObject {
    struct Tab { var title: String; var icon: (NSRect) -> Void }
    private(set) var window: NSWindow?
    private var root: MLPrefsRoot!
    private var panes: [NSView] = []
    private(set) var selected = 0
    private var sysStatus = NSTextField(labelWithString: "")
    private var sysCheck: MLCheck!

    var tabs: [Tab] {
        [Tab(title: L("Allgemein", "General")) { r in
            mlGradient(r.insetBy(dx: 5, dy: 1), [(0, mlRGB(250, 250, 250)), (1, mlRGB(190, 190, 190))], radius: 4)
            mlRGB(110, 110, 110).setStroke(); NSBezierPath(roundedRect: r.insetBy(dx: 5.5, dy: 1.5), xRadius: 4, yRadius: 4).stroke()
            mlGradient(NSRect(x: r.midX - 5, y: r.minY + 6, width: 10, height: 20), [(0, mlRGB(70, 70, 70)), (1, mlRGB(150, 150, 150))], radius: 3)
        },
         Tab(title: L("Systemkalender", "Accounts")) { r in
            let c = NSRect(x: r.minX + 3, y: r.minY + 3, width: 26, height: 26)
            mlGradient(c, [(0, mlRGB(110, 170, 250)), (1, mlRGB(30, 90, 214))], radius: 13)
            mlText("@", c, mlFont(22, bold: true), .white, align: .center)
        },
         Tab(title: L("Mitteilungen", "Alerts")) { r in
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX + 6, y: r.minY + 12)); p.line(to: NSPoint(x: r.minX + 14, y: r.minY + 12)); p.line(to: NSPoint(x: r.maxX - 4, y: r.minY + 4))
            p.line(to: NSPoint(x: r.maxX - 4, y: r.maxY - 6)); p.line(to: NSPoint(x: r.minX + 14, y: r.minY + 20)); p.line(to: NSPoint(x: r.minX + 6, y: r.minY + 20)); p.close()
            mlGradient(r, [(0, mlRGB(244, 210, 90)), (1, mlRGB(196, 140, 24))]); NSGraphicsContext.saveGraphicsState(); p.addClip()
            mlGradient(r, [(0, mlRGB(250, 222, 110)), (1, mlRGB(196, 140, 24))]); NSGraphicsContext.restoreGraphicsState()
            mlRGB(130, 90, 10).setStroke(); p.lineWidth = 1; p.stroke()
        }]
    }
    var currentTitle: String { tabs[selected].title }

    func show() {
        if window == nil { build() }
        refreshSystemPane()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func select(_ i: Int) {
        selected = i
        for (k, p) in panes.enumerated() { p.isHidden = k != i }
        root.needsDisplay = true
        window?.title = currentTitle
    }

    private func build() {
        let W: CGFloat = 520, H: CGFloat = 392
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(b)?.isHidden = true }
        w.appearance = NSAppearance(named: .aqua)
        w.isReleasedWhenClosed = false
        w.title = L("Allgemein", "General")
        root = MLPrefsRoot(self)
        w.contentView = root
        window = w
        w.center()

        let top = MLPrefsRoot.headerH
        func pane() -> MLFlip { let p = MLFlip(frame: NSRect(x: 0, y: top, width: W, height: H - top)); root.addSubview(p); panes.append(p); return p }

        // General
        let g = pane()
        var y: CGFloat = 34
        func row(_ pane: NSView, _ name: String, _ c: NSView, h: CGFloat = 22) {
            pane.addSubview(lbl(name, NSRect(x: 0, y: y + 3, width: 190, height: 16), color: .black, size: 11.5))
            c.frame.origin = NSPoint(x: 202, y: y); c.frame.size.height = h; pane.addSubview(c); y += h + 12
        }
        let wk = [2, 1, 7]
        row(g, L("Woche beginnt am:", "Week starts on:"), MLPopup([L("Montag", "Monday"), L("Sonntag", "Sunday"), L("Samstag", "Saturday")], index: wk.firstIndex(of: MLPrefs.weekStart) ?? 0) { MLPrefs.weekStart = wk[$0] }.sized(170))
        row(g, L("Zeitformat:", "Time format:"), MLCheck(L("24-Stunden-Zeit", "24-hour time"), on: MLPrefs.hour24, { }).bind { MLPrefs.hour24 = $0 }, h: 18)
        let hours = (0...24).map { String(format: "%02d:00", $0) }
        row(g, L("Tag beginnt um:", "Day starts at:"), MLPopup(Array(hours[0...23]), index: MLPrefs.dayStart) { MLPrefs.dayStart = min($0, MLPrefs.dayEnd - 1) }.sized(100))
        row(g, L("Tag endet um:", "Day ends at:"), MLPopup(Array(hours[1...24]), index: MLPrefs.dayEnd - 1) { MLPrefs.dayEnd = max($0 + 1, MLPrefs.dayStart + 1) }.sized(100))
        let ids = [""] + TimeZone.knownTimeZoneIdentifiers.sorted()
        row(g, L("Zeitzone:", "Time zone:"), MLPopup([L("Systemzeitzone", "System time zone")] + ids.dropFirst(), index: ids.firstIndex(of: MLPrefs.timeZoneID) ?? 0) { MLPrefs.timeZoneID = ids[$0] }.sized(240))
        let langs = ["auto", "de", "en"]
        row(g, L("Sprache:", "Language:"), MLPopup([L("Automatisch", "Automatic"), "Deutsch", "English"], index: langs.firstIndex(of: MLPrefs.lang) ?? 0) { MLPrefs.lang = langs[$0] }.sized(170))

        // System calendars
        let s = pane()
        sysCheck = MLCheck(L("Kalender dieses Macs verwenden", "Use this Mac's calendars"), on: MLSystem.shared.enabled) { }
        sysCheck.frame = NSRect(x: 40, y: 34, width: 420, height: 18)
        _ = sysCheck.bind { [weak self] on in MLSystem.shared.setEnabled(on) { self?.refreshSystemPane() } }
        s.addSubview(sysCheck)
        sysStatus.frame = NSRect(x: 62, y: 60, width: 420, height: 48)
        sysStatus.font = mlPF(10.5); sysStatus.textColor = mlRGB(100, 100, 100); sysStatus.maximumNumberOfLines = 3; sysStatus.lineBreakMode = .byWordWrapping
        s.addSubview(sysStatus)
        let open = MLButton(L("Systemeinstellungen öffnen…", "Open System Settings…")) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
        }
        open.frame = NSRect(x: 62, y: 118, width: 220, height: 24); s.addSubview(open)
        let note = lbl(L("Die Anwendung fragt erst nach Zugriff, wenn du das einschaltest. Ohne Zugriff bleiben alle lokalen Kalender voll nutzbar. Änderungen an Systemkalendern werden sofort gespeichert und lassen sich hier nicht rückgängig machen.",
                         "Access is only requested when you turn this on. Without it all local calendars stay fully usable. Changes to system calendars are saved immediately and cannot be undone here."),
                       NSRect(x: 62, y: 156, width: 410, height: 60), align: .left, color: mlRGB(120, 120, 120), size: 10)
        note.maximumNumberOfLines = 4; note.lineBreakMode = .byWordWrapping; s.addSubview(note)

        // Alerts (not available)
        let a = pane()
        let msg = lbl(L("Terminerinnerungen sind in dieser Version nicht verfügbar.\nEinladungen und iCalendar-Import/-Export ebenfalls nicht.",
                        "Alerts are not available in this version.\nInvitations and iCalendar import/export are not available either."),
                      NSRect(x: 40, y: 40, width: 440, height: 50), align: .left, color: mlRGB(80, 80, 80), size: 11.5)
        msg.maximumNumberOfLines = 3; a.addSubview(msg)
        select(0)
    }

    private func refreshSystemPane() {
        sysCheck?.on = MLSystem.shared.enabled
        sysStatus.stringValue = MLSystem.shared.enabled ? MLSystem.shared.statusText : L("Ausgeschaltet.", "Off.")
    }
}

private extension MLPopup {
    func sized(_ w: CGFloat) -> MLPopup { frame.size.width = w; return self }
}
private extension MLCheck {
    @discardableResult
    func bind(_ f: @escaping (Bool) -> Void) -> MLCheck {
        let c = MLClosure { [weak self] in if let s = self { f(s.on) } }
        objc_setAssociatedObject(self, "ml.bind", c, .OBJC_ASSOCIATION_RETAIN)
        target = c; action = #selector(MLClosure.run)
        return self
    }
}
