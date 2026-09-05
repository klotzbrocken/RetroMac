import Foundation

/// The catalogue's value types. Deliberately free of AppKit: a scenario is data, and keeping the
/// import out is what stops it from slowly growing drawing code.

/// The character grid a screen is rendered on. Both are real VGA modes.
enum CrashGrid: Equatable {
    /// 720x400, 80x25, 9x16 cells — what Windows 95, 98 and Me put their blue screen in.
    case vga80x25
    /// 640x480, 80x30, 8x16 cells — the NT family from Windows 2000 on. XP's Stop screen needs
    /// far more than 25 rows, which is why it does not share the 9x grid.
    case vga80x30

    var columns: Int { self == .vga80x25 ? 80 : 80 }
    var rows: Int { self == .vga80x25 ? 25 : 30 }
    var cellWidth: Int { self == .vga80x25 ? 9 : 8 }
    var cellHeight: Int { 16 }
    var pixelWidth: Int { columns * cellWidth }
    var pixelHeight: Int { rows * cellHeight }
}

/// One line of a text-mode screen. Laid out top to bottom from the screen's first row.
enum ScreenLine: Equatable {
    case blank
    /// Left-aligned at the screen's left margin.
    case text(String)
    /// Centred across the full width.
    case centred(String)
    /// Centred, colours swapped — the grey "Windows" plaque at the top of the 9x screen.
    case inverted(String)
    /// A counter line that fills in while the stage runs: "Dumping physical memory to disk: 42".
    case counter(prefix: String)
}

/// Which typeface a text screen is set in. The IBM PC ones are a character ROM; Mac OS X's
/// panic console was a normal monospaced font on a black screen.
enum ScreenFont: Equatable { case vga, mono }

/// Two colours, because that is all a text-mode screen ever had.
enum ScreenPalette: Equatable {
    /// Windows 95/98/Me: silver on #0000A8.
    case win9x
    /// Windows 2000 through 7: white on #000080.
    case nt
    /// The Mac OS X panic console: white on black.
    case console
}

struct TextScreen: Equatable {
    let grid: CrashGrid
    /// Row the first line sits on, counted from the top of the grid.
    let topRow: Int
    /// Column the left margin starts at.
    let leftColumn: Int
    let lines: [ScreenLine]
    var font: ScreenFont = .vga
    var palette: ScreenPalette = .win9x
}

/// The Macintosh system-error alert: a bomb, a sentence, and a button that never helped.
struct MacAlert: Equatable {
    enum Style: Equatable {
        /// System 6: one bit, Chicago, a double-ruled border.
        case system6
        /// Mac OS 9: Platinum grey with a bevel.
        case platinum
    }
    let style: Style
    let title: String?
    let lines: [String]
    let buttons: [String]
    /// A bomb for a system error, the caution triangle for "the application unexpectedly quit":
    /// the machine was fine, one program was not, and the alert said so with a milder icon
    /// rather than with none. Leaving it out looked like the artwork had failed to load, because
    /// the layout reserves the gutter either way.
    var showsBomb: Bool = true
    /// "ID = 03" in the corner, the number nobody could look up.
    let idCode: String?
    let restartButton: String?
}

/// The grey curtain: "You need to restart your computer", in four languages, over whatever was
/// on screen.
struct KernelPanic: Equatable {
    let messages: [String]
}

/// A windowed error. Most failures were one of these rather than a blue screen — the 9x
/// "Illegal Operation" and XP's "has encountered a problem" were what people actually saw.
struct ErrorDialog: Equatable {
    /// Which era paints it. The words differ, but so does the furniture: a 9x dialog has a
    /// square navy caption and a hard bevel, XP a rounded Luna caption.
    enum Style: Equatable { case win9x, winXP, win7, aqua }

    /// The badge left of the message. Period artwork where the era had a recognisable one.
    enum Icon: Equatable {
        case none
        /// The pixel-art red circle with a white cross, Windows 95 through Me.
        case error9x
        /// The same idea, smoothly drawn, Windows XP.
        case errorXP
        /// The yellow triangle an antivirus used, which was never the same as an error.
        case warning
    }

    /// Where the buttons sit. A 9x error dialog stacked them down the right-hand side; most
    /// other dialogs put them in a row along the bottom.
    enum ButtonLayout: Equatable { case bottomRight, rightColumn }

