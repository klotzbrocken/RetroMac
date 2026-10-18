import AppKit
import ApplicationServices

/// The unread counts and other numbers apps put on their Dock icons, shown on the retro dock —
/// but only in the themes whose system had them, and the way that system drew them:
///
/// - **Mac OS X 10.0 Cheetah:** only Mail. It painted a red circle with the number into the top
///   right of its own icon; there was no way yet for other apps to do it (that came with
///   `NSDockTile` in 10.5).
/// - **Mac OS X 10.6, OS X 10.8:** every app, the glossy red pill of the 10.5 – 10.9 Dock.
/// - **Windows 7:** an overlay icon on the taskbar button's bottom right corner (the
///   `ITaskbarList3` overlay Windows 7 introduced), which mail and chat programs used for counts.
///
/// Every other theme shows none: Windows before 7, classic Mac OS, NeXTSTEP, BeOS and the Unix
/// desktops had no such thing on their docks and taskbars.
///
/// The numbers come from the Mac's own Dock, hidden under the theme but still running: its
/// accessibility tree carries each tile's badge as `AXStatusLabel`. That needs the Accessibility
/// permission RetroMac already asks for; without it nothing is shown.
final class DockBadges {
    static let shared = DockBadges()

    enum Style { case cheetah, leopard, win7 }

    /// Which badge a theme's system had. By theme id: an imported or user theme gets none.
    static func style(forThemeID id: String?) -> Style? {
        switch id {
        case "com.retromac.apple.aqua-cheetah": return .cheetah
        case "com.retromac.apple.snow-leopard", "com.retromac.apple.mountain-lion": return .leopard
        case "com.retromac.microsoft.windows7": return .win7
        default: return nil
        }
    }

    var style: Style? {
        AppSettings.shared.dockBadges ? Self.style(forThemeID: ThemeManager.shared.activeTheme?.config.id) : nil
    }

    /// The badge to draw on an app's icon in the current theme, or nil.
    func badge(for bundleID: String) -> String? {
        guard let s = style else { return nil }
        if s == .cheetah && bundleID != "com.apple.mail" { return nil }
        return counts[bundleID]
    }

    private(set) var counts: [String: String] = [:]
    /// The Dock forgets every badge when it restarts (a theme turning on restarts it), and most
    /// apps set theirs again only when the number changes. What was showing is carried over
    /// until the Dock reports that app again or the app quits; Mail's own count stands in for
    /// Mail's once the Dock has shown that Mail badges at all (the user may have turned them off).
    private var carried: [String: String] = [:]
    private var lastDockPID: pid_t?
    /// Kept across launches: RetroMac starting a theme restarts the Dock before it sees a badge.
    private var dockShowedMail: Bool {
        get { UserDefaults.standard.bool(forKey: "dockBadgesMailSeen") }
        set { if newValue != dockShowedMail { UserDefaults.standard.set(newValue, forKey: "dockBadgesMailSeen") } }
    }
    private var timer: Timer?
    private var urlToID: [URL: String] = [:]
    private let queue = DispatchQueue(label: "retromac.dockbadges", qos: .utility)

    /// Read the Dock every two seconds while a theme with badges is on. Idempotent.
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    func poll() {
        guard style != nil, AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            publish([:]); return
        }
        let pid = dock.processIdentifier
        if let last = lastDockPID, last != pid { carried.merge(counts) { new, _ in new } }
        lastDockPID = pid
        queue.async { [weak self] in
            guard let self else { return }
            var found: [String: String] = [:]
            self.walk(AXUIElementCreateApplication(pid), depth: 0, into: &found)
            DispatchQueue.main.async { self.publish(self.withCarried(found)) }
        }
    }

    private func withCarried(_ fromDock: [String: String]) -> [String: String] {
        var result = fromDock
        if fromDock["com.apple.mail"] != nil { dockShowedMail = true }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        carried = carried.filter { fromDock[$0.key] == nil && running.contains($0.key) }
        for (id, label) in carried { result[id] = label }
        if dockShowedMail, fromDock["com.apple.mail"] == nil, running.contains("com.apple.mail") {
            result["com.apple.mail"] = Self.mailOwnCount()
        }
        return result
    }

    /// The number Mail keeps for its Dock icon, nil at none.
    private static func mailOwnCount() -> String? {
        CFPreferencesAppSynchronize("com.apple.mail" as CFString)
        let v = CFPreferencesCopyAppValue("MailDockBadgeCurrentCount" as CFString, "com.apple.mail" as CFString) as? [String: Any]
        guard let n = (v?["count"] as? NSNumber)?.intValue, n > 0 else { return nil }
        return String(n)
    }

    private func publish(_ new: [String: String]) {
        guard new != counts else { return }
        counts = new
        NotificationCenter.default.post(name: .dockBadgesChanged, object: nil)
    }

    private func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }

    /// The Dock is shallow: application, list, tiles.
    private func walk(_ e: AXUIElement, depth: Int, into found: inout [String: String]) {
        if (attr(e, "AXSubrole") as? String) == "AXApplicationDockItem",
           let label = attr(e, "AXStatusLabel") as? String, !label.isEmpty,
           let url = attr(e, "AXURL") as? URL {
            let id = urlToID[url] ?? Bundle(url: url)?.bundleIdentifier
            if let id { urlToID[url] = id; found[id] = label }
        }
        guard depth < 3 else { return }
        for c in (attr(e, "AXChildren") as? [AXUIElement]) ?? [] { walk(c, depth: depth + 1, into: &found) }
    }
}

