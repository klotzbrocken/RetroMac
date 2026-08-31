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

    /// A menu view that can hang a flyout off one of its rows. The panel needs this to keep
    /// itself open while the pointer is inside that flyout, and to take it down with itself.
    protocol SubmenuHost: AnyObject {
        var submenuPanel: StartMenuPanel? { get }
        func dismissSubmenu()
    }

    /// XP-style start menu uses separate left/right column items
    struct XPMenuData {
        let leftItems: [MenuItem]    // pinned apps (white panel)
        let rightItems: [MenuItem]   // system folders (blue panel)
        /// The Programs flyout. When set, "All Programs" opens it instead of running
        /// `allProgramsAction` — the same list the classic Start menu hangs off Programs.
        var allProgramsItems: [MenuItem]? = nil
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
        // The classic Start menu appears instantly — no fade/scale. Without this, AppKit gives a
        // borderless panel a default appear animation, which combined with the alpha-derived drop
        // shadow makes the menu visibly "shimmer"/settle for a frame after it opens.
        animationBehavior = .none
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

    /// Windows 7 Aero two-column menu (frosted glass behind translucent content).
    func showWin7(data: XPMenuData, at point: NSPoint, in parentView: NSView, startButtonRect: NSRect = .zero) {
        let content = Win7StartMenuContentView(data: data)
        content.onDismiss = { [weak self] in self?.dismiss() }
        self.menuContentView = content

        let size = content.fittingSize
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let blur = NSVisualEffectView(frame: container.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.blendingMode = .behindWindow
        blur.material = .fullScreenUI
        blur.state = .active
        blur.appearance = NSAppearance(named: .aqua)
        blur.maskImage = Win7StartMenuContentView.bodyMask(size: size)   // only the body, not the avatar overhang
        container.addSubview(blur)
        content.frame = container.bounds
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)
        self.contentView = container

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
        // Draw the content synchronously before the window server samples its alpha for the drop
        // shadow, then recompute the shadow once more after it is on screen — otherwise the shadow
        // is built from the not-yet-drawn content and visibly re-settles ("wabert") a frame later.
        contentView?.displayIfNeeded()
        orderFrontRegardless()
        invalidateShadow()

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
            if let host = self.menuContentView as? StartMenuPanel.SubmenuHost,
               let subPanel = host.submenuPanel,
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
        (menuContentView as? StartMenuPanel.SubmenuHost)?.dismissSubmenu()
        orderOut(nil)
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor); globalMonitor = nil }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor); localMonitor = nil }
    }
}

// MARK: - Programs flyout (XP / Windows 7)

/// Build and place Windows XP's All Programs list.
///
/// XP does not hang this off the side of the menu: the list is superimposed on the Start menu as
/// a third column in a second layer, its bottom sitting on the All Programs row and its left edge
/// at the right edge of the left column — so it covers the "My Documents" pane while it is open.
/// That is the original behaviour, not a placement accident. (Windows XP Pro: The Missing Manual,
/// "Start → All Programs".) `bottomLeft` is that corner, in the caller's coordinates.
///
/// The list is capped to what fits on the screen: a Mac with forty apps in the dock would
/// otherwise produce a panel taller than the display, and this menu has no scrolling. Whatever is
/// cut off is reachable through the last row.
private func makeProgramsFlyout(items: [StartMenuPanel.MenuItem],
                                style: SubmenuContentView.Style,
                                bottomLeft: NSPoint,
                                in view: NSView,
                                onDismiss: (() -> Void)?) -> StartMenuPanel? {
    guard !items.isEmpty, let window = view.window else { return nil }
    let itemHeight: CGFloat = 24
    let iconSize: CGFloat = 16
    let font = NSFont(name: "Tahoma", size: 12) ?? NSFont.systemFont(ofSize: 12)

    let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    var shown = items
    let maxRows = max(6, Int((visible.height - 60) / itemHeight) - 1)
    if shown.count > maxRows {
        shown = Array(shown.prefix(maxRows - 1))
        shown.append(StartMenuPanel.MenuItem(title: "More Programs…", action: {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        }))
    }

    var contentW: CGFloat = 0
    for it in shown where !it.isSeparator {
        let tw = (it.title as NSString).size(withAttributes: [.font: font]).width
        contentW = max(contentW, 6 + iconSize + 8 + tw + 16)
    }
    let width = min(360, max(170, ceil(contentW)))
    var height: CGFloat = 4
    for it in shown { height += it.isSeparator ? 9 : itemHeight }

    let content = SubmenuContentView(items: shown, itemHeight: itemHeight, menuWidth: width,
                                     bevelWidth: 1, iconSize: iconSize, style: style)
    content.onDismiss = onDismiss
    let size = NSSize(width: width, height: height)
    content.frame = NSRect(origin: .zero, size: size)
    let panel = StartMenuPanel()
    panel.contentView = content

    // The corner the caller nominated: over the menu, sitting on the All Programs row.
    let corner = window.convertPoint(toScreen: view.convert(bottomLeft, to: nil))
    var x = corner.x
    var y = corner.y
    // Only when it would run off the screen does it move; it never flips to the other side,
    // because on this menu the other side is the desktop.
    x = min(max(x, visible.minX), visible.maxX - size.width)
    y = min(max(y, visible.minY), visible.maxY - size.height)
    panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    panel.orderFrontRegardless()
    return panel
}

