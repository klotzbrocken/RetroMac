import XCTest
@testable import RetroMac

final class CalendarDockIconTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testMonthIsShortUpperCaseWithoutDot() {
        XCTAssertEqual(CalendarDockIcon.monthText(date(2013, 1, 19), locale: Locale(identifier: "en_US")), "JAN")
        XCTAssertEqual(CalendarDockIcon.monthText(date(2013, 10, 22), locale: Locale(identifier: "de_DE")), "OKT")
    }

    func testDayKeyTurnsOverAtMidnight() {
        XCTAssertEqual(CalendarDockIcon.dayKey(date(2026, 11, 25, 0)), CalendarDockIcon.dayKey(date(2026, 11, 25, 23)))
        XCTAssertNotEqual(CalendarDockIcon.dayKey(date(2026, 11, 25, 23)), CalendarDockIcon.dayKey(date(2026, 11, 26, 0)))
    }

    func testRendersOnTheMavericksBlank() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes/MacOSX-Mavericks.retromactheme/icons/calendar-empty.png")
        let blank = try XCTUnwrap(NSImage(contentsOf: url))
        let img = CalendarDockIcon.render(blank: blank, date: date(2026, 7, 17), size: 256)
        XCTAssertEqual(img.size, NSSize(width: 256, height: 256))
        if let out = ProcessInfo.processInfo.environment["RETROMAC_CALENDAR_PREVIEW"],
           let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: out))
        }
    }
}
