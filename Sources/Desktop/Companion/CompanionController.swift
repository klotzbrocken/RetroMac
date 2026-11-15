import AppKit
import SwiftUI

/// Settings ▸ Desktop ▸ Desktop companion. One choice for the sheep and the Office assistants.
struct CompanionPrefs: Codable, Equatable {
    /// "off", "theme" (whatever fits the active theme), "sheep", or an `AgentCatalog` name.
    var character = "off"
    var clipboard = true
    var calendar = false
    var watcher = true
    var tips = true
    var sounds = false
}

/// The Office assistant on the desktop: a character from `AgentCatalog` in a small floating panel,
/// with a yellow balloon for what it has to say and for its three jobs — the clipboard history,
/// a note with to-dos, and the day's meetings and reminders. It also mentions finished downloads,
/// a plugged-in disk, a low battery, a full disk or an old backup, and now and then a Mac tip.
/// No AI and no network: everything it says comes from the Mac.
final class CompanionController: ObservableObject {
    static let shared = CompanionController()

    struct Message {
        var text: String
        var buttons: [(String, () -> Void)] = []
    }
    enum Page {
        case none, message(Message), home, clipboard, notes, agenda([CompanionCalendar.Item])
    }

    @Published var page: Page = .none
    @Published var notes = CompanionNotes.load() { didSet { notes.save() } }
    @Published var downloading: String?
    @Published var tailUp = false
    @Published var tailX: CGFloat = 40

    let clipboard = ClipboardHistory()
    let calendar = CompanionCalendar()
    let watcher = MacWatcher()

    private var panel: AgentPanel?
    private var player: AgentPlayer?
    private var balloon: BalloonPanel?
    private var hideTimer: Timer?
    private var outsideMonitor: Any?
    private var pending: [(Message, AgentCharacter.Moment)] = []
    private var loading: String?

    static let balloonWidth: CGFloat = 270

