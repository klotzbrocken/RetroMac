import AppKit

/// Visual style for a retro dropdown menu.
enum RetroMenuStyle {
    case win31   // white background, black 1px border, navy selection bar
    case sgi     // gray raised menu, italic font, per-item drawer icon, dark selection
}

/// A single entry in a retro dropdown menu.
/// Use "&" in the title to mark the underlined mnemonic (e.g. "Mi&nimize").
struct Win31MenuItem {
    var title: String
    var accelerator: String?
    var enabled: Bool
    var isSeparator: Bool
    var submenu: [Win31MenuItem]?
    var action: (() -> Void)?

    init(_ title: String, accelerator: String? = nil, enabled: Bool = true,
         submenu: [Win31MenuItem]? = nil, action: (() -> Void)? = nil) {
        self.title = title; self.accelerator = accelerator; self.enabled = enabled
        self.isSeparator = false; self.submenu = submenu; self.action = action
    }
    private init(sep: Bool) {
        self.title = ""; self.accelerator = nil; self.enabled = false
        self.isSeparator = true; self.submenu = nil; self.action = nil
    }
    static var separator: Win31MenuItem { Win31MenuItem(sep: true) }
}

/// Presents a pixel-accurate retro dropdown as a full-screen overlay inside the host panel.
enum Win31Menu {
    /// `topLeft` is the menu's top-left corner in `host` coordinates (non-flipped, y up).
    static func present(items: [Win31MenuItem], topLeft: NSPoint, in host: NSView,
                        style: RetroMenuStyle = .win31, header: String? = nil) {
        host.subviews.compactMap { $0 as? Win31MenuOverlay }.forEach { $0.dismiss() }
        let overlay = Win31MenuOverlay(items: items, topLeft: topLeft, hostBounds: host.bounds,
                                       style: style, header: header)
        overlay.autoresizingMask = [.width, .height]
        host.addSubview(overlay)
        overlay.window?.acceptsMouseMovedEvents = true
        overlay.activate()
    }
}

final class Win31MenuOverlay: NSView {
    private let items: [Win31MenuItem]
    private let style: RetroMenuStyle
    private let header: String?
    private let topLeft: NSPoint
    private var menuRect: NSRect = .zero
    private var hovered: Int? = nil

    private let itemH: CGFloat = 22
    private let sepH: CGFloat = 7
    private let headerH: CGFloat = 22
    private var padL: CGFloat { 24 }
    private var padR: CGFloat { style == .sgi ? 30 : 18 }
    private let accelGap: CGFloat = 28
    private let font: NSFont

    init(items: [Win31MenuItem], topLeft: NSPoint, hostBounds: NSRect,
         style: RetroMenuStyle, header: String?) {
        self.items = items; self.style = style; self.header = header; self.topLeft = topLeft
        if style == .sgi {
            self.font = NSFontManager.shared.convert(.systemFont(ofSize: 13, weight: .semibold),
                                                     toHaveTrait: .italicFontMask)
        } else {
            self.font = Win31Chrome.font(size: 13, bold: false)
        }
        super.init(frame: hostBounds)
        let size = measure()
        var origin = NSPoint(x: topLeft.x, y: topLeft.y - size.height)
        origin.x = max(2, min(origin.x, hostBounds.maxX - size.width - 2))
        origin.y = max(2, origin.y)
        menuRect = NSRect(origin: origin, size: size)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var trackingAreaRef: NSTrackingArea?
    func activate() {
        let ta = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(ta); trackingAreaRef = ta
    }
    func dismiss() { window?.acceptsMouseMovedEvents = false; removeFromSuperview() }

    // MARK: Layout

    private func measure() -> NSSize {
        var maxText: CGFloat = 0, maxAccel: CGFloat = 0
        var h: CGFloat = 4
        if header != nil { h += headerH }
        for it in items {
            if it.isSeparator { h += sepH; continue }
            h += itemH
            let tw = (displayTitle(it.title) as NSString).size(withAttributes: [.font: font]).width
            maxText = max(maxText, tw)
            if let a = it.accelerator { maxAccel = max(maxAccel, (a as NSString).size(withAttributes: [.font: font]).width) }
        }
        if let head = header { maxText = max(maxText, (head as NSString).size(withAttributes: [.font: font]).width) }
        let w = padL + maxText + (maxAccel > 0 ? accelGap + maxAccel : 0) + padR
        return NSSize(width: ceil(max(w, 130)), height: ceil(h))
    }

    /// Returns item row rects (index -1 = header).
    private func rows() -> [(rect: NSRect, index: Int)] {
        var result: [(NSRect, Int)] = []
        var y = menuRect.maxY - 2
        if header != nil {
            y -= headerH
            result.append((NSRect(x: menuRect.minX + 2, y: y, width: menuRect.width - 4, height: headerH), -1))
        }
        for (i, it) in items.enumerated() {
            let hgt = it.isSeparator ? sepH : itemH
            y -= hgt
            result.append((NSRect(x: menuRect.minX + 2, y: y, width: menuRect.width - 4, height: hgt), i))
        }
        return result
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        if style == .sgi {
            SGIChrome.face.setFill(); menuRect.fill()
            SGIChrome.drawRaised(menuRect, t: 2)
        } else {
            NSColor.white.setFill(); menuRect.fill()
            NSColor.black.setStroke()
            let b = NSBezierPath(rect: menuRect.insetBy(dx: 0.5, dy: 0.5)); b.lineWidth = 1; b.stroke()
        }

        for (rect, i) in rows() {
            if i == -1 {   // header
                SGIChrome.dark.setFill(); rect.fill()
                drawTitle(header ?? "", in: rect, color: .white, drawer: false)
                continue
            }
            let it = items[i]
            if it.isSeparator {
                let midY = rect.midY
                (style == .sgi ? SGIChrome.dark : Win31Chrome.darkGray).setFill()
                NSRect(x: rect.minX + 2, y: midY, width: rect.width - 4, height: 1).fill()
                (style == .sgi ? SGIChrome.light : Win31Chrome.white).setFill()
                NSRect(x: rect.minX + 2, y: midY - 1, width: rect.width - 4, height: 1).fill()
                continue
            }
            let isHi = (hovered == i) && it.enabled
            if isHi {
                (style == .sgi ? SGIChrome.activeTitle : Win31Chrome.activeTitle).setFill()
                rect.fill()
            }
            let color: NSColor = !it.enabled ? (style == .sgi ? SGIChrome.dark : Win31Chrome.darkGray)
                                             : (isHi ? .white : .black)
            let hasDrawer = (style == .sgi)
            drawTitle(it.title, in: rect, color: color, drawer: hasDrawer)
            if let a = it.accelerator {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let s = a as NSString; let sz = s.size(withAttributes: attrs)
                s.draw(at: NSPoint(x: rect.maxX - padR - sz.width + 6, y: rect.midY - sz.height / 2), withAttributes: attrs)
            }
            // SGI: thin etched line under each item
            if style == .sgi {
                SGIChrome.dark.withAlphaComponent(0.4).setFill()
                NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1).fill()
            }
        }
    }

