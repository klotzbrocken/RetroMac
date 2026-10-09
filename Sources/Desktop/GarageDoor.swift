import AppKit

/// Mac OS X's WindowShade, animated: the window rolls up into its title bar like a garage door
/// and rolls back down out of it.
///
/// The real window cannot be rolled, only parked (`TitleBarOverlayController`'s WindowShade),
/// so a picture of it does the rolling: taken just before the window is parked, laid over it
/// in a panel under the bar, and shortened from the bottom toward the bar with its lower edge
/// still showing the window's lower edge — the door going up. Rolling down plays the same
/// picture back, and the real window is put back once the door is closed.
final class GarageDoor {

    static let shared = GarageDoor()
    private init() {}

    static let duration: TimeInterval = 0.25

    /// The picture each rolled-up window left, for the way down.
    private var pictures: [CGWindowID: CGImage] = [:]
    private var doors: [CGWindowID: NSPanel] = [:]
    func isMoving(_ wid: CGWindowID) -> Bool { doors[wid] != nil }

    /// Roll `wid` up; `bounds` is the window in Quartz coordinates (top-left origin). Call it
    /// before the window is parked: the picture goes up over the window first. False when
    /// nothing could be photographed (the window then just goes).
    @discardableResult
    func rollUp(_ wid: CGWindowID, bounds: CGRect) -> Bool {
        guard let shot = CGWindowListCreateImage(.null, .optionIncludingWindow, wid, [.boundsIgnoreFraming, .bestResolution]),
              shot.width > 1, shot.height > 1 else { return false }
        pictures[wid] = shot
        run(wid, bounds: bounds, picture: shot, opening: false, then: nil)
        return true
    }

    /// Roll `wid` back down to `bounds`; `then` puts the real window back when the door is
    /// down. Without a picture (it could not be taken) `then` runs at once.
    func rollDown(_ wid: CGWindowID, bounds: CGRect, then: @escaping () -> Void) {
        guard let shot = pictures.removeValue(forKey: wid) else { then(); return }
        run(wid, bounds: bounds, picture: shot, opening: true, then: then)
    }

    /// The window is gone, or unrolled some other way: its picture goes too.
    func forget(_ wid: CGWindowID) {
        pictures.removeValue(forKey: wid)
        doors.removeValue(forKey: wid)?.orderOut(nil)
    }

    func forgetAll() {
        pictures.removeAll()
        doors.values.forEach { $0.orderOut(nil) }
        doors.removeAll()
    }

    private func run(_ wid: CGWindowID, bounds: CGRect, picture: CGImage, opening: Bool, then: (() -> Void)?) {
        doors.removeValue(forKey: wid)?.orderOut(nil)
        let frame = TitleBarOverlayController.appKitFrame(topLeft: bounds, height: bounds.height)
        let scale = NSScreen.screens.first { $0.frame.intersects(frame) }?.backingScaleFactor ?? 2
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.setAccessibilityElement(false)   // drawing only: no "new window" for VoiceOver
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .stationary]
        let host = NSView(frame: NSRect(origin: .zero, size: frame.size))
        host.wantsLayer = true
        // The door: hung from its top edge, the picture held by its bottom edge, so shortening
        // it takes the top of the picture away first — up into the bar.
        let door = CALayer()
        door.anchorPoint = CGPoint(x: 0.5, y: 1)
        door.contents = picture
        door.contentsScale = scale
        door.contentsGravity = .bottom
        door.masksToBounds = true
        let full = CGRect(origin: .zero, size: frame.size)
        door.bounds = opening ? CGRect(x: 0, y: 0, width: full.width, height: 0) : full
        door.position = CGPoint(x: full.midX, y: full.maxY)
        // The door's lower edge, a shadow line as it moves.
        let lip = CALayer()
        lip.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        lip.frame = CGRect(x: 0, y: 0, width: full.width, height: 1)
        door.addSublayer(lip)
        host.layer?.addSublayer(door)
        panel.contentView = host
        panel.order(.above, relativeTo: Int(wid))
        panel.display()
        CATransaction.flush()
        doors[wid] = panel

        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: opening ? .easeOut : .easeIn))
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            then?()
            // The real window needs a moment on screen before the door can go.
            DispatchQueue.main.asyncAfter(deadline: .now() + (opening ? 0.15 : 0)) {
                if self.doors[wid] === panel { self.doors.removeValue(forKey: wid) }
                panel.orderOut(nil)
            }
        }
        door.bounds = opening ? full : CGRect(x: 0, y: 0, width: full.width, height: 0)
        CATransaction.commit()
    }
}
