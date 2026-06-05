import AppKit

/// Start menu popup supporting classic Win98 style and XP Luna Blue style.
final class StartMenuPanel: NSPanel {
    private var menuContentView: NSView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private weak var dockWindow: NSWindow?
    /// Screen-space rect of the start button — clicks here are passed through (DockView handles toggle)
    private var startButtonScreenRect: NSRect = .zero

    struct MenuItem {
        let title: String
        let icon: NSImage?
        let action: (() -> Void)?
        let submenuItems: [MenuItem]?
        let isSeparator: Bool
        let isBold: Bool
        /// App bundle id, when this entry represents a launchable app — enables the
        /// right-click "Set Custom Icon…" context menu (persisted via ThemeManager).
        let bundleID: String?

        init(title: String, icon: NSImage? = nil, action: (() -> Void)? = nil, submenuItems: [MenuItem]? = nil, isBold: Bool = false, bundleID: String? = nil) {
            self.title = title
            self.icon = icon
            self.action = action
            self.submenuItems = submenuItems
            self.isSeparator = false
            self.isBold = isBold
            self.bundleID = bundleID
        }

        init(separator: Bool) {
            self.title = ""
            self.icon = nil
            self.action = nil
            self.submenuItems = nil
            self.isSeparator = true
            self.isBold = false
            self.bundleID = nil
        }
    }

    /// XP-style start menu uses separate left/right column items
    struct XPMenuData {
        let leftItems: [MenuItem]    // pinned apps (white panel)
        let rightItems: [MenuItem]   // system folders (blue panel)
        let allProgramsAction: (() -> Void)?
        let logOffAction: (() -> Void)?
        let shutDownAction: (() -> Void)?
        let userName: String
        let logOffIcon: NSImage?
        let shutDownIcon: NSImage?
    }

    // MARK: - macOS account picture (for the XP start-menu avatar)

    private static var cachedUserPicture: NSImage?? = nil
    static func macUserPicture() -> NSImage? {
        if let cached = cachedUserPicture { return cached }
        let img = loadMacUserPicture()
        cachedUserPicture = .some(img)
        return img
    }
    private static func dsclRead(_ key: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        p.arguments = [".", "-read", "/Users/\(NSUserName())", key]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
    private static func loadMacUserPicture() -> NSImage? {
        // Custom photo set in System Settings is stored as a hex JPEGPhoto attribute.
        let jpeg = dsclRead("JPEGPhoto")
        if jpeg.contains("JPEGPhoto") {
            let hex = jpeg.replacingOccurrences(of: "JPEGPhoto:", with: "")
                .components(separatedBy: .whitespacesAndNewlines).joined()
            if hex.count > 64 {
                var bytes = [UInt8](); bytes.reserveCapacity(hex.count / 2)
                var idx = hex.startIndex
                while let next = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex), next <= hex.endIndex {
                    if let b = UInt8(hex[idx..<next], radix: 16) { bytes.append(b) }
                    idx = next
                }
                if let img = NSImage(data: Data(bytes)) { return img }
            }
        }
        // Otherwise the Picture attribute points to an image file on disk.
        let pic = dsclRead("Picture")
        if let line = pic.components(separatedBy: "\n").first(where: { $0.contains("/") }) {
            let path = line.replacingOccurrences(of: "Picture:", with: "").trimmingCharacters(in: .whitespaces)
            if let img = NSImage(contentsOfFile: path) { return img }
        }
        return nil
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: 27)
        collectionBehavior = [.canJoinAllSpaces, .stationary]
    }

    // MARK: - Classic Win98 Style

    func show(items: [MenuItem], bannerText: String, at point: NSPoint, in parentView: NSView, startButtonRect: NSRect = .zero) {
        let content = ClassicStartMenuContentView(items: items, bannerText: bannerText)
        content.onDismiss = { [weak self] in self?.dismiss() }
        self.menuContentView = content

        let size = content.fittingSize
        content.frame = NSRect(origin: .zero, size: size)
        self.contentView = content

        positionAndShow(size: size, at: point, in: parentView, startButtonRect: startButtonRect)
    }

    // MARK: - XP Luna Blue Style

    func showXP(data: XPMenuData, at point: NSPoint, in parentView: NSView, startButtonRect: NSRect = .zero) {
        let content = XPStartMenuContentView(data: data)
        content.onDismiss = { [weak self] in self?.dismiss() }
        self.menuContentView = content

        let size = content.fittingSize
        content.frame = NSRect(origin: .zero, size: size)
        self.contentView = content

        positionAndShow(size: size, at: point, in: parentView, startButtonRect: startButtonRect)
    }

    private func positionAndShow(size: NSSize, at point: NSPoint, in parentView: NSView, startButtonRect: NSRect = .zero) {
        guard let parentWindow = parentView.window else { return }
        self.dockWindow = parentWindow
        // Convert start button rect to screen coordinates
        if !startButtonRect.isEmpty {
            let winRect = parentView.convert(startButtonRect, to: nil)
            self.startButtonScreenRect = parentWindow.convertToScreen(winRect)
        } else {
            self.startButtonScreenRect = .zero
        }
        let screenPoint = parentWindow.convertPoint(toScreen: parentView.convert(point, to: nil))
        let panelOrigin = NSPoint(x: screenPoint.x, y: screenPoint.y)
        setFrame(NSRect(origin: panelOrigin, size: size), display: true)
        orderFrontRegardless()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return }
            // Don't dismiss if clicking the start button (DockView toggle handles it)
            if !self.startButtonScreenRect.isEmpty {
                let loc = NSEvent.mouseLocation
                if self.startButtonScreenRect.contains(loc) { return }
            }
            self.dismiss()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            if event.window == self { return event }
            // Allow clicks on submenu panels (Favorites, Programs, etc.)
            if let classic = self.menuContentView as? ClassicStartMenuContentView,
               let subPanel = classic.submenuPanel,
               event.window == subPanel {
                return event
            }
            // Click on dock window: only pass through if on start button (DockView toggles)
            if event.window == self.dockWindow {
                if !self.startButtonScreenRect.isEmpty {
                    let loc = NSEvent.mouseLocation
                    if self.startButtonScreenRect.contains(loc) {
                        return event
                    }
                }
            }
            self.dismiss()
            return event
        }
    }

    func dismiss() {
        if let classic = menuContentView as? ClassicStartMenuContentView {
            classic.dismissSubmenu()
        }
        orderOut(nil)
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor); globalMonitor = nil }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor); localMonitor = nil }
    }
}

