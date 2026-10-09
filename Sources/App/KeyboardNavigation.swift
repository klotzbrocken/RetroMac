import AppKit
import Carbon.HIToolbox

/// Keyboard access to the theme surfaces without VoiceOver: the arrow keys, Return and Esc
/// in RetroMac's drawn menus, the launcher shortcut that opens the theme's main menu, and the
/// focus shortcut that walks the dock or taskbar.

/// The keys a menu or the dock focus listens to.
enum NavKey: CaseIterable {
    case up, down, left, right, enter, escape

    /// The virtual key codes that mean this key (Return and the keypad's Enter both choose).
    var keyCodes: [Int] {
        switch self {
        case .up: [kVK_UpArrow]
        case .down: [kVK_DownArrow]
        case .left: [kVK_LeftArrow]
        case .right: [kVK_RightArrow]
        case .enter: [kVK_Return, kVK_ANSI_KeypadEnter]
        case .escape: [kVK_Escape]
        }
    }

    init?(keyCode: Int) {
        guard let k = Self.allCases.first(where: { $0.keyCodes.contains(keyCode) }) else { return nil }
        self = k
    }
}

/// While a menu, a subpanel or the dock focus is open, its keys are held as hotkeys and let go
/// on close. RetroMac stays in the background (macOS no longer lets it take the keyboard from
/// the app in front), and a hotkey needs no permission; an event tap would need Input Monitoring.
///
/// Holders stack: the last one to hold gets the keys, and when it lets go the one below gets
/// them back (a Start menu opened from the focused taskbar hands the arrows back on close).
enum HeldKeys {
    private struct Holder { let owner: String; let keys: Set<NavKey>; let handler: (NavKey) -> Void }
    private static var holders: [Holder] = []
    private static var refs: [EventHotKeyRef] = []
    private static var handler: EventHandlerRef?
    private static let signature = OSType(0x524B4559)   // "RKEY"; AppDelegate's hotkeys are "RMAC"

    static func hold(_ owner: String, keys: Set<NavKey> = Set(NavKey.allCases), _ handler: @escaping (NavKey) -> Void) {
        holders.removeAll { $0.owner == owner }
        holders.append(Holder(owner: owner, keys: keys, handler: handler))
        register()
    }

    static func release(_ owner: String) {
        guard holders.contains(where: { $0.owner == owner }) else { return }
        holders.removeAll { $0.owner == owner }
        register()
    }

    /// Whether any key is held right now, for the leak check (PERF-06).
    static var isHeld: Bool { !refs.isEmpty }

    private static func register() {
        installHandler()
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        guard let top = holders.last else { return }
        for key in top.keys {
            for code in key.keyCodes {
                var ref: EventHotKeyRef?
                if RegisterEventHotKey(UInt32(code), 0, EventHotKeyID(signature: signature, id: UInt32(code)),
                                       GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                    refs.append(ref)
                }
            }
        }
    }

    private static func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == HeldKeys.signature, let key = NavKey(keyCode: Int(id.id)) else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { HeldKeys.holders.last?.handler(key) }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}

// MARK: - Menus

/// One row of a drawn menu, as the keyboard sees it.
struct KeyMenuRow {
    var label: String
    /// Separators, labels and dimmed rows are passed over.
    var selectable = true
    /// Right and Return open it rather than choose it.
    var submenu = false
}

/// One open level of a drawn menu (a menu, a cascade, a flyout). Each engine keeps its own
/// highlight, which the mouse moves too; the keyboard reads it fresh on every key.
protocol KeyMenuLevel: AnyObject {
    var keyRows: [KeyMenuRow] { get }
    var keyHighlight: Int? { get }
    /// Highlight row `i` as the mouse would, closing anything opened deeper.
    func setKeyHighlight(_ i: Int)
    /// What a click on row `i` does: open its submenu, or choose it.
    func activateKeyRow(_ i: Int)
    /// Left on the first open level: for a menu whose submenu took its parent's place (Win 3.1).
    func keyBack()
}

extension KeyMenuLevel {
    func keyBack() {}
}

/// The arrow keys in a drawn menu: Up/Down move the highlight, Right/Return open a submenu,
/// Left closes it, Return chooses, Esc closes the menu. Kept free of AppKit so it can be tested.
enum MenuKeyNavigator {
    /// The next row that can be highlighted from `from`, `delta` rows on, wrapping round; from
    /// nothing, Down starts at the top and Up at the bottom.
    static func step(_ rows: [KeyMenuRow], from: Int?, by delta: Int) -> Int? {
        let n = rows.count
        guard rows.contains(where: \.selectable) else { return nil }
        var i = from ?? (delta > 0 ? -1 : n)
        for _ in 0..<n {
            i = ((i + delta) % n + n) % n
            if rows[i].selectable { return i }
        }
        return nil
    }

    /// What VoiceOver says for a highlighted row.
    static func describe(_ row: KeyMenuRow) -> String { row.submenu ? row.label + ", submenu" : row.label }