    let title: String
    let body: [String]
    let buttons: [String]
    /// Which button restarts rather than returns. nil = every button just closes.
    let restartButton: String?
    var style: Style = .win9x
    var icon: Icon = .error9x
    var buttonLayout: ButtonLayout = .bottomRight
    /// The dump behind "Details >>". Empty = the dialog has nothing to unfold.
    var details: [String] = []
    /// A monospaced report shown in a sunken well, always visible (the antivirus dialogs).
    var report: [String] = []
    /// The status strip along the bottom, left and right halves.
    var statusBar: (String, String)? = nil
    /// Closing this dialog sometimes takes the whole machine with it. A program that had just
    /// performed an illegal operation frequently did.
    var escalatesToBlueScreen: Bool = false

    static func == (a: ErrorDialog, b: ErrorDialog) -> Bool {
        a.title == b.title && a.body == b.body && a.buttons == b.buttons
            && a.restartButton == b.restartButton && a.style == b.style && a.icon == b.icon
            && a.buttonLayout == b.buttonLayout && a.details == b.details && a.report == b.report
            && a.statusBar?.0 == b.statusBar?.0 && a.statusBar?.1 == b.statusBar?.1
            && a.escalatesToBlueScreen == b.escalatesToBlueScreen
    }
}

enum CrashSurface: Equatable {
    case textScreen(TextScreen)
    case dialog(ErrorDialog)
    case macAlert(MacAlert)
    case kernelPanic(KernelPanic)
    /// The shell dies and comes back: the taskbar and the desktop icons vanish, the machine sits
    /// there for a few seconds, and then they return. No overlay at all — the most common Windows
    /// failure of the era was not a blue screen, it was Explorer restarting under you.
    case shellRestart
    /// Black, for the beat between "Restart" and the boot screen.
    case black
}

/// What the user may do to get out of a stage, and what that does.
struct CrashRecovery: OptionSet {
    let rawValue: Int
    /// Any key returns to the desktop — the 9x "Press any key to continue".
    static let anyKey       = CrashRecovery(rawValue: 1 << 0)
    /// Return returns to the desktop.
    static let enterKey     = CrashRecovery(rawValue: 1 << 1)
    /// Ctrl+Alt+Delete reboots. The one gesture everyone in this era knew by heart.
    static let ctrlAltDelete = CrashRecovery(rawValue: 1 << 2)
    /// There is no way back: any key power-cycles the machine. A Stop error did not return to
    /// Windows when you pressed something, and neither did a kernel panic — you restarted, which
    /// is why this is a separate option rather than `anyKey`.
    static let restartsOnAnyKey = CrashRecovery(rawValue: 1 << 3)
    /// The stage holds for its own time and moves on by itself.
    static let none: CrashRecovery = []
}

struct CrashStage: Equatable {
    let surface: CrashSurface
    /// Seconds to hold before moving to the next stage. Ignored when `recovery` is non-empty:
    /// then the stage waits for the user.
    let hold: TimeInterval
    let recovery: CrashRecovery

    init(_ surface: CrashSurface, hold: TimeInterval = 0, recovery: CrashRecovery = .none) {
        self.surface = surface
        self.hold = hold
        self.recovery = recovery
    }

    static func == (a: CrashStage, b: CrashStage) -> Bool {
        a.surface == b.surface && a.hold == b.hold && a.recovery.rawValue == b.recovery.rawValue
    }
}

/// The coarse shape of a failure, as a person sees it. Four different blue screens are four
/// entries in the catalogue and one experience, which is why "it is always the same crash" can be
/// true and the picker still correct.
enum CrashKind: Equatable { case fullScreen, window, shell }

struct CrashScenario: Identifiable, Equatable {
    let id: String
    /// Shown in the settings list and the Party-mode picker.
    let title: String
    let eras: Set<CrashEra>
    /// Relative likelihood within an era. The screens people actually remember are heavier.
    let weight: Int
    /// How long the desktop sits there looking frozen before the failure appears.
    let freezeHold: TimeInterval
    let stages: [CrashStage]

    /// What this looks like from across the room.
    var kind: CrashKind {
        switch stages.first?.surface {
        case .dialog, .macAlert: return .window
        case .shellRestart:      return .shell
        default:                 return .fullScreen
        }
    }

    static func == (a: CrashScenario, b: CrashScenario) -> Bool { a.id == b.id }
}
