import SwiftUI

/// Screensaver settings. The saver applies to the currently selected theme (settings.dockTheme);
/// the on/off switch and the idle delay are app-wide. The boot screen switch is under Themes ▸
/// Behaviour, next to the other things that happen when a theme starts.
struct ScreensaverSettingsTab: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var installMessage = ""

    /// Storage key for the per-theme saver — `dockTheme` holds the stable theme id, never the
    /// display name.
    private var themeName: String { settings.dockTheme }

    /// What the user should actually SEE — the id is an internal identifier.
    private var themeLabel: String {
        ThemeManager.shared.theme(for: themeName).map { ThemeManager.displayName(for: $0.name) } ?? themeName
    }

    /// Copy the bundled .saver modules into ~/Library/Screen Savers.
    private func installSavers() {
        guard let src = Bundle.main.resourceURL?.appendingPathComponent("Savers"),
              let savers = try? FileManager.default.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
                  .filter({ $0.pathExtension == "saver" }), !savers.isEmpty else {
            installMessage = "No bundled savers found in this build."
            return
        }
        let destDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Screen Savers", isDirectory: true)
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        var ok = 0
        for s in savers {
            let dest = destDir.appendingPathComponent(s.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: s, to: dest)) != nil { ok += 1 }
        }
        installMessage = "Installed \(ok) savers. Pick them in System Settings \u{25B8} Screen Saver."
    }

    private var themeConfig: DockThemeConfig? {
        ThemeManager.shared.theme(for: themeName)?.config
    }

    private var saverBinding: Binding<String> {
        Binding(
            get: { settings.themeScreensaverOverrides[themeName] ?? themeConfig?.screensaver ?? "none" },
            set: { settings.themeScreensaverOverrides[themeName] = $0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: RMSpacing.section) {
                RMCard(title: "Screensaver", bodyPadding: 0) {
                    VStack(spacing: 0) {
                        RMRow(label: "Screensaver") {
                            Toggle("", isOn: $settings.screensaverEnabled)
                                .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                        }
                        RMRow(label: "Start after",
                              hint: "Minutes without input.") {
                            HStack(spacing: 8) {
                                Text("\(settings.screensaverIdleMinutes) min")
                                    .font(.rmMono(size: 11.5)).foregroundColor(.rmTextSecondary)
                                Stepper("", value: $settings.screensaverIdleMinutes, in: 1...120)
                                    .labelsHidden()
                            }
                            .disabled(!settings.screensaverEnabled)
                        }
                        RMRow(label: "Saver for \u{201C}\(themeLabel)\u{201D}",
                              hint: "A \u{201C}Screen Saver\u{201D} icon on the desktop starts it at once.") {
                            Picker("", selection: saverBinding) {
                                ForEach(ScreensaverController.available, id: \.id) { s in
                                    Text(s.name).tag(s.id)
                                }
                            }
                            .labelsHidden().frame(width: 180)
                        }
                        RMRow(label: "Preview", isLast: true) {
                            Button("Start now") { ScreensaverController.shared.start() }
                                .buttonStyle(RMDefaultButtonStyle())
                                .disabled(saverBinding.wrappedValue == "none")
                        }
                    }
                }

                RMCard(title: "macOS screensavers",
                       subtitle: "Pipes, FlowerBox, Flying Toasters and Flurry as real .saver modules for System Settings \u{25B8} Screen Saver.",
                       bodyPadding: 0) {
                    RMRow(label: "Install",
                          hint: installMessage.isEmpty ? nil : installMessage,
                          isLast: true) {
                        Button("Install\u{2026}") { installSavers() }
                            .buttonStyle(RMDefaultButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}
