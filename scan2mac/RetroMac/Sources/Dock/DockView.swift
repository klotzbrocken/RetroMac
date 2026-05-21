import AppKit

final class DockView: NSView {
    private var itemViews: [DockItemView] = []
    private var runningBundleIDs: Set<String> = []
    private var lastItemBundleIDs: [String] = []
    private var wsObserver: NSObjectProtocol?
    private var appsObserver: NSObjectProtocol?
    private var themeObserver: NSObjectProtocol?
    private var dropInsertionIndex: Int?
    private var separatorX: CGFloat?
    private var separatorY: CGFloat?
    private var startButtonFrame: NSRect = .zero
    private var clockFrame: NSRect = .zero
    private var clockTimer: Timer?
    private var clockString: String = ""
    private var startButtonIcon: NSImage?
    private var startButtonPressed = false

    private var isVertical: Bool {
        ThemeManager.shared.activeTheme?.config.isVertical ?? false
    }

    private var hasStartButton: Bool {
        ThemeManager.shared.activeTheme?.config.hasStartButton ?? false
    }

    private var hasClock: Bool {
        ThemeManager.shared.activeTheme?.config.hasClock ?? false
    }

    var onContextMenu: ((String, NSPoint) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
        setupObservers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        clockTimer?.invalidate()
        if let obs = wsObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
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
        wsNC.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateRunningIndicators()
        }
        wsNC.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateRunningIndicators()
        }
    }

    func rebuildItems() {
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        separatorX = nil
        separatorY = nil

        let apps = AppManager.shared.apps
        guard let theme = ThemeManager.shared.activeTheme?.config else { return }
        let scale = CGFloat(AppSettings.shared.dockIconScale)
        let iconSize = theme.dock.iconSize * scale
        let spacing = theme.dock.spacing * scale
        let padding = theme.dock.padding * scale
        let vertical = isVertical

        if vertical {
            var y = padding
            for app in apps {
                let x = (bounds.width - iconSize) / 2
                addItem(bundleID: app.bundleID,
                        frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                        theme: theme, iconSize: iconSize)
                y += iconSize + spacing
            }
            let transientApps = runningAppsNotInDock()
            if !transientApps.isEmpty {
                separatorY = y - spacing / 2
                y += spacing
                for bid in transientApps {
                    let x = (bounds.width - iconSize) / 2
                    addItem(bundleID: bid,
                            frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                            theme: theme, iconSize: iconSize)
                    y += iconSize + spacing
                }
            }
        } else {
            var x = padding

            if hasStartButton {
                loadStartButtonIcon()
                let label = theme.dock.startButtonLabel ?? "Start"
                let fontSize = max(11, iconSize * 0.45)
                let font = NSFont.boldSystemFont(ofSize: fontSize)
                let labelWidth = (label as NSString).size(withAttributes: [.font: font]).width
                let iconSz = max(14, iconSize * 0.55)
                let btnWidth = 6 + iconSz + 3 + labelWidth + 6
                let btnHeight = bounds.height - 6
                startButtonFrame = NSRect(x: 3, y: 3, width: btnWidth, height: btnHeight)
                x = startButtonFrame.maxX + spacing
            } else {
                startButtonFrame = .zero
            }

            if hasClock {
                updateClockString()
                startClockTimer()
                let clockFontSize = max(11, iconSize * 0.45)
                let clockFont = NSFont.monospacedDigitSystemFont(ofSize: clockFontSize, weight: .regular)
                let clockTextWidth = (clockString as NSString).size(withAttributes: [.font: clockFont]).width
                let clockWidth = clockTextWidth + 16
                let clockHeight = bounds.height - 6
                clockFrame = NSRect(x: bounds.width - clockWidth - 3, y: 3, width: clockWidth, height: clockHeight)
            } else {
                clockFrame = .zero
                clockTimer?.invalidate()
                clockTimer = nil
            }

            for app in apps {
                let y = (bounds.height - iconSize) / 2
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
                    let y = (bounds.height - iconSize) / 2
                    addItem(bundleID: bid,
                            frame: NSRect(x: x, y: y, width: iconSize, height: iconSize),
                            theme: theme, iconSize: iconSize)
                    x += iconSize + spacing
                }
            }
        }

        lastItemBundleIDs = itemViews.map { $0.bundleID }
        updateRunningIndicators()
        needsDisplay = true
    }

    func relayoutItems() {
        let apps = AppManager.shared.apps
        let transientApps = runningAppsNotInDock()
        let currentIDs = apps.map { $0.bundleID } + transientApps
        if currentIDs != lastItemBundleIDs {
            rebuildItems()
            return
        }

        guard let theme = ThemeManager.shared.activeTheme?.config else { return }
        let scale = CGFloat(AppSettings.shared.dockIconScale)
        let iconSize = theme.dock.iconSize * scale
        let spacing = theme.dock.spacing * scale
        let padding = theme.dock.padding * scale
        let vertical = isVertical

        separatorX = nil
        separatorY = nil

        var idx = 0
        if vertical {
            var y = padding
            for _ in apps {
                guard idx < itemViews.count else { break }
                let x = (bounds.width - iconSize) / 2
                itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
                idx += 1
                y += iconSize + spacing
            }
            if !transientApps.isEmpty {
                separatorY = y - spacing / 2
                y += spacing
                for _ in transientApps {
                    guard idx < itemViews.count else { break }
                    let x = (bounds.width - iconSize) / 2
                    itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
                    idx += 1
                    y += iconSize + spacing
                }
            }
        } else {
            var x = padding

            if hasStartButton {
                loadStartButtonIcon()
                let label = theme.dock.startButtonLabel ?? "Start"
                let fontSize = max(11, iconSize * 0.45)
                let font = NSFont.boldSystemFont(ofSize: fontSize)
                let labelWidth = (label as NSString).size(withAttributes: [.font: font]).width
                let iconSz = max(14, iconSize * 0.55)
                let btnWidth = 6 + iconSz + 3 + labelWidth + 6
                let btnHeight = bounds.height - 6
                startButtonFrame = NSRect(x: 3, y: 3, width: btnWidth, height: btnHeight)
                x = startButtonFrame.maxX + spacing
            } else {
                startButtonFrame = .zero
            }

            if hasClock {
                updateClockString()
                startClockTimer()
                let clockFontSize = max(11, iconSize * 0.45)
                let clockFont = NSFont.monospacedDigitSystemFont(ofSize: clockFontSize, weight: .regular)
                let clockTextWidth = (clockString as NSString).size(withAttributes: [.font: clockFont]).width
                let clockWidth = clockTextWidth + 16
                let clockHeight = bounds.height - 6
                clockFrame = NSRect(x: bounds.width - clockWidth - 3, y: 3, width: clockWidth, height: clockHeight)
            } else {
                clockFrame = .zero
                clockTimer?.invalidate()
                clockTimer = nil
            }

            for _ in apps {
                guard idx < itemViews.count else { break }
                let y = (bounds.height - iconSize) / 2
                itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
                idx += 1
                x += iconSize + spacing
            }
            if !transientApps.isEmpty {
                separatorX = x - spacing / 2
                x += spacing
                for _ in transientApps {
                    guard idx < itemViews.count else { break }
                    let y = (bounds.height - iconSize) / 2
                    itemViews[idx].frame = NSRect(x: x, y: y, width: iconSize, height: iconSize)
                    idx += 1
                    x += iconSize + spacing
                }
            }
        }

        needsDisplay = true
    }

    private func addItem(bundleID: String, frame: NSRect, theme: DockThemeConfig, iconSize: CGFloat) {
        let itemView = DockItemView(bundleID: bundleID, frame: frame)
        let icon = ThemeManager.shared.icon(for: bundleID, size: iconSize)
        itemView.updateIcon(icon)
        itemView.updateTheme(theme)
        itemView.onLeftClick = { [weak self] bid in
            AppLauncher.launchOrActivate(bundleID: bid)
            self?.updateRunningIndicators()
        }
        itemView.onRightClick = { [weak self] bid, point in
            self?.onContextMenu?(bid, point)
        }
        addSubview(itemView)
        itemViews.append(itemView)
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
        for item in itemViews {
            item.setRunningIndicator(visible: running.contains(item.bundleID), theme: theme)
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

        let pinnedCount = CGFloat(AppManager.shared.apps.count)
        var width = padding * 2 + pinnedCount * iconSize + max(0, pinnedCount - 1) * spacing

        let transientApps = runningAppsNotInDock()
        if !transientApps.isEmpty {
            width += spacing + CGFloat(transientApps.count) * (iconSize + spacing)
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

        let rect = bounds
        let cr = theme.dock.cornerRadius * scale

        // Shadow
        if theme.dock.shadowEnabled {
            ctx.saveGState()
            let shadowColor = theme.parsedShadowColor.cgColor
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: theme.dock.shadowRadius, color: shadowColor)
            let bgPath = NSBezierPath(roundedRect: rect, xRadius: cr, yRadius: cr)
            theme.parsedBackgroundColor.setFill()
            bgPath.fill()
            ctx.restoreGState()
        }

        // Background
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: cr, yRadius: cr)
        theme.parsedBackgroundColor.setFill()
        bgPath.fill()

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

        // Border
        if theme.dock.borderWidth > 0 {
            theme.parsedBorderColor.setStroke()
            bgPath.lineWidth = theme.dock.borderWidth
            bgPath.stroke()
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

        // Drop insertion indicator
        if let idx = dropInsertionIndex {
            let iconSize = theme.dock.iconSize * scale
            let spacing = theme.dock.spacing * scale
            let padding = theme.dock.padding * scale
            NSColor.controlAccentColor.setFill()
            if isVertical {
                let y = padding + CGFloat(idx) * (iconSize + spacing) - spacing / 2
                NSBezierPath(roundedRect: NSRect(x: 4, y: y - 1, width: rect.width - 8, height: 2),
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

        // Start button (raised or sunken bevel depending on pressed state)
        if hasStartButton && !startButtonFrame.isEmpty {
            let bw: CGFloat = 2
            let iconSize = theme.dock.iconSize * scale
            let lightColor: NSColor = startButtonPressed ? NSColor(white: 0.5, alpha: 1) : .white
            let darkColor: NSColor = startButtonPressed ? .white : NSColor(white: 0.5, alpha: 1)
            let pressOffset: CGFloat = startButtonPressed ? 1 : 0

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

            let iconSz = max(14, iconSize * 0.55)
            if let icon = startButtonIcon {
                let iconRect = NSRect(
                    x: startButtonFrame.minX + 6 + pressOffset,
                    y: startButtonFrame.midY - iconSz / 2 - pressOffset,
                    width: iconSz, height: iconSz)
                icon.draw(in: iconRect)
            }

            let label = theme.dock.startButtonLabel ?? "Start"
            let font = NSFont.boldSystemFont(ofSize: max(11, iconSize * 0.45))
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let labelSize = (label as NSString).size(withAttributes: attrs)
            let labelX = startButtonFrame.minX + 6 + iconSz + 3 + pressOffset
            let labelY = startButtonFrame.midY - labelSize.height / 2 - pressOffset
            (label as NSString).draw(at: NSPoint(x: labelX, y: labelY), withAttributes: attrs)
        }

        // Clock (sunken bevel)
        if hasClock && !clockFrame.isEmpty {
            let bw: CGFloat = 2

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

            let clockFontSize = max(11, theme.dock.iconSize * scale * 0.45)
            let font = NSFont.monospacedDigitSystemFont(ofSize: clockFontSize, weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let timeSize = (clockString as NSString).size(withAttributes: attrs)
            let tx = clockFrame.midX - timeSize.width / 2
            let ty = clockFrame.midY - timeSize.height / 2
            (clockString as NSString).draw(at: NSPoint(x: tx, y: ty), withAttributes: attrs)
        }
    }

    // MARK: - Hit testing (pass through clicks outside items)

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if hasStartButton && startButtonFrame.contains(local) {
            return self
        }
        for item in itemViews {
            if item.frame.contains(local) {
                return item
            }
        }
        return nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if hasStartButton && startButtonFrame.contains(local) {
            startButtonPressed = true
            needsDisplay = true
            showStartMenu()
            startButtonPressed = false
            needsDisplay = true
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

        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: ["com.apple.application-bundle"]
        ]) as? [URL], let appURL = items.first else { return false }

        guard let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier else { return false }

        AppManager.shared.addApp(bundleID: bundleID)
        return true
    }

    private func hasAppURL(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: ["com.apple.application-bundle"]
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

    // MARK: - Start Button

    private func loadStartButtonIcon() {
        guard startButtonIcon == nil,
              let url = ThemeManager.shared.activeTheme?.startButtonIconURL() else { return }
        startButtonIcon = NSImage(contentsOf: url)
    }

    private func showStartMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for app in AppManager.shared.apps {
            let item = NSMenuItem()
            item.representedObject = app.bundleID
            item.target = self
            item.action = #selector(startMenuLaunch(_:))
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                item.title = FileManager.default.displayName(atPath: appURL.path)
                    .replacingOccurrences(of: ".app", with: "")
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            } else {
                item.title = app.bundleID
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(startMenuSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Shut Down", action: #selector(startMenuQuit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        let pt = NSPoint(x: startButtonFrame.minX, y: startButtonFrame.maxY + 2)
        menu.popUp(positioning: nil, at: pt, in: self)
    }

    @objc private func startMenuLaunch(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        AppLauncher.launchOrActivate(bundleID: bid)
    }

    @objc private func startMenuSettings(_ sender: NSMenuItem) {
        NSApp.sendAction(Selector(("openSettings")), to: nil, from: self)
    }

    @objc private func startMenuQuit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    // MARK: - Clock

    private func startClockTimer() {
        guard clockTimer == nil else { return }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateClockString()
            self?.needsDisplay = true
        }
    }

    private func updateClockString() {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        clockString = fmt.string(from: Date())
    }
}
