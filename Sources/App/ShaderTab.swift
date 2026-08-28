import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Everything about the shader itself, in one place.
///
/// This was the "Advanced" tab, which is how the app's own centrepiece ended up with no home:
/// four of its six sections were shader topics, while the on/off state, the per-theme choice and
/// the launch behaviour sat in three other places. Hotkeys and system setup moved out to tabs of
/// their own; what stays is the effect, from the preset down to when it runs.
struct ShaderTab: View {
    @State private var section: ShaderSection = .preset

    enum ShaderSection: String, CaseIterable, Identifiable {
        case preset = "Preset"
        case look = "Look"
        case scope = "Where"
        case rules = "Per-App"
        case performance = "Performance"
        case when = "When"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Section").font(.rmSecondary).foregroundColor(.rmTextSecondary)
                Picker("", selection: $section) {
                    ForEach(ShaderSection.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 180)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Rectangle().fill(Color.rmDivider).frame(height: 1)

            Group {
                switch section {
                case .preset:      CustomPresetsSection()
                case .look:        LookSection()
                case .scope:       ScopeSection()
                case .rules:       PerAppRulesTab()
                case .performance: PerformanceSection()
                case .when:        WhenSection()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Single "Quality" control (replaces the old four-tile performance card + scattered
/// toggles). The profile already maps to fps / half-resolution internally.
private struct PerformanceSection: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(spacing: RMSpacing.section) {
                RMCard(title: "Performance", subtitle: "Higher quality uses more GPU.", bodyPadding: 0) {
                    VStack(spacing: 0) {
                        RMRow(label: "Quality", hint: "Balances GPU load against visual fidelity.", isLast: false) {
                            Picker("", selection: $settings.performanceProfile) {
                                ForEach(PerformanceProfile.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                        }
                        RMRow(label: "Frame rate",
                              hint: "How often the effect redraws. Higher is smoother while scrolling or dragging windows, and costs more GPU and battery.",
                              isLast: true) {
                            Picker("", selection: $settings.targetFPS) {
                                Text("30 fps \u{2014} lower power").tag(30)
                                Text("60 fps \u{2014} smoother").tag(60)
                                // Only where a display can actually show it: a 100 Hz panel would
                                // silently cap 120, which looks like the setting does nothing.
                                if NSScreen.screens.contains(where: { $0.maximumFramesPerSecond >= 120 }) {
                                    Text("120 fps \u{2014} ProMotion").tag(120)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                            .onChange(of: settings.targetFPS) { _, _ in
                                // Mark it as a deliberate choice so the Quality picker stops
                                // resetting it (see AppSettings.applyPerformanceProfile).
                                settings.targetFPSUserSet = true
                                (NSApp.delegate as? AppDelegate)?.reapplyCaptureSettings()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}

/// Where the effect draws: over everything, or only on the wallpaper.
private struct ScopeSection: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var license = LicenseManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: RMSpacing.section) {
                RMCard(title: "Effect scope",
                       subtitle: license.isLicensed
                            ? "Draw the effect over everything, or only on the wallpaper \u{2014} animated, behind your icons and windows."
                            : "Draw the effect over everything, or only on the wallpaper (Pro) \u{2014} animated, behind your icons and windows.",
                       bodyPadding: 0) {
                    VStack(spacing: 0) {
                        RMRow(label: "Apply to", isLast: true) {
                            Picker("", selection: Binding(
                                get: { settings.shaderWallpaperOnly && license.isLicensed },
                                set: { on in
                                    if on && !license.isLicensed {
                                        (NSApp.delegate as? AppDelegate)?.presentUnlockScreen()
                                    } else {
                                        settings.shaderWallpaperOnly = on
                                    }
                                })) {
                                Text("Whole screen").tag(false)
                                Text(license.isLicensed ? "Wallpaper only" : "Wallpaper only \u{1F512}").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden().frame(width: 240)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}

/// Extra layers drawn on top of whichever preset is running.
private struct LookSection: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(spacing: RMSpacing.section) {
                RMCard(title: "Overlay effects",
                       subtitle: "Extra layers drawn on top of the shader.",
                       bodyPadding: 0) {
                    VStack(spacing: 0) {
                        RMRow(label: "Scanline overlay") {
                            Picker("", selection: $settings.scanlineOverlayName) {
                                Text("None").tag("")
                                Text("Light").tag("scanlines-light")
                                Text("Medium").tag("scanlines-medium")
                                Text("Heavy").tag("scanlines-heavy")
                            }
                            .labelsHidden().frame(width: 180)
                        }
                        RMRow(label: "Scanline intensity") {
                            Slider(value: $settings.scanlineOverlayIntensity, in: 0...1)
                                .frame(width: 180)
                                .disabled(settings.scanlineOverlayName.isEmpty)
                        }
                        RMRow(label: "Glass reflection") {
                            Picker("", selection: $settings.reflectionName) {
                                Text("None").tag("")
                                Text("Subtle").tag("reflection-subtle")
                                Text("Strong").tag("reflection-strong")
                            }
                            .labelsHidden().frame(width: 180)
                        }
                        RMRow(label: "Reflection intensity", isLast: true) {
                            Slider(value: $settings.reflectionIntensity, in: 0...1)
                                .frame(width: 180)
                                .disabled(settings.reflectionName.isEmpty)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}

/// Mirrors the shader's on/off state into SwiftUI. The overlay can start asynchronously, so the
/// switch follows `.overlayStateChanged` rather than reading once and going stale.
private final class ShaderRunState: ObservableObject {
    @Published var isOn = AppDelegate.shared?.launcherShaderActive ?? false
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .overlayStateChanged, object: nil, queue: .main) { [weak self] _ in
            self?.isOn = AppDelegate.shared?.launcherShaderActive ?? false
        }
    }
    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }
}

/// When the shader runs: right now, at launch, for this theme, and around sleep.
///
/// These four lived in three different places, which is how the app came to remember "off for
/// this theme" and then switch the shader back on at the next launch without anyone noticing.
private struct WhenSection: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var run = ShaderRunState()

    private var themeKey: String { ThemeManager.shared.activeTheme?.config.settingsKey ?? settings.dockTheme }
    private var themeName: String { ThemeManager.shared.activeTheme?.config.name ?? "" }
    private var disabledForTheme: Bool { settings.themeShaderDisabled[themeKey] == true }
    private var presetDisplayName: String {
        PresetRegistry.availablePresets.first(where: { $0.id == settings.defaultPreset })?.displayName
            ?? settings.defaultPreset
    }

    var body: some View {
        ScrollView {
            VStack(spacing: RMSpacing.section) {
                RMCard(title: "Running", bodyPadding: 0) {
                    VStack(spacing: 0) {
                        RMRow(label: "Shader",
                              hint: "The same switch as the one in the menu-bar popover.") {
                            Toggle("", isOn: Binding(get: { run.isOn },
                                                     set: { _ in AppDelegate.shared?.launcherToggleShader() }))
                                .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                        }
                        RMRow(label: "Turn the shader on when RetroMac launches", isLast: true) {
                            Toggle("", isOn: $settings.enableOnLaunch)
                                .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                        }
                    }
                }

                if settings.dockEnabled && !themeName.isEmpty {
                    RMCard(title: "For \u{201C}\(themeName)\u{201D}",
                           subtitle: "Switching the shader off here is remembered for this theme, and it outranks the launch switch above.",
                           bodyPadding: 0) {
                        VStack(spacing: 0) {
                            RMRow(label: "Shader") {
                                Toggle("", isOn: Binding(
                                    get: { !disabledForTheme },
                                    set: { on in settings.themeShaderDisabled[themeKey] = on ? nil : true }))
                                    .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                            }
                            RMRow(label: "Preset",
                                  hint: "Kept even while the shader is off for this theme.",
                                  isLast: true) {
                                Picker("", selection: Binding(
                                    get: { settings.themePresetOverrides[themeKey]
                                            ?? ThemeManager.shared.activeTheme?.config.defaultPreset ?? "" },
                                    set: { settings.themePresetOverrides[themeKey] = $0 })) {
                                    ForEach(PresetRegistry.builtinPresets, id: \.id) { preset in
                                        Text(preset.displayName).tag(preset.id)
                                    }
                                }
                                .labelsHidden().frame(width: 180)
                                .disabled(disabledForTheme)
                            }
                        }
                    }
                }

                RMCard(title: "When my Mac sleeps", bodyPadding: 0) {
                    VStack(spacing: 0) {
                        RMRow(label: "Stop overlay on sleep or lock") {
                            Toggle("", isOn: $settings.stopOnSleep)
                                .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                        }
                        RMRow(label: "Resume overlay after wake") {
                            Toggle("", isOn: $settings.resumeAfterSleep)
                                .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                                .disabled(!settings.stopOnSleep)
                        }
                        RMRow(label: "Reset to default preset after wake",
                              hint: "Restores \(presetDisplayName) regardless of last-used preset.",
                              isLast: true) {
                            Toggle("", isOn: $settings.resetOnWake)
                                .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                                .disabled(!settings.stopOnSleep || !settings.resumeAfterSleep)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}

/// Import / manage custom .metal CRT shaders. Imported files land in the custom-presets
/// directory and appear under "Shader Presets" in the status-bar menu.
private struct CustomPresetsSection: View {
    @State private var files: [String] = []

    var body: some View {
        ScrollView {
            VStack(spacing: RMSpacing.section) {
                installedCard

                RMCard(title: "Custom presets",
                       subtitle: "Import your own .metal CRT shaders — they show up under Shader Presets in the menu.",
                       bodyPadding: 0) {
                    VStack(spacing: 0) {
                        RMRow(label: "Import shaders") {
                            Button("Import .metal\u{2026}") { importMetal() }
                                .buttonStyle(RMDefaultButtonStyle())
                        }
                        RMRow(label: "How to build a shader",
                              hint: "Metal format + a copy-paste template.",
                              isLast: files.isEmpty) {
                            Button("Open guide") {
                                if let u = URL(string: "https://github.com/klotzbrocken/RetroMac/blob/main/docs/CUSTOM-SHADERS.md") {
                                    NSWorkspace.shared.open(u)
                                }
                            }
                            .buttonStyle(RMDefaultButtonStyle())
                        }
                        ForEach(Array(files.enumerated()), id: \.offset) { idx, name in
                            RMRow(label: (name as NSString).deletingPathExtension,
                                  isLast: idx == files.count - 1) {
                                Button("Remove") { remove(name) }
                                    .buttonStyle(RMGhostButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .onAppear(perform: refresh)
    }

    /// Read-only catalogue of the built-in presets, grouped by category (collapsed).
    private var installedCard: some View {
        RMCard(title: "Installed presets",
               subtitle: "Built-in shaders — choose them from Shader Presets in the menu.",
               bodyPadding: RMSpacing.card) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(PresetRegistry.categorizedPresets, id: \.0) { category, presets in
                    DisclosureGroup("\(category.rawValue)  (\(presets.count))") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(presets, id: \.id) { p in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.rmTextPrimary)
                                    Text(p.description)
                                        .font(.rmSecondary)
                                        .foregroundColor(.rmTextSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, 4)
                        .padding(.leading, 8)
                    }
                    .font(.system(size: 12, weight: .semibold))
                }
            }
        }
    }

    private func refresh() {
        let dir = AppSettings.shared.customPresetsDirectory
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        files = urls.filter { $0.pathExtension == "metal" }.map { $0.lastPathComponent }.sorted()
    }

    private func importMetal() {
        let panel = NSOpenPanel()
        if let metalType = UTType(filenameExtension: "metal") {
            panel.allowedContentTypes = [metalType]
        }
        panel.allowsMultipleSelection = true
        panel.message = "Select Metal shader files to import"
        guard panel.runModal() == .OK else { return }
        let dest = AppSettings.shared.customPresetsDirectory
        for url in panel.urls {
            let target = dest.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: target)   // overwrite on re-import
            try? FileManager.default.copyItem(at: url, to: target)
        }
        refresh()
    }

    private func remove(_ filename: String) {
        let url = AppSettings.shared.customPresetsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        refresh()
    }
}
