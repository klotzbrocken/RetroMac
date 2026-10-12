import AppKit

// Window, header (leather), sidebar and the controller that ties the calendar together.

enum MLMode: Int { case day, week, month, year }

// MARK: - Accessibility + hotspot base

final class MLAXElement: NSAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { press?(); return press != nil }
}

struct MLHot {
    var rect: NSRect
    var label: String
    var role: NSAccessibility.Role = .button
    var action: () -> Void
}

/// Flipped view that owns a list of clickable rects and exposes them to VoiceOver.
class MLView: NSView {
    unowned var ctl: MLController
    var hots: [MLHot] = []

    init(_ ctl: MLController) { self.ctl = ctl; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    func hot(at p: NSPoint) -> MLHot? { hots.last { $0.rect.contains(p) } }

    func axChildren(_ list: [MLHot]) -> [Any] {
        list.map { h in
            let e = MLAXElement()
            e.setAccessibilityRole(h.role)
            e.setAccessibilityLabel(h.label)
            e.setAccessibilityParent(self)
            if let w = window { e.setAccessibilityFrame(w.convertToScreen(convert(h.rect, to: nil))) }
            e.press = h.action
            return e
        }
    }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { axChildren(hots) }
}

// MARK: - Window

final class MLWindow: NSWindow {
    weak var ctl: MLController?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if firstResponder is NSTextView, super.performKeyEquivalent(with: event) { return true }
        return ctl?.handleKey(event, shortcutOnly: true) ?? false
    }
    override func cancelOperation(_ sender: Any?) { ctl?.escape() }
}

final class MLRootView: NSView {
    unowned var ctl: MLController
    init(_ c: MLController) { ctl = c; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { NSColor.white.setFill(); dirtyRect.fill() }
    /// The calendar is laid out in the reference screenshots' units and scaled up (they are ~2/3 size),
    /// so every drawing stays vector-sharp and proportions match the original.
    static let scale: CGFloat = 1.5
    override func setFrameSize(_ s: NSSize) {
        super.setFrameSize(s)
        setBoundsSize(NSSize(width: s.width / Self.scale, height: s.height / Self.scale))
    }
    override func layout() {
        super.layout()
        let h = MLHeaderView.chromeH
        ctl.header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: MLHeaderView.height)
        let sw: CGFloat = ctl.sidebarVisible ? MLSidebarView.width : 0
        ctl.sidebar.isHidden = !ctl.sidebarVisible
        ctl.sidebar.frame = NSRect(x: 0, y: h, width: sw, height: bounds.height - h)
        ctl.main.frame = NSRect(x: sw, y: h, width: bounds.width - sw, height: bounds.height - h)
    }
}

// MARK: - Controller

