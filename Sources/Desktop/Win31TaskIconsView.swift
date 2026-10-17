import AppKit

/// Windows 3.1-style row of *running programs* shown as minimized program icons along the
/// bottom of the desktop (the Program Manager theme hides the macOS Dock, so this is how you
/// see and switch to open apps — exactly like minimized programs in real Win 3.x).
/// Click an icon to bring that app to the front; drag it anywhere on the desktop, as Win 3.1's
/// icons could be, and it stays there (per app, across launches).
///
/// The view covers the whole desktop so an icon can be put anywhere; `hitTest` claims only the
/// icons, so every other click falls through.
final class Win31TaskIconsView: NSView {
    private var apps: [NSRunningApplication] = []
    private let cellW: CGFloat = 84
    private let cellH: CGFloat = 62
    private static let positionsKey = "win31TaskIconPositions"
    /// Where the user put each app's icon, by bundle id, in this view's coordinates.
    private var positions: [String: [CGFloat]] =
        UserDefaults.standard.dictionary(forKey: Win31TaskIconsView.positionsKey) as? [String: [CGFloat]] ?? [:]
    private var dragIndex: Int?
    private var dragOffset = NSPoint.zero
    private var didDrag = false

    override var isFlipped: Bool { false }   // bottom-up: icon on top, label at the bottom

    /// Deliver the click even when RetroMac isn't the frontmost app (clicking a task icon
    /// from another app would otherwise just activate the panel and swallow the first click).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Win 3.1 glyph for a running app: the mapped theme icon if the theme has one, else the
    /// theme's default program icon (never the real macOS app icon, which breaks the look).
    private static func win31Icon(for bundleID: String, size: CGFloat) -> NSImage? {
        let theme = ThemeManager.shared.activeTheme
        if ThemeManager.shared.hasThemedIcon(for: bundleID) {
            return ThemeManager.shared.icon(for: bundleID, size: size)
        }
        let dir = theme?.iconsDirectory
        for name in ["group.png", "progman.png", "groupicon.png"] {
            if let url = dir?.appendingPathComponent(name), let img = NSImage(contentsOf: url) {
                img.size = NSSize(width: size, height: size); return img
            }
        }
        return nil
    }

    /// Rebuild from the current set of regular (Dock-worthy) running apps, excluding RetroMac.
    func reload() {
        let own = Bundle.main.bundleIdentifier
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.bundleIdentifier != own }
            .sorted { ($0.localizedName ?? "") .localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
        needsDisplay = true
    }

    /// Each app's cell: where it was put, else the next free slot of the row along the bottom.
    private func cells() -> [NSRect] {
        var slot = 0
        return apps.map { app in
            if let p = positions[app.bundleIdentifier ?? ""], p.count == 2 {
                return NSRect(x: min(max(0, p[0]), bounds.width - cellW), y: min(max(0, p[1]), bounds.height - cellH),
                              width: cellW, height: cellH)
            }
            defer { slot += 1 }
            return NSRect(x: 8 + CGFloat(slot) * cellW, y: 6, width: cellW, height: cellH)
        }
    }

    private func index(at p: NSPoint) -> Int? {
        let c = cells()
        // Topmost first: the one drawn last wins where two overlap.
        return c.indices.reversed().first { c[$0].contains(p) && c[$0].maxX <= bounds.width }
    }

    override func draw(_ dirtyRect: NSRect) {
        let iconSize = ProgramItemView.iconSize
        NSGraphicsContext.current?.imageInterpolation = .none
        for (app, cell) in zip(apps, cells()) {
            if cell.maxX > bounds.width { continue }   // a row longer than the screen is clipped

            let iconRect = NSRect(x: cell.midX - iconSize / 2, y: cell.maxY - iconSize - 2,
                                  width: iconSize, height: iconSize)
            Self.win31Icon(for: app.bundleIdentifier ?? "", size: iconSize)?
                .draw(in: iconRect, from: .zero, operation: .sourceOver,
                      fraction: 1.0, respectFlipped: true, hints: nil)

            let name = app.localizedName ?? app.bundleIdentifier ?? "App"
            let labelRect = NSRect(x: cell.minX + 2, y: 2, width: cellW - 4, height: 26)
            // Active app gets the navy selection box (white text); others black-on-teal.
            if app.isActive {
                let attr = NSAttributedString(string: name, attributes: [.font: Win31Chrome.font(size: 11, bold: false)])
                let tw = min(attr.size().width + 6, cellW)
                Win31Chrome.selection.setFill()
                NSRect(x: cell.midX - tw / 2, y: labelRect.minY, width: tw, height: 14).integral.fill()
            }
            Win31Chrome.drawText(name, in: labelRect, size: 11, color: .white, centered: true)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = index(at: p) else { return }
        let cell = cells()[i]
        dragIndex = i
        dragOffset = NSPoint(x: p.x - cell.minX, y: p.y - cell.minY)
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let i = dragIndex, let id = apps[i].bundleIdentifier else { return }
        let p = convert(event.locationInWindow, from: nil)
        didDrag = true
        positions[id] = [p.x - dragOffset.x, p.y - dragOffset.y]
        needsDisplay = true
    }

    /// A click that did not move brings the app forward; a drag only moves its icon.
    override func mouseUp(with event: NSEvent) {
        defer { dragIndex = nil }
        guard let i = dragIndex else { return }
        if didDrag {
            UserDefaults.standard.set(positions, forKey: Self.positionsKey)
        } else {
            bringToFront(apps[i])
        }
    }

    private func bringToFront(_ app: NSRunningApplication) {
        app.unhide()
        app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    }

    /// VoiceOver gets each drawn icon as a button named after its app; pressing it brings the
    /// app to the front, as a click does.
    private var axParts: [AccessibleHotspot] = []
    /// A group, so VoiceOver asks it for the controls it paints: a view with no subviews that
    /// is no element of its own was skipped, and the window read "content is empty".
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityChildren() -> [Any]? {
        axParts = zip(apps, cells()).filter { $0.1.maxX <= bounds.width }.map { app, cell in
            AccessibleHotspot.make(in: self, label: app.localizedName ?? app.bundleIdentifier ?? "App",
                              rect: cell) { [weak self] in self?.bringToFront(app) }
        }
        return axParts
    }

    /// Only claim clicks that land on an actual icon — empty desktop clicks fall through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        index(at: convert(point, from: superview)) == nil ? nil : self
    }
}