    private func displayTitle(_ raw: String) -> String { raw.replacingOccurrences(of: "&", with: "") }

    private func drawTitle(_ raw: String, in rect: NSRect, color: NSColor, drawer: Bool) {
        let display = displayTitle(raw)
        let attr = NSMutableAttributedString(string: display, attributes: [.font: font, .foregroundColor: color])
        if let amp = raw.firstIndex(of: "&") {
            let off = raw.distance(from: raw.startIndex, to: amp)
            if off < display.count { attr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: off, length: 1)) }
        }
        let sz = attr.size()
        attr.draw(at: NSPoint(x: rect.minX + padL - 2, y: rect.midY - sz.height / 2))
        if drawer { drawDrawerIcon(at: NSRect(x: rect.maxX - 22, y: rect.midY - 7, width: 13, height: 14)) }
    }

    /// Small SGI "drawer" glyph (a 3D filing-drawer box).
    private func drawDrawerIcon(at r: NSRect) {
        NSColor.white.setFill(); r.fill()
        SGIChrome.dark.setStroke()
        let b = NSBezierPath(rect: r); b.lineWidth = 1; b.stroke()
        // drawer front line + handle
        SGIChrome.dark.setFill()
        NSRect(x: r.minX, y: r.minY + r.height * 0.35, width: r.width, height: 1).fill()
        NSRect(x: r.midX - 2, y: r.minY + r.height * 0.16, width: 4, height: 1).fill()
    }

    // MARK: Interaction

    private func indexAt(_ p: NSPoint) -> Int? {
        for (rect, i) in rows() where i >= 0 && rect.contains(p) { return items[i].isSeparator ? nil : i }
        return nil
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let idx = menuRect.contains(p) ? indexAt(p) : nil
        if idx != hovered { hovered = idx; needsDisplay = true }
    }
    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }

    private func choose(_ i: Int) {
        let it = items[i]
        guard it.enabled else { return }
        if let sub = it.submenu, !sub.isEmpty {
            // Open submenu to the right of this row
            let rowRect = rows().first(where: { $0.index == i })?.rect ?? menuRect
            let host = superview
            let tl = NSPoint(x: menuRect.maxX - 4, y: rowRect.maxY)
            dismiss()
            if let host = host { Win31Menu.present(items: sub, topLeft: tl, in: host, style: style) }
            return
        }
        let action = it.action
        dismiss()
        action?()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if !menuRect.contains(p) { dismiss(); return }
        if let i = indexAt(p) { choose(i) }
    }
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = indexAt(p), hovered == i { choose(i) }
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { dismiss() } }
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { self }
}
