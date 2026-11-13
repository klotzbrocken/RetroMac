import AppKit
import WebKit

/// Settings ▸ Themes ▸ Screensaver ▸ SETI@home. Retromac's choices, outside the historical
/// screen (spec 9.1).
struct SETIPrefs: Codable, Equatable {
    enum Processing: String, Codable, CaseIterable { case whenIdle, always }
    var userName = "Retromac"
    var processing = Processing.whenIdle
    var speed = SETISimulation.Speed.historical
    var candidates = true
    var frequency = SETISimulation.Frequency.standard
    /// "auto" follows the theme; "windows", "mac", "macosx" force a client.
    var profile = "auto"
    /// The clients' network setting: connect when needed, or ask first.
    var askBeforeConnecting = false
    var proxyHost = ""
    var proxyPort = ""
    /// Mac screensaver option: blank the screen after so many minutes; 0 = never.
    var blankAfterMinutes = 0
    /// Mac OS X: Preferences and Login on the first start have been through.
    var osxSetupDone = false
}

/// The one SETI@home client in RetroMac. It owns the simulation and every view of it — the
/// themed window, the screensaver on each screen — so they all show the same work unit
/// (spec 2.1, SCR-06). It saves the state to Application Support, runs it only while someone
/// watches (or always, if the user chose so), never while the Mac sleeps, and draws nothing
/// itself: the views get a small snapshot ten times a second and draw from it.
final class SETIController: NSObject, WKScriptMessageHandler {

    static let shared = SETIController()

    private(set) var state: SETIState
    /// The saved state could not be read and a fresh one took its place (spec 9.3).
    private(set) var recovered = false
    private let fileURL: URL
    private var windowViews = NSHashTable<WKWebView>.weakObjects()
    private var saverViews = NSHashTable<WKWebView>.weakObjects()
    private var timer: Timer?
    private var lastTick = Date()
    private var lastSave = Date()
    private var asleep = false
    private var windowWanted = false
    private var telescope: NSStatusItem?
    private var blinkOn = false
    private var tokens: [NSObjectProtocol] = []

