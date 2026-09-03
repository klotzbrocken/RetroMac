import Foundation

/// The Windows 95, 98 and Me system tray, laid out from a single gap.
///
/// The three spaces in there came from three unrelated expressions and worked out to 5, 3 and 11
/// points: the speaker was glued to the icon beside it while the clock sat in a hole. They are
/// derived from one number now, so they cannot drift apart again.
///
/// Windows XP is deliberately not this shape — it carries the hidden-icons chevron and its
/// speaker artwork is smaller in its frame — and Windows 7 draws its own glyphs in
/// `drawWin7Systray`. Both keep their own arithmetic.
struct ClassicTrayLayout {

    /// The rhythm. Every space in the tray is this wide.
    static let gap: CGFloat = 6
    /// What the clock leaves between the time and the right edge of the tray. Eight, because
    /// that is what the classic clock actually draws with — the XP path uses ten, and reading
    /// the wrong one off the wrong branch is how the gap in front of the time became eleven.
    static let clockRightMargin: CGFloat = 8

    let iconSize: CGFloat
    let hasSpeaker: Bool
    let clockTextWidth: CGFloat

    /// How wide the tray has to be for the gaps to come out right.
    var width: CGFloat {
        var w = Self.gap + iconSize + Self.gap + clockTextWidth + Self.clockRightMargin
        if hasSpeaker { w += iconSize + Self.gap }
        return w
    }

    /// All offsets are from the tray's left edge.
    var iconX: CGFloat { Self.gap }
    var speakerX: CGFloat { Self.gap + iconSize + Self.gap }
    var clockTextX: CGFloat { width - Self.clockRightMargin - clockTextWidth }

    /// Every gap across the tray, left to right. They must all be `gap`; that is the whole point
    /// of the type, and the test says so.
    var gaps: [CGFloat] {
        var out = [iconX]
        if hasSpeaker {
            out.append(speakerX - (iconX + iconSize))
            out.append(clockTextX - (speakerX + iconSize))
        } else {
            out.append(clockTextX - (iconX + iconSize))
        }
        return out
    }
}