// MARK: - XP Luna Blue Start Menu

private final class XPStartMenuContentView: NSView, StartMenuPanel.SubmenuHost {
    private let data: StartMenuPanel.XPMenuData
    var onDismiss: (() -> Void)?

    // Layout constants
    private let menuWidth: CGFloat = 440
    private let headerHeight: CGFloat = 54
    private let footerHeight: CGFloat = 36
    private let leftColumnWidth: CGFloat = 212
    private let itemHeight: CGFloat = 34
    private let largeItemHeight: CGFloat = 40
    private let iconSizeLarge: CGFloat = 32
    private let iconSizeSmall: CGFloat = 24   // harmonized: all right-column icons same size
    private let borderWidth: CGFloat = 2
    private let separatorHeight: CGFloat = 8

    // Colors
    private let headerBlueTop = NSColor(red: 0.21, green: 0.46, blue: 0.86, alpha: 1.0)
    private let headerBlueBottom = NSColor(red: 0.05, green: 0.22, blue: 0.66, alpha: 1.0)
    private let leftPanelBg = NSColor.white
    private let rightPanelBg = NSColor(red: 0.82, green: 0.87, blue: 0.96, alpha: 1.0)
    private let footerGray = NSColor(red: 0.82, green: 0.87, blue: 0.96, alpha: 1.0)
    private let borderBlue = NSColor(red: 0.04, green: 0.16, blue: 0.57, alpha: 1.0)
    private let hoverBlue = NSColor(red: 0.24, green: 0.38, blue: 0.82, alpha: 1.0)
    private let orangeHighlight = NSColor(red: 0.17, green: 0.35, blue: 0.78, alpha: 0.15)
    private let footerBtnBg = NSColor(red: 0.22, green: 0.41, blue: 0.82, alpha: 1.0)

    private var hoveredSection: HoverSection? = nil
    private var trackingArea: NSTrackingArea?
    private(set) var submenuPanel: StartMenuPanel?

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
            // Don't dismiss: the flyout is part of this menu, not a way out of it.
            if let items = data.allProgramsItems, !items.isEmpty {
                toggleProgramsFlyout(items)
            } else {
                data.allProgramsAction?()
            }
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

    func dismissSubmenu() {
        submenuPanel?.dismiss()
        submenuPanel = nil
    }

    private func toggleProgramsFlyout(_ items: [StartMenuPanel.MenuItem]) {
        if submenuPanel != nil { dismissSubmenu(); return }
        // Third column: left edge where the left column ends, bottom on the All Programs row.
        let row = allProgramsRect()
        submenuPanel = makeProgramsFlyout(items: items, style: .xp,
                                          bottomLeft: NSPoint(x: row.maxX, y: row.minY),
                                          in: self, onDismiss: { [weak self] in self?.onDismiss?() })
    }

