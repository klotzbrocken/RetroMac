import AppKit
import WebKit

/// The Dashboard layer: a dimmed sheet over the desktop holding free-floating widgets, the way
/// Mac OS X 10.4 to 10.9 did it. Dashboard itself was removed from macOS in Catalina, so this is
/// a rebuild rather than a hook into anything the system still provides.
///
/// It deliberately does NOT reuse the desktop widget controllers. Each of those owns its own
/// `NSPanel` with its own saved position, and an `NSPanel` cannot be re-parented into another
/// window. The layer loads the same HTML into its own web views instead, so the very same clock
/// can sit on the desktop and on the Dashboard at once with independent positions — which is
/// what the original did too.
final class DashboardController: NSObject, WKScriptMessageHandler {

    static let shared = DashboardController()

    /// One entry per widget the layer can host. `html` is relative to `Resources/Widgets`.
    struct Widget {
        let id: String
        let name: String
        let html: String
        let size: NSSize
        /// Widgets that draw their own window chrome for the desktop (Clock, Calculator) are
        /// told to drop it: Dashboard widgets are shapes on a sheet, not little windows.
        let stripChrome: Bool
    }

    static let catalogue: [Widget] = [
        Widget(id: "clock", name: "Clock", html: "Clock/Clock.html",
               size: NSSize(width: 200, height: 200), stripChrome: true),
        Widget(id: "calculator", name: "Calculator", html: "Calculator/Calculator.html",
               size: NSSize(width: 236, height: 220), stripChrome: true),
        Widget(id: "weather", name: "Weather", html: "Weather/Weather.html",
               size: NSSize(width: 236, height: 160), stripChrome: false),
        Widget(id: "calendar", name: "Calendar", html: "Calendar/Calendar.html",
               size: NSSize(width: 200, height: 250), stripChrome: false),
        Widget(id: "stickies", name: "Stickies", html: "Stickies/Stickies.html",
               size: NSSize(width: 220, height: 200), stripChrome: false),
        Widget(id: "search", name: "Search", html: "Search/Search.html",
               size: NSSize(width: 324, height: 40), stripChrome: false),
        // The CPU widget renders its content at SCALE 0.6, so its desktop panel is 560 wide for
        // what lands as roughly 336 points on screen. Sized to the drawn result, not the page.
        Widget(id: "cpu", name: "CPU", html: "CPUMonitor/CPUMonitor.html",
               size: NSSize(width: 560, height: 220), stripChrome: true),
    ]

    private var windows: [NSWindow] = []
    private var hosts: [String: DashboardWidgetView] = [:]
    private weak var root: DashboardBackdropView?
    private weak var bar: DashboardBarView?
    private weak var plus: DashboardPlusView?
    private var mainScreen: NSScreen?
    private var barOpen = false
    private(set) var isOpen = false

    private override init() { super.init() }

    // MARK: - Persisted state

    private let activeKey = "dashboardWidgets"
    private let prefsKey  = "dashboardPrefs"

