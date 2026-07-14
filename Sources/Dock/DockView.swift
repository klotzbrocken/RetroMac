import AppKit

final class DockView: NSView {
    private var itemViews: [DockItemView] = []
    private var taskButtonViews: [TaskButtonView] = []   // Win98/XP per-window taskbar buttons
    // Resting Y-centres of vertical-dock icons, captured at layout time. The frame-based
    // vertical magnifier mutates item frames, so it must read REST positions from here
    // (not the live, already-magnified frames) to avoid compounding spacing/jitter.
    private var restCentersY: [CGFloat] = []
    private var restCentersX: [CGFloat] = []
    private var runningBundleIDs: Set<String> = []
    private var lastItemBundleIDs: [String] = []
    private var wsObserver: NSObjectProtocol?
    private var appsObserver: NSObjectProtocol?
    private var themeObserver: NSObjectProtocol?
    private var wsTerminateObserver: NSObjectProtocol?
    private var wsActivateObserver: NSObjectProtocol?
    private var dropInsertionIndex: Int?
    private var separatorX: CGFloat?
    private var startSeparatorX: CGFloat?
    private var separatorY: CGFloat?
    private var trashSeparatorX: CGFloat?
    private var startButtonFrame: NSRect = .zero
    private var clockFrame: NSRect = .zero
    private var clockTimer: Timer?
    private var clockString: String = ""
    private var startButtonIcon: NSImage?
    private var startButtonImages: (normal: NSImage, hover: NSImage, pressed: NSImage)?
    private var startButtonPressed = false
    private var startButtonHovered = false
    private var diskFreeFrame: NSRect = .zero
    private var diskFreeLabel: String = ""   // e.g. "APFS"
    private var diskFreeValue: String = ""   // e.g. "150"
    private var diskFreeUnit: String = ""    // e.g. "GB Free"
    private var trayIconFrame: NSRect = .zero  // ICQ tray icon (right of clock)
    private var magnificationTrackingArea: NSTrackingArea?
    private var startMenuPanel: StartMenuPanel?
    private var trashMonitorSource: DispatchSourceFileSystemObject?
    private var trashDirectoryFD: Int32 = -1
    private var trashPollTimer: Timer?
    private var trashEmptyCached = true   // updated off-main via refreshTrashState()
    var magnificationOverflow: CGFloat = 0
    /// Extra width on each side of the window for magnification expansion
    var horizontalMagOverflow: CGFloat = 0
    /// Scale factor applied when the dock is too wide for the screen (1.0 = no shrink)
    var dynamicScale: CGFloat = 1.0
    /// Expanded dock bar rect during magnification (nil = use resting rect)
    private var magnifiedDockBarRect: NSRect?
    // Continuous eased magnification: a phase 0→1 ramps in/out so the bar AND icons
    // grow/shrink together (computed from the same phase each tick = always in sync).
    private var magPhase: CGFloat = 0
    private var magPhaseTarget: CGFloat = 0
    private var magTargetPoint: NSPoint = .zero
    private var magTimer: DispatchSourceTimer?
    private var magRampStart: CFTimeInterval = 0
    private var magRampFromPhase: CGFloat = 0
    private var magRestFrames: [NSRect] = []   // icon frames at rest (captured when magnify engages)
    private var magExitFrames: [NSRect] = []   // icon frames when the exit ramp began
    private var magExitBar: NSRect = .zero     // bar rect when the exit ramp began

    // Pac-Man pellet border animation (theme borderStyle == "pacman") — layer-based
    private var pacmanTimer: Timer?
    private var pacmanPhase: CGFloat = 0
    private var pacmanObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?
    private var minimizedObserver: NSObjectProtocol?
    private var pelletLayer: CAShapeLayer?
    private var pacLayer: CAShapeLayer?
    private var pacmanConfiguredRect: NSRect = .zero
    private var pacmanConfiguredAnimated: Bool?
    private var pacPerimSegs: [(CGPoint, CGPoint)] = []
    private var pacPerimLen: [CGFloat] = []
    private var pacPerim: CGFloat = 0
    private var pacTopLen: CGFloat = 0
    private var pacPelletDists: [CGFloat] = []
    private var pacPelletR: CGFloat = 2.2
    private var pacRadius: CGFloat = 7
    private var pacLastEatenCount: Int = -1
    // Run-mode motion is now stateful (position + direction) so hovered icons can act as
    // barriers that reverse Pac-Man / the ghosts.
    private var pacDist: CGFloat = 0
    private var pacDir: CGFloat = 1        // +1 forward / -1 reversed
    private var pacBlockCooldown: Int = 0  // ticks to ignore barrier re-trigger after a bounce
    private var eatenPellets: Set<Int> = []
    // Perimeter positions of currently-hovered dock icons (bundleID → distance). A mover
    // heading into one of these is blocked and turns around.
    private var barrierDists: [String: CGFloat] = [:]
    private var pacmanConfiguredClock: Bool?
    private var pacmanIsClock = false

    // Doom Slayer — DOOM-themed counterpart to the Pac-Man border (borderStyle "doomslayer").
    private let doomSlayer = DoomSlayerController()
    private var clockLabelLayers: [CATextLayer] = []
    private var clockTopStart: CGFloat = 0
    private var clockTopEnd: CGFloat = 0
    private var clockDotDists: [CGFloat] = []
    private var lastClockHour: Int = -1
    // Ghosts that chase Pac-Man (spawned on icon hover; max 2).
    private final class PacGhost {
        let body = CAShapeLayer()
        var dist: CGFloat
        var dir: CGFloat = 1          // travel direction (+1/-1), flipped by barriers
        var blockCooldown: Int = 0    // ticks to keep the bounced direction after a barrier hit
        init(dist: CGFloat) { self.dist = dist }
    }
    private var ghosts: [PacGhost] = []
    private let maxGhosts = 2
    private var ghostCGImage: CGImage?
    // Cherry power-up: eating it lets Pac-Man hunt the ghosts for a while.
    private var cherryLayer: CALayer?
    private var cherryDist: CGFloat = 0
    private var nextCherryPhase: CGFloat = 150     // ~10s after start (15fps)
    private var poweredUntilPhase: CGFloat = -1

    // Control Strip state
    private var controlStripCollapsed = false
    private var controlStripLeftCap: NSImage?
    private var controlStripRightCap: NSImage?

    private var isVertical: Bool {
        ThemeManager.shared.activeTheme?.config.isVertical ?? false
    }

    /// Resolved dock edge: "bottom"/"left"/"right".
    private var dockPosition: String {
        ThemeManager.shared.activeTheme?.config.effectiveDockPosition ?? "bottom"
    }

    private var hasStartButton: Bool {
        ThemeManager.shared.activeTheme?.config.hasStartButton ?? false
    }

    private var hasClock: Bool {
        ThemeManager.shared.activeTheme?.config.hasClock ?? false
    }

    private var hasMagnification: Bool {
        (ThemeManager.shared.activeTheme?.config.hasMagnification ?? false) && AppSettings.shared.dockMagnification
    }

    private var hasTrash: Bool {
        ThemeManager.shared.activeTheme?.config.hasTrash ?? false
    }
    private var hasUrlLauncher: Bool {
        ThemeManager.shared.activeTheme?.config.hasUrlLauncher ?? false
    }
    /// DOOM logo launcher tile (Maiks Favourite II) — sits right of the trash, launches DOOM.
    private var hasDoomLauncher: Bool {
        ThemeManager.shared.activeTheme?.config.dock.borderStyle == "doomslayer"
    }
    /// Aspect ratio (w/h) of the DOOM logo, so its dock tile is as TALL as the icons (= trash)
    /// while keeping the wide wordmark un-squashed. Cached from the theme bundle.
    private var doomLogoAspectCache: CGFloat?
    private var doomLogoAspect: CGFloat {
        if let a = doomLogoAspectCache { return a }
        var a: CGFloat = 1.14
        if let url = ThemeManager.shared.activeTheme?.url.appendingPathComponent("doom-logo.png"),
           let img = NSImage(contentsOf: url), img.size.height > 0 {
            a = img.size.width / img.size.height
        }
        doomLogoAspectCache = a
        return a
    }
    private func doomTileWidth(_ iconSize: CGFloat) -> CGFloat { iconSize * doomLogoAspect }
    /// Win98-style taskbar (classic start menu): etched groove separators + Show Desktop.
    private var isClassicTaskbar: Bool {
        ThemeManager.shared.activeTheme?.config.dock.startMenuStyle == "classic"
    }
    private var hasShowDesktop: Bool { isClassicTaskbar && !isVertical && !isControlStrip }

    private var hasDiskFree: Bool {
        ThemeManager.shared.activeTheme?.config.hasDiskFree ?? false
    }

    private var hasGrip: Bool {
        ThemeManager.shared.activeTheme?.config.hasGrip ?? false
    }

    private var isControlStrip: Bool {
        ThemeManager.shared.activeTheme?.config.isControlStrip ?? false
    }

    /// Extra space at the top of a vertical dock for grip dots
    private var gripHeight: CGFloat {
        hasGrip && isVertical ? 22 : 0
    }

    /// The resting rect where the dock bar background is drawn (centered within wider window)
    private var dockBarRect: NSRect {
        if isVertical {
            // Vertical: magnification expands the bar THICKNESS (width axis) toward
            // the interior; the bar hugs the screen edge. Along the LONG axis the bar
            // spans the resting region, leaving headroom (horizontalMagOverflow per
            // side) for magnified icons to reflow into.
            let thickness = bounds.width - magnificationOverflow
            let x = (dockPosition == "right") ? magnificationOverflow : 0
            let len = bounds.height - horizontalMagOverflow * 2
            return NSRect(x: x, y: horizontalMagOverflow, width: thickness, height: len)
        }
        let barWidth = bounds.width - horizontalMagOverflow * 2
        let barHeight = bounds.height - magnificationOverflow
        return NSRect(x: horizontalMagOverflow, y: 0, width: barWidth, height: barHeight)
    }

    /// The rect to use for drawing — expands during magnification
    private var currentBarRect: NSRect {
        magnifiedDockBarRect ?? dockBarRect
    }

    /// Background + border paths for a vertical dock: flush (square) on the
    /// screen-edge side, rounded on the other three. The border path is open and
    /// covers only the top, bottom, and interior sides (no border on the edge side).
    private func verticalBarPaths(rect: NSRect, radius r: CGFloat) -> (fill: NSBezierPath, border: NSBezierPath) {
        let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        let fill = NSBezierPath()
        let border = NSBezierPath()
        if dockPosition == "right" {
            // Flush on the RIGHT (screen edge); rounded on the LEFT (interior).
            fill.move(to: NSPoint(x: maxX, y: minY))
            fill.line(to: NSPoint(x: maxX, y: maxY))
            fill.appendArc(from: NSPoint(x: minX, y: maxY), to: NSPoint(x: minX, y: minY), radius: r)
            fill.appendArc(from: NSPoint(x: minX, y: minY), to: NSPoint(x: maxX, y: minY), radius: r)
            fill.close()
            border.move(to: NSPoint(x: maxX, y: maxY))
            border.appendArc(from: NSPoint(x: minX, y: maxY), to: NSPoint(x: minX, y: minY), radius: r)
            border.appendArc(from: NSPoint(x: minX, y: minY), to: NSPoint(x: maxX, y: minY), radius: r)
            border.line(to: NSPoint(x: maxX, y: minY))
        } else {
            // Flush on the LEFT (screen edge); rounded on the RIGHT (interior).
            fill.move(to: NSPoint(x: minX, y: minY))
            fill.line(to: NSPoint(x: minX, y: maxY))
            fill.appendArc(from: NSPoint(x: maxX, y: maxY), to: NSPoint(x: maxX, y: minY), radius: r)
            fill.appendArc(from: NSPoint(x: maxX, y: minY), to: NSPoint(x: minX, y: minY), radius: r)
            fill.close()
            border.move(to: NSPoint(x: minX, y: maxY))
            border.appendArc(from: NSPoint(x: maxX, y: maxY), to: NSPoint(x: maxX, y: minY), radius: r)
            border.appendArc(from: NSPoint(x: maxX, y: minY), to: NSPoint(x: minX, y: minY), radius: r)
            border.line(to: NSPoint(x: minX, y: minY))
        }
        return (fill, border)
    }

    var onContextMenu: ((String, NSPoint) -> Void)?
    var onDockContextMenu: ((NSPoint) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        registerForDraggedTypes([.fileURL])
        setupObservers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        magTimer?.cancel()
        clockTimer?.invalidate()
        pacmanTimer?.invalidate()
        doomSlayer.teardown()
        trashPollTimer?.invalidate()
        trashMonitorSource?.cancel()
        if trashDirectoryFD >= 0 { close(trashDirectoryFD) }
        let wsNC = NSWorkspace.shared.notificationCenter
        if let obs = wsObserver { wsNC.removeObserver(obs) }
        if let obs = wsTerminateObserver { wsNC.removeObserver(obs) }
        if let obs = wsActivateObserver { wsNC.removeObserver(obs) }
        if let obs = appsObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = themeObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = pacmanObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = occlusionObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = minimizedObserver { NotificationCenter.default.removeObserver(obs) }
    }

