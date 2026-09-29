import AppKit
import Carbon.HIToolbox
import WebKit

/// Windows Task Manager (XP's 5.1) under the Windows XP theme: a widget panel
/// with the page in `Widgets/TaskManager/TaskManager.html`, fed by `SystemSampler` at the
/// update speed its View menu sets. Opened with Ctrl+Option+Delete — the Mac's Ctrl+Alt+Del —
/// or "Task Manager" in the taskbar's menu, as in XP.
final class TaskManagerController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    static let shared = TaskManagerController()

    /// The themes that had a Task Manager with tabs. Windows 95, 98 and Me had only the
    /// "Close Program" list.
    /// Windows XP only for now: Windows 7 gets it with Task Manager 6.1's own look, not XP's.
    static var wanted: Bool { RetroFrameTheme.key() == "winxp" }

    private var panel: NSPanel?
    private var webView: WKWebView?
    private var overlay: DragOverlayView?
    private var timer: Timer?
    private var keyTokens: [NSObjectProtocol] = []
    private let sampler = SystemSampler()
    /// Seconds between samples: XP's High, Normal and Low; nil while paused.
    private var interval: TimeInterval? = 1

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .dockThemeChanged, object: nil)
    }

    @objc private func themeChanged() { update() }

    /// Follow the theme: the hotkey while a Windows theme with a Task Manager is on, the
    /// window gone when it is not.
    func update() {
        setHotKey(Self.wanted && AppSettings.shared.dockEnabled)
        if !Self.wanted { destroy() }
    }


    /// The theme is going off: the key back to macOS, the window gone.
    func stop() {
        setHotKey(false)
        destroy()
    }

    func show() {
        guard Self.wanted,
              let html = Bundle.main.resourceURL?.appendingPathComponent("Widgets/TaskManager/TaskManager.html"),
              FileManager.default.fileExists(atPath: html.path) else { NSSound.beep(); return }
        if panel == nil { build(html: html) }
        restorePosition()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startSampling()
    }

    private static let size = NSSize(width: 410, height: 470)

    private func build(html: URL) {
        let frame = NSRect(origin: .zero, size: Self.size)
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.userContentController.add(self, name: "taskmgr")
        let wv = WKWebView(frame: frame, configuration: cfg)
        wv.navigationDelegate = self
        wv.autoresizingMask = [.width, .height]
        wv.setValue(false, forKey: "drawsBackground")

        let ov = DragOverlayView(frame: .zero)
        ov.onClose = { [weak self] in self?.close() }
        ov.onCollapse = { [weak self] in self?.close() }   // minimise: out of sight, back with Ctrl+Option+Delete
        ov.onButtonState = { [weak self] slot, state in
            self?.webView?.evaluateJavaScript("window.setBtnState && window.setBtnState('\(slot)','\(state)')")
        }
        let container = NSView(frame: frame)
        container.addSubview(wv)
        container.addSubview(ov)

        let p = KeyableWidgetPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        p.level = .normal
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.moveToActiveSpace]
        p.contentView = container
        panel = p; webView = wv; overlay = ov
        for (name, active) in [(NSWindow.didBecomeKeyNotification, true), (NSWindow.didResignKeyNotification, false)] {
            keyTokens.append(NotificationCenter.default.addObserver(forName: name, object: p, queue: .main) { [weak self] _ in
                self?.webView?.evaluateJavaScript("window.setActive && window.setActive(\(active))")
            })
        }
        keyTokens.append(NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
            self?.saveOrigin()
        })
        wv.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
    }

    /// Hide, keep the page (and its history graphs) for the next time.
    func close() {
        saveOrigin()
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil)
    }

    func destroy() {
        timer?.invalidate(); timer = nil
        sampler.reset()
        keyTokens.forEach { NotificationCenter.default.removeObserver($0) }
        keyTokens = []
        if let wv = webView {
            wv.stopLoading()
            wv.navigationDelegate = nil
            wv.configuration.userContentController.removeAllScriptMessageHandlers()
        }
        webView = nil; overlay = nil
        panel?.orderOut(nil); panel = nil
    }

    // MARK: Sampling

    private func startSampling() {
        timer?.invalidate(); timer = nil
        sample()
        guard let interval else { return }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sample() {
        let s = sampler.next()
        webView?.evaluateJavaScript("window.update && window.update(\(s.json))")
    }

    // MARK: Page

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.setTheme && window.setTheme('\(RetroFrameTheme.key())')")
        webView.evaluateJavaScript("window.setActive && window.setActive(\(panel?.isKeyWindow ?? true))")
        sample()
        captureRegions()
    }

    /// Lay the drag and caption-button overlay over the page's title bar.
    private func captureRegions() {
        webView?.evaluateJavaScript("window.regions ? window.regions() : []") { [weak self] result, _ in
            guard let self, let wv = self.webView, let ov = self.overlay,
                  let a = (result as? [NSNumber])?.map({ CGFloat(truncating: $0) }), a.count >= 16 else { return }
            let tabY = a[1], tabH = a[3], H = wv.bounds.height
            ov.frame = CGRect(x: 0, y: H - (tabY + tabH), width: wv.bounds.width, height: tabH)
            func local(_ i: Int) -> CGRect { CGRect(x: a[i], y: tabH - ((a[i+1] - tabY) + a[i+3]), width: a[i+2], height: a[i+3]) }
            ov.closeRect = local(4)
            ov.collapseRect = local(8)
            ov.zoomRect = local(12)
        }
    }

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let a = body["a"] as? String else { return }
        switch a {
        case "close":   close()
        case "refresh": sample()
        case "speed":
            switch body["v"] as? String {
            case "high": interval = 0.5
            case "low":  interval = 4
            case "paused": interval = nil
            default:     interval = 1
            }
            startSampling()
        case "run":     newTask()
        case "about":   about()
        default: break
        }
    }

    /// File ▸ New Task (Run...): pick a program and start it.
    private func newTask() {
        let open = NSOpenPanel()
        open.title = "Create New Task"
        open.prompt = "OK"
        open.directoryURL = URL(fileURLWithPath: "/Applications")
        open.allowedContentTypes = [.application]
        NSApp.activate(ignoringOtherApps: true)
        open.begin { resp in
            guard resp == .OK, let url = open.url else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    private func about() {
        let alert = NSAlert()
        alert.messageText = "Windows Task Manager"
        alert.informativeText = "Version 5.1, as it came with Windows XP — rebuilt for RetroMac from what macOS can tell."
        alert.runModal()
    }

    // MARK: Position

    private let posKey = "taskManagerOrigin"

    private func saveOrigin() {
        guard let panel, panel.isVisible else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: posKey)
    }

    private func restorePosition() {
        guard let panel else { return }
        if let s = UserDefaults.standard.string(forKey: posKey) {
            let origin = NSPointFromString(s)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(NSRect(origin: origin, size: panel.frame.size)) }) {
                panel.setFrameOrigin(origin); return
            }
        }
        panel.center()
    }

    // MARK: Ctrl+Option+Delete

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static let signature = OSType(0x524D544D)   // "RMTM"

    private func setHotKey(_ on: Bool) {
        if on, hotKey == nil {
            if handler == nil {
                var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
                InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                    var id = EventHotKeyID()
                    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &id)
                    guard id.signature == TaskManagerController.signature else { return OSStatus(eventNotHandledErr) }
                    DispatchQueue.main.async { TaskManagerController.shared.show() }
                    return noErr
                }, 1, &spec, nil, &handler)
            }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: 1)
            if RegisterEventHotKey(UInt32(kVK_Delete), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref) == noErr {
                hotKey = ref
            }
        } else if !on, let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }
}
