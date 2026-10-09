import SwiftUI
import AppKit

/// Settings for Favourite (called Retro Mode before): the look one click puts on, and what it hides.
struct RetroModeTab: View {
    @ObservedObject private var settings = AppSettings.shared

    private var themeNames: [String] { ThemeManager.shared.availableThemes.map { $0.name } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RMSpacing.section) {
                Text("Favourite puts on your favourite look in one click and hides distractions, then restores everything when you turn it off. Switch it from the wand icon at the top of the menu-bar popover.")
                    .font(.rmSecondary)
                    .foregroundColor(.rmTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                RMCard(title: "Your favourite look", bodyPadding: 0) {
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
                    Label("Switch Favourite now", systemImage: "wand.and.stars")
                }
                .buttonStyle(RMPrimaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sw(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding).toggleStyle(.switch).tint(.rmAccent)
    }
}
