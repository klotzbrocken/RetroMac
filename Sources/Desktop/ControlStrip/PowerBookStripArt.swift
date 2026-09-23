import AppKit

/// The Control Strip as the PowerBook 150 showed it (System 7.1.1, 1994), after the picture in
/// Apple's own "PowerBook Getting Started" for the 150, chapter 5: a close box at the left end,
/// hollow scroll arrows, every module a raised grey button with its black triangle, the Battery
/// Monitor as a battery and a row of eight cells, and the tab with its grip at the right end.
/// The 150's screen showed four greys (2 bits per pixel); System 7 drew each module's 16-colour
/// icon at the nearest of them, so the pictures here are drawn in exactly those four:
/// `#` black, `d` #555555, `g` #AAAAAA, `w` white, `.` the button showing through.
enum PowerBookStrip {

    static func draw(_ rows: [String], at origin: NSPoint, flipped: Bool = false) {
        let width = rows.map(\.count).max() ?? 0
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                let c: NSColor
                switch ch {
                case "#": c = FourGrays.black
                case "d": c = FourGrays.dark
                case "g": c = FourGrays.light
                case "w": c = FourGrays.white
                default: continue
                }
                c.setFill()
                let px = flipped ? width - 1 - x : x
                NSRect(x: origin.x + CGFloat(px), y: origin.y + CGFloat(y), width: 1, height: 1).fill()
            }
        }
    }

    /// A raised button: #AAAAAA face, white top and left edge, #555555 bottom and right.
    static func button(_ r: NSRect) {
        FourGrays.light.setFill(); r.fill()
        FourGrays.white.setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width - 1, height: 1).fill()
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height - 1).fill()
        FourGrays.dark.setFill()
        NSRect(x: r.minX + 1, y: r.maxY - 1, width: r.width - 1, height: 1).fill()
        NSRect(x: r.maxX - 1, y: r.minY + 1, width: 1, height: r.height - 1).fill()
    }

    // MARK: The ends

    /// The close box at the left end: a sunken frame around a raised square.
    static let closeBox = [
        "ddddddddw",
        "dggggggww",
        "dg#####gw",
        "dg#ddd#gw",
        "dg#ddd#gw",
        "dg#ddd#gw",
        "dg#####gw",
        "dggggggww",
        "wwwwwwwww",
    ]

    /// The tab at the right end (13 × 24): the chamfered cap with its dotted grip and the
    /// D-shaped handle. Collapsed, it is all of the strip that shows.
    static let tab: [String] = {
        let w = 13, h = 24
        var g = Array(repeating: Array(repeating: Character("."), count: w), count: h)
        func set(_ x: Int, _ y: Int, _ c: Character) { if x >= 0, x < w, y >= 0, y < h { g[y][x] = c } }
        // Face, inside the outline.
        for y in 1..<(h - 1) {
            let cut = max(0, 4 - y, y - (h - 1 - 4))          // the chamfers, top and bottom right
            for x in 1..<(w - 1 - cut) { set(x, y, "g") }
        }
        // Bevel: white along the top and left, #555555 along the bottom, right and chamfers.
        for x in 1..<(w - 5) { set(x, 1, "w") }
        for y in 1..<(h - 1) { set(1, y, "w") }
        for x in 2..<(w - 5) { set(x, h - 2, "d") }
        for y in 5..<(h - 5) { set(w - 2, y, "d") }
        for i in 0..<4 { set(w - 5 + i, 1 + i, "d"); set(w - 5 + i, h - 2 - i, "d") }
        // Outline.
        for x in 0..<(w - 4) { set(x, 0, "#"); set(x, h - 1, "#") }
        for y in 0..<h { set(0, y, "#") }
        for y in 4..<(h - 4) { set(w - 1, y, "#") }
        for i in 0..<4 { set(w - 4 + i, i, "#"); set(w - 4 + i, h - 1 - i, "#") }
        // The grip: two staggered columns of dots.
        for y in stride(from: 4, through: h - 6, by: 2) { set(3, y, "d") }
        for y in stride(from: 5, through: h - 5, by: 2) { set(4, y, "w") }
        // The handle: a D, open to the left.
        for y in 7...16 { set(7, y, "#") }
        for x in 7...9 { set(x, 7, "#"); set(x, 16, "#") }
        for y in 8...15 { set(10, y, "#"); for x in 8...9 { set(x, y, "w") } }
        return g.map { String($0) }
    }()

    /// A scroll arrow, hollow: black when there is somewhere to scroll, #555555 when not.
    static func arrow(pointsLeft: Bool, enabled: Bool) -> [String] {
        let ink: Character = enabled ? "#" : "d"
        let rows = [
            "....o....",
            "...oo....",
            "..owoooo.",
            ".owwwwwo.",
            "owwwwwwo.",
            ".owwwwwo.",
            "..owoooo.",
            "...oo....",
            "....o....",
        ].map { String($0.map { $0 == "o" ? ink : $0 }) }
        return pointsLeft ? rows : rows.map { String($0.reversed()) }
    }

    // MARK: The modules

    /// Every picture is 16 px tall; most are 16 wide, the Battery Monitor is its own width.
    static func picture(for module: ControlStripModule) -> [String]? {
        switch module.id {
        case "network", "appletalk": return appleTalk
        case "sharing": return fileSharing
        case "hdspindown": return hdSpinDown
        case "power": return powerSettings
        case "sleep": return sleepNow
        case "volume": return speaker(level: (module as? VolumeModule)?.level ?? 2)
        case "battery":
            let b = module as? BatteryModule
            return batteryMonitor(fraction: b?.fraction ?? 0, charging: b?.charging ?? false)
        default: return nil
        }
    }

    /// Modules that open no menu of their own in the 150's strip have no triangle: the Battery
    /// Monitor is a gauge.
    static func hasTriangle(_ module: ControlStripModule) -> Bool { module.id != "battery" }

    /// AppleTalk Switch: the compact Mac, its screen sunk in, the floppy slot below.
    static let appleTalk = [
        "................",
        "...#########....",
        "..#.........#...",
        "..#.ddddddw.#...",
        "..#.dwwwwww.#...",
        "..#.dwwwwww.#...",
        "..#.dwwwwww.#...",
        "..#.dwwwwww.#...",
        "..#.wwwwwww.#...",
        "..#.........#...",
        "..#.........#...",
        "..#.d...###.#...",
        "..#.........#...",
        "..#ddddddddd#...",
        "...#########....",
        "................",
    ]

    /// File Sharing: the folder, its front a 50 % pattern.
    static let fileSharing = [
        "................",
        "................",
        "................",
        "...####.........",
        "..#gggg#........",
        ".#gggggg#######.",
        ".#wwwwwwwwwwww#.",
        ".#w.w.w.w.w.w.#.",
        ".#.w.w.w.w.w.w#.",
        ".#w.w.w.w.w.w.#.",
        ".#.w.w.w.w.w.w#.",
        ".#w.w.w.w.w.w.#.",
        ".#.w.w.w.w.w.w#.",
        ".##############.",
        "................",
        "................",
    ]

    /// HD Spin Down: the drive, flat, with the three strokes of its spinning above it.
    static let hdSpinDown = [
        "................",
        "................",
        "................",
        "...#...#...#....",
        "...#...#...#....",
        "....#..#..#.....",
        "................",
        "..############..",
        ".#wwwwwwwwwwww#.",
        ".#w..........d#.",
        ".#wdd........d#.",
        ".#dddddddddddd#.",
        "..############..",
        "................",
        "................",
        "................",
    ]

    /// Power Settings: the lever raised off its plate, the slider below it.
    static let powerSettings = [
        "................",
        "................",
        "............##..",
        "...........###..",
        "..........###...",
        ".........###....",
        "........###.....",
        "..######d##.....",
        ".#ddddddd#......",
        ".#########......",
        "................",
        ".dddddddddddddd.",
        "................",
        "......#.........",
        ".######d#######.",
        "......#.........",
    ]

    /// Sleep Now: three z's rising over the reclined lid.
    static let sleepNow = [
        "..........#####.",
        ".............#..",
        "............#...",
        ".....####..#....",
        ".......#..#####.",
        "......#.........",
        ".###.####.......",
        "..#.............",
        ".###..........#.",
        ".............#..",
        "............#...",
        "...........#....",
        ".##########.....",
        ".#dddddddd#.....",
        ".##########.....",
        "................",
    ]

    /// Sound Volume: the speaker, its cone lit from above, and one to three waves for the level.
    static func speaker(level: Int) -> [String] {
        var rows = [
            "................",
            "........#.......",
            ".......##.......",
            "......#w#.......",
            ".....#wg#.......",
            "######wg#.......",
            "#www#wwg#.......",
            "#wgg#wgg#.......",
            "#wgg#wgg#.......",
            "#ggd#wgd#.......",
            "######gd#.......",
            ".....#gd#.......",
            "......#d#.......",
            ".......##.......",
            "........#.......",
            "................",
        ]
        func put(_ x: Int, _ y: Int) { var r = Array(rows[y]); r[x] = "#"; rows[y] = String(r) }
        if level >= 1 { put(10, 5); for y in 6...9 { put(11, y) }; put(10, 10) }
        if level >= 2 { put(12, 3); put(13, 4); for y in 5...10 { put(14, y) }; put(13, 11); put(12, 12) }
        if level >= 3 { put(14, 1); put(15, 2); for y in 3...12 { put(15, y) }; put(15, 13); put(14, 14) }
        return rows
    }

    /// Battery Monitor: the battery standing up, a rule, and eight cells — dark for the charge
    /// there is, white for the charge that is gone. Charging, the battery wears a white bolt.
    static func batteryMonitor(fraction: Double, charging: Bool) -> [String] {
        var battery = [
            "................",
            "...##...........",
            "..#dd#..........",
            ".#wwww#.........",
            ".#w##w#.........",
            ".##..##.........",
            ".#w##w#.........",
            ".#wwww#.........",
            ".#gggg#.........",
            ".#gggg#.........",
            ".#g##g#.........",
            ".#gggg#.........",
            ".#dddd#.........",
            "..####..........",
            "................",
            "................",
        ].map { String($0.prefix(8)) }
        if charging {
            for (x, y) in [(4, 8), (3, 9), (4, 10), (3, 11)] { var r = Array(battery[y]); r[x] = "w"; battery[y] = String(r) }
        }
        let cells = 8
        let lit = max(0, min(cells, Int((max(0, min(1, fraction)) * Double(cells)).rounded())))
        var rows: [String] = []
        for y in 0..<16 {
            var r = battery[y] + "."                                   // 8 + 1
            r += (2...13).contains(y) ? "dw" : ".."                     // the rule, sunk in
            r += ".."
            for c in 0..<cells {
                let edge = y == 2 || y == 13
                let inside = (3...12).contains(y)
                if edge { r += "ddd" }
                else if inside { r += c < lit ? "ddd" : "dwd" }
                else { r += "..." }
                r += c < cells - 1 ? "." : ""
            }
            r += "."
            rows.append(r)
        }
        return rows
    }
}