    /// The "All Programs" row, walked the same way `hitSection` walks it so the flyout is
    /// anchored to the row the user actually clicked.
    private func allProgramsRect() -> NSRect {
        var y = borderWidth + footerHeight + contentHeight
        for item in data.leftItems { y -= item.isSeparator ? separatorHeight : largeItemHeight }
        return NSRect(x: borderWidth, y: y - largeItemHeight,
                      width: leftColumnWidth, height: largeItemHeight)
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

        // Iconic XP amber separator bands: under the header and above the footer.
        let amberTop = NSColor(srgbRed: 0.97, green: 0.69, blue: 0.33, alpha: 1)
        let amberBot = NSColor(srgbRed: 0.85, green: 0.45, blue: 0.13, alpha: 1)
        func amberBand(_ y: CGFloat) {
            NSGradient(starting: amberBot, ending: amberTop)?
                .draw(in: NSRect(x: bw, y: y, width: innerRect.width, height: 2), angle: 90)
        }
        amberBand(contentTop - 2)
        amberBand(contentBottom)

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

// MARK: - Windows 7 Aero Start Menu

/// Authentic Win7 two-column Aero menu: white program list (left) + frosted-glass places
/// column (right) with the account picture, "All Programs", a search field, and a single
/// "Shut down" split-button. Reuses `XPMenuData` (leftItems = programs w/ icons, rightItems =
/// places, title only). Frosted glass comes from an NSVisualEffectView placed behind this view
/// by `StartMenuPanel.showWin7`; the right column is painted translucent so the blur shows.
private final class Win7StartMenuContentView: NSView, StartMenuPanel.SubmenuHost {
    private let data: StartMenuPanel.XPMenuData
    var onDismiss: (() -> Void)?

    private let menuWidth: CGFloat = 420
    private let leftColW: CGFloat = 244
    private let topPad: CGFloat = 12
    private let progH: CGFloat = 38
    private let placeH: CGFloat = 26
    private let avatarSize: CGFloat = 48
    private let nameH: CGFloat = 18
    private let searchH: CGFloat = 32
    private let allProgH: CGFloat = 30
    private let shutH: CGFloat = 30
    private var radius: CGFloat { Self.radiusConst }
    private var overhang: CGFloat { Self.overhangConst }   // account picture sticks out above the top edge
    private let frameGutter: CGFloat = 8                    // dark glass border around the inset white panel
    private var rightColW: CGFloat { menuWidth - leftColW }

    private enum Hover: Equatable { case left(Int), right(Int), allPrograms, search, shutDown }
    private var hovered: Hover?
    private var tracking: NSTrackingArea?

    init(data: StartMenuPanel.XPMenuData) { self.data = data; super.init(frame: .zero); wantsLayer = true }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Windows 7 has no All Programs flyout. Clicking the row swaps the left pane for the
    /// program list in place and turns the row into "Back" — the pane navigates, it does not
    /// spawn a second menu. (Windows XP was the one with the cascading third column.)
    private var showingAllPrograms = false

    private var programs: [StartMenuPanel.MenuItem] {
        let source = showingAllPrograms ? (data.allProgramsItems ?? []) : data.leftItems
        let list = source.filter { !$0.isSeparator }
        // The real pane scrolls; this one cannot, so it shows what fits and offers the rest
        // through the last row rather than drawing past its own edge.
        guard showingAllPrograms, list.count > maxProgramRows else { return list }
        var capped = Array(list.prefix(maxProgramRows - 1))
        capped.append(StartMenuPanel.MenuItem(title: "More Programs…", action: {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        }))
        return capped
    }

    /// How many rows the left pane holds without growing: the pane keeps the height it was
    /// opened with, exactly like the real one.
    private var maxProgramRows: Int {
        max(4, data.leftItems.filter { !$0.isSeparator }.count)
    }

    private var places: [StartMenuPanel.MenuItem] { data.rightItems.filter { !$0.isSeparator } }

    private var bodyHeight: CGFloat {
        let left = topPad + CGFloat(programs.count) * progH + 8 + 1 + allProgH + 8 + searchH + 10
        let right = topPad + avatarSize * 0.55 + 6 + nameH + 10 + CGFloat(places.count) * placeH + 12 + shutH + 10
        return ceil(max(left, right))
    }
    // Total view = the menu body + the top overhang strip the avatar sticks out into.
    override var fittingSize: NSSize { NSSize(width: menuWidth, height: bodyHeight + overhang) }

    static let overhangConst: CGFloat = 20
    static let radiusConst: CGFloat = 8
    /// Blur mask covering only the rounded menu body — the top `overhang` strip (where the account
    /// picture sticks out over the desktop) stays clear.
    static func bodyMask(size: NSSize) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size.width, height: size.height - overhangConst),
                     xRadius: radiusConst, yRadius: radiusConst).fill()
        img.unlockFocus()
        return img
    }

    private struct Layout {
        var body = NSRect.zero, white = NSRect.zero
        var programs: [NSRect] = []
        var places: [NSRect] = []
        var avatar = NSRect.zero, name = NSRect.zero
        var allPrograms = NSRect.zero, search = NSRect.zero, shutDown = NSRect.zero
    }
    private func computeRects() -> Layout {
        var L = Layout()
        // The menu body sits below the transparent overhang strip; the avatar straddles its top edge.
        let body = NSRect(x: bounds.minX, y: bounds.minY, width: menuWidth, height: bounds.height - overhang)
        L.body = body
        // White program panel, inset by the glass gutter (right edge meets the column divider).
        let white = NSRect(x: body.minX + frameGutter, y: body.minY + frameGutter,
                           width: leftColW - frameGutter, height: body.height - frameGutter * 2)
        L.white = white
        var y = white.maxY - 6
        for _ in programs { L.programs.append(NSRect(x: white.minX, y: y - progH, width: white.width, height: progH)); y -= progH }
        L.search = NSRect(x: white.minX + 8, y: white.minY + 8, width: white.width - 16, height: searchH)
        L.allPrograms = NSRect(x: white.minX, y: L.search.maxY + 8, width: white.width, height: allProgH)
        // Avatar centered over the right (dark) column, centered on the body's top edge (~40% above).
        let avX = body.minX + leftColW + (rightColW - avatarSize) / 2
        let avY = body.maxY - avatarSize * 0.6
        L.avatar = NSRect(x: avX, y: avY, width: avatarSize, height: avatarSize)
        L.name = NSRect(x: body.minX + leftColW, y: avY - nameH - 2, width: rightColW, height: nameH)
        var ry = L.name.minY - 10
        for _ in places { L.places.append(NSRect(x: body.minX + leftColW, y: ry - placeH, width: rightColW, height: placeH)); ry -= placeH }
        L.shutDown = NSRect(x: body.minX + leftColW + 12, y: body.minY + 8, width: rightColW - 24, height: shutH)
        return L
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(t); tracking = t
    }
    override func mouseMoved(with event: NSEvent) {
        let h = sectionAt(convert(event.locationInWindow, from: nil))
        if h != hovered { hovered = h; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }

    private func sectionAt(_ p: NSPoint) -> Hover? {
        let L = computeRects()
        for (i, r) in L.programs.enumerated() where r.contains(p) { return .left(i) }
        for (i, r) in L.places.enumerated() where r.contains(p) { return .right(i) }
        if L.allPrograms.contains(p) { return .allPrograms }
        if L.search.contains(p) { return .search }
        if L.shutDown.contains(p) { return .shutDown }
        return nil
    }
    override func mouseDown(with event: NSEvent) {
        guard let h = sectionAt(convert(event.locationInWindow, from: nil)) else { return }
        switch h {
        case .left(let i): programs[i].action?(); onDismiss?()
        case .right(let i): places[i].action?(); onDismiss?()
        case .allPrograms:
            // Navigate in place; never dismiss — Back has to stay reachable.
            if let items = data.allProgramsItems, !items.isEmpty {
                showingAllPrograms.toggle()
                hovered = nil
                needsDisplay = true
            } else {
                data.allProgramsAction?()
            }
        case .search:
            if let f = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") { NSWorkspace.shared.open(f) }
            onDismiss?()
        case .shutDown: data.shutDownAction?(); onDismiss?()
        }
    }
    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard case let .left(i)? = sectionAt(p), let bid = programs[i].bundleID else { return }
        CustomIconPicker.present(for: bid, in: self, at: p) { [weak self] in self?.onDismiss?() }
    }

    private(set) var submenuPanel: StartMenuPanel?
    func dismissSubmenu() {
        submenuPanel?.dismiss()
        submenuPanel = nil
    }

    private func font(_ sz: CGFloat, _ bold: Bool) -> NSFont {
        NSFont(name: bold ? "Segoe UI Bold" : "Segoe UI", size: sz)
            ?? NSFont(name: bold ? "Tahoma Bold" : "Tahoma", size: sz)
            ?? NSFont.systemFont(ofSize: sz, weight: bold ? .semibold : .regular)
    }
    private func text(_ s: String, _ p: NSPoint, _ f: NSFont, _ c: NSColor) {
        (s as NSString).draw(at: p, withAttributes: [.font: f, .foregroundColor: c])
    }

    override func draw(_ dirtyRect: NSRect) {
        let L = computeRects()
        let body = L.body, white = L.white
        func rr(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad) }
        let darkText = NSColor(white: 0.1, alpha: 1)

        // Outer glow, then clip to the menu body (the top overhang strip stays clear for the avatar).
        NSColor(white: 1, alpha: 0.35).setStroke()
        let glow = rr(body.insetBy(dx: -1, dy: -1), radius + 1); glow.lineWidth = 1.5; glow.stroke()
        NSGraphicsContext.current?.saveGraphicsState()
        rr(body, radius).addClip()

        // Dark translucent glass = the whole body (frosted by the blur behind); this is the frame.
        NSColor(srgbRed: 0.14, green: 0.17, blue: 0.22, alpha: 0.80).setFill(); body.fill()
        NSColor(white: 1, alpha: 0.12).setFill(); NSRect(x: body.minX, y: body.maxY - 1.5, width: body.width, height: 1.5).fill()
        // Inset white program panel (glass gutter shows around its left/top/bottom).
        NSColor.white.setFill(); rr(white, 3).fill()

        // Left: programs
        for (i, r) in L.programs.enumerated() {
            if hovered == .left(i) {
                NSColor(srgbRed: 0.82, green: 0.90, blue: 0.99, alpha: 1).setFill(); rr(r.insetBy(dx: 2, dy: 1), 3).fill()
                NSColor(srgbRed: 0.55, green: 0.75, blue: 0.95, alpha: 1).setStroke(); let hp = rr(r.insetBy(dx: 2, dy: 1), 3); hp.lineWidth = 1; hp.stroke()
            }
            let it = programs[i]
            if let icon = it.icon { icon.draw(in: NSRect(x: r.minX + 8, y: r.midY - 13, width: 26, height: 26)) }
            text(it.title, NSPoint(x: r.minX + 42, y: r.midY - 7), font(12, it.isBold), darkText)
        }
        // All Programs + separator
        NSColor(white: 0.82, alpha: 1).setFill(); NSRect(x: white.minX + 6, y: L.allPrograms.maxY, width: white.width - 12, height: 1).fill()
        if hovered == .allPrograms { NSColor(srgbRed: 0.82, green: 0.90, blue: 0.99, alpha: 1).setFill(); rr(L.allPrograms.insetBy(dx: 2, dy: 1), 3).fill() }
        // The triangle points into the list on the way in and back out on the way home, and the
        // label changes with it: in Windows 7 this row IS the navigation.
        let ar = NSBezierPath()
        if showingAllPrograms {
            ar.move(to: NSPoint(x: white.minX + 16, y: L.allPrograms.midY - 5))
            ar.line(to: NSPoint(x: white.minX + 8, y: L.allPrograms.midY))
            ar.line(to: NSPoint(x: white.minX + 16, y: L.allPrograms.midY + 5))
        } else {
            ar.move(to: NSPoint(x: white.minX + 8, y: L.allPrograms.midY - 5))
            ar.line(to: NSPoint(x: white.minX + 16, y: L.allPrograms.midY))
            ar.line(to: NSPoint(x: white.minX + 8, y: L.allPrograms.midY + 5))
        }
        ar.close()
        NSColor(srgbRed: 0.30, green: 0.60, blue: 0.20, alpha: 1).setFill(); ar.fill()
        text(showingAllPrograms ? "Back" : "All Programs",
             NSPoint(x: white.minX + 24, y: L.allPrograms.midY - 8), font(12, true), darkText)

        // Search field
        let sp = rr(L.search, 3)
        NSColor.white.setFill(); sp.fill()
        NSColor(white: 0.55, alpha: 1).setStroke(); sp.lineWidth = 1; sp.stroke()
        text("Search programs and files", NSPoint(x: L.search.minX + 8, y: L.search.midY - 7), font(11, false), NSColor(white: 0.5, alpha: 1))
        NSColor(srgbRed: 0.20, green: 0.45, blue: 0.75, alpha: 1).setStroke()
        let mp = NSBezierPath(ovalIn: NSRect(x: L.search.maxX - 19, y: L.search.midY - 5, width: 9, height: 9)); mp.lineWidth = 1.5; mp.stroke()

        // Right: user name + places (text only, white; hover = translucent white pill)
        let nm = data.userName
        let nmW = (nm as NSString).size(withAttributes: [.font: font(13, false)]).width
        text(nm, NSPoint(x: body.minX + leftColW + (rightColW - nmW) / 2, y: L.name.minY), font(13, false), .white)
        for (i, r) in L.places.enumerated() {
            if hovered == .right(i) {
                NSColor(white: 1, alpha: 0.16).setFill(); rr(r.insetBy(dx: 6, dy: 1), 3).fill()
                NSColor(white: 1, alpha: 0.30).setStroke(); let hp = rr(r.insetBy(dx: 6, dy: 1), 3); hp.lineWidth = 1; hp.stroke()
            }
            text(places[i].title, NSPoint(x: r.minX + 16, y: r.midY - 8), font(12, places[i].isBold), .white)
            if i < places.count - 1 { NSColor(white: 1, alpha: 0.08).setFill(); NSRect(x: r.minX + 12, y: r.minY, width: rightColW - 24, height: 1).fill() }
        }

        // Shut down split-button
        let sd = L.shutDown
        NSGradient(colors: [NSColor(white: hovered == .shutDown ? 0.82 : 0.74, alpha: 1), NSColor(white: 0.54, alpha: 1)])!.draw(in: rr(sd, 3), angle: 90)
        NSColor(white: 0.32, alpha: 1).setStroke(); let sdp = rr(sd, 3); sdp.lineWidth = 1; sdp.stroke()
        text("Shut down", NSPoint(x: sd.minX + 10, y: sd.midY - 8), font(12, false), darkText)
        NSColor(white: 0.35, alpha: 1).setFill(); NSRect(x: sd.maxX - 20, y: sd.minY + 3, width: 1, height: sd.height - 6).fill()
        let sar = NSBezierPath()
        sar.move(to: NSPoint(x: sd.maxX - 14, y: sd.midY - 3))
        sar.line(to: NSPoint(x: sd.maxX - 9, y: sd.midY))
        sar.line(to: NSPoint(x: sd.maxX - 14, y: sd.midY + 3)); sar.close()
        NSColor(white: 0.2, alpha: 1).setFill(); sar.fill()

        NSGraphicsContext.current?.restoreGraphicsState()

        // Avatar LAST, outside the body clip so it straddles (sticks out above) the top edge.
        let av = L.avatar
        NSColor(white: 0.85, alpha: 0.95).setFill(); rr(av.insetBy(dx: -3, dy: -3), 6).fill()   // glossy light frame
        let avPath = rr(av, 4)
        NSGraphicsContext.current?.saveGraphicsState(); avPath.addClip()
        if let pic = StartMenuPanel.macUserPicture() {
            pic.draw(in: av, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            NSColor(srgbRed: 0.95, green: 0.6, blue: 0.2, alpha: 1).setFill(); av.fill()
            if let sym = NSImage(systemSymbolName: "person.fill", accessibilityDescription: nil) {
                sym.draw(in: av.insetBy(dx: 10, dy: 10), from: .zero, operation: .sourceOver, fraction: 0.9)
            }
        }
        NSGraphicsContext.current?.restoreGraphicsState()
        NSColor.white.setStroke(); avPath.lineWidth = 1.5; avPath.stroke()
    }
}

