import AppKit

/// The Control Strip of System 7.5 on a colour Mac, pixel for pixel: taken from a screenshot of
/// the real strip (a 2× capture, halved and every colour snapped to the Mac's 256-colour
/// table). Every part is the original's own art, the black line after it included, 24 rows
/// from the top rule to the bottom one: the close box, the scroll arrows, five modules —
/// AppleTalk Switch, File Sharing, Monitor Bit Depth, Monitor Resolution, Sound Volume, each
/// a 30 px raised button with its picture and triangle — and the tab with its grip.
///
/// Colours: `#` black, `.` #AAAAAA, `a` #666666, `b` #CCCCCC (the face), `c` #888888, `d`
/// white, `e` #6666CC, `f` #555555, `g` #9999FF, `h` #CCCCFF, `i` #222222, `j` #3333CC,
/// `k` #FFFF33, `l` #CC3300, `m` #00CC33, `n` #DDDDDD, `o` #FF6633, `p` #BBBBBB, `q` #777777;
/// a space is not drawn (the desktop beside the tab's chamfer).
enum System7Strip {

    static let ink: [Character: NSColor] = [
        "#": Mac256.black, ".": Mac256.greyAA, "a": Mac256.colour(0x666666), "b": Mac256.colour(0xCCCCCC),
        "c": Mac256.grey88, "d": Mac256.white, "e": Mac256.colour(0x6666CC), "f": Mac256.grey55,
        "g": Mac256.colour(0x9999FF), "h": Mac256.colour(0xCCCCFF), "i": Mac256.colour(0x222222),
        "j": Mac256.colour(0x3333CC), "k": Mac256.colour(0xFFFF33), "l": Mac256.colour(0xCC3300),
        "m": Mac256.colour(0x00CC33), "n": Mac256.greyDD, "o": Mac256.colour(0xFF6633),
        "p": Mac256.greyBB, "q": Mac256.colour(0x777777),
    ]

