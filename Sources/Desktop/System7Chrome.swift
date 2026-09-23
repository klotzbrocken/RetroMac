import AppKit

/// **System 7.1** window chrome, in greys from the Mac's 256-colour table.
/// The title bar is System 6's racing stripes (`System6Chrome` draws them) with the close box
/// on the left AND the zoom box on the right, which is what System 7 added; the window is
/// white in a 1 px black frame, and the parts System 7 drew in grey — the scroll bar's gutter,
/// the grow box's ground — use #AAAAAA and #555555 rather than the Platinum bevels.
enum System7Chrome {

    static let black = Mac256.black
    static let dark = Mac256.grey55      // #555555
    static let light = Mac256.greyAA     // #AAAAAA
    static let white = Mac256.white

    static let boxSize = System6Chrome.boxSize
    static var titleFont: NSFont { System6Chrome.titleFont }

    private static func fill(_ r: NSRect, _ c: NSColor) { c.setFill(); NSBezierPath(rect: r).fill() }

    static func titleBar(_ bar: NSRect, active: Bool) { System6Chrome.titleBar(bar, active: active) }
    static func closeBox(_ r: NSRect, state: ChromeButtonState = .normal) { System6Chrome.closeBox(r, state: state) }
    static func zoomBox(_ r: NSRect, state: ChromeButtonState = .normal) { System6Chrome.resizeBox(r, state: state) }
    static func titlePlaque(_ title: String, bar: NSRect, font: NSFont, active: Bool) {
        System6Chrome.titlePlaque(title, bar: bar, font: font, active: active)
    }

    /// The 1 px black frame the window sits in.
    static func frame(_ r: NSRect) {
        black.setStroke()
        let p = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
        p.lineWidth = 1
        p.stroke()
    }

    /// A scroll bar the era's way: a #AAAAAA gutter between two white arrow boxes, a white
    /// thumb outlined in black. `fraction` 0…1 is where the thumb sits, `visible` 0…1 how
    /// much of the document shows. A bar with nothing to scroll is left empty (grey).
    static func scrollBar(_ r: NSRect, vertical: Bool, fraction: CGFloat, visible: CGFloat) {
        fill(r, light)
        frame(r)
        let side = vertical ? r.width : r.height
        let arrowA = vertical ? NSRect(x: r.minX, y: r.maxY - side, width: side, height: side)
                              : NSRect(x: r.minX, y: r.minY, width: side, height: side)
        let arrowB = vertical ? NSRect(x: r.minX, y: r.minY, width: side, height: side)
                              : NSRect(x: r.maxX - side, y: r.minY, width: side, height: side)
        for (box, up) in [(arrowA, true), (arrowB, false)] {
            fill(box, white); frame(box)
            let c = box.insetBy(dx: 4, dy: 4)
            let p = NSBezierPath()
            if vertical {
                if up { p.move(to: NSPoint(x: c.minX, y: c.minY)); p.line(to: NSPoint(x: c.maxX, y: c.minY)); p.line(to: NSPoint(x: c.midX, y: c.maxY)) }
                else { p.move(to: NSPoint(x: c.minX, y: c.maxY)); p.line(to: NSPoint(x: c.maxX, y: c.maxY)); p.line(to: NSPoint(x: c.midX, y: c.minY)) }
            } else {
                if up { p.move(to: NSPoint(x: c.maxX, y: c.minY)); p.line(to: NSPoint(x: c.maxX, y: c.maxY)); p.line(to: NSPoint(x: c.minX, y: c.midY)) }
                else { p.move(to: NSPoint(x: c.minX, y: c.minY)); p.line(to: NSPoint(x: c.minX, y: c.maxY)); p.line(to: NSPoint(x: c.maxX, y: c.midY)) }
            }
            p.close(); black.setFill(); p.fill()
        }
        guard visible > 0, visible < 1 else { return }
        let track = vertical ? NSRect(x: r.minX, y: r.minY + side, width: r.width, height: r.height - 2 * side)
                             : NSRect(x: r.minX + side, y: r.minY, width: r.width - 2 * side, height: r.height)
        let length = max(side, (vertical ? track.height : track.width) * visible)
        let travel = (vertical ? track.height : track.width) - length
        let thumb = vertical
            ? NSRect(x: track.minX, y: track.maxY - length - travel * fraction, width: track.width, height: length)
            : NSRect(x: track.minX + travel * fraction, y: track.minY, width: length, height: track.height)
        fill(thumb, white); frame(thumb)
    }

    /// The grow box in the bottom-right corner: two nested outlines, as System 7 drew it.
    static func growBox(_ r: NSRect) {
        fill(r, white)
        frame(r)
        let outer = r.insetBy(dx: 3, dy: 3)
        fill(NSRect(x: outer.minX, y: outer.minY, width: outer.width - 3, height: outer.height - 3), light)
        black.setStroke()
        let a = NSBezierPath(rect: NSRect(x: outer.minX + 0.5, y: outer.minY + 0.5, width: outer.width - 3, height: outer.height - 3))
        a.lineWidth = 1; a.stroke()
        let b = NSBezierPath(rect: NSRect(x: outer.minX + 3.5, y: outer.minY + 3.5, width: outer.width - 3, height: outer.height - 3))
        b.lineWidth = 1; b.stroke()
    }
}
