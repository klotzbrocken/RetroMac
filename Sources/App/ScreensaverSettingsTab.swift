import SwiftUI

/// Screensaver + boot-screen settings. The saver and boot-screen toggle apply to the
/// currently selected theme (settings.dockTheme); global on/off + idle delay are app-wide.
struct ScreensaverSettingsTab: View {
    @ObservedObject var settings = AppSettings.shared

    private var themeName: String { settings.dockTheme }

    private var themeConfig: DockThemeConfig? {
        ThemeManager.shared.availableThemes.first(where: { $0.name == themeName })?.config
    }

    private var saverBinding: Binding<String> {
        Binding(
            get: { settings.themeScreensaverOverrides[themeName] ?? themeConfig?.screensaver ?? "none" },
            set: { settings.themeScreensaverOverrides[themeName] = $0 }
        )
    }

    private var bootDefaultOn: Bool {
        themeConfig?.splashVideo != nil || themeConfig?.splashScreen != nil
    }

    private var bootBinding: Binding<Bool> {
        Binding(
            get: { settings.themeBootscreenEnabled[themeName] ?? bootDefaultOn },
            set: { settings.themeBootscreenEnabled[themeName] = $0 }
        )
    }

    var body: some View {
        Form {
            Section("Screensaver") {
                Toggle("Enable screensaver", isOn: $settings.screensaverEnabled)

                Stepper(value: $settings.screensaverIdleMinutes, in: 1...120) {
                    Text("Start after \(settings.screensaverIdleMinutes) min of inactivity")
                }
                .disabled(!settings.screensaverEnabled)

                Picker("Saver for “\(themeName)”", selection: saverBinding) {
                    ForEach(ScreensaverController.available, id: \.id) { s in
                        Text(s.name).tag(s.id)
                    }
                }

                HStack {
                    Button("Preview") { ScreensaverController.shared.start() }
                        .disabled(saverBinding.wrappedValue == "none")
                    Spacer()
                    Text("Tip: a “Screen Saver” icon on the desktop starts it instantly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Boot Screen") {
                Toggle("Show boot screen for “\(themeName)”", isOn: bootBinding)
                Text("Plays this theme's boot video or image when you switch to it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}
