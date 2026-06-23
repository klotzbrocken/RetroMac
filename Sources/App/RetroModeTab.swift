import SwiftUI
import AppKit

/// Settings for the one-click Retro Mode: pick the favourite look and what to hide.
struct RetroModeTab: View {
    @ObservedObject private var settings = AppSettings.shared

    private var themeNames: [String] { ThemeManager.shared.availableThemes.map { $0.name } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RMSpacing.section) {
                Text("Retro Mode applies a favourite look in one click and hides distractions, then restores everything when you turn it off. Toggle it from the wand icon at the top of the menu-bar popover.")
                    .font(.rmSecondary)
                    .foregroundColor(.rmTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                RMCard(title: "Favourite", bodyPadding: 0) {
                    VStack(spacing: 0) {
                        RMRow(label: "Theme") {
                            Picker("", selection: $settings.retroModeTheme) {
                                ForEach(themeNames, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden().frame(width: 180)
                        }
                        RMRow(label: "Shader") {
                            Picker("", selection: $settings.retroModeShader) {
                                Text("Theme default").tag("")
                                ForEach(PresetRegistry.builtinPresets, id: \.id) { preset in
                                    Text(preset.displayName).tag(preset.id)
                                }
                            }
                            .labelsHidden().frame(width: 180)
                        }
                        RMRow(label: "Activate shader on enter", isLast: true) {
                            sw($settings.retroModeActivateShader)
                        }
                    }
                }

                RMCard(title: "Hide while active", bodyPadding: 0) {
                    VStack(spacing: 0) {
                        RMRow(label: "Dock") { sw($settings.retroModeHideDock) }
                        RMRow(label: "Menu bar") { sw($settings.retroModeHideMenuBar) }
                        RMRow(label: "Desktop icons", isLast: true) { sw($settings.retroModeHideDesktopIcons) }
                    }
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

    private func sw(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding).toggleStyle(.switch).tint(.rmAccent).labelsHidden()
    }
}
