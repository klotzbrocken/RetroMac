import AppKit
import WebKit

/// BeOS "App Folder" — a Tracker-style window listing the installed applications with
/// matching BeOS icons. Launched from the Deskbar "Applikationen" entry or the desktop
/// "Applikationen" folder. Movable by its yellow title-tab.
final class AppFolderController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    static let shared = AppFolderController()

    private var panel: NSPanel?
    private var webView: WKWebView?
    private var dragOverlay: DragOverlayView?

    private override init() { super.init() }

    func toggle() { if panel?.isVisible == true { close() } else { show() } }

    func show() {
        guard let html = Bundle.main.resourceURL?
            .appendingPathComponent("Widgets/AppFolder/AppFolder.html"),
              FileManager.default.fileExists(atPath: html.path) else { NSSound.beep(); return }

        if panel == nil {
            let initial = NSRect(x: 0, y: 0, width: 700, height: 484)
            let cfg = WKWebViewConfiguration()
            cfg.userContentController.add(self, name: "appfolder")
            let wv = WKWebView(frame: initial, configuration: cfg)
            wv.navigationDelegate = self
            wv.autoresizingMask = [.width, .height]
            wv.setValue(false, forKey: "drawsBackground")

            let overlay = DragOverlayView(frame: .zero)
            overlay.onClose = { [weak self] in self?.close() }
            overlay.autoresizingMask = [.minYMargin]   // stay pinned to the top tab on resize

            let resize = ResizeOverlayView(frame: NSRect(x: initial.width - 15, y: 0, width: 15, height: 15))
            resize.autoresizingMask = [.minXMargin]   // pin to the bottom-right resize gadget

            let container = NSView(frame: initial)
            container.addSubview(wv)
            container.addSubview(overlay)
            container.addSubview(resize)

            let p = NSPanel(contentRect: initial, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.level = .floating
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.contentView = container
            self.panel = p; self.webView = wv; self.dragOverlay = overlay
        }

        webView?.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        if let panel = panel, let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.midX - panel.frame.width / 2, y: vf.midY - panel.frame.height / 2))
        }
        panel?.orderFrontRegardless()
    }

    func close() { panel?.orderOut(nil) }

    private func resizeTo(_ w: CGFloat, _ h: CGFloat) {
        guard let panel = panel, let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let top = panel.frame.maxY
        panel.setContentSize(NSSize(width: min(max(w, 320), vf.width - 20), height: min(max(h, 200), vf.height - 40)))
        var f = panel.frame; f.origin.y = top - f.height   // keep the top-left corner anchored
        panel.setFrame(f, display: true)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let apps = Self.installedApps()
        if let data = try? JSONSerialization.data(withJSONObject: apps),
           let json = String(data: data, encoding: .utf8) {
            webView.evaluateJavaScript("window.setApps && window.setApps(\(json))")
        }
        // Position the drag/close overlay over the yellow title-tab.
        webView.evaluateJavaScript("window.regions ? window.regions() : []") { [weak self] result, _ in
            guard let self = self, let wv = self.webView, let overlay = self.dragOverlay,
                  let a = (result as? [NSNumber]).map({ $0.map { CGFloat(truncating: $0) } }), a.count == 8 else { return }
            let tabX = a[0], tabY = a[1], tabW = a[2], tabH = a[3]
            let cX = a[4], cY = a[5], cW = a[6], cH = a[7]
            let H = wv.bounds.height
            overlay.frame = CGRect(x: tabX, y: H - (tabY + tabH), width: tabW, height: tabH)
            overlay.closeRect = CGRect(x: cX - tabX, y: tabH - ((cY - tabY) + cH), width: cW, height: cH)
        }
    }

    // MARK: - WKScriptMessageHandler (menu actions + double-click launch)

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "appfolder", let d = message.body as? [String: Any],
              let a = d["a"] as? String else { return }
        let path = d["path"] as? String
        let name = (d["name"] as? String) ?? (path.map { ($0 as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "") } ?? "App")
        switch a {
        case "open":
            if let id = d["id"] as? String {
                if id.hasPrefix("/") { NSWorkspace.shared.open(URL(fileURLWithPath: id)) }
                else { AppLauncher.launchOrActivate(bundleID: id) }
            }
        case "close":   close()
        case "openparent": NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        case "resizefit":
            if let w = (d["w"] as? NSNumber)?.doubleValue, let h = (d["h"] as? NSNumber)?.doubleValue { resizeTo(CGFloat(w), CGFloat(h)) }
        case "find":    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        case "newfolder": makeNewFolderOnDesktop()
        case "getinfo": if let p = path { getInfo(p) }
        case "editname": if let p = path { editName(p, current: name) }
        case "duplicate": if let p = path { duplicate(p) }
        case "trash": if let p = path { trash(p, name: name) }
        case "moveto": if let p = path, let dest = d["dest"] as? String { transfer(p, to: dest, copy: false) }
        case "copyto": if let p = path, let dest = d["dest"] as? String { transfer(p, to: dest, copy: true) }
        case "createlink": if let p = path { createLink(p, name: name) }
        case "iconown": pickOwnIcon()
        default: break
        }
    }

    // MARK: - File operations (real, with confirmation; system apps are protected)

    private func isProtected(_ path: String) -> Bool { path.hasPrefix("/System/") }
    private func systemBlocked() {
        let a = NSAlert(); a.messageText = "Protected by macOS"
        a.informativeText = "System applications can't be renamed, moved, duplicated or trashed (System Integrity Protection)."
        a.addButton(withTitle: "OK"); a.runModal()
    }
    private func confirm(_ msg: String, _ info: String) -> Bool {
        let a = NSAlert(); a.messageText = msg; a.informativeText = info; a.alertStyle = .warning
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel"); return a.runModal() == .alertFirstButtonReturn
    }
    private func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent(), base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var n = 2
        while true {
            let cand = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            if !fm.fileExists(atPath: cand.path) { return cand }; n += 1
        }
    }
    private func refresh() {
        if let data = try? JSONSerialization.data(withJSONObject: Self.installedApps()),
           let json = String(data: data, encoding: .utf8) {
            webView?.evaluateJavaScript("window.setApps && window.setApps(\(json))")
        }
    }
    private func folderURL(_ dest: String) -> URL {
        let fm = FileManager.default
        switch dest {
        case "Documents": return fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? fm.homeDirectoryForCurrentUser
        case "Downloads": return fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fm.homeDirectoryForCurrentUser
        case "Applications": return URL(fileURLWithPath: "/Applications")
        case "Home": return fm.homeDirectoryForCurrentUser
        default: return fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        }
    }

    private func getInfo(_ path: String) {
        let src = "tell application \"Finder\"\nactivate\nopen information window of (POSIX file \"\(path)\" as alias)\nend tell"
        var e: NSDictionary?; NSAppleScript(source: src)?.executeAndReturnError(&e)
    }
    private func editName(_ path: String, current: String) {
        if isProtected(path) { systemBlocked(); return }
        let alert = NSAlert(); alert.messageText = "Edit Name"; alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24)); tf.stringValue = current; alert.accessoryView = tf
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = tf.stringValue.trimmingCharacters(in: .whitespaces); guard !newName.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        let dst = url.deletingLastPathComponent().appendingPathComponent(newName + (url.pathExtension.isEmpty ? "" : "." + url.pathExtension))
        do { try FileManager.default.moveItem(at: url, to: dst); refresh() } catch { NSSound.beep() }
    }
    private func duplicate(_ path: String) {
        if isProtected(path) { systemBlocked(); return }
        let url = URL(fileURLWithPath: path)
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        let dst = uniqueURL(url.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? "\(base) copy" : "\(base) copy.\(ext)"))
        do { try FileManager.default.copyItem(at: url, to: dst); refresh() } catch { NSSound.beep() }
    }
    private func trash(_ path: String, name: String) {
        if isProtected(path) { systemBlocked(); return }
        guard confirm("Move “\(name)” to the Trash?", "You can restore it from the Trash later.") else { return }
        do { try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil); refresh() } catch { NSSound.beep() }
    }
    private func transfer(_ path: String, to dest: String, copy: Bool) {
        if !copy && isProtected(path) { systemBlocked(); return }
        let url = URL(fileURLWithPath: path)
        let dst = uniqueURL(folderURL(dest).appendingPathComponent(url.lastPathComponent))
        do {
            if copy { try FileManager.default.copyItem(at: url, to: dst) }
            else { try FileManager.default.moveItem(at: url, to: dst); refresh() }
        } catch { NSSound.beep() }
    }
    private func createLink(_ path: String, name: String) {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let link = uniqueURL(desktop.appendingPathComponent(name))
        do { try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: path)) }
        catch { NSSound.beep() }
    }
    private func makeNewFolderOnDesktop() {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let dir = uniqueURL(desktop.appendingPathComponent("New Folder"))
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false); NSWorkspace.shared.activateFileViewerSelecting([dir]) }
        catch { NSSound.beep() }
    }
    fileprivate func resizeBy(corner mouse: NSPoint) {
        guard let panel = panel else { return }
        let f = panel.frame
        let newW = max(360, mouse.x - f.minX)
        let newH = max(220, f.maxY - mouse.y)            // keep the top edge anchored
        panel.setFrame(NSRect(x: f.minX, y: f.maxY - newH, width: newW, height: newH), display: true)
    }

    private func pickOwnIcon() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .tiff, .icns, .image]
        panel.allowsMultipleSelection = false; panel.message = "Choose an icon image"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        let mime = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
        let dataURL = "data:\(mime);base64,\(data.base64EncodedString())"
        webView?.evaluateJavaScript("window.setOwnIcon && window.setOwnIcon('\(dataURL)')")
    }

    // MARK: - Installed apps + BeOS icon mapping

    /// BeOS icon keys (from beos-icons.js): generic, folder, browser, mail, messages, maps,
    /// photos, video, calendar, people, notes, settings, clock, calculator, terminal, text.
    private static let bundleIcon: [String: String] = [
        "com.apple.finder": "folder", "com.apple.Safari": "browser", "com.apple.mail": "mail",
        "com.apple.MobileSMS": "messages", "com.apple.Maps": "maps", "com.apple.Photos": "photos",
        "com.apple.FaceTime": "video", "com.apple.iCal": "calendar", "com.apple.AddressBook": "people",
        "com.apple.Notes": "notes", "com.apple.reminders": "text", "com.apple.Music": "generic",
        "com.apple.podcasts": "messages", "com.apple.TV": "video", "com.apple.calculator": "calculator",
        "com.apple.Terminal": "terminal", "com.apple.systempreferences": "settings", "com.apple.AppStore": "generic",
        "com.apple.Preview": "photos", "com.apple.TextEdit": "text", "com.apple.clock": "clock",
        "com.apple.ActivityMonitor": "generic", "com.apple.Console": "terminal", "com.apple.DiskUtility": "generic",
        "com.apple.FontBook": "text", "com.apple.keychainaccess": "settings", "com.apple.ScriptEditor2": "text",
        "com.apple.iWork.Pages": "text", "com.apple.iWork.Numbers": "calculator", "com.apple.iWork.Keynote": "photos",
        "com.apple.dt.Xcode": "terminal", "com.apple.freeform": "notes", "com.apple.weather": "maps",
        "com.apple.VoiceMemos": "messages", "com.apple.Home": "settings", "com.apple.shortcuts": "settings",
        "com.apple.QuickTimePlayerX": "video", "com.apple.Dictionary": "text", "com.apple.Stocks": "generic",
        "com.apple.Image_Capture": "photos", "com.apple.PhotoBooth": "photos", "com.apple.Automator": "settings",
    ]

    private static func iconKey(bundleID: String?, name: String) -> String {
        if let b = bundleID, let k = bundleIcon[b] { return k }
        let n = name.lowercased()
        func has(_ xs: [String]) -> Bool { xs.contains { n.contains($0) } }
        if has(["safari", "chrome", "firefox", "browser", "edge", "arc", "comet", "opera"]) { return "browser" }
        if has(["mail", "outlook", "spark"]) { return "mail" }
        if has(["message", "chat", "slack", "discord", "telegram", "whatsapp", "signal", "teams"]) { return "messages" }
        if has(["map"]) { return "maps" }
        if has(["calendar"]) { return "calendar" }
        if has(["contact", "people", "address"]) { return "people" }
        if has(["note"]) { return "notes" }
        if has(["calc"]) { return "calculator" }
        if has(["clock", "timer", "stopwatch"]) { return "clock" }
        if has(["terminal", "console", "code", "iterm", "warp"]) { return "terminal" }
        if has(["setting", "preference", "keychain", "config"]) { return "settings" }
        if has(["photo", "image", "preview", "pixel", "affinity", "gimp"]) { return "photos" }
        if has(["video", "movie", "player", "vlc", "quicktime", "tv", "music", "podcast"]) { return "video" }
        if has(["text", "edit", "word", "pages", "font", "writer", "doc"]) { return "text" }
        return "generic"
    }

    private static func installedApps() -> [[String: String]] {
        let fm = FileManager.default
        var dirs = ["/Applications", "/Applications/Utilities",
                    "/System/Applications", "/System/Applications/Utilities"]
        dirs.append(NSHomeDirectory() + "/Applications")
        var seen = Set<String>()
        var out: [[String: String]] = []
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let path = dir + "/" + item
                let url = URL(fileURLWithPath: path)
                let bundleID = Bundle(url: url)?.bundleIdentifier
                let key = bundleID ?? path
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                let name = fm.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
                out.append(["id": bundleID ?? path, "name": name, "path": path,
                            "icon": iconKey(bundleID: bundleID, name: name)])
            }
        }
        return out.sorted { ($0["name"] ?? "").localizedCaseInsensitiveCompare($1["name"] ?? "") == .orderedAscending }
    }
}

/// Transparent grip over the BeOS bottom-right resize gadget: dragging it resizes the
/// window (top-left anchored).
final class ResizeOverlayView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {
        AppFolderController.shared.resizeBy(corner: NSEvent.mouseLocation)
    }
}
