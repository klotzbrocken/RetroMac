import AppKit

// Mountain Lion Calendar: data model, recurrence, quick-entry parser, persistence.
// Local only (UM-02, DAT-05). EventKit / iCalendar are SOLL items and not part of this file.

// MARK: - Preferences

enum MLPrefs {
    private static let d = UserDefaults.standard
    private static func int(_ k: String, _ def: Int) -> Int { d.object(forKey: "mlcal." + k) as? Int ?? def }

    static var weekStart: Int { get { int("weekStart", 2) } set { d.set(newValue, forKey: "mlcal.weekStart"); apply() } }   // 1 = Sunday … 7 = Saturday
    static var hour24: Bool { get { d.object(forKey: "mlcal.hour24") as? Bool ?? true } set { d.set(newValue, forKey: "mlcal.hour24"); apply() } }
    static var dayStart: Int { get { int("dayStart", 8) } set { d.set(newValue, forKey: "mlcal.dayStart"); apply() } }
    static var dayEnd: Int { get { int("dayEnd", 18) } set { d.set(newValue, forKey: "mlcal.dayEnd"); apply() } }
    static var timeZoneID: String { get { d.string(forKey: "mlcal.tz") ?? "" } set { d.set(newValue, forKey: "mlcal.tz"); apply() } }
    static var lang: String { get { d.string(forKey: "mlcal.lang") ?? "auto" } set { d.set(newValue, forKey: "mlcal.lang"); apply() } }

    static var isDE: Bool {
        switch lang {
        case "de": return true
        case "en": return false
        default: return (Locale.preferredLanguages.first ?? "de").hasPrefix("de")
        }
    }

    /// Rebuilt by `apply()`; every date calculation in the calendar goes through this one value.
    private(set) static var calendar: Calendar = build()
    private static var formatters: [String: DateFormatter] = [:]

    private static func build() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = weekStart
        c.locale = Locale(identifier: isDE ? "de_DE" : "en_US")
        if let z = TimeZone(identifier: timeZoneID), !timeZoneID.isEmpty { c.timeZone = z }
        return c
    }

    static func apply() {
        calendar = build()
        formatters = [:]
        NotificationCenter.default.post(name: .mlPrefsChanged, object: nil)
    }

    /// Locale-correct formatting from a skeleton ("yMMMM" → "Juli 2012" / "July 2012").
    static func fmt(_ date: Date, _ template: String) -> String {
        let f: DateFormatter
        if let c = formatters[template] { f = c } else {
            f = DateFormatter()
            f.calendar = calendar
            f.locale = calendar.locale
            f.timeZone = calendar.timeZone
            f.setLocalizedDateFormatFromTemplate(template)
            formatters[template] = f
        }
        return f.string(from: date)
    }

    /// "14:30" or "2:30 PM" per setting.
    static func time(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0, m = c.minute ?? 0
        if hour24 { return String(format: "%02d:%02d", h, m) }
        let h12 = h % 12 == 0 ? 12 : h % 12
        return m == 0 ? "\(h12) \(h < 12 ? "AM" : "PM")" : String(format: "%d:%02d %@", h12, m, h < 12 ? "AM" : "PM")
    }
}

extension Notification.Name {
    static let mlPrefsChanged = Notification.Name("MLCalendarPrefsChanged")
    static let mlStoreChanged = Notification.Name("MLCalendarStoreChanged")
}

func L(_ de: String, _ en: String) -> String { MLPrefs.isDE ? de : en }

// MARK: - Model

enum MLRepeat: String, Codable, CaseIterable {
    case none, daily, weekly, monthly, yearly
    var title: String {
        switch self {
        case .none: return L("Nie", "None")
        case .daily: return L("Täglich", "Every Day")
        case .weekly: return L("Wöchentlich", "Every Week")
        case .monthly: return L("Monatlich", "Every Month")
        case .yearly: return L("Jährlich", "Every Year")
        }
    }
    var component: Calendar.Component? {
        switch self { case .none: return nil; case .daily: return .day; case .weekly: return .weekOfYear; case .monthly: return .month; case .yearly: return .year }
    }
    /// Rough length of one step in days, only for skipping ahead.
    var days: Double { switch self { case .none: return 1; case .daily: return 1; case .weekly: return 7; case .monthly: return 28; case .yearly: return 365 } }
}