    private init() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: .dockThemeChanged, object: nil, queue: .main) { [weak self] _ in self?.apply() }
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.placeOnScreen()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.appActivated(app)
        }
        calendar.onSoon = { [weak self] item in self?.meetingSoon(item) }
        calendar.onDue = { [weak self] item in self?.reminderDue(item) }
        watcher.onNotice = { [weak self] n in self?.notice(n) }
    }

    // MARK: - Which character

    /// What "Match the theme" means: Rover on XP when downloaded, Clippy on the other Windows themes.
    static func themeCharacter(_ themeName: String?) -> String? {
        guard let n = themeName?.lowercased(), n.contains("windows") else { return nil }
        if n.contains("windows xp"), AgentCatalog.isAvailable("Rover") { return "Rover" }
        return "Clippy"
    }

    static func resolved(_ choice: String, themeName: String?) -> String? {
        switch choice {
        case "off", "sheep": return nil
        case "theme": return themeCharacter(themeName)
        default: return AgentCatalog.all.contains(choice) ? choice : nil
        }
    }

    var activeName: String? { player?.character.name }

    /// Brings the screen in line with the settings. Called on every change of them and of the theme.
    func apply() {
        let prefs = AppSettings.shared.companion
        let name = Self.resolved(prefs.character, themeName: ThemeManager.shared.activeTheme?.config.name)
        if let name, AgentCatalog.isAvailable(name) {
            if activeName != name { show(name) }
        } else {
            tearDown()
        }
        player?.soundsOn = prefs.sounds
        let on = name != nil
        on && prefs.clipboard ? clipboard.start() : clipboard.stop()
        on && prefs.calendar ? calendar.start() : calendar.stop()
        on && prefs.watcher ? watcher.start() : watcher.stop()
    }

    /// Picks a character in Settings, fetching it first when it is not on this Mac yet.
    func choose(_ choice: String) {
        guard AgentCatalog.downloadable.contains(choice), !AgentCatalog.isAvailable(choice) else {
            AppSettings.shared.companion.character = choice
            return
        }
        downloading = choice
        AgentCatalog.download(choice) { [weak self] ok in
            self?.downloading = nil
            if ok { AppSettings.shared.companion.character = choice }
        }
    }

    private func show(_ name: String) {
        guard loading != name, let dir = AgentCatalog.directory(for: name) else { return }
        loading = name
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let character = AgentCharacter.load(name: name, from: dir)
            DispatchQueue.main.async {
                guard let self, self.loading == name else { return }
                self.loading = nil
                guard let character else { NSLog("[Companion] could not read %@", name); return }
                // The settings may have moved on while it loaded.
                guard Self.resolved(AppSettings.shared.companion.character,
                                    themeName: ThemeManager.shared.activeTheme?.config.name) == name else { return }
                self.present(character)
            }
        }
    }

    private func present(_ character: AgentCharacter) {
        tearDown()
        AgentCharacter.dropCache(except: character.name)
        let player = AgentPlayer(character: character)
        player.soundsOn = AppSettings.shared.companion.sounds
        player.onClick = { [weak self] in self?.clicked() }
        player.onRightClick = { [weak self] e in self?.showMenu(e) }
        player.onMoved = { [weak self] origin in
            UserDefaults.standard.set([origin.x, origin.y], forKey: "companionOrigin")
            self?.positionBalloon()
        }
        let p = AgentPanel(contentRect: NSRect(origin: .zero, size: character.frameSize),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: 25)   // above the RetroMac taskbar (24), like the sheep
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView = player
        p.setFrameOrigin(startOrigin(size: character.frameSize))
        p.orderFrontRegardless()
        panel = p
        self.player = player
        player.play(.show) { [weak player] in player?.play(.greet) }
    }

    private func tearDown() {
        loading = nil
        closeBalloon()
        pending.removeAll()
        player?.stop()
        panel?.orderOut(nil)
        panel = nil
        player = nil
        AgentCharacter.dropCache(except: nil)
    }

    /// Where it stood last time, if that is still on a screen; otherwise bottom right, above the taskbar.
    private func startOrigin(size: CGSize) -> NSPoint {
        if let xy = UserDefaults.standard.array(forKey: "companionOrigin") as? [Double], xy.count == 2 {
            let r = NSRect(x: xy[0], y: xy[1], width: size.width, height: size.height)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(r.insetBy(dx: size.width / 3, dy: size.height / 3)) }) {
                return r.origin
            }
        }
        guard let vf = NSScreen.main?.visibleFrame else { return .zero }
        let taskbar = DockController.shared.currentDockFrame()?.height ?? 0
        return NSPoint(x: vf.maxX - size.width - 40, y: vf.minY + taskbar + 40)
    }

    private func placeOnScreen() {
        guard let p = panel else { return }
        p.setFrameOrigin(startOrigin(size: p.frame.size))
        positionBalloon()
    }

    // MARK: - Talking

    /// Says something with a matching animation. While a page the user opened is up, it waits.
    func say(_ text: String, _ moment: AgentCharacter.Moment = .explain, buttons: [(String, () -> Void)] = []) {
        guard player != nil else { return }
        let m = Message(text: text, buttons: buttons)
        switch page {
        case .home, .clipboard, .notes, .agenda: pending.append((m, moment)); return
        default: break
        }
        player?.play(moment)
        open(.message(m))
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "\(AgentCatalog.title(activeName ?? "")): \(text)",
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: buttons.isEmpty ? 12 : 40, repeats: false) { [weak self] _ in
            guard let self, self.balloon?.frame.contains(NSEvent.mouseLocation) != true else {
                self?.hideTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in self?.closeBalloon() }
                return
            }
            self.closeBalloon()
        }
    }

    private func clicked() {
        switch page {
        case .none, .message: open(.home)
        default: closeBalloon()
        }
    }

    func open(_ page: Page) {
        if case .message = page {} else { hideTimer?.invalidate() }
        self.page = page
        if balloon == nil {
            let b = BalloonPanel(contentRect: NSRect(x: 0, y: 0, width: Self.balloonWidth, height: 80),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            b.isOpaque = false
            b.backgroundColor = .clear
            b.hasShadow = false
            b.level = NSWindow.Level(rawValue: 25)
            b.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            b.contentView = NSHostingView(rootView: CompanionBalloonView(model: self))
            balloon = b
        }
        if case .message = page {} else { player?.play(page.moment) }
        DispatchQueue.main.async { [weak self] in self?.positionBalloon() }   // after SwiftUI laid out
        balloon?.orderFrontRegardless()
        if outsideMonitor == nil {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self else { return }
                if case .message = self.page { return }   // messages time out by themselves
                self.closeBalloon()
            }
        }
    }

    func makeBalloonKey() { balloon?.makeKey() }

    func closeBalloon() {
        hideTimer?.invalidate()
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        balloon?.orderOut(nil)
        page = .none
        if !pending.isEmpty {
            let (m, moment) = pending.removeFirst()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.say(m.text, moment, buttons: m.buttons) }
        }
    }

    /// Above the character with the tail pointing down at it, or below it where the top has no room.
    func positionBalloon() {
        guard let b = balloon, let agent = panel?.frame, let content = b.contentView else { return }
        let size = content.fittingSize
        let screen = (panel?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let up = agent.maxY + size.height + 4 > screen.maxY
        var x = agent.midX - size.width / 2
        x = min(max(x, screen.minX + 4), screen.maxX - size.width - 4)
        let y = up ? agent.minY - size.height - 2 : agent.maxY + 2
        if tailUp != up { tailUp = up }
        let tx = min(max(agent.midX - x, 24), size.width - 24)
        if abs(tailX - tx) > 0.5 { tailX = tx }
        b.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    // MARK: - Menu

    private func showMenu(_ event: NSEvent) {
        let menu = NSMenu()
        func item(_ title: String, _ action: @escaping () -> Void) {
            let i = NSMenuItem(title: title, action: #selector(MenuAction.run(_:)), keyEquivalent: "")
            let a = MenuAction(action)
            i.target = a
            i.representedObject = a
            menu.addItem(i)
        }
        item("Animate!") { [weak self] in
            guard let c = self?.player?.character else { return }
            let skip: Set<String> = ["Show", "Hide", "RestPose"]
            self?.player?.play(c.animations.keys.filter { !skip.contains($0) && !$0.hasPrefix("Idle") }.randomElement())
        }
        menu.addItem(.separator())
        item("Clipboard") { [weak self] in self?.open(.clipboard) }
        item("Notes") { [weak self] in self?.open(.notes) }
        item("Today") { [weak self] in self?.showAgenda() }
        menu.addItem(.separator())
        let choose = NSMenuItem(title: "Choose Assistant", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for name in AgentCatalog.all where AgentCatalog.isAvailable(name) {
            let i = NSMenuItem(title: AgentCatalog.title(name), action: #selector(MenuAction.run(_:)), keyEquivalent: "")
            let a = MenuAction { AppSettings.shared.companion.character = name }
            i.target = a; i.representedObject = a
            i.state = name == activeName ? .on : .off
            sub.addItem(i)
        }
        choose.submenu = sub
        menu.addItem(choose)
        item("Options…") { AppDelegate.shared?.showSettings(tab: .desktop) }
        menu.addItem(.separator())
        item("Hide Assistant") { [weak self] in
            self?.closeBalloon()
            self?.player?.play(.hide) { AppSettings.shared.companion.character = "off" }
        }
        if let view = player { NSMenu.popUpContextMenu(menu, with: event, for: view) }
    }

    func showAgenda() {
        guard CompanionCalendar.authorized else {
            say(AppSettings.shared.companion.calendar || CompanionCalendar.denied
                ? "I may not look at your calendar. Allow RetroMac under Privacy & Security ▸ Calendars and Reminders."
                : "Switch on Calendar & reminders in Settings ▸ Desktop and I'll keep an eye on your day.", .think,
                buttons: [("Options…", { AppDelegate.shared?.showSettings(tab: .desktop) })])
            return
        }
        calendar.today { [weak self] items in self?.open(.agenda(items)) }
    }

    // MARK: - What happens on the Mac

    private func meetingSoon(_ item: CompanionCalendar.Item) {
        let mins = max(1, Int(((item.start ?? Date()).timeIntervalSinceNow / 60).rounded()))
        var buttons: [(String, () -> Void)] = []
        if let link = item.link { buttons.append(("Join", { NSWorkspace.shared.open(link) })) }
        buttons.append(("Snooze", { [weak self] in self?.calendar.snooze(item, minutes: Double(max(1, mins - 2))) }))
        say("In \(mins) minute\(mins == 1 ? "" : "s"): \(item.title)", .search, buttons: buttons)
    }

    private func reminderDue(_ item: CompanionCalendar.Item) {
        say("Reminder: \(item.title)", .alert, buttons: [
            ("Done", { [weak self] in self?.calendar.complete(item); self?.player?.play(.congratulate) }),
            ("Later", { [weak self] in self?.calendar.snooze(item, minutes: 15) }),
        ])
    }

    private func notice(_ n: MacWatcher.Notice) {
        switch n {
        case .downloaded(let urls):
            guard let first = urls.first else { return }
            let text = urls.count == 1 ? "Your download is ready: \(first.lastPathComponent)" : "\(urls.count) downloads are ready."
            var buttons: [(String, () -> Void)] = []
            if urls.count == 1 { buttons.append(("Open", { NSWorkspace.shared.open(first) })) }
            buttons.append(("Show in Finder", { NSWorkspace.shared.activateFileViewerSelecting(urls) }))
            say(text, .congratulate, buttons: buttons)
        case .mounted(let url):
            say("\(FileManager.default.displayName(atPath: url.path)) is connected.", .alert, buttons: [
                ("Open", { NSWorkspace.shared.open(url) }),
                ("Eject", { try? NSWorkspace.shared.unmountAndEjectDevice(at: url) }),
            ])
        case .battery(let pct):
            say("The battery is down to \(pct) %. Time for the charger!", .alert)
        case .diskFull(let free):
            let text = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            say("Your disk is nearly full: only \(text) left. Shall we empty the Trash?", .trash, buttons: [
                ("Storage Settings", { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!) }),
            ])
        case .oldBackup(let days):
            say("Your last Time Machine backup was \(days) days ago.", .think, buttons: [
                ("Time Machine Settings", { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension")!) }),
            ])
        }
    }

    private func appActivated(_ app: NSRunningApplication) {
        guard player != nil, AppSettings.shared.companion.tips, case .none = page,
              let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
              let tip = CompanionTips.next(for: id) else { return }
        say(tip, .explain, buttons: [
            ("Thanks", { [weak self] in self?.closeBalloon() }),
            ("No more tips", { AppSettings.shared.companion.tips = false }),
        ])
    }
}

private extension CompanionController.Page {
    var moment: AgentCharacter.Moment {
        switch self {
        case .clipboard: return .clipboard
        case .notes: return .write
        case .agenda: return .search
        default: return .explain
        }
    }
}

/// An NSMenuItem target that runs a closure (the menu holds it through representedObject).
final class MenuAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run(_ sender: Any?) { action() }
}

/// Takes the keyboard for the note field without bringing RetroMac to the front.
final class BalloonPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