    /// Handles `key` on the open `levels` (outermost first, re-read after each step) and returns
    /// what to announce, if anything. The keyboard works on the deepest level with a highlight;
    /// `close(n)` closes level `n` and every one deeper (the whole menu for 0).
    @discardableResult
    static func handle(_ key: NavKey, levels: () -> [KeyMenuLevel], close: (Int) -> Void) -> String? {
        let open = levels()
        guard !open.isEmpty else { return nil }
        let focus = open.lastIndex { $0.keyHighlight != nil } ?? 0
        let level = open[focus]
        let rows = level.keyRows
        func highlight(_ l: KeyMenuLevel, _ i: Int?) -> String? {
            guard let i else { return nil }
            l.setKeyHighlight(i)
            return describe(l.keyRows[i])
        }
        switch key {
        case .up, .down:
            return highlight(level, step(rows, from: level.keyHighlight, by: key == .up ? -1 : 1))
        case .right, .enter:
            guard let i = level.keyHighlight, rows.indices.contains(i), rows[i].selectable else { return nil }
            if !rows[i].submenu && key == .right { return nil }
            level.activateKeyRow(i)
            let now = levels()
            // Levels are compared by place, not identity: an engine may hand out fresh ones.
            if rows[i].submenu, now.count > focus + 1 {
                let child = now[focus + 1]
                return highlight(child, step(child.keyRows, from: nil, by: 1))
            }
            // A row that changed the menu in place (Windows 7's All Programs) and left a highlight.
            if now.count > focus, let h = now[focus].keyHighlight, now[focus].keyRows.indices.contains(h) {
                return describe(now[focus].keyRows[h])
            }
            return nil
        case .left:
            if focus > 0 {
                close(focus)
                let parent = open[focus - 1]
                return parent.keyHighlight.flatMap { parent.keyRows.indices.contains($0) ? describe(parent.keyRows[$0]) : nil }
            }
            level.keyBack()
            // Where that left the keyboard (Win 3.1: back on the parent row).
            let now = levels()
            guard let at = now.lastIndex(where: { $0.keyHighlight != nil }), let h = now[at].keyHighlight,
                  now[at].keyRows.indices.contains(h) else { return nil }
            return describe(now[at].keyRows[h])
        case .escape:
            close(0)
            return nil
        }
    }
}

/// Wires a menu engine to the held keys: call `attach` when the menu opens and `detach` when it
/// closes. Opened from the keyboard (the launcher shortcut), the first row starts highlighted.
enum MenuKeyboard {
    static func attach(_ owner: String, highlightFirst: Bool = false, levels: @escaping () -> [KeyMenuLevel], close: @escaping (Int) -> Void) {
        HeldKeys.hold(owner) { key in
            if let say = MenuKeyNavigator.handle(key, levels: levels, close: close) { announce(say) }
        }
        if highlightFirst || openingFromKeyboard { highlightTop(levels()) }
    }

    static func detach(_ owner: String) { HeldKeys.release(owner) }

    /// Set by the launcher shortcut around the call that opens the menu.
    static var openingFromKeyboard = false

    static func highlightTop(_ levels: [KeyMenuLevel]) {
        guard let root = levels.first, root.keyHighlight == nil,
              let i = MenuKeyNavigator.step(root.keyRows, from: nil, by: 1) else { return }
        root.setKeyHighlight(i)
        announce(MenuKeyNavigator.describe(root.keyRows[i]))
    }

    /// VoiceOver speaks the highlighted item. RetroMac is not the app in front, so VoiceOver's
    /// cursor does not follow its focus; an announcement is what reaches the listener.
    static func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

// MARK: - Dock focus

/// The focus shortcut: walks the controls of the theme's dock, taskbar or panel with the arrow
/// keys — the same named controls VoiceOver presses — under a focus ring. Return presses the
/// focused one and leaves, Esc leaves; the shortcut again moves on to the next bar.
final class KeyboardFocus {
    static let shared = KeyboardFocus()
    private init() {}

    /// The theme windows that hold a bar of controls, in the order the shortcut visits them.
    static let barTitles = ["Dock", "Taskbar", "Deskbar", "Front Panel", "Shelf", "Control Strip", "Program Manager", "Desktop"]

    private var elements: [NSAccessibilityProtocol] = []
    private var index = 0
    private var barWindow: NSWindow?
    private var ring: NSPanel?
    var isActive: Bool { barWindow != nil }

    /// Into the first bar, or on to the next one when already in one; past the last, out.
    func toggle() {
        let bars = Self.bars()
        let next = barWindow.flatMap { w in bars.firstIndex { $0 === w } }.map { $0 + 1 } ?? 0
        guard next < bars.count else { end(); return }
        begin(bars[next])
    }

    /// The visible theme windows with controls, in `barTitles` order.
    static func bars() -> [NSWindow] {
        let visible = NSApp.windows.filter { $0.isVisible && !RetroMacApplication.isDecorative($0) }
        return barTitles.flatMap { t in visible.filter { $0.title == t } }.filter { !controls(in: $0).isEmpty }
    }