    private var activeIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: activeKey) ?? ["clock", "weather", "calendar"] }
        set { UserDefaults.standard.set(newValue, forKey: activeKey) }
    }
    private func posKey(_ id: String) -> String { "dashboardPos.\(id)" }

    /// Widget preferences (the weather widget's city, for instance). Kept on this side because
    /// the layer's web views use a non-persistent data store, so `localStorage` would not
    /// survive a quit.
    private var prefs: [String: Any] {
        get { UserDefaults.standard.dictionary(forKey: prefsKey) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: prefsKey) }
    }

    // MARK: - Show / hide

    func toggle() { isOpen ? hide() : show() }

    func show() {
        guard !isOpen else { return }
        guard Bundle.main.resourceURL != nil else { NSSound.beep(); return }
        isOpen = true
        barOpen = false

        for screen in NSScreen.screens {
            // KeyableWindow, not NSWindow: a borderless window returns canBecomeKey = false, so
            // the web views could never receive a keystroke — the weather widget's city field was
            // impossible to type into.
            let win = KeyableWindow(contentRect: screen.frame, styleMask: [.borderless],
                                    backing: .buffered, defer: false)
            win.acceptsMouseMovedEvents = true
            // Below the retro dock (24) and the CRT overlay (25) on purpose: the Dock stayed
            // visible over Dashboard, and the shader should treat the layer like anything else.
            win.level = NSWindow.Level(rawValue: 23)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            win.hasShadow = false

            let root = DashboardBackdropView(frame: NSRect(origin: .zero, size: screen.frame.size))
            root.onBackgroundClick = { [weak self] in self?.hide() }
            root.onEscape = { [weak self] in self?.hide() }
            win.contentView = root
            win.alphaValue = 0
            win.orderFrontRegardless()
            windows.append(win)

            // Only the main screen carries the widgets; the others just dim, as they did.
            if screen == NSScreen.screens.first {
                self.root = root
                self.mainScreen = screen
                for id in activeIDs { addWidget(id, to: root, on: screen) }
                // The bar starts off-screen and slides up from the + in the corner, the way
                // Dashboard's widget bar did.
                // Clear the retro dock. It sits one level above this layer — deliberately, so it
                // stays visible as it did in Dashboard — which means the bar and the + have to be
                // lifted above it rather than sliding underneath.
                let inset = self.bottomInset(on: screen)
                let b = makeBar(width: screen.frame.width)
                b.bottomInset = inset
                b.frame.origin.y = -b.frame.height
                root.addSubview(b)
                self.bar = b
                let p = DashboardPlusView(frame: NSRect(x: 14, y: 14 + inset, width: 30, height: 30))
                p.onClick = { [weak self] in self?.setBarOpen(!(self?.barOpen ?? false)) }
                root.addSubview(p)
                self.plus = p
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                win.animator().alphaValue = 1
            }
            win.makeKey()
            win.makeFirstResponder(root)
        }
        // Without this the layer needs a click before it is interactive, which is why the info
        // button only appeared after clicking rather than on hover.
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        guard isOpen else { return }
        isOpen = false
        let closing = windows
        windows.removeAll()
        hosts.removeAll()
        root = nil; bar = nil; plus = nil; mainScreen = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            closing.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            closing.forEach { $0.orderOut(nil) }
        }
    }

    /// How much of the bottom of `screen` the retro dock occupies, so nothing is laid out under
    /// it. Zero when the dock is hidden or sits on another edge.
    private func bottomInset(on screen: NSScreen) -> CGFloat {
        guard let dock = DockController.shared.visibleDockFrame(on: screen) else { return 0 }
        guard dock.minY <= screen.frame.minY + 2 else { return 0 }   // only a dock along the bottom
        return dock.height
    }

    /// Slides the widget bar in or out. While it is open every widget wears its remove badge,
    /// which is exactly when Dashboard showed them — not on hover, which had the badge sitting
    /// in the corner of a widget you were only trying to use.
    private func setBarOpen(_ open: Bool) {
        guard let bar = bar, let plus = plus else { return }
        barOpen = open
        hosts.values.forEach { $0.showBadge = open }
        plus.isOpen = open
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            bar.animator().frame.origin.y = open ? bar.bottomInset : -bar.frame.height
        }
    }

    // MARK: - Widgets

    private func addWidget(_ id: String, to root: NSView, on screen: NSScreen) {
        guard let w = Self.catalogue.first(where: { $0.id == id }),
              let res = Bundle.main.resourceURL else { return }
        let url = res.appendingPathComponent("Widgets/\(w.html)")
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let origin = storedOrigin(for: w, on: screen)
        let host = DashboardWidgetView(frame: NSRect(origin: origin, size: w.size))
        host.widgetID = id
        host.onMove = { [weak self] delta in
            guard let self = self else { return }
            var f = host.frame
            f.origin.x += delta.x
            f.origin.y -= delta.y                  // web deltas grow downwards
            f.origin.x = min(max(f.origin.x, 0), root.bounds.width - f.width)
            f.origin.y = min(max(f.origin.y, 0), root.bounds.height - f.height)
            host.frame = f
            UserDefaults.standard.set(NSStringFromPoint(f.origin), forKey: self.posKey(id))
        }
        host.onRemove = { [weak self] in
            guard let self = self else { return }
            self.activeIDs = self.activeIDs.filter { $0 != id }
            self.hosts[id] = nil
            self.bar?.activeIDs = Set(self.activeIDs)
            // Suck it away rather than blink it out, the way Dashboard did.
            host.wantsLayer = true
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                host.animator().alphaValue = 0
                host.animator().frame = host.frame.insetBy(dx: host.frame.width * 0.35,
                                                           dy: host.frame.height * 0.35)
            }, completionHandler: { host.removeFromSuperview() })
        }

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.userContentController.add(self, name: "dashboard")
        cfg.userContentController.addUserScript(
            WKUserScript(source: bootstrap(for: w), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let wv = WKWebView(frame: NSRect(origin: .zero, size: w.size), configuration: cfg)
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")
        wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        host.webView = wv
        host.addSubview(wv)

        root.addSubview(host)
        hosts[id] = host
    }

    private func storedOrigin(for w: Widget, on screen: NSScreen) -> NSPoint {
        if let s = UserDefaults.standard.string(forKey: posKey(w.id)) {
            let p = NSPointFromString(s)
            if p != .zero { return p }
        }
        // First run: stack them down the left, the way a fresh Dashboard laid its defaults out.
        let index = Self.catalogue.firstIndex { $0.id == w.id } ?? 0
        return NSPoint(x: 90 + CGFloat(index % 2) * 300,
                       y: screen.frame.height - 160 - CGFloat(index) * 200)
    }

    /// Injected before the page runs: preferences, the setter, the chrome strip for widgets that
    /// draw a desktop window frame, and the drag reporter.
    private func bootstrap(for w: Widget) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: prefs))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        // Dragging is reported from the page rather than handled by a transparent view on top:
        // an overlay would swallow the calculator's keys. Nothing is preventDefault-ed, so a
        // click still reaches the widget; a drag simply also moves the host.
        let strip = w.stripChrome ? """
        document.addEventListener('DOMContentLoaded', function(){
          // These pages are desktop windows in every theme; on the Dashboard they are shapes on
          // a sheet, so the title bars, the frame and the body plate all go and only the content
          // is left floating.
          if (window.setTheme) window.setTheme('snowleopard');
          var s = document.createElement('style');
          s.textContent = '.tab,.m9-title,.m9-plaque,.xp-title,.mf-title,.mx-title,.w98-title,'
            + '.w98-menubar,.vsb,.hsb,.be-menubar,.be-status{display:none!important}'
            + 'html,body{background:transparent!important}'
            + '.be-win,#win,.window{border:none!important;box-shadow:none!important;'
            + 'background:transparent!important;overflow:visible!important}'
            + '.body,.be-mid,.be-content{background:transparent!important;border:none!important;'
            + 'box-shadow:none!important}';
          document.head.appendChild(s);
        });
        """ : ""
        return """
        (function(){
          window.dashPrefs = \(json);
          window.dashSetPref = function(k, v){
            try { window.webkit.messageHandlers.dashboard.postMessage({a:'pref', k:k, v:v}); } catch(e){}
          };
          \(strip)
          var on = false, sx = 0, sy = 0;
          document.addEventListener('mousedown', function(e){
            if (e.button !== 0) return;
            if (e.target.closest('input,button,a,select,textarea,[data-nodrag]')) return;
            on = true; sx = e.screenX; sy = e.screenY;
          }, true);
          window.addEventListener('mousemove', function(e){
            if (!on) return;
            var dx = e.screenX - sx, dy = e.screenY - sy;
            if (!dx && !dy) return;
            sx = e.screenX; sy = e.screenY;
            try { window.webkit.messageHandlers.dashboard.postMessage({a:'move', dx:dx, dy:dy}); } catch(err){}
          }, true);
          window.addEventListener('mouseup', function(){ on = false; }, true);
          window.addEventListener('blur', function(){ on = false; });
        })();
        """
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "dashboard", let d = message.body as? [String: Any],
              let a = d["a"] as? String else { return }
        // Which widget sent this: match the web view back to its host.
        let host = hosts.values.first { $0.webView === message.webView }
        switch a {
        case "move":
            guard let dx = (d["dx"] as? NSNumber)?.doubleValue,
                  let dy = (d["dy"] as? NSNumber)?.doubleValue else { return }
            host?.onMove?(CGPoint(x: dx, y: dy))
        case "pref":
            guard let k = d["k"] as? String, let v = d["v"] else { return }
            var p = prefs
            p[k] = v
            prefs = p
        case "open":
            // Only http(s), and only from our own bundled pages — a widget should not be able to
            // hand the system an arbitrary scheme to launch.
            guard let str = d["url"] as? String, let u = URL(string: str),
                  u.scheme == "https" || u.scheme == "http" else { return }
            hide()
            NSWorkspace.shared.open(u)
        default: break
        }
    }

    // MARK: - Widget bar

    private func makeBar(width: CGFloat) -> DashboardBarView {
        let bar = DashboardBarView(frame: NSRect(x: 0, y: 0, width: width, height: 92))
        bar.autoresizingMask = [.width]
        bar.items = Self.catalogue
        bar.activeIDs = Set(activeIDs)
        bar.onPick = { [weak self] id in
            guard let self = self, let root = self.root, let screen = self.mainScreen else { return }
            guard !self.activeIDs.contains(id) else { return }
            self.activeIDs = self.activeIDs + [id]
            self.addWidget(id, to: root, on: screen)
            self.hosts[id]?.showBadge = self.barOpen
            bar.activeIDs = Set(self.activeIDs)
            bar.needsDisplay = true
            if let host = self.hosts[id] {
                // Dashboard rippled the sheet where a widget landed. A single expanding ring is
                // the honest approximation — the original was a water distortion of the backdrop,
                // which needs a filter over live content rather than a drawn shape.
                root.ripple(at: NSPoint(x: host.frame.midX, y: host.frame.midY))
                host.wantsLayer = true
                host.alphaValue = 0
                let target = host.frame
                host.frame = target.insetBy(dx: target.width * 0.25, dy: target.height * 0.25)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.28
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    host.animator().alphaValue = 1
                    host.animator().frame = target
                }
            }
        }
        return bar
    }
}

