import AppKit
import WebKit
import UniformTypeIdentifiers

/// The Windows Explorer of the Windows themes (`"finder": "explorer"`): My Computer, folders with
/// Large Icons, List and Details, cut, copy, paste, drag and drop, rename, delete and undo, all
/// through FileOps (after retro98, MIT). The same window is the Open and Save As dialog of the
/// Notepad. Paths read the Windows way: the startup disk is C:, other volumes D:, E:….
final class ExplorerController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static var isEnabled: Bool { ThemeManager.shared.activeTheme?.config.finder == "explorer" }
    private static var windows: [ExplorerController] = []

    /// Opens `url` in a new Explorer window; nil is My Computer.
    static func show(_ url: URL?) {
        let w = ExplorerController(dialog: nil)
        windows.append(w)
        w.present(at: url)
    }

    /// Open: a file, or nil when cancelled.
    static func openDialog(extensions: [String], start: URL?, completion: @escaping (URL?) -> Void) {
        let w = ExplorerController(dialog: Dialog(save: false, name: "", extensions: extensions, completion: completion))
        windows.append(w)
        w.present(at: start ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"))
    }

    /// Save As: where to save, asked again before replacing, or nil when cancelled.
    static func saveDialog(name: String, start: URL?, completion: @escaping (URL?) -> Void) {
        let w = ExplorerController(dialog: Dialog(save: true, name: name, extensions: ["txt"], completion: completion))
        windows.append(w)
        w.present(at: start ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"))
    }

    @objc private static func themeChanged() { if !isEnabled { windows.forEach { $0.finish(nil) } } }
    private static let observer: Void = {
        NotificationCenter.default.addObserver(ExplorerController.self, selector: #selector(themeChanged), name: .dockThemeChanged, object: nil)
    }()

    struct Dialog { let save: Bool; let name: String; let extensions: [String]; let completion: (URL?) -> Void }
    private let dialog: Dialog?
    private var panel: NSPanel?
    private var webView: WKWebView?
    private var overlay: DragOverlayView?
    private var current: URL?                     // nil: My Computer
    private var back: [URL?] = [], forward: [URL?] = []
    private var fileObserver: NSObjectProtocol?
    private var cut: [URL] = []
    private var restoreFrame: NSRect?
    private var pendingSelect: [String] = []

    private init(dialog: Dialog?) { self.dialog = dialog; super.init(); _ = Self.observer }

    // MARK: - Window

    private func present(at url: URL?) {
        guard let html = Bundle.main.resourceURL?.appendingPathComponent("Widgets/Explorer/Explorer.html"),
              FileManager.default.fileExists(atPath: html.path) else { NSSound.beep(); return }
        current = url
        let size = dialog == nil ? NSSize(width: 720, height: 480) : NSSize(width: 560, height: 400)
        let frame = NSRect(origin: .zero, size: size)
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.userContentController.add(self, name: "explorer")
        let wv = WKWebView(frame: frame, configuration: cfg)
        wv.navigationDelegate = self
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")
        let ov = DragOverlayView(frame: .zero)
        ov.onClose = { [weak self] in self?.finish(nil) }
        ov.onButtonState = { [weak self] slot, state in
            self?.webView?.evaluateJavaScript("window.setBtnState && window.setBtnState('\(slot)','\(state)')")
        }
        let container = NSView(frame: frame)
        container.addSubview(wv); container.addSubview(ov)
        let p = KeyableWidgetPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .miniaturizable], backing: .buffered, defer: false)
        p.level = dialog == nil ? .normal : .floating
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.hidesOnDeactivate = false
        p.contentView = container
        // Each new window a little down and right of the last, as Windows cascaded them.
        let n = CGFloat(Self.windows.count - 1)
        if let vf = NSScreen.main?.visibleFrame {
            p.setFrameTopLeftPoint(NSPoint(x: vf.minX + 120 + n * 24, y: vf.maxY - 60 - n * 24))
        }
        panel = p; webView = wv; overlay = ov
        fileObserver = NotificationCenter.default.addObserver(forName: .fileOperationsDidChange, object: nil, queue: .main) { [weak self] _ in self?.render() }
        // Resources, not Widgets: the XP title bar takes its buttons from Resources/Chrome/winxp.
        wv.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    /// Closes the window; a dialog answers its caller first.
    private func finish(_ result: URL?) {
        if let o = fileObserver { NotificationCenter.default.removeObserver(o) }
        fileObserver = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "explorer")
        panel?.orderOut(nil)
        panel = nil; webView = nil
        Self.windows.removeAll { $0 === self }
        dialog?.completion(result)
    }

    private func layoutOverlay() {
        guard let wv = webView else { return }
        wv.evaluateJavaScript("window.regions()") { [weak self] r, _ in
            guard let self, let r = (r as? [NSNumber])?.map({ CGFloat(truncating: $0) }), r.count >= 8, let ov = self.overlay else { return }
            let tabY = r[1], tabH = r[3], H = wv.bounds.height
            // The title text only: the buttons at its right are the page's own (min, max, close).
            ov.frame = CGRect(x: 0, y: H - (tabY + tabH), width: max(0, r[4] - 4), height: tabH)
            ov.closeRect = .zero
        }
    }

    private func toggleMaximize() {
        guard let p = panel, let vf = (p.screen ?? NSScreen.main)?.visibleFrame else { return }
        if let r = restoreFrame { p.setFrame(r, display: true, animate: true); restoreFrame = nil }
        else { restoreFrame = p.frame; p.setFrame(vf, display: true, animate: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.layoutOverlay() }
    }

    // MARK: - Page

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.setTheme('\(RetroFrameTheme.widgetKey())')")
        webView.evaluateJavaScript(Win98Scheme.widgetOverrideJS())   // the theme's title colours, as on its other windows
        if let d = dialog { send("window.setDialog", ["save": d.save, "name": d.name, "types": d.extensions]) }
        let mode = UserDefaults.standard.string(forKey: "explorerView") ?? "icons"
        webView.evaluateJavaScript("window.setView('\(mode)')")
        render()
        layoutOverlay()
    }

    private func send(_ fn: String, _ value: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: value), let s = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("\(fn)(\(s))")
    }

    /// The listing, built off the main thread (a big folder takes a moment), then shown.
    private func render() {
        let at = current, own = dialog?.extensions
        DispatchQueue.global(qos: .userInitiated).async {
            let listing = ExplorerListing.build(at, onlyExtensions: own)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.current == at else { return }
                let ops = FileOps.shared
                var page = listing
                // The apps wear the theme's icons; its icon cache lives on the main thread.
                var icons: [String: String] = [:]
                for item in listing["items"] as? [[String: Any]] ?? [] {
                    guard let key = item["icon"] as? String, key.hasPrefix("app:"), icons[key] == nil,
                          let bid = Bundle(url: URL(fileURLWithPath: String(key.dropFirst(4))))?.bundleIdentifier else { continue }
                    icons[key] = ExplorerListing.pngDataURL(ThemeManager.shared.icon(for: bid, size: 32))
                }
                page["icons"] = icons
                page["canBack"] = !self.back.isEmpty
                page["canForward"] = !self.forward.isEmpty
                page["canUp"] = at != nil
                page["undo"] = ["can": ops.canUndo, "title": ops.undoTitle]
                page["canPaste"] = at != nil && !FileOps.pasteboardFiles().isEmpty
                page["cut"] = self.cut.map(\.path)
                page["select"] = self.pendingSelect
                self.pendingSelect = []
                self.send("window.render", page)
            }
        }
    }

    private func go(_ url: URL?, record: Bool = true) {
        if record, url != current { back.append(current); forward.removeAll() }
        current = url
        render()
    }

    // MARK: - Messages from the page

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let b = message.body as? [String: Any], let a = b["a"] as? String else { return }
        let paths = (b["paths"] as? [String] ?? []).map { URL(fileURLWithPath: $0) }
        let path = (b["path"] as? String).map { $0.isEmpty ? nil : URL(fileURLWithPath: $0) } ?? nil
        let ops = FileOps.shared
        switch a {
        case "close": finish(nil)
        case "min": panel?.miniaturize(nil)
        case "max": toggleMaximize()
        case "view": UserDefaults.standard.set(b["mode"] as? String, forKey: "explorerView")
        case "nav": go(path)
        case "up": if let c = current { go(c.path == "/" || c.deletingLastPathComponent().path == "/Volumes" ? nil : c.deletingLastPathComponent()) }
        case "back": if let u = back.popLast() { forward.append(current); go(u, record: false) }
        case "forward": if let u = forward.popLast() { back.append(current); go(u, record: false) }
        case "address":
            let text = b["text"] as? String ?? ""
            if let u = ExplorerListing.fromWindows(text) { go(u) }
            else if let t = RunTarget.resolve(text), case .url(let u) = t { NSWorkspace.shared.open(u) }
            else { alert("Cannot find \u{2018}\(text)\u{2019}. Make sure the path is correct.") }
        case "open": if let u = path { open(u) }
        case "accept": accept(b["name"] as? String ?? "", selected: path)
        case "newFolder":
            guard let c = current else { return }
            ops.newFolder(in: c, base: "New Folder") { [weak self] o in self?.pendingSelect = o.results.map(\.path); self?.render() }
        case "rename":
            guard let u = path else { return }
            switch RenameRules.check(original: u.lastPathComponent, typed: b["name"] as? String ?? "", isFolder: FileOperations.isPlainFolder(u)) {
            case .unchanged: render()
            case .invalid(let why): alert(why); render()
            case .accept(let name): ops.rename(u, to: name) { [weak self] o in self?.pendingSelect = o.results.map(\.path) }
            case .confirmExtensionChange:
                let ask = NSAlert()
                ask.messageText = "Rename"
                ask.informativeText = "If you change a filename extension, the file may become unusable.\n\nAre you sure you want to change it?"
                ask.addButton(withTitle: "Yes"); ask.addButton(withTitle: "No")
                if ask.runModal() == .alertFirstButtonReturn {
                    ops.rename(u, to: (b["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                } else { render() }
            }
        case "delete":
            guard !paths.isEmpty else { return }
            let ask = NSAlert()
            ask.messageText = paths.count == 1 ? "Confirm File Delete" : "Confirm Multiple File Delete"
            ask.informativeText = paths.count == 1 ? "Are you sure you want to send \u{2018}\(paths[0].lastPathComponent)\u{2019} to the Recycle Bin?"
                : "Are you sure you want to send these \(paths.count) items to the Recycle Bin?"
            ask.addButton(withTitle: "Yes"); ask.addButton(withTitle: "No")
            guard ask.runModal() == .alertFirstButtonReturn else { return }
            ops.trash(paths)
        case "copy": cut = []; FileOps.putOnPasteboard(paths); render()
        case "cut": cut = paths; FileOps.putOnPasteboard(paths); render()
        case "paste":
            guard let c = current else { return }
            let urls = FileOps.pasteboardFiles()
            let moving = !cut.isEmpty && Set(cut) == Set(urls)
            cut = []
            let done: (OperationOutcome) -> Void = { [weak self] o in self?.pendingSelect = o.results.map(\.path) }
            moving ? ops.move(urls, to: c, done: done) : ops.copy(urls, to: c, done: done)
        case "drop":
            guard let to = (b["to"] as? String).map({ URL(fileURLWithPath: $0) }) ?? current, !paths.isEmpty else { return }
            (b["copy"] as? Bool == true) ? ops.copy(paths, to: to) : ops.move(paths, to: to)
        case "undo": ops.undo()
        case "redo": ops.redo()
        case "props": if let u = path { properties(u) }
        case "mydocs": go(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"))
        case "desktop": go(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"))
        case "recycle": DesktopLauncher.launch(DockThemeConfig.DesktopIconEntry(name: "Recycle Bin", icon: "", type: "trash"))
        case "control": NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!)
        case "about": NSApp.sendAction(Selector(("showAbout")), to: nil, from: nil)
        default: break
        }
    }

    private func open(_ u: URL) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
        let isPackage = (try? u.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
        if isDir.boolValue && !isPackage { go(u); return }
        if let d = dialog, !d.save { finish(u); return }    // the Open dialog's double-click
        if dialog == nil { NSWorkspace.shared.open(u) }
    }

    /// The dialog's Open or Save button. Save checks the name and asks before replacing.
    private func accept(_ typed: String, selected: URL?) {
        guard let d = dialog else { return }
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.save {
            if let s = selected { open(s); return }
            if let u = ExplorerListing.fromWindows(name) ?? current.map({ $0.appendingPathComponent(name) }), FileManager.default.fileExists(atPath: u.path) { open(u) }
            else { alert("\(name)\nFile not found.\nPlease verify the correct file name was given.") }
            return
        }
        guard let folder = current else { alert("Choose a folder to save in."); return }
        guard !name.isEmpty, !name.contains("/"), !name.contains(":"), !name.hasPrefix(".") else { alert("The file name is not valid."); return }
        var target = folder.appendingPathComponent(name)
        if target.pathExtension.isEmpty, let ext = d.extensions.first { target.appendPathExtension(ext) }
        if FileManager.default.fileExists(atPath: target.path) {
            let ask = NSAlert()
            ask.messageText = "Save As"
            ask.informativeText = "\(target.lastPathComponent) already exists.\nDo you want to replace it?"
            ask.addButton(withTitle: "Yes"); ask.addButton(withTitle: "No")
            guard ask.runModal() == .alertFirstButtonReturn else { return }
        }
        finish(target)
    }

    private func properties(_ u: URL) {
        let v = try? u.resourceValues(forKeys: [.localizedTypeDescriptionKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey, .isDirectoryKey])
        let size: String
        if v?.isDirectory == true {
            let total = FileCopy.totalSize(of: u, control: OperationControl())
            size = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        } else {
            size = ByteCountFormatter.string(fromByteCount: Int64(v?.fileSize ?? 0), countStyle: .file)
        }
        func date(_ d: Date?) -> String { d.map { DateFormatter.localizedString(from: $0, dateStyle: .long, timeStyle: .short) } ?? "" }
        let a = NSAlert()
        a.messageText = "\(u.lastPathComponent) Properties"
        a.informativeText = "Type:\t\(v?.localizedTypeDescription ?? "")\nLocation:\t\(ExplorerListing.toWindows(u.deletingLastPathComponent()))\nSize:\t\(size)\n\nCreated:\t\(date(v?.creationDate))\nModified:\t\(date(v?.contentModificationDate))"
        a.runModal()
    }

    private func alert(_ text: String) {
        let a = NSAlert(); a.alertStyle = .warning; a.messageText = dialog == nil ? "Explorer" : (dialog!.save ? "Save As" : "Open")
        a.informativeText = text
        a.runModal()
    }
}

/// What a folder (or My Computer) shows, as the page wants it, and the Windows spelling of paths.
enum ExplorerListing {
    static func build(_ folder: URL?, onlyExtensions: [String]?) -> [String: Any] {
        guard let folder else { return myComputer() }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey, .isHiddenKey, .contentTypeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        var items: [[String: Any]] = []
        for u in urls {
            let v = try? u.resourceValues(forKeys: Set(keys))
            let isDir = v?.isDirectory == true, isPkg = v?.isPackage == true
            let isApp = u.pathExtension == "app"
            if let only = onlyExtensions, !isDir || isPkg, !only.isEmpty, !only.contains(u.pathExtension.lowercased()) { continue }
            let icon = isApp ? "app:" + u.path : isDir && !isPkg ? "folder" : kind(v?.contentType, ext: u.pathExtension)
            items.append([
                "name": isApp ? u.deletingPathExtension().lastPathComponent : u.lastPathComponent,
                "path": u.path, "folder": isDir && !isPkg, "icon": icon,
                "size": isDir ? -1 : Int64(v?.fileSize ?? 0),
                "type": isDir && !isPkg ? "File Folder" : (v?.localizedTypeDescription ?? "File"),
                "mod": (v?.contentModificationDate ?? .distantPast).timeIntervalSince1970,
            ])
        }
        items.sort { a, b in
            let fa = a["folder"] as? Bool == true, fb = b["folder"] as? Bool == true
            if fa != fb { return fa }
            return (a["name"] as? String ?? "").localizedStandardCompare(b["name"] as? String ?? "") == .orderedAscending
        }
        let free = (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        return ["title": title(folder), "address": toWindows(folder), "path": folder.path, "items": items, "role": role(folder),
                "free": free.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""]
    }

    /// My Computer: the drives, then Control Panel.
    static func myComputer() -> [String: Any] {
        var items: [[String: Any]] = []
        for (i, v) in volumes().enumerated() {
            let r = try? v.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsRemovableKey,
                                                    .volumeIsEjectableKey, .volumeIsLocalKey, .volumeTypeNameKey])
            let letter = String(UnicodeScalar(UInt8(67 + i)))   // C:, D:, E:…
            let (icon, type) = driveKind(typeName: r?.volumeTypeName, isLocal: r?.volumeIsLocal ?? true,
                                         isRemovable: r?.volumeIsRemovable == true || r?.volumeIsEjectable == true)
            items.append(["name": "\(r?.volumeName ?? v.lastPathComponent) (\(letter):)", "path": v.path, "folder": true,
                          "icon": icon, "size": -1, "type": type,
                          "mod": 0, "total": Int64(r?.volumeTotalCapacity ?? 0), "freeBytes": Int64(r?.volumeAvailableCapacity ?? 0)])
        }
        items.append(["name": "Control Panel", "path": "", "special": "control", "folder": false, "icon": "control", "size": -1, "type": "System Folder", "mod": 0])
        return ["title": "My Computer", "address": "My Computer", "path": "", "items": items, "free": ""]
    }

    /// A CD-ROM only for a disc's file system; an external disk is a Removable Disk, a server a
    /// Network Drive.
    static func driveKind(typeName: String?, isLocal: Bool, isRemovable: Bool) -> (icon: String, type: String) {
        if ["cd9660", "udf", "cddafs"].contains(typeName?.lowercased() ?? "") { return ("cd", "CD-ROM Disc") }
        if !isLocal { return ("netdrive", "Network Drive") }
        if isRemovable { return ("removable", "Removable Disk") }
        return ("drive", "Local Disk")
    }

    static func volumes() -> [URL] {
        let all = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        let root = URL(fileURLWithPath: "/")
        return [root] + all.filter { $0.path != "/" && $0.path.hasPrefix("/Volumes/") }
    }

    /// The window icon of the special folders; any other folder shows an open folder.
    static func role(_ u: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        switch u.standardizedFileURL.path {
        case home + "/Documents": return "mydocs"
        case home + "/Desktop": return "desktop"
        case "/Applications": return "programs"
        default: return "folderopen"
        }
    }

    static func title(_ u: URL) -> String {
        if u.path == "/" { return FileManager.default.displayName(atPath: "/") + " (C:)" }
        return FileManager.default.displayName(atPath: u.path)
    }

    /// "/Users/maik" → "C:\Users\maik"; a second volume is D:\, and so on.
    static func toWindows(_ u: URL) -> String {
        let vols = volumes()
        for (i, v) in vols.enumerated().reversed() where i > 0 && (u.path == v.path || u.path.hasPrefix(v.path + "/")) {
            let rest = String(u.path.dropFirst(v.path.count))
            return String(UnicodeScalar(UInt8(67 + i))) + ":" + (rest.isEmpty ? "\\" : rest.replacingOccurrences(of: "/", with: "\\"))
        }
        return "C:" + u.path.replacingOccurrences(of: "/", with: "\\")
    }

    /// The reverse, for the address bar; Mac paths and ~ work too.
    static func fromWindows(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.caseInsensitiveCompare("My Computer") == .orderedSame { return nil }
        var path: String
        if t.hasPrefix("~") { path = NSHomeDirectory() + t.dropFirst() }
        else if t.hasPrefix("/") { path = t }
        else if t.count >= 2, t.dropFirst().first == ":", let letter = t.uppercased().unicodeScalars.first?.value {
            let vols = volumes(), i = Int(letter) - 67
            guard i >= 0, i < vols.count else { return nil }
            let rest = String(t.dropFirst(2)).replacingOccurrences(of: "\\", with: "/")
            path = (i == 0 ? "" : vols[i].path) + (rest.isEmpty ? "/" : rest)
        } else { return nil }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue ? URL(fileURLWithPath: path) : nil
    }

    /// Which of the page's own drawn icons a file gets.
    static func kind(_ type: UTType?, ext: String) -> String {
        guard let t = type else { return "doc" }
        if t.conforms(to: .plainText) || t.conforms(to: .sourceCode) { return "text" }
        if t.conforms(to: .font) { return "font" }
        if t.conforms(to: .image) { return "image" }
        if t.conforms(to: .audio) { return "audio" }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return "video" }
        if t.conforms(to: .archive) || t.conforms(to: .diskImage) { return "archive" }
        if t.conforms(to: .pdf) { return "pdf" }
        if t.conforms(to: .html) || t.conforms(to: .internetLocation) { return "web" }
        if t.conforms(to: .executable) || t.conforms(to: .unixExecutable) { return "exe" }
        return "doc"
    }

    static func pngDataURL(_ image: NSImage?) -> String? {
        guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }
}