final class MLController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    static let shared = MLController()
    /// Smallest usable size (LASTENHEFT §5.1: 800 × 600 test size).
    static let minContentSize = NSSize(width: 800, height: 600)

    var store = MLStore.shared
    private(set) var window: MLWindow?
    var popover: MLPopover?
    private var settings: MLPrefsController?

    var mode: MLMode = MLMode(rawValue: UserDefaults.standard.object(forKey: "mlcal.mode") as? Int ?? 2) ?? .month
    var date = MLPrefs.calendar.startOfDay(for: Date())
    var selectedKey: String?
    var sidebarVisible = UserDefaults.standard.object(forKey: "mlcal.sidebar") as? Bool ?? true
    var defaultCalID: UUID?
    var query = ""

    lazy var header = MLHeaderView(self)
    lazy var sidebar = MLSidebarView(self)
    lazy var main = MLMainView(self)
    lazy var searchField = MLSearchField(self)

    /// Test/automation hook: a fixed "now" so screenshots and comparisons are reproducible (§10.1).
    var now: () -> Date = { Date() }

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .mlStoreChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged), name: .mlPrefsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSWindow.didResignKeyNotification, object: nil)
        defaultCalID = store.calendars.first?.id
    }

    var cal: Calendar { MLPrefs.calendar }
    var today: Date { cal.startOfDay(for: now()) }
    var isActive: Bool { window?.isKeyWindow ?? false }

    // MARK: window lifecycle

    func makeWindow(size: NSSize = NSSize(width: 1086, height: 735)) -> MLWindow {
        let w = MLWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.ctl = self
        w.title = "Kalender"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(b)?.isHidden = true }
        w.appearance = NSAppearance(named: .aqua)           // VIS: historical light design regardless of system dark mode
        w.backgroundColor = .white
        w.isReleasedWhenClosed = false
        w.collectionBehavior.insert(.fullScreenPrimary)
        w.contentMinSize = MLController.minContentSize
        w.delegate = self
        let root = MLRootView(self)
        w.contentView = root
        for v in [main, sidebar, header] { root.addSubview(v) }
        header.addSubview(searchField)
        w.setAccessibilityLabel(L("Kalender", "Calendar"))
        return w
    }

    func show() {
        if window == nil {
            let w = makeWindow()
            window = w
            w.setFrameAutosaveName("RetroMacMLCalendar2")
            if !w.setFrameUsingName("RetroMacMLCalendar2") { w.center() }
            if let msg = store.loadError { store.loadError = nil; DispatchQueue.main.async { self.alert(msg) } }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(main)
        refresh()
        MLSystem.shared.resumeIfNeeded { [weak self] in self?.refresh() }
    }

    func windowWillClose(_ notification: Notification) { popover?.close() }
    func windowDidResize(_ notification: Notification) { refresh() }

    @objc func prefsChanged() { date = cal.startOfDay(for: date); main.scrollToDayStart(); refresh() }
    @objc func refresh() {
        for v in [header, sidebar, main] as [NSView] { v.needsDisplay = true }
        window?.contentView?.needsLayout = true
        header.needsLayout = true
        window?.title = L("Kalender", "Calendar")
    }

    func alert(_ text: String) {
        let a = NSAlert(); a.messageText = text; a.addButton(withTitle: "OK"); a.runModal()
    }

    // MARK: navigation (FUN-01, FUN-02)

    func setMode(_ m: MLMode) {
        mode = m
        UserDefaults.standard.set(m.rawValue, forKey: "mlcal.mode")
        refresh()
    }

    func goToday() { date = today; selectedKey = nil; main.scrollToDayStart(); refresh() }

    func step(_ dir: Int) {
        let unit: (Calendar.Component, Int)
        switch mode { case .day: unit = (.day, 1); case .week: unit = (.weekOfYear, 1); case .month: unit = (.month, 1); case .year: unit = (.year, 1) }
        date = cal.date(byAdding: unit.0, value: unit.1 * dir, to: date) ?? date
        refresh()
    }

    /// Keyboard: move the reference date inside the current view.
    func nudge(days: Int) {
        date = cal.date(byAdding: .day, value: days, to: date) ?? date
        refresh()
    }

    func select(date d: Date) { date = cal.startOfDay(for: d); selectedKey = nil; refresh() }

    func toggleSidebar() {
        sidebarVisible.toggle()
        UserDefaults.standard.set(sidebarVisible, forKey: "mlcal.sidebar")
        window?.contentView?.needsLayout = true
        refresh()
    }

    var title: String {
        switch mode {
        case .year: return MLPrefs.fmt(date, "y")
        case .month: return MLPrefs.fmt(date, "yMMMM")
        case .day: return MLPrefs.fmt(date, "yMMMMd")
        case .week:
            let a = weekStart(of: date), b = cal.date(byAdding: .day, value: 6, to: a)!
            if cal.component(.month, from: a) == cal.component(.month, from: b) {
                let d1 = cal.component(.day, from: a), d2 = cal.component(.day, from: b)
                return MLPrefs.isDE ? "\(d1).–\(MLPrefs.fmt(b, "dMMMMy"))"
                                    : "\(MLPrefs.fmt(a, "MMMM")) \(d1) - \(d2), \(cal.component(.year, from: a))"
            }
            return "\(MLPrefs.fmt(a, "dMMM")) – \(MLPrefs.fmt(b, "dMMMy"))"
        }
    }

    func weekStart(of d: Date) -> Date {
        let off = (cal.component(.weekday, from: d) - cal.firstWeekday + 7) % 7
        return cal.date(byAdding: .day, value: -off, to: cal.startOfDay(for: d))!
    }

    // MARK: events (FUN-04 … FUN-07)

    func occ(withKey k: String?) -> MLOcc? {
        guard let k else { return nil }
        let id = String(k.split(separator: "|").first ?? "")
        guard let uuid = UUID(uuidString: id) else { return nil }
        if let sys = MLSystem.shared.event(uuid) {            // system events are concrete occurrences already
            let (a, b) = MLStore.interval(sys, cal: cal)
            let o = MLOcc(ev: sys, start: a, end: b)
            return o.id == k ? o : nil
        }
        guard let ev = store.event(uuid) else { return nil }
        let s = cal.date(byAdding: .day, value: -1, to: date)!
        let range = (cal.date(byAdding: .year, value: -2, to: s)!, cal.date(byAdding: .year, value: 3, to: s)!)
        var out: [MLOcc] = []
        MLStore.expand(ev, from: range.0, to: range.1, cal: cal, into: &out)
        return out.first { $0.id == k }
    }

    var selectedOcc: MLOcc? { occ(withKey: selectedKey) }

    var writableCalID: UUID? {
        if let d = defaultCalID, let c = store.calendar(d), !c.readOnly { return d }
        return store.allCalendars.first { !$0.readOnly }?.id
    }

    /// Creates the event right away (as Calendar did) and opens its editor.
    func newEvent(start: Date? = nil, allDay: Bool = true, anchor: NSRect? = nil, in view: NSView? = nil) {
        guard let cid = writableCalID else { alert(L("Es gibt keinen beschreibbaren Kalender.", "There is no writable calendar.")); return }
        let s = start ?? (cal.isDate(date, inSameDayAs: today) ? cal.date(bySetting: .minute, value: 0, of: cal.date(byAdding: .hour, value: 1, to: now())!)! : cal.date(byAdding: .hour, value: 9, to: date)!)
        let day = cal.startOfDay(for: s)
        var ev = MLEvent(calID: cid, title: "", start: allDay ? day : s, end: allDay ? day : cal.date(byAdding: .hour, value: 1, to: s)!, allDay: allDay)
        ev = store.add(ev)
        let o = MLOcc(ev: ev, start: allDay ? day : s, end: allDay ? cal.date(byAdding: .day, value: 1, to: day)! : ev.end)
        selectedKey = o.id
        date = day
        refresh()
        openEditor(o, rect: anchor ?? main.rectForSelected() ?? NSRect(x: main.bounds.midX, y: 60, width: 1, height: 1), view: view ?? main, isNew: true)
    }

    func openEditor(_ o: MLOcc, rect: NSRect, view: NSView, isNew: Bool = false) {
        popover?.close()
        let vc = MLEditorVC(self, occ: o, isNew: isNew)
        let p = MLPopover()
        popover = p
        p.onClose = { [weak vc] in vc?.popoverClosed() }
        p.show(vc.view, footer: 0, relativeTo: rect, of: view)
        vc.focusTitleIfNew()
    }

    func editSelected() {
        guard let o = selectedOcc else { return }
        openEditor(o, rect: main.rectForSelected() ?? NSRect(x: main.bounds.midX, y: 60, width: 1, height: 1), view: main)
    }

    func deleteSelected() { if let o = selectedOcc { delete(o) } }

    func delete(_ o: MLOcc) {
        if store.calendar(o.ev.calID)?.readOnly == true { alert(L("Dieser Kalender ist schreibgeschützt.", "This calendar is read-only.")); return }
        if o.isRecurring {
            switch recurrenceChoice(L("Dies ist ein Serientermin.", "This is a repeating event."), verb: L("Löschen", "Delete"), system: MLSystem.shared.owns(o.ev.id)) {
            case .this: store.deleteOccurrence(o)
            case .all: store.delete(o.ev.id, series: true)
            case .cancel: return
            }
        } else { store.delete(o.ev.id) }
        selectedKey = nil
    }

    func duplicateSelected() {
        guard let o = selectedOcc, let id = store.duplicate(o.ev.id), let e = store.event(id) ?? MLSystem.shared.event(id) else { return }
        selectedKey = occ(withKey: "\(e.id)|\(Int(MLStore.interval(e, cal: cal).0.timeIntervalSince1970))")?.id
        refresh()
    }

    enum Scope { case this, all, cancel }
    func recurrenceChoice(_ text: String, verb: String, system: Bool = false) -> Scope {
        let a = NSAlert()
        a.messageText = text
        a.informativeText = L("Soll nur dieses Vorkommen oder die ganze Serie geändert werden?", "Do you want to change only this occurrence or the whole series?")
        a.addButton(withTitle: L("Nur dieses Vorkommen", "Only This Event"))
        a.addButton(withTitle: system ? L("Dieses und alle folgenden", "This and All Future") : L("Alle", "All Events"))
        a.addButton(withTitle: L("Abbrechen", "Cancel"))
        switch a.runModal() { case .alertFirstButtonReturn: return .this; case .alertSecondButtonReturn: return .all; default: return .cancel }
    }

    /// Drag result (FUN-07): only the chosen occurrence, or the series shifted as a whole.
    func move(_ o: MLOcc, newStart: Date, newEnd: Date) {
        if store.calendar(o.ev.calID)?.readOnly == true { NSSound.beep(); return }
        var e = o.ev
        if o.isRecurring {
            switch recurrenceChoice(L("Dies ist ein Serientermin.", "This is a repeating event."), verb: L("Ändern", "Change"), system: MLSystem.shared.owns(o.ev.id)) {
            case .cancel: return
            case .this:
                apply(&e, o, newStart, newEnd)
                if let n = store.detach(o, as: e) { selectedKey = "\(n.id)|\(Int(MLStore.interval(n, cal: cal).0.timeIntervalSince1970))" }
                return
            case .all:
                let shift = newStart.timeIntervalSince(o.start)
                e.start = o.ev.start.addingTimeInterval(shift); e.end = o.ev.end.addingTimeInterval(shift)
                if e.allDay { e.start = cal.startOfDay(for: e.start); e.end = cal.startOfDay(for: e.end) }
                e.exceptions = []
            }
        } else { apply(&e, o, newStart, newEnd) }
        let saved = store.update(e, name: L("Termin verschieben", "Move Event"), series: o.isRecurring)
        selectedKey = "\(saved.id)|\(Int(MLStore.interval(saved, cal: cal).0.timeIntervalSince1970))"
    }

    private func apply(_ e: inout MLEvent, _ o: MLOcc, _ s: Date, _ en: Date) {
        if e.allDay { e.start = s; e.end = cal.date(byAdding: .day, value: -1, to: en) ?? s } else { e.start = s; e.end = en }
    }

    // MARK: quick entry + search

    func showQuickEntry() {
        popover?.close()
        let vc = MLQuickVC(self)
        let p = MLPopover()
        popover = p
        p.show(vc.view, footer: MLQuickVC.footerH, relativeTo: header.plusRect, of: header, preferred: .below)
        vc.focus()
    }

    func controlTextDidChange(_ obj: Notification) {
        query = searchField.field.stringValue
        searchField.needsDisplay = true
        main.needsDisplay = true
    }

    func focusSearch() { window?.makeFirstResponder(searchField.field) }

    func clearSearch() {
        query = ""; searchField.field.stringValue = ""
        searchField.needsDisplay = true; main.needsDisplay = true
        window?.makeFirstResponder(main)
    }

    func escape() {
        if main.cancelDrag() { return }
        if !query.isEmpty { clearSearch(); return }
        if popover?.isShown == true { popover?.close() }
    }

    func reveal(_ o: MLOcc) {
        date = cal.startOfDay(for: o.start); selectedKey = o.id
        window?.makeFirstResponder(main)
        refresh()
    }

    func showSettings() {
        if settings == nil { settings = MLPrefsController() }
        settings?.show()
    }

    // MARK: keyboard (FUN-13)

    @discardableResult
    func handleKey(_ e: NSEvent, shortcutOnly: Bool) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
        let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if mods.contains(.command) {
            switch (ch, mods.contains(.shift)) {
            case ("1", _): setMode(.day)
            case ("2", _): setMode(.week)
            case ("3", _): setMode(.month)
            case ("4", _): setMode(.year)
            case ("t", _): goToday()
            case ("n", false): newEvent()
            case ("n", true): showQuickEntry()
            case ("f", _): focusSearch()
            case ("d", _): duplicateSelected()
            case ("e", _): editSelected()
            case ("r", _): break
            case ("z", false): store.undoManager.undo()
            case ("z", true): store.undoManager.redo()
            case (",", _): showSettings()
            case ("w", _): window?.close()
            case ("\u{7f}", _), (String(UnicodeScalar(NSBackspaceCharacter)!), _): deleteSelected()
            default:
                if e.keyCode == 123 { step(-1); return true }
                if e.keyCode == 124 { step(1); return true }
                return false
            }
            return true
        }
        if shortcutOnly { return false }
        switch e.keyCode {
        case 123: nudge(days: -1)
        case 124: nudge(days: 1)
        case 125: nudge(days: mode == .day ? 1 : 7)
        case 126: nudge(days: mode == .day ? -1 : -7)
        case 36, 76: if selectedKey != nil { editSelected() } else { newEvent() }
        case 51, 117: deleteSelected()
        case 53: escape()
        default: return false
        }
        return true
    }
}
