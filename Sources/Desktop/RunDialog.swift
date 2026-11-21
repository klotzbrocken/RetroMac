import AppKit
import WebKit

/// What the Run… dialog opens for a typed line. After retro98's RunTarget (matheushchaves, MIT):
/// in order a URL, a web address, a path (with ~), an app by name; before them the Windows
/// commands RetroMac has an answer for.
enum RunTarget: Equatable {
    case url(URL)
    case path(URL)
    case app(URL)
    case command(String)
    case notFound(String)

    static let maxSearchDepth = 5
    /// The Windows commands, and what each opens on the Mac.
    static let commands: [String: String] = [
        "notepad": "notepad", "write": "notepad", "wordpad": "notepad", "edit": "notepad",
        "calc": "calc", "cmd": "terminal", "command": "terminal", "powershell": "terminal",
        "control": "settings", "taskmgr": "taskmgr", "explorer": "explorer", "winfile": "explorer",
        "msconfig": "settings", "winver": "about", "sysedit": "notepad",
    ]
    static var appRoots: [URL] {
        ["/Applications", "/System/Applications", "/System/Library/CoreServices/Applications", NSHomeDirectory() + "/Applications"]
            .map { URL(fileURLWithPath: $0) }
    }

    /// Nil for blank input.
    static func resolve(_ input: String, appRoots: [URL] = appRoots, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                        fileManager: FileManager = .default) -> RunTarget? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lowered = text.lowercased()
        let bare = lowered.hasSuffix(".exe") ? String(lowered.dropLast(4)) : lowered
        if let c = commands[bare] { return .command(c) }
        if text.contains("://") || lowered.hasPrefix("mailto:"), let url = URL(string: text) { return .url(url) }
        if lowered.hasPrefix("www."), let url = URL(string: "https://" + text) { return .url(url) }
        if text.hasPrefix("/") || text.hasPrefix("~") {
            let path = text.hasPrefix("~") ? home.path + text.dropFirst() : text
            return fileManager.fileExists(atPath: path) ? .path(URL(fileURLWithPath: path)) : .notFound(text)
        }
        let wanted = lowered.hasSuffix(".app") ? String(text.dropLast(4)) : text
        for root in appRoots {
            if let url = findApp(named: wanted, in: root, depth: 0, fileManager: fileManager) { return .app(url) }
        }
        return .notFound(text)
    }

    /// Apps in a folder are checked before its subfolders; app bundles are never entered.
    private static func findApp(named wanted: String, in folder: URL, depth: Int, fileManager: FileManager) -> URL? {
        guard depth < maxSearchDepth, let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return nil }
        let visible = names.filter { !$0.hasPrefix(".") }.sorted()
        for name in visible where name.lowercased().hasSuffix(".app") {
            let url = folder.appendingPathComponent(name, isDirectory: false)
            let candidates = [String(name.dropLast(4)), stripApp(fileManager.displayName(atPath: url.path))]
            if candidates.contains(where: { matches($0, wanted) }) { return url }
        }
        for name in visible where !name.lowercased().hasSuffix(".app") {
            let url = folder.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            if let found = findApp(named: wanted, in: url, depth: depth + 1, fileManager: fileManager) { return found }
        }
        return nil
    }
    private static func matches(_ candidate: String, _ wanted: String) -> Bool {
        candidate.compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
    private static func stripApp(_ name: String) -> String { name.lowercased().hasSuffix(".app") ? String(name.dropLast(4)) : name }
}

