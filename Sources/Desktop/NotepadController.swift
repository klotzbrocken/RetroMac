import AppKit
import WebKit
import UniformTypeIdentifiers

/// Borderless key-accepting panel so the textarea can receive keyboard input.
final class NotepadPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Desktop Notepad widget — a themed plain-text scratchpad (BeOS / Mac OS 9 / Windows XP /
/// Maiks Favourite / Mac OS X Aqua). Opened from a "Notepad" desktop icon (type "notepad").
/// Mirrors ClockWidgetController (borderless WKWebView panel + DragOverlayView chrome) but
/// uses a key-accepting panel and persists its text.
final class NotepadController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    static let shared = NotepadController()

    private var panel: NotepadPanel?
    private var webView: WKWebView?
    /// The key-window observers that blur the Mac OS 9 widget; removed with the panel.
    private var blurTokens: [NSObjectProtocol] = []
    private var dragOverlay: DragOverlayView?
    private var moveObserver: NSObjectProtocol?
    private let posKey = "notepadWidgetOrigin"
    private let textKey = "notepadText"
    private var currentFileURL: URL?
    /// The opened file's line ending, byte-order mark and encoding, so Save writes the same kind back.
    private var currentFile = TextFile(text: "")

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: .dockThemeChanged, object: nil)
    }

    @objc private func themeChanged() { destroy() }

    func toggle() { if panel?.isVisible == true { close() } else { show() } }

    /// Warm hide — keeps the WebView alive for instant reopen.
    func close() { saveOrigin(); panel?.orderOut(nil) }

    /// Cold teardown — removes the script-message handler and releases the WebView.
    func destroy() {
        saveOrigin()
        if let mo = moveObserver { NotificationCenter.default.removeObserver(mo); moveObserver = nil }
        if let wv = webView {
            wv.stopLoading()
            wv.navigationDelegate = nil
            wv.configuration.userContentController.removeAllScriptMessageHandlers()
            wv.removeFromSuperview()
        }
        webView = nil
        dragOverlay = nil
        blurTokens.forEach { NotificationCenter.default.removeObserver($0) }
        blurTokens = []
        panel?.orderOut(nil); panel = nil
    }

    private func saveOrigin() {
        guard let panel = panel, panel.isVisible else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: posKey)
    }
    private func restorePosition() {
        guard let panel = panel else { return }
        if let s = UserDefaults.standard.string(forKey: posKey) {
            let origin = NSPointFromString(s)
            // Whole on one screen: a spot remembered on a bigger display can leave it all but off the edge.
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(NSRect(origin: origin, size: panel.frame.size)) }) {
                panel.setFrameOrigin(origin); return
            }
        }
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.midX - panel.frame.width / 2, y: vf.midY - panel.frame.height / 2))
        }
    }

    func show() {
        guard let html = Bundle.main.resourceURL?.appendingPathComponent("Widgets/Notepad/Notepad.html"),
              FileManager.default.fileExists(atPath: html.path) else { NSSound.beep(); return }

        if panel == nil {
            let sz = restoredSize()
            let initial = NSRect(x: 0, y: 0, width: sz.width, height: sz.height)
            let cfg = WKWebViewConfiguration()
            cfg.userContentController.add(self, name: "notepad")
            let wv = WKWebView(frame: initial, configuration: cfg)
            wv.navigationDelegate = self
            wv.autoresizingMask = [.width, .height]
            wv.setValue(false, forKey: "drawsBackground")

            let overlay = DragOverlayView(frame: .zero)
            overlay.onClose = { [weak self] in self?.close() }
            // WindowShade + Zoom: identical mechanism to the CPU/Applications widgets —
            // a JS control returns the new widget size and the panel resizes to match.
            overlay.onCollapse = { [weak self] in self?.resizeToWidget("window.toggleCollapse ? window.toggleCollapse() : [0,0]") }
            overlay.onZoom = { [weak self] in self?.resizeToWidget("window.toggleZoom ? window.toggleZoom() : [0,0]") }
            overlay.onHover = { [weak self] h in
                self?.webView?.evaluateJavaScript("window.setHover && window.setHover(\(h))")
            }
            overlay.onButtonState = { [weak self] slot, state in
                self?.webView?.evaluateJavaScript("window.setBtnState && window.setBtnState('\(slot)','\(state)')")
            }

            let container = NSView(frame: initial)
            addWin7Glass(to: container)   // Aero glass behind the transparent webview (win7 only)
            container.addSubview(wv)

            // Resize gadgets on all four corners (anchor the opposite corner).
            let g: CGFloat = 16
            let corners: [(ResizeCorner, NSRect, NSView.AutoresizingMask)] = [
                (.br, NSRect(x: initial.width - g, y: 0, width: g, height: g), [.minXMargin]),
                (.bl, NSRect(x: 0, y: 0, width: g, height: g), [.maxXMargin]),
                (.tr, NSRect(x: initial.width - g, y: initial.height - g, width: g, height: g), [.minXMargin, .minYMargin]),
                (.tl, NSRect(x: 0, y: initial.height - g, width: g, height: g), [.maxXMargin, .minYMargin]),
            ]
            for (corner, frame, mask) in corners {
                let r = ResizeOverlayView(frame: frame)
                r.autoresizingMask = mask
                r.onResize = { [weak self] p in self?.resizeBy(corner: corner, to: p) }
                container.addSubview(r)
            }
            // Drag/close overlay LAST → it sits on top of the corner gadgets in the title-bar
            // region, so the close/collapse/zoom boxes are always clickable (the top corners
            // would otherwise steal those clicks). Bottom corners stay free for resizing.
            container.addSubview(overlay)

            let p = NotepadPanel(contentRect: initial, styleMask: [.borderless],
                                 backing: .buffered, defer: false)
            p.level = .normal
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.hidesOnDeactivate = false   // stay visible when another app/window comes forward
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.contentView = container
            self.panel = p; self.webView = wv; self.dragOverlay = overlay
            blurTokens = installMacOS9BlurTracking(panel: p) { [weak self] in self?.webView }
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in self?.saveOrigin() }
        }

        webView?.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        restorePosition()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "notepad" else { return }
        if let action = message.body as? String, action == "close" { close(); return }
        guard let dict = message.body as? [String: Any], let action = dict["action"] as? String else { return }
        switch action {
        case "save": UserDefaults.standard.set(dict["text"] as? String ?? "", forKey: textKey)
        case "menuOpen": dragOverlay?.passthrough = (dict["open"] as? Bool ?? false)
        case "close": close()
        case "open": openFile()
        case "saveFile": saveFile(plain: dict["plain"] as? String ?? "", forceDialog: false)
        case "saveAs": saveFile(plain: dict["plain"] as? String ?? "", forceDialog: true)
        default: break
        }
    }

    /// Encode a Swift string as a safe JS string literal (incl. surrounding quotes).
    private func jsString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(json.dropFirst().dropLast())   // strip the [ ] → leaves "…"
    }

    /// Open: the Explorer's Open dialog under the Windows themes, the Mac's panel elsewhere. Read
    /// as TextFile (after retro98): binary and huge files are refused with a message.
    private func openFile() {
        let load: (URL?) -> Void = { [weak self] url in
            guard let self, let url else { return }
            do {
                let file = try TextFile.read(from: url)
                self.currentFile = file
                self.currentFileURL = url
                UserDefaults.standard.set(file.text, forKey: self.textKey)
                self.webView?.evaluateJavaScript("window.loadFile && window.loadFile(\(self.jsString(url.lastPathComponent)), \(self.jsString(file.text)), false)")
            } catch {
                self.problem("Cannot open \u{201C}\(url.lastPathComponent)\u{201D}", (error as? TextFileError)?.message ?? error.localizedDescription)
            }
        }
        if ExplorerController.isEnabled {
            ExplorerController.openDialog(extensions: ["txt", "text", "log", "ini", "md", "csv"], start: currentFileURL?.deletingLastPathComponent(), completion: load)
            return
        }
        let p = NSOpenPanel()
        p.allowedContentTypes = [.plainText, .text]
        p.allowsOtherFileTypes = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        load(p.runModal() == .OK ? p.url : nil)
    }

    /// Save writes the same kind of file back (line endings, BOM, encoding) through a finished copy;
    /// a failure says so instead of losing the text quietly.
    private func saveFile(plain: String, forceDialog: Bool) {
        UserDefaults.standard.set(plain, forKey: textKey)
        let write: (URL?) -> Void = { [weak self] url in
            guard let self, let url else { return }
            var file = self.currentFile
            file.text = plain
            do {
                try file.write(to: url)
                self.currentFile = file
                self.currentFileURL = url
                self.webView?.evaluateJavaScript("window.setFile && window.setFile(\(self.jsString(url.lastPathComponent)))")
            } catch {
                self.problem("Cannot save \u{201C}\(url.lastPathComponent)\u{201D}", error.localizedDescription)
            }
        }
        if !forceDialog, let url = currentFileURL { write(url); return }
        let name = currentFileURL?.lastPathComponent ?? "Untitled.txt"
        if ExplorerController.isEnabled {
            ExplorerController.saveDialog(name: name, start: currentFileURL?.deletingLastPathComponent(), completion: write)
            return
        }
        let p = NSSavePanel()
        p.allowedContentTypes = [.plainText]
        p.allowsOtherFileTypes = true
        p.nameFieldStringValue = name
        NSApp.activate(ignoringOtherApps: true)
        write(p.runModal() == .OK ? p.url : nil)
    }

    private func problem(_ title: String, _ text: String) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// The classic Mac themes turn the Notepad into their era's text editor: SimpleText for
    /// Mac OS 9, TeachText for Mac OS 6. Empty for every other theme (normal Notepad).
    private func editorAppFlavor() -> String {
        guard AppSettings.shared.dockEnabled else { return "" }
        let n = (ThemeManager.shared.activeTheme?.config.name ?? "").lowercased()
        if n.contains("mac os 9") || n.contains("copland") { return "simpletext" }
        if n.contains("mac os 6") { return "teachtext" }
        return ""
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(RetroFrameTheme.widgetThemeJS(RetroFrameTheme.widgetKey()))
        webView.evaluateJavaScript(Win98Scheme.widgetOverrideJS())   // Win98 Plus! scheme recolour
        webView.evaluateJavaScript("window.setEditorApp && window.setEditorApp('\(editorAppFlavor())')")
        let saved = UserDefaults.standard.string(forKey: textKey) ?? ""
        if let data = try? JSONSerialization.data(withJSONObject: [saved]),
           let json = String(data: data, encoding: .utf8) {
            // json is ["..."] — strip the array braces to get a valid JS string literal
            let literal = String(json.dropFirst().dropLast())
            webView.evaluateJavaScript("window.setText && window.setText(\(literal))")
        }
        // The editor is fluid (fills the panel) and user-resizable — keep the current
        // panel size; just (re)place the drag/close overlay over the title bar.
        captureRegions()
    }

    private let sizeKey = "notepadWidgetSize"
    private func restoredSize() -> NSSize {
        if let s = UserDefaults.standard.string(forKey: sizeKey) {
            let sz = NSSizeFromString(s)
            if sz.width >= 320, sz.height >= 240 { return sz }
        }
        return NSSize(width: 480, height: 420)
    }

    private func resizeBy(corner: ResizeCorner, to mouse: NSPoint) {
        guard let panel = panel else { return }
        let f = panel.frame
        let minW: CGFloat = 320, minH: CGFloat = 240
        var x = f.minX, y = f.minY, w = f.width, h = f.height
        switch corner {
        case .br: w = max(minW, mouse.x - f.minX); h = max(minH, f.maxY - mouse.y); x = f.minX;     y = f.maxY - h
        case .bl: w = max(minW, f.maxX - mouse.x); h = max(minH, f.maxY - mouse.y); x = f.maxX - w; y = f.maxY - h
        case .tr: w = max(minW, mouse.x - f.minX); h = max(minH, mouse.y - f.minY); x = f.minX;     y = f.minY
        case .tl: w = max(minW, f.maxX - mouse.x); h = max(minH, mouse.y - f.minY); x = f.maxX - w; y = f.minY
        }
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        UserDefaults.standard.set(NSStringFromSize(NSSize(width: w, height: h)), forKey: sizeKey)
        captureRegions()
    }

    private func captureRegions() {
        webView?.evaluateJavaScript("window.regions ? window.regions() : []") { [weak self] result, _ in
            guard let self = self, let wv = self.webView, let overlay = self.dragOverlay,
                  let a = (result as? [NSNumber])?.map({ CGFloat(truncating: $0) }), a.count >= 8 else { return }
            let tabY = a[1], tabH = a[3]
            let H = wv.bounds.height
            overlay.frame = CGRect(x: 0, y: H - (tabY + tabH), width: wv.bounds.width, height: tabH)
            overlay.closeRect = CGRect(x: a[4], y: tabH - ((a[5] - tabY) + a[7]), width: a[6], height: a[7])
            // Classic Mac editors add a WindowShade (collapse) + Zoom box on the right.
            if a.count >= 16 {
                overlay.collapseRect = CGRect(x: a[8],  y: tabH - ((a[9]  - tabY) + a[11]), width: a[10], height: a[11])
                overlay.zoomRect     = CGRect(x: a[12], y: tabH - ((a[13] - tabY) + a[15]), width: a[14], height: a[15])
            } else {
                overlay.collapseRect = .zero; overlay.zoomRect = .zero
            }
        }
    }

    // MARK: - Classic window gadgets (SimpleText / TeachText)

    /// Run a JS title-control that returns the new widget size; resize the panel
    /// (top-left anchored) and re-capture the title regions. Mirrors the CPU widget.
    private func resizeToWidget(_ js: String) {
        webView?.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self, let panel = self.panel,
                  let arr = result as? [NSNumber], arr.count == 2 else { return }
            let w = CGFloat(truncating: arr[0]), h = CGFloat(truncating: arr[1])
            guard w > 20, h > 20 else { return }
            let top = panel.frame.maxY
            panel.setContentSize(NSSize(width: w, height: h))
            self.webView?.frame = NSRect(origin: .zero, size: NSSize(width: w, height: h))
            var f = panel.frame; f.origin.y = top - f.height; panel.setFrame(f, display: true)
            self.captureRegions()
        }
    }
}
