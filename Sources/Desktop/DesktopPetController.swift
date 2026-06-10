import AppKit
import WebKit

/// Non-activating overlay panel so interacting with the pet never steals focus.
private final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Desktop pet — the classic eSheep look for the Windows XP / 98 themes.
/// The ENGINE is original (Pet.html, no third-party code); the classic sheep artwork is
/// fetched at RUNTIME from the open-source desktopPet project and cached (same pattern as
/// the GZDoom/shareware downloads — the GPL-licensed asset is never bundled with the app).
/// Falls back to the built-in sprite when offline.
final class DesktopPetController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

    static let shared = DesktopPetController()

    private var panel: PetPanel?
    private var webView: WKWebView?
    private var hoverTimer: Timer?
    private var petScreenRect: CGRect = .zero   // current pet bounds in screen coords

    private static let sheepXML = "https://raw.githubusercontent.com/Adrianotiger/desktopPet/master/Pets/esheep64/animations.xml"

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: .dockThemeChanged, object: nil)
        applyForCurrentTheme()
    }

    @objc private func themeChanged() { applyForCurrentTheme() }

    private var enabledForActiveTheme: Bool {
        guard AppSettings.shared.desktopPetEnabled else { return false }
        let n = (ThemeManager.shared.activeTheme?.config.name ?? "").lowercased()
        return n.contains("windows xp") || n.contains("windows 98")
    }

    func applyForCurrentTheme() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.enabledForActiveTheme { self.show() } else { self.hide() }
        }
    }

    private func show() {
        guard let html = Bundle.main.resourceURL?.appendingPathComponent("Widgets/DesktopPet/Pet.html"),
              FileManager.default.fileExists(atPath: html.path) else { return }

        if panel == nil {
            guard let screen = NSScreen.main else { return }
            let frame = screen.frame
            let cfg = WKWebViewConfiguration()
            cfg.userContentController.add(self, name: "pet")
            let wv = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: cfg)
            wv.navigationDelegate = self
            wv.autoresizingMask = [.width, .height]
            wv.setValue(false, forKey: "drawsBackground")   // transparent

            let p = PetPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
            // ABOVE the RetroMac taskbar (dock window is level 24): the sheep walks in
            // front of the taskbar instead of disappearing behind it.
            p.level = NSWindow.Level(rawValue: 25)
            p.ignoresMouseEvents = true   // click-through; flipped on only over the pet
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            p.contentView = wv
            self.panel = p; self.webView = wv
            installHoverTimer()
        }
        webView?.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        panel?.orderFrontRegardless()
    }

    private func hide() {
        hoverTimer?.invalidate(); hoverTimer = nil
        panel?.orderOut(nil)
        panel = nil; webView = nil; petScreenRect = .zero
    }

    /// Click-through everywhere except over the pet. Poll-based (60ms) — works without any
    /// extra permissions (a global mouseMoved monitor missed events over our own window).
    /// While the button is held over the pet, keep accepting events so the drag never drops.
    private func installHoverTimer() {
        hoverTimer?.invalidate()
        let t = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
            guard let self = self, let panel = self.panel else { return }
            let dragging = !panel.ignoresMouseEvents && (NSEvent.pressedMouseButtons & 1) == 1
            let over = self.petScreenRect.insetBy(dx: -10, dy: -10).contains(NSEvent.mouseLocation)
            let want = over || dragging
            if panel.ignoresMouseEvents == want { panel.ignoresMouseEvents = !want }
        }
        RunLoop.main.add(t, forMode: .common)
        hoverTimer = t
    }

    // MARK: - WKScriptMessageHandler (pet reports its rect in web/top-left px)

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "pet", let d = message.body as? [String: Any], let win = panel else { return }
        func num(_ k: String) -> CGFloat { (d[k] as? NSNumber).map { CGFloat(truncating: $0) } ?? 0 }
        let wx = num("x"), wy = num("y"), ww = num("w"), wh = num("h")
        guard ww > 0, wh > 0 else { return }
        // web (top-left) → screen (bottom-left)
        let f = win.frame
        petScreenRect = CGRect(x: f.minX + wx, y: f.minY + (f.height - (wy + wh)), width: ww, height: wh)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Floor = top of the RetroMac taskbar so the sheep walks ON it.
        let taskbarH = DockController.shared.currentDockFrame()?.height ?? 0
        webView.evaluateJavaScript("window.setGround && window.setGround(\(Int(taskbarH)))")
        loadSpriteSpec { [weak self] spec in
            guard let spec = spec else { return }
            self?.webView?.evaluateJavaScript("window.startPet && window.startPet(\(spec))")
        }
    }

    // MARK: - Sprite: runtime download of the classic sheep (cached), bundled fallback

    private var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RetroMac/Pets/esheep64.b64")
    }

    private func loadSpriteSpec(completion: @escaping (String?) -> Void) {
        if let b64 = try? String(contentsOf: cacheURL, encoding: .utf8), !b64.isEmpty {
            completion(Self.sheepSpec(b64: b64)); return
        }
        guard let url = URL(string: Self.sheepXML) else { completion(fallbackSpec()); return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            var b64: String?
            if let data = data, let xml = String(data: data, encoding: .utf8),
               let a = xml.range(of: "<png>"), let b = xml.range(of: "</png>"), a.upperBound < b.lowerBound {
                b64 = String(xml[a.upperBound..<b.lowerBound])
                    .components(separatedBy: .whitespacesAndNewlines).joined()
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let b64 = b64, !b64.isEmpty {
                    try? FileManager.default.createDirectory(at: self.cacheURL.deletingLastPathComponent(),
                                                             withIntermediateDirectories: true)
                    try? b64.write(to: self.cacheURL, atomically: true, encoding: .utf8)
                    completion(Self.sheepSpec(b64: b64))
                } else {
                    completion(self.fallbackSpec())
                }
            }
        }.resume()
    }

    /// Classic eSheep: 16×11 sprite grid; frame indices taken from the pet's animation table
    /// (walk #1, run #7, drag #4, fall #5, eat #26).
    private static func sheepSpec(b64: String) -> String {
        "{\"name\":\"eSheep\",\"image\":\"data:image/png;base64,\(b64)\",\"tilesx\":16,\"tilesy\":11,\"speed\":38,\"scale\":1.0,\"animations\":{" +
        "\"walk\":{\"frames\":[2,3],\"frameMs\":200,\"loop\":true}," +
        "\"run\":{\"frames\":[5,4,4],\"frameMs\":100,\"loop\":true}," +
        "\"idle\":{\"frames\":[3],\"frameMs\":1000,\"loop\":true}," +
        "\"eat\":{\"frames\":[6,6,6,6,58,59,59,60,61,60,61,6],\"frameMs\":300,\"loop\":true}," +
        "\"fall\":{\"frames\":[133],\"frameMs\":100,\"loop\":true}," +
        "\"held\":{\"frames\":[42,43,43,42,44,44],\"frameMs\":100,\"loop\":true}}}"
    }

    private func fallbackSpec() -> String? {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Widgets/DesktopPet/pets"),
              let json = try? String(contentsOf: dir.appendingPathComponent("retropet.json"), encoding: .utf8) else { return nil }
        return json
    }
}