// MARK: - Views

/// The dimmed sheet. Swallows clicks that land on the backdrop (closing the layer) but lets
/// widgets on top of it work normally.
final class DashboardBackdropView: NSView {
    var onBackgroundClick: (() -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.42).setFill()
        bounds.fill()
    }

    override func mouseDown(with event: NSEvent) {
        // Only a click on the sheet itself, not one that fell through from a widget.
        let p = convert(event.locationInWindow, from: nil)
        if let hit = hitTest(convert(p, to: superview)), hit !== self { return }
        onBackgroundClick?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }

    /// One expanding ring where a widget just landed.
    func ripple(at point: NSPoint) {
        wantsLayer = true
        guard let host = layer else { return }
        let ring = CAShapeLayer()
        let r: CGFloat = 26
        ring.path = CGPath(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2),
                           transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = NSColor(white: 1, alpha: 0.55).cgColor
        ring.lineWidth = 2
        host.addSublayer(ring)

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3
        grow.toValue = 4.5
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.55
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        // Scale about the ring's own centre rather than the layer origin.
        ring.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
        ring.position = point
        ring.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: r * 2, height: r * 2), transform: nil)
        ring.add(group, forKey: "ripple")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { ring.removeFromSuperlayer() }
    }
}

/// The + in the bottom-left corner that opens and closes the widget bar.
final class DashboardPlusView: NSView {
    var onClick: (() -> Void)?
    var isOpen = false { didSet { needsDisplay = true } }
    private var hot = false

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 2, dy: 2)
        NSColor(white: 0.1, alpha: hot ? 0.85 : 0.65).setFill()
        NSBezierPath(ovalIn: r).fill()
        NSColor(white: 1, alpha: 0.35).setStroke()
        let ring = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
        ring.lineWidth = 1
        ring.stroke()

        NSColor(white: 1, alpha: 0.95).setStroke()
        let p = NSBezierPath()
        p.lineWidth = 2.2
        p.lineCapStyle = .round
        let i = r.insetBy(dx: 8, dy: 8)
        if isOpen {                       // an × once the bar is up, so the same button closes it
            p.move(to: NSPoint(x: i.minX, y: i.minY)); p.line(to: NSPoint(x: i.maxX, y: i.maxY))
            p.move(to: NSPoint(x: i.maxX, y: i.minY)); p.line(to: NSPoint(x: i.minX, y: i.maxY))
        } else {
            p.move(to: NSPoint(x: i.minX, y: i.midY)); p.line(to: NSPoint(x: i.maxX, y: i.midY))
            p.move(to: NSPoint(x: i.midX, y: i.minY)); p.line(to: NSPoint(x: i.midX, y: i.maxY))
        }
        p.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hot = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hot = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// Holds one widget's web view plus its remove badge.
