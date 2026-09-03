import XCTest
@testable import RetroMac

/// The Windows 95/98/Me tray, which had three different-sized spaces in it because three
/// different expressions produced them: 5 points before the icon, 3 between the icon and the
/// speaker, and 11 before the time. The pair of icons read as one smudge and the clock sat in a
/// hole. These tests hold the rhythm.
final class ClassicTrayLayoutTests: XCTestCase {

    func testEveryGapIsTheSameGap() {
        for iconSize in [CGFloat(14), 16, 18, 22] {
            for text in [CGFloat(30), 44, 61.5] {
                for speaker in [true, false] {
                    let l = ClassicTrayLayout(iconSize: iconSize, hasSpeaker: speaker,
                                              clockTextWidth: text)
                    for g in l.gaps {
                        XCTAssertEqual(g, ClassicTrayLayout.gap, accuracy: 0.001,
                                       "icon \(iconSize), text \(text), speaker \(speaker): \(l.gaps)")
                    }
                    XCTAssertEqual(l.gaps.count, speaker ? 3 : 2)
                }
            }
        }
    }

    /// The clock is drawn at `clockFrame.maxX - textWidth - 8`, so the layout has to reserve
    /// exactly that. Reading the XP path's 10 instead is how the last gap became eleven.
    func testTheTimeLandsWhereTheClockDrawsIt() {
        let l = ClassicTrayLayout(iconSize: 16, hasSpeaker: true, clockTextWidth: 44)
        XCTAssertEqual(l.width - l.clockTextX - 44, ClassicTrayLayout.clockRightMargin)
        XCTAssertEqual(ClassicTrayLayout.clockRightMargin, 8)
    }

    /// Nothing may overlap, at any size the dock can be set to.
    func testTheIconsNeverCollide() {
        for iconSize in stride(from: CGFloat(14), through: 40, by: 2) {
            let l = ClassicTrayLayout(iconSize: iconSize, hasSpeaker: true, clockTextWidth: 44)
            XCTAssertGreaterThan(l.speakerX, l.iconX + iconSize)
            XCTAssertGreaterThan(l.clockTextX, l.speakerX + iconSize)
            XCTAssertLessThan(l.clockTextX + 44, l.width)
        }
    }
}