extension Notification.Name {
    static let dockBadgesChanged = Notification.Name("RetroMacDockBadgesChanged")
}

/// The badges themselves, drawn rather than shipped.
enum DockBadgeArt {

    /// The Mac OS X badge: red with a white rim, lit from above, a soft shadow below; round for
    /// one digit and a pill that grows with the text. 10.0's Mail painted its own a little
    /// brighter and more glassy, Aqua's look; 10.5 – 10.8's Dock drew the deeper red.
    static func macBadge(_ text: String, style: DockBadges.Style, height h: CGFloat) -> NSImage {
        let font = NSFont(name: "Helvetica-Bold", size: h * 0.58) ?? .boldSystemFont(ofSize: h * 0.58)
        let label = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        let w = max(h, label.size().width + h * 0.62)
        return NSImage(size: NSSize(width: w + 2, height: h + 3), flipped: false) { _ in
            let pill = NSRect(x: 1, y: 2.5, width: w, height: h)
            let rim = NSBezierPath(roundedRect: pill, xRadius: h / 2, yRadius: h / 2)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 1.5
            shadow.set()
            NSColor.white.setFill(); rim.fill()
            NSGraphicsContext.restoreGraphicsState()

            let border = max(1, h * 0.09)
            let body = pill.insetBy(dx: border, dy: border)
            let fill = NSBezierPath(roundedRect: body, xRadius: body.height / 2, yRadius: body.height / 2)
            let (top, bottom): (NSColor, NSColor) = style == .cheetah
                ? (NSColor(srgbRed: 1.00, green: 0.45, blue: 0.40, alpha: 1), NSColor(srgbRed: 0.86, green: 0.05, blue: 0.02, alpha: 1))
                : (NSColor(srgbRed: 0.98, green: 0.30, blue: 0.25, alpha: 1), NSColor(srgbRed: 0.76, green: 0.00, blue: 0.00, alpha: 1))
            NSGradient(starting: bottom, ending: top)?.draw(in: fill, angle: 90)
            // The shine on the upper half.
            let shine = NSRect(x: body.minX + body.height * 0.18, y: body.midY, width: body.width - body.height * 0.36, height: body.height * 0.46)
            NSColor.white.withAlphaComponent(style == .cheetah ? 0.45 : 0.28).setFill()
            NSBezierPath(roundedRect: shine, xRadius: shine.height / 2, yRadius: shine.height / 2).fill()

            let ts = label.size()
            label.draw(at: NSPoint(x: pill.midX - ts.width / 2, y: pill.midY - ts.height / 2))
            return true
        }
    }

    /// Windows 7's overlay: a small round red mark with the number, over the bottom right of the
    /// program's icon in its taskbar button. Windows drew it 16 × 16 over a 32-pixel icon.
    static func drawWin7Overlay(_ text: String, over icon: NSRect) {
        let d = max(10, icon.width * 0.6)
        let r = NSRect(x: icon.maxX - d * 0.75, y: icon.minY - d * 0.2, width: d, height: d)
        let path = NSBezierPath(ovalIn: r)
        NSGradient(starting: NSColor(srgbRed: 0.72, green: 0.03, blue: 0.03, alpha: 1),
                   ending: NSColor(srgbRed: 0.95, green: 0.25, blue: 0.20, alpha: 1))?.draw(in: path, angle: 90)
        NSColor.white.setStroke(); path.lineWidth = 1; path.stroke()
        let shown = text.count > 2 ? "99+" : text
        let font = NSFont.boldSystemFont(ofSize: d * (shown.count > 2 ? 0.38 : 0.55))
        let label = NSAttributedString(string: shown, attributes: [.font: font, .foregroundColor: NSColor.white])
        let ts = label.size()
        label.draw(at: NSPoint(x: r.midX - ts.width / 2, y: r.midY - ts.height / 2))
    }
}
