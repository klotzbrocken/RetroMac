import AppKit
import EventKit
import CryptoKit

/// System calendars (Apple Calendar / iCloud / Exchange accounts known to macOS) through EventKit.
/// DAT-06/07: asked for only when the user switches it on; denial or later revocation never touches local data.
/// Calendars the account allows to be changed are editable; others stay locked. Changes are saved straight to the
/// system store and are not part of the in-app undo history (EventKit has no undo).
final class MLSystem {
    static let shared = MLSystem()

    private let store = EKEventStore()
    private let d = UserDefaults.standard
    private(set) var calendars: [MLCal] = []
    private var identifiers: [UUID: String] = [:]
    private var cache: [UUID: MLEvent] = [:]
    private var eks: [UUID: EKEvent] = [:]

    private init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reload(); NotificationCenter.default.post(name: .mlStoreChanged, object: nil)
        }
        reload()
    }

    /// Until the user decides, follows an existing system grant (no new permission prompt is ever shown for this default).
    var enabled: Bool { d.object(forKey: "mlcal.sys") as? Bool ?? granted }
    var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    var granted: Bool { status == .fullAccess }
    private var hidden: Set<String> { Set(d.stringArray(forKey: "mlcal.sysHidden") ?? []) }
    var isActive: Bool { enabled && granted }

    var statusText: String {
        switch status {
        case .fullAccess: return L("Zugriff erlaubt", "Access granted")
        case .denied: return L("Zugriff verweigert – in den Systemeinstellungen unter „Datenschutz & Sicherheit › Kalender“ erlauben.", "Access denied – allow it in System Settings under Privacy & Security › Calendars.")
        case .restricted: return L("Zugriff durch das System eingeschränkt.", "Access is restricted by the system.")
        case .writeOnly: return L("Nur Schreibzugriff erteilt; zum Lesen ist voller Zugriff nötig.", "Only write access was granted; full access is needed to read.")
        default: return L("Noch nicht angefragt.", "Not requested yet.")
        }
    }

    /// Turning it on asks for permission; turning it off just hides the calendars.
    func setEnabled(_ on: Bool, done: @escaping () -> Void) {
        d.set(on, forKey: "mlcal.sys")
        guard on, status == .notDetermined else { reload(); notify(done); return }
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async { self?.reload(); self?.notify(done) }
        }
    }

    /// Called when the window opens: an earlier opt-in that never got its answer (dialog dismissed) is asked again.
    func resumeIfNeeded(done: @escaping () -> Void) { if enabled && status == .notDetermined { setEnabled(true, done: done) } else { reload(); done() } }

    private func notify(_ done: () -> Void) { NotificationCenter.default.post(name: .mlStoreChanged, object: nil); done() }

    func toggle(_ id: UUID) {
        guard let ident = identifiers[id] else { return }
        var h = hidden
        if h.contains(ident) { h.remove(ident) } else { h.insert(ident) }
        d.set(Array(h), forKey: "mlcal.sysHidden")
        reload(); NotificationCenter.default.post(name: .mlStoreChanged, object: nil)
    }

    private static func uuid(_ s: String) -> UUID {
        let h = Array(Insecure.MD5.hash(data: Data(s.utf8)))
        return UUID(uuid: (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8], h[9], h[10], h[11], h[12], h[13], h[14], h[15]))
    }

    func reload() {
        guard isActive else { calendars = []; identifiers = [:]; cache = [:]; eks = [:]; return }
        let hide = hidden
        var out: [MLCal] = [], ids: [UUID: String] = [:]
        for c in store.calendars(for: .event).sorted(by: { ($0.source.title, $0.title) < ($1.source.title, $1.title) }) {
            let id = Self.uuid(c.calendarIdentifier)
            let col = (c.color.usingColorSpace(.sRGB) ?? .gray)
            let hex = UInt32(col.redComponent * 255) << 16 | UInt32(col.greenComponent * 255) << 8 | UInt32(col.blueComponent * 255)
            out.append(MLCal(id: id, name: c.title, colorHex: hex, visible: !hide.contains(c.calendarIdentifier), readOnly: !c.allowsContentModifications, group: c.source.title))
            ids[id] = c.calendarIdentifier
        }
        calendars = out; identifiers = ids
    }

    func event(_ id: UUID) -> MLEvent? { cache[id] }

    private func visibleEKCalendars() -> [EKCalendar] {
        let visible = Set(calendars.filter { $0.visible }.compactMap { identifiers[$0.id] })
        return store.calendars(for: .event).filter { visible.contains($0.calendarIdentifier) }
    }

    func occurrences(from lo: Date, to hi: Date) -> [MLOcc] {
        guard isActive, hi.timeIntervalSince(lo) < 86400 * 800 else { return [] }
        let cals = visibleEKCalendars()
        guard !cals.isEmpty else { return [] }
        let cal = MLPrefs.calendar
        if cache.count > 5000 { cache = [:]; eks = [:] }
        return store.events(matching: store.predicateForEvents(withStart: lo, end: hi, calendars: cals)).map { e in
            let ev = register(e, fallback: lo)
            let (a, b) = MLStore.interval(ev, cal: cal)
            return MLOcc(ev: ev, start: a, end: b)
        }
    }

    /// Stable id per occurrence (identifier + start); keeps the EKEvent for later saves.
    @discardableResult
    private func register(_ e: EKEvent, fallback: Date) -> MLEvent {
        let cal = MLPrefs.calendar
        let sd: Date = e.startDate ?? fallback, ed: Date = e.endDate ?? sd
        let rule: MLRepeat
        switch e.recurrenceRules?.first?.frequency {
        case .daily?: rule = .daily
        case .weekly?: rule = .weekly
        case .monthly?: rule = .monthly
        case .yearly?: rule = .yearly
        default: rule = .none
        }
        let id = Self.uuid("\(e.eventIdentifier ?? e.title ?? "")|\(Int(sd.timeIntervalSince1970))")
        let ev = MLEvent(id: id, calID: Self.uuid(e.calendar.calendarIdentifier), title: e.title ?? "", location: e.location ?? "",
                         start: e.isAllDay ? cal.startOfDay(for: sd) : sd, end: e.isAllDay ? cal.startOfDay(for: ed) : ed, allDay: e.isAllDay,
                         notes: e.notes ?? "", url: e.url?.absoluteString ?? "", repeatRule: rule)
        cache[id] = ev; eks[id] = e
        return ev
    }

    // MARK: writing

    func isSystem(calendar id: UUID) -> Bool { identifiers[id] != nil }
    func owns(_ id: UUID) -> Bool { eks[id] != nil }

    private func fail(_ error: Error) {
        let a = NSAlert()
        a.messageText = L("Der Systemkalender konnte nicht geändert werden.", "The system calendar could not be changed.")
        a.informativeText = error.localizedDescription
        a.addButton(withTitle: "OK"); a.runModal()
    }

    private func ekCalendar(_ id: UUID) -> EKCalendar? {
        guard let ident = identifiers[id] else { return nil }
        return store.calendars(for: .event).first { $0.calendarIdentifier == ident }
    }

    private func fill(_ ek: EKEvent, from e: MLEvent) {
        let cal = MLPrefs.calendar
        ek.title = e.title.isEmpty ? L("Neuer Termin", "New Event") : e.title
        ek.location = e.location.isEmpty ? nil : e.location
        ek.notes = e.notes.isEmpty ? nil : e.notes
        ek.url = e.url.isEmpty ? nil : URL(string: e.url)
        ek.isAllDay = e.allDay
        ek.startDate = e.allDay ? cal.startOfDay(for: e.start) : e.start
        ek.endDate = e.allDay ? cal.startOfDay(for: e.end) : e.end
        if let c = ekCalendar(e.calID), c.allowsContentModifications, c.calendarIdentifier != ek.calendar?.calendarIdentifier { ek.calendar = c }
    }

    /// Only touched when the user picked a different repeat; an existing complex rule stays as it is otherwise.
    private func applyRule(_ ek: EKEvent, _ r: MLRepeat, original: MLRepeat) {
        guard r != original else { return }
        ek.recurrenceRules?.forEach { ek.removeRecurrenceRule($0) }
        let f: EKRecurrenceFrequency?
        switch r { case .none: f = nil; case .daily: f = .daily; case .weekly: f = .weekly; case .monthly: f = .monthly; case .yearly: f = .yearly }
        if let f { ek.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: f, interval: 1, end: nil)) }
    }

    func create(_ e: MLEvent) -> MLEvent? {
        guard let c = ekCalendar(e.calID), c.allowsContentModifications else {
            fail(NSError(domain: "MLCalendar", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Dieser Kalender ist schreibgeschützt.", "This calendar is read-only.")])); return nil
        }
        let ek = EKEvent(eventStore: store)
        ek.calendar = c
        fill(ek, from: e); applyRule(ek, e.repeatRule, original: .none)
        do { try store.save(ek, span: .thisEvent, commit: true) } catch { fail(error); return nil }
        let made = register(ek, fallback: e.start)
        NotificationCenter.default.post(name: .mlStoreChanged, object: nil)
        return made
    }

    func update(_ e: MLEvent, series: Bool) -> MLEvent? {
        guard let ek = eks[e.id], let old = cache[e.id] else { return nil }
        fill(ek, from: e); applyRule(ek, e.repeatRule, original: old.repeatRule)
        do { try store.save(ek, span: series ? .futureEvents : .thisEvent, commit: true) } catch { store.reset(); fail(error); reload(); NotificationCenter.default.post(name: .mlStoreChanged, object: nil); return nil }
        cache[e.id] = nil; eks[e.id] = nil
        let made = register(ek, fallback: e.start)
        NotificationCenter.default.post(name: .mlStoreChanged, object: nil)
        return made
    }

    @discardableResult
    func delete(_ id: UUID, series: Bool) -> Bool {
        guard let ek = eks[id] else { return false }
        do { try store.remove(ek, span: series ? .futureEvents : .thisEvent, commit: true) } catch { fail(error); return false }
        cache[id] = nil; eks[id] = nil
        NotificationCenter.default.post(name: .mlStoreChanged, object: nil)
        return true
    }

    func search(_ q: String, now: Date) -> [MLOcc] {
        guard isActive else { return [] }
        let all = occurrences(from: now.addingTimeInterval(-86400 * 366), to: now.addingTimeInterval(86400 * 366))
        let hits = all.filter { o in [o.ev.title, o.ev.location, o.ev.notes].contains { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }
        return Array(hits.filter { $0.end >= now }.prefix(40)) + Array(hits.filter { $0.end < now }.suffix(10))
    }
}