// MARK: - Classic Win98-Style Content View

private final class ClassicStartMenuContentView: NSView, StartMenuPanel.SubmenuHost {
    private let items: [StartMenuPanel.MenuItem]
    private let bannerText: String
    private let bannerWidth: CGFloat = 24
    private let itemHeight: CGFloat = 34         // taller top-level rows for the large (32px) icons
    private let iconSize: CGFloat = 32           // Win95: first-level icons are large; submenus use 16
    private let separatorHeight: CGFloat = 9
    private let bevelWidth: CGFloat = 2
    /// Space between a first-level item's icon and its label. Measured off the original, where
    /// the gap is about a third of the icon's width rather than the quarter this used to leave.
    /// Submenus keep their own tighter spacing: their icons are half the size.
    private let iconTextGap: CGFloat = 12
    /// First-level menu width. Snug against its (short) titles, then widened to the proportions
    /// of the real Me menu, which carries noticeably more empty space right of its labels.
    private var menuWidth: CGFloat {
        let font = NSFont(name: "Tahoma", size: 12) ?? NSFont.systemFont(ofSize: 12)
        var w: CGFloat = 0
        for item in items where !item.isSeparator {
            let tw = (item.title as NSString).size(withAttributes: [.font: font]).width
            let arrow: CGFloat = (item.submenuItems?.isEmpty == false) ? 24 : 12
            w = max(w, 6 + iconSize + iconTextGap + tw + arrow + 8)
        }
        return max(150, ceil(w * 1.15))
    }
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
        // Submenus use small (taskbar-size) icons and shorter rows, with a width that fits their
        // (longer) titles — so a submenu ends up WIDER than the narrow first-level menu.
        let subItemHeight: CGFloat = 22
        let subIconSize: CGFloat = 16
        let font = NSFont(name: "Tahoma", size: 12) ?? NSFont.systemFont(ofSize: 12)
        var contentW: CGFloat = 0
        for it in subItems where !it.isSeparator {
            let tw = (it.title as NSString).size(withAttributes: [.font: font]).width
            let arrow: CGFloat = (it.submenuItems?.isEmpty == false) ? 24 : 12
            contentW = max(contentW, 6 + subIconSize + 8 + tw + arrow + 8)
        }
        let subMenuWidth = max(150, ceil(contentW))
        var height: CGFloat = bevelWidth * 2 + 2
        for it in subItems { height += it.isSeparator ? separatorHeight : subItemHeight }
        let size = NSSize(width: subMenuWidth + bevelWidth * 2, height: height)

