import AppKit

/// Windows 3.1-style row of *running programs* shown as minimized program icons along the
/// bottom of the desktop (the Program Manager theme hides the macOS Dock, so this is how you
/// see and switch to open apps — exactly like minimized programs in real Win 3.x).
/// Click an icon to bring that app to the front.
final class Win31TaskIconsView: NSView {
    private var apps: [NSRunningApplication] = []
    private let cellW: CGFloat = 84
    private let cellH: CGFloat = 62

    override var isFlipped: Bool { false }   // bottom-up: icon on top, label at the bottom

    /// Rebuild from the current set of regular (Dock-worthy) running apps, excluding RetroMac.
    func reload() {
        let own = Bundle.main.bundleIdentifier
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.bundleIdentifier != own }
            .sorted { ($0.localizedName ?? "") .localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let iconSize = ProgramItemView.iconSize
        NSGraphicsContext.current?.imageInterpolation = .none
        for (i, app) in apps.enumerated() {
            let x = CGFloat(i) * cellW
            if x + cellW > bounds.width { break }   // single row; clip overflow
            let cell = NSRect(x: x, y: 0, width: cellW, height: cellH)

            let iconRect = NSRect(x: cell.midX - iconSize / 2, y: cell.maxY - iconSize - 2,
                                  width: iconSize, height: iconSize)
            app.icon?.draw(in: iconRect, from: .zero, operation: .sourceOver,
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
        let idx = Int(p.x / cellW)
        guard idx >= 0, idx < apps.count else { return }
        let app = apps[idx]
        app.unhide()
        app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    }

    /// Only claim clicks that land on an actual icon — empty desktop clicks fall through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        let idx = Int(p.x / cellW)
        guard p.y >= 0, p.y <= cellH, idx >= 0, idx < apps.count else { return nil }
        return self
    }
}
