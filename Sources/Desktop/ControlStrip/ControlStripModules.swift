import AppKit
import CoreGraphics
import IOKit.ps
import SystemConfiguration
import CoreAudio

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
    /// The text beside the picture (resolution, battery), when the theme supplies the picture.
    func drawText(in rect: NSRect)
    /// How often the state is read again; 0 = only on events.
    var refreshInterval: TimeInterval { get }
    /// Read the state again (called on the timer and on screen changes).
    func refresh()
}

extension ControlStripModule {
    func click(anchor: NSRect) {}
    func drawText(in rect: NSRect) {}
    var refreshInterval: TimeInterval { 0 }
    func refresh() {}
}

// MARK: - Pixel pictures

/// 1-pt pixel art from strings, the way the crash screens do it: `#` black, `w` white, `l`
/// light grey, `g` grey, `m` mid grey, `d` dark grey, `.` nothing, `r` red, `y` yellow,
/// `b` blue, `n` green.
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
                case "l": c = NSColor(white: 0.83, alpha: 1)   // light: the lit face
                case "m": c = NSColor(white: 0.5, alpha: 1)    // mid: the shaded face
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

    // The PowerBook's own modules, drawn like Mac OS 9 (authentic)'s: a black outline, white
    // faces, a touch of colour — the four-grey theme shows them in grey like the rest.

    /// HD Spin Down: the internal disk, its activity light on.
    static let hardDisk = [
        "................",
        "................",
        "................",
        "................",
        ".##############.",
        ".#wwwwwwwwwwww#.",
        ".#wwwwwwwwwwww#.",
        ".#wwwwwwwwwwww#.",
        ".##############.",
        ".#wwwwwwwwwwww#.",
        ".#wnnwwwwwwwww#.",
        ".#wwwwwwwwwwww#.",
        ".##############.",
        "................",
        "................",
        "................",
    ]
    /// Power Settings on the adapter: the two-prong plug, its cord hanging down.
    static let powerPlug = [
        "................",
        "....##..##......",
        "....##..##......",
        "....##..##......",
        "..##########....",
        "..#wwwwwwww#....",
        "..#wwwwwwww#....",
        "..#wwwwwwww#....",
        "...#wwwwww#.....",
        "....######......",
        "......##........",
        "......##........",
        "......##........",
        ".......##.......",
        "........###.....",
        "................",
    ]
    /// Power Settings on the battery: the cell, half full, as the Battery module draws it.
    static let powerBattery = [
        "................",
        "................",
        "................",
        "................",
        "...###########..",
        "...#####wwwww##.",
        "...#####wwwww#w#",
        "...#####wwwww#w#",
        "...#####wwwww#w#",
        "...#####wwwww##.",
        "...###########..",
        "................",
        "................",
        "................",
        "................",
        "................",
    ]
    /// Sleep Now: the crescent moon the era used for sleep.
    static let sleep = [
        "................",
        "....####........",
        "...#www#........",
        "..#www#.........",
        ".#www#..........",
        ".#ww#...........",
        ".#ww#...........",
        ".#ww#...........",
        ".#ww#...........",
        ".#www#..........",
        ".#wwww##....###.",
        "..#wwwww####ww#.",
        "..##wwwwwwwww#..",
        "....#########...",
        "................",
        "................",
    ]
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
        drawText(in: rect)
    }
    func drawText(in rect: NSRect) {
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
        drawText(in: rect)
    }
    func drawText(in rect: NSRect) {
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
    var isAvailable: Bool { true }   // on the strip as it was; with one display the menu says so
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
        if Self.displayCount() < 2 {
            i.isEnabled = false
            let note = m.addItem(withTitle: "Needs a second display", action: nil, keyEquivalent: ""); note.isEnabled = false
        }
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

// MARK: - The rest of a Mac OS 9 strip

/// Keychain: the strip's padlock. Locking every keychain is what the module did; the rest
/// opens Passwords (or Keychain Access on a Mac without it).
final class KeychainModule: ControlStripModule {
    let id = "keychain"
    var isAvailable: Bool { true }
    var width: CGFloat { 20 }
    static let art = [
        "................",
        ".....######.....",
        "....##....##....",
        "....#......#....",
        "....#......#....",
        "....#......#....",
        "..############..",
        "..#wwwwwwwwww#..",
        "..#wwwwwwwwww#..",
        "..#wwwww#wwww#..",
        "..#wwww###www#..",
        "..#wwwww#wwww#..",
        "..#wwwww#wwww#..",
        "..#wwwwwwwwww#..",
        "..############..",
        "................",
    ]
    func draw(in rect: NSRect) { StripArt.draw(Self.art, at: rect.origin) }
    func menu() -> NSMenu? {
        let m = NSMenu()
        let lock = m.addItem(withTitle: "Lock All Keychains", action: #selector(lockAll), keyEquivalent: "")
        lock.target = self
        m.addItem(.separator())
        let passwords = "/System/Applications/Passwords.app"
        let keychainAccess = "/System/Library/CoreServices/Applications/Keychain Access.app"
        let path = FileManager.default.fileExists(atPath: passwords) ? passwords : keychainAccess
        let open = m.addItem(withTitle: path == passwords ? "Open Passwords…" : "Open Keychain Access…", action: #selector(openApp(_:)), keyEquivalent: "")
        open.target = self; open.representedObject = path
        return m
    }
    @objc private func lockAll() {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/security"); p.arguments = ["lock-keychain", "-a"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
    }
    @objc private func openApp(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? String else { return }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: p), configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Media Bay: what sits in the PowerBook's bay — today, the removable volumes on the desk,
/// each with an Eject.
final class MediaBayModule: ControlStripModule {
    let id = "mediabay"
    var isAvailable: Bool { true }
    var width: CGFloat { 20 }
    var refreshInterval: TimeInterval { 5 }
    private(set) var volumes: [(name: String, url: URL)] = []

    func refresh() { volumes = Self.removableVolumes() }

    static func removableVolumes() -> [(name: String, url: URL)] {
        let keys: [URLResourceKey] = [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsInternalKey, .volumeLocalizedNameKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { u in
            guard let v = try? u.resourceValues(forKeys: Set(keys)),
                  (v.volumeIsRemovable == true || v.volumeIsEjectable == true || v.volumeIsInternal == false) else { return nil }
            return (v.volumeLocalizedName ?? u.lastPathComponent, u)
        }
    }

    static let art = [
        "................",
        "................",
        "................",
        "..############..",
        "..#..........#..",
        "..#.wwwwwwww.#..",
        "..#.wwwwwwww.#..",
        "..#.wwwwwwww.#..",
        "..#..........#..",
        "..############..",
        "..#dddddddddd#..",
        "..############..",
        "................",
        "................",
        "................",
        "................",
    ]
    func draw(in rect: NSRect) {
        StripArt.draw(Self.art, at: rect.origin)
        if !volumes.isEmpty {   // something in the bay: the slot lights up
            NSColor(red: 0.15, green: 0.65, blue: 0.2, alpha: 1).setFill()
            NSRect(x: rect.minX + 4, y: rect.minY + 10, width: 8, height: 1).fill()
        }
    }
    func menu() -> NSMenu? {
        let m = NSMenu()
        if volumes.isEmpty {
            let none = m.addItem(withTitle: "Nothing in the bay", action: nil, keyEquivalent: ""); none.isEnabled = false
            return m
        }
        for v in volumes {
            let i = m.addItem(withTitle: "Eject \(v.name)", action: #selector(eject(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = v.url
        }
        return m
    }
    @objc private func eject(_ sender: NSMenuItem) {
        guard let u = sender.representedObject as? URL else { return }
        try? NSWorkspace.shared.unmountAndEjectDevice(at: u)
        refresh()
    }
}

/// Printer Selector: the default printer, and the others to choose from.
final class PrinterModule: ControlStripModule {
    let id = "printer"
    var isAvailable: Bool { !NSPrinter.printerNames.isEmpty }
    var width: CGFloat { 20 }
    var refreshInterval: TimeInterval { 30 }
    private(set) var current = ""
    func refresh() { current = NSPrintInfo.shared.printer.name }
    static let art = [
        "................",
        ".....######.....",
        ".....#wwww#.....",
        ".....#wwww#.....",
        ".....#wwww#.....",
        "..############..",
        "..#dddddddddd#..",
        "..#dddddddddd#..",
        "..#dddddddddd#..",
        "..############..",
        ".....######.....",
        ".....#wwww#.....",
        ".....#wwww#.....",
        ".....######.....",
        "................",
        "................",
    ]
    func draw(in rect: NSRect) { StripArt.draw(Self.art, at: rect.origin) }
    func menu() -> NSMenu? {
        let m = NSMenu()
        for name in NSPrinter.printerNames {
            let i = m.addItem(withTitle: name, action: #selector(choose(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = name
            i.state = name == current ? .on : .off
        }
        m.addItem(.separator())
        m.addItem(ControlStripActions.item("Open Printers & Scanners…", url: "x-apple.systempreferences:com.apple.Print-Scan-Settings.extension"))
        return m
    }
    @objc private func choose(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        // The queue name, not the display name, is what lpoptions wants.
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/lpoptions")
        p.arguments = ["-d", name.replacingOccurrences(of: " ", with: "_")]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        refresh()
    }
}

/// SoundSource: where the sound goes — the output device, and the input beside it.
final class SoundSourceModule: ControlStripModule {
    let id = "soundsource"
    var isAvailable: Bool { true }
    var width: CGFloat { 20 }
    var refreshInterval: TimeInterval { 10 }
    private(set) var outputs: [(name: String, id: AudioDeviceID)] = []
    private(set) var inputs: [(name: String, id: AudioDeviceID)] = []
    private(set) var currentOutput: AudioDeviceID = 0
    private(set) var currentInput: AudioDeviceID = 0

    func refresh() {
        let all = Self.devices()
        outputs = all.filter { Self.streams($0.id, input: false) > 0 }
        inputs = all.filter { Self.streams($0.id, input: true) > 0 }
        currentOutput = Self.defaultDevice(input: false)
        currentInput = Self.defaultDevice(input: true)
    }

    static func devices() -> [(name: String, id: AudioDeviceID)] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var name: CFString = "" as CFString
            var nsize = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nsize, &name) == noErr else { return nil }
            return (name as String, id)
        }
    }
    static func streams(_ id: AudioDeviceID, input: Bool) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }
    static func defaultDevice(input: Bool) -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }
    static func setDefault(_ id: AudioDeviceID, input: Bool) {
        var addr = AudioObjectPropertyAddress(mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &v)
    }

    static let art = [
        "................",
        "................",
        "......##........",
        ".....#ww#.......",
        ".....#ww#.......",
        ".....#ww#.......",
        ".....#ww#.......",
        "...#.#ww#.#.....",
        "...#.####.#.....",
        "...#......#.....",
        "....######......",
        "......##........",
        "......##........",
        "....######......",
        "................",
        "................",
    ]
    func draw(in rect: NSRect) { StripArt.draw(Self.art, at: rect.origin) }
    func menu() -> NSMenu? {
        let m = NSMenu()
        let outHead = m.addItem(withTitle: "Output", action: nil, keyEquivalent: ""); outHead.isEnabled = false
        for d in outputs {
            let i = m.addItem(withTitle: d.name, action: #selector(pickOutput(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = NSNumber(value: d.id); i.state = d.id == currentOutput ? .on : .off
        }
        m.addItem(.separator())
        let inHead = m.addItem(withTitle: "Input", action: nil, keyEquivalent: ""); inHead.isEnabled = false
        for d in inputs {
            let i = m.addItem(withTitle: d.name, action: #selector(pickInput(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = NSNumber(value: d.id); i.state = d.id == currentInput ? .on : .off
        }
        return m
    }
    @objc private func pickOutput(_ sender: NSMenuItem) {
        if let n = sender.representedObject as? NSNumber { Self.setDefault(n.uint32Value, input: false); refresh() }
    }
    @objc private func pickInput(_ sender: NSMenuItem) {
        if let n = sender.representedObject as? NSNumber { Self.setDefault(n.uint32Value, input: true); refresh() }
    }
}

// MARK: - The System 7 strip's own modules

/// HD Spin Down: the module that put the internal disk to sleep on a PowerBook. macOS decides
/// that itself (Energy Saver's "Put hard disks to sleep"), and only root may change it, so the
/// module shows what the setting is now and opens the pane.
final class HDSpinDownModule: ControlStripModule {
    let id = "hdspindown"
    var isAvailable: Bool { true }
    var width: CGFloat { 20 }
    var refreshInterval: TimeInterval { 120 }   // a setting, not a reading: rarely
    private(set) var minutes: Int?

    func refresh() { minutes = Self.diskSleepMinutes() }

    /// `pmset -g` prints the live settings; `disksleep` is the spin-down time in minutes
    /// (0 = never). No privileges needed to read it.
    static func diskSleepMinutes() -> Int? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if parts.first == "disksleep", parts.count > 1 { return Int(parts[1]) }
        }
        return nil
    }

    func draw(in rect: NSRect) { StripArt.draw(StripArt.hardDisk, at: rect.origin) }

    func menu() -> NSMenu? {
        let m = NSMenu()
        let state: String
        switch minutes {
        case .some(0): state = "Disks never spin down"
        case .some(let n): state = "Disks spin down after \(n) min"
        default: state = "Spin-down time unknown"
        }
        m.addItem(withTitle: state, action: nil, keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(ControlStripActions.item("Open Energy Settings…", url: "x-apple.systempreferences:com.apple.Battery-Settings.extension"))
        return m
    }
}

/// Power Settings: where the Mac's power is coming from, and the pane that governs it.
final class PowerModule: ControlStripModule {
    let id = "power"
    var isAvailable: Bool { true }
    var width: CGFloat { 20 }
    var refreshInterval: TimeInterval { 30 }
    private(set) var onBattery = false
    private(set) var hasBattery = false

    func refresh() {
        hasBattery = BatteryModule.read().0 != nil
        // What is actually running the Mac right now, not what the battery is doing: a full
        // battery on the adapter reports "not charging", which is not the same as unplugged.
        let source = IOPSGetProvidingPowerSourceType(IOPSCopyPowerSourcesInfo()?.takeRetainedValue())?.takeRetainedValue() as String?
        onBattery = source == kIOPSBatteryPowerValue
    }

    func draw(in rect: NSRect) { StripArt.draw(onBattery ? StripArt.powerBattery : StripArt.powerPlug, at: rect.origin) }

    func menu() -> NSMenu? {
        let m = NSMenu()
        let source = !hasBattery ? "Power adapter" : (onBattery ? "Battery power" : "Power adapter")
        m.addItem(withTitle: "Source: \(source)", action: nil, keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(ControlStripActions.item("Open Energy Settings…", url: "x-apple.systempreferences:com.apple.Battery-Settings.extension"))
        m.addItem(ControlStripActions.item("Open Lock Screen Settings…", url: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension"))
        return m
    }
}

/// Sleep Now: the one-click module. No menu — the click does it, as the original did.
final class SleepNowModule: ControlStripModule {
    let id = "sleep"
    var isAvailable: Bool { true }
    var width: CGFloat { 20 }

    func draw(in rect: NSRect) { StripArt.draw(StripArt.sleep, at: rect.origin) }

    func menu() -> NSMenu? { nil }

    func click(anchor: NSRect) {
        // `pmset sleepnow` is the user-level way to sleep the Mac; the module's whole purpose.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["sleepnow"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
