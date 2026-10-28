import XCTest
@testable import RetroMac

final class StartMenuSearchTests: XCTestCase {

    func testSums() {
        XCTAssertEqual(StartMenuSearch.calculate("12*3"), 36)
        XCTAssertEqual(StartMenuSearch.calculate("2 + 3 * 4"), 14)
        XCTAssertEqual(StartMenuSearch.calculate("(2+3)*4"), 20)
        XCTAssertEqual(StartMenuSearch.calculate("7,5/2"), 3.75)
        XCTAssertEqual(StartMenuSearch.calculate("-3+5"), 2)
        XCTAssertEqual(StartMenuSearch.calculate("6×7"), 42)
        // Not sums: a lone number, words, half a sum, a division by zero.
        XCTAssertNil(StartMenuSearch.calculate("42"))
        XCTAssertNil(StartMenuSearch.calculate("safari"))
        XCTAssertNil(StartMenuSearch.calculate("1+"))
        XCTAssertNil(StartMenuSearch.calculate("(1+2"))
        XCTAssertNil(StartMenuSearch.calculate("1/0"))
        XCTAssertNil(StartMenuSearch.calculate("FUNCTION('x','y')"))
        XCTAssertEqual(StartMenuSearch.format(36), "36")
    }

    func testWebAddresses() {
        XCTAssertEqual(StartMenuSearch.webAddress("github.com")?.absoluteString, "https://github.com")
        XCTAssertEqual(StartMenuSearch.webAddress("https://example.com/a")?.absoluteString, "https://example.com/a")
        XCTAssertEqual(StartMenuSearch.webAddress("localhost:3000")?.absoluteString, "http://localhost:3000")
        XCTAssertEqual(StartMenuSearch.webAddress("myretromac.app/retro-family")?.absoluteString, "https://myretromac.app/retro-family")
        XCTAssertNil(StartMenuSearch.webAddress("safari"))
        XCTAssertNil(StartMenuSearch.webAddress("3.14"))
        XCTAssertNil(StartMenuSearch.webAddress("hello world.com"))
        XCTAssertNil(StartMenuSearch.webAddress("file.txt2"))
    }

    func testRankingPrefersStartsThenWordsThenContains() {
        let names = ["Microsoft Word", "Word Counter", "Swordfish", "Safari", "Écran"]
        XCTAssertEqual(StartMenuSearch.rank(names, query: "word"), [1, 0, 2])
        XCTAssertEqual(StartMenuSearch.rank(names, query: "ecr"), [4])
        XCTAssertEqual(StartMenuSearch.rank(names, query: " "), [])
    }

    func testKeysAreReadThroughTheLayout() {
        // The A key types a and, with Shift, A on every Latin layout (QWERTY, QWERTZ, Dvorak).
        XCTAssertEqual(StartMenuTyping.character(0, shift: false), "a")
        XCTAssertEqual(StartMenuTyping.character(0, shift: true), "A")
        XCTAssertEqual(StartMenuTyping.character(49, shift: false), " ")
    }

    func testCommandTapIsShort() {
        XCTAssertTrue(StartKeyTap.isTap(downAt: 10, upAt: 10.2))
        XCTAssertFalse(StartKeyTap.isTap(downAt: 10, upAt: 10.6))
    }
}
