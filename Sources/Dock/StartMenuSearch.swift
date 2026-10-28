import AppKit
import Carbon.HIToolbox

/// Start menu search (Windows Vista and 7): what is typed while the menu is open goes into its
/// search box, and the left pane shows what matches: the installed programs, a sum worked out
/// (`12*3`, Return copies the answer), or a web address to open.
enum StartMenuSearch {

    struct App { let name: String; let url: URL; let bundleID: String? }

    // MARK: - Programs

    private static var index: [App] = []
    private static var indexedAt = 0.0

    /// Every application in the usual places, looked up again at most once a minute.
    static func apps() -> [App] {
        let now = ProcessInfo.processInfo.systemUptime
        if !index.isEmpty, now - indexedAt < 60 { return index }
        let fm = FileManager.default
        var seen = Set<String>(), found: [App] = []
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications",
                     "/System/Applications/Utilities", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        for root in roots {
            for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where name.hasSuffix(".app") {
                let url = URL(fileURLWithPath: root).appendingPathComponent(name)
                let display = fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                guard seen.insert(display.lowercased()).inserted else { continue }
                found.append(App(name: display, url: url, bundleID: Bundle(url: url)?.bundleIdentifier))
            }
        }
        index = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        indexedAt = now
        return index
    }

    /// Names that start with the query first, then names with a word that does, then the rest
    /// that contain it; case and accents do not count.
    static func rank(_ names: [String], query: String) -> [Int] {
        let q = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !q.isEmpty else { return [] }
        var scored: [(Int, Int)] = []
        for (i, raw) in names.enumerated() {
            let n = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if n.hasPrefix(q) { scored.append((0, i)) }
            else if n.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "." }).contains(where: { $0.hasPrefix(q) }) { scored.append((1, i)) }
            else if n.contains(q) { scored.append((2, i)) }
        }
        return scored.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }.map(\.1)
    }

    // MARK: - Sums

    /// A sum of numbers with + - * / ×, ÷, parentheses and a decimal point or comma, worked out;
    /// nil for anything else, a lone number included. A parser of its own, never NSExpression,
    /// which throws an Objective-C exception (a crash) at the first odd character.
    static func calculate(_ text: String) -> Double? {
        let s = text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/").filter { !$0.isWhitespace }
        guard !s.isEmpty, s.contains(where: { "+-*/".contains($0) }), s.contains(where: \.isNumber) else { return nil }
        var p = Parser(chars: Array(s))
        guard let v = p.sum(), p.i == p.chars.count, v.isFinite else { return nil }
        return v
    }

    private struct Parser {
        let chars: [Character]
        var i = 0
        mutating func sum() -> Double? {
            guard var v = product() else { return nil }
            while i < chars.count, chars[i] == "+" || chars[i] == "-" {
                let op = chars[i]; i += 1
                guard let r = product() else { return nil }
                v = op == "+" ? v + r : v - r
            }
            return v
        }
        mutating func product() -> Double? {
            guard var v = factor() else { return nil }
            while i < chars.count, chars[i] == "*" || chars[i] == "/" {
                let op = chars[i]; i += 1
                guard let r = factor() else { return nil }
                v = op == "*" ? v * r : v / r
            }
            return v
        }
        mutating func factor() -> Double? {
            guard i < chars.count else { return nil }
            if chars[i] == "-" { i += 1; return factor().map { -$0 } }
            if chars[i] == "(" {
                i += 1
                guard let v = sum(), i < chars.count, chars[i] == ")" else { return nil }
                i += 1
                return v
            }
            let start = i
            while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
            return i > start ? Double(String(chars[start..<i])) : nil
        }
    }

    static func format(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 10
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    // MARK: - Web addresses

    /// `github.com`, `https://example.com/a`, `localhost:3000`: the address to open, `https://`
    /// added when it has no scheme (plain `http://` for localhost). Nil for words and sums.
    static func webAddress(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        let lower = t.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: t).flatMap { $0.host != nil ? $0 : nil }
        }
        if lower == "localhost" || lower.hasPrefix("localhost:") || lower.hasPrefix("localhost/") {
            return URL(string: "http://" + t)
        }
        let host = lower.split(separator: "/", maxSplits: 1).first.map(String.init) ?? lower
        let hostOnly = host.split(separator: ":").first.map(String.init) ?? host
        let labels = hostOnly.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }),
              let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter),
              hostOnly.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return URL(string: "https://" + t)
    }

    // MARK: - Results

    /// The left pane while searching: a sum first, then a web address, then the programs.
    static func results(for query: String, limit: Int) -> [StartMenuPanel.MenuItem] {
        typealias MI = StartMenuPanel.MenuItem
        var rows: [MI] = []
        if let v = calculate(query) {
            let answer = format(v)
            rows.append(MI(title: "= \(answer)", icon: ThemeManager.shared.icon(for: "com.apple.calculator", size: 20), action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(answer, forType: .string)
            }))
        }
        if let url = webAddress(query) {
            let browser = NSWorkspace.shared.urlForApplication(toOpen: url)
            rows.append(MI(title: "Open website \(url.host ?? query)",
                           icon: browser.map { NSWorkspace.shared.icon(forFile: $0.path) },
                           action: { NSWorkspace.shared.open(url) }))
        }
        let apps = apps()
        for i in rank(apps.map(\.name), query: query).prefix(max(0, limit - rows.count)) {
            let app = apps[i]
            let icon = app.bundleID.map { ThemeManager.shared.icon(for: $0, size: 20) } ?? NSWorkspace.shared.icon(forFile: app.url.path)
            rows.append(MI(title: app.name, icon: icon, action: {
                NSWorkspace.shared.openApplication(at: app.url, configuration: .init())
            }, bundleID: app.bundleID))
        }
        if rows.isEmpty { rows.append(MI(title: "No items match your search.")) }
        return rows
    }
}