final class DashboardWidgetView: NSView {
    var widgetID = ""
    weak var webView: WKWebView?
    var onMove: ((CGPoint) -> Void)?
    var onRemove: (() -> Void)?

    private var badgeRect: NSRect { NSRect(x: -1, y: bounds.height - 17, width: 18, height: 18) }
    /// Shown only while the widget bar is open. On hover it sat as a black blob in the corner of
    /// a widget you were merely using — which is what it looked like, and not what Dashboard did.
    var showBadge = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard showBadge else { return }
        // The close badge Dashboard put on the widget's top-left corner.
        let r = badgeRect
        NSColor(white: 0.15, alpha: 0.92).setFill()
        NSBezierPath(ovalIn: r).fill()
        NSColor(white: 1, alpha: 0.9).setStroke()
        let x = NSBezierPath()
        x.lineWidth = 1.8
        x.lineCapStyle = .round
        let i = r.insetBy(dx: 5.5, dy: 5.5)
        x.move(to: NSPoint(x: i.minX, y: i.minY)); x.line(to: NSPoint(x: i.maxX, y: i.maxY))
        x.move(to: NSPoint(x: i.maxX, y: i.minY)); x.line(to: NSPoint(x: i.minX, y: i.maxY))
        x.stroke()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The badge sits above the web view, so claim its rect before the page sees the click.
        let p = convert(point, from: superview)
        if showBadge && badgeRect.contains(p) { return self }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if badgeRect.contains(p) { onRemove?() }
    }
}

