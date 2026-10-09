import XCTest
@testable import RetroMac

/// The theme on chosen Spaces only: where it shows.
final class ThemeSpacesTests: XCTestCase {
    func testEverySpaceUnlessChosen() {
        XCTAssertTrue(ThemeSpaces.showsTheme(chosenOnly: false, chosen: [], current: "A"))
        XCTAssertTrue(ThemeSpaces.showsTheme(chosenOnly: false, chosen: ["B"], current: "A"), "the list counts only when the setting is on")
    }

    func testOnlyTheChosenOnes() {
        XCTAssertTrue(ThemeSpaces.showsTheme(chosenOnly: true, chosen: ["A", "B"], current: "B"))
        XCTAssertFalse(ThemeSpaces.showsTheme(chosenOnly: true, chosen: ["A"], current: "B"))
        XCTAssertTrue(ThemeSpaces.showsTheme(chosenOnly: true, chosen: [""], current: ""), "a first desktop without a uuid is a Space too")
    }

    func testNoAnswerKeepsTheTheme() {
        // The window server named no Space: better the theme everywhere than nowhere.
        XCTAssertTrue(ThemeSpaces.showsTheme(chosenOnly: true, chosen: ["A"], current: nil))
    }
}
