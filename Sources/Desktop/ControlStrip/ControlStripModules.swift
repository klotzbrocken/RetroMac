import AppKit
import CoreGraphics
import IOKit.ps
import SystemConfiguration

/// One module of the Mac OS 9 Control Strip: a small picture with a state, and a menu that
/// pops up when it is clicked. The originals lived in "Control Strip Modules"; these are
/// RetroMac's own for the parts of the system macOS still has.
protocol ControlStripModule: AnyObject {
    var id: String { get }
    /// A module that has nothing to show hides (the battery on a desktop Mac, mirroring with
    /// one display) instead of drawing a dead picture.
    var isAvailable: Bool { get }
    /// Width of the cell in points; the picture is 16 pt, text modules are wider.
    var width: CGFloat { get }
    /// Draw into `rect` (16 pt tall content area, flipped: y grows downwards).
    func draw(in rect: NSRect)
    /// The menu for a click; nil when the click is handled some other way (`click`).
    func menu() -> NSMenu?
    /// A click that is not a menu (the volume slider).
    func click(anchor: NSRect)
    /// How often the state is read again; 0 = only on events.
    var refreshInterval: TimeInterval { get }
    /// Read the state again (called on the timer and on screen changes).
    func refresh()
}

extension ControlStripModule {
    func click(anchor: NSRect) {}
    var refreshInterval: TimeInterval { 0 }
    func refresh() {}
}

// MARK: - Pixel pictures

/// 1-pt pixel art from strings, the way the crash screens do it: `#` black, `w` white, `g`
/// grey, `d` dark grey, `.` nothing, `r` red, `y` yellow, `b` blue, `n` green.
enum StripArt {
    static func draw(_ rows: [String], at origin: NSPoint) {
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                let c: NSColor?
                switch ch {
                case "#": c = .black
                case "w": c = .white
                case "g": c = NSColor(white: 0.6, alpha: 1)
                case "d": c = NSColor(white: 0.35, alpha: 1)
                case "r": c = NSColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1)
                case "y": c = NSColor(red: 1.0, green: 0.85, blue: 0.1, alpha: 1)
                case "b": c = NSColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
                case "n": c = NSColor(red: 0.15, green: 0.65, blue: 0.2, alpha: 1)
                default: c = nil
                }
                guard let c else { continue }
                c.setFill()
                NSRect(x: origin.x + CGFloat(x), y: origin.y + CGFloat(y), width: 1, height: 1).fill()
            }
        }
    }

    static let network = [
        "................",
        "....########....",
        "....#wwwwww#....",
        "....#wwwwww#....",
        "....#wwwwww#....",
        "....########....",
        ".......##.......",
        ".......##.......",
        "..############..",
        "..#..........#..",
        "..#..........#..",
        "######....######",
        "#wwww#....#wwww#",
        "#wwww#....#wwww#",
        "######....######",
        "................",
    ]
    static let sharing = [
        "................",
        "..#####.........",
        ".#wwwww########.",
        ".#wwwwwwwwwwww#.",
        ".#wwwwwwwwwwww#.",
        ".#wwwwwwwwwwww#.",
        ".#wwwwwwwwwwww#.",
        ".##############.",
        "................",
        "....##....##....",
        "...#ww#..#ww#...",
        "...#ww#..#ww#...",
        "..#wwww##wwww#..",
        "..#wwwwwwwwww#..",
        "...##########...",
        "................",
    ]
    static let colours = [
        "................",
        ".##############.",
        ".#rrrryyyybbbb#.",
        ".#rrrryyyybbbb#.",
        ".#rrrryyyybbbb#.",
        ".#rrrryyyybbbb#.",
        ".#nnnnwwwwgggg#.",
        ".#nnnnwwwwgggg#.",
        ".#nnnnwwwwgggg#.",
        ".#nnnnwwwwgggg#.",
        ".#ddddrrrryyyy#.",
        ".#ddddrrrryyyy#.",
        ".#ddddrrrryyyy#.",
        ".#ddddrrrryyyy#.",
        ".##############.",
        "................",
    ]
    static let monitor = [
        "................",
        ".##############.",
        ".#wwwwwwwwwwww#.",
        ".#wbbbbbbbbbbw#.",
        ".#wbbbbbbbbbbw#.",
        ".#wbbbbbbbbbbw#.",
        ".#wbbbbbbbbbbw#.",
        ".#wbbbbbbbbbbw#.",
        ".#wwwwwwwwwwww#.",
        ".##############.",
        ".......##.......",
        ".......##.......",
        "....########....",
        "....#gggggg#....",
        "....########....",
        "................",
    ]
    static func speaker(level: Int) -> [String] {
        var rows = [
            "................",
            "................",
            "......#.........",
            ".....##.........",
            "..#####.........",
            "..#ww##.........",
            "..#ww##.........",
            "..#ww##.........",
            "..#ww##.........",
            "..#ww##.........",
            "..#####.........",
            ".....##.........",
            "......#.........",
            "................",
            "................",
            "................",
        ]
        func put(_ x: Int, _ y: Int) { var r = Array(rows[y]); r[x] = "#"; rows[y] = String(r) }
        if level >= 1 { put(9, 6); put(9, 7); put(9, 8) }
        if level >= 2 { put(11, 4); put(11, 5); put(11, 6); put(11, 7); put(11, 8); put(11, 9); put(11, 10) }
        if level >= 3 { put(13, 2); put(13, 3); put(13, 4); put(13, 5); put(13, 6); put(13, 7); put(13, 8); put(13, 9); put(13, 10); put(13, 11); put(13, 12) }
        return rows
    }
    static func battery(fraction: Double, charging: Bool) -> [String] {
        var rows = [
            "................",
            "................",
            "................",
            "................",
            "...###########..",
            "...#wwwwwwwww##.",
            "...#wwwwwwwww#w#",
            "...#wwwwwwwww#w#",
            "...#wwwwwwwww#w#",
            "...#wwwwwwwww##.",
            "...###########..",
            "................",
            "................",
            "................",
            "................",
            "................",
        ]
        let cells = max(0, min(9, Int((fraction * 9).rounded())))
        for y in 5...9 { var r = Array(rows[y]); for x in 0..<cells { r[4 + x] = fraction < 0.2 ? "r" : "#" }; rows[y] = String(r) }
        if charging { for (x, y) in [(8, 3), (7, 4), (6, 5), (7, 6), (9, 6), (8, 7), (7, 8)] { var r = Array(rows[y]); r[x] = "y"; rows[y] = String(r) } }
        return rows
    }
    static let mirroring = [
        "................",
        "#######..#######",
        "#wwwww#..#wwwww#",
        "#wbbbw#..#wbbbw#",
        "#wbbbw#..#wbbbw#",
        "#wbbbw#..#wbbbw#",
        "#wwwww#..#wwwww#",
        "#######..#######",
        "...#........#...",
        "..###......###..",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
    ]
}