/// Start ▸ Run… of Windows 95 to 7: the dialog itself, in the theme's chrome, with the last ten
/// lines typed.
final class RunDialogController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = RunDialogController()

    private var panel: NSPanel?
    private var webView: WKWebView?
    private var dragOverlay: DragOverlayView?
    private let historyKey = "runDialogHistory"

    func show() {
        guard let html = Bundle.main.resourceURL?.appendingPathComponent("Widgets/Run/Run.html"),
              FileManager.default.fileExists(atPath: html.path) else { NSSound.beep(); return }
        if let panel { panel.makeKeyAndOrderFront(nil); webView?.evaluateJavaScript("window.focusField()"); return }
        let initial = NSRect(x: 0, y: 0, width: 347, height: 180)
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.userContentController.add(self, name: "run")
        let wv = WKWebView(frame: initial, configuration: cfg)
        wv.navigationDelegate = self
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")
        let overlay = DragOverlayView(frame: .zero)
        overlay.onClose = { [weak self] in self?.close() }
        overlay.onButtonState = { [weak self] slot, state in
            self?.webView?.evaluateJavaScript("window.setBtnState && window.setBtnState('\(slot)','\(state)')")
        }
        let container = NSView(frame: initial)
        container.addSubview(wv); container.addSubview(overlay)
        let p = KeyableWidgetPanel(contentRect: initial, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.title = "Run"
        p.contentView = container
        panel = p; webView = wv; dragOverlay = overlay
        // The Run dialog sat above the Start button, bottom left.
        if let vf = NSScreen.main?.visibleFrame { p.setFrameOrigin(NSPoint(x: vf.minX + 12, y: vf.minY + 40)) }
        wv.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent().deletingLastPathComponent())
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    func close() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "run")
        panel?.orderOut(nil)
        panel = nil; webView = nil; dragOverlay = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.setTheme('\(RetroFrameTheme.widgetKey())')")
        let theme = ThemeManager.shared.activeTheme
        let icon = ["menu-run.png", "xp_run.png"].lazy.compactMap { theme?.iconResource($0) }.first
        if let icon, let data = try? Data(contentsOf: icon) {
            webView.evaluateJavaScript("window.setIcon('data:image/png;base64,\(data.base64EncodedString())')")
        }
        let history = (UserDefaults.standard.stringArray(forKey: historyKey) ?? [])
        if let json = try? JSONSerialization.data(withJSONObject: history), let s = String(data: json, encoding: .utf8) {
            webView.evaluateJavaScript("window.setHistory(\(s))")
        }
        webView.evaluateJavaScript("window.widgetSize()") { [weak self] result, _ in
            guard let self, let panel = self.panel, let a = (result as? [NSNumber])?.map({ CGFloat(truncating: $0) }), a.count == 2 else { return }
            let top = panel.frame.minY
            panel.setContentSize(NSSize(width: a[0], height: a[1]))
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: top))
            self.webView?.frame = NSRect(x: 0, y: 0, width: a[0], height: a[1])
            webView.evaluateJavaScript("window.regions()") { r, _ in
                guard let r = (r as? [NSNumber])?.map({ CGFloat(truncating: $0) }), r.count >= 8, let overlay = self.dragOverlay else { return }
                let tabY = r[1], tabH = r[3], H = a[1]
                overlay.frame = CGRect(x: 0, y: H - (tabY + tabH), width: a[0], height: tabH)
                overlay.closeRect = CGRect(x: r[4], y: tabH - ((r[5] - tabY) + r[7]), width: r[6], height: r[7])
            }
            webView.evaluateJavaScript("window.focusField()")
        }
    }

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let a = body["a"] as? String else { return }
        switch a {
        case "close": close()
        case "browse": browse()
        case "run": run(body["text"] as? String ?? "")
        default: break
        }
    }

    private func run(_ text: String) {
        guard let target = RunTarget.resolve(text) else { return }
        if case .notFound(let t) = target {
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = t
            a.informativeText = "Cannot find the file \u{2018}\(t)\u{2019} (or one of its components). Make sure the path and filename are correct and that all required libraries are available."
            a.runModal()
            webView?.evaluateJavaScript("window.focusField()")
            return
        }
        var history = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
        history.removeAll { $0.caseInsensitiveCompare(text) == .orderedSame }
        history.insert(text, at: 0)
        UserDefaults.standard.set(Array(history.prefix(10)), forKey: historyKey)
        close()
        switch target {
        case .url(let u), .path(let u), .app(let u): NSWorkspace.shared.open(u)
        case .command(let c): Self.runCommand(c)
        case .notFound: break
        }
    }

    static func runCommand(_ c: String) {
        switch c {
        case "notepad": NotepadController.shared.show()
        case "calc": CalculatorController.shared.show()
        case "terminal": _ = NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        case "settings": _ = NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!)
        case "taskmgr":
            if TaskManagerController.wanted { TaskManagerController.shared.show() }
            else { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }
        case "explorer": DesktopLauncher.openFolder(URL(fileURLWithPath: "/"))
        case "about": _ = NSApp.sendAction(Selector(("showAbout")), to: nil, from: nil)
        default: break
        }
    }

    private func browse() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        guard p.runModal() == .OK, let url = p.url else { return }
        webView?.evaluateJavaScript("window.setField(\(Self.jsString(url.path)))")
    }

    private static func jsString(_ s: String) -> String {
        (try? JSONSerialization.data(withJSONObject: [s])).flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }
}
