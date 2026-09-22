import SwiftUI
import AppKit

/// Settings ▸ Desktop — everything the active theme puts ON the desktop, in one place.
///
/// These controls used to be scattered: wallpaper and icons were reachable only from the
/// desktop's own context menu, icon size sat in the Themes tab, and a removed icon could not be
/// brought back at all — "Remove" reads like a delete but only hides the entry, with nothing in
/// the interface to undo it. Everything here is stored PER THEME, so switching themes shows that
/// theme's own arrangement.
struct DesktopSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    /// Per-theme storage key; matches what DesktopIconsController persists under.
    private var themeKey: String { ThemeManager.shared.activeTheme?.config.settingsKey ?? "" }
    private var themeName: String { ThemeManager.shared.activeTheme?.name ?? "No theme" }
    private var themeConfig: DockThemeConfig? { ThemeManager.shared.activeTheme?.config }

    /// Icons the theme itself defines, plus anything the user added by hand.
    private var allEntries: [DockThemeConfig.DesktopIconEntry] {
        (themeConfig?.desktopIcons ?? []) + custom.added
    }

    @State private var custom = DesktopStore.ThemeCustom()
    /// Which theme `custom` was loaded for.
    ///
    /// `themeKey` is computed live from the active theme, but `custom` is view state loaded once.
    /// Switch theme from the status menu with this tab open and the two disagree: the icon list
    /// already shows the new theme while the toggles still hold the old theme's record, and the
    /// next edit writes it under the new key. That is not a wrong flag, it is data loss —
    /// `DesktopStore.save` replaces the WHOLE record, so free-drag icon positions and hand-added
    /// shortcuts of the new theme go with it.
    @State private var loadedForTheme = ""
    @State private var refresh = false          // forces a redraw after a store write

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: RMSpacing.section) {
                if ThemeManager.shared.activeTheme == nil {
                    RMCard(title: "No theme active") {
                        Text("Pick a theme in the Themes tab first — the desktop is part of a theme.")
                            .font(.rmSecondary).foregroundColor(.rmTextSecondary)
                    }
                } else {
                    wallpaperCard
                    menuBarCard
                    iconsCard
                    widgetsCard
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .onAppear(perform: reload)
        // The settings window is retained and not released when closed, so `custom` outlives both
        // a close/reopen and a theme switch unless it is reloaded explicitly.
        .onChange(of: themeKey) { _, _ in reload() }
    }

    // MARK: - Wallpaper

    private var wallpaperCard: some View {
        RMCard(title: "Wallpaper", subtitle: "Applies to \(themeName).", bodyPadding: 0) {
            VStack(spacing: 0) {
                if let options = themeConfig?.wallpapers, !options.isEmpty {
                    RMRow(label: "Bundled wallpaper",
                          hint: options.contains { $0.tiled == true } ? "Patterns are tiled edge to edge." : nil) {
                        Picker("", selection: Binding(
                            get: { settings.themeWallpaperOverrides[themeKey] ?? (themeConfig?.wallpaper ?? "") },
                            set: { file in
                                settings.themeCustomWallpaper[themeKey] = nil
                                settings.themeWallpaperOverrides[themeKey] = file
                                ThemeManager.shared.applyWallpaper()
                            })) {
                            ForEach(options, id: \.file) { opt in
                                Text(opt.name).tag(opt.file)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                }
                RMRow(label: "Own image",
                      hint: customWallpaperName ?? "Any picture instead of the theme's own.") {
                    HStack(spacing: 8) {
                        Button("Choose…") { chooseWallpaper() }
                            .buttonStyle(RMGhostButtonStyle())
                        if settings.themeCustomWallpaper[themeKey] != nil {
                            Button("Remove") {
                                settings.themeCustomWallpaper[themeKey] = nil
                                ThemeManager.shared.applyWallpaper()
                            }
                            .buttonStyle(RMGhostButtonStyle())
                        }
                    }
                }
                RMRow(label: "Reset to the theme's default", isLast: true) {
                    Button("Reset") {
                        settings.themeCustomWallpaper[themeKey] = nil
                        settings.themeWallpaperOverrides[themeKey] = nil
                        ThemeManager.shared.applyWallpaper()
                    }
                    .buttonStyle(RMGhostButtonStyle())
                }
            }
        }
    }

    // MARK: - Menu bar

    /// The macOS menu bar is the one piece of the desktop RetroMac cannot redraw, so this is
    /// what can be done to it: tint the picture behind it, and put a retro Apple over the real one.
    private var menuBarCard: some View {
        RMCard(title: "Menu bar", bodyPadding: 0) {
            VStack(spacing: 0) {
                // Only where the era actually had a Mac menu bar. The Windows themes hide it,
                // and every other family draws a bar of its own.
                if let cfg = themeConfig, ThemeManager.menuBarStyle(for: cfg) != nil {
                    RMRow(label: "Tint the menu bar",
                          hint: "Paints a strip of \(themeName)'s bar colour into the top of the wallpaper, behind the translucent menu bar.") {
                        Toggle("", isOn: $settings.menuBarTint)
                            .toggleStyle(.switch)
                            .tint(.rmAccent)
                            .labelsHidden()
                            .onChange(of: settings.menuBarTint) { _, _ in
                                ThemeManager.shared.applyWallpaper()
                            }
                            .help("Last run: \(ThemeManager.lastMenuBarTintNote)")
                    }
                }
                RMRow(label: "Apple logo",
                      hint: RainbowAppleController.canPlaceCover
                        ? "A retro Apple over the system one. Also cycled from the flyout."
                        : "Needs the Accessibility permission (General): the cover is placed by asking the menu bar where the Apple is, and without that it would sit in the wrong place — so it stays off.",
                      isLast: true) {
                    Picker("", selection: $settings.menuBarAppleStyle) {
                        Text("Off").tag(0)
                        Text("Rainbow").tag(1)
                        Text("Aqua").tag(2)
                        Text("Aqua Classic").tag(3)
                        Text("Apple Hell").tag(4)
                        Text("Futurama").tag(5)
                        Text("Black (1-bit)").tag(6)
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 140)
                    .disabled(!RainbowAppleController.canPlaceCover)
                }
            }
        }
    }

    private var customWallpaperName: String? {
        settings.themeCustomWallpaper[themeKey].map { ($0 as NSString).lastPathComponent }
    }

    private func chooseWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a wallpaper image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.themeCustomWallpaper[themeKey] = url.path
        ThemeManager.shared.applyWallpaper()
    }

    // MARK: - Desktop icons

    private var iconsCard: some View {
        RMCard(title: "Desktop icons",
               subtitle: "Switch an icon off to hide it. Nothing is deleted, so you can bring it back.",
               bodyPadding: 0) {
            VStack(spacing: 0) {
                let entries = allEntries
                if entries.isEmpty {
                    RMNote(text: "This theme places no icons on the desktop.")
                } else {
                    ForEach(Array(entries.enumerated()), id: \.offset) { idx, entry in
                        RMRow(label: entry.name,
                              isLast: idx == entries.count - 1 && hiddenCount == 0) {
                            Toggle("", isOn: Binding(
                                get: { !custom.removed.contains(entry.name) },
                                set: { visible in setVisible(entry.name, visible) }))
                            .toggleStyle(.switch)
                            .tint(.rmAccent)
                            .labelsHidden()
                        }
                    }
                    if hiddenCount > 0 {
                        RMRow(label: "Restore hidden icons",
                              hint: "\(hiddenCount) hidden on \(themeName).",
                              isLast: true) {
                            Button("Restore all") { restoreAll() }
                                .buttonStyle(RMGhostButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private var hiddenCount: Int { custom.removed.count }

    private func setVisible(_ name: String, _ visible: Bool) {
        if visible { custom.removed.removeAll { $0 == name } }
        else if !custom.removed.contains(name) { custom.removed.append(name) }
        persist()
    }

    private func restoreAll() {
        custom.removed.removeAll()
        persist()
    }

    private func persist() {
        // Never write a record that belongs to a different theme. Belt and braces next to the
        // `.id(themeKey)` on the tab itself: that ties the view's identity to the theme, but it
        // depends on how SwiftUI decides to rebuild, and this does not.
        guard loadedForTheme == themeKey else {
            reload()
            return
        }
        DesktopStore.save(custom, theme: themeKey)
        DesktopIconsController.shared.update()
        refresh.toggle()
    }

    private func reload() {
        loadedForTheme = themeKey
        custom = DesktopStore.load(theme: themeKey)
    }

    // MARK: - Size & widgets

    private var widgetsCard: some View {
        RMCard(title: "Size & widgets", bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Icon size",
                      hint: settings.desktopIconScaleLinked ? "Following the dock icon size." : nil) {
                    HStack(spacing: 8) {
                        // While linked the slider SHOWS the dock's value, so thumb and number agree.
                        Slider(value: Binding(
                            get: { settings.desktopIconScaleLinked ? settings.dockIconScale : settings.desktopIconScale },
                            set: { settings.desktopIconScale = $0 }), in: 0.5...2.0, step: 0.1)
                            .tint(.rmAccent)
                            .frame(width: 140)
                            .disabled(settings.desktopIconScaleLinked)
                        Text("\(Int((settings.desktopIconScaleLinked ? settings.dockIconScale : settings.desktopIconScale) * 100))%")
                            .font(.rmMono(size: 11))
                            .foregroundColor(.rmTextSecondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                RMRow(label: "Match the dock icon size") {
                    Toggle("", isOn: Binding(
                        get: { settings.desktopIconScaleLinked },
                        set: { on in
                            // Unlinking starts where the dock is, so nothing jumps.
                            if !on { settings.desktopIconScale = settings.dockIconScale }
                            settings.desktopIconScaleLinked = on
                        }))
                        .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                }
                RMRow(label: "Show theme widgets",
                      hint: "Clock, CPU monitor and the other gadgets a theme brings along.",
                      isLast: true) {
                    Toggle("", isOn: $settings.themeIncludeWidgets)
                        .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                        .onChange(of: settings.themeIncludeWidgets) { _, _ in
                            // Read while the theme is applied, so re-apply it now rather than
                            // leaving the switch to take effect at the next theme change.
                            AppDelegate.shared?.applyThemeWidgetsNow()
                        }
                }
            }
        }
    }
}