// MARK: - Modules

/// AppleTalk in its day; the network connection now: which interface carries an address.
final class NetworkModule: ControlStripModule {
    let id = "network"
    var isAvailable: Bool { true }
    var width: CGFloat { 20 }
    var refreshInterval: TimeInterval { 5 }
    private(set) var active: [(name: String, address: String)] = []

    func refresh() { active = Self.activeInterfaces() }

    static func activeInterfaces() -> [(name: String, address: String)] {
        var out: [(String, String)] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let i = p {
            defer { p = i.pointee.ifa_next }
            guard let addr = i.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  (Int32(i.pointee.ifa_flags) & IFF_UP) != 0, (Int32(i.pointee.ifa_flags) & IFF_LOOPBACK) == 0 else { continue }
            let name = String(cString: i.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                out.append((name, String(cString: host)))
            }
        }
        return out
    }

    func draw(in rect: NSRect) {
        StripArt.draw(StripArt.network, at: rect.origin)
        if active.isEmpty {   // no connection: the wire is cut
            NSColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1).setFill()
            NSRect(x: rect.minX + 6, y: rect.minY + 7, width: 4, height: 2).fill()
        }
    }

    func menu() -> NSMenu? {
        let m = NSMenu()
        if active.isEmpty {
            m.addItem(withTitle: "Not connected", action: nil, keyEquivalent: "")
        } else {
            for i in active { m.addItem(withTitle: "\(i.name)  \(i.address)", action: nil, keyEquivalent: "") }
        }
        m.addItem(.separator())
        m.addItem(ControlStripActions.item("Open Network Settings…", url: "x-apple.systempreferences:com.apple.Network-Settings.extension"))
        return m
    }
}

/// File Sharing: on or off, as far as a non-root process can tell.
final class SharingModule: ControlStripModule {
    let id = "sharing"
    var isAvailable: Bool { true }
    var width: CGFloat { 20 }
    var refreshInterval: TimeInterval { 30 }
    private(set) var isOn = false

