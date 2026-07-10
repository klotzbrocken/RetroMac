import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Advanced settings — power-user options collected behind one tab so the rest of the
/// Settings window stays simple. A segmented control switches between sub-sections; only
/// one is shown at a time (each reuses an existing view with its own scroll region).
struct AdvancedTab: View {
    @State private var section: AdvSection = .performance

    enum AdvSection: String, CaseIterable, Identifiable {
        case performance = "Performance"
        case presets = "Presets"
        case effects = "Effects"
        case hotkeys = "Hotkeys"
        case rules = "Per-App"
        case system = "System"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Section").font(.rmSecondary).foregroundColor(.rmTextSecondary)
                Picker("", selection: $section) {
                    ForEach(AdvSection.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 180)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Rectangle().fill(Color.rmDivider).frame(height: 1)

            Group {
                switch section {
                case .performance: PerformanceSection()
                case .presets:     CustomPresetsSection()
                case .effects:     EffectsSection()
                case .hotkeys:     ShortcutsTab()
                case .rules:       PerAppRulesTab()
                case .system:      SystemSettingsTab()
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
                        RMRow(label: "Low-latency mode", hint: "Forces 60 fps. Less mouse lag, more GPU.", isLast: true) {
                            Toggle("", isOn: $settings.lowLatencyMode)
                                .toggleStyle(.switch)
                                .tint(.rmAccent)
                                .labelsHidden()
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}

/// Overlay effects layered on top of the active shader — scanline overlay + glass
/// reflection (restored from the former Effect tab; selection lives only here now).
private struct EffectsSection: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var license = LicenseManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: RMSpacing.section) {
                RMCard(title: "Effect scope",
                       subtitle: license.isLicensed
                            ? "Draw the effect over everything, or only on the wallpaper — animated, behind your icons and windows."
                            : "Draw the effect over everything, or only on the wallpaper (Pro) — animated, behind your icons and windows.",
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
                                Text(license.isLicensed ? "Wallpaper only" : "Wallpaper only 🔒").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden().frame(width: 240)
                        }
                    }
                }
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
