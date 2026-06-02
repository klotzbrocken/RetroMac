import SwiftUI
import AppKit

/// Settings for the one-click Retro Mode: pick the favourite look and what to hide.
struct RetroModeTab: View {
    @ObservedObject private var settings = AppSettings.shared

    private var themeNames: [String] { ThemeManager.shared.availableThemes.map { $0.name } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Retro Mode applies a favourite look in one click and hides distractions, then restores everything when you turn it off. Toggle it from the ✨ icon at the top of the menu-bar popover.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox("Favourite") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Theme", selection: $settings.retroModeTheme) {
                            ForEach(themeNames, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Shader", selection: $settings.retroModeShader) {
                            Text("Theme default").tag("")
                            ForEach(PresetRegistry.builtinPresets, id: \.id) { preset in
                                Text(preset.displayName).tag(preset.id)
                            }
                        }
                        Toggle("Activate shader on enter", isOn: $settings.retroModeActivateShader)
                    }
                    .padding(8)
                }

                GroupBox("Hide while active") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Dock", isOn: $settings.retroModeHideDock)
                        Toggle("Menu bar", isOn: $settings.retroModeHideMenuBar)
                        Toggle("Desktop icons", isOn: $settings.retroModeHideDesktopIcons)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                Button {
                    (NSApp.delegate as? AppDelegate)?.toggleRetroMode()
                } label: {
                    Label("Toggle Retro Mode now", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The Settings panel is a fixed light theme (Color.rmBg) — pin this tab to the
        // light color scheme so text/controls stay readable in system Dark Mode.
        .environment(\.colorScheme, .light)
    }
}