    func refresh() { isOn = Self.fileSharingOn() }

    /// smbd is loaded as a system daemon only while File Sharing is on; `launchctl print` says
    /// so without privileges. Any failure reads as off.
    static func fileSharingOn() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["print", "system/com.apple.smbd"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    func draw(in rect: NSRect) {
        StripArt.draw(StripArt.sharing, at: rect.origin)
        if !isOn {   // off: the hands are grey
            NSColor(white: 0.6, alpha: 1).setFill()
            NSRect(x: rect.minX + 4, y: rect.minY + 10, width: 8, height: 4).fill()
        }
    }

    func menu() -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: isOn ? "File Sharing is on" : "File Sharing is off", action: nil, keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(ControlStripActions.item("Open Sharing Settings…", url: "x-apple.systempreferences:com.apple.Sharing-Settings.extension"))
        return m
    }
}

/// Colour depth: every Mac shows millions now; the menu is the one the module had, for the look.
final class ColourDepthModule: ControlStripModule {
    let id = "colours"
    var isAvailable: Bool { true }
    var width: CGFloat { 20 }
    func draw(in rect: NSRect) { StripArt.draw(StripArt.colours, at: rect.origin) }
    func menu() -> NSMenu? {
        let m = NSMenu()
        for (title, current) in [("Black & White", false), ("256", false), ("Thousands", false), ("Millions", true)] {
            let i = m.addItem(withTitle: title, action: nil, keyEquivalent: "")
            i.state = current ? .on : .off
            i.isEnabled = false
        }
        m.addItem(.separator())
        let note = m.addItem(withTitle: "macOS draws millions of colours", action: nil, keyEquivalent: "")
        note.isEnabled = false
        return m
    }
}

/// Monitor resolution: the mode of the display the strip sits on, and the modes it offers.
final class ResolutionModule: ControlStripModule {
    let id = "resolution"
    var isAvailable: Bool { true }
    var width: CGFloat { 20 + textWidth + 4 }
    private var textWidth: CGFloat { (label as NSString).size(withAttributes: Self.font).width.rounded(.up) }
    static let font: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.black]
    var display: CGDirectDisplayID = CGMainDisplayID()
    private(set) var label = ""
    /// Set after a switch: the mode to go back to unless the user keeps the new one.
    var onSwitched: ((CGDisplayMode) -> Void)?

    func refresh() {
        if let mode = CGDisplayCopyDisplayMode(display) { label = "\(mode.width)×\(mode.height)" } else { label = "" }
    }

    func draw(in rect: NSRect) {
        StripArt.draw(StripArt.monitor, at: rect.origin)
        (label as NSString).draw(at: NSPoint(x: rect.minX + 20, y: rect.minY + 1), withAttributes: Self.font)
    }

    /// The modes worth offering: usable for the desktop, one per size, largest first.
    static func offeredModes(_ modes: [CGDisplayMode]) -> [CGDisplayMode] {
        var seen = Set<String>()
        return modes.filter { $0.isUsableForDesktopGUI() }
            .sorted { ($0.width, $0.height) > ($1.width, $1.height) }
            .filter { seen.insert("\($0.width)x\($0.height)").inserted }
    }

    func menu() -> NSMenu? {
        let m = NSMenu()
        guard let current = CGDisplayCopyDisplayMode(display),
              let all = CGDisplayCopyAllDisplayModes(display, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] else { return m }
        for mode in Self.offeredModes(all) {
            let i = m.addItem(withTitle: "\(mode.width) × \(mode.height)", action: #selector(pick(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = mode
            i.state = (mode.width == current.width && mode.height == current.height) ? .on : .off
        }
        return m
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let obj = sender.representedObject, CFGetTypeID(obj as CFTypeRef) == CGDisplayMode.typeID,
              let before = CGDisplayCopyDisplayMode(display) else { return }
        let mode = obj as! CGDisplayMode
        guard mode.width != before.width || mode.height != before.height else { return }
        if Self.set(mode, on: display) { onSwitched?(before) }
    }

    static func set(_ mode: CGDisplayMode, on display: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        CGConfigureDisplayWithDisplayMode(config, display, mode, nil)
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }
}

/// Sound volume: the speaker with its waves, and the slider on a click.
final class VolumeModule: ControlStripModule {
    let id = "volume"
    var isAvailable: Bool { true }
    var width: CGFloat { 20 }
    var refreshInterval: TimeInterval { 2 }
    private(set) var level = 0