    private func setupObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        wsObserver = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.updateRunningIndicators() }

        let nc2 = NotificationCenter.default
        appsObserver = nc2.addObserver(forName: .dockAppsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildItems()
        }
        themeObserver = nc2.addObserver(forName: .dockThemeChanged, object: nil, queue: .main) { [weak self] _ in
            // The new theme may not have a "Show Desktop" tile — un-hide anything the old
            // theme's tile hid so those apps aren't stranded.
            DockView.restoreShowDesktop()
            self?.rebuildItems()
        }
        // Minimized windows of non-pinned apps surface as dock tiles; rebuild when they change.
        minimizedObserver = nc2.addObserver(forName: .minimizedWindowsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildItems()
        }
        pacmanObserver = nc2.addObserver(forName: .pacmanAnimationChanged, object: nil, queue: .main) { [weak self] _ in
            self?.needsDisplay = true   // re-configure layers (draw() → updatePacmanBorder)
        }
        // Pause the Pac-Man animation while the dock window isn't visible (covered, other
        // Space, or display asleep) so it costs nothing in the background.
        occlusionObserver = nc2.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] note in
            guard let self = self, (note.object as AnyObject?) === self.window else { return }
            self.refreshPacmanAnimationState()
            self.doomSlayer.refreshAnimationState(visible: self.window?.occlusionState.contains(.visible) ?? true)
        }

        let wsNC = NSWorkspace.shared.notificationCenter
        wsTerminateObserver = wsNC.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateRunningIndicators()
        }
        wsActivateObserver = wsNC.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateRunningIndicators()
        }

        startTrashMonitor()
    }

    // MARK: - Trash Monitoring

    private func startTrashMonitor() {
        // ALWAYS poll — this is the reliable path. The fs-monitor below is a bonus and
        // can fail (e.g. opening ~/.Trash is TCC-gated); previously a failed open()
        // returned early and skipped the poll entirely, so the icon never updated.
        trashPollTimer?.invalidate()
        trashPollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshTrashState()
        }
        refreshTrashState()

        guard let trashURL = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        let fd = Darwin.open(trashURL.path, O_EVTONLY)
        guard fd >= 0 else { return }   // fs-monitor is optional; poll already covers us
        trashDirectoryFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.refreshTrashState()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        trashMonitorSource = source
    }

    private func isTrashEmpty() -> Bool { trashEmptyCached }

    /// Recompute trash full/empty off-main, then update the icon. ~/.Trash is TCC-gated on
    /// modern macOS (enumerating it fails without Full Disk Access), so we ask Finder for the
    /// item count via AppleScript (Automation) instead — with a direct-read fast path for
    /// users who HAVE granted Full Disk Access.
    private func refreshTrashState() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let empty = DockView.computeTrashEmpty()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.trashEmptyCached = empty
                self.updateTrashIcon()
            }
        }
    }

    private static func computeTrashEmpty() -> Bool {
        // Fast path: direct read (only succeeds with Full Disk Access).
        if let trashURL = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
           let contents = try? FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil, options: []) {
            return contents.filter { $0.lastPathComponent != ".DS_Store" }.isEmpty
        }
        // TCC-gated → ask Finder.
        if let n = trashCountViaFinder() { return n == 0 }
        return true   // can't tell → assume empty (no false "full")
    }

    private static func trashCountViaFinder() -> Int? {
        guard let script = NSAppleScript(source: "tell application \"Finder\" to return (count of items of trash)") else { return nil }
        var err: NSDictionary?
        let r = script.executeAndReturnError(&err)
        if err != nil { return nil }
        return Int(r.int32Value)
    }

    private func updateTrashIcon() {
        guard let theme = ThemeManager.shared.activeTheme?.config else { return }
        let iconSize = theme.dock.iconSize * dynamicScale
        for item in itemViews where item.bundleID == "__trash__" {
            let icon = trashIcon(size: iconSize)
            item.updateIcon(icon)
        }
    }

    func rebuildItems() {
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        taskButtonViews.forEach { $0.removeFromSuperview() }
        taskButtonViews.removeAll()
        separatorX = nil
        separatorY = nil
        trashSeparatorX = nil
        startSeparatorX = nil
        startButtonIcon = nil
        startButtonImages = nil
        diskFreeFrame = .zero

        let apps = AppManager.shared.apps
        guard let theme = ThemeManager.shared.activeTheme?.config else { return }
        let scale = CGFloat(AppSettings.shared.dockIconScale) * dynamicScale
        let iconSize = theme.dock.iconSize * scale
        let spacing = theme.dock.spacing * scale
        let padding = theme.dock.padding * scale
        let vertical = isVertical
        let barRect = dockBarRect

        setupMagnificationTracking()

        if vertical {
            // Top→bottom, centered on the bar thickness, trash at the bottom — must
            // match relayoutItems() exactly so the resting layout and magnifier agree.
            let bar = barRect
            let x = bar.midX - iconSize / 2
            var y = bar.maxY - padding - gripHeight - iconSize
            for app in apps {
                addItem(bundleID: app.bundleID,
                        frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                        theme: theme, iconSize: iconSize)
                y -= iconSize + spacing
            }
            let transientApps = runningAppsNotInDock()
            if !transientApps.isEmpty {
                separatorY = y + iconSize + spacing / 2
                y -= spacing
                for bid in transientApps {
                    addItem(bundleID: bid,
                            frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                            theme: theme, iconSize: iconSize, isTransient: true)
                    y -= iconSize + spacing
                }
            }
            if hasUrlLauncher || hasTrash || hasDoomLauncher {
                y -= spacing
                if hasUrlLauncher {
                    addURLLauncherItem(frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                                       theme: theme, iconSize: iconSize)
                    y -= iconSize + spacing
                }
                if hasTrash {
                    addTrashItem(frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                                 theme: theme, iconSize: iconSize)
                    y -= iconSize + spacing
                }
                if hasDoomLauncher {
                    addDoomLauncherItem(frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                                        theme: theme, iconSize: iconSize)
                }
            }
        } else if isControlStrip {
            // Mac OS 9 Control Strip layout: left cap PNG + icon modules + right cap PNG
            // Each module = icon + ▶ arrow, separated by grooves
            loadControlStripCaps()
            let leftCapW = controlStripLeftCapWidth
            let arrowWidth: CGFloat = 14   // space for ▶ arrow after icon
            let grooveWidth: CGFloat = 2   // 1px dark + 1px light
            var x = barRect.minX + leftCapW

            // Skip start button, clock, disk free, tray icon, trash for Control Strip
            startButtonFrame = .zero
            clockFrame = .zero
            clockTimer?.invalidate()
            clockTimer = nil
            trayIconFrame = .zero
            diskFreeFrame = .zero

            // Pinned apps
            let allBundleIDs = apps.map { $0.bundleID }
            for (i, app) in apps.enumerated() {
                let y = (barRect.height - iconSize) / 2
                addItem(bundleID: app.bundleID,
                        frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                        theme: theme, iconSize: iconSize)
                x += iconSize + arrowWidth
                if i < apps.count - 1 || !runningAppsNotInDock().isEmpty {
                    x += grooveWidth
                }
            }
            // Running apps not in dock (transient)
            let transientApps = runningAppsNotInDock()
            for (i, bundleID) in transientApps.enumerated() {
                let y = (barRect.height - iconSize) / 2
                addItem(bundleID: bundleID,
                        frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                        theme: theme, iconSize: iconSize)
                x += iconSize + arrowWidth
                if i < transientApps.count - 1 {
                    x += grooveWidth
                }
            }

        } else {
            var x = barRect.minX + padding

            if hasStartButton {
                loadStartButtonIcon()
                loadStartButtonImages()
                let isXP = theme.isXPStartMenu

                let btnHeight: CGFloat
                let btnWidth: CGFloat
                let btnY: CGFloat

                if isXP, let imgs = startButtonImages {
                    // XP Luna bitmap start button: fills the full bar height (no top/bottom
                    // margin), width follows the sprite's aspect ratio, drawn 1:1.
                    btnHeight = barRect.height
                    btnY = 0
                    btnWidth = btnHeight * (imgs.normal.size.width / imgs.normal.size.height)
                } else if isXP {
                    // Fallback (no sprite): content-based programmatic green button.
                    btnHeight = barRect.height
                    btnY = 0
                    let iconSz = max(20, btnHeight * 0.52)
                    let label = theme.dock.startButtonLabel ?? "start"
                    let fontSize = max(15, btnHeight * 0.46)
                    let boldFont = NSFont.boldSystemFont(ofSize: fontSize)
                    let italicFont = NSFont(descriptor: boldFont.fontDescriptor.withSymbolicTraits(.italic), size: fontSize) ?? boldFont
                    let labelWidth = (label as NSString).size(withAttributes: [.font: italicFont]).width
                    btnWidth = 8 + iconSz + 3 + labelWidth + 7
                } else {
                    let isSunken = theme.dock.startButtonStyle == "sunken"
                    if isSunken, let imgs = startButtonImages {
                        // OS/2 WarpCenter: bitmap-based — use sprite aspect ratio
                        btnHeight = barRect.height
                        btnY = 0
                        let sliceW = imgs.normal.size.width
                        let sliceH = imgs.normal.size.height
                        btnWidth = btnHeight * (sliceW / sliceH)
                    } else {
                        // Classic style: text-based sizing (bigger icon + label — Win95 taskbar)
                        let label = theme.dock.startButtonLabel ?? "Start"
                        let fontSize = max(13, iconSize * 0.55)
                        let font = NSFont.boldSystemFont(ofSize: fontSize)
                        let iconSz = max(18, iconSize * 0.78)
                        if label.isEmpty {
                            btnWidth = 4 + iconSz + 4
                        } else {
                            let pad: CGFloat = isSunken ? 4 : 6
                            let gap: CGFloat = isSunken ? 2 : 3
                            let labelWidth = (label as NSString).size(withAttributes: [.font: font]).width
                            btnWidth = pad + iconSz + gap + labelWidth + pad
                        }
                        if isSunken {
                            btnHeight = barRect.height
                            btnY = 0
                        } else {
                            btnHeight = barRect.height - 6
                            btnY = 3
                        }
                    }
                }

                let isSunkenLayout = theme.dock.startButtonStyle == "sunken"
                startButtonFrame = NSRect(x: barRect.minX + (isXP || isSunkenLayout ? 0 : 3), y: btnY, width: btnWidth, height: btnHeight)
                x = startButtonFrame.maxX + spacing
                if isClassicTaskbar { startSeparatorX = x - spacing / 2; x += 2 }
            } else {
                startButtonFrame = .zero
            }

            // Right-side trays: clock + tray icon + disk free, positioned from right edge
            var rightEdge = barRect.maxX

            // Pre-calculate tray icon size for Win98/XP (needed to widen systray clockFrame)
            let hasTrayIcon: Bool
            let traySize: CGFloat
            let trayPad: CGFloat = 3
            if let tn = ThemeManager.shared.activeTheme?.config.name,
               (tn == "Windows 98" || tn == "Windows XP") {
                hasTrayIcon = true
                traySize = max(14, iconSize * 0.55)
            } else {
                hasTrayIcon = false
                traySize = 0
            }

            if hasClock {
                updateClockString()
                startClockTimer()
                let isXP = theme.isXPStartMenu
                let clockFontSize = theme.dock.clockFontSize ?? max(11, iconSize * 0.45)
                let clockFont = NSFont.monospacedDigitSystemFont(ofSize: clockFontSize, weight: .regular)
                let clockTextWidth = (clockString as NSString).size(withAttributes: [.font: clockFont]).width
                var clockWidth = clockTextWidth + (isXP ? 20 : 16)
                // Widen systray to include ICQ tray icon
                if hasTrayIcon {
                    clockWidth += traySize + trayPad * 2 + 2
                    // On XP the ICQ icon is shifted right past the systray chevron, so
                    // reserve the extra clearance too (chevron half-width + gap).
                    if isXP {
                        clockWidth += max(14, iconSize * 0.55) * 0.9 + 2
                    }
                }
                let isSunkenClock = theme.dock.startButtonStyle == "sunken"
                if isXP || isSunkenClock {
                    clockFrame = NSRect(x: rightEdge - clockWidth, y: 0, width: clockWidth, height: barRect.height)
                } else {
                    let clockHeight = barRect.height - 6
                    clockFrame = NSRect(x: rightEdge - clockWidth - 3, y: 3, width: clockWidth, height: clockHeight)
                }
                rightEdge = clockFrame.minX
            } else {
                clockFrame = .zero
                clockTimer?.invalidate()
                clockTimer = nil
            }

            // ICQ tray icon — inside the systray area for Windows 98 / Windows XP themes.
            // On XP the "show hidden icons" chevron is drawn centred on clockFrame.minX,
            // so it occupies the tray's left half-width. Shift the ICQ icon right past the
            // chevron's right half (≈ max(14, iconSize*0.55)*0.9) plus a small gap so they
            // don't overlap. Win98 has no chevron, so keep the tight original offset.
            if hasTrayIcon && !clockFrame.isEmpty {
                let trayStartX: CGFloat
                if theme.isXPStartMenu {
                    trayStartX = clockFrame.minX + max(14, iconSize * 0.55) * 0.9 + trayPad + 4
                } else {
                    trayStartX = clockFrame.minX + trayPad + 2
                }
                trayIconFrame = NSRect(
                    x: trayStartX,
                    y: clockFrame.midY - traySize / 2,
                    width: traySize,
                    height: traySize
                )
            } else {
                trayIconFrame = .zero
            }

            if hasDiskFree {
                updateDiskFreeString()
                let fontSize = theme.dock.clockFontSize ?? max(11, iconSize * 0.45)
                let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
                let boldFont = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
                let labelW = (diskFreeLabel as NSString).size(withAttributes: [.font: font]).width
                let valueW = (diskFreeValue as NSString).size(withAttributes: [.font: boldFont]).width
                let unitW = (diskFreeUnit as NSString).size(withAttributes: [.font: font]).width
                // Layout: [pad] label [gap] [valueBox] [gap] unit [pad]
                let dfWidth: CGFloat = 8 + labelW + 6 + valueW + 8 + 6 + unitW + 8
                let isSunkenDF = theme.dock.startButtonStyle == "sunken"
                if isSunkenDF {
                    // OS/2 WarpCenter: the drive/free-space gauge sits in the MIDDLE area
                    // of the bar (between the program tabs and the clock), not glued to
                    // the far-right clock. Anchor its right edge partway between the bar
                    // centre and the clock, leaving a clear separator gap before the clock.
                    let clockLeft = clockFrame.isEmpty ? barRect.maxX : clockFrame.minX
                    let dfRight = barRect.midX + (clockLeft - barRect.midX) * 0.42
                    let dfX = max(startButtonFrame.maxX + spacing, dfRight - dfWidth)
                    diskFreeFrame = NSRect(x: dfX, y: 0, width: dfWidth, height: barRect.height)
                    // rightEdge stays at the clock — gauge no longer consumes right tray space
                } else {
                    diskFreeFrame = NSRect(x: rightEdge - dfWidth, y: 0, width: dfWidth, height: barRect.height)
                    rightEdge = diskFreeFrame.minX
                }
            } else {
                diskFreeFrame = .zero
            }

            // Win98 / XP show their open windows as elongated taskbar buttons (one per window),
            // plus a launch button for each pinned app that isn't running. Other horizontal
            // themes keep the classic icon tiles.
            let winTaskbar = (theme.dock.startMenuStyle == "classic" || theme.isXPStartMenu)
            if winTaskbar {
                // Authentic Win98/XP layout: Start | Quick Launch (pinned apps as small icon
                // tiles) | separator | task buttons (one elongated button per open window).
                let quickLaunchStart = x
                if hasShowDesktop {
                    addShowDesktopItem(frame: NSRect(x: x, y: (barRect.height - iconSize) / 2,
                                                     width: iconSize, height: iconSize),
                                       theme: theme, iconSize: iconSize)
                    x += iconSize + spacing
                }
                for app in apps {
                    let y = (barRect.height - iconSize) / 2
                    addItem(bundleID: app.bundleID,
                            frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                            theme: theme, iconSize: iconSize)
                    x += iconSize + spacing
                }
                if x > quickLaunchStart {           // had quick-launch icons → divider before tasks
                    separatorX = x - spacing / 2
                    x += spacing
                }
                // Keep the tabs clear of the systray separator. On XP the "show hidden icons"
                // chevron straddles clockFrame.minX (its left half sits in the tab area), so
                // reserve that half-width; a small gap keeps Win98 off the divider too.
                var taskRightEdge = rightEdge - 2
                if theme.isXPStartMenu { taskRightEdge -= max(14, iconSize * 0.55) * 0.9 + 4 }
                addTaskButtonStrip(startX: x, rightEdge: taskRightEdge, barRect: barRect, theme: theme, iconSize: iconSize)
            } else {
                for app in apps {
                    let y = (barRect.height - iconSize) / 2
                    addItem(bundleID: app.bundleID,
                            frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                            theme: theme, iconSize: iconSize)
                    x += iconSize + spacing
                }
                if hasShowDesktop {
                    addShowDesktopItem(frame: NSRect(x: x, y: (barRect.height - iconSize) / 2,
                                                     width: iconSize, height: iconSize),
                                       theme: theme, iconSize: iconSize)
                    x += iconSize + spacing
                }
                let transientApps = runningAppsNotInDock()
                if !transientApps.isEmpty {
                    separatorX = x - spacing / 2
                    x += spacing
                    for bid in transientApps {
                        let y = (barRect.height - iconSize) / 2
                        addItem(bundleID: bid,
                                frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                                theme: theme, iconSize: iconSize, isTransient: true)
                        x += iconSize + spacing
                    }
                }

                if hasUrlLauncher || hasTrash || hasDoomLauncher {
                    trashSeparatorX = x - spacing / 2
                    x += spacing
                    let y = (barRect.height - iconSize) / 2
                    if hasUrlLauncher {
                        addURLLauncherItem(frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                                           theme: theme, iconSize: iconSize)
                        x += iconSize + spacing
                    }
                    if hasTrash {
                        addTrashItem(frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                                     theme: theme, iconSize: iconSize)
                        x += iconSize + spacing
                    }
                    if hasDoomLauncher {
                        addDoomLauncherItem(frame: NSRect(x: x, y: y, width: doomTileWidth(iconSize), height: iconSize),
                                            theme: theme, iconSize: iconSize)
                    }
                }
            }
        }

        lastItemBundleIDs = itemViews.map { $0.bundleID }
        restCentersX = itemViews.map { $0.frame.midX }
        updateRunningIndicators()
        needsDisplay = true
    }

    func relayoutItems() {
        let apps = AppManager.shared.apps
        let transientApps = runningAppsNotInDock()
        var currentIDs = apps.map { $0.bundleID }
        if hasShowDesktop { currentIDs.append("__showdesktop__") }
        currentIDs += transientApps
        if hasUrlLauncher && !isControlStrip { currentIDs.append("__urllauncher__") }
        if hasTrash && !isControlStrip { currentIDs.append("__trash__") }
        if hasDoomLauncher && !isControlStrip { currentIDs.append("__doomlauncher__") }
        if currentIDs != lastItemBundleIDs {
            rebuildItems()
            return
        }

        guard let theme = ThemeManager.shared.activeTheme?.config else { return }
        let scale = CGFloat(AppSettings.shared.dockIconScale) * dynamicScale
        let iconSize = theme.dock.iconSize * scale
        let spacing = theme.dock.spacing * scale
        let padding = theme.dock.padding * scale
        let vertical = isVertical
        let barRect = dockBarRect

        separatorX = nil
        separatorY = nil
        trashSeparatorX = nil
        startSeparatorX = nil

        var idx = 0
        if vertical {
            // Icons are centered in the bar thickness and stacked top→bottom
            // (Finder on top, Trash at the bottom — like a real vertical dock).
            let bar = dockBarRect
            let x = bar.midX - iconSize / 2
            var y = bar.maxY - padding - gripHeight - iconSize
            for _ in apps {
                guard idx < itemViews.count else { break }
                itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
                idx += 1
                y -= iconSize + spacing
            }
            if !transientApps.isEmpty {
                separatorY = y + iconSize + spacing / 2
                y -= spacing
                for _ in transientApps {
                    guard idx < itemViews.count else { break }
                    itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
                    idx += 1
                    y -= iconSize + spacing
                }
            }
            // Trash icon (always the last item) at the bottom of the stack.
            if hasUrlLauncher, idx < itemViews.count {
                y -= spacing
                trashSeparatorX = nil
                itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
                idx += 1
                y -= iconSize
            }
            if hasTrash, idx < itemViews.count {
                y -= spacing
                trashSeparatorX = nil
                itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
                idx += 1
                y -= iconSize
            }
            if hasDoomLauncher, idx < itemViews.count {
                y -= spacing
                itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
                idx += 1
            }
            // Snapshot resting Y-centres for the frame-based magnifier (see restCentersY).
            restCentersY = itemViews.map { $0.frame.midY }
        } else if isControlStrip {
            // Mac OS 9 Control Strip relayout: left cap + icon modules + right cap
            let leftCapW = controlStripLeftCapWidth
            let arrowWidth: CGFloat = 14
            let grooveWidth: CGFloat = 2
            var x = barRect.minX + leftCapW

            startButtonFrame = .zero
            clockFrame = .zero
            trayIconFrame = .zero
            diskFreeFrame = .zero

            let transientApps = runningAppsNotInDock()
            let totalCount = apps.count + transientApps.count
            for i in 0..<apps.count {
                guard idx < itemViews.count else { break }
                let y = (barRect.height - iconSize) / 2
                itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
                idx += 1
                x += iconSize + arrowWidth
                if i < apps.count - 1 || !transientApps.isEmpty {
                    x += grooveWidth
                }
            }
            for i in 0..<transientApps.count {
                guard idx < itemViews.count else { break }
                let y = (barRect.height - iconSize) / 2
                itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
                idx += 1
                x += iconSize + arrowWidth
                if i < transientApps.count - 1 {
                    x += grooveWidth
                }
            }

        } else {
            var x = barRect.minX + padding

            if hasStartButton {
                loadStartButtonIcon()
                loadStartButtonImages()
                let isXP = theme.isXPStartMenu

                let btnHeight: CGFloat
                let btnWidth: CGFloat
                let btnY: CGFloat

                if isXP, let imgs = startButtonImages {
                    btnHeight = barRect.height
                    let sliceW = imgs.normal.size.width
                    let sliceH = imgs.normal.size.height
                    btnWidth = btnHeight * (sliceW / sliceH)
                    btnY = 0
                } else if isXP {
                    let label = theme.dock.startButtonLabel ?? "start"
                    let fontSize = max(16, barRect.height * 0.47)
                    let boldFont = NSFont.boldSystemFont(ofSize: fontSize)
                    let font = NSFont(descriptor: boldFont.fontDescriptor.withSymbolicTraits(.italic), size: fontSize) ?? boldFont
                    let labelWidth = (label as NSString).size(withAttributes: [.font: font]).width
                    let iconSz = max(24, barRect.height * 0.60)
                    btnWidth = 8 + iconSz + 3 + labelWidth + 7
                    btnHeight = barRect.height
                    btnY = 0
                } else {
                    let isSunken = theme.dock.startButtonStyle == "sunken"
                    if isSunken, let imgs = startButtonImages {
                        // OS/2 WarpCenter: bitmap-based — use sprite aspect ratio
                        btnHeight = barRect.height
                        btnY = 0
                        let sliceW = imgs.normal.size.width
                        let sliceH = imgs.normal.size.height
                        btnWidth = btnHeight * (sliceW / sliceH)
                    } else {
                        let label = theme.dock.startButtonLabel ?? "Start"
                        let fontSize = max(11, iconSize * 0.45)
                        let font = NSFont.boldSystemFont(ofSize: fontSize)
                        let iconSz = max(14, iconSize * 0.55)
                        if label.isEmpty {
                            btnWidth = 4 + iconSz + 4
                        } else {
                            let pad: CGFloat = isSunken ? 4 : 6
                            let gap: CGFloat = isSunken ? 2 : 3
                            let labelWidth = (label as NSString).size(withAttributes: [.font: font]).width
                            btnWidth = pad + iconSz + gap + labelWidth + pad
                        }
                        if isSunken {
                            btnHeight = barRect.height
                            btnY = 0
                        } else {
                            btnHeight = barRect.height - 6
                            btnY = 3
                        }
                    }
                }

                let isSunkenLayout = theme.dock.startButtonStyle == "sunken"
                startButtonFrame = NSRect(x: barRect.minX + (isXP || isSunkenLayout ? 0 : 3), y: btnY, width: btnWidth, height: btnHeight)
                x = startButtonFrame.maxX + spacing
                if isClassicTaskbar { startSeparatorX = x - spacing / 2; x += 2 }
            } else {
                startButtonFrame = .zero
            }

            // Right-side trays: clock + tray icon + disk free, positioned from right edge
            var rightEdge = barRect.maxX

            // Pre-calculate tray icon size for Win98/XP (needed to widen systray clockFrame)
            let hasTrayIcon: Bool
            let traySize: CGFloat
            let trayPad: CGFloat = 3
            if let tn = ThemeManager.shared.activeTheme?.config.name,
               (tn == "Windows 98" || tn == "Windows XP") {
                hasTrayIcon = true
                traySize = max(14, iconSize * 0.55)
            } else {
                hasTrayIcon = false
                traySize = 0
            }

            if hasClock {
                updateClockString()
                startClockTimer()
                let isXP = theme.isXPStartMenu
                let clockFontSize = theme.dock.clockFontSize ?? max(11, iconSize * 0.45)
                let clockFont = NSFont.monospacedDigitSystemFont(ofSize: clockFontSize, weight: .regular)
                let clockTextWidth = (clockString as NSString).size(withAttributes: [.font: clockFont]).width
                var clockWidth = clockTextWidth + (isXP ? 20 : 16)
                // Widen systray to include ICQ tray icon
                if hasTrayIcon {
                    clockWidth += traySize + trayPad * 2 + 2
                    // On XP the ICQ icon is shifted right past the systray chevron, so
                    // reserve the extra clearance too (chevron half-width + gap).
                    if isXP {
                        clockWidth += max(14, iconSize * 0.55) * 0.9 + 2
                    }
                }
                let isSunkenClock = theme.dock.startButtonStyle == "sunken"
                if isXP || isSunkenClock {
                    clockFrame = NSRect(x: rightEdge - clockWidth, y: 0, width: clockWidth, height: barRect.height)
                } else {
                    let clockHeight = barRect.height - 6
                    clockFrame = NSRect(x: rightEdge - clockWidth - 3, y: 3, width: clockWidth, height: clockHeight)
                }
                rightEdge = clockFrame.minX
            } else {
                clockFrame = .zero
                clockTimer?.invalidate()
                clockTimer = nil
            }

            // ICQ tray icon — inside the systray area for Windows 98 / Windows XP themes.
            // On XP the "show hidden icons" chevron is drawn centred on clockFrame.minX,
            // so it occupies the tray's left half-width. Shift the ICQ icon right past the
            // chevron's right half (≈ max(14, iconSize*0.55)*0.9) plus a small gap so they
            // don't overlap. Win98 has no chevron, so keep the tight original offset.
            if hasTrayIcon && !clockFrame.isEmpty {
                let trayStartX: CGFloat
                if theme.isXPStartMenu {
                    trayStartX = clockFrame.minX + max(14, iconSize * 0.55) * 0.9 + trayPad + 4
                } else {
                    trayStartX = clockFrame.minX + trayPad + 2
                }
                trayIconFrame = NSRect(
                    x: trayStartX,
                    y: clockFrame.midY - traySize / 2,
                    width: traySize,
                    height: traySize
                )
            } else {
                trayIconFrame = .zero
            }

            if hasDiskFree {
                updateDiskFreeString()
                let fontSize = theme.dock.clockFontSize ?? max(11, iconSize * 0.45)
                let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
                let boldFont = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
                let labelW = (diskFreeLabel as NSString).size(withAttributes: [.font: font]).width
                let valueW = (diskFreeValue as NSString).size(withAttributes: [.font: boldFont]).width
                let unitW = (diskFreeUnit as NSString).size(withAttributes: [.font: font]).width
                let dfWidth: CGFloat = 8 + labelW + 6 + valueW + 8 + 6 + unitW + 8
                let isSunkenDF = theme.dock.startButtonStyle == "sunken"
                if isSunkenDF {
                    // OS/2 WarpCenter: the drive/free-space gauge sits in the MIDDLE area
                    // of the bar (between the program tabs and the clock), not glued to
                    // the far-right clock. Keep this in sync with rebuildItems().
                    let clockLeft = clockFrame.isEmpty ? barRect.maxX : clockFrame.minX
                    let dfRight = barRect.midX + (clockLeft - barRect.midX) * 0.42
                    let dfX = max(startButtonFrame.maxX + spacing, dfRight - dfWidth)
                    diskFreeFrame = NSRect(x: dfX, y: 0, width: dfWidth, height: barRect.height)
                } else {
                    diskFreeFrame = NSRect(x: rightEdge - dfWidth, y: 0, width: dfWidth, height: barRect.height)
                    rightEdge = diskFreeFrame.minX
                }
            } else {
                diskFreeFrame = .zero
            }

            for _ in apps {
                guard idx < itemViews.count else { break }
                let y = (barRect.height - iconSize) / 2
                itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
                idx += 1
                x += iconSize + spacing
            }
            if hasShowDesktop, idx < itemViews.count {
                let y = (barRect.height - iconSize) / 2
                itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
                idx += 1
                x += iconSize + spacing
            }
            if !transientApps.isEmpty {
                separatorX = x - spacing / 2
                x += spacing
                for _ in transientApps {
                    guard idx < itemViews.count else { break }
                    let y = (barRect.height - iconSize) / 2
                    itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
                    idx += 1
                    x += iconSize + spacing
                }
            }
            if (hasUrlLauncher || hasTrash || hasDoomLauncher) && idx < itemViews.count {
                trashSeparatorX = x - spacing / 2
                x += spacing
                let y = (barRect.height - iconSize) / 2
                if hasUrlLauncher, idx < itemViews.count {
                    itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
                    idx += 1
                    x += iconSize + spacing
                }
                if hasTrash, idx < itemViews.count {
                    itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
                    idx += 1
                    x += iconSize + spacing
                }
                if hasDoomLauncher, idx < itemViews.count {
                    itemViews[idx].frame = NSRect(x: x, y: y, width: doomTileWidth(iconSize), height: iconSize)
                    idx += 1
                }
            }
        }

        restCentersX = itemViews.map { $0.frame.midX }
        needsDisplay = true
    }

    private func addItem(bundleID: String, frame: NSRect, theme: DockThemeConfig, iconSize: CGFloat, isTransient: Bool = false) {
        let itemView = DockItemView(bundleID: bundleID, frame: frame)
        itemView.magnificationEnabled = theme.hasMagnification && AppSettings.shared.dockMagnification

        // Check if this is a folder item
        if let app = AppManager.shared.apps.first(where: { $0.bundleID == bundleID }), app.isFolder,
           let folderPath = app.folderPath {
            let icon = folderIcon(path: folderPath, size: iconSize)
            itemView.updateIcon(icon)
            itemView.updateTheme(theme)
            itemView.onLeftClick = { [weak itemView] _ in
                // Themes with folder stacks fan out the folder's recent files; otherwise
                // a click just opens the folder in Finder.
                guard theme.hasFolderStacks, let itemView = itemView, let win = itemView.window else {
                    NSWorkspace.shared.open(URL(fileURLWithPath: folderPath)); return
                }
                let rect = win.convertToScreen(itemView.convert(itemView.bounds, to: nil))
                DockStackController.shared.toggle(folderPath: folderPath, anchorScreenRect: rect)
            }
        } else {
            let icon: NSImage
            if isTransient && ThemeManager.shared.customIconPath(for: bundleID) == nil
                && !theme.isPixelated && theme.icon.monochrome != true {
                // Transient (running) apps show their real system icon unless user set a
                // custom one — except in pixel/monochrome themes, where icon(for:)
                // pixelates/desaturates the real icon so the whole dock stays consistent.
                icon = ThemeManager.shared.systemIcon(for: bundleID, size: iconSize)
            } else {
                icon = ThemeManager.shared.icon(for: bundleID, size: iconSize)
            }
            itemView.updateIcon(icon)
            itemView.updateTheme(theme)
            itemView.onLeftClick = { [weak self] bid in
                // With the system Dock hidden, the app tile is how minimized windows
                // come back: de-miniaturize them before activating (macOS behavior).
                MinimizedWindowTracker.shared.restoreWindows(for: bid)
                AppLauncher.launchOrActivate(bundleID: bid)
                self?.updateRunningIndicators()
            }
        }
        itemView.onRightClick = { [weak self] bid, point in
            self?.onContextMenu?(bid, point)
        }
        addSubview(itemView)
        itemViews.append(itemView)
    }

    private func folderIcon(path: String, size: CGFloat) -> NSImage {
        // Themed Downloads icon (e.g. Maiks Favourite's retro folder.icns), shown crisp.
        if let downloads = try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
           URL(fileURLWithPath: path).standardizedFileURL == downloads.standardizedFileURL,
           let dir = ThemeManager.shared.activeTheme?.iconsDirectory {
            let custom = dir.appendingPathComponent("downloads.icns")
            if let img = NSImage(contentsOf: custom) {
                img.size = NSSize(width: size, height: size)
                return img
            }
        }
        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: size, height: size)
        return img
    }

    private func addTrashItem(frame: NSRect, theme: DockThemeConfig, iconSize: CGFloat) {
        let item = DockItemView(bundleID: "__trash__", frame: frame)
        item.magnificationEnabled = theme.hasMagnification && AppSettings.shared.dockMagnification
        let icon = trashIcon(size: iconSize)
        item.updateIcon(icon)
        item.updateTheme(theme)
        item.onLeftClick = { _ in
            if let trashURL = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
                NSWorkspace.shared.open(trashURL)
            }
        }
        item.onRightClick = { [weak self] bid, point in
            self?.onContextMenu?(bid, point)
        }
        addSubview(item)
        itemViews.append(item)
    }

    static let urlLauncherDefault = "https://myretromac.app"
    static var urlLauncherURL: String {
        UserDefaults.standard.string(forKey: "urlLauncherURL") ?? urlLauncherDefault
    }

    // MARK: - Win98/XP task buttons

    /// One elongated taskbar button per open window (Win98/XP), plus a launch button for each
    /// pinned app that isn't running. Fills the bar from `startX` up to the right-side trays.
    private func addTaskButtonStrip(startX: CGFloat, rightEdge: CGFloat, barRect: NSRect, theme: DockThemeConfig, iconSize: CGFloat) {
        let style: TaskButtonView.Style = theme.isXPStartMenu ? .winxp : .win98
        let models = buildTaskModels()
        guard !models.isEmpty else { return }
        let gap: CGFloat = 2
        let available = max(0, rightEdge - startX - gap)
        let n = CGFloat(models.count)
        var bw = (available - gap * (n - 1)) / n
        bw = min(160, max(40, bw))
        let h = barRect.height - 4
        let y = (barRect.height - h) / 2
        var x = startX
        for m in models {
            if x + bw > rightEdge { break }   // don't draw under the trays
            let btn = TaskButtonView(frame: NSRect(x: x, y: y, width: bw, height: h),
                                     title: m.label, icon: m.icon, style: style, isActive: m.active,
                                     // Quick Launch icons render inset by 2px (DockItemView) → their
                                     // visible size is iconSize-4; cap tab icons to that, never larger.
                                     maxIconSize: max(0, iconSize - 4))
            let wasActive = m.active
            btn.onClick = { [weak self, weak btn] in
                m.action()
                // Immediate feedback: clicking an active window minimizes it (→ inactive);
                // clicking any other window raises it (→ active, others cleared). The 1.5s
                // tracker poll reconciles the real state afterwards.
                guard let self = self, let btn = btn else { return }
                if wasActive {
                    btn.setActive(false)
                } else {
                    for v in self.taskButtonViews { v.setActive(v === btn) }
                }
            }
            addSubview(btn)
            taskButtonViews.append(btn)
            x += bw + gap
        }
    }

    /// One task button per open window. Pinned apps already appear as Quick-Launch icon tiles,
    /// so they are NOT repeated here as launch buttons — only their open windows show (exactly
    /// like real Windows, where a quick-launch icon and its taskbar button are separate). Pinned
    /// apps' windows are grouped first for a stable order, then any remaining windows.
    private func buildTaskModels() -> [(label: String, icon: NSImage?, active: Bool, action: () -> Void)] {
        var models: [(label: String, icon: NSImage?, active: Bool, action: () -> Void)] = []
        let all = MinimizedWindowTracker.shared.allWindows
        let pinnedBundles = Set(AppManager.shared.apps.map { $0.bundleID })
        for bid in AppManager.shared.apps.map({ $0.bundleID }) {
            for w in all where w.bundleID == bid { models.append(windowModel(w)) }
        }
        for w in all where !pinnedBundles.contains(w.bundleID) {
            models.append(windowModel(w))
        }
        return models
    }

    private func windowModel(_ w: MinimizedWindowTracker.Entry) -> (label: String, icon: NSImage?, active: Bool, action: () -> Void) {
        // Use the themed icon (respects the theme's custom icon mapping / pixelation),
        // not the raw system icon, so program tabs match the rest of the themed dock.
        let icon = ThemeManager.shared.icon(for: w.bundleID, size: 18)
        // Active (focused, non-minimized) → minimize; minimized or background → restore + raise.
        return (w.title, icon, w.isFocused && !w.isMinimized, {
            if !w.isMinimized && w.isFocused { MinimizedWindowTracker.shared.minimize(w) }
            else { MinimizedWindowTracker.shared.activate(w) }
        })
    }

    private func appDisplayName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    private func addURLLauncherItem(frame: NSRect, theme: DockThemeConfig, iconSize: CGFloat) {
        let item = DockItemView(bundleID: "__urllauncher__", frame: frame)
        item.magnificationEnabled = theme.hasMagnification && AppSettings.shared.dockMagnification
        if let dir = ThemeManager.shared.activeTheme?.iconsDirectory {
            let url = dir.appendingPathComponent("genericurl.png")
            if let img = NSImage(contentsOf: url) {
                img.size = NSSize(width: iconSize, height: iconSize)
                item.updateIcon(img)
            }
        }
        item.updateTheme(theme)
        item.onLeftClick = { _ in
            if let u = URL(string: DockView.urlLauncherURL) { NSWorkspace.shared.open(u) }
        }
        item.onRightClick = { [weak self] bid, point in
            self?.onContextMenu?(bid, point)
        }
        addSubview(item)
        itemViews.append(item)
    }

    /// DOOM logo launcher tile — sits right of the trash (Maiks Favourite II). Click launches
    /// DOOM (auto-detected) or the program configured in Settings.
    private func addDoomLauncherItem(frame: NSRect, theme: DockThemeConfig, iconSize: CGFloat) {
        let item = DockItemView(bundleID: "__doomlauncher__", frame: frame)
        item.magnificationEnabled = theme.hasMagnification && AppSettings.shared.dockMagnification
        if let url = ThemeManager.shared.activeTheme?.url.appendingPathComponent("doom-logo.png"),
           let img = NSImage(contentsOf: url) {
            item.updateIcon(img)
        }
        item.updateTheme(theme)
        item.onLeftClick = { _ in DockView.launchDoom() }
        item.onRightClick = { [weak self] bid, point in self?.onContextMenu?(bid, point) }
        addSubview(item)
        itemViews.append(item)
    }

    /// Launch DOOM for the dock tile: prefer an installed DOOM app, else the configured
    /// program (Settings ▸ Dock), else a gentle beep.
    static func launchDoom() {
        let ws = NSWorkspace.shared
        // 1) Auto-detect an installed DOOM app in the usual application folders.
        let dirs = ["/Applications",
                    NSHomeDirectory() + "/Applications",
                    "/Applications/Utilities"]
        for dir in dirs {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for n in names where n.hasSuffix(".app") && n.lowercased().contains("doom") {
                ws.open(URL(fileURLWithPath: dir).appendingPathComponent(n)); return
            }
        }
        // 2) Configured fallback: an app path or a bundle identifier.
        let target = AppSettings.shared.doomLaunchTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        if !target.isEmpty {
            if target.hasPrefix("/") {
                ws.open(URL(fileURLWithPath: target)); return
            }
            if let u = ws.urlForApplication(withBundleIdentifier: target) {
                ws.open(u); return
            }
        }
        // 3) Nothing found.
        NSSound.beep()
    }

    /// Win98 Quick-Launch "Show Desktop": hides every regular app (toggle restores them).
    private static var showDesktopHidden: [NSRunningApplication] = []

    static func toggleShowDesktop() {
        if showDesktopHidden.isEmpty {
            let own = Bundle.main.bundleIdentifier
            for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular && app.bundleIdentifier != own && !app.isHidden {
                if app.hide() { showDesktopHidden.append(app) }
            }
        } else {
            for app in showDesktopHidden { app.unhide() }
            showDesktopHidden.removeAll()
        }
    }

    /// Un-hide any apps that "Show Desktop" hid, without toggling. Called when the Show
    /// Desktop tile goes away (theme switch, dock stop, app quit) so apps never stay hidden
    /// with no way to bring them back.
    static func restoreShowDesktop() {
        guard !showDesktopHidden.isEmpty else { return }
        for app in showDesktopHidden { app.unhide() }
        showDesktopHidden.removeAll()
    }

    private func addShowDesktopItem(frame: NSRect, theme: DockThemeConfig, iconSize: CGFloat) {
        let item = DockItemView(bundleID: "__showdesktop__", frame: frame)
        item.magnificationEnabled = theme.hasMagnification && AppSettings.shared.dockMagnification
        if let dir = ThemeManager.shared.activeTheme?.iconsDirectory,
           let img = NSImage(contentsOf: dir.appendingPathComponent("showdesktop.png")) {
            img.size = NSSize(width: iconSize, height: iconSize)
            item.updateIcon(img)
        }
        item.updateTheme(theme)
        item.toolTip = "Show Desktop"
        item.onLeftClick = { _ in DockView.toggleShowDesktop() }
        item.onRightClick = { [weak self] bid, point in self?.onContextMenu?(bid, point) }
        addSubview(item)
        itemViews.append(item)
    }

    private func trashIcon(size: CGFloat) -> NSImage {
        // Pixelate for pixel themes so the trash matches the rest of the dock.
        return ThemeManager.shared.pixelatedIfNeeded(rawTrashIcon(size: size), size: size)
    }

    private func rawTrashIcon(size: CGFloat) -> NSImage {
        let trashFull = !isTrashEmpty()

        // Try theme-specific trash icon first (trash_full.png / trash.png)
        if let themeBundle = ThemeManager.shared.activeTheme {
            let iconsDir = themeBundle.iconsDirectory
            if trashFull {
                // Try trash_full first, fall back to trash (empty) icon
                let fullURL = iconsDir.appendingPathComponent("trash_full.png")
                if let img = NSImage(contentsOf: fullURL) {
                    img.size = NSSize(width: size, height: size)
                    return img
                }
            }
            let trashURL = iconsDir.appendingPathComponent("trash.png")
            if let img = NSImage(contentsOf: trashURL) {
                img.size = NSSize(width: size, height: size)
                return img
            }
        }
        // Fallback: AppKit's authentic Aqua trash images, which DO reflect full vs.
        // empty (the .Trash *folder* icon from NSWorkspace does not, so we avoid it).
        let sysName = trashFull ? "NSTrashFull" : "NSTrashEmpty"
        if let img = NSImage(named: NSImage.Name(sysName)) {
            let copy = img.copy() as! NSImage
            copy.size = NSSize(width: size, height: size)
            return copy
        }
        // Last resort: the static folder icon.
        let trashPath = (FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")).path
        let sysIcon = NSWorkspace.shared.icon(forFile: trashPath)
        sysIcon.size = NSSize(width: size, height: size)
        return sysIcon
    }

    var onRunningAppsChanged: (() -> Void)?
    private var isRebuilding = false

    func updateRunningIndicators() {
        let running = Set(
            NSWorkspace.shared.runningApplications
                .compactMap { $0.bundleIdentifier }
        )

        let changed = running != runningBundleIDs
        runningBundleIDs = running

        guard let theme = ThemeManager.shared.activeTheme?.config else { return }
        // Control Strip does NOT show running app indicator dots, but still needs rebuild
        if !theme.isControlStrip {
            for item in itemViews {
                if item.bundleID == "__trash__" || item.bundleID.hasPrefix("__folder__") { continue }
                item.setRunningIndicator(visible: running.contains(item.bundleID), theme: theme)
            }
        }

        if changed && AppSettings.shared.dockShowRunningApps && !isRebuilding {
            isRebuilding = true
            onRunningAppsChanged?()
            isRebuilding = false
        }
    }

    func requiredWidth() -> CGFloat {
        guard let theme = ThemeManager.shared.activeTheme?.config else { return 200 }
        let scale = CGFloat(AppSettings.shared.dockIconScale)
        let iconSize = theme.dock.iconSize * scale
        let spacing = theme.dock.spacing * scale
        let padding = theme.dock.padding * scale

        // Control Strip: left cap PNG + icon modules + right cap PNG
        if isControlStrip {
            loadControlStripCaps()
            let leftCapW = controlStripLeftCapWidth
            if controlStripCollapsed {
                return leftCapW
            }
            let grooveWidth: CGFloat = 2    // 1px dark + 1px light
            let arrowWidth: CGFloat = 14    // ▶ arrow after each icon
            let rightCapW = controlStripRightCapWidth
            let pinnedCount = CGFloat(AppManager.shared.apps.count)
            let transientCount = CGFloat(runningAppsNotInDock().count)
            let totalCount = pinnedCount + transientCount
            let modulesWidth = totalCount * (iconSize + arrowWidth) + max(0, totalCount - 1) * grooveWidth
            return leftCapW + modulesWidth + rightCapW
        }

        let pinnedCount = CGFloat(AppManager.shared.apps.count)
        var width = padding * 2 + pinnedCount * iconSize + max(0, pinnedCount - 1) * spacing

        if hasShowDesktop {
            width += iconSize + spacing + 4   // tile + start-button groove allowance
        }
        let transientApps = runningAppsNotInDock()
        if !transientApps.isEmpty {
            width += spacing + CGFloat(transientApps.count) * (iconSize + spacing)
        }
        if hasUrlLauncher {
            width += spacing + iconSize
        }
        if hasTrash {
            width += spacing + iconSize + spacing
        }
        if hasDoomLauncher {
            width += spacing + doomTileWidth(iconSize)   // trailing padding is symmetric with the leading edge
        }

        // For vertical docks with grip, add grip height
        if isVertical && hasGrip {
            width += gripHeight
        }

        return width
    }

    private func runningAppsNotInDock() -> [String] {
        let pinnedIDs = Set(AppManager.shared.apps.map { $0.bundleID })
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""

        // Apps that currently have minimized windows MUST get a tile regardless of the
        // "show running apps" toggle: the system Dock is hidden, so the tile is the only
        // way to bring those windows back (clicking it calls restoreWindows(for:)).
        let minimizedIDs = Set(MinimizedWindowTracker.shared.entries
            .map { $0.bundleID }
            .filter { !pinnedIDs.contains($0) && $0 != ownBundleID })

        guard AppSettings.shared.dockShowRunningApps else {
            return minimizedIDs.sorted()
        }

        var ids = Set(NSWorkspace.shared.runningApplications
            .filter { app in
                guard let bid = app.bundleIdentifier,
                      !pinnedIDs.contains(bid),
                      bid != ownBundleID,
                      app.activationPolicy == .regular else { return false }
                return true
            }
            .compactMap { $0.bundleIdentifier })
        ids.formUnion(minimizedIDs)   // a minimized non-pinned app must never be missing
        return ids.sorted()
    }

    // MARK: - Drawing

    // MARK: - Pac-Man pellet border (layer-based)
    //
    // Pellets and Pac-Man live in dedicated CAShapeLayers on top of the dock, so the
    // animation NEVER re-rasterizes the whole dock view. A low-rate (15fps) timer moves
    // only those small layers; perimeter geometry + pellet positions are cached and only
    // recomputed when the bar rect (or on/off state) changes. The timer is paused whenever
    // the dock window isn't visible (covered / other Space / display asleep).

    private func ensurePacmanLayers() {
        guard pelletLayer == nil else { return }
        let pl = CAShapeLayer()
        pl.zPosition = 5
        pl.actions = ["path": NSNull()]   // no implicit path fades when pellets get eaten
        layer?.addSublayer(pl)
        pelletLayer = pl
        let pc = CAShapeLayer()
        pc.zPosition = 6
        pc.fillColor = NSColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0).cgColor
        layer?.addSublayer(pc)
        pacLayer = pc
    }

    private func tearDownPacmanLayers() {
        pacmanTimer?.invalidate(); pacmanTimer = nil
        clearClockLabels()
        clearGhosts()
        pacmanIsClock = false
        pelletLayer?.removeFromSuperlayer(); pelletLayer = nil
        pacLayer?.removeFromSuperlayer(); pacLayer = nil
        pacmanConfiguredRect = .zero
        pacmanConfiguredAnimated = nil
        pacmanConfiguredClock = nil
    }

    /// Called from draw() while the pacman-border theme is active. (Re)configures the
    /// layers only when the bar rect or on/off state changed; otherwise the timer keeps
    /// the existing layers moving without any dock redraw.
    private func updatePacmanBorder(rect: NSRect, scale: CGFloat) {
        ensurePacmanLayers()
        let animated = AppSettings.shared.pacmanAnimationEnabled
        let clock = AppSettings.shared.pacmanClockMode
        guard !rect.equalTo(pacmanConfiguredRect)
              || pacmanConfiguredAnimated != animated
              || pacmanConfiguredClock != clock else { return }
        configurePacmanGeometry(rect: rect, scale: scale, animated: animated)
    }

    private func configurePacmanGeometry(rect: NSRect, scale: CGFloat, animated: Bool) {
        pacmanConfiguredRect = rect
        pacmanConfiguredAnimated = animated

        let inset: CGFloat = 11 * scale   // margin between the border elements and the dock edge
        let spacing: CGFloat = 16 * scale
        pacPelletR = (animated ? 2.2 : 1.6) * scale
        pacRadius = 7 * scale
        let f = rect.insetBy(dx: inset, dy: inset)
        guard f.width > 4 * pacRadius, f.height > 2 * pacRadius else {
            pelletLayer?.path = nil; pacLayer?.path = nil; return
        }
        let tl = CGPoint(x: f.minX, y: f.maxY), tr = CGPoint(x: f.maxX, y: f.maxY)
        let br = CGPoint(x: f.maxX, y: f.minY), bl = CGPoint(x: f.minX, y: f.minY)
        pacPerimSegs = [(tl, tr), (tr, br), (br, bl), (bl, tl)]
        pacPerimLen = pacPerimSegs.map { hypot($0.1.x - $0.0.x, $0.1.y - $0.0.y) }
        pacPerim = pacPerimLen.reduce(0, +)
        pacTopLen = pacPerimLen.first ?? 0
        pacPelletDists = []
        var d: CGFloat = 0
        while d < pacPerim { pacPelletDists.append(d); d += spacing }

        pelletLayer?.frame = bounds
        pelletLayer?.fillColor = (animated ? NSColor(white: 0.95, alpha: 0.9)
                                           : NSColor(white: 0.55, alpha: 0.5)).cgColor
        pacLayer?.bounds = CGRect(x: 0, y: 0, width: pacRadius * 2, height: pacRadius * 2)

        pacmanPhase = 0
        pacLastEatenCount = -1
        pacDist = 0
        pacDir = 1
        pacBlockCooldown = 0
        eatenPellets.removeAll()
        pacmanConfiguredClock = AppSettings.shared.pacmanClockMode
        clearGhosts()   // reset on any reconfigure / mode switch

        if animated && AppSettings.shared.pacmanClockMode {
            configurePacmanClock()
        } else if animated {
            pacmanIsClock = false
            clearClockLabels()
            rebuildPellets(eatenUpTo: 0)
            updatePac(dist: 0, mouthDeg: 35, animateMove: false)
            startPacmanTimerIfVisible()
        } else {
            pacmanIsClock = false
            clearClockLabels()
            pacmanTimer?.invalidate(); pacmanTimer = nil
            rebuildPellets(eatenUpTo: -1)                       // all pellets visible
            updatePac(dist: pacTopLen / 3.0, mouthDeg: 30, animateMove: false)  // static, ~⅓ along top
        }
    }

    // MARK: - Clock mode (dots → 24 hour numbers, Pac-Man is the hand)

    private func clearClockLabels() {
        clockLabelLayers.forEach { $0.removeFromSuperlayer() }
        clockLabelLayers = []
    }

    private func configurePacmanClock() {
        pacmanIsClock = true
        clearClockLabels()
        pacmanTimer?.invalidate(); pacmanTimer = nil
        guard pacPerim > 0 else { return }

        // Full dot ring stays (same look as the run mode). 24 hour numbers are placed
        // around the dock but all hidden except the CURRENT hour ("current slot");
        // Pac-Man is the hand sitting on the current time. Dots are not eaten.
        pacPelletR *= 0.7   // smaller, less obtrusive in clock mode
        pelletLayer?.fillColor = NSColor(white: 0.62, alpha: 0.4).cgColor
        rebuildPellets(eatenUpTo: -1)   // all dots visible (dim + small)

        let hours = 24
        let fontSize = max(13, pacRadius * 2.4)
        let labelFont = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        for h in 0..<hours {
            let d = clockHourDist(h)
            let lab = CATextLayer()
            lab.string = "\(h)"
            lab.font = labelFont.fontName as CFString
            lab.fontSize = fontSize
            lab.foregroundColor = NSColor(white: 0.98, alpha: 1).cgColor
            lab.alignmentMode = .center
            lab.contentsScale = window?.backingScaleFactor ?? 2
            lab.bounds = CGRect(x: 0, y: 0, width: fontSize * 2.6, height: fontSize * 1.3)
            lab.position = pointOnPerimeter(d).0
            lab.opacity = 0   // hidden until it's the current slot
            lab.actions = ["opacity": NSNull(), "position": NSNull(), "bounds": NSNull(),
                           "contents": NSNull(), "string": NSNull()]
            layer?.addSublayer(lab)
            clockLabelLayers.append(lab)
        }
        lastClockHour = -1
        updateClockPac()
        startPacmanTimerIfVisible()
    }

    /// Hour `h` mapped around the dock with 06:00 at the start (far-left), wrapping once
    /// around per day.
    private func clockHourDist(_ h: Int) -> CGFloat {
        let idx = ((h - 6) % 24 + 24) % 24
        return CGFloat(idx) / 24.0 * pacPerim
    }

    /// Show the two current hours (current + next); move the Pac-Man hand to the current time.
    private func updateClockPac() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let hour = c.hour ?? 0, minute = c.minute ?? 0
        if hour != lastClockHour {
            lastClockHour = hour
            let next = (hour + 1) % 24
            for (i, lab) in clockLabelLayers.enumerated() { lab.opacity = (i == hour || i == next) ? 1 : 0 }
        }
        // Pac-Man at the current time on the 06:00-anchored scale, snapped to 15 min.
        let totalMin = hour * 60 + minute
        let step = (totalMin / 15) * 15
        let minSince6 = ((step - 6 * 60) % 1440 + 1440) % 1440
        let pacDist = CGFloat(minSince6) / 1440.0 * pacPerim
        updatePac(dist: pacDist, mouthDeg: 32, animateMove: true)
    }

    // MARK: - Ghosts (chase Pac-Man, spawned on icon hover)

    /// Spawn a random-coloured ghost near a hovered icon; it will chase Pac-Man.
    /// Only in the running animation (not clock/static), max 2 at a time.
    func spawnGhostNearItem(frame: CGRect) {
        guard AppSettings.shared.pacmanAnimationEnabled, !AppSettings.shared.pacmanClockMode,
              !pacmanIsClock, pacPerim > 0, pelletLayer != nil, ghosts.count < maxGhosts else { return }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let g = PacGhost(dist: nearestPerimeterDist(to: center))
        g.dir = pacDir
        configureGhost(g)
        g.body.position = pointOnPerimeter(g.dist).0
        layer?.addSublayer(g.body)
        ghosts.append(g)
        startPacmanTimerIfVisible()   // ensure the tick is running to animate the chase
    }

    private func clearGhosts() {
        ghosts.forEach { $0.body.removeFromSuperlayer() }
        ghosts = []
        barrierDists.removeAll()
        // Reset cherry / power state so a fresh run starts clean.
        removeCherry()
        poweredUntilPhase = -1
        nextCherryPhase = 150
    }

    private func nearestPerimeterDist(to p: CGPoint) -> CGFloat {
        var best: CGFloat = 0, bestSq = CGFloat.greatestFiniteMagnitude
        var d: CGFloat = 0
        while d < pacPerim {
            let q = pointOnPerimeter(d).0
            let sq = (q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y)
            if sq < bestSq { bestSq = sq; best = d }
            d += 8
        }
        return best
    }

    private func loadGhostImageIfNeeded() {
        if ghostCGImage != nil { return }
        guard let dir = ThemeManager.shared.activeTheme?.iconsDirectory,
              let img = NSImage(contentsOf: dir.appendingPathComponent("ghost.png")) else { return }
        var rect = CGRect(origin: .zero, size: img.size)
        ghostCGImage = img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private func configureGhost(_ g: PacGhost) {
        loadGhostImageIfNeeded()
        g.body.zPosition = 7   // above pellets(5) and Pac-Man(6)
        g.body.actions = ["position": NSNull(), "path": NSNull(), "contents": NSNull()]
        g.body.sublayers?.forEach { $0.removeFromSuperlayer() }
        if let img = ghostCGImage {
            // Ghost image at Pac-Man's size.
            let size = pacRadius * 2.0
            g.body.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            g.body.path = nil
            g.body.fillColor = nil
            g.body.contents = img
            g.body.contentsGravity = .resizeAspect
        } else {
            // Fallback: drawn random-colour ghost.
            let gr = pacRadius * 0.95, gw = gr * 2, gh = gr * 2.3
            g.body.bounds = CGRect(x: 0, y: 0, width: gw, height: gh)
            g.body.contents = nil
            g.body.path = ghostPath(gr: gr, gw: gw, gh: gh)
            g.body.fillColor = NSColor(hue: .random(in: 0...1), saturation: 0.85, brightness: 0.95, alpha: 0.95).cgColor
            let er = gr * 0.3
            for ex in [gr * 0.62, gr * 1.38] {
                let eye = CALayer()
                eye.frame = CGRect(x: ex - er, y: gh - gr * 0.95 - er, width: er * 2, height: er * 2)
                eye.cornerRadius = er
                eye.backgroundColor = NSColor.white.cgColor
                g.body.addSublayer(eye)
            }
        }
    }

    private func ghostPath(gr: CGFloat, gw: CGFloat, gh: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let footY = gr * 0.5
        p.move(to: CGPoint(x: 0, y: footY))
        p.addLine(to: CGPoint(x: 0, y: gh - gr))
        p.addArc(center: CGPoint(x: gr, y: gh - gr), radius: gr, startAngle: .pi, endAngle: 0, clockwise: false)
        p.addLine(to: CGPoint(x: gw, y: footY))
        let humps = 3
        let hw = gw / CGFloat(humps)
        for i in 0..<humps {
            let xR = gw - CGFloat(i) * hw
            let xL = gw - CGFloat(i + 1) * hw
            p.addLine(to: CGPoint(x: xR, y: footY))
            p.addQuadCurve(to: CGPoint(x: xL, y: footY), control: CGPoint(x: (xR + xL) / 2, y: -gr * 0.15))
        }
        p.closeSubpath()
        return p
    }

    /// Advance ghosts toward Pac-Man (faster than him, via the shorter arc); a ghost that
    /// reaches him "catches" him → it vanishes and Pac-Man respawns at the start.
    private func perimGap(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        guard pacPerim > 0 else { return 0 }
        let g = (a - b + pacPerim).truncatingRemainder(dividingBy: pacPerim)
        return min(g, pacPerim - g)
    }

    /// Signed shortest perimeter offset of `a` relative to `b` (range ±perim/2).
    private func signedOffset(_ a: CGFloat, from b: CGFloat) -> CGFloat {
        guard pacPerim > 0 else { return 0 }
        var d = (a - b).truncatingRemainder(dividingBy: pacPerim)
        if d > pacPerim / 2 { d -= pacPerim }
        if d < -pacPerim / 2 { d += pacPerim }
        return d
    }

    /// Distance from `pos` to the nearest hovered-icon barrier travelling in `dir`.
    private func barrierGapAhead(pos: CGFloat, dir: CGFloat) -> CGFloat {
        guard pacPerim > 0, !barrierDists.isEmpty else { return .greatestFiniteMagnitude }
        var best = CGFloat.greatestFiniteMagnitude
        for b in barrierDists.values {
            let gap = dir >= 0
                ? (b - pos + pacPerim).truncatingRemainder(dividingBy: pacPerim)
                : (pos - b + pacPerim).truncatingRemainder(dividingBy: pacPerim)
            if gap < best { best = gap }
        }
        return best
    }

    private func wrapDist(_ d: CGFloat) -> CGFloat {
        guard pacPerim > 0 else { return 0 }
        return (d.truncatingRemainder(dividingBy: pacPerim) + pacPerim).truncatingRemainder(dividingBy: pacPerim)
    }

    /// Set/clear a barrier at the perimeter point nearest a hovered icon (run mode only).
    func setHoverBarrier(bundleID: String, frame: CGRect, active: Bool) {
        guard pacPerim > 0, !pacmanIsClock else { barrierDists.removeValue(forKey: bundleID); return }
        if active {
            let c = CGPoint(x: frame.midX, y: frame.midY)
            barrierDists[bundleID] = nearestPerimeterDist(to: c)
        } else {
            barrierDists.removeValue(forKey: bundleID)
        }
    }

    /// Run-mode pellets: hide the ones Pac-Man has eaten (tracked as a set so eating works
    /// in both directions); refill once the whole loop is cleared.
    private func rebuildPelletsEaten() {
        guard let pl = pelletLayer else { return }
        let path = CGMutablePath()
        for (i, d) in pacPelletDists.enumerated() where !eatenPellets.contains(i) {
            let (p, _) = pointOnPerimeter(d)
            path.addEllipse(in: CGRect(x: p.x - pacPelletR, y: p.y - pacPelletR,
                                       width: pacPelletR * 2, height: pacPelletR * 2))
        }
        pl.path = path
    }

    private func updateGhosts(pacDist: CGFloat, powered: Bool) {
        guard pacPerim > 0, !ghosts.isEmpty else { return }
        let catchDist = pacRadius + 4
        var survivors: [PacGhost] = []
        for g in ghosts {
            let speed: CGFloat = powered ? 4.4 * 1.35 * 0.6   // flee slower than Pac-Man
                                         : 4.4 * 1.35         // chase a bit faster
            g.body.opacity = powered ? 0.5 : 1.0

            // Pick the desired direction (unless we're still committed to a recent bounce).
            if g.blockCooldown > 0 {
                g.blockCooldown -= 1
            } else if powered {
                // Flee: move away from Pac-Man (opposite the shorter arc toward him).
                g.dir = signedOffset(pacDist, from: g.dist) >= 0 ? -1 : 1
            } else {
                // Chase from behind: travel the same way Pac-Man is going.
                g.dir = pacDir
            }

            // A hovered icon ahead blocks the ghost → it turns around (player influence).
            if barrierGapAhead(pos: g.dist, dir: g.dir) <= speed + pacRadius {
                g.dir = -g.dir
                g.blockCooldown = 10
            }
            g.dist = wrapDist(g.dist + g.dir * speed)

            let gap = perimGap(pacDist, g.dist)
            if powered {
                if gap < catchDist { g.body.removeFromSuperlayer(); continue }   // eaten
            } else if gap < catchDist {
                g.body.removeFromSuperlayer()   // caught Pac-Man
                pacmanPhase = 0
                self.pacDist = 0; pacDir = 1; pacBlockCooldown = 0   // respawn at the start
                continue
            }

            CATransaction.begin()
            CATransaction.setAnimationDuration(1.0 / 15.0)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
            g.body.position = pointOnPerimeter(g.dist).0
            CATransaction.commit()
            survivors.append(g)
        }
        ghosts = survivors
    }

    // MARK: - Cherry power-up

    private func removeCherry() { cherryLayer?.removeFromSuperlayer(); cherryLayer = nil }

    private func maybeSpawnCherry(pacDist: CGFloat) {
        guard cherryLayer == nil, pacmanPhase >= nextCherryPhase, pacPerim > 0 else { return }
        cherryDist = (pacDist + pacPerim * CGFloat.random(in: 0.3...0.6)).truncatingRemainder(dividingBy: pacPerim)
        let c = buildCherryLayer()
        c.position = pointOnPerimeter(cherryDist).0
        layer?.addSublayer(c)
        cherryLayer = c
    }

    private func buildCherryLayer() -> CALayer {
        let sz = pacRadius * 1.7
        let c = CALayer()
        c.bounds = CGRect(x: 0, y: 0, width: sz, height: sz)
        c.zPosition = 6.5
        c.actions = ["position": NSNull()]
        let r = sz * 0.26
        let berries = CAShapeLayer()
        let bp = CGMutablePath()
        bp.addEllipse(in: CGRect(x: sz * 0.10, y: sz * 0.06, width: r * 2, height: r * 2))
        bp.addEllipse(in: CGRect(x: sz * 0.50, y: sz * 0.06, width: r * 2, height: r * 2))
        berries.path = bp
        berries.fillColor = NSColor.systemRed.cgColor
        berries.frame = c.bounds
        c.addSublayer(berries)
        let stems = CAShapeLayer()
        let sp = CGMutablePath()
        let top = CGPoint(x: sz * 0.70, y: sz * 0.94)
        sp.move(to: CGPoint(x: sz * 0.10 + r, y: sz * 0.06 + r * 1.6)); sp.addQuadCurve(to: top, control: CGPoint(x: sz * 0.34, y: sz * 0.70))
        sp.move(to: CGPoint(x: sz * 0.50 + r, y: sz * 0.06 + r * 1.6)); sp.addQuadCurve(to: top, control: CGPoint(x: sz * 0.72, y: sz * 0.62))
        stems.path = sp
        stems.strokeColor = NSColor.systemGreen.cgColor
        stems.fillColor = nil
        stems.lineWidth = max(1, sz * 0.06)
        stems.frame = c.bounds
        c.addSublayer(stems)
        return c
    }

    private func pacWedgePath(mouthDeg: CGFloat) -> CGPath {
        let c = CGPoint(x: pacRadius, y: pacRadius)
        let p = CGMutablePath()
        p.move(to: c)
        p.addArc(center: c, radius: pacRadius,
                 startAngle: mouthDeg * .pi / 180, endAngle: (360 - mouthDeg) * .pi / 180, clockwise: false)
        p.closeSubpath()
        return p
    }

    private func pointOnPerimeter(_ dist: CGFloat) -> (CGPoint, CGFloat) {
        guard pacPerim > 0 else { return (.zero, 0) }
        var d = dist.truncatingRemainder(dividingBy: pacPerim); if d < 0 { d += pacPerim }
        for (i, s) in pacPerimSegs.enumerated() {
            if d <= pacPerimLen[i] || i == pacPerimSegs.count - 1 {
                let t = pacPerimLen[i] == 0 ? 0 : min(1, d / pacPerimLen[i])
                let p = CGPoint(x: s.0.x + (s.1.x - s.0.x) * t, y: s.0.y + (s.1.y - s.0.y) * t)
                return (p, atan2(s.1.y - s.0.y, s.1.x - s.0.x))
            }
            d -= pacPerimLen[i]
        }
        return (pacPerimSegs.first?.0 ?? .zero, 0)
    }

    /// Set Pac-Man path (mouth) + position + rotation. `animateMove` smooths the 15fps
    /// step over 1/15s so the render server interpolates to ~display rate.
    private func updatePac(dist: CGFloat, mouthDeg: CGFloat, animateMove: Bool, facing: CGFloat = 1) {
        guard let pac = pacLayer else { return }
        let (pt, angRad) = pointOnPerimeter(dist)
        CATransaction.begin()
        if animateMove {
            CATransaction.setAnimationDuration(1.0 / 15.0)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        } else {
            CATransaction.setDisableActions(true)
        }
        pac.path = pacWedgePath(mouthDeg: mouthDeg)
        pac.position = pt
        // Flip the mouth to point along the actual travel direction when reversed.
        pac.setAffineTransform(CGAffineTransform(rotationAngle: angRad + (facing < 0 ? .pi : 0)))
        CATransaction.commit()
    }

    /// eatenUpTo < 0 → all pellets; else hide pellets behind Pac-Man (dist < pacDist).
    private func rebuildPellets(eatenUpTo pacDist: CGFloat) {
        guard let pl = pelletLayer else { return }
        let path = CGMutablePath()
        for d in pacPelletDists where !(pacDist >= 0 && d < pacDist) {
            let (p, _) = pointOnPerimeter(d)
            path.addEllipse(in: CGRect(x: p.x - pacPelletR, y: p.y - pacPelletR,
                                       width: pacPelletR * 2, height: pacPelletR * 2))
        }
        pl.path = path
    }

    private func startPacmanTimerIfVisible() {
        guard pacmanTimer == nil, pacmanShouldAnimate else { return }
        // Clock mode only needs to refresh the hand every ~30s (15-min steps); the
        // run-around mode needs 15fps for smooth motion.
        let interval = pacmanIsClock ? 30.0 : 1.0 / 15.0
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.pacmanIsClock { self.updateClockPac() } else { self.pacmanTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        pacmanTimer = t
    }

    private func pacmanTick() {
        guard pacPerim > 0 else { return }
        pacmanPhase += 1
        let speedPerTick: CGFloat = 4.4   // ~66 px/s at 15fps

        // Barrier handling: a hovered icon ahead reverses Pac-Man. A short cooldown after a
        // bounce prevents jittering in the barrier's catch band.
        if pacBlockCooldown > 0 {
            pacBlockCooldown -= 1
        } else if barrierGapAhead(pos: pacDist, dir: pacDir) <= speedPerTick + pacRadius {
            pacDir = -pacDir
            pacBlockCooldown = 8
        }
        pacDist = wrapDist(pacDist + pacDir * speedPerTick)

        let mouth = (sin(pacmanPhase * 0.5) * 0.5 + 0.5) * 38.0 + 2.0
        updatePac(dist: pacDist, mouthDeg: mouth, animateMove: true, facing: pacDir)

        // Eat any pellet Pac-Man is currently on (direction-independent).
        for (i, d) in pacPelletDists.enumerated() where !eatenPellets.contains(i) {
            if perimGap(d, pacDist) < pacRadius { eatenPellets.insert(i) }
        }
        if eatenPellets.count != pacLastEatenCount {
            pacLastEatenCount = eatenPellets.count
            rebuildPelletsEaten()
        }
        if !pacPelletDists.isEmpty, eatenPellets.count >= pacPelletDists.count {
            eatenPellets.removeAll()          // whole loop cleared → refill
            pacLastEatenCount = 0
            rebuildPelletsEaten()
        }

        // Cherry power-up: spawn sporadically; eating it lets Pac-Man hunt the ghosts.
        maybeSpawnCherry(pacDist: pacDist)
        if cherryLayer != nil, perimGap(cherryDist, pacDist) < pacRadius + 4 {
            removeCherry()
            poweredUntilPhase = pacmanPhase + 120                         // ~8s of power
            nextCherryPhase = pacmanPhase + CGFloat.random(in: 300...600) // next cherry in 20–40s
        }
        updateGhosts(pacDist: pacDist, powered: pacmanPhase < poweredUntilPhase)
    }

    /// Should the animation be running right now? (Theme on, animation enabled, dock visible.)
    private var pacmanShouldAnimate: Bool {
        guard AppSettings.shared.pacmanAnimationEnabled,
              ThemeManager.shared.activeTheme?.config.dock.borderStyle == "pacman",
              ThemeManager.shared.activeTheme?.config.isVertical == false else { return false }
        if let w = window { return w.occlusionState.contains(.visible) }
        return true
    }

    /// Pause/resume from the window-occlusion observer (covered window / other Space / sleep).
    func refreshPacmanAnimationState() {
        if pacmanShouldAnimate { startPacmanTimerIfVisible() }
        else { pacmanTimer?.invalidate(); pacmanTimer = nil }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let theme = ThemeManager.shared.activeTheme?.config else { return }
        let ctx = NSGraphicsContext.current!.cgContext
        let scale = CGFloat(AppSettings.shared.dockIconScale)
        // The real Windows XP Luna start bar and the classic Mac Control Strip are fully
        // opaque — never apply the transparency slider to them.
        let bgAlpha = (theme.isXPStartMenu || theme.isControlStrip) ? 1.0 : CGFloat(AppSettings.shared.dockTransparency)

        let rect = currentBarRect  // Draw background — expands during magnification
        let cr = theme.dock.cornerRadius * scale

        // ── Mac OS 9 Control Strip ──────────────────────────────────────
        if theme.isControlStrip {
            drawControlStrip(ctx: ctx, theme: theme, barRect: rect, bgAlpha: bgAlpha)
            return
        }

        // Background color with user transparency applied
        let bgColor = theme.parsedBackgroundColor.withAlphaComponent(
            theme.parsedBackgroundColor.alphaComponent * bgAlpha
        )

        // Build background path first (3D shelf uses trapezoid, flat uses rounded rect)
        // Vertical docks: flush (square) on the screen-edge side, rounded on the
        // other three, with the border drawn on those three sides only.
        var verticalBorderPath: NSBezierPath?
        let bgPath: NSBezierPath
        // 3D shelf is drawn SHORT — only the lower part of the bar — so icons (placed
        // with their centre on the shelf top) stick out halfway above it. Keep this
        // fraction in sync with the 3D floorY in the layout code.
        let shelfRect = theme.has3DShelf
            ? NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.55)
            : rect
        if theme.isVertical {
            let paths = verticalBarPaths(rect: rect, radius: cr)
            bgPath = paths.fill
            verticalBorderPath = paths.border
        } else if theme.has3DShelf {
            // Snow Leopard glass shelf: side walls converge toward the back (top).
            // Target angles measured from the real dock (from vertical): left 26.7°,
            // right 27.9°. inset = shelf height * tan(angle). Asymmetric on purpose.
            let leftInset  = shelfRect.height * CGFloat(tan(26.7 * Double.pi / 180))
            let rightInset = shelfRect.height * CGFloat(tan(27.9 * Double.pi / 180))
            bgPath = NSBezierPath()
            bgPath.move(to: NSPoint(x: shelfRect.minX, y: shelfRect.minY))
            bgPath.line(to: NSPoint(x: shelfRect.maxX, y: shelfRect.minY))
            bgPath.line(to: NSPoint(x: shelfRect.maxX - rightInset, y: shelfRect.maxY))
            bgPath.line(to: NSPoint(x: shelfRect.minX + leftInset, y: shelfRect.maxY))
            bgPath.close()
        } else {
            bgPath = NSBezierPath(roundedRect: rect, xRadius: cr, yRadius: cr)
        }

        // Shadow (uses the actual bgPath so it matches trapezoid shape)
        if theme.dock.shadowEnabled {
            ctx.saveGState()
            let shadowColor = theme.parsedShadowColor.cgColor
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: theme.dock.shadowRadius, color: shadowColor)
            bgColor.setFill()
            bgPath.fill()
            ctx.restoreGState()
        }
        if theme.hasGradientBackground,
           let gradTop = theme.parsedGradientTop?.withAlphaComponent(
               (theme.parsedGradientTop?.alphaComponent ?? 1) * bgAlpha),
           let gradBottom = theme.parsedGradientBottom?.withAlphaComponent(
               (theme.parsedGradientBottom?.alphaComponent ?? 1) * bgAlpha) {
            ctx.saveGState()
            bgPath.addClip()
            let gradient = NSGradient(starting: gradBottom, ending: gradTop)
            gradient?.draw(in: rect, angle: 90)
            ctx.restoreGState()
        } else {
            bgColor.setFill()
            bgPath.fill()
        }

        // Aqua pinstripe texture: fine horizontal lines over the (clipped) background.
        if theme.dock.pinstripe == true {
            ctx.saveGState()
            bgPath.addClip()
            NSColor.white.withAlphaComponent(0.07 * bgAlpha).setStroke()
            let pen = NSBezierPath(); pen.lineWidth = 1
            var yy = rect.minY + 1.5
            while yy < rect.maxY {
                pen.move(to: NSPoint(x: rect.minX, y: yy))
                pen.line(to: NSPoint(x: rect.maxX, y: yy))
                yy += 2
            }
            pen.stroke()
            ctx.restoreGState()
        }

        // Windows XP Luna taskbar: a bright highlight line along the very top edge + a thin
        // gloss band just below it, the way the real Luna start bar catches the light.
        if theme.isXPStartMenu && !theme.isVertical {
            ctx.saveGState()
            bgPath.addClip()
            NSColor(srgbRed: 0.62, green: 0.82, blue: 1.0, alpha: 0.9 * bgAlpha).setFill()
            ctx.fill(NSRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 1))
            NSColor.white.withAlphaComponent(0.16 * bgAlpha).setFill()
            ctx.fill(NSRect(x: rect.minX, y: rect.maxY - 4, width: rect.width, height: 3))
            ctx.restoreGState()
        }

        // 3D shelf: glass highlight on upper portion
        if theme.has3DShelf && !theme.isVertical {
            let topInset = shelfRect.height * 0.15
            let glassHeight = shelfRect.height * 0.4
            let glassRect = NSRect(x: shelfRect.minX + topInset * 0.6, y: shelfRect.maxY - glassHeight,
                                   width: shelfRect.width - topInset * 1.2, height: glassHeight)
            ctx.saveGState()
            bgPath.addClip()
            let glass = NSGradient(colors: [
                NSColor.white.withAlphaComponent(0.15 * bgAlpha),
                NSColor.white.withAlphaComponent(0.02 * bgAlpha),
            ])
            glass?.draw(in: glassRect, angle: 90)
            ctx.restoreGState()
        }

        // Shelf highlight line (horizontal floor — only for bottom docks)
        if let shelfColor = theme.parsedShelfLineColor, !theme.isVertical {
            shelfColor.withAlphaComponent(shelfColor.alphaComponent * bgAlpha).setStroke()
            let shelfLine = NSBezierPath()
            let shelfY = shelfRect.minY + shelfRect.height * 0.38
            shelfLine.move(to: NSPoint(x: shelfRect.minX + cr, y: shelfY))
            shelfLine.line(to: NSPoint(x: shelfRect.maxX - cr, y: shelfY))
            shelfLine.lineWidth = 1
            shelfLine.stroke()
        }

        // 3D bevel (for Platinum / Win95 themes)
        if theme.dock.bevelWidth > 0 {
            let bw = theme.dock.bevelWidth
            if let topColor = theme.parsedBevelTopColor {
                topColor.setStroke()
                let topLine = NSBezierPath()
                topLine.move(to: NSPoint(x: rect.minX + cr, y: rect.maxY - bw / 2))
                topLine.line(to: NSPoint(x: rect.maxX - cr, y: rect.maxY - bw / 2))
                topLine.lineWidth = bw
                topLine.stroke()

                let leftLine = NSBezierPath()
                leftLine.move(to: NSPoint(x: rect.minX + bw / 2, y: rect.minY + cr))
                leftLine.line(to: NSPoint(x: rect.minX + bw / 2, y: rect.maxY - cr))
                leftLine.lineWidth = bw
                leftLine.stroke()
            }
            if let bottomColor = theme.parsedBevelBottomColor {
                bottomColor.setStroke()
                let bottomLine = NSBezierPath()
                bottomLine.move(to: NSPoint(x: rect.minX + cr, y: rect.minY + bw / 2))
                bottomLine.line(to: NSPoint(x: rect.maxX - cr, y: rect.minY + bw / 2))
                bottomLine.lineWidth = bw
                bottomLine.stroke()

                let rightLine = NSBezierPath()
                rightLine.move(to: NSPoint(x: rect.maxX - bw / 2, y: rect.minY + cr))
                rightLine.line(to: NSPoint(x: rect.maxX - bw / 2, y: rect.maxY - cr))
                rightLine.lineWidth = bw
                rightLine.stroke()
            }
        }

        // Border — vertical docks stroke only the 3 visible sides (top, bottom, and
        // the interior side toward screen center); the screen-edge side stays flush.
        if theme.dock.borderWidth > 0 {
            theme.parsedBorderColor.setStroke()
            let strokePath = verticalBorderPath ?? bgPath
            strokePath.lineWidth = theme.dock.borderWidth
            strokePath.stroke()
        }

        // Pac-Man pellet border — drawn via dedicated CALayers (see updatePacmanBorder),
        // not into this view's backing, so the animation never re-rasterizes the dock.
        if theme.dock.borderStyle == "pacman", !theme.isVertical {
            updatePacmanBorder(rect: rect, scale: scale)
            doomSlayer.teardown()
        } else if theme.dock.borderStyle == "doomslayer", !theme.isVertical, let host = layer {
            doomSlayer.update(host: host, view: self, barRect: rect, scale: scale)
            tearDownPacmanLayers()
        } else {
            tearDownPacmanLayers()
            doomSlayer.teardown()
        }

        // Grip dots handle (BeOS deskbar style)
        if theme.hasGrip && theme.isVertical {
            let gripHeight: CGFloat = 18
            let gripY = rect.maxY - gripHeight - 3
            let dotSize: CGFloat = 2
            let dotSpacing: CGFloat = 4
            let centerX = rect.midX
            let cols = 3
            let rows = 3
            let totalW = CGFloat(cols - 1) * dotSpacing
            let totalH = CGFloat(rows - 1) * dotSpacing
            let startX = centerX - totalW / 2
            let startY = gripY + (gripHeight - totalH) / 2
            for row in 0..<rows {
                for col in 0..<cols {
                    let dx = startX + CGFloat(col) * dotSpacing
                    let dy = startY + CGFloat(row) * dotSpacing
                    // Light dot (highlight)
                    NSColor.white.setFill()
                    NSBezierPath(ovalIn: NSRect(x: dx - dotSize / 2, y: dy - dotSize / 2 + 0.5,
                                                width: dotSize, height: dotSize)).fill()
                    // Dark dot (shadow)
                    NSColor(white: 0.55, alpha: 1).setFill()
                    NSBezierPath(ovalIn: NSRect(x: dx - dotSize / 2 + 0.5, y: dy - dotSize / 2,
                                                width: dotSize, height: dotSize)).fill()
                }
            }
        }

        // Vertical taskbar separators. Win98 (classic start menu) draws the authentic
        // etched groove (1px shadow + 1px highlight, almost full bar height).
        func drawTaskbarSeparator(atX sx: CGFloat) {
            if theme.dock.startMenuStyle == "classic" {
                NSColor(white: 0.50, alpha: 1).setFill()
                NSBezierPath(rect: NSRect(x: sx - 1, y: rect.minY + 3, width: 1, height: rect.height - 6)).fill()
                NSColor.white.setFill()
                NSBezierPath(rect: NSRect(x: sx, y: rect.minY + 3, width: 1, height: rect.height - 6)).fill()
            } else {
                let sepColor = theme.parsedBorderColor.withAlphaComponent(0.4)
                sepColor.setFill()
                // Span only the (possibly shortened 3D) shelf so it doesn't poke out the top.
                NSBezierPath(roundedRect: NSRect(x: sx - 0.5, y: shelfRect.minY + shelfRect.height * 0.15,
                                                 width: 1, height: shelfRect.height * 0.7),
                             xRadius: 0.5, yRadius: 0.5).fill()
            }
        }
        if let startSepX = startSeparatorX { drawTaskbarSeparator(atX: startSepX) }
        // Separator between pinned (quick launch) and running apps
        if let sepX = separatorX { drawTaskbarSeparator(atX: sepX) }
        if let sepY = separatorY {
            let sepColor = theme.parsedBorderColor.withAlphaComponent(0.4)
            sepColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.width * 0.15, y: sepY - 0.5, width: rect.width * 0.7, height: 1),
                         xRadius: 0.5, yRadius: 0.5).fill()
        }
        if let trashSepX = trashSeparatorX { drawTaskbarSeparator(atX: trashSepX) }

        // Drop insertion indicator
        if let idx = dropInsertionIndex {
            let iconSize = theme.dock.iconSize * scale
            let spacing = theme.dock.spacing * scale
            let padding = theme.dock.padding * scale
            NSColor.controlAccentColor.setFill()
            if isVertical {
                let topY = dockBarRect.maxY - padding - gripHeight
                let y = topY - CGFloat(idx) * (iconSize + spacing) + spacing / 2
                NSBezierPath(roundedRect: NSRect(x: rect.minX + 4, y: y - 1, width: rect.width - 8, height: 2),
                             xRadius: 1, yRadius: 1).fill()
            } else {
                let startOffset = hasStartButton && !startButtonFrame.isEmpty
                    ? startButtonFrame.maxX + theme.dock.spacing * scale
                    : padding
                let x = startOffset + CGFloat(idx) * (iconSize + spacing) - spacing / 2
                NSBezierPath(roundedRect: NSRect(x: x - 1, y: 4, width: 2, height: rect.height - 8),
                             xRadius: 1, yRadius: 1).fill()
            }
        }

        // OS/2 WarpCenter: draw sunken trays around each dock icon
        if theme.dock.startButtonStyle == "sunken" {
            let dark = NSColor(calibratedWhite: 0.502, alpha: 1)   // #808080
            let vdark = NSColor(calibratedWhite: 0.25, alpha: 1)   // #404040
            let light = NSColor.white
            let trayPad: CGFloat = 2  // padding around icon inside tray

            for item in itemViews {
                let f = item.frame
                let tr = NSRect(x: f.minX - trayPad, y: f.minY - trayPad,
                                width: f.width + trayPad * 2, height: f.height + trayPad * 2)
                // Fill
                NSColor(calibratedWhite: 0.753, alpha: 1).setFill()
                NSBezierPath(rect: tr).fill()
                // Outer: dark top+left, white bottom+right
                dark.setStroke()
                var line = NSBezierPath()
                line.move(to: NSPoint(x: tr.minX, y: tr.maxY - 0.5))
                line.line(to: NSPoint(x: tr.maxX, y: tr.maxY - 0.5))
                line.lineWidth = 1; line.stroke()
                line = NSBezierPath()
                line.move(to: NSPoint(x: tr.minX + 0.5, y: tr.minY))
                line.line(to: NSPoint(x: tr.minX + 0.5, y: tr.maxY))
                line.lineWidth = 1; line.stroke()
                light.setStroke()
                line = NSBezierPath()
                line.move(to: NSPoint(x: tr.minX, y: tr.minY + 0.5))
                line.line(to: NSPoint(x: tr.maxX, y: tr.minY + 0.5))
                line.lineWidth = 1; line.stroke()
                line = NSBezierPath()
                line.move(to: NSPoint(x: tr.maxX - 0.5, y: tr.minY))
                line.line(to: NSPoint(x: tr.maxX - 0.5, y: tr.maxY))
                line.lineWidth = 1; line.stroke()
                // Inner shadow
                vdark.setStroke()
                line = NSBezierPath()
                line.move(to: NSPoint(x: tr.minX + 1, y: tr.maxY - 1.5))
                line.line(to: NSPoint(x: tr.maxX - 1, y: tr.maxY - 1.5))
                line.lineWidth = 1; line.stroke()
                line = NSBezierPath()
                line.move(to: NSPoint(x: tr.minX + 1.5, y: tr.minY + 1))
                line.line(to: NSPoint(x: tr.minX + 1.5, y: tr.maxY - 1))
                line.lineWidth = 1; line.stroke()
            }
        }

        // Start button (themed: XP uses green gradient + rounded, classic uses gray bevel)
        if hasStartButton && !startButtonFrame.isEmpty {
            let iconSize = theme.dock.iconSize * scale
            let pressOffset: CGFloat = startButtonPressed ? 1 : 0
            let isXPStyle = theme.isXPStartMenu

            if isXPStyle {
                // XP Luna start button
                let btnRect = startButtonFrame
                let btnH = btnRect.height

                // Draw background: bitmap sprite sheet or fallback gradient
                if let imgs = startButtonImages {
                    let stateImage: NSImage
                    if startButtonPressed {
                        stateImage = imgs.pressed
                    } else if startButtonHovered {
                        stateImage = imgs.hover
                    } else {
                        stateImage = imgs.normal
                    }
                    stateImage.draw(in: btnRect,
                                    from: NSRect(origin: .zero, size: stateImage.size),
                                    operation: .sourceOver, fraction: 1.0,
                                    respectFlipped: true,
                                    hints: [.interpolation: NSImageInterpolation.high.rawValue])
                } else {
                    // Authentic XP Luna green start button: glossy, rounded pill, hover-lift.
                    var gTop = theme.dock.startButtonGradientTop.map { NSColor.fromHex($0) }
                        ?? NSColor(red: 0.38, green: 0.76, blue: 0.25, alpha: 1.0)
                    var gBot = theme.dock.startButtonGradientBottom.map { NSColor.fromHex($0) }
                        ?? NSColor(red: 0.17, green: 0.49, blue: 0.09, alpha: 1.0)
                    if startButtonHovered && !startButtonPressed {
                        gTop = gTop.blended(withFraction: 0.18, of: .white) ?? gTop
                        gBot = gBot.blended(withFraction: 0.10, of: .white) ?? gBot
                    }
                    let top = startButtonPressed ? gBot : gTop
                    let bottom = startButtonPressed ? gTop : gBot
                    let btnPath = NSBezierPath(roundedRect: btnRect, xRadius: 6, yRadius: 6)
                    NSGradient(starting: bottom, ending: top)?.draw(in: btnPath, angle: 90)
                    // glossy white highlight over the top ~half
                    NSGraphicsContext.current?.saveGraphicsState(); btnPath.addClip()
                    let gloss = NSRect(x: btnRect.minX, y: btnRect.midY,
                                       width: btnRect.width, height: btnRect.height * 0.5)
                    NSGradient(starting: NSColor.white.withAlphaComponent(0),
                               ending: NSColor.white.withAlphaComponent(startButtonPressed ? 0.12 : 0.42))?
                        .draw(in: gloss, angle: 90)
                    NSGraphicsContext.current?.restoreGraphicsState()
                    // light inner edge + dark outline for the beveled look
                    NSColor.white.withAlphaComponent(0.5).setStroke()
                    NSBezierPath(roundedRect: btnRect.insetBy(dx: 0.75, dy: 0.75), xRadius: 5, yRadius: 5).stroke()
                    NSColor(red: 0.12, green: 0.34, blue: 0.06, alpha: 0.85).setStroke()
                    btnPath.stroke()
                }

                // The bitmap sprite already bakes in the flag + "start"; only the programmatic
                // green fallback needs the flag/label overlay below.
                if startButtonImages == nil {
                // Windows flag icon — large, proportional to button height
                let iconSz = max(20, btnH * 0.52)
                if let icon = startButtonIcon {
                    let iconRect = NSRect(
                        x: btnRect.minX + 8 + pressOffset,
                        y: btnRect.midY - iconSz / 2 - pressOffset,
                        width: iconSz, height: iconSz)
                    icon.draw(in: iconRect)
                }

                // "start" label — white bold italic with shadow
                let label = theme.dock.startButtonLabel ?? "start"
                let fontSize = max(15, btnH * 0.46)
                let boldFont = NSFont.boldSystemFont(ofSize: fontSize)
                let italicFont = NSFont(descriptor: boldFont.fontDescriptor.withSymbolicTraits(.italic),
                                        size: fontSize) ?? boldFont
                let shadow = NSShadow()
                shadow.shadowColor = NSColor(white: 0, alpha: 0.5)
                shadow.shadowOffset = NSSize(width: 1, height: -1)
                shadow.shadowBlurRadius = 1
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: italicFont,
                    .foregroundColor: NSColor.white,
                    .shadow: shadow,
                ]
                let labelSize = (label as NSString).size(withAttributes: attrs)
                let labelX = btnRect.minX + 8 + iconSz + 3 + pressOffset
                let labelY = btnRect.midY - labelSize.height / 2 - pressOffset
                (label as NSString).draw(at: NSPoint(x: labelX, y: labelY), withAttributes: attrs)
                }   // end programmatic-fallback flag + label
            } else {
                let btnStyle = theme.dock.startButtonStyle ?? "raised"
                let bw: CGFloat = btnStyle == "flat" ? 0 : (theme.dock.bevelWidth > 0 ? theme.dock.bevelWidth : 1)

                if btnStyle == "sunken" {
                    // OS/2 WarpCenter: bitmap-based start button
                    // The sprite sheet contains the complete button graphic
                    // (sunken tray + OS/2 WARP text, all baked in)
                    if let imgs = startButtonImages {
                        let stateImage: NSImage
                        if startButtonPressed {
                            stateImage = imgs.pressed
                        } else if startButtonHovered {
                            stateImage = imgs.hover
                        } else {
                            stateImage = imgs.normal
                        }
                        stateImage.draw(in: startButtonFrame,
                                        from: NSRect(origin: .zero, size: stateImage.size),
                                        operation: .sourceOver, fraction: 1.0,
                                        respectFlipped: true,
                                        hints: [.interpolation: NSImageInterpolation.high.rawValue])
                    } else {
                        // Fallback: procedural sunken tray
                        let r = startButtonFrame
                        let bg: NSColor = startButtonPressed
                            ? NSColor(calibratedWhite: 0.72, alpha: 1)
                            : NSColor(calibratedWhite: 0.753, alpha: 1)
                        bg.setFill()
                        NSBezierPath(rect: r).fill()

                        let dark = NSColor(calibratedWhite: 0.502, alpha: 1)
                        let vdark = NSColor(calibratedWhite: 0.25, alpha: 1)
                        let light = NSColor.white
                        dark.setStroke()
                        var line = NSBezierPath()
                        line.move(to: NSPoint(x: r.minX, y: r.maxY - 0.5))
                        line.line(to: NSPoint(x: r.maxX, y: r.maxY - 0.5))
                        line.lineWidth = 1; line.stroke()
                        line = NSBezierPath()
                        line.move(to: NSPoint(x: r.minX + 0.5, y: r.minY))
                        line.line(to: NSPoint(x: r.minX + 0.5, y: r.maxY))
                        line.lineWidth = 1; line.stroke()
                        light.setStroke()
                        line = NSBezierPath()
                        line.move(to: NSPoint(x: r.minX, y: r.minY + 0.5))
                        line.line(to: NSPoint(x: r.maxX, y: r.minY + 0.5))
                        line.lineWidth = 1; line.stroke()
                        line = NSBezierPath()
                        line.move(to: NSPoint(x: r.maxX - 0.5, y: r.minY))
                        line.line(to: NSPoint(x: r.maxX - 0.5, y: r.maxY))
                        line.lineWidth = 1; line.stroke()
                        vdark.setStroke()
                        line = NSBezierPath()
                        line.move(to: NSPoint(x: r.minX + 1, y: r.maxY - 1.5))
                        line.line(to: NSPoint(x: r.maxX - 1, y: r.maxY - 1.5))
                        line.lineWidth = 1; line.stroke()
                        line = NSBezierPath()
                        line.move(to: NSPoint(x: r.minX + 1.5, y: r.minY + 1))
                        line.line(to: NSPoint(x: r.minX + 1.5, y: r.maxY - 1))
                        line.lineWidth = 1; line.stroke()
                    }
                } else if btnStyle == "flat" {
                    // Flat: no bevel, just background
                    NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1).setFill()
                    NSBezierPath(rect: startButtonFrame).fill()
                } else {
                    // Classic Win98 raised: light top-left, dark bottom-right
                    let lightColor: NSColor = startButtonPressed ? NSColor(white: 0.5, alpha: 1) : .white
                    let darkColor: NSColor = startButtonPressed ? .white : NSColor(white: 0.5, alpha: 1)

                    NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1).setFill()
                    NSBezierPath(rect: startButtonFrame).fill()

                    lightColor.setStroke()
                    var bevelLine = NSBezierPath()
                    bevelLine.move(to: NSPoint(x: startButtonFrame.minX, y: startButtonFrame.maxY - bw / 2))
                    bevelLine.line(to: NSPoint(x: startButtonFrame.maxX, y: startButtonFrame.maxY - bw / 2))
                    bevelLine.lineWidth = bw
                    bevelLine.stroke()
                    bevelLine = NSBezierPath()
                    bevelLine.move(to: NSPoint(x: startButtonFrame.minX + bw / 2, y: startButtonFrame.minY))
                    bevelLine.line(to: NSPoint(x: startButtonFrame.minX + bw / 2, y: startButtonFrame.maxY))
                    bevelLine.lineWidth = bw
                    bevelLine.stroke()

                    darkColor.setStroke()
                    bevelLine = NSBezierPath()
                    bevelLine.move(to: NSPoint(x: startButtonFrame.minX, y: startButtonFrame.minY + bw / 2))
                    bevelLine.line(to: NSPoint(x: startButtonFrame.maxX, y: startButtonFrame.minY + bw / 2))
                    bevelLine.lineWidth = bw
                    bevelLine.stroke()
                    bevelLine = NSBezierPath()
                    bevelLine.move(to: NSPoint(x: startButtonFrame.maxX - bw / 2, y: startButtonFrame.minY))
                    bevelLine.line(to: NSPoint(x: startButtonFrame.maxX - bw / 2, y: startButtonFrame.maxY))
                    bevelLine.lineWidth = bw
                    bevelLine.stroke()
                }

                // Only draw procedural icon+label when NOT using bitmap sprite sheet
                if !(btnStyle == "sunken" && startButtonImages != nil) {
                    let isSunkenBtn = btnStyle == "sunken"
                    let iconSz = max(18, iconSize * (isSunkenBtn ? 0.60 : 0.78))
                    let iconPad: CGFloat = isSunkenBtn ? 3 : 5
                    let iconGap: CGFloat = isSunkenBtn ? 2 : 3
                    if let icon = startButtonIcon {
                        let label = theme.dock.startButtonLabel ?? "Start"
                        let iconX: CGFloat
                        if label.isEmpty {
                            iconX = startButtonFrame.midX - iconSz / 2 + pressOffset
                        } else {
                            iconX = startButtonFrame.minX + iconPad + pressOffset
                        }
                        let iconRect = NSRect(
                            x: iconX,
                            y: startButtonFrame.midY - iconSz / 2 - pressOffset,
                            width: iconSz, height: iconSz)
                        icon.draw(in: iconRect)
                    }

                    let label = theme.dock.startButtonLabel ?? "Start"
                    if !label.isEmpty {
                        let font = NSFont.boldSystemFont(ofSize: max(13, iconSize * 0.55))
                        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
                        let labelSize = (label as NSString).size(withAttributes: attrs)
                        let labelX = startButtonFrame.minX + iconPad + iconSz + iconGap + pressOffset
                        let labelY = startButtonFrame.midY - labelSize.height / 2 - pressOffset
                        (label as NSString).draw(at: NSPoint(x: labelX, y: labelY), withAttributes: attrs)
                    }
                }
            }
        }

        // Clock / System tray
        if hasClock && !clockFrame.isEmpty {
            let isXPClock = theme.isXPStartMenu

            if isXPClock {
                // XP Luna system tray: lighter blue gradient background
                let trayGradTop = NSColor(red: 0.16, green: 0.48, blue: 0.87, alpha: 1.0)
                let trayGradBottom = NSColor(red: 0.08, green: 0.33, blue: 0.73, alpha: 1.0)
                let trayPath = NSBezierPath(rect: clockFrame)
                if let grad = NSGradient(starting: trayGradBottom, ending: trayGradTop) {
                    grad.draw(in: trayPath, angle: 90)
                }
                // Left border: subtle darker line to separate from taskbar
                NSColor(red: 0.06, green: 0.20, blue: 0.60, alpha: 1.0).setStroke()
                var sepLine = NSBezierPath()
                sepLine.move(to: NSPoint(x: clockFrame.minX, y: clockFrame.minY + 2))
                sepLine.line(to: NSPoint(x: clockFrame.minX, y: clockFrame.maxY - 2))
                sepLine.lineWidth = 1
                sepLine.stroke()
                // Highlight line right of separator
                NSColor(red: 0.30, green: 0.55, blue: 0.90, alpha: 1.0).setStroke()
                sepLine = NSBezierPath()
                sepLine.move(to: NSPoint(x: clockFrame.minX + 1, y: clockFrame.minY + 2))
                sepLine.line(to: NSPoint(x: clockFrame.minX + 1, y: clockFrame.maxY - 2))
                sepLine.lineWidth = 1
                sepLine.stroke()

                let clockFontSize = max(11, theme.dock.iconSize * scale * 0.45)
                let font = NSFont.monospacedDigitSystemFont(ofSize: clockFontSize, weight: .regular)
                let shadow = NSShadow()
                shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
                shadow.shadowOffset = NSSize(width: 1, height: -1)
                shadow.shadowBlurRadius = 0
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.white,
                    .shadow: shadow,
                ]
                let timeSize = (clockString as NSString).size(withAttributes: attrs)
                let tx = clockFrame.maxX - timeSize.width - 10
                let ty = clockFrame.midY - timeSize.height / 2
                (clockString as NSString).draw(at: NSPoint(x: tx, y: ty), withAttributes: attrs)

                // XP notification-area "show hidden icons" chevron. On real Windows XP
                // Luna, the round "«" button straddles the notification area's left-edge
                // separator — half overlapping the tray, half in the taskbar — and is
                // vertically centred. We draw it centred ON the separator at
                // clockFrame.minX (the divider drawn above), vertically centred.
                if let arrow = NSImage(contentsOf: ThemeManager.shared.activeTheme!.iconsDirectory.appendingPathComponent("systray-arrow.png")) {
                    let aspect = arrow.size.width > 0 ? arrow.size.width / arrow.size.height : 1
                    let ah = max(14, theme.dock.iconSize * scale * 0.55)
                    let aw = ah * aspect
                    let arrowRect = NSRect(x: clockFrame.minX - aw / 2,
                                           y: clockFrame.midY - ah / 2, width: aw, height: ah)
                    arrow.draw(in: arrowRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                }
            } else {
                let isSunkenClock = theme.dock.startButtonStyle == "sunken"

                if isSunkenClock {
                    // OS/2 WarpCenter: clock in sunken tray (eingedrückte Mulde)
                    let cr = clockFrame
                    NSColor(calibratedWhite: 0.753, alpha: 1).setFill()
                    NSBezierPath(rect: cr).fill()

                    let dark = NSColor(calibratedWhite: 0.502, alpha: 1)
                    let vdark = NSColor(calibratedWhite: 0.25, alpha: 1)
                    let light = NSColor.white

                    dark.setStroke()
                    var line = NSBezierPath()
                    line.move(to: NSPoint(x: cr.minX, y: cr.maxY - 0.5))
                    line.line(to: NSPoint(x: cr.maxX, y: cr.maxY - 0.5))
                    line.lineWidth = 1; line.stroke()
                    line = NSBezierPath()
                    line.move(to: NSPoint(x: cr.minX + 0.5, y: cr.minY))
                    line.line(to: NSPoint(x: cr.minX + 0.5, y: cr.maxY))
                    line.lineWidth = 1; line.stroke()

                    light.setStroke()
                    line = NSBezierPath()
                    line.move(to: NSPoint(x: cr.minX, y: cr.minY + 0.5))
                    line.line(to: NSPoint(x: cr.maxX, y: cr.minY + 0.5))
                    line.lineWidth = 1; line.stroke()
                    line = NSBezierPath()
                    line.move(to: NSPoint(x: cr.maxX - 0.5, y: cr.minY))
                    line.line(to: NSPoint(x: cr.maxX - 0.5, y: cr.maxY))
                    line.lineWidth = 1; line.stroke()

                    vdark.setStroke()
                    line = NSBezierPath()
                    line.move(to: NSPoint(x: cr.minX + 1, y: cr.maxY - 1.5))
                    line.line(to: NSPoint(x: cr.maxX - 1, y: cr.maxY - 1.5))
                    line.lineWidth = 1; line.stroke()
                    line = NSBezierPath()
                    line.move(to: NSPoint(x: cr.minX + 1.5, y: cr.minY + 1))
                    line.line(to: NSPoint(x: cr.minX + 1.5, y: cr.maxY - 1))
                    line.lineWidth = 1; line.stroke()
                } else {
                    // Classic Win98 style: gray sunken bevel
                    let bw: CGFloat = theme.dock.bevelWidth > 0 ? theme.dock.bevelWidth : 2

                    NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1).setFill()
                    NSBezierPath(rect: clockFrame).fill()

                    NSColor(white: 0.5, alpha: 1).setStroke()
                    var bevelLine = NSBezierPath()
                    bevelLine.move(to: NSPoint(x: clockFrame.minX, y: clockFrame.maxY - bw / 2))
                    bevelLine.line(to: NSPoint(x: clockFrame.maxX, y: clockFrame.maxY - bw / 2))
                    bevelLine.lineWidth = bw
                    bevelLine.stroke()
                    bevelLine = NSBezierPath()
                    bevelLine.move(to: NSPoint(x: clockFrame.minX + bw / 2, y: clockFrame.minY))
                    bevelLine.line(to: NSPoint(x: clockFrame.minX + bw / 2, y: clockFrame.maxY))
                    bevelLine.lineWidth = bw
                    bevelLine.stroke()

                    NSColor.white.setStroke()
                    bevelLine = NSBezierPath()
                    bevelLine.move(to: NSPoint(x: clockFrame.minX, y: clockFrame.minY + bw / 2))
                    bevelLine.line(to: NSPoint(x: clockFrame.maxX, y: clockFrame.minY + bw / 2))
                    bevelLine.lineWidth = bw
                    bevelLine.stroke()
                    bevelLine = NSBezierPath()
                    bevelLine.move(to: NSPoint(x: clockFrame.maxX - bw / 2, y: clockFrame.minY))
                    bevelLine.line(to: NSPoint(x: clockFrame.maxX - bw / 2, y: clockFrame.maxY))
                    bevelLine.lineWidth = bw
                    bevelLine.stroke()
                }

                let clockFontSize = theme.dock.clockFontSize ?? max(11, theme.dock.iconSize * scale * 0.45)
                let font = NSFont.monospacedDigitSystemFont(ofSize: clockFontSize, weight: .regular)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
                let timeSize = (clockString as NSString).size(withAttributes: attrs)
                let tx = clockFrame.maxX - timeSize.width - 8
                let ty = clockFrame.midY - timeSize.height / 2
                (clockString as NSString).draw(at: NSPoint(x: tx, y: ty), withAttributes: attrs)
            }
        }

        // Disk free space tray (OS/2 WarpCenter style)
        // Renders as: [label]  [VALUE]  [unit] with VALUE on navy-blue highlight
        if hasDiskFree && !diskFreeFrame.isEmpty {
            let dr = diskFreeFrame

            // Sunken tray background + 3D borders
            NSColor(calibratedWhite: 0.788, alpha: 1).setFill()  // #C9C9C9
            NSBezierPath(rect: dr).fill()

            let dark = NSColor(calibratedWhite: 0.502, alpha: 1)
            let vdark = NSColor(calibratedWhite: 0.25, alpha: 1)
            let light = NSColor.white

            dark.setStroke()
            var line = NSBezierPath()
            line.move(to: NSPoint(x: dr.minX, y: dr.maxY - 0.5))
            line.line(to: NSPoint(x: dr.maxX, y: dr.maxY - 0.5))
            line.lineWidth = 1; line.stroke()
            line = NSBezierPath()
            line.move(to: NSPoint(x: dr.minX + 0.5, y: dr.minY))
            line.line(to: NSPoint(x: dr.minX + 0.5, y: dr.maxY))
            line.lineWidth = 1; line.stroke()

            light.setStroke()
            line = NSBezierPath()
            line.move(to: NSPoint(x: dr.minX, y: dr.minY + 0.5))
            line.line(to: NSPoint(x: dr.maxX, y: dr.minY + 0.5))
            line.lineWidth = 1; line.stroke()
            line = NSBezierPath()
            line.move(to: NSPoint(x: dr.maxX - 0.5, y: dr.minY))
            line.line(to: NSPoint(x: dr.maxX - 0.5, y: dr.maxY))
            line.lineWidth = 1; line.stroke()

            vdark.setStroke()
            line = NSBezierPath()
            line.move(to: NSPoint(x: dr.minX + 1, y: dr.maxY - 1.5))
            line.line(to: NSPoint(x: dr.maxX - 1, y: dr.maxY - 1.5))
            line.lineWidth = 1; line.stroke()
            line = NSBezierPath()
            line.move(to: NSPoint(x: dr.minX + 1.5, y: dr.minY + 1))
            line.line(to: NSPoint(x: dr.minX + 1.5, y: dr.maxY - 1))
            line.lineWidth = 1; line.stroke()

            // Draw 3-segment disk free display: label | highlighted value | unit
            let fontSize = theme.dock.clockFontSize ?? max(11, theme.dock.iconSize * scale * 0.45)
            let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
            let boldFont = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
            let blackAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let whiteAttrs: [NSAttributedString.Key: Any] = [.font: boldFont, .foregroundColor: NSColor.white]

            let labelSize = (diskFreeLabel as NSString).size(withAttributes: blackAttrs)
            let valueSize = (diskFreeValue as NSString).size(withAttributes: whiteAttrs)
            let unitSize = (diskFreeUnit as NSString).size(withAttributes: blackAttrs)

            let textY = dr.midY - labelSize.height / 2
            var curX = dr.minX + 8

            // Label (e.g. "(APFS)")
            (diskFreeLabel as NSString).draw(at: NSPoint(x: curX, y: textY), withAttributes: blackAttrs)
            curX += labelSize.width + 6

            // Navy-blue highlighted value box (e.g. "150")
            let valueBoxRect = NSRect(x: curX - 4, y: dr.midY - valueSize.height / 2 - 1,
                                      width: valueSize.width + 8, height: valueSize.height + 2)
            NSColor(red: 0, green: 0, blue: 0.502, alpha: 1).setFill()  // #000080 navy blue
            NSBezierPath(rect: valueBoxRect).fill()
            (diskFreeValue as NSString).draw(at: NSPoint(x: curX, y: dr.midY - valueSize.height / 2),
                                              withAttributes: whiteAttrs)
            curX += valueSize.width + 8 + 6

            // Unit (e.g. "GB Free")
            (diskFreeUnit as NSString).draw(at: NSPoint(x: curX, y: textY), withAttributes: blackAttrs)
        }

        // ICQ tray icon (right of clock, for Windows 98 / Windows XP)
        if !trayIconFrame.isEmpty, let icqImg = startMenuIcon("icq.png") {
            icqImg.size = trayIconFrame.size
            icqImg.draw(in: trayIconFrame,
                        from: .zero,
                        operation: .sourceOver,
                        fraction: 1.0)
        }
    }

    // MARK: - Control Strip Drawing

    /// Draws the Mac OS 9 Control Strip: a narrow platinum-gray horizontal bar
    /// Load left.png and right.png end cap images from the active theme bundle.
    private func loadControlStripCaps() {
        guard controlStripLeftCap == nil || controlStripRightCap == nil,
              let theme = ThemeManager.shared.activeTheme else { return }
        let iconsDir = theme.iconsDirectory
        let leftURL = iconsDir.appendingPathComponent("controlstrip-left.png")
        let rightURL = iconsDir.appendingPathComponent("controlstrip-right.png")
        controlStripLeftCap = NSImage(contentsOf: leftURL)
        controlStripRightCap = NSImage(contentsOf: rightURL)
    }

    /// Scale factor for left Control Strip PNG cap (bar height / PNG height).
    private var controlStripLeftCapScale: CGFloat {
        let origH: CGFloat = controlStripLeftCap?.size.height ?? 52
        return dockBarRect.height / origH
    }

    /// Scale factor for right Control Strip PNG cap (bar height / PNG height).
    private var controlStripRightCapScale: CGFloat {
        let origH: CGFloat = controlStripRightCap?.size.height ?? 52
        return dockBarRect.height / origH
    }

    /// Kept for border proportion calculations (based on left cap which defines the border style).
    var controlStripCapScale: CGFloat { controlStripLeftCapScale }

    /// Scaled width for the left end cap PNG.
    var controlStripLeftCapWidth: CGFloat {
        let origW: CGFloat = controlStripLeftCap?.size.width ?? 32
        return origW * controlStripLeftCapScale
    }

    /// Scaled width for the right end cap PNG (scaled proportionally to its own height).
    var controlStripRightCapWidth: CGFloat {
        let origW: CGFloat = controlStripRightCap?.size.width ?? 34
        return origW * controlStripRightCapScale
    }

    /// Mac OS 9 Control Strip — uses PNG end caps, ▶ arrows per module, grooves.
    private func drawControlStrip(ctx: CGContext, theme: DockThemeConfig, barRect: NSRect, bgAlpha: CGFloat) {
        loadControlStripCaps()
        let r = barRect
        let leftCapW = controlStripLeftCapWidth
        let rightCapW = controlStripRightCapWidth
        let arrowWidth: CGFloat = 14   // ▶ arrow space per module
        let grooveWidth: CGFloat = 2

        // -- Colors (measured from PNG pixel values)
        let platinum = NSColor(calibratedWhite: 0.733, alpha: bgAlpha)       // #BBBBBB — main content fill
        let grooveDark = NSColor(calibratedWhite: 0.55, alpha: bgAlpha)
        let grooveLight = NSColor(calibratedWhite: 0.92, alpha: bgAlpha)
        let arrowColor = NSColor(calibratedWhite: 0.20, alpha: bgAlpha)
        let borderColor = NSColor(calibratedWhite: 0.149, alpha: bgAlpha)    // #262626 — dark border
        let bevelLight = NSColor(calibratedWhite: 1.0, alpha: bgAlpha)       // #FFFFFF — top highlight
        let bevelShadow = NSColor(calibratedWhite: 0.502, alpha: bgAlpha)    // #808080 — bottom shadow

        // Proportional border sizes (PNG is 52px tall: 2+4+content+4+2)
        let scale = controlStripCapScale  // barRect.height / originalPNGHeight
        let darkBorderH  = round(2 * scale)   // 2px dark edge
        let highlightH   = round(4 * scale)   // 4px white bevel (top)
        let shadowH       = round(4 * scale)   // 4px gray shadow (bottom)

        // 1. Draw left cap PNG (collapse button) — pixel-crisp rendering
        let leftCapRect = NSRect(x: r.minX, y: r.minY, width: leftCapW, height: r.height)
        if let leftCap = controlStripLeftCap {
            ctx.saveGState()
            ctx.interpolationQuality = .none  // nearest-neighbor for pixel art
            leftCap.draw(in: leftCapRect, from: .zero, operation: .sourceOver, fraction: bgAlpha)
            ctx.restoreGState()
        }

        // If collapsed, only draw left cap
        if controlStripCollapsed { return }

        // 2. Middle section background — matches PNG border structure exactly
        let midX = r.minX + leftCapW
        let midW = r.width - leftCapW - rightCapW
        if midW > 0 {
            // a) Dark border — top 2px
            borderColor.setFill()
            NSBezierPath(rect: NSRect(x: midX, y: r.maxY - darkBorderH,
                                      width: midW, height: darkBorderH)).fill()
            // b) White highlight bevel — 4px below top border
            bevelLight.setFill()
            NSBezierPath(rect: NSRect(x: midX, y: r.maxY - darkBorderH - highlightH,
                                      width: midW, height: highlightH)).fill()

            // c) Platinum content fill
            let contentY = r.minY + darkBorderH + shadowH
            let contentH = r.height - darkBorderH * 2 - highlightH - shadowH
            platinum.setFill()
            NSBezierPath(rect: NSRect(x: midX, y: contentY,
                                      width: midW, height: contentH)).fill()

            // d) Gray shadow — 4px above bottom border
            bevelShadow.setFill()
            NSBezierPath(rect: NSRect(x: midX, y: r.minY + darkBorderH,
                                      width: midW, height: shadowH)).fill()
            // e) Dark border — bottom 2px
            borderColor.setFill()
            NSBezierPath(rect: NSRect(x: midX, y: r.minY,
                                      width: midW, height: darkBorderH)).fill()
        }

        // 3. Right cap PNG (grip handle) — pixel-crisp rendering for retro look
        let rightCapRect = NSRect(x: r.maxX - rightCapW, y: r.minY, width: rightCapW, height: r.height)
        if let rightCap = controlStripRightCap {
            ctx.saveGState()
            ctx.interpolationQuality = .none  // nearest-neighbor for pixel art
            rightCap.draw(in: rightCapRect, from: .zero, operation: .sourceOver, fraction: bgAlpha)
            ctx.restoreGState()
        }

        // 4. Arrows ▶ and grooves between icon modules
        for (i, item) in itemViews.enumerated() {
            let iconRight = item.frame.maxX
            // ▶ arrow — larger, matching original proportions
            let arrowX = iconRight + 3
            let arrowCY = item.frame.midY
            let triH: CGFloat = 8
            let triW: CGFloat = 6
            let tri = NSBezierPath()
            tri.move(to: NSPoint(x: arrowX, y: arrowCY - triH / 2))
            tri.line(to: NSPoint(x: arrowX + triW, y: arrowCY))
            tri.line(to: NSPoint(x: arrowX, y: arrowCY + triH / 2))
            tri.close()
            arrowColor.setFill()
            tri.fill()

            // Groove between modules (not after the last one)
            if i < itemViews.count - 1 {
                let gx = iconRight + arrowWidth
                let grooveTop = r.minY + darkBorderH + shadowH
                let grooveBot = r.maxY - darkBorderH - highlightH
                drawGroove(at: gx, top: grooveTop, bottom: grooveBot,
                           dark: grooveDark, light: grooveLight)
            }
        }
    }

    /// Callback for Control Strip collapse/expand animation (set by DockController).
    var onControlStripToggle: ((_ collapsed: Bool) -> Void)?

    /// Handle click on Control Strip left cap (collapse/expand toggle).
    func handleControlStripCollapseClick(at localPoint: NSPoint) -> Bool {
        guard isControlStrip else { return false }
        let leftCapW = controlStripLeftCapWidth
        // Use full bounds height so click detection works even during animations
        let capRect = NSRect(x: 0, y: 0, width: leftCapW, height: bounds.height)
        if capRect.contains(localPoint) {
            controlStripCollapsed.toggle()
            onControlStripToggle?(controlStripCollapsed)
            return true
        }
        return false
    }

    /// Helper: draw a 2px groove (dark + light line) at the given x position.
    private func drawGroove(at x: CGFloat, top: CGFloat, bottom: CGFloat,
                            dark: NSColor, light: NSColor) {
        dark.setStroke()
        var line = NSBezierPath()
        line.move(to: NSPoint(x: x, y: top))
        line.line(to: NSPoint(x: x, y: bottom))
        line.lineWidth = 1
        line.stroke()
        light.setStroke()
        line = NSBezierPath()
        line.move(to: NSPoint(x: x + 1, y: top))
        line.line(to: NSPoint(x: x + 1, y: bottom))
        line.lineWidth = 1
        line.stroke()
    }

    // MARK: - Hit testing (pass through clicks outside items)

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        // Control Strip: left cap is clickable (collapse/expand)
        if isControlStrip {
            let leftCapW = controlStripLeftCapWidth
            let capRect = NSRect(x: 0, y: 0, width: leftCapW, height: bounds.height)
            if capRect.contains(local) { return self }
            // When collapsed, the entire strip IS the left cap
            if controlStripCollapsed { return nil }
        }
        if hasStartButton && startButtonFrame.contains(local) {
            return self
        }
        // ICQ tray icon
        if !trayIconFrame.isEmpty && trayIconFrame.insetBy(dx: -4, dy: -4).contains(local) {
            return self
        }
        // Clock / systray strip (right edge): clicks here open the clock widget — must reach
        // DockView, not the app-button subviews that can overlap into this area.
        if !clockFrame.isEmpty {
            let strip = NSRect(x: clockFrame.minX, y: 0,
                               width: max(clockFrame.width, bounds.maxX - clockFrame.minX),
                               height: bounds.height)
            if strip.contains(local) { return self }
        }
        // Check items using their visual (rendered) bounds, not the original frame.
        // When magnification is active, icons are repositioned via layer transforms.
        for item in itemViews {
            guard let layer = item.layer else {
                if item.frame.contains(local) { return item }
                continue
            }
            // presentationLayer reflects the on-screen position (including animations)
            let effectiveLayer = layer.presentation() ?? layer
            let renderFrame = effectiveLayer.frame
            if renderFrame.contains(local) {
                return item
            }
        }
        // Win98/XP taskbar buttons (not in itemViews, no magnification → plain frame test).
        for btn in taskButtonViews where btn.frame.contains(local) {
            return btn
        }
        return nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        // If the right-click is on a dock item, let the item's own menu handle it.
        // Use the VISUAL (magnified/presentation) frame so a right-click on an
        // enlarged icon still hits it, matching hitTest(_:).
        let onItem = itemViews.contains { item in
            let f = (item.layer?.presentation() ?? item.layer)?.frame ?? item.frame
            return f.contains(local)
        }
        if onItem {
            super.rightMouseDown(with: event)
            return
        }
        onDockContextMenu?(local)
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)

        // Control Strip: left cap click → collapse/expand
        if handleControlStripCollapseClick(at: local) { return }

        // ICQ tray icon → open iMessages
        if !trayIconFrame.isEmpty && trayIconFrame.insetBy(dx: -4, dy: -4).contains(local) {
            AppLauncher.launchOrActivate(bundleID: "com.apple.MobileSMS")
            return
        }

        // Taskbar clock → open the themed analog-clock widget. Use a generous hit region
        // covering the whole right-edge systray/clock strip (full bar height) so the click
        // is reliably caught regardless of exact text metrics.
        if !clockFrame.isEmpty {
            let clockHit = NSRect(x: clockFrame.minX, y: 0,
                                  width: max(clockFrame.width, bounds.maxX - clockFrame.minX),
                                  height: bounds.height)
            if clockHit.contains(local) {
                ClockWidgetController.shared.toggle()
                return
            }
        }

        if hasStartButton && startButtonFrame.contains(local) {
            // Toggle: if start menu is visible, dismiss it; otherwise show it
            if let panel = startMenuPanel, panel.isVisible {
                panel.dismiss()
                startButtonPressed = false
                needsDisplay = true
            } else {
                startButtonPressed = true
                needsDisplay = true
                showStartMenu()
                startButtonPressed = false
                needsDisplay = true
            }
            return
        }
        super.mouseDown(with: event)
    }

    // MARK: - Drag & Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasAppURL(sender) else { return [] }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasAppURL(sender) else { return [] }
        let loc = convert(sender.draggingLocation, from: nil)
        dropInsertionIndex = insertionIndex(at: loc)
        needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropInsertionIndex = nil
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropInsertionIndex = nil
        needsDisplay = true

        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], let url = urls.first else { return false }

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        if isDir.boolValue && !url.pathExtension.lowercased().contains("app") {
            // It's a folder (not an .app bundle)
            AppManager.shared.addFolder(path: url.path)
            return true
        }

        // It's an app
        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return false }
        AppManager.shared.addApp(bundleID: bundleID)
        return true
    }

    private func hasAppURL(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ])
    }

    private func insertionIndex(at point: NSPoint) -> Int {
        guard let theme = ThemeManager.shared.activeTheme?.config else { return 0 }
        let scale = CGFloat(AppSettings.shared.dockIconScale)
        let iconSize = theme.dock.iconSize * scale
        let spacing = theme.dock.spacing * scale
        let padding = theme.dock.padding * scale
        let cell = iconSize + spacing
        let pos: CGFloat
        if isVertical {
            pos = point.y - padding
        } else if hasStartButton && !startButtonFrame.isEmpty {
            pos = point.x - startButtonFrame.maxX - spacing
        } else {
            pos = point.x - padding
        }
        let idx = Int((pos + cell / 2) / cell)
        return max(0, min(idx, AppManager.shared.apps.count))
    }

    // MARK: - Magnification

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setupMagnificationTracking()
    }

    private var needsStartButtonTracking: Bool {
        hasStartButton && startButtonImages != nil
    }

    private func setupMagnificationTracking() {
        if let ta = magnificationTrackingArea { removeTrackingArea(ta) }
        magnificationTrackingArea = nil
        guard hasMagnification || needsStartButtonTracking else { return }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(ta)
        magnificationTrackingArea = ta
    }

    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)

        // Track start button hover state
        if needsStartButtonTracking {
            let hovered = startButtonFrame.contains(local)
            if hovered != startButtonHovered {
                startButtonHovered = hovered
                needsDisplay = true
            }
        }

        if hasMagnification {
            if isWithinMagnificationRegion(local) {
                magTargetPoint = local
                if magPhase >= 1 {
                    applyMagnification(at: local)   // steady state: follow the pointer directly
                } else {
                    if magPhase == 0 { magRestFrames = itemViews.map { $0.frame } }  // capture true rest
                    setMagTarget(1)
                    startMagTimer()                 // ramp the magnification in
                }
            } else if magPhase > 0 || magPhaseTarget > 0 {
                // Cursor moved into the empty magnification-overflow margin (transparent, no
                // icons there) — ease back to rest so the dock doesn't "react" far outside its
                // visible bar and so anything sitting beside the dock stays clickable.
                magExitFrames = itemViews.map { $0.frame }
                magExitBar = magnifiedDockBarRect ?? dockBarRect
                setMagTarget(0)
                startMagTimer()
            }
        }
    }

    /// The hover zone that actually triggers magnification: the VISIBLE dock bar plus a
    /// half-icon margin — NOT the full window (which is widened by `horizontalMagOverflow`
    /// so magnified end-icons don't clip). Hovering the transparent overflow must not
    /// magnify or capture clicks meant for windows beside the dock.
    private func isWithinMagnificationRegion(_ p: NSPoint) -> Bool {
        let eff = CGFloat(AppSettings.shared.dockIconScale) * dynamicScale
        let icon = (ThemeManager.shared.activeTheme?.config.dock.iconSize ?? 64) * eff
        let m = icon * 0.5
        let bar = dockBarRect
        return isVertical ? (p.y >= bar.minY - m && p.y <= bar.maxY + m)
                          : (p.x >= bar.minX - m && p.x <= bar.maxX + m)
    }

    override func mouseExited(with event: NSEvent) {
        if startButtonHovered {
            startButtonHovered = false
            needsDisplay = true
        }
        guard hasMagnification else { return }

        // Bottom dock: the screen's bottom edge is a natural barrier. Sliding the
        // cursor all the way down can momentarily push it out of the tracking rect,
        // which would drop the magnifier and cause a flicker. Keep the effect alive
        // on a downward exit (cursor still horizontally over the dock); only reset on
        // a REAL exit — upward past the popped icons, or out either side.
        if !isVertical {
            let local = convert(event.locationInWindow, from: nil)
            let withinX = local.x >= 0 && local.x <= bounds.width
            let downwardExit = local.y <= dockBarRect.maxY
            if withinX && downwardExit {
                magTargetPoint = NSPoint(x: min(max(local.x, 0), bounds.width), y: dockBarRect.midY)
                if magPhase >= 1 { applyMagnification(at: magTargetPoint) }
                else { setMagTarget(1); startMagTimer() }
                return
            }
        }
        // Ease the magnification back out by interpolating the captured magnified frames
        // toward the true rest frames, so it lands EXACTLY on the rest layout (no settle jump).
        magExitFrames = itemViews.map { $0.frame }
        magExitBar = magnifiedDockBarRect ?? dockBarRect
        setMagTarget(0)
        startMagTimer()
    }

    private func applyMagnification(at point: NSPoint) {
        guard let theme = ThemeManager.shared.activeTheme?.config,
              theme.hasMagnification, !itemViews.isEmpty else { return }

        let maxScale = theme.magnificationMaxScale
        let effectiveScale = CGFloat(AppSettings.shared.dockIconScale) * dynamicScale
        let baseSize = theme.dock.iconSize * effectiveScale
        let spacing = theme.dock.spacing * effectiveScale
        let padding = theme.dock.padding * effectiveScale
        let range = baseSize * 3.0  // effect radius
        let barRect = dockBarRect

        // ── Vertical dock magnification ─────────────────────────────────────
        // Cursor-anchored reflow: the icon under the pointer keeps its position (its
        // fractional spot in the stack is preserved) while neighbours spread apart so
        // they never overlap, each bulging toward the screen interior over the long
        // edge. calculateDockSize reserves enough length headroom that this rarely
        // clamps. The bar grows in LENGTH only (fixed thickness) to wrap the icons.
        if isVertical {
            let count = itemViews.count
            // Use the REST centres captured at layout time, NOT the live frames (which
            // the frame-based magnifier mutates — reading them would compound spacing).
            let originalCentersY = (restCentersY.count == count) ? restCentersY : itemViews.map { $0.frame.midY }
            var scales: [CGFloat] = []
            for cYrest in originalCentersY {
                let dist = abs(point.y - cYrest)
                if dist < range {
                    let t = dist / range
                    scales.append(1.0 + (maxScale - 1.0) * ((1.0 + cos(CGFloat.pi * t)) / 2.0))
                } else {
                    scales.append(1.0)
                }
            }
            // Ease in/out: interpolate each icon from rest (1) toward its full scale by phase.
            if magPhase < 1.0 { scales = scales.map { 1.0 + ($0 - 1.0) * magPhase } }
            // Magnified heights are based on the REST icon size (baseSize), not the
            // current (possibly already-magnified) frame height — avoids compounding.
            let magHeights = scales.map { $0 * baseSize }
            var posFromTop = [CGFloat](repeating: 0, count: count)
            var cum: CGFloat = 0
            for i in 0..<count { posFromTop[i] = cum + magHeights[i] / 2; cum += magHeights[i] + spacing }
            let totalMag = max(1, cum - spacing)

            let origTop = (originalCentersY.first ?? 0) + baseSize / 2
            let origBottom = (originalCentersY.last ?? 0) - baseSize / 2
            let origTotal = max(1, origTop - origBottom)
            // Anchor the stack using a cursor position CLAMPED to the icon range, so
            // moving the mouse past the last icon (e.g. below the Trash) does not drag
            // the whole stack along with it — it stays put while the end icon shrinks.
            let anchorY = min(max(point.y, origBottom), origTop)
            let frac = (origTop - anchorY) / origTotal
            var newTop = anchorY + frac * totalMag
            if newTop > bounds.height - padding { newTop = bounds.height - padding }
            if newTop - totalMag < padding { newTop = max(bounds.height - padding, padding + totalMag) }

            let popDir: CGFloat = (dockPosition == "right") ? -1 : 1  // interior direction
            // Resize each icon's FRAME (rather than a layer transform). A transform
            // pushes the icon outside its own frame, and CoreAnimation clips that
            // overhang asymmetrically (leftward overhang clipped → right dock popped
            // less). Setting the real frame keeps the content inside it, so both sides
            // protrude identically. All vertical icons rest centred on barRect.midX.
            let restCenterX = barRect.midX
            for (i, item) in itemViews.enumerated() {
                let magW = scales[i] * baseSize
                let cx = restCenterX + popDir * (scales[i] - 1.0) * baseSize * 0.9  // pop interior
                let cy = newTop - posFromTop[i]
                item.layer?.setAffineTransform(.identity)
                item.layer?.zPosition = scales[i]
                item.frame = NSRect(x: cx - magW / 2, y: cy - magW / 2, width: magW, height: magW)
            }
            let expandedTop = min(bounds.height, max(barRect.maxY, newTop + padding))
            let expandedBottom = max(0, min(barRect.minY, newTop - totalMag - padding))
            magnifiedDockBarRect = NSRect(x: barRect.minX, y: expandedBottom,
                                          width: barRect.width, height: expandedTop - expandedBottom)
            needsDisplay = true
            return
        }

        // Rest geometry captured at layout time — NEVER read live frames here, or the
        // frame-based magnification compounds on every mouse move. (Layer-transform
        // magnification proved unreliable — it expanded the bar but didn't render the
        // icon scale — so the horizontal dock now resizes frames, like the vertical one.)
        let count = itemViews.count
        let restX = (restCentersX.count == count) ? restCentersX : itemViews.map { $0.frame.midX }

        // 1. Per-icon scale (raised cosine bell curve)
        var scales: [CGFloat] = []
        for cx in restX {
            let dist = abs(point.x - cx)
            if dist < range {
                let t = dist / range
                scales.append(1.0 + (maxScale - 1.0) * ((1.0 + cos(CGFloat.pi * t)) / 2.0))
            } else {
                scales.append(1.0)
            }
        }
        // Ease in/out: interpolate each icon from rest (1) toward its full scale by phase.
        if magPhase < 1.0 { scales = scales.map { 1.0 + ($0 - 1.0) * magPhase } }

        // 2. Magnified widths from the REST icon size (baseSize), not live frames
        let magnifiedWidths = scales.map { baseSize * $0 }
        let spacingTotal = CGFloat(max(0, count - 1)) * spacing
        let totalMagnified = magnifiedWidths.reduce(CGFloat(0), +) + spacingTotal

        // 3. Centre the magnified row around the resting centre
        let firstStart = (restX.first ?? barRect.midX) - baseSize / 2
        let lastEnd = (restX.last ?? barRect.midX) + baseSize / 2
        let originalCenter = (firstStart + lastEnd) / 2
        var x = originalCenter - totalMagnified / 2
        if x < padding { x = padding }
        if x + totalMagnified > bounds.width - padding {
            x = max(padding, bounds.width - padding - totalMagnified)
        }

        var maxIdx = 0
        for i in 0..<scales.count where scales[i] > scales[maxIdx] { maxIdx = i }
        var labelX: CGFloat = 0, labelTopY: CGFloat = 0
        // 3D shelf is drawn only in the lower 55% of the bar; place icons with their
        // CENTRE on the shelf top so they stick out ~halfway above it (matches the real
        // Snow Leopard dock). 0.55 must match the shelfRect fraction in the draw code.
        let is3DShelf = ThemeManager.shared.activeTheme?.config.has3DShelf ?? false
        let floorY = is3DShelf
            ? barRect.minY + barRect.height * 0.55 - baseSize / 2
            : barRect.minY + (barRect.height - baseSize) / 2   // rest baseline; icons grow upward from here

        // 4. Resize each icon's FRAME (reliable scaling — the icon image fills the frame).
        for (i, item) in itemViews.enumerated() {
            let magW = magnifiedWidths[i]
            let magH = baseSize * scales[i]
            item.resetMagnification()
            item.frame = NSRect(x: x, y: floorY, width: magW, height: magH)
            item.layer?.zPosition = scales[i]
            if i == maxIdx { labelX = x + magW / 2; labelTopY = floorY + magH }
            x += magW + spacing
        }

        // Aqua app-name label above the most-magnified icon.
        if ThemeManager.shared.activeTheme?.config.dock.showLabels == true,
           !itemViews.isEmpty, scales[maxIdx] > 1.08 {
            showHoverLabel(text: nameFor(itemViews[maxIdx].bundleID), centerX: labelX, aboveY: labelTopY)
        } else {
            hoverLabel?.isHidden = true
        }

        // 4. Expand the dock bar background to contain magnified icons
        let magLeft = originalCenter - totalMagnified / 2 - padding
        let magRight = originalCenter + totalMagnified / 2 + padding
        let expandedLeft = min(barRect.minX, magLeft)
        let expandedRight = max(barRect.maxX, magRight)
        magnifiedDockBarRect = NSRect(
            x: expandedLeft, y: barRect.minY,
            width: expandedRight - expandedLeft, height: barRect.height
        )
        needsDisplay = true
    }

    // MARK: - Aqua hover name label

    private var hoverLabel: NSTextField?

    private func nameFor(_ bundleID: String) -> String {
        if bundleID == "__trash__" { return "Trash" }
        if bundleID == "__urllauncher__" { return "Link" }
        if let app = AppManager.shared.apps.first(where: { $0.bundleID == bundleID }) { return app.displayName }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return app.localizedName ?? bundleID
        }
        return bundleID
    }

    private func showHoverLabel(text: String, centerX: CGFloat, aboveY: CGFloat) {
        let lbl: NSTextField
        if let l = hoverLabel { lbl = l } else {
            let l = NSTextField(labelWithString: "")
            l.font = NSFont(name: "Lucida Grande", size: 12) ?? .systemFont(ofSize: 12)
            l.textColor = .white
            l.alignment = .center
            l.drawsBackground = false
            l.isBezeled = false; l.isEditable = false; l.isSelectable = false
            l.wantsLayer = true
            l.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
            l.layer?.cornerRadius = 5
            l.layer?.zPosition = 10_000   // above the magnified icons (which raise zPosition)
            hoverLabel = l; lbl = l
        }
        lbl.stringValue = text
        let tw = ceil((text as NSString).size(withAttributes: [.font: lbl.font as Any]).width)
        let w = tw + 16, h: CGFloat = 18
        let cx = max(w / 2 + 2, min(centerX, bounds.width - w / 2 - 2))
        let y = min(aboveY + 6, bounds.height - h)
        lbl.frame = NSRect(x: cx - w / 2, y: y, width: w, height: h)
        if lbl.superview == nil { addSubview(lbl) } else { addSubview(lbl, positioned: .above, relativeTo: nil) }
        lbl.isHidden = false
    }

    // MARK: - Eased magnification driver

    private func startMagTimer() {
        guard magTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 1.0 / 120.0)
        t.setEventHandler { [weak self] in self?.magTick() }
        magTimer = t
        t.resume()
    }

    private func stopMagTimer() {
        magTimer?.cancel()
        magTimer = nil
    }

    /// Set the magnification target; restart the timed ramp from the current phase so the
    /// ease finishes cleanly (no exponential tail/creep).
    private func setMagTarget(_ target: CGFloat) {
        guard target != magPhaseTarget else { return }
        magPhaseTarget = target
        magRampStart = CACurrentMediaTime()
        magRampFromPhase = magPhase
    }

    /// Duration-based ease-out so the phase REACHES the target in a fixed time and flattens
    /// at the end (the icons settle without a late "nudge"). Bar + icons use the same phase.
    private func magTick() {
        let duration: CFTimeInterval = 0.18
        let t = min(1.0, max(0.0, (CACurrentMediaTime() - magRampStart) / duration))
        let u = 1.0 - t
        let e = CGFloat(1.0 - u * u * u)   // cubic ease-out: very gentle finish, exact at t=1

        // Ramp OUT: interpolate the captured magnified frames → the true rest frames (and the
        // bar with them) so it lands EXACTLY on the rest layout — no settle wobble.
        if magPhaseTarget < 0.5 {
            magPhase = 1.0 - e
            if magExitFrames.count == itemViews.count, magRestFrames.count == itemViews.count {
                for (i, item) in itemViews.enumerated() {
                    item.frame = Self.lerpRect(magExitFrames[i], magRestFrames[i], e)
                }
                magnifiedDockBarRect = Self.lerpRect(magExitBar, dockBarRect, e)
                needsDisplay = true
            }
            if t >= 1.0 {
                stopMagTimer()
                resetMagnification()   // endpoint == the interpolation target, so no jump
            }
            return
        }

        // Ramp IN: phase-scaled magnification (bar + icons from the same phase).
        magPhase = magRampFromPhase + (magPhaseTarget - magRampFromPhase) * e
        if t >= 1.0 {
            magPhase = 1.0
            applyMagnification(at: magTargetPoint)   // steady; mouseMoved drives follow
            stopMagTimer()
            return
        }
        applyMagnification(at: magTargetPoint)
    }

    private static func lerpRect(_ a: NSRect, _ b: NSRect, _ f: CGFloat) -> NSRect {
        NSRect(x: a.minX + (b.minX - a.minX) * f,
               y: a.minY + (b.minY - a.minY) * f,
               width: a.width + (b.width - a.width) * f,
               height: a.height + (b.height - a.height) * f)
    }

    private func resetMagnification() {
        hoverLabel?.isHidden = true
        for item in itemViews {
            item.resetMagnification()
        }
        magnifiedDockBarRect = nil
        // Both axes now resize icon FRAMES during magnification, so restore the
        // resting layout when the pointer leaves.
        relayoutItems()
        needsDisplay = true
    }

    // MARK: - Start Button

    private func loadStartButtonIcon() {
        guard startButtonIcon == nil,
              let url = ThemeManager.shared.activeTheme?.startButtonIconURL() else { return }
        startButtonIcon = NSImage(contentsOf: url)
    }

    private func loadStartButtonImages() {
        guard startButtonImages == nil,
              let url = ThemeManager.shared.activeTheme?.startButtonImageURL(),
              let sheet = NSImage(contentsOf: url) else { return }

        // Sprite sheet has 3 states stacked vertically: normal, hover, pressed
        let sheetSize = sheet.size
        let sliceHeight = sheetSize.height / 3.0
        let sliceSize = NSSize(width: sheetSize.width, height: sliceHeight)

        func slice(at index: Int) -> NSImage {
            let img = NSImage(size: sliceSize)
            img.lockFocus()
            // In image coordinates, y=0 is bottom. State 0 (normal) is top of sheet.
            let srcY = sheetSize.height - sliceHeight * CGFloat(index + 1)
            sheet.draw(in: NSRect(origin: .zero, size: sliceSize),
                       from: NSRect(x: 0, y: srcY, width: sheetSize.width, height: sliceHeight),
                       operation: .copy, fraction: 1.0)
            img.unlockFocus()
            return img
        }

        startButtonImages = (normal: slice(at: 0), hover: slice(at: 1), pressed: slice(at: 2))
    }

    private func showStartMenu() {
        let theme = ThemeManager.shared.activeTheme
        let isXP = theme?.config.isXPStartMenu == true

        if isXP {
            showXPStartMenu()
        } else {
            // Defer to the next runloop tick so the opening click fully completes before
            // the panel's dismiss monitors are installed (fixes OS/2 needing two clicks).
            DispatchQueue.main.async { [weak self] in self?.showClassicStartMenu() }
        }
    }

    private func showXPStartMenu() {
        typealias MI = StartMenuPanel.MenuItem

        // Left column: pinned apps from dock (max 6, like original XP)
        let xpIconSize: CGFloat = 32
        var leftItems: [MI] = []
        for app in AppManager.shared.apps.prefix(6) {
            let bid = app.bundleID
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                let name = FileManager.default.displayName(atPath: appURL.path)
                    .replacingOccurrences(of: ".app", with: "")
                let icon = ThemeManager.shared.icon(for: bid, size: xpIconSize)
                leftItems.append(MI(title: name, icon: icon, action: {
                    AppLauncher.launchOrActivate(bundleID: bid)
                }, bundleID: bid))
            }
        }

        // Re:Amp (Winamp clone) — pinned in XP start menu (if enabled in theme settings)
        if AppSettings.shared.reampEnabled {
            if !leftItems.isEmpty {
                leftItems.append(MI(separator: true))
            }
            let reampXPIcon: NSImage? = {
                guard let themeBundle = ThemeManager.shared.activeTheme else { return nil }
                let url = themeBundle.iconsDirectory.appendingPathComponent("reamp.png")
                guard let img = NSImage(contentsOf: url) else { return nil }
                img.size = NSSize(width: xpIconSize, height: xpIconSize)
                return img
            }()
            leftItems.append(MI(title: "Re:Amp", icon: reampXPIcon, action: {
                ReAmpHelper.launchOrInstall()
            }))
        }

        // (The real XP Start menu lists pinned/frequent programs only — running apps live on
        // the taskbar, not here, so they are intentionally NOT injected into the left column.)

        // Right column: system locations with authentic XP icons
        let xpIcon = { (filename: String) -> NSImage? in
            guard let themeBundle = ThemeManager.shared.activeTheme else { return nil }
            let url = themeBundle.iconsDirectory.appendingPathComponent(filename)
            return NSImage(contentsOf: url)
        }

        var rightItems: [MI] = [
            MI(title: "My Documents", icon: xpIcon("xp_documents.png"), action: {
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"))
            }, isBold: true),
            MI(title: "My Recent Documents", icon: xpIcon("xp_recent.png"), action: {
                DockView.openRecentDocuments()
            }),
            MI(title: "My Pictures", icon: xpIcon("xp_pictures.png"), action: {
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures"))
            }),
            MI(title: "My Music", icon: xpIcon("xp_music.png"), action: {
                AppFolderController.tv.show()   // TV-streams folder, styled like the App Folder
            }),
            MI(title: "My Computer", icon: xpIcon("xp_mycomputer.png"), action: {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/"))
            }, isBold: true),
            MI(separator: true),
            MI(title: "Control Panel", icon: xpIcon("xp_controlpanel.png"), action: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!)
            }),
            MI(title: "RetroMac Settings", icon: xpIcon("xp_controlpanel.png"), action: {
                NSApp.sendAction(Selector(("openSettings")), to: nil, from: nil)
            }),
            MI(separator: true),
            MI(title: "Search", icon: xpIcon("xp_search.png"), action: {
                if let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
                    NSWorkspace.shared.open(finderURL)
                }
            }),
            MI(title: "Help and Support", icon: xpIcon("xp_help.png"), action: {
                if let url = URL(string: "https://www.reddit.com") { NSWorkspace.shared.open(url) }
            }),
            MI(title: "Run…", icon: xpIcon("xp_run.png"), action: {
                NSWorkspace.shared.launchApplication("Terminal")
            }),
        ]

        let data = StartMenuPanel.XPMenuData(
            leftItems: leftItems,
            rightItems: rightItems,
            allProgramsAction: {
                // Open Finder's Applications folder
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
            },
            logOffAction: {
                let src = "tell application \"System Events\" to log out"
                NSAppleScript(source: src)?.executeAndReturnError(nil)
            },
            shutDownAction: {
                let src = "tell application \"System Events\" to shut down"
                NSAppleScript(source: src)?.executeAndReturnError(nil)
            },
            userName: NSFullUserName(),
            logOffIcon: xpIcon("xp_logoff.png"),
            shutDownIcon: xpIcon("xp_shutdown.png")
        )

        let panel = StartMenuPanel()
        startMenuPanel = panel
        let pt = NSPoint(x: startButtonFrame.minX, y: startButtonFrame.maxY + 2)
        panel.showXP(data: data, at: pt, in: self, startButtonRect: startButtonFrame)
    }

    private func showClassicStartMenu() {
        typealias MI = StartMenuPanel.MenuItem

        // Win98 start-menu icon loader (mirrors the XP `xpIcon` pattern): loads a
        // 16px glyph from the active theme's icons directory.
        let win98Icon = { (filename: String) -> NSImage? in
            self.startMenuIcon(filename)
        }

        // Programs submenu items
        var programItems: [MI] = []
        for app in AppManager.shared.apps {
            let bid = app.bundleID
            // Use the THEME-mapped icon (same as the dock), not the raw macOS app icon,
            // so the Programs submenu matches the Win98 look.
            let icon = ThemeManager.shared.icon(for: bid, size: 20)
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                let name = FileManager.default.displayName(atPath: appURL.path)
                    .replacingOccurrences(of: ".app", with: "")
                programItems.append(MI(title: name, icon: icon, action: {
                    AppLauncher.launchOrActivate(bundleID: bid)
                }, bundleID: bid))
            } else {
                programItems.append(MI(title: bid, icon: icon, action: {
                    AppLauncher.launchOrActivate(bundleID: bid)
                }, bundleID: bid))
            }
        }
        let transient = runningAppsNotInDock()
        if !transient.isEmpty {
            programItems.append(MI(separator: true))
            for bid in transient {
                let icon = ThemeManager.shared.icon(for: bid, size: 20)
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                    let name = FileManager.default.displayName(atPath: appURL.path)
                        .replacingOccurrences(of: ".app", with: "")
                    programItems.append(MI(title: name, icon: icon, action: {
                        AppLauncher.launchOrActivate(bundleID: bid)
                    }, bundleID: bid))
                } else {
                    programItems.append(MI(title: bid, icon: icon, action: {
                        AppLauncher.launchOrActivate(bundleID: bid)
                    }, bundleID: bid))
                }
            }
        }

        // Re:Amp (Winamp clone) — shown if enabled in theme settings
        if AppSettings.shared.reampEnabled {
            let reampIcon = startMenuIcon("reamp.png")
            let reampItem = MI(title: "Re:Amp", icon: reampIcon, action: {
                ReAmpHelper.launchOrInstall()
            })
            programItems.append(MI(separator: true))
            programItems.append(reampItem)
        }

        // Favorites submenu items
        var favItems: [MI] = []
        for bookmark in AppSettings.shared.tvBookmarks {
            let idString = bookmark.id.uuidString
            let icon = startMenuIcon("menu-internet.png")
            favItems.append(MI(title: bookmark.name, icon: icon, action: {
                // Start-menu streams open the immersive Tube Mode (the windowed TV
                // stays reachable via the TV desktop widget).
                NotificationCenter.default.post(name: .init("openTVBookmarkTube"), object: idString)
            }))
        }
        if favItems.isEmpty {
            favItems.append(MI(title: "(empty)"))
        }

        // Documents submenu items
        var docItems: [MI] = []
        let recentDocs = NSDocumentController.shared.recentDocumentURLs
        for docURL in recentDocs.prefix(10) {
            let icon = NSWorkspace.shared.icon(forFile: docURL.path)
            icon.size = NSSize(width: 20, height: 20)
            let url = docURL
            docItems.append(MI(title: docURL.lastPathComponent, icon: icon, action: {
                NSWorkspace.shared.open(url)
            }))
        }
        if docItems.isEmpty {
            docItems.append(MI(title: "(empty)"))
        }

        // Settings submenu items
        let settingsSubItems: [MI] = [
            MI(title: "RetroMac Settings…", icon: win98Icon("menu-settings.png"), action: {
                NSApp.sendAction(Selector(("openSettings")), to: nil, from: nil)
            }),
            MI(title: "Control Panel", icon: win98Icon("menu-sysguard.png"), action: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!)
            }),
        ]

        // Build top-level items
        let items: [MI] = [
            MI(title: "Programs", icon: win98Icon("menu-programs.png"), submenuItems: programItems),
            MI(title: "Favorites", icon: win98Icon("menu-favorites.png"), submenuItems: favItems),
            MI(title: "Documents", icon: win98Icon("menu-documents.png"), submenuItems: docItems),
            MI(title: "Settings", icon: win98Icon("menu-settings.png"), submenuItems: settingsSubItems),
            MI(title: "Find…", icon: win98Icon("menu-find.png"), action: {
                if let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
                    NSWorkspace.shared.open(finderURL)
                }
            }),
            MI(title: "Help", icon: win98Icon("menu-help.png"), action: {
                NSApp.sendAction(Selector(("showAbout")), to: nil, from: nil)
            }),
            MI(title: "Run…", icon: win98Icon("menu-run.png"), action: {
                NSWorkspace.shared.launchApplication("Terminal")
            }),
            MI(separator: true),
            MI(title: "Log Off \(NSFullUserName())…", icon: win98Icon("menu-logoff.png"), action: {
                let src = "tell application \"System Events\" to log out"
                NSAppleScript(source: src)?.executeAndReturnError(nil)
            }),
            MI(title: "Shut Down…", icon: win98Icon("menu-shutdown.png"), action: {
                let src = "tell application \"System Events\" to shut down"
                NSAppleScript(source: src)?.executeAndReturnError(nil)
            }),
        ]

        let bannerText = ThemeManager.shared.activeTheme?.config.name ?? "Windows 98"
        let panel = StartMenuPanel()
        startMenuPanel = panel
        let pt = NSPoint(x: startButtonFrame.minX, y: startButtonFrame.maxY + 2)
        panel.show(items: items, bannerText: bannerText, at: pt, in: self, startButtonRect: startButtonFrame)
    }

    /// Opens a Finder window showing recently modified files (macOS "Recents"-style)
    /// by writing a temporary smart-folder saved search and opening it.
    static func openRecentDocuments() {
        let query = "(kMDItemContentModificationDate >= $time.now(-2592000)) && (kMDItemContentType != public.folder)"
        let plist: [String: Any] = [
            "RawQuery": query,
            "RawQueryDict": [
                "RawQuery": query,
                "SearchScopes": ["kMDQueryScopeComputer"]
            ],
            "SearchCriteria": [:] as [String: Any]
        ]
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("RetroMac-Recents.savedSearch")
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: url)
            NSWorkspace.shared.open(url)
        } catch {
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"))
        }
    }

    private func startMenuIcon(_ name: String) -> NSImage? {
        // Mirror the XP `xpIcon` loader exactly: load straight from the active theme's
        // icons directory and return the image AS-IS. Do NOT mutate `img.size` here —
        // the start-menu views draw into their own fixed icon rects via `draw(in:)`, and
        // pre-shrinking the image to 16×16 (while the views ask for 20px) was the source
        // of the "Win98 menu icons missing" report. Returning the unmodified image makes
        // the classic Win98 path identical to the working XP path.
        guard let theme = ThemeManager.shared.activeTheme else { return nil }
        let iconURL = theme.iconsDirectory.appendingPathComponent(name)
        return NSImage(contentsOf: iconURL)
    }

    private func dismissStartMenu() {
        startMenuPanel?.dismiss()
        startMenuPanel = nil
    }

    // MARK: - Clock

    private func startClockTimer() {
        guard clockTimer == nil else { return }
        let clockFmt = ThemeManager.shared.activeTheme?.config.dock.clockFormat
        let hasSeconds = clockFmt?.contains("ss") == true
        let interval: TimeInterval = hasSeconds ? 1 : 30
        clockTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateClockString()
            self?.needsDisplay = true
        }
    }

    private func updateClockString() {
        let fmt = DateFormatter()
        let base = ThemeManager.shared.activeTheme?.config.dock.clockFormat ?? "h:mm a"
        fmt.dateFormat = AppSettings.applyClockFormat(base)
        clockString = fmt.string(from: Date())
    }

    private func updateDiskFreeString() {
        guard hasDiskFree else {
            diskFreeLabel = ""; diskFreeValue = ""; diskFreeUnit = ""
            return
        }
        let url = URL(fileURLWithPath: "/")
        // Get filesystem type (APFS, HFS+, etc.)
        var statBuf = statfs()
        let fsType: String
        if statfs("/", &statBuf) == 0 {
            fsType = withUnsafePointer(to: &statBuf.f_fstypename) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                    String(cString: $0).uppercased()
                }
            }
        } else {
            fsType = "APFS"
        }
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let freeBytes = values.volumeAvailableCapacityForImportantUsage {
            let gb = Double(freeBytes) / 1_000_000_000
            diskFreeLabel = "(\(fsType))"
            if gb >= 100 {
                diskFreeValue = "\(Int(gb))"
            } else {
                diskFreeValue = String(format: "%.1f", gb)
            }
            diskFreeUnit = "GB Free"
        } else {
            diskFreeLabel = ""; diskFreeValue = ""; diskFreeUnit = ""
        }
    }
}