struct MLCal: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var colorHex: UInt32
    var visible = true
    var readOnly = false
    /// Account name for system calendars ("Google", "iCloud"); nil for local ones.
    var group: String? = nil
    var color: NSColor { NSColor(srgbRed: CGFloat((colorHex >> 16) & 255) / 255, green: CGFloat((colorHex >> 8) & 255) / 255, blue: CGFloat(colorHex & 255) / 255, alpha: 1) }
}

/// Ganztag: `start`/`end` are local midnights of the first and the LAST day (inclusive).
/// Timed: `end` is exclusive. (DAT-02 – ponytail: an all-day event is stored as instants, so changing the
/// time-zone setting after the fact can shift it; upgrade path is storing y-m-d components.)
struct MLEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    var calID: UUID
    var title = ""
    var location = ""
    var start: Date
    var end: Date
    var allDay = false
    var notes = ""
    var url = ""
    var repeatRule: MLRepeat = .none
    /// Occurrence starts (Int epoch seconds) removed from the series.
    var exceptions: [Int] = []
}

struct MLOcc: Identifiable, Equatable {
    var ev: MLEvent
    /// Concrete interval; end exclusive (all-day: start of the day after the last day).
    var start: Date
    var end: Date
    var id: String { "\(ev.id)|\(Int(start.timeIntervalSince1970))" }
    var isRecurring: Bool { ev.repeatRule != .none }
    var title: String { ev.title.isEmpty ? L("Neuer Termin", "New Event") : ev.title }
}

struct MLState: Codable {
    var version = 1
    var calendars: [MLCal] = []
    var events: [MLEvent] = []
}

// MARK: - Store

final class MLStore {
    static let shared = MLStore()

    private(set) var state = MLState()
    let undoManager = UndoManager()
    /// Set when the file on disk could not be read; the window shows it once.
    var loadError: String?
    private let url: URL

