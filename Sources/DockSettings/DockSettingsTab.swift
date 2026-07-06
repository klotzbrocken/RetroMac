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

    private var selectedThemeConfig: DockThemeConfig? {
        themes.first(where: { $0.name == settings.dockTheme })?.config
            ?? ThemeManager.shared.activeTheme?.config
    }

    private var selectedThemeBundle: ThemeBundle? {
        themes.first(where: { $0.name == settings.dockTheme })
            ?? ThemeManager.shared.activeTheme
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: RMSpacing.section) {
                // 1. Theme cards
                themeSection

                // 2. Behavior (core)
                behaviorCard

                // 3. Apps in the dock
                appsCard

                // 4. Advanced — appearance fine-tuning, wallpaper, shader, system icons,
                //    management — collapsed by default to keep the tab simple.
                DisclosureGroup(isExpanded: $showAdvanced) {
                    VStack(spacing: RMSpacing.section) {
                        appearanceCard
                        advancedSection
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Advanced appearance & themes", systemImage: "slider.horizontal.3")
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
                    ForEach(themes, id: \.name) { theme in
                        Text(themeShortName(theme.name)).tag(theme.name)
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
        let bundle = themes.first(where: { $0.name == settings.dockTheme }) ?? ThemeManager.shared.activeTheme
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
            let gradient = themeGradient(settings.dockTheme)
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(
                    ZStack {
                        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 28)).foregroundStyle(.white.opacity(0.85))
                            Text(themeShortName(settings.dockTheme))
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
        case "Mac OS 9.2 Classic": return [Color(red: 0.78, green: 0.78, blue: 0.8), Color(red: 0.62, green: 0.62, blue: 0.68)]
        case "Windows 98": return [Color(red: 0.0, green: 0.5, blue: 0.5), Color(red: 0.0, green: 0.35, blue: 0.35)]
        case "Windows XP": return [Color(red: 0.0, green: 0.35, blue: 0.75), Color(red: 0.0, green: 0.25, blue: 0.55)]
        case "OS/2 Warp 4": return [Color(red: 0.15, green: 0.15, blue: 0.5), Color(red: 0.1, green: 0.1, blue: 0.35)]
        case "BeOS": return [Color(red: 0.85, green: 0.85, blue: 0.5), Color(red: 0.7, green: 0.7, blue: 0.35)]
        default: return [Color(red: 0.3, green: 0.3, blue: 0.4), Color(red: 0.2, green: 0.2, blue: 0.3)]
        }
    }

    private var themeDisplayName: String {
        themeShortName(settings.dockTheme)
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
        let name = settings.dockTheme
        return name == "Windows 98" || name == "Windows XP"
    }

    /// Returns the currently active wallpaper filename for the given theme bundle
    private func activeWallpaperFile(bundle: ThemeBundle) -> String {
        if let override = settings.themeWallpaperOverrides[settings.dockTheme] {
            return override
        }
        return bundle.config.wallpaper ?? ""
    }

    // MARK: - Behavior Card

    private var behaviorCard: some View {
        RMCard(title: "Behavior", bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Show RetroMac in the Dock", hint: "Adds a theme-aware Dock icon; click it for a quick launcher (themes, effects, apps).") {
                    Toggle("", isOn: $settings.dockModeEnabled)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                }
                RMRow(label: "Show retro dock") {
                    Toggle("", isOn: $settings.dockEnabled)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                }
                RMRow(label: "Show only when system dock is hidden", hint: "Auto-shows when macOS dock auto-hides.") {
                    Toggle("", isOn: $settings.dockAutoHide)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
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
                if selectedThemeConfig?.hasMagnification == true {
                    RMRow(label: "Magnification on hover") {
                        Toggle("", isOn: $settings.dockMagnification)
                            .toggleStyle(.switch)
                            .tint(.rmAccent)
                            .labelsHidden()
                    }
                }
                if selectedThemeConfig?.dock.borderStyle == "pacman" {
                    RMRow(label: "Animate Pac-Man border", hint: "Pac-Man runs once around the dock eating the dots. Off shows a calm static border.") {
                        Toggle("", isOn: $settings.pacmanAnimationEnabled)
                            .toggleStyle(.switch)
                            .tint(.rmAccent)
                            .labelsHidden()
                    }
                    if settings.pacmanAnimationEnabled {
                        RMRow(label: "Clock mode", hint: "Dots become 24 hour numbers around the dock; Pac-Man is the clock hand (15-min steps).") {
                            Toggle("", isOn: $settings.pacmanClockMode)
                                .toggleStyle(.switch)
                                .tint(.rmAccent)
                                .labelsHidden()
                        }
                    }
                }
                if selectedThemeConfig?.name == "Mac OS 6 classic" {
                    RMRow(label: "Dock style", hint: "Replace the Control Strip with a Mountain-Lion-style dock — flat 2D panel, icons stay black & white.") {
                        Picker("", selection: $settings.macos6UseDock) {
                            Text("Control Strip").tag(false)
                            Text("Dock (B/W)").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                        .onChange(of: settings.macos6UseDock) { _, _ in
                            guard settings.dockEnabled,
                                  ThemeManager.shared.activeTheme?.baseConfig.name == "Mac OS 6 classic" else { return }
                            ThemeManager.shared.setActiveTheme(name: "Mac OS 6 classic",
                                                               applyWallpaper: !AppSettings.shared.dockOnly)
                        }
                    }
                }
                if selectedThemeConfig?.name == "Mac OS 9.2 Classic" {
                    RMRow(label: "Dock style", hint: "Replace the Control Strip with the Platinum dock (the former standalone \u{201C}Mac OS 9.2\u{201D} theme).") {
                        Picker("", selection: $settings.macos9UseDock) {
                            Text("Control Strip").tag(false)
                            Text("Platinum Dock").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                        .onChange(of: settings.macos9UseDock) { _, _ in
                            guard settings.dockEnabled,
                                  ThemeManager.shared.activeTheme?.baseConfig.name == "Mac OS 9.2 Classic" else { return }
                            ThemeManager.shared.setActiveTheme(name: "Mac OS 9.2 Classic",
                                                               applyWallpaper: !AppSettings.shared.dockOnly)
                        }
                    }
                }
                if selectedThemeConfig?.name == "BeOS" {
                    RMRow(label: "Dock style", hint: "The classic BeOS Deskbar (corner panel) or a regular bottom dock.") {
                        Picker("", selection: $settings.beosUseDock) {
                            Text("Deskbar").tag(false)
                            Text("Dock").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                        .onChange(of: settings.beosUseDock) { _, _ in
                            guard settings.dockEnabled,
                                  ThemeManager.shared.activeTheme?.baseConfig.name == "BeOS" else { return }
                            ThemeManager.shared.setActiveTheme(name: "BeOS",
                                                               applyWallpaper: !AppSettings.shared.dockOnly)
                        }
                    }
                }
                if selectedThemeConfig?.dock.borderStyle == "doomslayer" {
                    RMRow(label: "Slayer size", hint: "Scale of the Doom Slayer patrolling below the dock. The one knob you usually touch.") {
                        HStack(spacing: 8) {
                            Slider(value: $settings.slayerScale, in: 0.4...2.0, step: 0.05)
                                .frame(width: 150)
                            Text(String(format: "%.2f×", settings.slayerScale))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    RMRow(label: "Run speed", hint: "How fast the Slayer crosses the dock (px/s). Optional.") {
                        HStack(spacing: 8) {
                            Slider(value: $settings.slayerRunSpeed, in: 20...170, step: 2)
                                .frame(width: 150)
                            Text("\(Int(settings.slayerRunSpeed))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    RMRow(label: "Combat", hint: "Calm, Normal or Intense — controls how often the Slayer fires and gets fragged. Optional.") {
                        Picker("", selection: $settings.slayerCombat) {
                            Text("Calm").tag("Calm")
                            Text("Normal").tag("Normal")
                            Text("Intense").tag("Intense")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    RMRow(label: "Weapons", hint: "Auto-cycle picks a new weapon each lap, or lock one. Optional.") {
                        Picker("", selection: $settings.slayerWeapon) {
                            Text("Auto-cycle").tag("Auto-cycle")
                            Text("Shotgun").tag("Shotgun")
                            Text("Chaingun").tag("Chaingun")
                            Text("Rocket").tag("Rocket")
                            Text("Plasma").tag("Plasma")
                            Text("Chainsaw").tag("Chainsaw")
                            Text("BFG").tag("BFG")
                        }
                        .frame(width: 200)
                    }
                    RMRow(label: "Direction", hint: "Travel and facing direction. Optional.") {
                        Picker("", selection: $settings.slayerDirection) {
                            Text("Right").tag("Right")
                            Text("Left").tag("Left")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    RMRow(label: "DOOM tile launches", hint: "What the DOOM logo tile (right of the trash) opens. Empty = auto-detect an installed DOOM app. You can also paste an app path or a bundle id.") {
                        HStack(spacing: 6) {
                            TextField("Auto-detect DOOM", text: $settings.doomLaunchTarget)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 150)
                            Button("Choose…") {
                                let p = NSOpenPanel()
                                p.allowedContentTypes = [.application]
                                p.canChooseDirectories = false
                                p.directoryURL = URL(fileURLWithPath: "/Applications")
                                if p.runModal() == .OK, let u = p.url { settings.doomLaunchTarget = u.path }
                            }
                        }
                    }
                }
                if selectedThemeConfig?.hasFolderStacks == true {
                    RMRow(label: "Show Downloads folder", hint: "Pins your Downloads folder to the dock; click it to fan out the most recent files.") {
                        Toggle("", isOn: $settings.dockShowDownloads)
                            .toggleStyle(.switch)
                            .tint(.rmAccent)
                            .labelsHidden()
                    }
                }
                if selectedThemeConfig?.isDeskbar == true {
                    RMRow(label: "Deskbar position") {
                        Picker("", selection: $settings.deskbarCorner) {
                            Text("Bottom Left").tag("bottomLeft")
                            Text("Bottom Right").tag("bottomRight")
                            Text("Top Left").tag("topLeft")
                            Text("Top Right").tag("topRight")
                        }
                        .frame(width: 200)
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
                RMRow(label: "Show indicators for running apps") {
                    Toggle("", isOn: $settings.dockShowRunningApps)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                }
                RMRow(label: "24-hour clock", hint: "Show the dock / deskbar clock in 24-hour (military) time instead of 12-hour AM/PM.") {
                    Toggle("", isOn: $settings.clockUse24Hour)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                }
                RMRow(label: "Terminal profile", hint: "Install and select a Terminal profile matching the theme (DOS green, BeOS, Classic Mac, DOOM …). Your previous profile returns when the theme goes off.") {
                    Toggle("", isOn: $settings.themeTerminalProfile)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                        .onChange(of: settings.themeTerminalProfile) { _, on in
                            if on, settings.dockEnabled, let cfg = ThemeManager.shared.activeTheme?.config {
                                TerminalThemer.apply(forThemeNamed: cfg.name)
                            } else if !on {
                                TerminalThemer.restore()
                            }
                        }
                }
                RMRow(label: "Match appearance", hint: "Set the macOS appearance and accent colour to fit the active theme (e.g. Graphite for Mac OS 6). Your own settings are remembered and restored.") {
                    Toggle("", isOn: $settings.themeAdaptAppearance)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                        .onChange(of: settings.themeAdaptAppearance) { _, on in
                            if on, settings.dockEnabled, let cfg = ThemeManager.shared.activeTheme?.config {
                                AppearanceAdapter.apply(for: cfg)
                            } else if !on {
                                AppearanceAdapter.restore()
                            }
                        }
                }
                RMRow(label: "Match cursor", hint: "Replace the system-wide mouse cursor with the theme's set (classic Mac pointer + ticking wristwatch for Apple System 6/9). Your normal cursor returns when the theme goes off.") {
                    Toggle("", isOn: $settings.themeAdaptCursor)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                        .onChange(of: settings.themeAdaptCursor) { _, on in
                            if on, settings.dockEnabled, let cfg = ThemeManager.shared.activeTheme?.config {
                                CursorThemeManager.shared.apply(for: cfg)
                            } else if !on {
                                CursorThemeManager.shared.restore()
                            }
                        }
                }
                if ThemeManager.shared.activeTheme?.config.name == "Windows XP" {
                    RMRow(label: "XP cursor size", hint: "Windows XP cursors (modernXP, GPL-3.0) come in three sizes — the theme is drawn to scale crisply.") {
                        Picker("", selection: $settings.xpCursorSize) {
                            Text("Normal").tag(0); Text("Large").tag(1); Text("XL").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 180)
                        .onChange(of: settings.xpCursorSize) { _, _ in
                            if settings.themeAdaptCursor, settings.dockEnabled,
                               let cfg = ThemeManager.shared.activeTheme?.config, cfg.name == "Windows XP" {
                                CursorThemeManager.shared.apply(for: cfg)
                            }
                        }
                    }
                }
                RMRow(label: "Show splash screen", hint: "Briefly shows the theme's boot splash when activated.", isLast: true) {
                    Toggle("", isOn: $settings.showSplashScreen)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                }
            }
        }
    }

    // MARK: - Appearance Card

    private var appearanceCard: some View {
        RMCard(title: "Appearance", bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Transparency") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.dockTransparency, in: 0.3...1.0, step: 0.05)
                            .tint(.rmAccent)
                            .frame(width: 110)
                        Text("\(Int(settings.dockTransparency * 100))%")
                            .font(.rmMono(size: 11))
                            .foregroundColor(.rmTextSecondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                RMRow(label: "Icon scale") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.dockIconScale, in: 0.5...2.0, step: 0.1)
                            .tint(.rmAccent)
                            .frame(width: 110)
                        Text("\(Int(settings.dockIconScale * 100))%")
                            .font(.rmMono(size: 11))
                            .foregroundColor(.rmTextSecondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                RMRow(label: "Desktop icons") {
                    HStack(spacing: 8) {
                        // Link toggle: while locked the desktop icons track the dock slider.
                        Button {
                            if settings.desktopIconScaleLinked {
                                // Unlocking: start where the dock currently is.
                                settings.desktopIconScale = settings.dockIconScale
                                settings.desktopIconScaleLinked = false
                            } else {
                                settings.desktopIconScaleLinked = true
                            }
                        } label: {
                            Image(systemName: settings.desktopIconScaleLinked ? "lock.fill" : "lock.open")
                                .font(.system(size: 11))
                                .foregroundColor(settings.desktopIconScaleLinked ? .rmTextSecondary : .rmAccent)
                        }
                        .buttonStyle(.plain)
                        .help(settings.desktopIconScaleLinked
                              ? "Linked to the dock icon scale — click to size desktop icons independently"
                              : "Independent from the dock — click to link back to the dock icon scale")

                        Slider(
                            value: Binding(
                                get: { settings.desktopIconScaleLinked ? settings.dockIconScale : settings.desktopIconScale },
                                set: { settings.desktopIconScale = $0 }
                            ),
                            in: 0.5...2.0, step: 0.1
                        )
                        .tint(.rmAccent)
                        .frame(width: 110)
                        .disabled(settings.desktopIconScaleLinked)

                        Text("\(Int((settings.desktopIconScaleLinked ? settings.dockIconScale : settings.desktopIconScale) * 100))%")
                            .font(.rmMono(size: 11))
                            .foregroundColor(.rmTextSecondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                RMRow(label: "Target display") {
                    Picker("", selection: $settings.dockTargetDisplayID) {
                        Text("Main Display").tag(CGDirectDisplayID(0))
                        ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in
                            let res = "\(Int(screen.frame.width))\u{00D7}\(Int(screen.frame.height))"
                            Text("\(screen.localizedName) (\(res))").tag(screen.displayID)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }
                // Hotkey display-only row
                RMRow(label: "Toggle shortcut", isLast: true) {
                    RMHotkeyChip(keys: dockHotkeyKeys)
                }
            }
        }
    }

    private var dockHotkeyKeys: [String] {
        var keys: [String] = []
        if settings.dockHotkeyModifiers & UInt32(controlKey) != 0 { keys.append("\u{2303}") }
        if settings.dockHotkeyModifiers & UInt32(optionKey) != 0 { keys.append("\u{2325}") }
        if settings.dockHotkeyModifiers & UInt32(cmdKey) != 0 { keys.append("\u{2318}") }
        keys.append(AppSettings.keyName(for: settings.dockHotkeyCode))
        return keys
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

    // MARK: - Advanced Section

    private var advancedSection: some View {
        VStack(spacing: RMSpacing.xxl) {
            // Wallpaper picker (only when theme has multiple wallpapers)
            if let bundle = selectedThemeBundle {
                let wallpapers = bundle.wallpaperOptions()
                if wallpapers.count > 1 {
                    RMCard(title: "Wallpaper", subtitle: "\(wallpapers.count) wallpapers available for \u{201C}\(themeDisplayName)\u{201D}.", bodyPadding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(wallpapers.enumerated()), id: \.offset) { index, wp in
                                let isSelected = activeWallpaperFile(bundle: bundle) == wp.url.lastPathComponent
                                let isLast = index == wallpapers.count - 1
                                Button {
                                    settings.themeWallpaperOverrides[settings.dockTheme] = wp.url.lastPathComponent
                                    ThemeManager.shared.applyWallpaper()
                                } label: {
                                    HStack(spacing: 10) {
                                        // Thumbnail
                                        if let nsImage = NSImage(contentsOf: wp.url) {
                                            Image(nsImage: nsImage)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 48, height: 32)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .stroke(isSelected ? Color.rmAccent : Color.rmBorder, lineWidth: isSelected ? 1.5 : 0.5)
                                                )
                                        }
                                        Text(wp.name)
                                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                            .foregroundColor(.rmTextPrimary)
                                        Spacer()
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(.rmAccent)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, RMSpacing.card)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if !isLast {
                                    Rectangle()
                                        .fill(Color.rmDivider)
                                        .frame(height: 1)
                                        .padding(.horizontal, RMSpacing.card)
                                }
                            }
                        }
                    }
                }
            }

            // Shader preset
            RMCard(title: "Shader preset", subtitle: "Activated when switching to \u{201C}\(themeDisplayName)\u{201D}.", bodyPadding: 0) {
                RMRow(label: "Preset", isLast: true) {
                    Picker("", selection: Binding(
                        get: {
                            if let override = settings.themePresetOverrides[settings.dockTheme] {
                                return override
                            }
                            return selectedThemeConfig?.defaultPreset ?? ""
                        },
                        set: { settings.themePresetOverrides[settings.dockTheme] = $0 }
                    )) {
                        Text("None").tag("")
                        ForEach(PresetRegistry.builtinPresets, id: \.id) { preset in
                            Text(preset.displayName).tag(preset.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }
            }

            // Re:Amp integration (Win98/XP only)
            if isWin98OrXP {
                RMCard(title: "Re:Amp", subtitle: "Winamp-style music player for macOS. Adds a shortcut to the taskbar and Start Menu.", bodyPadding: 0) {
                    RMRow(label: "Enable Re:Amp", isLast: true) {
                        Toggle("", isOn: Binding(
                            get: { settings.reampEnabled },
                            set: { newValue in
                                settings.reampEnabled = newValue
                                if newValue {
                                    enableReAmp()
                                } else {
                                    disableReAmp()
                                }
                            }
                        ))
                            .toggleStyle(.switch)
                            .tint(.rmAccent)
                            .labelsHidden()
                    }
                }
            }

            // System icons + theme management
            HStack(alignment: .top, spacing: RMSpacing.xxl) {
                RMCard(title: "System icons", bodyPadding: 0) {
                    VStack(spacing: 0) {
                        RMRow(label: "Apply theme icons to system apps") {
                            Toggle("", isOn: $settings.applySystemIcons)
                                .toggleStyle(.switch)
                                .tint(.rmAccent)
                                .labelsHidden()
                        }
                        RMRow(label: "Apply now", isLast: true) {
                            HStack(spacing: 6) {
                                Button("Apply") { ThemeManager.shared.applyIconsToSystem() }
                                    .buttonStyle(RMDefaultButtonStyle())
                                Button("Revert") { ThemeManager.shared.revertSystemIcons() }
                                    .buttonStyle(RMDangerButtonStyle())
                            }
                        }
                    }
                }

                RMCard(title: "Theme management", bodyPadding: RMSpacing.card) {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Button("Open folder") {
                                NSWorkspace.shared.open(ThemeManager.shared.userThemesDirectory)
                            }
                            .buttonStyle(RMDefaultButtonStyle())

                            Button("Import\u{2026}") { importTheme() }
                                .buttonStyle(RMDefaultButtonStyle())
                        }

                        if ThemeManager.shared.canSaveExistingTheme {
                            Button("Save changes to \u{201C}\(themeDisplayName)\u{201D}") {
                                try? ThemeManager.shared.saveExistingTheme()
                                themes = ThemeManager.shared.availableThemes
                                iconOverrideRefresh.toggle()
                            }
                            .buttonStyle(RMDefaultButtonStyle())
                        }

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

struct DockHotkeyRecorderView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text("Toggle Dock")
            Spacer()
            Button(action: { isRecording.toggle() }) {
                Text(isRecording ? "Press keys\u{2026}" : dockHotkeyDisplayString)
                    .frame(minWidth: 100)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .overlay(
                DockHotkeyListenerView(isRecording: $isRecording)
                    .frame(width: 0, height: 0)
            )
        }
    }

    private var dockHotkeyDisplayString: String {
        var parts: [String] = []
        if settings.dockHotkeyModifiers & UInt32(controlKey) != 0 { parts.append("\u{2303}") }
        if settings.dockHotkeyModifiers & UInt32(optionKey) != 0 { parts.append("\u{2325}") }
        if settings.dockHotkeyModifiers & UInt32(shiftKey) != 0 { parts.append("\u{21E7}") }
        if settings.dockHotkeyModifiers & UInt32(cmdKey) != 0 { parts.append("\u{2318}") }
        parts.append(AppSettings.keyName(for: settings.dockHotkeyCode))
        return parts.joined()
    }
}

struct DockHotkeyListenerView: NSViewRepresentable {
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> DockHotkeyNSView {
        let view = DockHotkeyNSView()
        view.onKeyRecorded = { keyCode, modifiers in
            let settings = AppSettings.shared
            settings.dockHotkeyCode = UInt32(keyCode)
            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift) { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option) { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            settings.dockHotkeyModifiers = carbonMods
            DispatchQueue.main.async { self.isRecording = false }
        }
        return view
    }

    func updateNSView(_ nsView: DockHotkeyNSView, context: Context) {
        if isRecording { nsView.window?.makeFirstResponder(nsView) }
    }
}

final class DockHotkeyNSView: NSView {
    var onKeyRecorded: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        guard !event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty else { return }
        onKeyRecorded?(event.keyCode, event.modifierFlags)
    }
}
