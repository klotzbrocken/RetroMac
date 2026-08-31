import SwiftUI
import AppKit
import ScreenCaptureKit

/// Post-install configuration wizard. Walks the user through how RetroMac should behave.
/// Options are grouped onto a few pages (Appearance / System / Permissions) rather than
/// one-question-per-screen. Re-runnable any time from the menu or Settings ▸ Overview.
///
/// Toggles bind directly to AppSettings, so changes apply live via the existing `didSet`
/// side-effects (hide icons, hide menu bar, login item, dock mode, …).
private enum WizardPage: Int, CaseIterable {
    case intro
    case appearance
    // Theme first, then its shortcuts: the Desktop page lists what the ACTIVE theme puts on the
    // desktop, and every theme puts something different there. Asking before the theme is picked
    // showed the outgoing theme's list, or nothing at all.
    case theme
    case desktop
    case games
    case system
    case permissions
    case getMore
    case done
}

/// One selectable PC game on the Setup Assistant's Games page: a data-folder picker + an
/// optional themed desktop shortcut (DesktopStore.added entry of `shortcutType`).
private struct WizardGame: Identifiable {
    let id: String            // shortcut type ("doom","duke3d","quake","quake2","warcraft2","warcraft1")
    let name: String
    let dataHint: String      // what folder to pick
    let hasData: () -> Bool
    let choose: () -> Void
}