    init(url: URL? = nil) {
        if let url { self.url = url } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RetroMac")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.url = dir.appendingPathComponent("MLCalendar.json")
        }
        load()
    }

    var calendars: [MLCal] { state.calendars }
    func calendar(_ id: UUID) -> MLCal? { state.calendars.first { $0.id == id } ?? MLSystem.shared.calendars.first { $0.id == id } }

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path) else { seed(); return }
        do {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
            state = try dec.decode(MLState.self, from: Data(contentsOf: url))
        } catch {
            // Never overwrite a damaged file: move it aside and start clean.
            let aside = url.deletingLastPathComponent().appendingPathComponent("MLCalendar.damaged-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            loadError = L("Die Kalenderdaten konnten nicht gelesen werden. Die Datei wurde gesichert als „\(aside.lastPathComponent)“, es wird mit leeren Kalendern gestartet.",
                          "The calendar data could not be read. The file was kept as “\(aside.lastPathComponent)”; starting with empty calendars.")
            seed()
        }
    }

    /// DAT-05: first start is an empty calendar set, no sample events.
    private func seed() {
        state = MLState(calendars: [
            MLCal(name: L("Privat", "Home"), colorHex: 0x2F6FD6),
            MLCal(name: L("Arbeit", "Work"), colorHex: 0x4DA83B),
            MLCal(name: L("Geburtstage", "Birthdays"), colorHex: 0xD9432B),
        ])
        save()
    }

    @discardableResult
    func save() -> Bool {
        do {
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
            try enc.encode(state).write(to: url, options: .atomic)
            return true
        } catch {
            loadError = L("Die Änderung konnte nicht gespeichert werden: \(error.localizedDescription)", "The change could not be saved: \(error.localizedDescription)")
            return false
        }
    }

    /// Every edit goes through here: whole-state snapshot undo, atomic save, one notification.
    func mutate(_ name: String, _ f: (inout MLState) -> Void) {
        let before = state
        var s = state; f(&s)
        guard s.calendars != before.calendars || s.events != before.events else { return }
        restore(s, before: before, name: name)
    }

    private func restore(_ new: MLState, before: MLState, name: String) {
        state = new
        // Without a running event loop (tests, scripts) no group is open; one group per edit keeps undo granular.
        let wrap = !undoManager.isUndoing && !undoManager.isRedoing
        if wrap { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { me in me.restore(before, before: new, name: name) }
        undoManager.setActionName(name)
        if wrap { undoManager.endUndoGrouping() }
        save()
        NotificationCenter.default.post(name: .mlStoreChanged, object: nil)
    }

    // MARK: Calendars
    func addCalendar(name: String, colorHex: UInt32) -> UUID {
        let c = MLCal(name: name, colorHex: colorHex)
        mutate(L("Neuer Kalender", "New Calendar")) { $0.calendars.append(c) }
        return c.id
    }
    func updateCalendar(_ c: MLCal) {
        mutate(L("Kalender ändern", "Edit Calendar")) { s in if let i = s.calendars.firstIndex(where: { $0.id == c.id }) { s.calendars[i] = c } }
    }
    func deleteCalendar(_ id: UUID) {
        mutate(L("Kalender löschen", "Delete Calendar")) { s in s.calendars.removeAll { $0.id == id }; s.events.removeAll { $0.calID == id } }
    }

    // MARK: Events
    func event(_ id: UUID) -> MLEvent? { state.events.first { $0.id == id } }
    var allCalendars: [MLCal] { state.calendars + MLSystem.shared.calendars }

    // Events of system calendars (EventKit) are routed to MLSystem; they are not part of `state` and not undoable here.
    @discardableResult
    func add(_ e: MLEvent, name: String? = nil) -> MLEvent {
        if MLSystem.shared.isSystem(calendar: e.calID) { return MLSystem.shared.create(e) ?? e }
        mutate(name ?? L("Neuer Termin", "New Event")) { $0.events.append(e) }
        return e
    }

    /// `series`: for repeating system events, change this and all following occurrences instead of just this one.
    @discardableResult
    func update(_ e: MLEvent, name: String? = nil, series: Bool = false) -> MLEvent {
        let sysNow = MLSystem.shared.owns(e.id), sysTarget = MLSystem.shared.isSystem(calendar: e.calID)
        switch (sysNow, sysTarget) {
        case (true, true): return MLSystem.shared.update(e, series: series) ?? e
        case (true, false):                                   // moved from a system calendar to a local one
            guard MLSystem.shared.delete(e.id, series: false) else { return e }
            var n = e; n.id = UUID(); n.repeatRule = .none; n.exceptions = []
            mutate(name ?? L("Termin ändern", "Edit Event")) { $0.events.append(n) }
            return n
        case (false, true):                                   // moved from a local calendar to a system one
            guard let made = MLSystem.shared.create(e) else { return e }
            mutate(name ?? L("Termin ändern", "Edit Event")) { $0.events.removeAll { $0.id == e.id } }
            return made
        default:
            mutate(name ?? L("Termin ändern", "Edit Event")) { s in if let i = s.events.firstIndex(where: { $0.id == e.id }) { s.events[i] = e } }
            return e
        }
    }

    func delete(_ id: UUID, series: Bool = false) {
        if MLSystem.shared.owns(id) { MLSystem.shared.delete(id, series: series); return }
        mutate(L("Termin löschen", "Delete Event")) { $0.events.removeAll { $0.id == id } }
    }
    func deleteOccurrence(_ o: MLOcc) {
        if MLSystem.shared.owns(o.ev.id) { MLSystem.shared.delete(o.ev.id, series: false); return }
        var e = o.ev; e.exceptions.append(Int(o.start.timeIntervalSince1970)); update(e, name: L("Termin löschen", "Delete Event"))
    }

    /// Terminreihe: nur dieses Vorkommen geändert → eigenständiger Termin + Ausnahme in der Serie.
    @discardableResult
    func detach(_ o: MLOcc, as new: MLEvent) -> MLEvent? {
        if MLSystem.shared.owns(o.ev.id) { var n = new; n.id = o.ev.id; return MLSystem.shared.update(n, series: false) }
        var n = new; n.id = UUID(); n.repeatRule = .none; n.exceptions = []
        mutate(L("Termin ändern", "Edit Event")) { s in
            guard let i = s.events.firstIndex(where: { $0.id == o.ev.id }) else { return }
            s.events[i].exceptions.append(Int(o.start.timeIntervalSince1970))
            s.events.append(n)
        }
        return n
    }

    func duplicate(_ id: UUID) -> UUID? {
        guard var e = event(id) ?? MLSystem.shared.event(id) else { return nil }
        e.id = UUID(); e.exceptions = []; e.repeatRule = MLSystem.shared.owns(id) ? .none : e.repeatRule
        return add(e, name: L("Termin duplizieren", "Duplicate Event")).id
    }

    // MARK: Expansion

    func occurrences(from lo: Date, to hi: Date) -> [MLOcc] {
        let cal = MLPrefs.calendar
        let visible = Set(state.calendars.filter { $0.visible }.map { $0.id })
        var out: [MLOcc] = []
        for e in state.events where visible.contains(e.calID) {
            Self.expand(e, from: lo, to: hi, cal: cal, into: &out)
        }
        out += MLSystem.shared.occurrences(from: lo, to: hi)
        out.sort { ($0.start, $0.end, $0.ev.title) < ($1.start, $1.end, $1.ev.title) }
        return out
    }

    /// The concrete [start, end) of the stored event (all-day: whole days, end exclusive).
    static func interval(_ e: MLEvent, cal: Calendar) -> (Date, Date) {
        guard e.allDay else { return (e.start, max(e.end, e.start)) }
        let s = cal.startOfDay(for: e.start)
        let last = max(cal.startOfDay(for: e.end), s)
        return (s, cal.date(byAdding: .day, value: 1, to: last)!)
    }

    static func expand(_ e: MLEvent, from lo: Date, to hi: Date, cal: Calendar, into out: inout [MLOcc]) {
        let (s0, e0) = interval(e, cal: cal)
        guard let comp = e.repeatRule.component else {
            if s0 < hi && (e0 > lo || (e0 == s0 && s0 >= lo)) { out.append(MLOcc(ev: e, start: s0, end: e0)) }
            return
        }
        let delta = cal.dateComponents([.day, .hour, .minute, .second], from: s0, to: e0)
        let spanDays = e0.timeIntervalSince(s0) / 86400
        var n = 0
        if s0 < lo {
            let approx = cal.dateComponents([comp], from: s0, to: lo).value(for: comp) ?? 0
            n = max(0, approx - Int(spanDays / e.repeatRule.days) - 2)
        }
        let cap = n + 4000
        let skip = Set(e.exceptions)
        // Monthly/yearly are always computed from the ORIGINAL start, so a 31st clamps to the month's last day
        // (Feb 28/29) and returns to the 31st afterwards (DAT-03).
        while n < cap, let s = cal.date(byAdding: comp, value: n, to: s0), s < hi {
            n += 1
            guard let en = cal.date(byAdding: delta, to: s) else { continue }
            if en > lo || (en == s && s >= lo), !skip.contains(Int(s.timeIntervalSince1970)) {
                out.append(MLOcc(ev: e, start: s, end: en))
            }
        }
    }

    /// Title, place and notes (QUA-06). Returns the first upcoming-or-last occurrence per event.
    func search(_ q: String) -> [MLOcc] {
        let needle = q.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        let visible = Set(state.calendars.filter { $0.visible }.map { $0.id })
        let cal = MLPrefs.calendar
        let now = Date()
        var out: [MLOcc] = []
        for e in state.events where visible.contains(e.calID) {
            let hay = [e.title, e.location, e.notes]
            guard hay.contains(where: { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) else { continue }
            var occs: [MLOcc] = []
            Self.expand(e, from: .distantPast, to: now.addingTimeInterval(86400 * 366 * 2), cal: cal, into: &occs)
            if let o = occs.first(where: { $0.end >= now }) ?? occs.last { out.append(o) }
        }
        out += MLSystem.shared.search(needle, now: now)
        return out.sorted { $0.start < $1.start }
    }
}

// MARK: - Quick entry (FUN-10)

struct MLQuick {
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var hasDate: Bool
    var hasTime: Bool
}

enum MLQuickParser {
    private static let weekdays: [(String, Int)] = [
        ("sonntag", 1), ("montag", 2), ("dienstag", 3), ("mittwoch", 4), ("donnerstag", 5), ("freitag", 6), ("samstag", 7),
        ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4), ("thursday", 5), ("friday", 6), ("saturday", 7),
    ]

    /// Understands: dd.mm.[yy[yy]], yyyy-mm-dd, heute/today, morgen/tomorrow, übermorgen, Wochentag (next one),
    /// 14:30, 14 Uhr, 3pm, "um/at/am/on". Anything else stays in the title. Without a date → today;
    /// without a time → all day. The caller shows the interpretation before saving.
    static func parse(_ input: String, now: Date = Date(), cal: Calendar = MLPrefs.calendar) -> MLQuick {
        var s = " " + input + " "
        var day: Date?
        var minutes: Int?
        let today = cal.startOfDay(for: now)

        /// Replaces the first match with a marker when `f` accepts it (so "31.02." stays in the title).
        func take(_ pattern: String, _ f: ([String]) -> Bool) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return }
            let g = (0..<m.numberOfRanges).map { i -> String in
                guard let r = Range(m.range(at: i), in: s) else { return "" }; return String(s[r])
            }
            if f(g) { s.replaceSubrange(Range(m.range, in: s)!, with: " \u{1} ") }
        }
        func ymd(_ y: Int, _ m: Int, _ d: Int) -> Date? {
            guard let dt = cal.date(from: DateComponents(year: y, month: m, day: d)),
                  cal.component(.day, from: dt) == d, cal.component(.month, from: dt) == m else { return nil }   // rejects 31.02.
            return dt
        }

        take(#"(?<=\s)(\d{4})-(\d{1,2})-(\d{1,2})(?=\s)"#) { g in day = ymd(Int(g[1])!, Int(g[2])!, Int(g[3])!); return day != nil }
        if day == nil {
            take(#"(?<=\s)(\d{1,2})\.\s?(\d{1,2})\.(\d{2,4})?(?=[\s,])"#) { g in
                var y = g[3].isEmpty ? cal.component(.year, from: today) : Int(g[3])!
                if y < 100 { y += 2000 }
                guard var d = ymd(y, Int(g[2])!, Int(g[1])!) else { return false }
                if g[3].isEmpty, d < today { d = ymd(y + 1, Int(g[2])!, Int(g[1])!) ?? d }
                day = d; return true
            }
        }
        if day == nil { take(#"(?<=\s)(übermorgen|overmorrow)(?=[\s,])"#) { _ in day = cal.date(byAdding: .day, value: 2, to: today); return true } }
        if day == nil { take(#"(?<=\s)(morgen|tomorrow)(?=[\s,])"#) { _ in day = cal.date(byAdding: .day, value: 1, to: today); return true } }
        if day == nil { take(#"(?<=\s)(heute|today)(?=[\s,])"#) { _ in day = today; return true } }
        if day == nil {
            for (name, wd) in weekdays {
                take("(?<=\\s)\(name)(?=[\\s,])") { _ in
                    var d = today
                    repeat { d = cal.date(byAdding: .day, value: 1, to: d)! } while cal.component(.weekday, from: d) != wd
                    day = d; return true
                }
                if day != nil { break }
            }
        }
        take(#"(?<=\s)(\d{1,2}):(\d{2})\s?(am|pm)?(?=[\s,])"#) { g in
            var h = Int(g[1])!; let m = Int(g[2])!
            if g[3].lowercased() == "pm", h < 12 { h += 12 }; if g[3].lowercased() == "am", h == 12 { h = 0 }
            guard h < 24, m < 60 else { return false }
            minutes = h * 60 + m; return true
        }
        if minutes == nil {
            take(#"(?<=\s)(\d{1,2})\s?(uhr|h|am|pm)(?=[\s,])"#) { g in
                var h = Int(g[1])!
                let u = g[2].lowercased()
                if u == "pm", h < 12 { h += 12 }; if u == "am", h == 12 { h = 0 }
                guard h < 24 else { return false }
                minutes = h * 60; return true
            }
        }
        // Connecting words in front of a recognised date/time ("am 31.12.", "at 3pm"), then the markers.
        s = s.replacingOccurrences(of: #"(?i)(?<=\s)(um|at|am|on)\s+\x{01}"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\u{1}", with: " ")
        let title = s.split(separator: " ").joined(separator: " ")
        let base = day ?? today
        if let mi = minutes {
            let st = cal.date(byAdding: .minute, value: mi, to: base)!
            return MLQuick(title: title, start: st, end: cal.date(byAdding: .hour, value: 1, to: st)!, allDay: false, hasDate: day != nil, hasTime: true)
        }
        return MLQuick(title: title, start: base, end: base, allDay: true, hasDate: day != nil, hasTime: false)
    }
}