    /// Rows top-down from `origin` (the view is flipped); `flipped` mirrors left to right, for
    /// a strip on the right edge.
    static func draw(_ rows: [String], at origin: NSPoint, flipped: Bool = false) {
        let width = rows.map(\.count).max() ?? 0
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let c = ink[ch] else { continue }
                c.setFill()
                let px = flipped ? width - 1 - x : x
                NSRect(x: origin.x + CGFloat(px), y: origin.y + CGFloat(y), width: 1, height: 1).fill()
            }
        }
    }

    static let height = 24
    /// A module's button, its black line included.
    static let cellWidth = 31
    /// The close box's and an arrow's piece, the black line included.
    static let endWidth = 14
    static var tabWidth: Int { tab[0].count }

    /// The picture for a module, in its state: File Sharing crossed out while it is off, the
    /// speaker's waves for the volume. Nil for a module the colour strip did not have.
    static func cell(for module: ControlStripModule) -> [String]? {
        switch module.id {
        case "network", "appletalk": return appleTalk
        case "sharing": return (module as? SharingModule)?.isOn == true ? fileSharingOn : fileSharing
        case "colours": return colourDepth
        case "resolution": return resolution
        case "volume": return sound(level: (module as? VolumeModule)?.level ?? 2)
        default: return nil
        }
    }

    /// A plain button for a module without its own picture: the AppleTalk button with its
    /// picture cleared, the module draws on it.
    static let blankCell: [String] = appleTalk.enumerated().map { y, row in
        guard (4...19).contains(y) else { return row }
        return String(row.enumerated().map { x, c in (3...26).contains(x) ? "b" : c })
    }

    /// The speaker with no, one or both waves.
    static func sound(level: Int) -> [String] {
        let inner: [(Int, Int)] = [(14, 8), (14, 9), (15, 10), (15, 11), (15, 12), (15, 13), (14, 14), (14, 15)]
        let outer: [(Int, Int)] = [(15, 6), (16, 7), (16, 8), (17, 9), (17, 10), (17, 11), (17, 12), (17, 13), (17, 14),
                                   (16, 15), (16, 16), (15, 17)]
        var rows = soundArt.map { Array($0) }
        if level < 1 { for (x, y) in inner { rows[y][x] = "b" } }
        if level < 2 { for (x, y) in outer { rows[y][x] = "b" } }
        return rows.map { String($0) }
    }

    /// A scroll arrow's piece: sunk in and grey when there is nothing to scroll to, as the
    /// original showed it; raised with a black arrow when there is.
    static func arrow(pointsLeft: Bool, enabled: Bool) -> [String] {
        let art = pointsLeft ? leftArrow : rightArrow
        guard enabled else { return art }
        let swap: [Character: Character] = ["c": "d", "d": "c", "f": "#", "n": "d"]
        return art.map { row in
            String(row.enumerated().map { x, ch in x == row.count - 1 ? ch : (swap[ch] ?? ch) })
        }
    }

    /// The close box at the left end.
    static let closeBox: [String] = [
        "##############",
        "bbbbbbbbbbbbb#",
        "bddddddddddbc#",
        "bdbbbbbbbbb.c#",
        "bdbbbbbbbbb.c#",
        "bdbbbbbbbbb.c#",
        "bdbbbbbbbbb.c#",
        "bdbbbbbbbbb.c#",
        "bdffffffffb.c#",
        "bdfhhhhhhhb.c#",
        "bdfhccccfdb.c#",
        "bdfhccccfdb.c#",
        "bdfhccccfdb.c#",
        "bdfhccccfdb.c#",
        "bdfhfffffdb.c#",
        "bdfhddddddb.c#",
        "bdbbbbbbbbb.c#",
        "bdbbbbbbbbb.c#",
        "bdbbbbbbbbb.c#",
        "bdbbbbbbbbb.c#",
        "bdbbbbbbbbb.c#",
        "#b..........c#",
        "##ccccccccccc#",
        "##############",
    ]
    /// The left scroll arrow, nothing to scroll to.
    static let leftArrow: [String] = [
        "##############",
        "ccccccccccccb#",
        "cbbbbbbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "cbbbbbfbbbbbd#",
        "cbbbbffbbbbbd#",
        "cbbbfnffffbbd#",
        "cbbfnnnnnfbbd#",
        "cbfnnnnnnfbbd#",
        "cbfnnnnnnfbbd#",
        "cbbfnnnnnfbbd#",
        "cbbbfnffffbbd#",
        "cbbbbffbbbbbd#",
        "cbbbbbfbbbbbd#",
        "cbbbbbbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "bdddddddddddd#",
        "##############",
    ]
    /// The right scroll arrow, nothing to scroll to.
    static let rightArrow: [String] = [
        "##############",
        "ccccccccccccb#",
        "cbbbbbbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "cbbbbfbbbbbbd#",
        "cbbbbffbbbbbd#",
        "cbffffnfbbbbd#",
        "cbfnnnnnfbbbd#",
        "cbfnnnnnnfbbd#",
        "cbfnnnnnnfbbd#",
        "cbfnnnnnfbbbd#",
        "cbffffnfbbbbd#",
        "cbbbbffbbbbbd#",
        "cbbbbfbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "cbbbbbbbbbbbd#",
        "bdddddddddddd#",
        "##############",
    ]
    /// AppleTalk Switch: the compact Mac, its lavender screen.
    static let appleTalk: [String] = [
        "###############################",
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#",
        "bdddddddddddddddddddddddddddbc#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bdbbb#########bbbbbbbbbbbbbb.c#",
        "bdbb#bbbbbbbbb#bbbbbbbbbbbbb.c#",
        "bdbb#bfffffffb#bbbbbbbbbbbbb.c#",
        "bdbb#bfhhhhhdb#bbbbbbbbbbbbb.c#",
        "bdbb#bfhhhhhdb#bbbbbbb#bbbbb.c#",
        "bdbb#bfhhhhhdb#bbbbbbb##bbbb.c#",
        "bdbb#bfhhhhhdb#bbbbbbb###bbb.c#",
        "bdbb#bqddddddb#bbbbbbb####bb.c#",
        "bdbb#bbbbbbbbb#bbbbbbb####bb.c#",
        "bdbb#bmbbbbbbb#bbbbbbb###bbb.c#",
        "bdbb#blbbb###b#bbbbbbb##bbbb.c#",
        "bdbb#bbbbbbbbb#bbbbbbb#bbbbb.c#",
        "bdbbbiiiiii###bbbbbbbbbbbbbb.c#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bb...........................c#",
        "bccccccccccccccccccccccccccccc#",
        "###############################",
    ]
    /// File Sharing, off: the folder crossed out in red.
    static let fileSharing: [String] = [
        "###############################",
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#",
        "bdddddddddddddddddddddddddddbc#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bd.bb##bbbbbbbbbbbbbbbbbbbbb.c#",
        "bdcb##e##bbbbbbbbbbbbbbbbbbb.c#",
        "bdfb#gffe##b##bbbbbbbbbbbbbb.c#",
        "bdib#hhhffeegg#bbbbbbbbbbbbb.c#",
        "bd#f###hhgffegg#bbbbbb#bbbbb.c#",
        "bdbloc.#hhhgfol#bbbbbb##bbbb.c#",
        "bd#flo#hhhhhole#bbbbbb###bbb.c#",
        "bd#b#lohhhhol#e#bbbbbb####bb.c#",
        "bd#b#elohhole#e#bbbbbb####bb.c#",
        "bdib#helooleg#e#bbbbbb###bbb.c#",
        "bdib#egellehg#e#bbbbbb##bbbb.c#",
        "bdfbb#eollohg#e#ibbbbb#bbbbb.c#",
        "bdfbbboleelog#e#iibbbbbbbbbb.c#",
        "bdqbboleb##lo#e#iibbbbbbbbbb.c#",
        "bdcbolebbbb#lo#iibbbbbbbbbbb.c#",
        "bd.olebbbbbbelobbbbbbbbbbbbb.c#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bb...........................c#",
        "bccccccccccccccccccccccccccccc#",
        "###############################",
    ]
    /// File Sharing, on: the folder alone.
    static let fileSharingOn: [String] = [
        "###############################",
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#",
        "bdddddddddddddddddddddddddddbc#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bd.bb##bbbbbbbbbbbbbbbbbbbbb.c#",
        "bdcb##e##bbbbbbbbbbbbbbbbbbb.c#",
        "bdfb#gffe##b##bbbbbbbbbbbbbb.c#",
        "bdib#hhhffeegg#bbbbbbbbbbbbb.c#",
        "bd#f###hhgffegg#bbbbbb#bbbbb.c#",
        "bd#b#hhhhhhhheg#bbbbbb##bbbb.c#",
        "bd#f#hhhhhhhh#e#bbbbbb###bbb.c#",
        "bd#b#hhhhhhhh#e#bbbbbb####bb.c#",
        "bd#b#hhhhhhhh#e#bbbbbb####bb.c#",
        "bdib#hhhhhhhg#e#bbbbbb###bbb.c#",
        "bdib#hhhhhhhg#e#bbbbbb##bbbb.c#",
        "bdfb##hhhhhhg#e#ibbbbb#bbbbb.c#",
        "bdfbbb##hhhhg#e#iibbbbbbbbbb.c#",
        "bdqbbbbb##hhg#e#iibbbbbbbbbb.c#",
        "bdcbbbbbbbb#####ibbbbbbbbbbb.c#",
        "bd.bbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bb...........................c#",
        "bccccccccccccccccccccccccccccc#",
        "###############################",
    ]
    /// Monitor Bit Depth: the screen with its four colour bars.
    static let colourDepth: [String] = [
        "###############################",
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#",
        "bdddddddddddddddddddddddddddbc#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bdb##############bbbbbbbbbbb.c#",
        "bd#..............#bbbbbbbbbb.c#",
        "bd#.###########d.#bbbbbbbbbb.c#",
        "bd#.#jjkkklllmmd.#bbbb#bbbbb.c#",
        "bd#.#jjkkklllmmd.#bbbb##bbbb.c#",
        "bd#.#jjkkklllmmd.#bbbb###bbb.c#",
        "bd#.#jjkkklllmmd.#bbbb####bb.c#",
        "bd#.#jjkkklllmmd.#bbbb####bb.c#",
        "bd#.#jjkkklllmmd.#bbbb###bbb.c#",
        "bd#.#jjkkklllmmd.#bbbb##bbbb.c#",
        "bd#.#jjkkklllmmd.#bbbb#bbbbb.c#",
        "bd#dlddddddddddd.#bbbbbbbbbb.c#",
        "bd#ffffffffffffff#bbbbbbbbbb.c#",
        "bd#p............p#bbbbbbbbbb.c#",
        "bdb##############bbbbbbbbbbb.c#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bb...........................c#",
        "bccccccccccccccccccccccccccccc#",
        "###############################",
    ]
    /// Monitor Resolution: the screen with its checkerboard.
    static let resolution: [String] = [
        "###############################",
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#",
        "bdddddddddddddddddddddddddddbc#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bdb##############bbbbbbbbbbb.c#",
        "bd#..............#bbbbbbbbbb.c#",
        "bd#.###########d.#bbbbbbbbbb.c#",
        "bd#.#ffddffddffd.#bbbb#bbbbb.c#",
        "bd#.#ffddffddffd.#bbbb##bbbb.c#",
        "bd#.#ddffddffddd.#bbbb###bbb.c#",
        "bd#.#ddffddffddd.#bbbb####bb.c#",
        "bd#.#ffddffddffd.#bbbb####bb.c#",
        "bd#.#ffddffddffd.#bbbb###bbb.c#",
        "bd#.#ddffddffddd.#bbbb##bbbb.c#",
        "bd#.#ddffddffddd.#bbbb#bbbbb.c#",
        "bd#dlddddddddddd.#bbbbbbbbbb.c#",
        "bd#ffffffffffffff#bbbbbbbbbb.c#",
        "bd#p............p#bbbbbbbbbb.c#",
        "bdb##############bbbbbbbbbbb.c#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bb...........................c#",
        "bccccccccccccccccccccccccccccc#",
        "###############################",
    ]
    /// Sound Volume: the lavender speaker and its two waves.
    static let soundArt: [String] = [
        "###############################",
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#",
        "bdddddddddddddddddddddddddddbc#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bdbbbbbbbbb#bbbbbbbbbbbbbbbb.c#",
        "bdbbbbbbbb##bbbbbbbbbbbbbbbb.c#",
        "bdbbbbbbb#e#bbb#bbbbbbbbbbbb.c#",
        "bdbbbbbb#eg#bbbb#bbbbbbbbbbb.c#",
        "bdbbbbb#egh#bb#b#bbbbb#bbbbb.c#",
        "bd#####eghd#bb#bb#bbbb##bbbb.c#",
        "bd#ggggpddh#bbb#b#bbbb###bbb.c#",
        "bd#ddddddhh#bbb#b#bbbb####bb.c#",
        "bd#ggggeggg#bbb#b#bbbb####bb.c#",
        "bd#eeeeeggg#bbb#b#bbbb###bbb.c#",
        "bd#####eegg#bb#bb#bbbb##bbbb.c#",
        "bdbbbbb#eeg#bb#b#bbbbb#bbbbb.c#",
        "bdbbbbbb#ee#bbbb#bbbbbbbbbbb.c#",
        "bdbbbbbbb#e#bbb#bbbbbbbbbbbb.c#",
        "bdbbbbbbbb##bbbbbbbbbbbbbbbb.c#",
        "bdbbbbbbbbb#bbbbbbbbbbbbbbbb.c#",
        "bdbbbbbbbbbbbbbbbbbbbbbbbbbb.c#",
        "bb...........................c#",
        "bccccccccccccccccccccccccccccc#",
        "###############################",
    ]
    /// The tab at the right end, with its grip and handle; collapsed, all of the strip that shows.
    static let tab: [String] = [
        "#########         ",
        "#bbbbbbb##        ",
        "#bddddddd##       ",
        "#bdbbbbbbb##      ",
        "#bddbbbbbbb##     ",
        "#bdbfbbbbbbb##    ",
        "#bdbbbdbbbbbb##   ",
        "#bdbbbbfbb##bb##  ",
        "#bddbbbbbb#d#bb## ",
        "#bdbfbbbbb#dd#bc# ",
        "#bdbbbdbbb#dd#bc# ",
        "#bdbbbbfbb#dd#bc# ",
        "#bddbbbbbb#dd#bc# ",
        "#bdbfbbbbb#dd#bc# ",
        "#bdbbbdbbb#dd#bc# ",
        "#bdbbbbfbb#d#bb## ",
        "#bddbbbbbb##bb##  ",
        "#bdbfbbbbbbbb##   ",
        "#bdbbbbbbbbb##    ",
        "#bdbbbbbbbb##     ",
        "#bdbbbbbbb##      ",
        "#bccccccc##       ",
        "#cffffff##        ",
        "#########         ",
    ]
}