struct SetupWizardView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var page: WizardPage = .intro
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false
    @State private var reframeInstalled = SetupWizardView.isReframeInstalled()

    // Games page
    @State private var gamesSetup = false
    @State private var addShortcut: [String: Bool] = [:]   // shortcut type → create a themed desktop icon
    @State private var wcStatus: [String: String] = [:]    // Warcraft extraction status per title
    @State private var dataTick = 0                        // bump to re-read folder settings after a pick
    @State private var desktopTick = 0                     // ditto for the desktop shortcut list

    // Theme page — which theme to switch to on finish ("" = keep current)
    @State private var selectedTheme: String = ThemeManager.shared.activeTheme?.config.name ?? ""

    /// Called when the user finishes or skips the wizard.
    let onFinish: () -> Void

    private static let reframeURL = "https://myretromac.app/reframe"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .padding(.horizontal, 28)
                    .padding(.top, 26)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
        }
        // Same window as the What's New flow, which runs straight after this one on a first
        // launch. Two sizes made them read as two unrelated windows instead of one flow.
        .frame(width: WelcomePage.windowWidth, height: WelcomePage.windowHeight)
        .onAppear { refreshPermissions() }
    }

    // MARK: - Pages

    @ViewBuilder private var content: some View {
        switch page {
        case .intro:       introPage
        case .appearance:  appearancePage
        case .desktop:     desktopPage
        case .games:       gamesPage
        case .system:      systemPage
        case .permissions: permissionsPage
        case .getMore:     GetMoreView()
        case .theme:       themePage
        case .done:        donePage
        }
    }

    private var introPage: some View {
        VStack(alignment: .center, spacing: 14) {
            Spacer(minLength: 12)
            Image(systemName: "wand.and.stars")
                .font(.system(size: 46)).foregroundStyle(.tint)
            Text("Welcome to RetroMac").font(.title.bold())
            Text("Let’s set up how RetroMac looks and behaves. Just a few choices — change any of them later in Settings, or re-run this assistant from the menu.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                introBullet("paintbrush", "Appearance — desktop, shader, menu bar, widgets")
                introBullet("gamecontroller", "Games — Doom, Quake, Duke Nukem & Warcraft")
                introBullet("gearshape.2", "System — Dock Mode, start at login, Reframe")
                introBullet("lock.shield", "Permissions — screen recording & accessibility")
                introBullet("paintbrush.pointed", "Theme — pick the look to start with")
            }
            .padding(.top, 6)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity)
    }

    private func introBullet(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.tint).frame(width: 20)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var appearancePage: some View {
        pageScaffold(icon: "paintbrush.fill", tint: .blue, title: "Appearance",
                     subtitle: "How a theme changes your desktop.") {
            toggleRow(icon: "menubar.dock.rectangle", tint: .blue,
                      title: "Hide original desktop icons",
                      subtitle: "Recommended — hides your real icons while a theme is on.",
                      isOn: $settings.hideDesktopIcons)
            Divider()
            toggleRow(icon: "tv.inset.filled", tint: .purple,
                      title: "Shader on theme change",
                      subtitle: "Turn on a theme’s CRT shader automatically.",
                      isOn: $settings.shaderOnThemeChange)
            Divider()
            toggleRow(icon: "film.fill", tint: .teal,
                      title: "Boot animation on theme change",
                      subtitle: "Play a theme’s boot screen (like the Mac OS X startup) when you switch to it. Off by default.",
                      isOn: $settings.showSplashScreen)
            Divider()
            toggleRow(icon: "menubar.rectangle", tint: .orange,
                      title: "Hide the macOS menu bar",
                      subtitle: "Show it again by moving the pointer to the top of the screen.",
                      isOn: $settings.hideMenuBar)
            Divider()
            toggleRow(icon: "square.grid.2x2", tint: .green,
                      title: "Also apply theme widgets",
                      subtitle: "On = Dock, Wallpaper & widgets (desktop Clock). Off = Dock & Wallpaper only.",
                      isOn: $settings.themeIncludeWidgets)
            Divider()
            toggleRow(icon: "paintpalette.fill", tint: .pink,
                      title: "Match colour scheme",
                      subtitle: "Set the macOS appearance & accent colour to fit the theme (e.g. Graphite). Your own settings are restored when the theme goes off.",
                      isOn: $settings.themeAdaptAppearance)
            Divider()
            toggleRow(icon: "cursorarrow.rays", tint: .indigo,
                      title: "Match cursor",
                      subtitle: "Replace the system-wide mouse cursor with the theme's set (classic Mac, XP, …). Your normal cursor returns afterwards.",
                      isOn: $settings.themeAdaptCursor)
        }
    }

    // MARK: - Games page

    private var gamesList: [WizardGame] {
        _ = dataTick   // re-read folder settings after a pick
        return [
            WizardGame(id: "doom", name: "Doom", dataHint: "Pick your WAD folder (also enables Heretic & Freedoom).",
                       hasData: { Self.doomHasData(AppSettings.shared.doomWadFolder) },
                       choose: { chooseFolder("Select the folder with your Doom WAD files") { AppSettings.shared.doomWadFolder = $0 } }),
            WizardGame(id: "duke3d", name: "Duke Nukem 3D", dataHint: "Pick your GRP folder (also enables Shadow Warrior).",
                       hasData: { Self.folderHasFile(AppSettings.shared.razeGrpFolder) { $0.lowercased().hasSuffix(".grp") } },
                       choose: { chooseFolder("Select the folder with your Duke Nukem 3D GRP files") { AppSettings.shared.razeGrpFolder = $0 } }),
            WizardGame(id: "quake", name: "Quake", dataHint: "Pick the base folder (contains id1/PAK0.PAK).",
                       hasData: { Self.quakeHasData(AppSettings.shared.quakeBasePath, sub: "id1") },
                       choose: { chooseFolder("Select your Quake base directory (id1/PAK0.PAK)") { AppSettings.shared.quakeBasePath = $0 } }),
            WizardGame(id: "quake2", name: "Quake II", dataHint: "Pick the base folder (contains baseq2/pak0.pak).",
                       hasData: { Self.quakeHasData(AppSettings.shared.quake2BasePath, sub: "baseq2") },
                       choose: { chooseFolder("Select your Quake II base directory (baseq2/pak0.pak)") { AppSettings.shared.quake2BasePath = $0 } }),
            // Only Warcraft II: RetroMac can extract + run it (proven working). Warcraft I (war1gus)
            // has no bundled extractor and isn't reliably playable, so it stays in Settings ▸ Games
            // for advanced users rather than being offered — and shortcut-launched — here.
            WizardGame(id: "warcraft2", name: "Warcraft II", dataHint: "Pick your Warcraft II folder (the game or extracted data).",
                       hasData: { WarcraftGame.hasExtractedData(.warcraft2) }, choose: { chooseWarcraft(.warcraft2) }),
        ]
    }

    // Game-data validation — a non-empty folder path is not enough; check for the actual files so
    // a green tick / desktop shortcut never promises a game that can't launch (Warcraft already
    // validates via WarcraftGame.hasExtractedData).
    static func folderHasFile(_ folder: String, matching: (String) -> Bool) -> Bool {
        guard !folder.isEmpty,
              let items = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return false }
        return items.contains(where: matching)
    }
    static func doomHasData(_ folder: String) -> Bool {
        folderHasFile(folder) { let l = $0.lowercased(); return l.hasSuffix(".wad") || l.hasSuffix(".pk3") || l.hasSuffix(".ipk3") }
    }
    /// Quake / Quake II: `base/<sub>/pak0.pak` (case-insensitive), or `pak0.pak` in the picked folder.
    static func quakeHasData(_ base: String, sub: String) -> Bool {
        guard !base.isEmpty else { return false }
        let fm = FileManager.default
        func hasPak(_ dir: String) -> Bool {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return false }
            return items.contains { $0.lowercased() == "pak0.pak" }
        }
        if let subs = try? fm.contentsOfDirectory(atPath: base),
           let match = subs.first(where: { $0.lowercased() == sub }),
           hasPak((base as NSString).appendingPathComponent(match)) {
            return true
        }
        return hasPak(base)
    }

    /// Which of the active theme's desktop shortcuts are on. Writes to the same per-theme store
    /// the desktop itself reads (`DesktopStore.removed`), so a choice here is the same choice as
    /// hiding an icon on the desktop later.
    private var desktopPage: some View {
        pageScaffold(icon: "square.grid.2x2.fill", tint: .green, title: "Desktop",
                     subtitle: themeForDesktop == nil
                        ? "Activate a theme first and its shortcuts will be listed here."
                        : "Which shortcuts \(themeForDesktop?.config.name ?? "") puts on your desktop.") {
            if let theme = themeForDesktop, !(theme.config.desktopIcons ?? []).isEmpty {
                ForEach(Array((theme.config.desktopIcons ?? []).enumerated()), id: \.offset) { i, icon in
                    if i > 0 { Divider() }
                    toggleRow(icon: desktopSymbol(for: icon.type), tint: .green,
                              title: icon.name,
                              subtitle: desktopHint(for: icon.type),
                              isOn: Binding(
                                get: { !desktopRemoved.contains(icon.name) },
                                set: { on in
                                    var c = DesktopStore.load(theme: theme.config.settingsKey)
                                    c.removed.removeAll { $0 == icon.name }
                                    if !on { c.removed.append(icon.name) }
                                    DesktopStore.save(c, theme: theme.config.settingsKey)
                                    desktopTick += 1
                                    DesktopIconsController.shared.update()
                                }))
                }
            } else {
                Text("Nothing to configure yet.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// The theme picked on the previous page, not the one currently running. The chosen theme is
    /// only applied when the assistant finishes, so reading the active one here would have listed
    /// the outgoing theme's shortcuts however the pages were ordered.
    private var themeForDesktop: ThemeBundle? {
        if !selectedTheme.isEmpty, let t = ThemeManager.shared.theme(for: selectedTheme) { return t }
        return ThemeManager.shared.activeTheme
    }
    private var desktopRemoved: [String] {
        _ = desktopTick   // re-read after a toggle
        guard let t = themeForDesktop else { return [] }
        return DesktopStore.load(theme: t.config.settingsKey).removed
    }

    /// Covers every `type` the shipped manifests use; anything new falls back to a plain tile
    /// rather than pretending to know what it is.
    private func desktopSymbol(for type: String) -> String {
        switch type {
        case "folder", "appfolder", "funstuff": return "folder.fill"
        case "tvfolder":            return "play.tv.fill"
        case "trash":               return "trash.fill"
        case "clock":               return "clock.fill"
        case "cpumonitor":          return "chart.bar.fill"
        case "calculator":          return "plusminus.circle.fill"
        case "notepad":             return "note.text"
        case "defrag":              return "internaldrive.fill"
        case "screensaver":         return "sparkles.tv.fill"
        case "dashboard":           return "square.grid.2x2.fill"
        case "expose":              return "rectangle.3.group.fill"
        case "readme":              return "doc.text.fill"
        case "sheep":               return "hare.fill"
        case "pacman", "tictactoe", "nyanochrome": return "gamecontroller.fill"
        case "webapp", "localapp":  return "macwindow"
        case "network":             return "network"
        case "url":                 return "globe"
        case "app":                 return "app.fill"
        default:                    return "square.dashed"
        }
    }

    private func desktopHint(for type: String) -> String {
        switch type {
        case "folder", "appfolder", "funstuff": return "Opens a folder window."
        case "tvfolder":            return "The theme's TV window."
        case "trash":               return "The theme's wastebasket."
        case "clock":               return "A desktop clock."
        case "cpumonitor":          return "A live CPU meter."
        case "calculator":          return "A period calculator."
        case "notepad":             return "A period notepad."
        case "defrag":              return "The disk defragmenter."
        case "screensaver":         return "Starts the theme's screensaver."
        case "dashboard":           return "The widget layer."
        case "expose":              return "Shows every window at once."
        case "readme":              return "About this theme."
        case "sheep":               return "The desktop pet."
        case "pacman", "tictactoe", "nyanochrome": return "A little game."
        case "webapp", "localapp":  return "Opens in a themed window."
        case "network":             return "Jumps to Network in the Finder."
        case "url":                 return "Opens a web page."
        default:                    return "A desktop shortcut."
        }
    }

    private var gamesPage: some View {
        pageScaffold(icon: "gamecontroller.fill", tint: .green, title: "Games",
                     subtitle: "Play classic PC games with your own game files.") {
            toggleRow(icon: "gamecontroller", tint: .green, title: "Set up games",
                      subtitle: "Point RetroMac at the games you own — and optionally add a desktop shortcut for the active theme.",
                      isOn: $gamesSetup)
            if gamesSetup {
                ForEach(gamesList) { g in
                    Divider()
                    gameRow(g)
                }
                Text("RetroMac only ships the open-source engines / game logic — the games themselves must come from your own copy. Doom and Duke Nukem also need GZDoom / Raze installed (Settings ▸ Games).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func gameRow(_ g: WizardGame) -> some View {
        let has = g.hasData()
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: has ? "checkmark.circle.fill" : "folder")
                .font(.system(size: 16)).foregroundStyle(has ? .green : .secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(g.name).font(.headline)
                Text(has ? "Game data set." : g.dataHint).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let s = wcStatus[g.id] { Text(s).font(.caption2).foregroundStyle(.orange) }
                Toggle("Add desktop shortcut", isOn: Binding(
                    get: { addShortcut[g.id] ?? false }, set: { addShortcut[g.id] = $0 }))
                    .font(.caption).toggleStyle(.checkbox)
            }
            Spacer()
            Button(has ? "Change…" : "Choose…") { g.choose() }
        }
    }

    private func chooseFolder(_ message: String, _ apply: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = message; panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        apply(url.path); dataTick += 1
    }

    /// Warcraft picker — accepts an original installation (auto-extracted) or already-extracted data.
    private func chooseWarcraft(_ title: WarcraftGame.Title) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Choose your \(title.displayName) folder — the original game or already-extracted data"
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        func setFolder(_ p: String) {
            if title == .warcraft2 { settings.warcraft2DataFolder = p } else { settings.warcraft1DataFolder = p }
        }
        if WarcraftGame.hasExtractedData(at: url, title) {
            setFolder(url.path); wcStatus[title.rawValue] = nil; dataTick += 1
        } else if WarcraftGame.looksLikeInstallation(at: url, title) {
            wcStatus[title.rawValue] = "Extracting game data — this takes a moment…"
            WarcraftGame.extract(title, from: url) { result in
                switch result {
                case .success(let dest): setFolder(dest.path); wcStatus[title.rawValue] = nil
                case .failure(let e):    wcStatus[title.rawValue] = "Extraction failed: \(e.message)"
                }
                dataTick += 1
            }
        } else {
            wcStatus[title.rawValue] = "No \(title.displayName) data found in that folder."
        }
    }

    // MARK: - Theme page

    private var themeChoices: [(String, String)] {
        ThemeManager.shared.availableThemes.map { ($0.config.name, ThemeManager.displayName(for: $0.config.name)) }
    }

    private var themePage: some View {
        pageScaffold(icon: "paintbrush.pointed.fill", tint: .indigo, title: "Choose a theme",
                     subtitle: "Which look should RetroMac start with? You can switch any time from the menu.") {
            Picker("", selection: $selectedTheme) {
                Text("Keep current / none").tag("")
                ForEach(themeChoices, id: \.0) { name, display in
                    Text(display).tag(name)
                }
            }
            .labelsHidden().pickerStyle(.inline)
        }
    }

    /// Applied when the user finishes: switch to the chosen theme and add the requested game
    /// shortcuts to that theme's desktop.
    private func applyFinalChoices() {
        // Always (re)apply the chosen theme — even if it matches the current name it may not be
        // actually showing (desktop off), and the user explicitly picked it here. setActiveTheme
        // is idempotent.
        if !selectedTheme.isEmpty {
            ThemeManager.shared.setActiveTheme(name: selectedTheme, applyWallpaper: !settings.dockOnly)
            settings.dockEnabled = true   // the themed desktop must be on for the theme to show
            // Setting the flag alone does NOT start the dock: the DockController's own
            // dockEnabled observer is only registered inside start(), so if the dock wasn't
            // running at launch (dockEnabled was off), flipping it here goes unheard. Every
            // other "enable dock" site calls start() explicitly (selectTheme / toggleDock);
            // do the same so the retro dock actually appears after the assistant. Idempotent.
            DockController.shared.start()
        }
        let themeName = ThemeManager.shared.activeTheme?.config.name ?? selectedTheme
        guard gamesSetup, !themeName.isEmpty else { return }
        var custom = DesktopStore.load(theme: themeName)
        var nextRow = (custom.added.compactMap { $0.gridY }.max() ?? 6) + 1
        for g in gamesList where (addShortcut[g.id] ?? false) && g.hasData() {
            guard !custom.added.contains(where: { $0.type == g.id }) else { continue }
            custom.added.append(DockThemeConfig.DesktopIconEntry(
                name: g.name, icon: "", type: g.id, gridX: 0, gridY: nextRow))
            nextRow += 1
        }
        DesktopStore.save(custom, theme: themeName)
        DesktopIconsController.shared.update()
    }

    private var systemPage: some View {
        pageScaffold(icon: "gearshape.2.fill", tint: .cyan, title: "System",
                     subtitle: "How RetroMac runs on your Mac.") {
            toggleRow(icon: "dock.rectangle", tint: .cyan,
                      title: "Enable Dock Mode",
                      subtitle: "Adds a Dock icon with a quick launcher for themes, shader & camera.",
                      isOn: $settings.dockModeEnabled)
            Divider()
            toggleRow(icon: "power", tint: .pink,
                      title: "Start at login",
                      subtitle: "Launch RetroMac automatically when you log in.",
                      isOn: $settings.launchAtLogin)
            Divider()
            toggleRow(icon: "circle.dashed", tint: .teal,
                      title: "Floating launcher button",
                      subtitle: "Recommended — a small, draggable button (bottom-right) that opens the launcher.",
                      isOn: $settings.floatingLauncherEnabled)
            Divider()
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "globe").font(.system(size: 18)).foregroundStyle(.indigo).frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reframe browser").font(.headline)
                    Text("RetroMac’s companion retro web browser.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if reframeInstalled {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.green)
                } else {
                    Button("Install…") {
                        if let u = URL(string: Self.reframeURL) { NSWorkspace.shared.open(u) }
                        reframeInstalled = Self.isReframeInstalled()
                    }
                }
            }
        }
    }

    private var permissionsPage: some View {
        pageScaffold(icon: "lock.shield.fill", tint: .red, title: "Permissions",
                     subtitle: "RetroMac needs these to draw the shader and use hotkeys.") {
            permissionRow(name: "Screen Recording",
                          detail: "Required to draw the shader over your screen.",
                          granted: screenRecordingGranted,
                          pane: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            Divider()
            permissionRow(name: "Accessibility",
                          detail: "Required for global hotkeys and window control.",
                          granted: accessibilityGranted,
                          pane: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            Divider()
            Button("Re-check") { refreshPermissions() }.buttonStyle(.link)
        }
    }

    private var donePage: some View {
        VStack(alignment: .center, spacing: 14) {
            Spacer(minLength: 20)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46)).foregroundStyle(.green)
            Text("You’re all set!").font(.title.bold())
            Text("RetroMac is configured. Pick a theme from the menu to get started — re-run this assistant any time from the menu or Settings ▸ Overview.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer / navigation

    private var footer: some View {
        HStack {
            if page != .intro {
                Button("Back") { goBack() }.keyboardShortcut(.cancelAction)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(WizardPage.allCases, id: \.rawValue) { p in
                    Circle()
                        .fill(p.rawValue <= page.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            Button(primaryTitle) { goNext() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }

    private var primaryTitle: String {
        switch page {
        case .intro: return "Get Started"
        case .done:  return "Finish"
        default:     return "Continue"
        }
    }

    private func goNext() {
        if page == .done { applyFinalChoices(); onFinish(); return }
        if let next = WizardPage(rawValue: page.rawValue + 1) {
            withAnimation(.easeInOut(duration: 0.15)) { page = next }
            if next == .permissions { refreshPermissions() }
        }
    }

    private func goBack() {
        if let prev = WizardPage(rawValue: page.rawValue - 1) {
            withAnimation(.easeInOut(duration: 0.15)) { page = prev }
        }
    }

    // MARK: - Reusable pieces

    @ViewBuilder
    private func pageScaffold<C: View>(
        icon: String, tint: Color, title: String, subtitle: String,
        @ViewBuilder rows: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 24)).foregroundStyle(tint).frame(width: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.title2.bold())
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) { rows() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleRow(icon: String, tint: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }

    private func permissionRow(name: String, detail: String, granted: Bool, pane: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 18)).foregroundStyle(granted ? .green : .orange).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Text("Granted").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Open Settings") {
                    if let u = URL(string: pane) { NSWorkspace.shared.open(u) }
                }
            }
        }
    }

    // MARK: - Permission / install checks

    private func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                await MainActor.run { screenRecordingGranted = true }
            } catch {
                await MainActor.run { screenRecordingGranted = false }
            }
        }
    }

    private static func isReframeInstalled() -> Bool {
        let candidates = ["/Applications/Reframe.app",
                          NSHomeDirectory() + "/Applications/Reframe.app"]
        return candidates.contains { FileManager.default.fileExists(atPath: $0) }
    }
}

// MARK: - Controller

final class SetupWizardWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    /// Optional follow-up after the wizard finishes (e.g. show What's New on first run).
    var onFinishExtra: (() -> Void)?

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SetupWizardView(onFinish: { [weak self] in self?.finish() })
        let hosting = NSHostingView(rootView: view)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: WelcomePage.windowWidth,
                                height: WelcomePage.windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        win.title = "RetroMac Setup Assistant"
        win.contentView = hosting
        win.center()
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func finish() {
        AppSettings.shared.setupWizardComplete = true
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window (X or Finish) counts as having seen the wizard.
        AppSettings.shared.setupWizardComplete = true
        let extra = onFinishExtra
        onFinishExtra = nil
        extra?()
    }
}
