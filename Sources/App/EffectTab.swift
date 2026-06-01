import SwiftUI

// MARK: - Effect Tab (merges old Shader + Display)

struct EffectTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var customPresetFiles: [String] = []
    @State private var expandedCategories: Set<String> = Set(PresetRegistry.categorizedPresets.map { $0.0.rawValue })

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: RMSpacing.xxl) {
                // Left column — Preview + Library
                leftColumn
                    .frame(maxWidth: .infinity)

                // Right column — Controls
                rightColumn
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .onAppear { refreshCustomPresets() }
    }

    // MARK: - Left Column

    private var isViewportActive: Bool {
        (NSApp.delegate as? AppDelegate)?.retroViewport.isActive ?? false
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Viewport preview — click to open the retro viewport window
            viewportPreview

            // Library
            RMSectionHeaderView(title: "Library", hint: "\(PresetRegistry.availablePresets.count) built-in \u{00B7} \(customPresetFiles.count) custom")
                .padding(.top, RMSpacing.xxl)

            presetLibrary
        }
    }

    private var viewportPreview: some View {
        Button {
            (NSApp.delegate as? AppDelegate)?.toggleViewport()
        } label: {
            ZStack {
                // Background — use the live preview image
                LivePreviewView()

                // Overlay label
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: isViewportActive ? "viewfinder.circle.fill" : "viewfinder.circle")
                                .font(.system(size: 13))
                            Text(isViewportActive ? "Viewport open" : "Open Viewport")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())

                        Spacer()

                        Text("\(settings.targetFPS) fps")
                            .font(.rmMono(size: 10.5))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Capsule())
                    }
                    .padding(10)
                }
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: RMRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: RMRadius.card)
                    .stroke(isViewportActive ? Color.rmAccent.opacity(0.6) : Color.rmBorder, lineWidth: isViewportActive ? 1.5 : 1)
            )
            .rmCardShadow()
        }
        .buttonStyle(.plain)
    }

    private var presetLibrary: some View {
        RMCard(bodyPadding: 0) {
            VStack(spacing: 0) {
                ForEach(PresetRegistry.categorizedPresets, id: \.0) { category, presets in
                    let catName = category.rawValue
                    let isExpanded = expandedCategories.contains(catName)

                    // Category header — clickable to expand/collapse
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isExpanded {
                                expandedCategories.remove(catName)
                            } else {
                                expandedCategories.insert(catName)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.rmTextTertiary)
                                .frame(width: 12)

                            Text(catName.uppercased())
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.5)
                                .foregroundColor(.rmTextTertiary)

                            Spacer()

                            Text("\(presets.count)")
                                .font(.rmMono(size: 10))
                                .foregroundColor(.rmTextTertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.rmSurface2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(
                        VStack(spacing: 0) {
                            Rectangle().fill(Color.rmDivider).frame(height: 1)
                            Spacer()
                            Rectangle().fill(Color.rmDivider).frame(height: 1)
                        }
                    )

                    // Preset rows — only when expanded
                    if isExpanded {
                        ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                            PresetRow(
                                preset: preset,
                                isActive: preset.id == settings.defaultPreset,
                                isLast: index == presets.count - 1
                            ) {
                                settings.defaultPreset = preset.id
                                // Apply the preset to the running overlay
                                if let delegate = NSApp.delegate as? AppDelegate {
                                    delegate.currentPresetName = preset.id
                                    try? delegate.overlayController?.renderer?.loadShader(named: preset.id)
                                    // Also update the viewport if it's open
                                    if delegate.retroViewport.isActive {
                                        delegate.retroViewport.switchPreset(preset.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Right Column

    private var rightColumn: some View {
        VStack(spacing: RMSpacing.xxl) {
            // Active effect controls
            activeEffectCard

            // Performance card
            performanceCard

            // Display target card
            displayTargetCard
        }
    }

    private var activeEffectCard: some View {
        RMCard(title: "Active effect", bodyPadding: 0) {
            VStack(spacing: 0) {
                // Intensity
                RMRow(label: "Intensity", hint: "Blend factor between original and shaded image.") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.defaultIntensity, in: 0...1)
                            .tint(.rmAccent)
                            .frame(width: 130)
                        Text("\(Int(settings.defaultIntensity * 100))%")
                            .font(.rmMono(size: 11))
                            .foregroundColor(.rmTextSecondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }

                // Vignette
                RMRow(label: "Vignette") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.vignetteIntensity, in: 0...1)
                            .tint(.rmAccent)
                            .frame(width: 130)
                        Text("\(Int(settings.vignetteIntensity * 100))%")
                            .font(.rmMono(size: 11))
                            .foregroundColor(.rmTextSecondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }

                // Scanline overlay
                RMRow(label: "Scanline overlay") {
                    Picker("", selection: $settings.scanlineOverlayName) {
                        Text("None").tag("")
                        Text("Light").tag("scanlines-light")
                        Text("Medium").tag("scanlines-medium")
                        Text("Heavy").tag("scanlines-heavy")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }

                // Glass reflection
                RMRow(label: "Glass reflection", isLast: true) {
                    Picker("", selection: $settings.reflectionName) {
                        Text("None").tag("")
                        Text("Subtle").tag("reflection-subtle")
                        Text("Strong").tag("reflection-strong")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }
            }
        }
    }

    private var performanceCard: some View {
        RMCard(title: "Performance", subtitle: "Higher quality uses more GPU.", bodyPadding: 0) {
            VStack(spacing: 0) {
                // Profile tiles
                HStack(spacing: 8) {
                    ForEach(PerformanceProfile.allCases) { profile in
                        ProfileTile(
                            profile: profile,
                            isActive: settings.performanceProfile == profile
                        ) {
                            settings.performanceProfile = profile
                        }
                    }
                }
                .padding(RMSpacing.card)

                Rectangle()
                    .fill(Color.rmDivider)
                    .frame(height: 1)

                // Low-latency mode
                RMRow(label: "Low-latency mode", hint: "Forces 60 fps. Reduces mouse lag, uses more GPU.", isLast: true) {
                    Toggle("", isOn: $settings.lowLatencyMode)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                }
            }
        }
    }

    private var displayTargetCard: some View {
        RMCard(title: "Display target", bodyPadding: 0) {
            VStack(spacing: 0) {
                let screens = NSScreen.screens
                ForEach(Array(screens.enumerated()), id: \.offset) { index, screen in
                    HStack(spacing: 10) {
                        Image(systemName: "display")
                            .font(.system(size: 14))
                            .foregroundColor(.rmTextSecondary)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(screen.localizedName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.rmTextPrimary)
                        }

                        Spacer()

                        Text("\(Int(screen.frame.width))\u{00D7}\(Int(screen.frame.height))")
                            .font(.rmMono(size: 11))
                            .foregroundColor(.rmTextTertiary)

                        if screen.displayID == (settings.targetDisplayID == 0 ? CGMainDisplayID() : settings.targetDisplayID) {
                            RMChip(text: "Active", tone: .on, showDot: false)
                        } else {
                            Button("Use") {
                                settings.targetDisplayID = screen.displayID
                            }
                            .buttonStyle(RMDefaultButtonStyle())
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 11)
                    .padding(.horizontal, RMSpacing.card)

                    if index < screens.count - 1 {
                        Rectangle()
                            .fill(Color.rmDivider)
                            .frame(height: 1)
                            .padding(.horizontal, RMSpacing.card)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func refreshCustomPresets() {
        let fm = FileManager.default
        let dir = settings.customPresetsDirectory
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        customPresetFiles = files
            .filter { $0.pathExtension == "metal" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }
}

// MARK: - Preset Row

private struct PresetRow: View {
    let preset: PresetInfo
    let isActive: Bool
    let isLast: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Mini swatch
                    presetSwatch

                    // Name + description
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preset.displayName)
                            .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                            .tracking(-0.05)
                            .foregroundColor(isActive ? .rmAccentText : .rmTextPrimary)

                        Text(preset.description)
                            .font(.rmSecondary)
                            .foregroundColor(isActive ? .rmAccentText.opacity(0.85) : .rmTextSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.rmAccentText)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(isActive ? Color.rmAccentSoft : Color.clear)

                if !isLast {
                    Rectangle()
                        .fill(Color.rmDivider)
                        .frame(height: 1)
                        .padding(.horizontal, 14)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var presetSwatch: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(red: 0.08, green: 0.10, blue: 0.14))
                .frame(width: 44, height: 30)

            // Scanline stripes
            VStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                }
            }
            .frame(width: 40, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            // Vignette
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.4)],
                center: .center,
                startRadius: 8,
                endRadius: 22
            )
            .frame(width: 44, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.black.opacity(0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - Profile Tile

private struct ProfileTile: View {
    let profile: PerformanceProfile
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Image(systemName: profile.icon)
                    .font(.system(size: 14))
                    .foregroundColor(isActive ? .rmAccentText : .rmTextPrimary)

                Text(profile.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(isActive ? .rmAccentText : .rmTextPrimary)

                Text(profile.description)
                    .font(.system(size: 10.5))
                    .foregroundColor(isActive ? .rmAccentText : .rmTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(isActive ? Color.rmAccentSoft : Color.rmSurface)
            .clipShape(RoundedRectangle(cornerRadius: RMRadius.tile))
            .overlay(
                RoundedRectangle(cornerRadius: RMRadius.tile)
                    .stroke(isActive ? Color.rmAccent.opacity(0.7) : Color.rmBorder, lineWidth: isActive ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// NSScreen.displayID is defined in AppDelegate.swift
