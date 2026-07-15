import AppKit
import WebKit

/// BeOS "App Folder" — a Tracker-style window listing the installed applications with
/// matching BeOS icons. Launched from the Deskbar "Applikationen" entry or the desktop
/// "Applikationen" folder. Movable by its yellow title-tab.
final class AppFolderController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    enum Kind { case apps, tv }

    static let shared = AppFolderController(kind: .apps)
    /// Second instance reusing the same window design to list the RetroMac "Television" streams.
    static let tv = AppFolderController(kind: .tv)

    private let kind: Kind
    private var panel: NSPanel?
    private var webView: WKWebView?
    private var dragOverlay: DragOverlayView?
    private var windowTitle: String { kind == .tv ? "Television" : "Applications" }

    private init(kind: Kind) {
        self.kind = kind
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: .dockThemeChanged, object: nil)
    }

    /// On theme switch, drop the cached window so it rebuilds fresh (correct chrome, no
    /// stale collapsed/zoom state — fixes the "only BeOS tab, no window" carry-over).
    @objc private func themeChanged() { destroy() }

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
            overlay.onHover = { [weak self] h in
                self?.webView?.evaluateJavaScript("window.setHover && window.setHover(\(h))")
            }
            overlay.onButtonState = { [weak self] slot, state in
                self?.webView?.evaluateJavaScript("window.setBtnState && window.setBtnState('\(slot)','\(state)')")
            }
            overlay.autoresizingMask = [.minYMargin]   // stay pinned to the top tab on resize

            let container = NSView(frame: initial)
            container.addSubview(wv)

            // Resize gadgets — bottom corners only. (The top corners would sit right on the
            // Mac OS 9 title-bar close/zoom boxes and steal their clicks; the title bar's
            // drag overlay is added AFTER these so it stays on top for the boxes.)
            let g: CGFloat = 16
            let corners: [(ResizeCorner, NSRect, NSView.AutoresizingMask)] = [
                (.br, NSRect(x: initial.width - g, y: 0, width: g, height: g), [.minXMargin]),
                (.bl, NSRect(x: 0, y: 0, width: g, height: g), [.maxXMargin]),
            ]
            for (corner, frame, mask) in corners {
                let r = ResizeOverlayView(frame: frame)
                r.autoresizingMask = mask
                r.onResize = { [weak self] p in self?.resizeBy(corner: corner, to: p) }
                container.addSubview(r)
            }

            container.addSubview(overlay)   // topmost: title-bar boxes + drag win over resize grips

            let p = NSPanel(contentRect: initial, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.level = .normal   // behaves like a normal window (not always-on-top)
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

    /// Warm hide — keeps the WebView alive for instant reopen.
    func close() { panel?.orderOut(nil) }

    /// Cold teardown — removes the script-message handler and releases the WebView.
    func destroy() {
        if let wv = webView {
            wv.stopLoading()
            wv.navigationDelegate = nil
            wv.configuration.userContentController.removeAllScriptMessageHandlers()
            wv.removeFromSuperview()
        }
        webView = nil
        dragOverlay = nil
        panel?.orderOut(nil); panel = nil
        collapsed = false; preZoomFrame = nil; preCollapseHeight = 0
    }

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
        // Theme the window chrome (BeOS tab vs Mac OS 9 Platinum) before populating.
        webView.evaluateJavaScript("window.setTheme && window.setTheme('\(RetroFrameTheme.key())')")
        let escTitle = windowTitle.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.setTitle && window.setTitle('\(escTitle)')")
        let items = (kind == .tv) ? Self.tvItems() : Self.installedApps()
        if let data = try? JSONSerialization.data(withJSONObject: items),
           let json = String(data: data, encoding: .utf8) {
            webView.evaluateJavaScript("window.setApps && window.setApps(\(json))")
        }
        // Position the drag/close overlay over the title bar (BeOS tab or Mac OS 9 bar).
        webView.evaluateJavaScript("window.regions ? window.regions() : []") { [weak self] result, _ in
            guard let self = self, let wv = self.webView, let overlay = self.dragOverlay,
                  let a = (result as? [NSNumber]).map({ $0.map { CGFloat(truncating: $0) } }),
                  a.count >= 8 else { return }
            let tabY = a[1], tabH = a[3]
            let H = wv.bounds.height
            // Overlay spans from x=0 to the title bar's right edge (a[0]+a[2], from the
            // DOM — always valid even before the webview reaches its final width, which
            // wv.bounds.width isn't at this point in didFinish). Box rects in absolute x.
            overlay.frame = CGRect(x: 0, y: H - (tabY + tabH), width: a[0] + a[2], height: tabH)
            self.titleStripHeight = tabH   // for WindowShade collapse
            func local(_ i: Int) -> CGRect {
                CGRect(x: a[i], y: tabH - ((a[i+1] - tabY) + a[i+3]), width: a[i+2], height: a[i+3])
            }
            overlay.closeRect = local(4)
            if a.count >= 16 {   // Mac OS 9: collapse (WindowShade) + zoom boxes
                overlay.collapseRect = local(8)
                overlay.zoomRect = local(12)
                overlay.onCollapse = { [weak self] in self?.toggleCollapse() }
                overlay.onZoom = { [weak self] in self?.toggleZoom() }
            } else {
                overlay.collapseRect = .zero; overlay.zoomRect = .zero
            }
        }
    }

    // MARK: - Mac OS 9 title-bar controls

    private var collapsed = false
    private var preCollapseHeight: CGFloat = 0
    private var preZoomFrame: NSRect?
    private var titleStripHeight: CGFloat = 22   // active chrome's title-bar height (captured live)

    /// WindowShade: roll the window up to just the title bar, or restore.
    private func toggleCollapse() {
        guard let panel = panel else { return }
        if collapsed {
            panel.setContentSize(NSSize(width: panel.frame.width, height: preCollapseHeight))
            collapsed = false
        } else {
            preCollapseHeight = panel.frame.height
            let top = panel.frame.maxY
            panel.setContentSize(NSSize(width: panel.frame.width, height: titleStripHeight))
            var f = panel.frame; f.origin.y = top - f.height; panel.setFrame(f, display: true)
            collapsed = true
        }
        scheduleReposition()
    }

    /// Zoom: toggle between the current size and a standard full-content size.
    private func toggleZoom() {
        guard let panel = panel, let screen = NSScreen.main else { return }
        if collapsed { toggleCollapse() }
        let vf = screen.visibleFrame
        if let f = preZoomFrame {
            panel.setFrame(f, display: true); preZoomFrame = nil
        } else {
            preZoomFrame = panel.frame
            let top = panel.frame.maxY
            let w = min(820, vf.width - 20), h = min(620, vf.height - 40)
            panel.setContentSize(NSSize(width: w, height: h))
            var f = panel.frame; f.origin.y = top - f.height; panel.setFrame(f, display: true)
        }
        scheduleReposition()
    }

    /// Debounced re-capture: coalesces rapid resize events and waits a beat so the
    /// WKWebView has reflowed (regions() read immediately after setFrame returns the
    /// OLD box positions — that's why clicks broke after a resize).
    private var repositionWork: DispatchWorkItem?
    private func scheduleReposition() {
        repositionWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.repositionOverlay() }
        repositionWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: w)
    }

    /// Re-run regions() so the overlay tracks the title bar after a resize.
    private func repositionOverlay() {
        webView?.evaluateJavaScript("window.regions ? window.regions() : []") { [weak self] result, _ in
            guard let self = self, let wv = self.webView, let overlay = self.dragOverlay,
                  let a = (result as? [NSNumber]).map({ $0.map { CGFloat(truncating: $0) } }),
                  a.count >= 8 else { return }
            let tabY = a[1], tabH = a[3]
            let H = wv.bounds.height
            overlay.frame = CGRect(x: 0, y: H - (tabY + tabH), width: a[0] + a[2], height: tabH)
            func local(_ i: Int) -> CGRect {
                CGRect(x: a[i], y: tabH - ((a[i+1] - tabY) + a[i+3]), width: a[i+2], height: a[i+3])
            }
            overlay.closeRect = local(4)
            if a.count >= 16 { overlay.collapseRect = local(8); overlay.zoomRect = local(12) }
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
                if id.hasPrefix("tv:") {
                    // TV folder entry → open the stream via AppDelegate's retained TV window.
                    NotificationCenter.default.post(name: .init("openTVBookmark"), object: String(id.dropFirst(3)))
                } else if id.hasPrefix("/") { NSWorkspace.shared.open(URL(fileURLWithPath: id)) }
                else { AppLauncher.launchOrActivate(bundleID: id) }
            }
        case "close":   close()
        case "zoom":    toggleZoom()
        case "openparent": NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        case "resizefit":
            if let w = (d["w"] as? NSNumber)?.doubleValue, let h = (d["h"] as? NSNumber)?.doubleValue {
                resizeTo(CGFloat(w), CGFloat(h))
                scheduleReposition()   // re-capture the title/box regions at the final size
            }
        case "find":    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        case "newfolder": makeNewFolderOnDesktop()
        case "getinfo": if let p = path { getInfo(p) }
        case "editname": if let p = path { editName(p, current: name) }
        case "duplicate": if let p = path { duplicate(p) }
        case "trash": if let p = path { trash(p, name: name) }
        case "moveto": if let p = path, let dest = d["dest"] as? String { transfer(p, to: dest, copy: false) }
        case "copyto": if let p = path, let dest = d["dest"] as? String { transfer(p, to: dest, copy: true) }
        case "createlink": if let p = path { createLink(p, name: name) }
        case "iconown": pickOwnIcon(bundleID: d["id"] as? String)
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
    fileprivate func resizeBy(corner: ResizeCorner, to mouse: NSPoint) {
        guard let panel = panel else { return }
        let f = panel.frame
        let minW: CGFloat = 360, minH: CGFloat = 220
        var x = f.minX, y = f.minY, w = f.width, h = f.height
        switch corner {
        case .br:  w = max(minW, mouse.x - f.minX); h = max(minH, f.maxY - mouse.y); x = f.minX;        y = f.maxY - h
        case .bl:  w = max(minW, f.maxX - mouse.x); h = max(minH, f.maxY - mouse.y); x = f.maxX - w;    y = f.maxY - h
        case .tr:  w = max(minW, mouse.x - f.minX); h = max(minH, mouse.y - f.minY); x = f.minX;        y = f.minY
        case .tl:  w = max(minW, f.maxX - mouse.x); h = max(minH, mouse.y - f.minY); x = f.maxX - w;    y = f.minY
        }
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        scheduleReposition()   // keep the title-bar box hit areas aligned after resizing
    }

    private func pickOwnIcon(bundleID: String?) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .tiff, .icns, .image]
        panel.allowsMultipleSelection = false; panel.message = "Choose an icon image"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        // Persist per-theme (so the same icon also shows in the Dock / Start menu) when this
        // entry is a real app; path-only entries fall back to the per-window visual below.
        if let bid = bundleID, !bid.hasPrefix("/") {
            ThemeManager.shared.setCustomIcon(for: bid, path: url.path)
            reloadApps()   // rebuild the grid so the themed icon picks up the override
        }
        let mime = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
        let dataURL = "data:\(mime);base64,\(data.base64EncodedString())"
        webView?.evaluateJavaScript("window.setOwnIcon && window.setOwnIcon('\(dataURL)')")
    }

    /// Re-scan installed apps and push them to the grid (picks up icon overrides).
    private func reloadApps() {
        let apps = Self.installedApps()
        if let data = try? JSONSerialization.data(withJSONObject: apps),
           let json = String(data: data, encoding: .utf8) {
            webView?.evaluateJavaScript("window.setApps && window.setApps(\(json))")
        }
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

    /// Themed icon (mapped PNG, else real app icon) as a small PNG data URL — the Mac OS 9 /
    /// Windows XP equivalent of BeOS' SVG icon set. Rendered into a FIXED 40×40 bitmap:
    /// NSImage.tiffRepresentation would otherwise emit the largest underlying rep (often 512px),
    /// so 30+ system icons produced multi-megabyte JSON that froze the main thread.
    private static func iconDataURL(bundleID: String?, path: String) -> String? {
        let img: NSImage
        if let b = bundleID { img = ThemeManager.shared.icon(for: b, size: 128) }
        else { img = NSWorkspace.shared.icon(forFile: path) }
        return pngDataURL(img)
    }

    /// Render an NSImage into a fixed 40×40 PNG data URL (bounded size — see note above).
    private static func pngDataURL(_ img: NSImage) -> String? {
        let side = 128
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                 from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    /// The RetroMac "Television" streams as folder items (id = "tv:<uuid>").
    private static func tvItems() -> [[String: String]] {
        // A themed music/TV icon (used by the Mac OS 9 / Windows XP grids that show it.img).
        var img: String? = nil
        if let dir = ThemeManager.shared.activeTheme?.iconsDirectory {
            for cand in ["TVStreams.icns", "xp_music.png", "music.png", "video.png", "tv.png", "quicktime.png"] {
                let u = dir.appendingPathComponent(cand)
                if FileManager.default.fileExists(atPath: u.path), let i = NSImage(contentsOf: u) {
                    img = pngDataURL(i); break
                }
            }
        }
        return AppSettings.shared.tvBookmarks.map { bm in
            var rec: [String: String] = ["id": "tv:\(bm.id.uuidString)", "name": bm.name, "path": "", "icon": "video"]
            if let img = img { rec["img"] = img }
            return rec
        }
    }

    private static func installedApps() -> [[String: String]] {
        let k = RetroFrameTheme.key()
        let themed = (k == "macos9" || k == "winxp" || k == "maiksfav" || k == "macosx" || k == "win98")
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
                var rec: [String: String] = ["id": bundleID ?? path, "name": name, "path": path,
                                             "icon": iconKey(bundleID: bundleID, name: name)]
                if themed, let dataURL = iconDataURL(bundleID: bundleID, path: path) { rec["img"] = dataURL }
                out.append(rec)
            }
        }
        return out.sorted { ($0["name"] ?? "").localizedCaseInsensitiveCompare($1["name"] ?? "") == .orderedAscending }
    }
}

enum ResizeCorner { case br, bl, tr, tl }

/// Transparent grip over a window resize gadget: dragging it resizes the window,
/// anchoring the opposite corner.
final class ResizeOverlayView: NSView {
    var onResize: ((NSPoint) -> Void)?   // owning controller resizes ITS window
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {
        onResize?(NSEvent.mouseLocation)
    }
}