/// While the search box listens, the keys that type are held as hotkeys and read through the
/// current keyboard layout. RetroMac stays in the background (macOS no longer lets it take the
/// keyboard from the app in front), and a hotkey needs no permission; the keys are let go when
/// the menu closes. Return, Esc and the arrows stay with `MenuKeyboard`.
final class StartMenuTyping {
    static let shared = StartMenuTyping()
    private static let signature: OSType = 0x53545950   // 'STYP'
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var onText: ((String) -> Void)?
    private var onDelete: (() -> Void)?

    /// The character keys of a Mac keyboard (ANSI and ISO), Space and the keypad.
    private static let keys: [Int] = Array(0...47).filter { $0 != kVK_Return && $0 != kVK_Tab }
        + [kVK_Space, kVK_ANSI_Grave] + [65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]

    var isAttached: Bool { !refs.isEmpty }

    func attach(onText: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        detach()
        self.onText = onText
        self.onDelete = onDelete
        installHandler()
        for code in Self.keys {
            for shift in [false, true] {
                register(code, shift: shift)
            }
        }
        register(kVK_Delete, shift: false)
    }

    func detach() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        onText = nil
        onDelete = nil
    }

    private func register(_ code: Int, shift: Bool) {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: UInt32(code) | (shift ? 0x100 : 0))
        if RegisterEventHotKey(UInt32(code), shift ? UInt32(shiftKey) : 0, id, GetApplicationEventTarget(), 0, &ref) == noErr,
           let ref { refs.append(ref) }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == StartMenuTyping.signature else { return OSStatus(eventNotHandledErr) }
            let code = Int(id.id & 0xFF), shift = id.id & 0x100 != 0
            DispatchQueue.main.async { StartMenuTyping.shared.pressed(code, shift: shift) }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    private func pressed(_ code: Int, shift: Bool) {
        if code == kVK_Delete { onDelete?(); return }
        if let s = Self.character(code, shift: shift), !s.isEmpty { onText?(s) }
    }

    /// What the key types on the current layout (a German keyboard's Shift+] is `*`).
    static func character(_ code: Int, shift: Bool) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), shift ? UInt32(shiftKey >> 8) & 0xFF : 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead,
                                  chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length)
        return s.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) ? s : nil
    }
}

/// A tap of the left Command key opens the Start menu, as the Windows key did: pressed and let
/// go within a moment, with no other key, click or modifier in between (Command-C stays
/// Command-C). Watching the keys of other apps needs Accessibility, which the taskbar has.
final class StartKeyTap {
    static let shared = StartKeyTap()
    private var monitors: [Any] = []
    private var downAt: TimeInterval?

    /// Watches while the setting is on; the Start menu itself checks for a theme that has one.
    func update() {
        let on = AppSettings.shared.startMenuCommandTap
        if on && monitors.isEmpty {
            let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0) }) { monitors.append(m) }
            if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0); return $0 }) { monitors.append(m) }
        } else if !on && !monitors.isEmpty {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
        }
    }

    private func handle(_ e: NSEvent) {
        guard e.type == .flagsChanged else { downAt = nil; return }
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function, .numericPad])
        if e.keyCode == UInt16(kVK_Command) {
            if flags == .command { downAt = e.timestamp; return }
            if flags.isEmpty, let at = downAt, StartKeyTap.isTap(downAt: at, upAt: e.timestamp) {
                downAt = nil
                _ = DockController.shared.openStartMenuFromKeyboard()
                return
            }
        }
        downAt = nil
    }

    static func isTap(downAt: TimeInterval, upAt: TimeInterval) -> Bool { upAt - downAt < 0.35 }
}