    private override init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RetroMac")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("seti-state.json")
        (state, recovered) = Self.load(from: fileURL)
        super.init()
    }

    static func load(from url: URL) -> (SETIState, recovered: Bool) {
        guard let data = try? Data(contentsOf: url) else { return (SETIState(seed: UInt64.random(in: 1...UInt64.max)), false) }
        if let s = try? JSONDecoder().decode(SETIState.self, from: data), s.version == SETIState.formatVersion { return (s, false) }
        return (SETIState(seed: UInt64.random(in: 1...UInt64.max)), true)
    }

    private func save() {
        lastSave = Date()
        guard let data = try? JSONEncoder().encode(state) else { return }
        do { try data.write(to: fileURL, options: .atomic) } catch { print("[SETI] Could not save: \(error)") }
    }

    // MARK: Lifecycle

    /// From launch: sleep and lock stop the clock, quitting saves, the telescope follows the theme.
    func start() {
        guard tokens.isEmpty else { return }
        let ws = NSWorkspace.shared.notificationCenter
        for (name, sleeping) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false),
                                 (NSWorkspace.sessionDidResignActiveNotification, true),
                                 (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
            tokens.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.setAsleep(sleeping) })
        }
        let dist = DistributedNotificationCenter.default()
        tokens.append(dist.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.setAsleep(true) })
        tokens.append(dist.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.setAsleep(false) })
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.save() })
        tokens.append(NotificationCenter.default.addObserver(forName: .dockThemeChanged, object: nil, queue: .main) { [weak self] _ in self?.themeChanged() })
        updateTelescope()
        updateTimer()
    }

    private func setAsleep(_ a: Bool) {
        asleep = a
        lastTick = Date()   // sleep time is no processing time (spec 8.3)
        updateTimer()
    }

    /// The themed window closes on a theme switch (WebAppController); the client comes back in
    /// the new theme's dress with the same unit (AB-16).
    private func themeChanged() {
        updateTelescope()
        guard windowWanted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.showWindow() }
    }

    // MARK: Profiles

    /// Which client the views draw: Windows 3.08, Classic Mac 2.01, or Mac OS X (reconstructed).
    var profile: String {
        let p = AppSettings.shared.seti.profile
        if p != "auto" { return p }
        switch RetroFrameTheme.key() {
        case "system7", "macos9", "macos6": return "mac"
        case "macosx", "snowleopard": return "macosx"
        default: return "windows"
        }
    }

    // MARK: Window

    func showWindow() {
        guard let html = Bundle.main.resourceURL?.appendingPathComponent("Widgets/SETI/SETI.html") else { return }
        windowWanted = true
        let mac = profile != "windows"
        WebAppController.open(name: mac ? "SETI@home Client" : "SETI@Home Client", url: html.path,
                              width: mac ? 769 : 760, height: mac ? 478 : 491, icon: "seti.png", titleOnly: true, messageHandler: ("seti", self))
    }

    /// The screensaver's web view on each screen (ScreensaverController).
    func attachSaver(_ wv: WKWebView) { saverViews.add(wv) }

    /// The saver is gone: back to the desktop. Mac OS X told the user then if the client
    /// waited to connect (OSX-02).
    func saverEnded() {
        saverViews.removeAllObjects()
        updateTimer()
        if state.awaitingConnection, profile == "macosx" {
            let a = NSAlert()
            a.messageText = "SETI@home needs to connect to the server."
            a.informativeText = "This is a simulation: connecting only moves the simulated work unit on. Nothing is sent anywhere."
            a.addButton(withTitle: "Connect"); a.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if a.runModal() == .alertFirstButtonReturn { connect() }
        }
    }

    // MARK: Commands

    func setPaused(_ p: Bool) { state.paused = p; save(); push(); updateTimer() }
    func connect() { SETISimulation.connect(&state); push() }
    func forceCandidate() { if !state.started { state.started = true }; SETISimulation.stageFind(&state); push() }
    func resetStatistics() { state.unitsDone = 0; state.totalCPU = state.unitCPU; save(); push() }

    // MARK: Messages from the page

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "seti", let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else { return }
        switch cmd {
        case "hello":
            if let wv = message.webView, !saverViews.contains(wv) { windowViews.add(wv) }
            if !state.started, !(profile == "macosx" && !AppSettings.shared.seti.osxSetupDone) { state.started = true }
            updateTimer(); push()
        case "pause": setPaused(true)
        case "resume": setPaused(false)
        case "connect": connect()
        case "saver": ScreensaverController.shared.start(saverID: "seti")
        case "login":
            if let name = body["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                AppSettings.shared.seti.userName = String(name.prefix(40))
            }
            push()
        case "prefs":
            var p = AppSettings.shared.seti
            if let v = body["ask"] as? Bool { p.askBeforeConnecting = v }
            if let v = body["proxyHost"] as? String { p.proxyHost = String(v.prefix(80)) }
            if let v = body["proxyPort"] as? String { p.proxyPort = String(v.filter(\.isNumber).prefix(5)) }
            if let v = body["blank"] as? Int { p.blankAfterMinutes = max(0, min(60, v)) }
            AppSettings.shared.seti = p
            push()
        case "error": print("[SETI] page: \(body["message"] ?? "")")
        case "setupDone":
            AppSettings.shared.seti.osxSetupDone = true
            state.started = true
            updateTimer(); push()
        default: break
        }
    }

    // MARK: The clock

    private var views: [WKWebView] { windowViews.allObjects + saverViews.allObjects }
    private var someoneWatches: Bool {
        !saverViews.allObjects.isEmpty || windowViews.allObjects.contains { $0.window?.occlusionState.contains(.visible) == true }
    }
    private var shouldRun: Bool {
        guard state.started, !state.paused, !asleep else { return false }
        return AppSettings.shared.seti.processing == .always || someoneWatches
    }

    /// Ten ticks a second while a view is up, one in the background, none otherwise.
    private func updateTimer() {
        let interval: TimeInterval? = !views.isEmpty ? 0.1 : (shouldRun ? 1 : nil)
        if timer?.timeInterval == interval { return }
        timer?.invalidate(); timer = nil
        guard let interval else { return }
        lastTick = Date()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        if shouldRun {
            let p = AppSettings.shared.seti
            SETISimulation.advance(&state, by: dt, visible: someoneWatches, speed: p.speed, candidates: p.candidates,
                                   frequency: p.frequency, askBeforeConnecting: p.askBeforeConnecting)
        }
        if now.timeIntervalSince(lastSave) > 15 { save() }
        blinkOn = Int(now.timeIntervalSince1970 * 2) % 2 == 0   // once a second
        if state.awaitingConnection || telescopeBlinking { refreshTelescopeImage() }
        push()
        if views.isEmpty { updateTimer() }
    }

    // MARK: Snapshot

    /// Everything a view needs to draw this moment, small and flat.
    func snapshot() -> [String: Any] {
        let s = state, p = AppSettings.shared.seti
        let ph = SETISimulation.phase(s)
        func cand(_ c: SETIState.Candidate?) -> Any {
            guard let c else { return NSNull() }
            return ["kind": c.kind.rawValue, "power": c.power, "score": c.score, "period": c.period,
                    "f": c.frequency, "t": c.time, "seed": Double(c.seed % 1_000_000_007),
                    "age": c.appearedAt.map { s.visibleSeconds - $0 } ?? -1]
        }
        return [
            "profile": profile, "theme": RetroFrameTheme.key(), "started": s.started, "paused": s.paused, "awaiting": s.awaitingConnection,
            "step": ph.step.rawValue, "stepProgress": s.phaseProgress, "pass": ph.pass,
            "transfer": ph.step.isTransfer, "overall": SETISimulation.overall(s),
            "drift": SETISimulation.drift(s), "resolution": SETISimulation.resolution(s),
            "unitCPU": s.unitCPU, "spectrumSeed": Double((s.seed ^ UInt64(s.unitIndex)) % 1_000_000_007),
            "unit": ["ra": s.unit.raHours, "dec": s.unit.decDegrees, "recorded": s.unit.recordedAt.timeIntervalSince1970,
                     "source": s.unit.source, "base": s.unit.baseFrequencyHz, "id": s.unit.id],
            "user": ["name": p.userName, "units": s.unitsDone, "cpu": s.totalCPU],
            "best": ["gaussian": cand(s.best["gaussian"]), "pulse": cand(s.best["pulse"]),
                     "triplet": cand(s.best["triplet"]), "spike": cand(s.best["spike"])],
            "current": cand(s.current),
            "prefs": ["ask": p.askBeforeConnecting, "proxyHost": p.proxyHost, "proxyPort": p.proxyPort,
                      "blank": p.blankAfterMinutes, "osxSetupDone": p.osxSetupDone],
        ]
    }

    private func push() {
        guard !views.isEmpty, let data = try? JSONSerialization.data(withJSONObject: snapshot()),
              let json = String(data: data, encoding: .utf8) else { return }
        for wv in windowViews.allObjects { wv.evaluateJavaScript("window.setiState && setiState(\(json), false)") }
        for wv in saverViews.allObjects { wv.evaluateJavaScript("window.setiState && setiState(\(json), true)") }
    }

    // MARK: The telescope in the menu bar (Classic Mac clients)

    /// The Mac clients' green radio telescope in the menu bar, with Launch (MAC-01). Only in
    /// the Mac themes with their own Apple menu, so Mac OS 9.2 Classic stays as it is.
    func updateTelescope() {
        let theme = ThemeManager.shared.activeTheme?.config
        let wanted = AppSettings.shared.dockEnabled && !AppSettings.shared.hideMenuBar
            && theme?.hasAppleMenu == true && ["system7", "macos9", "macosx"].contains(RetroFrameTheme.key())
        if !wanted {
            if let telescope { NSStatusBar.system.removeStatusItem(telescope) }
            telescope = nil
            return
        }
        guard telescope == nil else { return }
        let i = NSStatusBar.system.statusItem(withLength: 24)
        i.button?.toolTip = "SETI@home"
        i.button?.setAccessibilityLabel("SETI@home")
        i.button?.target = self
        i.button?.action = #selector(openTelescopeMenu)
        telescope = i
        refreshTelescopeImage()
    }

    private var telescopeBlinking: Bool { telescope?.button?.alphaValue != 1 }

    /// Blinks while a transfer waits for "Connect" — attention, never a find (MAC-07).
    private func refreshTelescopeImage() {
        guard let button = telescope?.button else { return }
        if button.image == nil { button.image = Self.telescopeImage() }
        button.alphaValue = state.awaitingConnection && blinkOn ? 0.25 : 1
    }

    @objc private func openTelescopeMenu() {
        guard let button = telescope?.button, let window = button.window else { return }
        let menu = PlatinumMenuController.shared
        if menu.isOpen { menu.dismissAll(); return }
        var rows: [PlatinumMenuItem] = [.action("Launch") { [weak self] in self?.showWindow() }]
        if state.awaitingConnection { rows.append(.action("Connect") { [weak self] in self?.connect() }) }
        rows += [
            .action(state.paused ? "Resume" : "Pause") { [weak self] in guard let self else { return }; self.setPaused(!self.state.paused) },
            .separator(),
            .action("Preferences\u{2026}") { [weak self] in self?.openDialog("prefs") },
            .action("Change/Create Login\u{2026}") { [weak self] in self?.openDialog("login") },
        ]
        menu.ignoreClickWindow = window
        menu.show(rows, below: window.convertToScreen(button.convert(button.bounds, to: nil)))
    }

    /// Opens the window and has the page show one of its dialogs.
    private func openDialog(_ name: String) {
        showWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.windowViews.allObjects.forEach { $0.evaluateJavaScript("window.setiDialog && setiDialog('\(name)')") }
        }
    }

    /// The green dish on its stand, drawn (16 pt).
    static func telescopeImage() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 16))
        img.lockFocus()
        let green = NSColor(srgbRed: 0, green: 0.6, blue: 0.2, alpha: 1)
        NSColor.black.setStroke()
        let dish = NSBezierPath(ovalIn: NSRect(x: 2, y: 6, width: 13, height: 8))
        green.setFill(); dish.fill(); dish.lineWidth = 1; dish.stroke()
        let stand = NSBezierPath()
        stand.move(to: NSPoint(x: 8.5, y: 7)); stand.line(to: NSPoint(x: 5, y: 1))
        stand.move(to: NSPoint(x: 8.5, y: 7)); stand.line(to: NSPoint(x: 12, y: 1))
        stand.move(to: NSPoint(x: 8.5, y: 10)); stand.line(to: NSPoint(x: 14, y: 14))
        stand.lineWidth = 1.2; stand.stroke()
        img.unlockFocus()
        return img
    }
}
