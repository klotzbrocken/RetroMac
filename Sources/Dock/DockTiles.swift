import AppKit

// MARK: - The dock's row, enumerated once

/// One tile in the icon dock's row.
///
/// The row used to be spelled out four separate times — once to size the bar, once to create the
/// views, once to position them, once to notice the contents changed — as four parallel if-chains
/// that had to be kept in step by hand. They drifted: when Dashboard joined the dock it reached
/// three of the four, so the bar came out exactly one tile too narrow and the trash was drawn
/// beside it rather than on it. The vertical branch had drifted too, spacing its stacks
/// differently on rebuild than on relayout. One list now feeds all four.
struct DockTile {
    enum Kind: Equatable {
        /// A pinned app, a folder stack, or a running app that is not pinned.
        case app(bundleID: String, transient: Bool)
        case dashboard
        case showDesktop
        case urlLauncher
        case trash
        case doomLauncher
    }
    /// Which separator, if any, belongs in this tile's leading gap.
    enum Separator: Equatable { case transients, rightGroup }

    let kind: Kind
    /// Bundle id for a real app, the synthetic `__trash__`-style id otherwise. Identity for
    /// change detection and for the view.
    let id: String
    /// The tile's own width. Only the DOOM logo differs from a plain icon.
    let width: CGFloat
    /// Extra room before this tile, on top of the spacing every tile already trails.
    let gapBefore: CGFloat
    let separator: Separator?
}

extension DockView {

    /// The icon dock's row, in order. Pure on purpose: everything it needs is an argument, so the
    /// invariant that sizing and layout agree can be tested without a running dock.
    static func iconDockTiles(taskbar: Bool,
                              showQuickLaunch: Bool,
                              apps: [DockApp],
                              transients: [String],
                              stacksOnRight: Bool,
                              hasDashboard: Bool,
                              hasShowDesktop: Bool,
                              hasUrlLauncher: Bool,
                              hasTrash: Bool,
                              hasDoomLauncher: Bool,
                              iconSize: CGFloat,
                              spacing: CGFloat,
                              doomWidth: CGFloat) -> [DockTile] {
        // Folder stacks (Downloads, Applications) belong beside the trash the way macOS groups
        // them, rather than inline among the pinned apps. Layouts with no right-hand section have
        // no trash either, so there they stay inline.
        let stacks = stacksOnRight ? apps.filter { $0.isFolder } : []
        let inline = stacksOnRight ? apps.filter { !$0.isFolder } : apps

        var tiles: [DockTile] = []
        func tile(_ kind: DockTile.Kind, _ id: String,
                  width: CGFloat = iconSize, gap: CGFloat = 0, sep: DockTile.Separator? = nil) {
            tiles.append(DockTile(kind: kind, id: id, width: width, gapBefore: gap, separator: sep))
        }

        // A Windows taskbar's icon tiles are its Quick Launch bar and nothing else: running apps
        // become elongated task buttons, and there is no Dashboard, no stack group and no trash.
        // Show Desktop leads, as it did on the real thing.
        if taskbar {
            guard showQuickLaunch else { return [] }
            if hasShowDesktop { tile(.showDesktop, "__showdesktop__") }
            for app in inline { tile(.app(bundleID: app.bundleID, transient: false), app.bundleID) }
            return tiles
        }

        for (i, app) in inline.enumerated() {
            tile(.app(bundleID: app.bundleID, transient: false), app.bundleID)
            // Mac OS X put Dashboard in the Dock directly after Finder.
            if i == 0 && hasDashboard { tile(.dashboard, "__dashboard__") }
        }
        // A dock with no pinned apps still gets its Dashboard tile.
        if inline.isEmpty && hasDashboard { tile(.dashboard, "__dashboard__") }

        if hasShowDesktop { tile(.showDesktop, "__showdesktop__") }

        for (i, bid) in transients.enumerated() {
            tile(.app(bundleID: bid, transient: true), bid,
                 gap: i == 0 ? spacing : 0, sep: i == 0 ? .transients : nil)
        }

        if hasUrlLauncher || hasTrash || hasDoomLauncher {
            var first = true
            func rightTile(_ kind: DockTile.Kind, _ id: String, width: CGFloat = iconSize) {
                tile(kind, id, width: width,
                     gap: first ? spacing : 0, sep: first ? .rightGroup : nil)
                first = false
            }
            for app in stacks { rightTile(.app(bundleID: app.bundleID, transient: false), app.bundleID) }
            if hasUrlLauncher { rightTile(.urlLauncher, "__urllauncher__") }
            if hasTrash { rightTile(.trash, "__trash__") }
            if hasDoomLauncher { rightTile(.doomLauncher, "__doomlauncher__", width: doomWidth) }
        }
        return tiles
    }

    /// How much room the row needs along the layout axis, not counting the bar's own padding.
    /// Every tile trails `spacing`; the last one's is dropped.
    static func iconDockRunLength(_ tiles: [DockTile], spacing: CGFloat) -> CGFloat {
        guard !tiles.isEmpty else { return 0 }
        return tiles.reduce(0) { $0 + $1.gapBefore + $1.width + spacing } - spacing
    }
}