/// The strip along the bottom that adds widgets, standing in for Dashboard's widget bar.
final class DashboardBarView: NSView {
    /// How far up from the bottom the bar rests, so it clears the retro dock.
    var bottomInset: CGFloat = 0
    var items: [DashboardController.Widget] = []
    var activeIDs: Set<String> = []
    var onPick: ((String) -> Void)?

    private let tileW: CGFloat = 96
    private var hovered = -1

    private func tileRect(_ i: Int) -> NSRect {
        let total = CGFloat(items.count) * tileW
        let x0 = (bounds.width - total) / 2
        return NSRect(x: x0 + CGFloat(i) * tileW, y: 10, width: tileW, height: 72)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.08, alpha: 0.72).setFill()
        bounds.fill()
        NSColor(white: 1, alpha: 0.16).setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

        for (i, w) in items.enumerated() {
            let r = tileRect(i)
            let on = activeIDs.contains(w.id)
            if i == hovered && !on {
                NSColor(white: 1, alpha: 0.12).setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 6, dy: 4), xRadius: 8, yRadius: 8).fill()
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "Lucida Grande", size: 11) ?? .systemFont(ofSize: 11),
                .foregroundColor: NSColor(white: 1, alpha: on ? 0.35 : 0.92)]
            let s = w.name.size(withAttributes: attrs)
            w.name.draw(at: NSPoint(x: r.midX - s.width / 2, y: r.minY + 8), withAttributes: attrs)
            // A plain plus for one that can still be added, a tick for one already on the sheet.
            let g = NSRect(x: r.midX - 13, y: r.minY + 28, width: 26, height: 26)
            NSColor(white: 1, alpha: on ? 0.22 : 0.85).setStroke()
            let p = NSBezierPath()
            p.lineWidth = 2
            p.lineCapStyle = .round
            if on {
                p.move(to: NSPoint(x: g.minX + 5, y: g.midY))
                p.line(to: NSPoint(x: g.midX - 2, y: g.minY + 6))
                p.line(to: NSPoint(x: g.maxX - 4, y: g.maxY - 6))
            } else {
                p.move(to: NSPoint(x: g.minX + 4, y: g.midY)); p.line(to: NSPoint(x: g.maxX - 4, y: g.midY))
                p.move(to: NSPoint(x: g.midX, y: g.minY + 4)); p.line(to: NSPoint(x: g.midX, y: g.maxY - 4))
            }
            p.stroke()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let old = hovered
        hovered = items.indices.first { tileRect($0).contains(p) } ?? -1
        if old != hovered { needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { if hovered != -1 { hovered = -1; needsDisplay = true } }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = items.indices.first(where: { tileRect($0).contains(p) }) { onPick?(items[i].id) }
    }
}
