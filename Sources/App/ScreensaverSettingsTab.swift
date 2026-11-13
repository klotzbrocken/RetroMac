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

    /// SETI@home Classic: one simulated client for the window, the background and the saver.
    private var setiCard: some View {
        RMCard(title: "SETI@home",
               subtitle: "A historical SETI@home Classic simulation. No real data analysis and no connection to the research project. The window, the background and the screensaver share one work unit." + (SETIController.shared.recovered ? " The saved state could not be read; a new work unit was started." : ""),
               bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "SETI@home", hint: "In the Windows themes' Start menu and under the telescope in the Mac themes' menu bar.") {
                    HStack(spacing: 8) {
                        Button("Open") { SETIController.shared.showWindow() }.buttonStyle(RMDefaultButtonStyle())
                        Button("Preview saver") { ScreensaverController.shared.start(saverID: "seti") }.buttonStyle(RMGhostButtonStyle())
                    }
                }
                RMRow(label: "Name", hint: "Shown under User Info. No account, nothing is sent.") {
                    TextField("", text: $settings.seti.userName).frame(width: 180)
                }
                RMRow(label: "Processing") {
                    Picker("", selection: $settings.seti.processing) {
                        Text("Only while shown").tag(SETIPrefs.Processing.whenIdle)
                        Text("Also in the background").tag(SETIPrefs.Processing.always)
                    }.labelsHidden().frame(width: 200)
                }
                RMRow(label: "Speed", hint: "Demonstration finishes a work unit in about four minutes.") {
                    Picker("", selection: $settings.seti.speed) {
                        Text("Historical").tag(SETISimulation.Speed.historical)
                        Text("Demonstration").tag(SETISimulation.Speed.demo)
                    }.labelsHidden().frame(width: 200)
                }
                RMRow(label: "Random candidates", hint: "Now and then a strong peak to examine. Never a claim that anything was found.") {
                    HStack(spacing: 8) {
                        Picker("", selection: $settings.seti.frequency) {
                            Text("Rare").tag(SETISimulation.Frequency.rare)
                            Text("Standard").tag(SETISimulation.Frequency.standard)
                            Text("Often").tag(SETISimulation.Frequency.often)
                        }.labelsHidden().frame(width: 110).disabled(!settings.seti.candidates)
                        Toggle("", isOn: $settings.seti.candidates).toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                    }
                }
                RMRow(label: "Client", hint: "Automatic follows the theme: Windows 3.08, Macintosh 2.01, or Mac OS X (reconstructed).") {
                    Picker("", selection: $settings.seti.profile) {
                        Text("Automatic").tag("auto")
                        Text("Windows 3.08").tag("windows")
                        Text("Macintosh 2.01").tag("mac")
                        Text("Mac OS X").tag("macosx")
                    }.labelsHidden().frame(width: 200)
                }
                RMRow(label: "Statistics", hint: "Work units completed and computer time.", isLast: true) {
                    HStack(spacing: 8) {
                        Button("Test candidate") { SETIController.shared.forceCandidate() }.buttonStyle(RMGhostButtonStyle())
                        Button("Reset statistics") { SETIController.shared.resetStatistics() }.buttonStyle(RMGhostButtonStyle())
                    }
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: RMSpacing.section) {
                RMCard(title: "Screensaver", bodyPadding: 0) {
                    VStack(spacing: 0) {
                        RMRow(label: "Screensaver") {
                            Toggle("", isOn: $settings.screensaverEnabled)
                                .toggleStyle(.switch).tint(.rmAccent)
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

                setiCard

                RMCard(title: "macOS screensavers",
                       subtitle: "Pipes, FlowerBox, Starfield Simulation, 3D Maze, 3D Text, Flying Toasters and Flurry as real .saver modules for System Settings \u{25B8} Screen Saver. The five Windows 3D savers come from retro-screensavers by Adrian Herskind (MIT).",
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
