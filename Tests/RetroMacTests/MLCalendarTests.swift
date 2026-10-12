import XCTest
import AppKit
@testable import RetroMac

/// Date logic (DAT-02/03, FUN-08, FUN-10) and a snapshot renderer for the visual comparison (§10.1).
/// Snapshots go to $ML_SNAP_DIR (default /tmp/mlsnap); they are inspected, not asserted.
final class MLCalendarTests: XCTestCase {
    private var cal: Calendar!
    private var store: MLStore!

    override func setUp() {
        MLPrefs.lang = "en"; MLPrefs.weekStart = 1; MLPrefs.hour24 = true; MLPrefs.timeZoneID = "Europe/Berlin"
        cal = MLPrefs.calendar
        store = MLStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("ml-\(UUID()).json"))
    }

    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: mi))!
    }

    func testMonthlyOn31stClampsAndReturns() {
        let e = MLEvent(calID: store.calendars[0].id, title: "x", start: d(2024, 1, 31, 10), end: d(2024, 1, 31, 11), repeatRule: .monthly)
        var out: [MLOcc] = []
        MLStore.expand(e, from: d(2024, 1, 1), to: d(2024, 5, 1), cal: cal, into: &out)
        XCTAssertEqual(out.map { cal.component(.day, from: $0.start) }, [31, 29, 31, 30])      // Feb 29 (leap year), Mar 31, Apr 30
    }

    func testDailyAcrossDSTKeepsWallClock() {
        let e = MLEvent(calID: store.calendars[0].id, title: "x", start: d(2026, 3, 27, 9), end: d(2026, 3, 27, 10), repeatRule: .daily)
        var out: [MLOcc] = []
        MLStore.expand(e, from: d(2026, 3, 27), to: d(2026, 4, 2), cal: cal, into: &out)
        XCTAssertEqual(out.count, 6)
        XCTAssertTrue(out.allSatisfy { cal.component(.hour, from: $0.start) == 9 })
    }

    func testAllDayIsWholeDaysAndExceptionRemovesOne() {
        var e = MLEvent(calID: store.calendars[0].id, title: "x", start: d(2026, 10, 12), end: d(2026, 10, 13), allDay: true, repeatRule: .weekly)
        var out: [MLOcc] = []
        MLStore.expand(e, from: d(2026, 10, 1), to: d(2026, 11, 1), cal: cal, into: &out)
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out[0].end.timeIntervalSince(out[0].start), 2 * 86400, accuracy: 3700)   // 12th and 13th
        e.exceptions = [Int(out[1].start.timeIntervalSince1970)]
        out = []; MLStore.expand(e, from: d(2026, 10, 1), to: d(2026, 11, 1), cal: cal, into: &out)
        XCTAssertEqual(out.count, 2)
    }

    func testUndoRestoresAndPersists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ml-\(UUID()).json")
        let s = MLStore(url: url)
        s.undoManager.groupsByEvent = false
        s.add(MLEvent(calID: s.calendars[0].id, title: "Zahnärztin Müller", start: d(2026, 10, 12, 9), end: d(2026, 10, 12, 10)))
        XCTAssertEqual(MLStore(url: url).state.events.first?.title, "Zahnärztin Müller")      // survives a restart
        s.undoManager.undo()
        XCTAssertTrue(s.state.events.isEmpty)
        s.undoManager.redo()
        XCTAssertEqual(s.state.events.count, 1)
    }

    func testQuickParser() {
        let now = d(2026, 10, 12, 8)          // Monday
        var q = MLQuickParser.parse("Zahnarzt morgen 15:30", now: now, cal: cal)
        XCTAssertEqual(q.title, "Zahnarzt"); XCTAssertEqual(q.start, d(2026, 10, 13, 15, 30)); XCTAssertFalse(q.allDay)
        q = MLQuickParser.parse("Lunch am 31.12. um 12 Uhr", now: now, cal: cal)
        XCTAssertEqual(q.title, "Lunch"); XCTAssertEqual(q.start, d(2026, 12, 31, 12))
        q = MLQuickParser.parse("Urlaub", now: now, cal: cal)
        XCTAssertTrue(q.allDay); XCTAssertFalse(q.hasDate)
        q = MLQuickParser.parse("Meeting 31.02. 10:00", now: now, cal: cal)
        XCTAssertTrue(q.title.contains("31.02."))                                              // invalid date is not guessed
    }

    // MARK: snapshots

    @MainActor func testSnapshots() throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ML_SNAP_DIR"] ?? "/tmp/mlsnap")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ctl = MLController.shared
        ctl.store = store
        let now = d(2012, 7, 22, 12)
        ctl.now = { now }
        let home = store.calendars[0].id, work = store.calendars[1].id
        store.add(MLEvent(calID: home, title: "New Event", start: d(2012, 7, 22), end: d(2012, 7, 22), allDay: true))
        store.add(MLEvent(calID: work, title: "Design review", location: "Room 4", start: d(2012, 7, 24, 10), end: d(2012, 7, 24, 11, 30)))
        store.add(MLEvent(calID: home, title: "Dinner", start: d(2012, 7, 24, 10, 30), end: d(2012, 7, 24, 12)))
        store.add(MLEvent(calID: work, title: "Conference", start: d(2012, 7, 25), end: d(2012, 7, 27), allDay: true))
        store.add(MLEvent(calID: home, title: "Run", start: d(2012, 7, 23, 7), end: d(2012, 7, 23, 8), repeatRule: .daily))
        ctl.defaultCalID = home
        ctl.date = d(2012, 7, 22)
        let w = ctl.makeWindow()
        for (name, mode) in [("month", MLMode.month), ("week", .week), ("day", .day), ("year", .year)] {
            ctl.mode = mode
            ctl.main.scrollToDayStart()
            w.setContentSize(NSSize(width: 1086, height: 735))
            w.contentView!.layoutSubtreeIfNeeded()
            let v = w.contentView!
            let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
            v.cacheDisplay(in: v.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("ml-\(name).png"))
        }
    }

    @MainActor func testPanelSnapshots() throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ML_SNAP_DIR"] ?? "/tmp/mlsnap")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ctl = MLController.shared
        ctl.store = store
        let ev = MLEvent(calID: store.calendars[0].id, title: "New Event", start: d(2012, 7, 22), end: d(2012, 7, 22), allDay: true)
        let occ = MLOcc(ev: ev, start: d(2012, 7, 22), end: d(2012, 7, 23))
        let tmp = MLEvent(calID: store.calendars[0].id, title: "Zahnarzt", location: "Praxis Dr. Müller", start: d(2012, 7, 22, 9), end: d(2012, 7, 22, 10), repeatRule: .weekly)
        for (name, vc) in [("editor", MLEditorVC(ctl, occ: MLOcc(ev: tmp, start: tmp.start, end: tmp.end), isNew: false) as NSViewController), ("quick", MLQuickVC(ctl))] {
            let v = vc.view
            v.appearance = NSAppearance(named: .aqua)
            v.layoutSubtreeIfNeeded()
            let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
            v.cacheDisplay(in: v.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("ml-\(name).png"))
        }
        let dd = MLCalDropdown(cal: cal, selected: d(2012, 7, 12))
        let drep = dd.bitmapImageRepForCachingDisplay(in: dd.bounds)!
        dd.cacheDisplay(in: dd.bounds, to: drep)
        try drep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("ml-dropdown.png"))
        let prefs = MLPrefsController(); prefs.show()
        let pv = prefs.window!.contentView!
        for i in 0..<3 {
            prefs.select(i)
            let rep = pv.bitmapImageRepForCachingDisplay(in: pv.bounds)!
            pv.cacheDisplay(in: pv.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("ml-prefs\(i).png"))
        }
    }
}