    func refresh() {
        let v = SystemVolume.isMuted ? 0 : Double(SystemVolume.level ?? 0)
        level = v <= 0.01 ? 0 : v < 0.34 ? 1 : v < 0.67 ? 2 : 3
    }
    func draw(in rect: NSRect) { StripArt.draw(StripArt.speaker(level: level), at: rect.origin) }
    func menu() -> NSMenu? { nil }
    /// Press, drag, release: the Platinum slider stands up above the module for the drag.
    func click(anchor: NSRect) {
        PlatinumVolumeSlider.shared.onChange = { [weak self] in self?.refresh() }
        PlatinumVolumeSlider.shared.begin(above: anchor)
    }
}

/// The battery, on a Mac that has one.
final class BatteryModule: ControlStripModule {
    let id = "battery"
    var isAvailable: Bool { fraction != nil }
    var width: CGFloat { 20 + (text as NSString).size(withAttributes: ResolutionModule.font).width.rounded(.up) + 4 }
    var refreshInterval: TimeInterval { 10 }
    private var text: String { "\(Int(((fraction ?? 0) * 100).rounded()))%" }
    private(set) var fraction: Double?
    private(set) var charging = false

    func refresh() {
        let (f, c) = Self.read()
        fraction = f; charging = c
    }

    static func read() -> (Double?, Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return (nil, false) }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Double, let max = d[kIOPSMaxCapacityKey] as? Double, max > 0 else { continue }
            return (cur / max, (d[kIOPSIsChargingKey] as? Bool) ?? false)
        }
        return (nil, false)
    }

    func draw(in rect: NSRect) {
        StripArt.draw(StripArt.battery(fraction: fraction ?? 0, charging: charging), at: rect.origin)
        (text as NSString).draw(at: NSPoint(x: rect.minX + 20, y: rect.minY + 1), withAttributes: ResolutionModule.font)
    }

    func menu() -> NSMenu? {
        let m = NSMenu()
        let pct = Int(((fraction ?? 0) * 100).rounded())
        m.addItem(withTitle: charging ? "\(pct)% — charging" : "\(pct)%", action: nil, keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(ControlStripActions.item("Open Battery Settings…", url: "x-apple.systempreferences:com.apple.Battery-Settings.extension"))
        return m
    }
}

/// Video mirroring, with two or more displays.
final class MirroringModule: ControlStripModule {
    let id = "mirroring"
    var isAvailable: Bool { Self.displayCount() >= 2 }
    var width: CGFloat { 20 }
    private(set) var isOn = false

    static func displayCount() -> Int {
        var n: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &n)
        var m: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &m)
        return Int(max(n, m))
    }

    func refresh() { isOn = CGDisplayIsInMirrorSet(CGMainDisplayID()) != 0 }

    func draw(in rect: NSRect) {
        StripArt.draw(StripArt.mirroring, at: rect.origin)
        if !isOn {   // off: the second picture is dark
            NSColor(white: 0.35, alpha: 1).setFill()
            NSRect(x: rect.minX + 10, y: rect.minY + 3, width: 3, height: 3).fill()
        }
    }

    func menu() -> NSMenu? {
        let m = NSMenu()
        let i = m.addItem(withTitle: isOn ? "Turn Mirroring Off" : "Turn Mirroring On", action: #selector(toggle), keyEquivalent: "")
        i.target = self
        m.addItem(.separator())
        m.addItem(ControlStripActions.item("Open Displays Settings…", url: "x-apple.systempreferences:com.apple.Displays-Settings.extension"))
        return m
    }

    @objc private func toggle() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var n: UInt32 = 0
        guard CGGetOnlineDisplayList(8, &ids, &n) == .success, n >= 2 else { return }
        let main = CGMainDisplayID()
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        for d in ids.prefix(Int(n)) where d != main {
            CGConfigureDisplayMirrorOfDisplay(config, d, isOn ? kCGNullDirectDisplay : main)
        }
        CGCompleteDisplayConfiguration(config, .forSession)
        refresh()
    }
}

/// Menu items that open a Settings pane.
enum ControlStripActions {
    static func item(_ title: String, url: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(Opener.open(_:)), keyEquivalent: "")
        i.target = Opener.shared
        i.representedObject = url
        return i
    }
    final class Opener: NSObject {
        static let shared = Opener()
        @objc func open(_ sender: NSMenuItem) {
            if let s = sender.representedObject as? String, let u = URL(string: s) { NSWorkspace.shared.open(u) }
        }
    }
}