// MARK: - XP Luna Blue Start Menu

private final class XPStartMenuContentView: NSView {
    private let data: StartMenuPanel.XPMenuData
    var onDismiss: (() -> Void)?

    // Layout constants
    private let menuWidth: CGFloat = 370
    private let headerHeight: CGFloat = 54
    private let footerHeight: CGFloat = 36
    private let leftColumnWidth: CGFloat = 190
    private let itemHeight: CGFloat = 34
    private let largeItemHeight: CGFloat = 40
    private let iconSizeLarge: CGFloat = 32
    private let iconSizeSmall: CGFloat = 24   // harmonized: all right-column icons same size
    private let borderWidth: CGFloat = 2
    private let separatorHeight: CGFloat = 8

    // Colors
    private let headerBlueTop = NSColor(red: 0.15, green: 0.33, blue: 0.77, alpha: 1.0)
    private let headerBlueBottom = NSColor(red: 0.04, green: 0.16, blue: 0.57, alpha: 1.0)
    private let leftPanelBg = NSColor.white
    private let rightPanelBg = NSColor(red: 0.82, green: 0.87, blue: 0.96, alpha: 1.0)
    private let footerGray = NSColor(red: 0.82, green: 0.87, blue: 0.96, alpha: 1.0)
    private let borderBlue = NSColor(red: 0.04, green: 0.16, blue: 0.57, alpha: 1.0)
    private let hoverBlue = NSColor(red: 0.24, green: 0.38, blue: 0.82, alpha: 1.0)
    private let orangeHighlight = NSColor(red: 0.17, green: 0.35, blue: 0.78, alpha: 0.15)
    private let footerBtnBg = NSColor(red: 0.22, green: 0.41, blue: 0.82, alpha: 1.0)

    private var hoveredSection: HoverSection? = nil
    private var trackingArea: NSTrackingArea?

    private enum HoverSection: Equatable {
        case left(Int)
        case right(Int)
        case allPrograms
        case logOff
        case shutDown
    }

