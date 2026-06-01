import AppKit

final class DockView: NSView {
    private var itemViews: [DockItemView] = []
    // Resting Y-centres of vertical-dock icons, captured at layout time. The frame-based
    // vertical magnifier mutates item frames, so it must read REST positions from here
    // (not the live, already-magnified frames) to avoid compounding spacing/jitter.
    private var restCentersY: [CGFloat] = []
    private var runningBundleIDs: Set<String> = []
    private var lastItemBundleIDs: [String] = []
    private var wsObserver: NSObjectProtocol?
    private var appsObserver: NSObjectProtocol?
    private var themeObserver: NSObjectProtocol?
    private var wsTerminateObserver: NSObjectProtocol?
    private var wsActivateObserver: NSObjectProtocol?
    private var dropInsertionIndex: Int?
    private var separatorX: CGFloat?
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
    var magnificationOverflow: CGFloat = 0
    /// Extra width on each side of the window for magnification expansion
    var horizontalMagOverflow: CGFloat = 0
    /// Scale factor applied when the dock is too wide for the screen (1.0 = no shrink)
    var dynamicScale: CGFloat = 1.0
    /// Expanded dock bar rect during magnification (nil = use resting rect)
    private var magnifiedDockBarRect: NSRect?

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
        clockTimer?.invalidate()
        trashPollTimer?.invalidate()
        trashMonitorSource?.cancel()
        if trashDirectoryFD >= 0 { close(trashDirectoryFD) }
        let wsNC = NSWorkspace.shared.notificationCenter
        if let obs = wsObserver { wsNC.removeObserver(obs) }
        if let obs = wsTerminateObserver { wsNC.removeObserver(obs) }
        if let obs = wsActivateObserver { wsNC.removeObserver(obs) }
        if let obs = appsObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = themeObserver { NotificationCenter.default.removeObserver(obs) }
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
            self?.rebuildItems()
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
        trashPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateTrashIcon()
        }
        updateTrashIcon()

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
            self?.updateTrashIcon()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        trashMonitorSource = source
    }

    private func isTrashEmpty() -> Bool {
        guard let trashURL = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return true }
        let contents = (try? FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil, options: [])) ?? []
        // Ignore Finder bookkeeping files — any real item means the trash is full.
        return contents.filter { $0.lastPathComponent != ".DS_Store" }.isEmpty
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
        separatorX = nil
        separatorY = nil
        trashSeparatorX = nil
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
            if hasTrash {
                y -= spacing
                addTrashItem(frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                             theme: theme, iconSize: iconSize)
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

                if isXP {
                    // XP Luna: content-based sizing — large icon + text fill the button
                    btnHeight = barRect.height
                    btnY = 0
                    let iconSz = max(24, btnHeight * 0.60)
                    let label = theme.dock.startButtonLabel ?? "start"
                    let fontSize = max(16, btnHeight * 0.47)
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
                        // Classic style: text-based sizing
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

            for app in apps {
                let y = (barRect.height - iconSize) / 2
                addItem(bundleID: app.bundleID,
                        frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
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

            if hasTrash {
                trashSeparatorX = x - spacing / 2
                x += spacing
                let y = (barRect.height - iconSize) / 2
                addTrashItem(frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                             theme: theme, iconSize: iconSize)
            }
        }

        lastItemBundleIDs = itemViews.map { $0.bundleID }
        updateRunningIndicators()
        needsDisplay = true
    }

    func relayoutItems() {
        let apps = AppManager.shared.apps
        let transientApps = runningAppsNotInDock()
        var currentIDs = apps.map { $0.bundleID } + transientApps
        if hasTrash && !isControlStrip { currentIDs.append("__trash__") }
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
            if hasTrash, idx < itemViews.count {
                y -= spacing
                trashSeparatorX = nil
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
            if hasTrash && idx < itemViews.count {
                trashSeparatorX = x - spacing / 2
                x += spacing
                let y = (barRect.height - iconSize) / 2
                itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
            }
        }

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
            itemView.onLeftClick = { _ in
                NSWorkspace.shared.open(URL(fileURLWithPath: folderPath))
            }
        } else {
            let icon: NSImage
            if isTransient && ThemeManager.shared.customIconPath(for: bundleID) == nil {
                // Transient (running) apps show their real system icon unless user set a custom one
                icon = ThemeManager.shared.systemIcon(for: bundleID, size: iconSize)
            } else {
                icon = ThemeManager.shared.icon(for: bundleID, size: iconSize)
            }
            itemView.updateIcon(icon)
            itemView.updateTheme(theme)
            itemView.onLeftClick = { [weak self] bid in
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

    private func trashIcon(size: CGFloat) -> NSImage {
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

        let transientApps = runningAppsNotInDock()
        if !transientApps.isEmpty {
            width += spacing + CGFloat(transientApps.count) * (iconSize + spacing)
        }
        if hasTrash {
            width += spacing + iconSize + spacing
        }

        // For vertical docks with grip, add grip height
        if isVertical && hasGrip {
            width += gripHeight
        }

        return width
    }

    private func runningAppsNotInDock() -> [String] {
        guard AppSettings.shared.dockShowRunningApps else { return [] }
        let pinnedIDs = Set(AppManager.shared.apps.map { $0.bundleID })
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard let bid = app.bundleIdentifier,
                      !pinnedIDs.contains(bid),
                      bid != ownBundleID,
                      app.activationPolicy == .regular else { return false }
                return true
            }
            .compactMap { $0.bundleIdentifier }
            .sorted()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let theme = ThemeManager.shared.activeTheme?.config else { return }
        let ctx = NSGraphicsContext.current!.cgContext
        let scale = CGFloat(AppSettings.shared.dockIconScale)
        let bgAlpha = CGFloat(AppSettings.shared.dockTransparency)

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
        if theme.isVertical {
            let paths = verticalBarPaths(rect: rect, radius: cr)
            bgPath = paths.fill
            verticalBorderPath = paths.border
        } else if theme.has3DShelf {
            let topInset = rect.height * 0.15
            bgPath = NSBezierPath()
            bgPath.move(to: NSPoint(x: rect.minX, y: rect.minY))
            bgPath.line(to: NSPoint(x: rect.maxX, y: rect.minY))
            bgPath.line(to: NSPoint(x: rect.maxX - topInset, y: rect.maxY))
            bgPath.line(to: NSPoint(x: rect.minX + topInset, y: rect.maxY))
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

        // 3D shelf: glass highlight on upper portion
        if theme.has3DShelf && !theme.isVertical {
            let topInset = rect.height * 0.15
            let glassHeight = rect.height * 0.4
            let glassRect = NSRect(x: rect.minX + topInset * 0.6, y: rect.maxY - glassHeight,
                                   width: rect.width - topInset * 1.2, height: glassHeight)
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
            let shelfY = rect.minY + rect.height * 0.38
            shelfLine.move(to: NSPoint(x: rect.minX + cr, y: shelfY))
            shelfLine.line(to: NSPoint(x: rect.maxX - cr, y: shelfY))
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

        // Separator between pinned and running apps
        if let sepX = separatorX {
            let sepColor = theme.parsedBorderColor.withAlphaComponent(0.4)
            sepColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: sepX - 0.5, y: rect.height * 0.15, width: 1, height: rect.height * 0.7),
                         xRadius: 0.5, yRadius: 0.5).fill()
        }
        if let sepY = separatorY {
            let sepColor = theme.parsedBorderColor.withAlphaComponent(0.4)
            sepColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.width * 0.15, y: sepY - 0.5, width: rect.width * 0.7, height: 1),
                         xRadius: 0.5, yRadius: 0.5).fill()
        }
        if let trashSepX = trashSeparatorX {
            let sepColor = theme.parsedBorderColor.withAlphaComponent(0.4)
            sepColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: trashSepX - 0.5, y: rect.height * 0.15, width: 1, height: rect.height * 0.7),
                         xRadius: 0.5, yRadius: 0.5).fill()
        }

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
                    // Fallback: simple green gradient
                    let gradTop = theme.dock.startButtonGradientTop.map { NSColor.fromHex($0) }
                        ?? NSColor(red: 0.32, green: 0.74, blue: 0.22, alpha: 1.0)
                    let gradBottom = theme.dock.startButtonGradientBottom.map { NSColor.fromHex($0) }
                        ?? NSColor(red: 0.18, green: 0.56, blue: 0.10, alpha: 1.0)
                    let top = startButtonPressed ? gradBottom : gradTop
                    let bottom = startButtonPressed ? gradTop : gradBottom
                    let btnPath = NSBezierPath(roundedRect: btnRect, xRadius: 3, yRadius: 3)
                    if let grad = NSGradient(starting: bottom, ending: top) {
                        grad.draw(in: btnPath, angle: 90)
                    }
                }

                // Windows flag icon — large, proportional to button height
                let iconSz = max(24, btnH * 0.60)
                if let icon = startButtonIcon {
                    let iconRect = NSRect(
                        x: btnRect.minX + 8 + pressOffset,
                        y: btnRect.midY - iconSz / 2 - pressOffset,
                        width: iconSz, height: iconSz)
                    icon.draw(in: iconRect)
                }

                // "start" label — white bold italic with shadow
                let label = theme.dock.startButtonLabel ?? "start"
                let fontSize = max(16, btnH * 0.47)
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
                    let iconSz = max(14, iconSize * (isSunkenBtn ? 0.60 : 0.65))
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
                        let font = NSFont.boldSystemFont(ofSize: max(11, iconSize * 0.45))
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
            applyMagnification(at: local)
        }
    }

    override func mouseExited(with event: NSEvent) {
        if startButtonHovered {
            startButtonHovered = false
            needsDisplay = true
        }
        if hasMagnification {
            resetMagnification()
        }
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

        // 1. Calculate scale for each icon (raised cosine bell curve)
        var scales: [CGFloat] = []
        for item in itemViews {
            let center = item.frame.midX
            let dist = abs(point.x - center)
            if dist < range {
                let t = dist / range
                let factor = (1.0 + cos(CGFloat.pi * t)) / 2.0
                scales.append(1.0 + (maxScale - 1.0) * factor)
            } else {
                scales.append(1.0)
            }
        }

        // 2. Calculate magnified widths and total
        let originalCenters = itemViews.map { $0.frame.midX }
        let magnifiedWidths = zip(scales, itemViews).map { $1.frame.width * $0 }
        let spacingTotal = CGFloat(max(0, itemViews.count - 1)) * spacing
        let totalMagnified = magnifiedWidths.reduce(CGFloat(0), +) + spacingTotal

        // 3. Position icons centered — the dock bar expands to contain them
        guard let firstStart = itemViews.first?.frame.minX,
              let lastEnd = itemViews.last?.frame.maxX else { return }
        let totalOriginal = itemViews.reduce(CGFloat(0)) { $0 + $1.frame.width } + spacingTotal
        let expansion = totalMagnified - totalOriginal

        // Center the magnified layout around the original center
        let originalCenter = (firstStart + lastEnd) / 2
        var x = originalCenter - totalMagnified / 2

        // Clamp within window bounds (not dock bar — the window is wider)
        if x < padding { x = padding }
        if x + totalMagnified > bounds.width - padding {
            x = max(padding, bounds.width - padding - totalMagnified)
        }

        for (i, item) in itemViews.enumerated() {
            let magnifiedW = magnifiedWidths[i]
            let newCenter = x + magnifiedW / 2
            let dx = newCenter - originalCenters[i]
            let dy = (scales[i] - 1.0) * baseSize / 2  // pop up from dock bar
            item.applyMagnification(scale: scales[i], dx: dx, dy: dy)
            x += magnifiedW + spacing
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

    private func resetMagnification() {
        for item in itemViews {
            item.resetMagnification()
        }
        magnifiedDockBarRect = nil
        // Vertical magnification resizes icon FRAMES, so restore the resting layout.
        if isVertical { relayoutItems() }
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
                }))
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

        // Add separator and running apps not in dock
        let transient = runningAppsNotInDock()
        if !transient.isEmpty && !leftItems.isEmpty {
            leftItems.append(MI(separator: true))
        }
        for bid in transient.prefix(4) {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                let name = FileManager.default.displayName(atPath: appURL.path)
                    .replacingOccurrences(of: ".app", with: "")
                let icon = ThemeManager.shared.icon(for: bid, size: xpIconSize)
                leftItems.append(MI(title: name, icon: icon, action: {
                    AppLauncher.launchOrActivate(bundleID: bid)
                }))
            }
        }

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
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music"))
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
                }))
            } else {
                programItems.append(MI(title: bid, icon: icon, action: {
                    AppLauncher.launchOrActivate(bundleID: bid)
                }))
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
                    }))
                } else {
                    programItems.append(MI(title: bid, icon: icon, action: {
                        AppLauncher.launchOrActivate(bundleID: bid)
                    }))
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
                NotificationCenter.default.post(name: .init("openTVBookmark"), object: idString)
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
            MI(separator: true),
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
        fmt.dateFormat = ThemeManager.shared.activeTheme?.config.dock.clockFormat ?? "h:mm a"
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