    func begin(_ window: NSWindow) {
        let found = Self.controls(in: window)
        guard !found.isEmpty else { return }
        barWindow = window
        elements = found
        index = 0
        HeldKeys.hold("focus") { [weak self] in self?.handle($0) }
        MenuKeyboard.announce(window.title)
        show()
    }

    func end() {
        barWindow = nil
        elements = []
        ring?.orderOut(nil); ring = nil
        HeldKeys.release("focus")
    }

    private func handle(_ key: NavKey) {
        guard let window = barWindow, window.isVisible else { end(); return }
        switch DockFocusNavigator.action(for: key, index: index, count: elements.count) {
        case .move(let i):
            index = i
            show()
        case .press:
            let el = elements[index]
            end()   // first: what the press opens (a Start menu) takes the keys from here
            MenuKeyboard.openingFromKeyboard = true   // and starts with its first row lit
            defer { MenuKeyboard.openingFromKeyboard = false }
            _ = el.accessibilityPerformPress()
        case .leave:
            end()
        case .none:
            break
        }
    }

    private func show() {
        guard elements.indices.contains(index) else { return }
        let el = elements[index]
        drawRing(around: el.accessibilityFrame())
        NSAccessibility.post(element: el, notification: .focusedUIElementChanged)
        MenuKeyboard.announce(el.accessibilityLabel() ?? el.accessibilityTitle() ?? "Item")
    }

    private func drawRing(around frame: NSRect) {
        let r = frame.insetBy(dx: -3, dy: -3)
        let p = ring ?? {
            let p = NSPanel(contentRect: r, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
            p.ignoresMouseEvents = true   // and so left out of VoiceOver's windows (RetroMacApplication)
            p.level = .popUpMenu
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.contentView = FocusRingView()
            return p
        }()
        ring = p
        p.setFrame(r, display: true)
        p.orderFrontRegardless()
    }

    /// The pressable controls under a window, in reading order: a horizontal bar left to right,
    /// a vertical one top to bottom, anything else as its views list them.
    static func controls(in window: NSWindow) -> [NSAccessibilityProtocol] {
        var out: [NSAccessibilityProtocol] = []
        func walk(_ el: Any, depth: Int) {
            guard depth < 12, let el = el as? NSAccessibilityProtocol else { return }
            if let v = el as? NSView, v.isHidden { return }
            let role = el.accessibilityRole()
            if el.isAccessibilityElement(), role == .button || role == .menuButton || role == .menuItem {
                let f = el.accessibilityFrame()
                if f.width > 1, f.height > 1 { out.append(el) }
                return
            }
            for child in el.accessibilityChildren() ?? [] { walk(child, depth: depth + 1) }
        }
        if let content = window.contentView { walk(content, depth: 0) }
        let size = window.frame.size
        if size.width > size.height * 2 {
            out.sort { $0.accessibilityFrame().minX < $1.accessibilityFrame().minX }
        } else if size.height > size.width * 2 {
            out.sort { $0.accessibilityFrame().maxY > $1.accessibilityFrame().maxY }
        }
        return out
    }
}

/// The dock focus's keys, kept free of AppKit for the tests: either arrow pair moves (a dock can
/// stand vertically), wrapping round; Return presses; Esc leaves.
enum DockFocusNavigator {
    enum Action: Equatable { case move(Int), press, leave, none }

    static func action(for key: NavKey, index: Int, count: Int) -> Action {
        guard count > 0 else { return .leave }
        switch key {
        case .left, .up: return .move((index - 1 + count) % count)
        case .right, .down: return .move((index + 1) % count)
        case .enter: return .press
        case .escape: return .leave
        }
    }
}

private final class FocusRingView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
        path.lineWidth = 3
        NSColor.keyboardFocusIndicatorColor.withAlphaComponent(1).setStroke()
        path.stroke()
    }
}

// MARK: - Launcher

/// The launcher shortcut: the theme's main menu, opened as its button would open it, with the
/// first row highlighted so the arrow keys go straight on.
enum ThemeLauncher {
    static func open() {
        KeyboardFocus.shared.end()
        guard ThemeManager.shared.activeTheme != nil else { NSSound.beep(); return }
        MenuKeyboard.openingFromKeyboard = true
        defer { MenuKeyboard.openingFromKeyboard = false }
        if DockController.shared.openStartMenuFromKeyboard() { return }
        if BeOSDeskbarController.shared.openBeMenu() { return }
        if PhotonDesktopController.shared.openLaunchMenu() { return }
        if SGIDesktopController.shared.openToolchest() { return }
        if CDEDesktop.shared.openWorkspaceMenu() { return }
        if NextMenuController.shared.focusFromKeyboard() { return }
        if AppleMenuController.shared.popUpFromKeyboard() { return }
        // Windows 3.1: Program Manager is the launcher; its program items take the focus.
        if let pm = NSApp.windows.first(where: { $0.isVisible && $0.title == "Program Manager" }) {
            KeyboardFocus.shared.begin(pm); return
        }
        NSSound.beep()
    }
}