        let subContent = SubmenuContentView(items: subItems, itemHeight: subItemHeight,
                                            menuWidth: subMenuWidth, bevelWidth: bevelWidth, iconSize: subIconSize)
        subContent.onDismiss = { [weak self] in self?.onDismiss?() }
        subContent.frame = NSRect(origin: .zero, size: size)
        let panel = StartMenuPanel()
        panel.contentView = subContent

        guard let window = self.window else { return }
        let itemRect = rectForItem(at: index)
        // Align the submenu's top with the parent item's top, opening to the right.
        let itemTopRight = window.convertPoint(toScreen: convert(NSPoint(x: bounds.maxX, y: itemRect.maxY), to: nil))
        var originX = itemTopRight.x - 2
        var originY = itemTopRight.y - size.height
        if let vf = (window.screen ?? NSScreen.main)?.visibleFrame {
            // Flip to the LEFT of the parent menu if opening right would overflow the screen edge.
            if originX + size.width > vf.maxX {
                let leftEdge = window.convertPoint(toScreen: convert(NSPoint(x: bounds.minX + bevelWidth, y: 0), to: nil))
                originX = leftEdge.x - size.width + 2
            }
            originX = min(max(originX, vf.minX), vf.maxX - size.width)
            originY = min(max(originY, vf.minY), vf.maxY - size.height)   // keep fully on screen
        }
        panel.setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: size), display: true)
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
        let gray = Win98Scheme.activeFaceColor() ?? NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1)

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
        let isMe = bannerText.lowercased().contains("windows me")
        let isWin95 = bannerText.lowercased().contains("windows 95")
        if isWin95 {
            // Windows 95 side banner: a grey gradient (darker grey at the bottom → lighter up), NOT
            // the Win98 blue. "Windows 95" is drawn white over it (via the shared text path below).
            NSGradient(starting: NSColor(white: 0.40, alpha: 1), ending: NSColor(white: 0.62, alpha: 1))?
                .draw(in: bannerRect, angle: 90)
        } else if isMe {
            // Windows Me banner: a vivid royal-blue → navy → black gradient running UP the strip, with
            // a big white "Windows" + italic "Me" over the blue at the bottom and a small "Millennium
            // Edition" fading into the black above. Colour stops sampled from the original screenshot
            // (bottom → top): #2410CE → #1B0E9C → #110667 → #0C0833 → black, black holding the top ~30%.
            let grad = NSGradient(colorsAndLocations:
                (NSColor(srgbRed: 0.141, green: 0.063, blue: 0.808, alpha: 1), 0.0),
                (NSColor(srgbRed: 0.106, green: 0.055, blue: 0.612, alpha: 1), 0.25),
                (NSColor(srgbRed: 0.067, green: 0.024, blue: 0.404, alpha: 1), 0.42),
                (NSColor(srgbRed: 0.047, green: 0.031, blue: 0.200, alpha: 1), 0.56),
                (NSColor.black, 0.72),
                (NSColor.black, 1.0))
            grad?.draw(in: bannerRect, angle: 90)   // first colour at the bottom
        } else {
            // Win98: default #00007B (bottom) → #1085D2 (top), or the active Plus! scheme's colours.
            let (bannerBottom, bannerTop) = Win98Scheme.activeTitleColors()
                ?? (NSColor(red: 0.0, green: 0.0, blue: 0.482, alpha: 1.0),
                    NSColor(red: 0.063, green: 0.522, blue: 0.824, alpha: 1.0))
            NSGradient(starting: bannerBottom, ending: bannerTop)?.draw(in: bannerRect, angle: 90)
        }

        if !bannerText.isEmpty {
            let ctx = NSGraphicsContext.current!.cgContext
            if isMe {
                // "Windows" (bold sans) + "Me" (connected brush script, as in the original logotype),
                // then "Millennium Edition" (small sans) further up. The Me logo "Me" is a brush script:
                // prefer Brush Script MT, fall back to the always-present Snell Roundhand (never plain
                // bold) so it stays a script on Macs without Office.
                let big: CGFloat = 17
                let bold = NSFont(name: "Tahoma-Bold", size: big) ?? NSFont.boldSystemFont(ofSize: big)
                // Not bold: the logotype's "Me" is a light brush script, and the Snell fallback
                // was reaching for its Bold cut, which read as a heavy slab beside "Windows".
                let script = NSFont(name: "BrushScriptMT", size: big + 6)
                    ?? NSFont(name: "SnellRoundhand", size: big + 5)
                    ?? NSFontManager.shared.convert(NSFont(name: "Tahoma", size: big)
                        ?? NSFont.systemFont(ofSize: big), toHaveTrait: .italicFontMask)
                let main = NSMutableAttributedString()
                main.append(NSAttributedString(string: "Windows ", attributes: [.font: bold, .foregroundColor: NSColor.white]))
                main.append(NSAttributedString(string: "Me", attributes: [.font: script, .foregroundColor: NSColor.white, .baselineOffset: -3]))
                // Same size as "Windows": in the original the two read as one lockup, not a
                // heading with a caption under it.
                let sub = NSAttributedString(string: "Millennium Edition",
                    attributes: [.font: NSFont(name: "Tahoma", size: big) ?? NSFont.systemFont(ofSize: big),
                                 .foregroundColor: NSColor.white])
                func drawRot(_ s: NSAttributedString, up: CGFloat) {
                    ctx.saveGState()
                    let h = s.size().height
                    ctx.translateBy(x: bannerRect.minX + (bannerRect.width + h) / 2, y: bannerRect.minY + 5 + up)
                    ctx.rotate(by: CGFloat.pi / 2)
                    s.draw(at: .zero)
                    ctx.restoreGState()
                }
                drawRot(main, up: 0)
                drawRot(sub, up: main.size().width + 12)
            } else {
                ctx.saveGState()
                // Original banner reads "Windows" (bold) + "98" (regular) with NO space.
                let size: CGFloat = 16
                let boldFont = NSFont(name: "Tahoma-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size)
                let regFont  = NSFont(name: "Tahoma", size: size) ?? NSFont.systemFont(ofSize: size)
                let bannerTextColor = Win98Scheme.activeTitleTextColor() ?? NSColor.white
                let parts = bannerText.split(separator: " ", maxSplits: 1).map(String.init)
                let text = NSMutableAttributedString()
                text.append(NSAttributedString(string: parts.first ?? bannerText,
                                               attributes: [.font: boldFont, .foregroundColor: bannerTextColor]))
                if parts.count > 1 {
                    text.append(NSAttributedString(string: parts[1],
                                                   attributes: [.font: regFont, .foregroundColor: bannerTextColor]))
                }
                let textSize = text.size()
                ctx.translateBy(x: bannerRect.minX + (bannerRect.width + textSize.height) / 2, y: bannerRect.minY + 6)
                ctx.rotate(by: CGFloat.pi / 2)
                text.draw(at: .zero)
                ctx.restoreGState()
            }
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
            let iconY = itemRect.midY - iconSize / 2

            if let icon = item.icon {
                icon.draw(in: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
            }

            let textX = iconX + iconSize + iconTextGap
            let font = NSFont(name: "Tahoma", size: 12) ?? NSFont.systemFont(ofSize: 12)
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
    /// Which era's flyout to draw. The Win9x bevel would look like a visitor from another
    /// operating system hanging off an XP Luna menu. (Windows 7 needs no case here: its
    /// All Programs list replaces the left pane instead of opening a flyout.)
    enum Style { case classic, xp }

    private let items: [StartMenuPanel.MenuItem]
    private let itemHeight: CGFloat
    private let menuWidth: CGFloat
    private let bevelWidth: CGFloat
    private let iconSize: CGFloat
    private let style: Style
    private var hoveredIndex: Int? = nil
    private var trackingArea: NSTrackingArea?

    var onDismiss: (() -> Void)?

    init(items: [StartMenuPanel.MenuItem], itemHeight: CGFloat, menuWidth: CGFloat,
         bevelWidth: CGFloat, iconSize: CGFloat, style: Style = .classic) {
        self.items = items
        self.itemHeight = itemHeight
        self.menuWidth = menuWidth
        self.bevelWidth = bevelWidth
        self.iconSize = iconSize
        self.style = style
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

    /// XP and Windows 7 flyouts: a plain white list with a thin border and a coloured
    /// selection bar, in each era's own blue.
    private func drawModern() {
        let border = NSColor(red: 0.51, green: 0.58, blue: 0.71, alpha: 1)
        let selection = NSColor(red: 0.19, green: 0.42, blue: 0.77, alpha: 1)
        let selectedText = NSColor.white
        let textFont = NSFont(name: "Tahoma", size: 12) ?? NSFont.systemFont(ofSize: 12)

        let body = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(rect: body)
        NSColor.white.setFill(); path.fill()
        border.setStroke(); path.lineWidth = 1; path.stroke()

        var y = bounds.height - bevelWidth - 1
        for (i, item) in items.enumerated() {
            if item.isSeparator {
                y -= 9
                NSColor(white: 0.85, alpha: 1).setStroke()
                let line = NSBezierPath()
                line.move(to: NSPoint(x: 8, y: y + 4.5))
                line.line(to: NSPoint(x: bounds.width - 8, y: y + 4.5))
                line.lineWidth = 1; line.stroke()
                continue
            }
            let r = NSRect(x: 2, y: y - itemHeight, width: bounds.width - 4, height: itemHeight)
            y -= itemHeight
            if hoveredIndex == i {
                selection.setFill()
                NSBezierPath(rect: r).fill()
            }
            if let icon = item.icon {
                icon.draw(in: NSRect(x: r.minX + 6, y: r.midY - iconSize / 2,
                                     width: iconSize, height: iconSize))
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: textFont,
                .foregroundColor: hoveredIndex == i ? selectedText : NSColor.black]
            let size = (item.title as NSString).size(withAttributes: attrs)
            (item.title as NSString).draw(at: NSPoint(x: r.minX + 6 + iconSize + 8,
                                                     y: r.midY - size.height / 2),
                                          withAttributes: attrs)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if style != .classic { drawModern(); return }
        let gray = Win98Scheme.activeFaceColor() ?? NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1)
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
            let iconY = itemRect.midY - iconSize / 2

            if let icon = item.icon {
                icon.draw(in: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
            }

            let textX = iconX + iconSize + 8
            let font = NSFont(name: "Tahoma", size: 12) ?? NSFont.systemFont(ofSize: 12)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let textSize = (item.title as NSString).size(withAttributes: attrs)
            let textY = itemRect.midY - textSize.height / 2
            (item.title as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)

            if item.submenuItems?.isEmpty == false {
                let arrowAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: textColor]
                let arrow = "▸" as NSString
                let asz = arrow.size(withAttributes: arrowAttrs)
                arrow.draw(at: NSPoint(x: itemRect.maxX - asz.width - 8, y: itemRect.midY - asz.height / 2), withAttributes: arrowAttrs)
            }
        }
    }
}