    init(data: StartMenuPanel.XPMenuData) {
        self.data = data
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: NSSize {
        let leftCount = data.leftItems.count
        let rightCount = data.rightItems.count
        let maxItems = max(leftCount, rightCount)

        // Calculate left column height
        var leftHeight: CGFloat = 0
        for item in data.leftItems {
            leftHeight += item.isSeparator ? separatorHeight : largeItemHeight
        }
        leftHeight += largeItemHeight // "All Programs" row

        // Calculate right column height
        var rightHeight: CGFloat = 0
        for item in data.rightItems {
            rightHeight += item.isSeparator ? separatorHeight : itemHeight
        }

        let contentHeight = max(leftHeight, rightHeight)
        let totalHeight = headerHeight + contentHeight + footerHeight + borderWidth * 2
        return NSSize(width: menuWidth, height: totalHeight)
    }

    private var contentHeight: CGFloat {
        var leftHeight: CGFloat = 0
        for item in data.leftItems {
            leftHeight += item.isSeparator ? separatorHeight : largeItemHeight
        }
        leftHeight += largeItemHeight // "All Programs" row

        var rightHeight: CGFloat = 0
        for item in data.rightItems {
            rightHeight += item.isSeparator ? separatorHeight : itemHeight
        }

        return max(leftHeight, rightHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let section = hitSection(at: local)
        if section != hoveredSection {
            hoveredSection = section
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredSection = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard let section = hitSection(at: local) else { return }

        switch section {
        case .left(let idx):
            let item = data.leftItems[idx]
            guard !item.isSeparator else { return }
            item.action?()
            onDismiss?()
        case .right(let idx):
            let item = data.rightItems[idx]
            guard !item.isSeparator else { return }
            item.action?()
            onDismiss?()
        case .allPrograms:
            data.allProgramsAction?()
            // Don't dismiss — might open a submenu
        case .logOff:
            data.logOffAction?()
            onDismiss?()
        case .shutDown:
            data.shutDownAction?()
            onDismiss?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard let section = hitSection(at: local) else { return }
        let item: StartMenuPanel.MenuItem?
        switch section {
        case .left(let idx):  item = data.leftItems[idx]
        case .right(let idx): item = data.rightItems[idx]
        default:              item = nil
        }
        guard let it = item, let bid = it.bundleID else { return }
        CustomIconPicker.present(for: bid, in: self, at: local) { [weak self] in self?.onDismiss?() }
    }

    private func hitSection(at point: NSPoint) -> HoverSection? {
        let bw = borderWidth
        let cHeight = contentHeight

        // Footer area
        let footerTop = bw + footerHeight
        if point.y >= bw && point.y < footerTop {
            // Log Off and Turn Off Computer buttons
            let midX = bounds.width / 2
            if point.x < midX {
                return .logOff
            } else {
                return .shutDown
            }
        }

        // Content area
        let contentBottom = footerTop
        let contentTop = contentBottom + cHeight

        if point.y >= contentBottom && point.y < contentTop {
            let leftEnd = bw + leftColumnWidth
            let rightStart = leftEnd

            if point.x >= bw && point.x < leftEnd {
                // Left column
                var y = contentTop
                for (i, item) in data.leftItems.enumerated() {
                    let h = item.isSeparator ? separatorHeight : largeItemHeight
                    y -= h
                    if point.y >= y && point.y < y + h {
                        return .left(i)
                    }
                }
                // "All Programs" row at bottom
                let allProgY = y - largeItemHeight
                if point.y >= allProgY && point.y < y {
                    return .allPrograms
                }
            } else if point.x >= rightStart && point.x < bounds.width - bw {
                // Right column
                var y = contentTop
                for (i, item) in data.rightItems.enumerated() {
                    let h = item.isSeparator ? separatorHeight : itemHeight
                    y -= h
                    if point.y >= y && point.y < y + h {
                        return .right(i)
                    }
                }
            }
        }

        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let bw = borderWidth
        let cHeight = contentHeight

        // 1. Blue border around entire menu
        borderBlue.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()

        let innerRect = bounds.insetBy(dx: bw, dy: bw)

        // 2. Header — blue gradient with user name
        let headerRect = NSRect(
            x: bw, y: bounds.height - bw - headerHeight,
            width: innerRect.width, height: headerHeight
        )
        let headerPath = NSBezierPath()
        let topRadius: CGFloat = 3
        headerPath.move(to: NSPoint(x: headerRect.minX, y: headerRect.minY))
        headerPath.line(to: NSPoint(x: headerRect.minX, y: headerRect.maxY - topRadius))
        headerPath.curve(to: NSPoint(x: headerRect.minX + topRadius, y: headerRect.maxY),
                         controlPoint1: NSPoint(x: headerRect.minX, y: headerRect.maxY),
                         controlPoint2: NSPoint(x: headerRect.minX, y: headerRect.maxY))
        headerPath.line(to: NSPoint(x: headerRect.maxX - topRadius, y: headerRect.maxY))
        headerPath.curve(to: NSPoint(x: headerRect.maxX, y: headerRect.maxY - topRadius),
                         controlPoint1: NSPoint(x: headerRect.maxX, y: headerRect.maxY),
                         controlPoint2: NSPoint(x: headerRect.maxX, y: headerRect.maxY))
        headerPath.line(to: NSPoint(x: headerRect.maxX, y: headerRect.minY))
        headerPath.close()

        let headerGrad = NSGradient(
            starting: headerBlueBottom,
            ending: headerBlueTop
        )
        headerGrad?.draw(in: headerPath, angle: 90)

        // User avatar (white circle with person icon)
        let avatarSize: CGFloat = 36
        let avatarX = headerRect.minX + 10
        let avatarY = headerRect.midY - avatarSize / 2
        let avatarRect = NSRect(x: avatarX, y: avatarY, width: avatarSize, height: avatarSize)

        // Draw avatar frame (white border with slight shadow)
        NSColor.white.setStroke()
        let avatarFrame = NSBezierPath(roundedRect: avatarRect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
        avatarFrame.lineWidth = 2
        avatarFrame.stroke()

        // Real macOS account picture, clipped to the rounded avatar frame; falls back to the
        // generic person glyph when no account picture is available.
        if let photo = StartMenuPanel.macUserPicture() {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: avatarRect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3).addClip()
            photo.draw(in: avatarRect.insetBy(dx: 1, dy: 1), from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
        } else if let personImg = NSImage(systemSymbolName: "person.fill", accessibilityDescription: "User") {
            let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
            if let configured = personImg.withSymbolConfiguration(config) {
                let imgSize: CGFloat = 24
                let imgRect = NSRect(
                    x: avatarRect.midX - imgSize / 2,
                    y: avatarRect.midY - imgSize / 2,
                    width: imgSize, height: imgSize
                )
                NSColor.white.set()
                configured.draw(in: imgRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
        }

        // User name text
        let userNameX = avatarRect.maxX + 8
        let userFont = NSFont.boldSystemFont(ofSize: 13)
        let userAttrs: [NSAttributedString.Key: Any] = [
            .font: userFont,
            .foregroundColor: NSColor.white,
        ]
        let userTextSize = (data.userName as NSString).size(withAttributes: userAttrs)
        let userTextY = headerRect.midY - userTextSize.height / 2
        (data.userName as NSString).draw(
            at: NSPoint(x: userNameX, y: userTextY),
            withAttributes: userAttrs
        )

        // 3. Content area
        let contentTop = headerRect.minY
        let contentBottom = bw + footerHeight

        // Left panel (white)
        let leftRect = NSRect(
            x: bw, y: contentBottom,
            width: leftColumnWidth, height: contentTop - contentBottom
        )
        leftPanelBg.setFill()
        NSBezierPath(rect: leftRect).fill()

        // Right panel (light blue)
        let rightRect = NSRect(
            x: bw + leftColumnWidth, y: contentBottom,
            width: innerRect.width - leftColumnWidth, height: contentTop - contentBottom
        )
        rightPanelBg.setFill()
        NSBezierPath(rect: rightRect).fill()

        // Subtle separator line between columns
        let sepLineColor = NSColor(red: 0.75, green: 0.80, blue: 0.90, alpha: 1.0)
        sepLineColor.setStroke()
        let colSep = NSBezierPath()
        colSep.move(to: NSPoint(x: leftRect.maxX, y: contentBottom))
        colSep.line(to: NSPoint(x: leftRect.maxX, y: contentTop))
        colSep.lineWidth = 1
        colSep.stroke()

        // 4. Draw left column items
        var yLeft = contentTop
        for (i, item) in data.leftItems.enumerated() {
            if item.isSeparator {
                yLeft -= separatorHeight
                // Draw separator line
                let sepY = yLeft + separatorHeight / 2
                NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0).setStroke()
                let sepLine = NSBezierPath()
                sepLine.move(to: NSPoint(x: leftRect.minX + 8, y: sepY))
                sepLine.line(to: NSPoint(x: leftRect.maxX - 8, y: sepY))
                sepLine.lineWidth = 1
                sepLine.stroke()
                continue
            }

            let itemRect = NSRect(x: leftRect.minX, y: yLeft - largeItemHeight, width: leftRect.width, height: largeItemHeight)
            yLeft -= largeItemHeight

            // Hover highlight
            if hoveredSection == .left(i) {
                hoverBlue.withAlphaComponent(0.15).setFill()
                NSBezierPath(rect: itemRect).fill()
            }

            // Icon
            let iconX = itemRect.minX + 8
            let icoSize = iconSizeLarge
            let iconY = itemRect.midY - icoSize / 2
            if let icon = item.icon {
                icon.draw(in: NSRect(x: iconX, y: iconY, width: icoSize, height: icoSize))
            }

            // Text
            let textX = iconX + icoSize + 8
            let font = item.isBold ? NSFont.boldSystemFont(ofSize: 11) : NSFont.systemFont(ofSize: 11)
            let textColor: NSColor = hoveredSection == .left(i) ? hoverBlue : .black
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let textSize = (item.title as NSString).size(withAttributes: attrs)
            let textY = itemRect.midY - textSize.height / 2
            (item.title as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
        }

        // "All Programs" row
        let allProgRect = NSRect(x: leftRect.minX, y: yLeft - largeItemHeight, width: leftRect.width, height: largeItemHeight)
        yLeft -= largeItemHeight

        // Separator above "All Programs"
        let allProgSepY = allProgRect.maxY
        NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0).setStroke()
        let allProgSep = NSBezierPath()
        allProgSep.move(to: NSPoint(x: leftRect.minX + 8, y: allProgSepY))
        allProgSep.line(to: NSPoint(x: leftRect.maxX - 8, y: allProgSepY))
        allProgSep.lineWidth = 1
        allProgSep.stroke()

        if hoveredSection == .allPrograms {
            hoverBlue.withAlphaComponent(0.15).setFill()
            NSBezierPath(rect: allProgRect).fill()
        }

        let allProgFont = NSFont.boldSystemFont(ofSize: 11)
        let allProgColor: NSColor = hoveredSection == .allPrograms ? hoverBlue : .black
        let allProgAttrs: [NSAttributedString.Key: Any] = [.font: allProgFont, .foregroundColor: allProgColor]
        let allProgText = "All Programs"
        let allProgSize = (allProgText as NSString).size(withAttributes: allProgAttrs)
        let allProgTextY = allProgRect.midY - allProgSize.height / 2
        (allProgText as NSString).draw(
            at: NSPoint(x: allProgRect.maxX - allProgSize.width - 28, y: allProgTextY),
            withAttributes: allProgAttrs
        )
        // Green play triangle arrow (XP authentic)
        let arrowSize: CGFloat = 10
        let arrowX = allProgRect.maxX - 18
        let arrowY = allProgRect.midY
        let arrowPath = NSBezierPath()
        arrowPath.move(to: NSPoint(x: arrowX, y: arrowY + arrowSize / 2))
        arrowPath.line(to: NSPoint(x: arrowX + arrowSize * 0.75, y: arrowY))
        arrowPath.line(to: NSPoint(x: arrowX, y: arrowY - arrowSize / 2))
        arrowPath.close()
        NSColor(red: 0.18, green: 0.60, blue: 0.18, alpha: 1.0).setFill()
        arrowPath.fill()

        // 5. Draw right column items
        var yRight = contentTop
        for (i, item) in data.rightItems.enumerated() {
            if item.isSeparator {
                yRight -= separatorHeight
                let sepY = yRight + separatorHeight / 2
                NSColor(red: 0.68, green: 0.75, blue: 0.88, alpha: 1.0).setStroke()
                let sepLine = NSBezierPath()
                sepLine.move(to: NSPoint(x: rightRect.minX + 8, y: sepY))
                sepLine.line(to: NSPoint(x: rightRect.maxX - 8, y: sepY))
                sepLine.lineWidth = 1
                sepLine.stroke()
                continue
            }

            let itemRect = NSRect(x: rightRect.minX, y: yRight - itemHeight, width: rightRect.width, height: itemHeight)
            yRight -= itemHeight

            // Hover highlight
            if hoveredSection == .right(i) {
                hoverBlue.withAlphaComponent(0.2).setFill()
                NSBezierPath(rect: itemRect).fill()
            }

            // Icon — uniform size for all right column items
            let iconX = itemRect.minX + 8
            let icoSize = iconSizeSmall
            let iconY = itemRect.midY - icoSize / 2
            if let icon = item.icon {
                icon.draw(in: NSRect(x: iconX, y: iconY, width: icoSize, height: icoSize))
            }

            // Text
            let textX = iconX + iconSizeSmall + 8
            let font = item.isBold ? NSFont.boldSystemFont(ofSize: 11) : NSFont.systemFont(ofSize: 11)
            let textColor: NSColor = hoveredSection == .right(i) ? .white : .black
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let textSize = (item.title as NSString).size(withAttributes: attrs)
            let textY = itemRect.midY - textSize.height / 2
            (item.title as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
        }

        // 6. Footer — blue gradient with Log Off / Turn Off Computer
        let footerRect = NSRect(
            x: bw, y: bw,
            width: innerRect.width, height: footerHeight
        )
        let footerPath = NSBezierPath()
        let btmRadius: CGFloat = 3
        footerPath.move(to: NSPoint(x: footerRect.minX + btmRadius, y: footerRect.maxY))
        footerPath.line(to: NSPoint(x: footerRect.maxX - btmRadius, y: footerRect.maxY))
        footerPath.line(to: NSPoint(x: footerRect.maxX, y: footerRect.maxY))
        footerPath.line(to: NSPoint(x: footerRect.maxX, y: footerRect.minY + btmRadius))
        footerPath.curve(to: NSPoint(x: footerRect.maxX - btmRadius, y: footerRect.minY),
                         controlPoint1: NSPoint(x: footerRect.maxX, y: footerRect.minY),
                         controlPoint2: NSPoint(x: footerRect.maxX, y: footerRect.minY))
        footerPath.line(to: NSPoint(x: footerRect.minX + btmRadius, y: footerRect.minY))
        footerPath.curve(to: NSPoint(x: footerRect.minX, y: footerRect.minY + btmRadius),
                         controlPoint1: NSPoint(x: footerRect.minX, y: footerRect.minY),
                         controlPoint2: NSPoint(x: footerRect.minX, y: footerRect.minY))
        footerPath.line(to: NSPoint(x: footerRect.minX, y: footerRect.maxY))
        footerPath.close()

        let footerGrad = NSGradient(
            starting: NSColor(red: 0.15, green: 0.33, blue: 0.77, alpha: 1.0),
            ending: NSColor(red: 0.16, green: 0.38, blue: 0.85, alpha: 1.0)
        )
        footerGrad?.draw(in: footerPath, angle: 90)

        // Top separator line on footer
        NSColor(red: 0.08, green: 0.22, blue: 0.64, alpha: 1.0).setStroke()
        let footerSepLine = NSBezierPath()
        footerSepLine.move(to: NSPoint(x: footerRect.minX, y: footerRect.maxY))
        footerSepLine.line(to: NSPoint(x: footerRect.maxX, y: footerRect.maxY))
        footerSepLine.lineWidth = 1
        footerSepLine.stroke()

        // Log Off button
        let btnFont = NSFont.systemFont(ofSize: 11)
        let btnY = footerRect.midY

        let logOffText = "Log Off"
        let logOffAttrs: [NSAttributedString.Key: Any] = [
            .font: btnFont,
            .foregroundColor: NSColor.white,
        ]
        let logOffSize = (logOffText as NSString).size(withAttributes: logOffAttrs)

        // Log Off icon
        let logOffIconSize: CGFloat = 16
        let logOffTotalWidth = logOffIconSize + 4 + logOffSize.width
        let logOffStartX = footerRect.minX + footerRect.width * 0.25 - logOffTotalWidth / 2

        if hoveredSection == .logOff {
            let hoverRect = NSRect(x: footerRect.minX, y: footerRect.minY,
                                   width: footerRect.width / 2, height: footerRect.height)
            NSColor.white.withAlphaComponent(0.1).setFill()
            NSBezierPath(rect: hoverRect).fill()
        }

        // Draw log off icon — authentic XP icon
        let logOffIconRect = NSRect(x: logOffStartX, y: btnY - logOffIconSize / 2,
                                     width: logOffIconSize, height: logOffIconSize)
        if let logOffImg = data.logOffIcon {
            logOffImg.draw(in: logOffIconRect)
        } else if let logOffImg = NSImage(systemSymbolName: "rectangle.portrait.and.arrow.right", accessibilityDescription: "Log Off") {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let configured = logOffImg.withSymbolConfiguration(config) {
                configured.draw(in: logOffIconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
        }
        (logOffText as NSString).draw(
            at: NSPoint(x: logOffStartX + logOffIconSize + 4, y: btnY - logOffSize.height / 2),
            withAttributes: logOffAttrs
        )

        // Turn Off Computer button
        let shutDownText = "Turn Off Computer"
        let shutDownAttrs = logOffAttrs
        let shutDownSize = (shutDownText as NSString).size(withAttributes: shutDownAttrs)

        let shutDownIconSize: CGFloat = 16
        let shutDownTotalWidth = shutDownIconSize + 4 + shutDownSize.width
        let shutDownStartX = footerRect.minX + footerRect.width * 0.75 - shutDownTotalWidth / 2

        if hoveredSection == .shutDown {
            let hoverRect = NSRect(x: footerRect.minX + footerRect.width / 2, y: footerRect.minY,
                                   width: footerRect.width / 2, height: footerRect.height)
            NSColor.white.withAlphaComponent(0.1).setFill()
            NSBezierPath(rect: hoverRect).fill()
        }

        // Draw shut down icon — authentic XP icon
        let shutDownIconRect = NSRect(x: shutDownStartX, y: btnY - shutDownIconSize / 2,
                                       width: shutDownIconSize, height: shutDownIconSize)
        if let shutDownImg = data.shutDownIcon {
            shutDownImg.draw(in: shutDownIconRect)
        } else {
            // Fallback: red circle with power symbol
            NSColor(red: 0.90, green: 0.20, blue: 0.15, alpha: 1.0).setFill()
            NSBezierPath(ovalIn: shutDownIconRect.insetBy(dx: 1, dy: 1)).fill()
            if let shutDownImg = NSImage(systemSymbolName: "power", accessibilityDescription: "Turn Off") {
                let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
                if let configured = shutDownImg.withSymbolConfiguration(config) {
                    configured.draw(in: shutDownIconRect.insetBy(dx: 2, dy: 2), from: .zero, operation: .sourceOver, fraction: 1.0)
                }
            }
        }
        (shutDownText as NSString).draw(
            at: NSPoint(x: shutDownStartX + shutDownIconSize + 4, y: btnY - shutDownSize.height / 2),
            withAttributes: shutDownAttrs
        )
    }
}

// MARK: - Classic Win98-Style Content View

private final class ClassicStartMenuContentView: NSView {
    private let items: [StartMenuPanel.MenuItem]
    private let bannerText: String
    private let bannerWidth: CGFloat = 24
    private let itemHeight: CGFloat = 28
    private let separatorHeight: CGFloat = 9
    private let menuWidth: CGFloat = 200
    private let bevelWidth: CGFloat = 2
    private var hoveredIndex: Int? = nil
    private var trackingArea: NSTrackingArea?
    /// The currently visible submenu panel (exposed for parent event monitor)
    private(set) var submenuPanel: StartMenuPanel?

    var onDismiss: (() -> Void)?

    init(items: [StartMenuPanel.MenuItem], bannerText: String) {
        self.items = items
        self.bannerText = bannerText
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: NSSize {
        var h: CGFloat = bevelWidth * 2 + 2
        for item in items {
            h += item.isSeparator ? separatorHeight : itemHeight
        }
        return NSSize(width: bannerWidth + menuWidth + bevelWidth * 2, height: h)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let idx = itemIndex(at: local)
        if idx != hoveredIndex {
            hoveredIndex = idx
            needsDisplay = true

            dismissSubmenu()
            if let idx = idx, !items[idx].isSeparator,
               let subItems = items[idx].submenuItems, !subItems.isEmpty {
                showSubmenu(for: idx, subItems: subItems)
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard let idx = itemIndex(at: local), !items[idx].isSeparator else { return }
        let item = items[idx]
        if item.submenuItems != nil && !(item.submenuItems?.isEmpty ?? true) {
            return
        }
        item.action?()
        onDismiss?()
    }

    override func rightMouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard let idx = itemIndex(at: local), !items[idx].isSeparator,
              let bid = items[idx].bundleID else { return }
        CustomIconPicker.present(for: bid, in: self, at: local) { [weak self] in self?.onDismiss?() }
    }

    func dismissSubmenu() {
        submenuPanel?.dismiss()
        submenuPanel = nil
    }

    private func showSubmenu(for index: Int, subItems: [StartMenuPanel.MenuItem]) {
        let panel = StartMenuPanel()
        let content = ClassicStartMenuContentView(items: subItems, bannerText: "")
        content.onDismiss = { [weak self] in self?.onDismiss?() }
        let size = NSSize(
            width: menuWidth + bevelWidth * 2,
            height: content.fittingSize.height
        )
        let subContent = SubmenuContentView(items: subItems, itemHeight: itemHeight, menuWidth: menuWidth, bevelWidth: bevelWidth)
        subContent.onDismiss = { [weak self] in self?.onDismiss?() }
        subContent.frame = NSRect(origin: .zero, size: size)
        panel.contentView = subContent

        guard let window = self.window else { return }
        let itemRect = rectForItem(at: index)
        let topRight = NSPoint(x: bounds.maxX, y: itemRect.midY)
        let screenPoint = window.convertPoint(toScreen: convert(topRight, to: nil))
        let panelOrigin = NSPoint(x: screenPoint.x - 2, y: screenPoint.y - size.height + itemHeight)
        panel.setFrame(NSRect(origin: panelOrigin, size: size), display: true)
        panel.orderFrontRegardless()
        submenuPanel = panel
    }

    private func itemIndex(at point: NSPoint) -> Int? {
        let contentX = bevelWidth + bannerWidth
        let contentWidth = menuWidth
        guard point.x >= contentX && point.x <= contentX + contentWidth else { return nil }

        var y = bounds.height - bevelWidth - 1
        for (i, item) in items.enumerated() {
            let h = item.isSeparator ? separatorHeight : itemHeight
            y -= h
            if point.y >= y && point.y < y + h {
                return i
            }
        }
        return nil
    }

    private func rectForItem(at index: Int) -> NSRect {
        let contentX = bevelWidth + bannerWidth
        var y = bounds.height - bevelWidth - 1
        for (i, item) in items.enumerated() {
            let h = item.isSeparator ? separatorHeight : itemHeight
            y -= h
            if i == index {
                return NSRect(x: contentX, y: y, width: menuWidth, height: h)
            }
        }
        return .zero
    }

    override func draw(_ dirtyRect: NSRect) {
        let gray = NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1)

        gray.setFill()
        NSBezierPath(rect: bounds).fill()

        let bw = bevelWidth
        NSColor.white.setStroke()
        var line = NSBezierPath()
        line.move(to: NSPoint(x: bounds.minX + bw / 2, y: bounds.minY))
        line.line(to: NSPoint(x: bounds.minX + bw / 2, y: bounds.maxY))
        line.lineWidth = bw; line.stroke()
        line = NSBezierPath()
        line.move(to: NSPoint(x: bounds.minX, y: bounds.maxY - bw / 2))
        line.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - bw / 2))
        line.lineWidth = bw; line.stroke()

        NSColor(white: 0.5, alpha: 1).setStroke()
        line = NSBezierPath()
        line.move(to: NSPoint(x: bounds.maxX - bw / 2, y: bounds.minY))
        line.line(to: NSPoint(x: bounds.maxX - bw / 2, y: bounds.maxY))
        line.lineWidth = bw; line.stroke()
        line = NSBezierPath()
        line.move(to: NSPoint(x: bounds.minX, y: bounds.minY + bw / 2))
        line.line(to: NSPoint(x: bounds.maxX, y: bounds.minY + bw / 2))
        line.lineWidth = bw; line.stroke()

        let bannerRect = NSRect(x: bw, y: bw + 1, width: bannerWidth, height: bounds.height - bw * 2 - 2)
        let bannerGrad = NSGradient(
            starting: NSColor(red: 0.0, green: 0.0, blue: 0.50, alpha: 1.0),
            ending: NSColor(red: 0.0, green: 0.30, blue: 0.85, alpha: 1.0)
        )
        bannerGrad?.draw(in: bannerRect, angle: 90)

        if !bannerText.isEmpty {
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.saveGState()
            let font = NSFont.boldSystemFont(ofSize: 16)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
            let textSize = (bannerText as NSString).size(withAttributes: attrs)
            let tx = bannerRect.minX + (bannerRect.width + textSize.height) / 2
            let ty = bannerRect.minY + 6
            ctx.translateBy(x: tx, y: ty)
            ctx.rotate(by: CGFloat.pi / 2)
            (bannerText as NSString).draw(at: .zero, withAttributes: attrs)
            ctx.restoreGState()
        }

        let contentX = bw + bannerWidth
        var y = bounds.height - bw - 1
        for (i, item) in items.enumerated() {
            if item.isSeparator {
                y -= separatorHeight
                let lineY = y + separatorHeight / 2
                NSColor(white: 0.5, alpha: 1).setStroke()
                line = NSBezierPath()
                line.move(to: NSPoint(x: contentX + 2, y: lineY + 0.5))
                line.line(to: NSPoint(x: contentX + menuWidth - 2, y: lineY + 0.5))
                line.lineWidth = 1; line.stroke()
                NSColor.white.setStroke()
                line = NSBezierPath()
                line.move(to: NSPoint(x: contentX + 2, y: lineY - 0.5))
                line.line(to: NSPoint(x: contentX + menuWidth - 2, y: lineY - 0.5))
                line.lineWidth = 1; line.stroke()
                continue
            }

            let itemRect = NSRect(x: contentX, y: y - itemHeight, width: menuWidth, height: itemHeight)
            y -= itemHeight

            if hoveredIndex == i {
                NSColor(red: 0.0, green: 0.0, blue: 0.50, alpha: 1.0).setFill()
                NSBezierPath(rect: itemRect).fill()
            }

            let textColor: NSColor = hoveredIndex == i ? .white : .black
            let iconX = itemRect.minX + 6
            let iconSize: CGFloat = 20
            let iconY = itemRect.midY - iconSize / 2

            if let icon = item.icon {
                icon.draw(in: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
            }

            let textX = iconX + iconSize + 6
            let font = NSFont.systemFont(ofSize: 12)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let textSize = (item.title as NSString).size(withAttributes: attrs)
            let textY = itemRect.midY - textSize.height / 2
            (item.title as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)

            if item.submenuItems != nil && !(item.submenuItems?.isEmpty ?? true) {
                let arrowFont = NSFont.systemFont(ofSize: 10)
                let arrowAttrs: [NSAttributedString.Key: Any] = [.font: arrowFont, .foregroundColor: textColor]
                let arrowStr = "▸"
                let arrowSize = (arrowStr as NSString).size(withAttributes: arrowAttrs)
                (arrowStr as NSString).draw(
                    at: NSPoint(x: itemRect.maxX - arrowSize.width - 8,
                                y: itemRect.midY - arrowSize.height / 2),
                    withAttributes: arrowAttrs
                )
            }
        }
    }
}

// MARK: - Submenu Content View (no blue banner)

private final class SubmenuContentView: NSView {
    private let items: [StartMenuPanel.MenuItem]
    private let itemHeight: CGFloat
    private let menuWidth: CGFloat
    private let bevelWidth: CGFloat
    private var hoveredIndex: Int? = nil
    private var trackingArea: NSTrackingArea?

    var onDismiss: (() -> Void)?

    init(items: [StartMenuPanel.MenuItem], itemHeight: CGFloat, menuWidth: CGFloat, bevelWidth: CGFloat) {
        self.items = items
        self.itemHeight = itemHeight
        self.menuWidth = menuWidth
        self.bevelWidth = bevelWidth
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let idx = itemIndex(at: local)
        if idx != hoveredIndex {
            hoveredIndex = idx
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard let idx = itemIndex(at: local), !items[idx].isSeparator else { return }
        items[idx].action?()
        onDismiss?()
    }

    override func rightMouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard let idx = itemIndex(at: local), !items[idx].isSeparator,
              let bid = items[idx].bundleID else { return }
        CustomIconPicker.present(for: bid, in: self, at: local) { [weak self] in self?.onDismiss?() }
    }

    private func itemIndex(at point: NSPoint) -> Int? {
        guard point.x >= bevelWidth && point.x <= bounds.width - bevelWidth else { return nil }
        var y = bounds.height - bevelWidth - 1
        for (i, item) in items.enumerated() {
            let h = item.isSeparator ? 9.0 : itemHeight
            y -= h
            if point.y >= y && point.y < y + h {
                return i
            }
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let gray = NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1)
        let bw = bevelWidth

        gray.setFill()
        NSBezierPath(rect: bounds).fill()

        NSColor.white.setStroke()
        var line = NSBezierPath()
        line.move(to: NSPoint(x: bounds.minX + bw / 2, y: bounds.minY))
        line.line(to: NSPoint(x: bounds.minX + bw / 2, y: bounds.maxY))
        line.lineWidth = bw; line.stroke()
        line = NSBezierPath()
        line.move(to: NSPoint(x: bounds.minX, y: bounds.maxY - bw / 2))
        line.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - bw / 2))
        line.lineWidth = bw; line.stroke()

        NSColor(white: 0.5, alpha: 1).setStroke()
        line = NSBezierPath()
        line.move(to: NSPoint(x: bounds.maxX - bw / 2, y: bounds.minY))
        line.line(to: NSPoint(x: bounds.maxX - bw / 2, y: bounds.maxY))
        line.lineWidth = bw; line.stroke()
        line = NSBezierPath()
        line.move(to: NSPoint(x: bounds.minX, y: bounds.minY + bw / 2))
        line.line(to: NSPoint(x: bounds.maxX, y: bounds.minY + bw / 2))
        line.lineWidth = bw; line.stroke()

        var y = bounds.height - bw - 1
        for (i, item) in items.enumerated() {
            if item.isSeparator {
                y -= 9
                let lineY = y + 4.5
                NSColor(white: 0.5, alpha: 1).setStroke()
                line = NSBezierPath()
                line.move(to: NSPoint(x: bw + 2, y: lineY + 0.5))
                line.line(to: NSPoint(x: bounds.width - bw - 2, y: lineY + 0.5))
                line.lineWidth = 1; line.stroke()
                NSColor.white.setStroke()
                line = NSBezierPath()
                line.move(to: NSPoint(x: bw + 2, y: lineY - 0.5))
                line.line(to: NSPoint(x: bounds.width - bw - 2, y: lineY - 0.5))
                line.lineWidth = 1; line.stroke()
                continue
            }

            let itemRect = NSRect(x: bw, y: y - itemHeight, width: bounds.width - bw * 2, height: itemHeight)
            y -= itemHeight

            if hoveredIndex == i {
                NSColor(red: 0.0, green: 0.0, blue: 0.50, alpha: 1.0).setFill()
                NSBezierPath(rect: itemRect).fill()
            }

            let textColor: NSColor = hoveredIndex == i ? .white : .black
            let iconX = itemRect.minX + 6
            let iconSize: CGFloat = 20
            let iconY = itemRect.midY - iconSize / 2

            if let icon = item.icon {
                icon.draw(in: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
            }

            let textX = iconX + iconSize + 6
            let font = NSFont.systemFont(ofSize: 12)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let textSize = (item.title as NSString).size(withAttributes: attrs)
            let textY = itemRect.midY - textSize.height / 2
            (item.title as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
        }
    }
}
