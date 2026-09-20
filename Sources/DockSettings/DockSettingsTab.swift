import SwiftUI
import UniformTypeIdentifiers
import Carbon.HIToolbox

struct DockSettingsTab: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var dockApps: [DockApp] = []
    @State private var themes: [ThemeBundle] = []
    @State private var newThemeName: String = ""
    @State private var showingSaveSheet: Bool = false
    @State private var iconOverrideRefresh: Bool = false
    @State private var showAllApps: Bool = false
    @State private var showAdvanced: Bool = false

    // `settings.dockTheme` holds the theme's STABLE ID, so every lookup here goes through
    // `ThemeManager.resolve` (id first, display name as the pre-Manifest-2.0 fallback) and
    // anything user-visible is derived from the resolved bundle's `name`, never from the id.
    private var selectedThemeConfig: DockThemeConfig? {
        selectedThemeBundle?.config ?? ThemeManager.shared.activeTheme?.config
    }

    private var selectedThemeBundle: ThemeBundle? {
        ThemeManager.resolve(settings.dockTheme, in: themes) ?? ThemeManager.shared.activeTheme
    }

    /// Display name of the selected theme — for labels, gradients and any name-based check.
    private var selectedThemeName: String { selectedThemeBundle?.name ?? settings.dockTheme }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: RMSpacing.section) {
                themeSection
                behaviourCard
                dockCard
                extrasCard
                integrationCard
                appsCard

                // Fine-tuning and theme files, collapsed by default to keep the tab simple.
                DisclosureGroup(isExpanded: $showAdvanced) {
                    VStack(spacing: RMSpacing.section) {
                        appearanceCard
                        managementCard
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Advanced appearance & theme files", systemImage: "slider.horizontal.3")
                        .font(.headline)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .onAppear {
            refreshApps()
            themes = ThemeManager.shared.availableThemes
        }
        .sheet(isPresented: $showingIconPicker) {
            ThemeIconPickerSheet(
                bundleID: iconPickerBundleID,
                theme: selectedThemeBundle ?? ThemeManager.shared.activeTheme,
                onSelectThemeIcon: { iconPath in
                    ThemeManager.shared.setCustomIcon(for: iconPickerBundleID, path: iconPath)
                    iconOverrideRefresh.toggle()
                    showingIconPicker = false
                },
                onBrowse: {
                    showingIconPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        browseForCustomIconFile(bundleID: iconPickerBundleID)
                    }
                },
                onCancel: { showingIconPicker = false }
            )
        }
    }

    // MARK: - Theme Section

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: RMSpacing.md) {
            RMSectionHeaderView(title: "Theme")

            HStack(spacing: RMSpacing.md) {
                Picker("", selection: $settings.dockTheme) {
                    // Tag by stable id: the selection is what gets STORED, and it must not change
                    // when a theme is renamed. The label stays the display name.
                    ForEach(themes, id: \.stableID) { theme in
                        Text(themeShortName(theme.name)).tag(theme.stableID)
                    }
                }
                .labelsHidden()
                .frame(width: 180)

                Spacer()

                Button("Add custom\u{2026}") { importTheme() }
                    .buttonStyle(RMGhostButtonStyle())
            }

            themePreview
        }
    }

    /// Large preview of the selected theme (dock + overall look). Shows the theme's bundled
    /// preview.png if present, otherwise a placeholder until screenshots are dropped in.
    @ViewBuilder
    private var themePreview: some View {
        let bundle = selectedThemeBundle
        if let url = bundle?.previewImageURL, let img = NSImage(contentsOf: url) {
            // Match the screenshot's own aspect ratio — no cropping.
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: RMRadius.card))
                .overlay(RoundedRectangle(cornerRadius: RMRadius.card).strokeBorder(Color.rmBorder, lineWidth: 1))
        } else {
            // Placeholder until a screenshot exists — keep a sensible 16:9 box.
            let gradient = themeGradient(selectedThemeName)
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(
                    ZStack {
                        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 28)).foregroundStyle(.white.opacity(0.85))
                            Text(themeShortName(selectedThemeName))
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            Text("Preview image coming soon")
                                .font(.caption).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: RMRadius.card))
                .overlay(RoundedRectangle(cornerRadius: RMRadius.card).strokeBorder(Color.rmBorder, lineWidth: 1))
        }
    }

    private func themeShortName(_ name: String) -> String {
        ThemeManager.displayName(for: name)
    }

    private func themeGradient(_ name: String) -> [Color] {
        switch name {
        case "Mountain Lion": return [Color(red: 0.3, green: 0.5, blue: 0.8), Color(red: 0.2, green: 0.4, blue: 0.7)]
        case "Snow Leopard": return [Color(red: 0.45, green: 0.5, blue: 0.58), Color(red: 0.3, green: 0.35, blue: 0.45)]
        case "Mac OS 9.2 Classic", "Mac OS 9 (authentic)": return [Color(red: 0.78, green: 0.78, blue: 0.8), Color(red: 0.62, green: 0.62, blue: 0.68)]
        case "Windows 98": return [Color(red: 0.0, green: 0.5, blue: 0.5), Color(red: 0.0, green: 0.35, blue: 0.35)]
        case "Windows XP": return [Color(red: 0.0, green: 0.35, blue: 0.75), Color(red: 0.0, green: 0.25, blue: 0.55)]
        case "OS/2 Warp 4": return [Color(red: 0.15, green: 0.15, blue: 0.5), Color(red: 0.1, green: 0.1, blue: 0.35)]
        case "BeOS": return [Color(red: 0.85, green: 0.85, blue: 0.5), Color(red: 0.7, green: 0.7, blue: 0.35)]
        default: return [Color(red: 0.3, green: 0.3, blue: 0.4), Color(red: 0.2, green: 0.2, blue: 0.3)]
        }
    }

    private var themeDisplayName: String {
        themeShortName(selectedThemeName)
    }

    /// Themes that support switching between vertical (left) and horizontal (bottom) orientation
    private var themeSupportsOrientationSwitch: Bool {
        guard let c = selectedThemeConfig else { return false }
        // Any normal dock bar can be repositioned (Bottom/Left/Right). Exclude
        // full-width taskbars (Win XP/98, OS/2), the Mac OS 9 Control Strip, and
        // dock-less desktops (Win 3.1 / SGI) — they can't sensibly go vertical.
        return !c.hidesDock && !c.isFullWidth && !c.isControlStrip
    }

    /// Whether the current theme is Windows 98 or Windows XP (for Re:Amp integration)
    private var isWin98OrXP: Bool {
        let name = selectedThemeName
        return name == "Windows 98" || name == "Windows XP"
    }

    // MARK: - Behaviour, Dock, Extras, Integration

    private func toggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding).toggleStyle(.switch).tint(.rmAccent).labelsHidden()
    }

    /// Re-apply the selected theme so a change that is only read while the desktop is built
    /// shows up now rather than at the next theme switch.
    private func reapplySelectedTheme() {
        guard settings.dockEnabled,
              let active = ThemeManager.shared.activeTheme,
              active.stableID == selectedThemeBundle?.stableID else { return }
        ThemeManager.shared.setActiveTheme(name: active.baseConfig.name,
                                           applyWallpaper: !AppSettings.shared.dockOnly)
    }

    private var selectedThemeHasBootScreen: Bool {
        selectedThemeConfig?.splashVideo != nil || selectedThemeConfig?.splashScreen != nil
    }

    /// What RetroMac does around the theme: how it starts, and what it shows of itself.
    private var behaviourCard: some View {
        RMCard(title: "Behaviour", bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Show RetroMac in the Dock",
                      hint: "A theme-aware Dock icon; click it for the quick launcher.") {
                    toggle($settings.dockModeEnabled)
                }
                RMRow(label: "Activate theme on launch",
                      hint: "Start straight into the last theme instead of the clean desktop.") {
                    toggle($settings.activateThemeOnLaunch)
                }
                RMRow(label: "Boot screens",
                      hint: "A theme's own boot video or picture, once, when it starts.") {
                    toggle($settings.showSplashScreen)
                }
                RMRow(label: "Boot screen for \u{201C}\(themeDisplayName)\u{201D}",
                      hint: selectedThemeHasBootScreen ? nil : "This theme has no boot screen of its own.",
                      isLast: true) {
                    Toggle("", isOn: Binding(
                        get: { settings.themeBootscreenEnabled[settings.dockTheme] ?? selectedThemeHasBootScreen },
                        set: { settings.themeBootscreenEnabled[settings.dockTheme] = $0 }))
                        .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                        .disabled(!settings.showSplashScreen || !selectedThemeHasBootScreen)
                }
            }
        }
    }

    /// The retro dock itself: whether, where, and what is on it.
    private var dockCard: some View {
        RMCard(title: "Dock", bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Show retro dock") { toggle($settings.dockEnabled) }
                RMRow(label: "Show only when the system Dock is hidden",
                      hint: "Appears when the macOS Dock auto-hides.") {
                    toggle($settings.dockAutoHide)
                }
                if themeSupportsOrientationSwitch {
                    RMRow(label: "Position") {
                        Picker("", selection: Binding(
                            get: {
                                settings.themeDockPositionOverride[settings.dockTheme]
                                    ?? selectedThemeConfig?.effectiveDockPosition
                                    ?? "bottom"
                            },
                            set: { settings.themeDockPositionOverride[settings.dockTheme] = $0 }
                        )) {
                            Text("Bottom").tag("bottom")
                            Text("Left").tag("left")
                            Text("Right").tag("right")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }
                if selectedThemeConfig?.isControlStrip == true {
                    RMRow(label: "Control Strip edge",
                          hint: "Flush to the left or right screen edge, like classic Mac OS.") {
                        Picker("", selection: $settings.controlStripSide) {
                            Text("Left").tag("left")
                            Text("Right").tag("right")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }
                }
                if selectedThemeConfig?.hasMagnification == true {
                    RMRow(label: "Magnification on hover") { toggle($settings.dockMagnification) }
                }
                if selectedThemeConfig?.name == "Mac OS 6 classic" {
                    RMRow(label: "Dock style",
                          hint: "The Control Strip, or a flat dock with the icons in black and white.",
                          stacked: true) {
                        Picker("", selection: $settings.macos6UseDock) {
                            Text("Control Strip").tag(false)
                            Text("Dock (black & white)").tag(true)
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        .onChange(of: settings.macos6UseDock) { _, _ in reapplySelectedTheme() }
                    }
                }
                if selectedThemeConfig?.name == "Mac OS 9.2 Classic" {
                    RMRow(label: "Dock style",
                          hint: "The Control Strip, or the Platinum dock.",
                          stacked: true) {
                        Picker("", selection: $settings.macos9UseDock) {
                            Text("Control Strip").tag(false)
                            Text("Platinum dock").tag(true)
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        .onChange(of: settings.macos9UseDock) { _, _ in reapplySelectedTheme() }
                    }
                }
                if selectedThemeConfig?.isControlStripModules == true {
                    RMRow(label: "Control Strip",
                          hint: "System modules along one screen edge, as Mac OS 9 had it: the tab collapses it and drags it up and down, the box at the other end sets how much shows, the arrows scroll. No dock: running apps are in the Application menu at the top right.",
                          stacked: true) {
                        HStack {
                            Picker("", selection: $settings.controlStripSide) {
                                Text("Left edge").tag("left")
                                Text("Right edge").tag("right")
                            }
                            .pickerStyle(.segmented).labelsHidden()
                            .onChange(of: settings.controlStripSide) { _, _ in ControlStripController.shared.layout() }
                            Button("Reset position") {
                                settings.controlStripOffsets = [:]
                                settings.controlStripCollapsed = false
                                settings.controlStripVisibleWidth = 0
                                ControlStripController.shared.layout()
                            }
                            .buttonStyle(RMDefaultButtonStyle())
                        }
                    }
                    // Its own row: two segmented controls and a button side by side outgrow the
                    // pane, and the whole settings view is then cut off at both edges.
                    RMRow(label: "Control Strip size",
                          hint: "Medium is one and a half times the strip of a 1× screen, in step with the desktop icons and the menus.") {
                        Picker("", selection: $settings.controlStripScale) {
                            Text("Small").tag(1.0)
                            Text("Medium").tag(1.5)
                            Text("Large").tag(2.0)
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        .onChange(of: settings.controlStripScale) { _, _ in ControlStripController.shared.layout() }
                    }
                }
                if selectedThemeConfig?.name == "BeOS" {
                    RMRow(label: "Dock style",
                          hint: "The Deskbar in a corner, or a regular dock along the bottom.",
                          stacked: true) {
                        Picker("", selection: $settings.beosUseDock) {
                            Text("Deskbar").tag(false)
                            Text("Dock").tag(true)
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        .onChange(of: settings.beosUseDock) { _, _ in reapplySelectedTheme() }
                    }
                }
                if selectedThemeConfig?.isDeskbar == true {
                    RMRow(label: "Deskbar corner") {
                        Picker("", selection: $settings.deskbarCorner) {
                            Text("Bottom left").tag("bottomLeft")
                            Text("Bottom right").tag("bottomRight")
                            Text("Top left").tag("topLeft")
                            Text("Top right").tag("topRight")
                        }
                        .labelsHidden().frame(width: 160)
                    }
                    ForEach(BeOSDeskbarView.availableShortcuts.indices, id: \.self) { i in
                        let sc = BeOSDeskbarView.availableShortcuts[i]
                        RMRow(label: "Show \(sc.label)") {
                            Toggle("", isOn: Binding(
                                get: { settings.deskbarShortcuts.contains(sc.bundleID) },
                                set: { on in
                                    var list = settings.deskbarShortcuts
                                    if on { if !list.contains(sc.bundleID) { list.append(sc.bundleID) } }
                                    else { list.removeAll { $0 == sc.bundleID } }
                                    settings.deskbarShortcuts = list
                                }
                            ))
                            .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                        }
                    }
                }
                if selectedThemeConfig?.hasFolderStacks == true {
                    RMRow(label: "Show Downloads folder",
                          hint: "Pinned to the dock; click it to fan out the most recent files.") {
                        toggle($settings.dockShowDownloads)
                    }
                    RMRow(label: "Show Applications folder",
                          hint: "Pinned to the dock; click it for a grid of everything installed.") {
                        toggle($settings.dockShowApplications)
                    }
                }
                RMRow(label: "Show indicators for running apps") { toggle($settings.dockShowRunningApps) }
                RMRow(label: "24-hour clock",
                      hint: "For the clock in the dock, taskbar or Deskbar.", isLast: true) {
                    toggle($settings.clockUse24Hour)
                }
            }
        }
    }

    /// The bits a particular theme brings along and nothing else has.
    @ViewBuilder
    private var extrasCard: some View {
        let cfg = selectedThemeConfig
        let hasPacman = cfg?.dock.borderStyle == "pacman"
        let hasSlayer = cfg?.dock.borderStyle == "doomslayer"
        let hasScheme = cfg?.name == "Windows 98"
        let hasMessenger = ["Windows 95", "Windows 98", "Windows Me"].contains(cfg?.name ?? "")
        if hasPacman || hasSlayer || hasScheme || hasMessenger || isWin98OrXP {
            RMCard(title: "\(themeDisplayName) extras", bodyPadding: 0) {
                VStack(spacing: 0) {
                    if hasScheme {
                        RMRow(label: "Scheme",
                              hint: "A Windows 98 Plus! desktop theme: colours, wallpaper, icons and cursors.") {
                            Picker("", selection: $settings.win98Scheme) {
                                ForEach(Win98Scheme.pickerOptions, id: \.id) { opt in
                                    Text(opt.display).tag(opt.id)
                                }
                            }
                            .pickerStyle(.menu).labelsHidden().frame(width: 180)
                            .onChange(of: settings.win98Scheme) { _, _ in reapplySelectedTheme() }
                        }
                    }
                    if hasMessenger {
                        RMRow(label: "Messenger in the tray",
                              hint: "ICQ arrived in 1996 and MSN Messenger in 1999.") {
                            Picker("", selection: $settings.trayMessenger) {
                                Text("MSN Messenger").tag("msn")
                                Text("ICQ").tag("icq")
                            }
                            .pickerStyle(.menu).labelsHidden().frame(width: 160)
                            .onChange(of: settings.trayMessenger) { _, _ in reapplySelectedTheme() }
                        }
                    }
                    if isWin98OrXP {
                        RMRow(label: "Re:Amp in the taskbar",
                              hint: "The Winamp-style player for macOS, with a shortcut in the taskbar and the Start menu.") {
                            Toggle("", isOn: Binding(
                                get: { settings.reampEnabled },
                                set: { newValue in
                                    settings.reampEnabled = newValue
                                    if newValue { enableReAmp() } else { disableReAmp() }
                                }
                            ))
                            .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                        }
                    }
                    if hasPacman {
                        RMRow(label: "Animate Pac-Man border",
                              hint: "Pac-Man runs once around the dock eating the dots.") {
                            toggle($settings.pacmanAnimationEnabled)
                        }
                        if settings.pacmanAnimationEnabled {
                            RMRow(label: "Clock mode",
                                  hint: "The dots become the hours and Pac-Man the hand.") {
                                toggle($settings.pacmanClockMode)
                            }
                        }
                    }
                    if hasSlayer {
                        RMRow(label: "Slayer size", stacked: true) {
                            HStack(spacing: 8) {
                                Slider(value: $settings.slayerScale, in: 0.4...2.0, step: 0.05)
                                Text(String(format: "%.2f×", settings.slayerScale))
                                    .font(.rmMono(size: 11)).foregroundColor(.rmTextSecondary)
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                        RMRow(label: "Run speed", hint: "Pixels per second across the dock.", stacked: true) {
                            HStack(spacing: 8) {
                                Slider(value: $settings.slayerRunSpeed, in: 20...170, step: 2)
                                Text("\(Int(settings.slayerRunSpeed))")
                                    .font(.rmMono(size: 11)).foregroundColor(.rmTextSecondary)
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                        RMRow(label: "Combat", hint: "How often the Slayer fires and gets fragged.", stacked: true) {
                            Picker("", selection: $settings.slayerCombat) {
                                Text("Calm").tag("Calm")
                                Text("Normal").tag("Normal")
                                Text("Intense").tag("Intense")
                            }
                            .pickerStyle(.segmented).labelsHidden()
                        }
                        RMRow(label: "Weapon", hint: "Auto-cycle picks a new one each lap.") {
                            Picker("", selection: $settings.slayerWeapon) {
                                Text("Auto-cycle").tag("Auto-cycle")
                                Text("Shotgun").tag("Shotgun")
                                Text("Chaingun").tag("Chaingun")
                                Text("Rocket").tag("Rocket")
                                Text("Plasma").tag("Plasma")
                                Text("Chainsaw").tag("Chainsaw")
                                Text("BFG").tag("BFG")
                            }
                            .labelsHidden().frame(width: 140)
                        }
                        RMRow(label: "Direction") {
                            Picker("", selection: $settings.slayerDirection) {
                                Text("Right").tag("Right")
                                Text("Left").tag("Left")
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 140)
                        }
                        RMRow(label: "DOOM tile opens",
                              hint: "Empty finds an installed DOOM by itself. A path or a bundle id also works.",
                              stacked: true) {
                            HStack(spacing: 6) {
                                TextField("Auto-detect DOOM", text: $settings.doomLaunchTarget)
                                    .textFieldStyle(.roundedBorder)
                                Button("Choose…") {
                                    let p = NSOpenPanel()
                                    p.allowedContentTypes = [.application]
                                    p.canChooseDirectories = false
                                    p.directoryURL = URL(fileURLWithPath: "/Applications")
                                    if p.runModal() == .OK, let u = p.url { settings.doomLaunchTarget = u.path }
                                }
                                .buttonStyle(RMDefaultButtonStyle())
                            }
                        }
                    }
                    // The card's last row needs no divider; the row set varies, so a spacer
                    // divider is cheaper than tracking which row is last.
                    Color.clear.frame(height: 0)
                }
            }
        }
    }

    /// What the theme changes OUTSIDE RetroMac's own windows. Every one of these is restored
    /// Apps whose windows keep their native title bar. Running apps are one click away; any
    /// other app through the open panel.
    @ViewBuilder
    private var titleBarExclusions: some View {
        let excluded = settings.themeTitleBarsExcludedApps
        RMRow(label: "Leave these apps alone",
              hint: excluded.isEmpty ? "Every window gets them." : nil,
              isLast: excluded.isEmpty) {
            Menu("Add app\u{2026}") {
                let running = NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                              && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                              && !excluded.contains($0.bundleIdentifier!) }
                    .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
                ForEach(running, id: \.processIdentifier) { app in
                    Button(app.localizedName ?? app.bundleIdentifier!) {
                        settings.themeTitleBarsExcludedApps.append(app.bundleIdentifier!)
                    }
                }
                if !running.isEmpty { Divider() }
                Button("Other app\u{2026}") { excludeAppFromPanel() }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        ForEach(Array(excluded.enumerated()), id: \.element) { index, bundleID in
            RMRow(label: Self.appName(for: bundleID), hint: bundleID, isLast: index == excluded.count - 1) {
                Button("Remove") {
                    settings.themeTitleBarsExcludedApps.removeAll { $0 == bundleID }
                }
                .buttonStyle(RMGhostButtonStyle())
            }
        }
    }

    private static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func excludeAppFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an app whose windows keep their own title bar"
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        if !settings.themeTitleBarsExcludedApps.contains(id) { settings.themeTitleBarsExcludedApps.append(id) }
    }

    /// when the theme goes off.
    private var integrationCard: some View {
        RMCard(title: "System integration",
               subtitle: "Changes to macOS itself while the theme is on. All of them are undone when it goes off.",
               bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Window borders", hint: "A border around every window in the theme's colours.") {
                    toggle($settings.themeWindowBorders)
                    // No onChange: AppSettings.didSet already drives WindowBorderController.update().
                }
                if let chrome = selectedThemeConfig?.chrome?.style, TitleBarOverlayController.style(for: chrome) != nil {
                    let bars = TitleBarOverlayController.style(for: chrome)?.isBar == true
                    RMRow(label: bars ? "Title bars (experimental)" : "Traffic lights (experimental)",
                          hint: bars
                            ? "The era's title bar above every window, with its own buttons; the real title bar keeps its toolbar, only the lights are hidden. Windows are drawn square, through a setting every app reads when it launches: an app that shows video (Webex, Teams) started while this is on may show grey tiles until it is restarted with it off — excluding it here does not help with that."
                            : "The era's glossy lights over the real ones, and nothing else changes. Close, minimise and zoom work.") {
                        // (Platinum's WindowShade box minimises: a real shade would need the app to allow a 28 pt window.)
                        toggle($settings.themeTitleBars)
                    }
                    if settings.themeTitleBars, !TitleBarOverlayController.accessibilityGranted {
                        RMRow(label: "Needs Accessibility",
                              hint: "The controls drive the real windows through Accessibility; until it is granted nothing is drawn.") {
                            Button("Grant\u{2026}") { TaskbarNoticeView.requestAccessibility() }
                                .buttonStyle(RMDefaultButtonStyle())
                        }
                    }
                    if settings.themeTitleBars {
                        titleBarExclusions
                    }
                }
                RMRow(label: "Match appearance", hint: "macOS appearance and accent colour to fit the theme.") {
                    Toggle("", isOn: $settings.themeAdaptAppearance)
                        .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                        .onChange(of: settings.themeAdaptAppearance) { _, on in
                            if on, settings.dockEnabled, let cfg = ThemeManager.shared.activeTheme?.config {
                                AppearanceAdapter.apply(for: cfg)
                            } else if !on {
                                AppearanceAdapter.restore()
                            }
                        }
                }
                RMRow(label: "Match cursor", hint: "The theme's own pointer set, system-wide.") {
                    Toggle("", isOn: $settings.themeAdaptCursor)
                        .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                        .onChange(of: settings.themeAdaptCursor) { _, on in
                            if on, settings.dockEnabled, let cfg = ThemeManager.shared.activeTheme?.config {
                                CursorThemeManager.shared.apply(for: cfg)
                            } else if !on {
                                CursorThemeManager.shared.restore()
                            }
                        }
                }
                if selectedThemeConfig?.name == "Windows XP" {
                    RMRow(label: "XP cursor size") {
                        Picker("", selection: $settings.xpCursorSize) {
                            Text("Normal").tag(0); Text("Large").tag(1); Text("XL").tag(2)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                        .onChange(of: settings.xpCursorSize) { _, _ in
                            if settings.themeAdaptCursor, settings.dockEnabled,
                               let cfg = ThemeManager.shared.activeTheme?.config, cfg.name == "Windows XP" {
                                CursorThemeManager.shared.apply(for: cfg)
                            }
                        }
                    }
                }
                RMRow(label: "Restore the system cursor",
                      hint: "If a themed pointer got stuck after a force-quit. Also turns Match cursor off.") {
                    Button("Restore") {
                        settings.themeAdaptCursor = false
                        CursorThemeManager.shared.restore(force: true)
                    }
                    .buttonStyle(RMDefaultButtonStyle())
                }
                RMRow(label: "Terminal profile", hint: "A matching Terminal profile: DOS green, BeOS, classic Mac, DOOM.") {
                    Toggle("", isOn: $settings.themeTerminalProfile)
                        .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                        .onChange(of: settings.themeTerminalProfile) { _, on in
                            if on, settings.dockEnabled, let cfg = ThemeManager.shared.activeTheme?.config {
                                TerminalThemer.apply(forThemeNamed: cfg.name)
                            } else if !on {
                                TerminalThemer.restore()
                            }
                        }
                }
                if selectedThemeConfig?.systemTweaks != nil {
                    RMRow(label: "Classic Finder", hint: "Opaque windows, classic scrollbars, list view, fewer animations.") {
                        Toggle("", isOn: $settings.themeApplySystemTweaks)
                            .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                            .onChange(of: settings.themeApplySystemTweaks) { _, on in
                                guard let theme = ThemeManager.shared.activeTheme else { return }
                                let cfg = theme.config
                                if on {
                                    SystemTweaksAdapter.apply(for: cfg, isBuiltIn: theme.isBuiltIn)
                                    SystemTweaksAdapter.showCornerHintIfNeeded(for: cfg)
                                } else {
                                    SystemTweaksAdapter.restore()
                                }
                            }
                    }
                }
                RMRow(label: "Theme icons for system apps", hint: "Swap the icons of Safari, Mail and friends in the Finder too.") {
                    toggle($settings.applySystemIcons)
                }
                RMRow(label: "Apply the icons now", isLast: true) {
                    HStack(spacing: 6) {
                        Button("Apply") { ThemeManager.shared.applyIconsToSystem() }
                            .buttonStyle(RMDefaultButtonStyle())
                        Button("Revert") { ThemeManager.shared.revertSystemIcons() }
                            .buttonStyle(RMDangerButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - Appearance Card

    private var appearanceCard: some View {
        RMCard(title: "Appearance",
               subtitle: "Desktop icon size is under Desktop; the dock hotkey under Shortcuts.",
               bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Transparency") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.dockTransparency, in: 0.3...1.0, step: 0.05)
                            .tint(.rmAccent)
                            .frame(width: 140)
                        Text("\(Int(settings.dockTransparency * 100))%")
                            .font(.rmMono(size: 11))
                            .foregroundColor(.rmTextSecondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                RMRow(label: "Icon scale") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.dockIconScale, in: 0.5...2.0, step: 0.1)
                            .tint(.rmAccent)
                            .frame(width: 140)
                        Text("\(Int(settings.dockIconScale * 100))%")
                            .font(.rmMono(size: 11))
                            .foregroundColor(.rmTextSecondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                RMRow(label: "Target display", isLast: true) {
                    Picker("", selection: $settings.dockTargetDisplayUUID) {
                        Text("Main Display").tag("")
                        ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in
                            let res = "\(Int(screen.frame.width))\u{00D7}\(Int(screen.frame.height))"
                            Text("\(screen.localizedName) (\(res))").tag(screen.displayUUID ?? "")
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
            }
        }
    }

    // MARK: - Apps Card

    private var appsCard: some View {
        let maxVisible = 5
        let visibleApps = showAllApps ? dockApps : Array(dockApps.prefix(maxVisible))
        let hasMore = dockApps.count > maxVisible && !showAllApps

        return RMCard(
            title: "Apps in the dock",
            subtitle: "\(dockApps.count) apps",
            headerAction: AnyView(
                Button("Add app\u{2026}") { browseForApp() }
                    .buttonStyle(RMDefaultButtonStyle())
            ),
            bodyPadding: 0
        ) {
            VStack(spacing: 0) {
                if dockApps.isEmpty {
                    Text("No apps configured. Default apps will be added on first launch.")
                        .font(.rmSecondary)
                        .foregroundColor(.rmTextSecondary)
                        .padding(RMSpacing.card)
                } else {
                    ForEach(Array(visibleApps.enumerated()), id: \.element.id) { index, app in
                        let isLast = !hasMore && index == visibleApps.count - 1
                        dockAppRow(app, isLast: isLast)
                    }
                    if hasMore {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showAllApps = true }
                        } label: {
                            Text("Show all \(dockApps.count) apps\u{2026}")
                                .font(.rmSecondary)
                                .foregroundColor(.rmAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Theme files

    private var managementCard: some View {
        RMCard(title: "Theme files",
               subtitle: "Your own themes live in Application Support. Import with \u{201C}Add custom\u{2026}\u{201D} above.",
               bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Themes folder") {
                    Button("Open in Finder") {
                        NSWorkspace.shared.open(ThemeManager.shared.userThemesDirectory)
                    }
                    .buttonStyle(RMDefaultButtonStyle())
                }
                if ThemeManager.shared.canSaveExistingTheme {
                    RMRow(label: "Save changes to \u{201C}\(themeDisplayName)\u{201D}") {
                        Button("Save") {
                            try? ThemeManager.shared.saveExistingTheme()
                            themes = ThemeManager.shared.availableThemes
                            iconOverrideRefresh.toggle()
                        }
                        .buttonStyle(RMDefaultButtonStyle())
                    }
                }
                RMRow(label: "Save as a new theme",
                      hint: "The selected theme with your icon and wallpaper changes.",
                      isLast: true, stacked: true) {
                    HStack(spacing: 6) {
                        TextField("New theme name", text: $newThemeName)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            guard !newThemeName.isEmpty else { return }
                            try? ThemeManager.shared.saveAsNewTheme(name: newThemeName)
                            themes = ThemeManager.shared.availableThemes
                            newThemeName = ""
                            iconOverrideRefresh.toggle()
                        }
                        .buttonStyle(RMDefaultButtonStyle())
                        .disabled(newThemeName.isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - Dock App Row

    @ViewBuilder
    private func dockAppRow(_ app: DockApp, isLast: Bool = false) -> some View {
        let hasCustom = ThemeManager.shared.customIconPath(for: app.bundleID) != nil && iconOverrideRefresh == iconOverrideRefresh
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Grip handle
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 2) {
                            Circle().fill(Color.rmTextTertiary).frame(width: 2, height: 2)
                            Circle().fill(Color.rmTextTertiary).frame(width: 2, height: 2)
                        }
                    }
                }

                DockAppIconView(bundleID: app.bundleID)
                    .frame(width: 24, height: 24)

                Text(app.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.rmTextPrimary)

                Spacer()

                if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == app.bundleID }) {
                    RMChip(text: "Running", tone: .on, showDot: true)
                }

                Button {
                    browseForCustomIcon(bundleID: app.bundleID)
                } label: {
                    Image(systemName: hasCustom ? "paintbrush.fill" : "paintbrush")
                        .font(.system(size: 11))
                        .foregroundColor(hasCustom ? .rmAccent : .rmTextTertiary)
                }
                .buttonStyle(.plain)

                Button {
                    AppManager.shared.removeApp(bundleID: app.bundleID)
                    refreshApps()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundColor(.rmTextTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, RMSpacing.card)

            if !isLast {
                Rectangle()
                    .fill(Color.rmDivider)
                    .frame(height: 1)
                    .padding(.horizontal, RMSpacing.card)
            }
        }
    }

    // MARK: - Re:Amp Integration

    private func enableReAmp() {
        // Trigger install/launch dialog
        ReAmpHelper.launchOrInstall()

        // Set the theme icon override for Re:Amp
        if let theme = ThemeManager.shared.activeTheme {
            let iconPath = theme.iconsDirectory.appendingPathComponent("reamp.png").path
            if FileManager.default.fileExists(atPath: iconPath) {
                ThemeManager.shared.setCustomIcon(for: ReAmpHelper.bundleID, path: iconPath)
            }
        }

        // Add to dock if installed (may not be yet if user just downloaded)
        addReAmpToDockIfInstalled()

        // Poll briefly in case user is installing right now
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in
            addReAmpToDockIfInstalled()
        }
    }

    private func disableReAmp() {
        // Remove from dock
        AppManager.shared.removeApp(bundleID: ReAmpHelper.bundleID)
        ThemeManager.shared.setCustomIcon(for: ReAmpHelper.bundleID, path: nil)
        refreshApps()
    }

    private func addReAmpToDockIfInstalled() {
        let bid = ReAmpHelper.bundleID
        guard !AppManager.shared.apps.contains(where: { $0.bundleID == bid }) else { return }
        // Try adding — AppManager.addApp checks if installed
        AppManager.shared.addApp(bundleID: bid)
        refreshApps()
    }

    // MARK: - Existing Helpers

    private func refreshApps() {
        dockApps = AppManager.shared.apps
    }

    @State private var showingIconPicker = false
    @State private var iconPickerBundleID: String = ""

    private func browseForCustomIcon(bundleID: String) {
        if let theme = selectedThemeBundle ?? ThemeManager.shared.activeTheme,
           !theme.availableIcons().isEmpty {
            iconPickerBundleID = bundleID
            showingIconPicker = true
            return
        }
        browseForCustomIconFile(bundleID: bundleID)
    }

    private func browseForCustomIconFile(bundleID: String) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.png, UTType.icns, UTType.tiff, UTType.jpeg]
        panel.message = "Choose a custom icon for \u{201C}\(themeDisplayName)\u{201D} theme"
        panel.prompt = "Set Icon"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.level = .floating
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ThemeManager.shared.setCustomIcon(for: bundleID, path: url.path)
        iconOverrideRefresh.toggle()
    }

    private func browseForApp() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an application to add to the Dock"
        panel.prompt = "Add"
        panel.level = .floating

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return }

        AppManager.shared.addApp(bundleID: bundleID)
        refreshApps()
    }

    private func importTheme() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.folder]
        panel.message = "Select a .retromactheme bundle"
        panel.prompt = "Import"
        panel.level = .floating

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.pathExtension == "retromactheme" else { return }
        do {
            try ThemeManager.shared.importTheme(from: url)
            themes = ThemeManager.shared.availableThemes
        } catch {
            print("[Dock] Import failed: \(error)")
        }
    }
}

// MARK: - Theme Card

// MARK: - Kept from original

struct DockAppIconView: View {
    let bundleID: String

    var body: some View {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path {
            let icon = NSWorkspace.shared.icon(forFile: path)
            Image(nsImage: icon)
                .resizable()
        } else {
            Image(systemName: "app")
                .resizable()
        }
    }
}
