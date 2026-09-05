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
                    iconsCard
                    widgetsCard
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .onAppear(perform: reload)
    }

    // MARK: - Wallpaper

    private var wallpaperCard: some View {
        RMCard(title: "Wallpaper", subtitle: "Applies to \(themeName).") {
            VStack(spacing: 0) {
                if let options = themeConfig?.wallpapers, !options.isEmpty {
                    RMRow(label: "Bundled wallpaper") {
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
                        .frame(width: 190)
                    }
                }
                RMRow(label: "Own image",
                      hint: customWallpaperName ?? "Use any picture instead of the theme's own.") {
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
                // Lives with the wallpaper because that is literally what it changes: the tint is
                // painted into the top of the rendered wallpaper. It sat under Advanced > Hotkeys
                // next to the menu-bar hiding switch at first, where nobody found it.
                                // Only where the era actually had a Mac menu bar. The Windows themes hide it,
                // and every other family draws a bar of its own, so the control was offering to
                // paint a grey band across the top of a wallpaper for no reason.
                if let cfg = themeConfig, ThemeManager.menuBarStyle(for: cfg) != nil {
                RMRow(label: "Tint the menu bar",
                      hint: "macOS cannot recolour the menu bar, but it is translucent over the desktop picture. This paints a strip of menu-bar height into the top of the wallpaper, matched to how \(themeName) drew its bar.\nLast run — \(ThemeManager.lastMenuBarTintNote)") {
                    Toggle("", isOn: $settings.menuBarTint)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                        .onChange(of: settings.menuBarTint) { _, _ in
                            ThemeManager.shared.applyWallpaper()
                        }
                }
                }
                // An option OF Live Wallpaper, not a mode beside it: Live Wallpaper is still
                // switched on wherever it always was, in the flyout and the menu. This only says
                // how far it reaches once it is on. Application windows are never included —
                // they are not RetroMac's windows to touch.
                RMRow(label: "Live Wallpaper covers the whole desktop",
                      hint: "Runs the desktop picture, RetroMac's desktop icons and the retro dock through the selected shader in ONE pass, so the pattern runs through all three instead of restarting in each. Application windows are never touched. While this is on the dock sits behind them, and the effect runs at the display's frame rate because it now carries the dock's own animation \u{2014} unless you picked a frame rate yourself under Shader.") {
                    Toggle("", isOn: $settings.liveWallpaperPlus)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                        .onChange(of: settings.liveWallpaperPlus) { _, _ in
                            (NSApp.delegate as? AppDelegate)?.restartLiveWallpaperScope()
                        }
                }
                RMRow(label: "Reset to theme default", isLast: true) {
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
               subtitle: "Switch an icon off to hide it. Nothing is deleted, so you can bring it back.") {
            VStack(spacing: 0) {
                let entries = allEntries
                if entries.isEmpty {
                    Text("This theme places no icons on the desktop.")
                        .font(.rmSecondary).foregroundColor(.rmTextSecondary)
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
        DesktopStore.save(custom, theme: themeKey)
        DesktopIconsController.shared.update()
        refresh.toggle()
    }

    private func reload() { custom = DesktopStore.load(theme: themeKey) }

    // MARK: - Size & widgets

    private var widgetsCard: some View {
        RMCard(title: "Size & widgets") {
            VStack(spacing: 0) {
                RMRow(label: "Icon size",
                      hint: settings.desktopIconScaleLinked ? "Following the dock icon size." : nil) {
                    HStack(spacing: 8) {
                        Slider(value: $settings.desktopIconScale, in: 0.5...2.0)
                            .frame(width: 130)
                            .disabled(settings.desktopIconScaleLinked)
                        Text("\(Int((settings.desktopIconScaleLinked ? settings.dockIconScale : settings.desktopIconScale) * 100))%")
                            .font(.rmMono(size: 11))
                            .foregroundColor(.rmTextSecondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                RMRow(label: "Match dock icon size") {
                    Toggle("", isOn: $settings.desktopIconScaleLinked)
                        .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                }
                RMRow(label: "Show theme widgets",
                      hint: "Clock, CPU monitor and the other desktop gadgets a theme brings along.",
                      isLast: true) {
                    Toggle("", isOn: $settings.themeIncludeWidgets)
                        .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                }
            }
        }
    }
}
