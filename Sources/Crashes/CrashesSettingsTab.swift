import SwiftUI

/// The Crashes pane. Two modes, one intensity, a list of what can happen, and a button that makes
/// it happen now.
struct CrashesTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var license = LicenseManager.shared
    /// Why the button just did nothing. Empty when it did something.
    @State private var holdReason: String = ""
    /// Why nothing is happening on its own — a different question from the one above, and the
    /// two used to be answered by the same line, which made the button look broken.
    @State private var scheduleReason: String = ""
    @State private var tick = 0
    /// Whether the machine will actually hand over a screenshot — checked, not assumed.
    @State private var canFreeze = true

    private var era: CrashEra? { CrashEra.current() }
    private var specs: [CrashCatalogue.Spec] { era.map { CrashCatalogue.specs(for: $0) } ?? [] }
    private var isParty: Bool { settings.crashMode == "party" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RMSpacing.section) {
                Text("Period-accurate failures that never actually fail. RetroMac lays a picture of your desktop over your desktop, shows the error the machine of the day would have shown, and takes it all away again. Nothing is quit, nothing is closed, nothing restarts.")
                    .font(.rmSecondary)
                    .foregroundColor(.rmTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !license.isLicensed {
                    RMCard(title: license.label("Retro Crashes"),
                           subtitle: "Pro — part of the licence.") {
                        Button("Unlock RetroMac") {
                            (NSApp.delegate as? AppDelegate)?.presentUnlockScreen()
                        }
                        .buttonStyle(RMPrimaryButtonStyle())
                    }
                }

                RMCard(title: "Mode", bodyPadding: 0) {
                    VStack(spacing: 0) {
                        RMRow(label: "Behaviour",
                              hint: isParty
                              ? "Party: nothing happens by itself. You trigger it, with a countdown if you want one."
                              : "Authentic: rare, plausible, and only when you are at the machine but not mid-sentence.") {
                            Picker("", selection: $settings.crashMode) {
                                Text("Authentic").tag("authentic")
                                Text("Party").tag("party")
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                        }
                        RMRow(label: "How often",
                              hint: isParty ? "Ignored in Party mode." : nil) {
                            Picker("", selection: $settings.crashIntensity) {
                                ForEach(CrashScheduler.Intensity.allCases, id: \.rawValue) { level in
                                    Text(level.title).tag(level.rawValue)
                                }
                            }
                            .labelsHidden().frame(width: 280)
                            .disabled(isParty)
                        }
                        RMRow(label: "By itself", hint: scheduleReason, isLast: true) {
                            Button("Refresh") { refresh() }
                                .buttonStyle(RMGhostButtonStyle())
                        }
                    }
                }

                RMCard(title: "Crash now",
                       subtitle: era.map { "The active theme is \($0.displayName)." }
                       ?? "Activate a theme that can crash to try one.") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button("Surprise me") { fire(nil) }
                                .buttonStyle(RMPrimaryButtonStyle())
                                .disabled(era == nil || !license.isLicensed)
                            if isParty {
                                Picker("Countdown", selection: $settings.crashCountdown) {
                                    Text("Immediately").tag(0)
                                    Text("3 seconds").tag(3)
                                    Text("5 seconds").tag(5)
                                    Text("10 seconds").tag(10)
                                }
                                .frame(width: 200)
                            }
                        }
                        if !holdReason.isEmpty {
                            // Say why nothing happened, where the button is. A button that
                            // silently does nothing is indistinguishable from a broken one.
                            Text(holdReason)
                                .font(.rmCaption).foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Esc always ends it. So does switching to another app, and so does waiting a minute.")
                            .font(.rmCaption).foregroundColor(.rmTextSecondary)
                    }
                }

                RMCard(title: "What can happen", bodyPadding: 0) {
                    VStack(spacing: 0) {
                        if specs.isEmpty {
                            RMRow(label: "Nothing yet",
                                  hint: "Each era has several failures and picks between them, so the same one does not come round twice. Windows 95, 98, Me, XP and 7, System 6, Mac OS 9, Mac OS X and Snow Leopard are covered; the other themes are still stable.",
                                  isLast: true) { EmptyView() }
                        } else {
                            ForEach(Array(specs.enumerated()), id: \.element.id) { index, spec in
                                RMRow(label: spec.title,
                                      hint: nil,
                                      isLast: index == specs.count - 1) {
                                    HStack(spacing: 8) {
                                        Button("Show") { fire(spec.id) }
                                            .buttonStyle(RMGhostButtonStyle())
                                            .disabled(!license.isLicensed)
                                        Toggle("", isOn: enabledBinding(spec.id))
                                            .labelsHidden().toggleStyle(.switch).tint(.rmAccent)
                                    }
                                }
                            }
                        }
                    }
                }

                RMCard(title: "The scene", bodyPadding: 0) {
                    VStack(spacing: 0) {
                        RMRow(label: "Full sequence",
                              hint: canFreeze
                              ? "The pointer falls behind for five or six seconds and the drive starts hunting before the error appears. Off shows the error straight away."
                              : "Needs Screen Recording: the build-up is a photograph of your desktop laid over your desktop, and without it there is nothing to freeze. RetroMac will show the error on its own instead.") {
                            Toggle("", isOn: $settings.crashFullSequence)
                                .labelsHidden().toggleStyle(.switch).tint(.rmAccent)
                        }
                        RMRow(label: "Failing drive sound",
                              hint: "Synthesised, not sampled: a spindle spinning up, then the head clicking and retrying.") {
                            Toggle("", isOn: $settings.crashSoundEnabled)
                                .labelsHidden().toggleStyle(.switch).tint(.rmAccent)
                        }
                        RMRow(label: "Graphics glitches",
                              hint: "Corrupts the frozen desktop in the way the era really did: redraw trails on everything before Windows Vista, torn bands, stale blocks of video memory, and a wrecked palette where the desktop had 256 colours.") {
                            Toggle("", isOn: $settings.crashGlitches)
                                .labelsHidden().toggleStyle(.switch).tint(.rmAccent)
                        }
                        RMRow(label: "Show “simulated crash”",
                              hint: "A red note in the bottom corner. Turn it off for a video, but leave it on if anyone else can see your screen.",
                              isLast: true) {
                            Toggle("", isOn: $settings.crashShowBadge)
                                .labelsHidden().toggleStyle(.switch).tint(.rmAccent)
                        }
                    }
                }

                RMCard(title: "Picture", bodyPadding: 0) {
                    RMRow(label: "Stretch to fill the screen",
                          hint: "Off keeps whole square pixels with a black border, the way a 720x400 text mode looked on a modern panel. On stretches it edge to edge, like a 4:3 signal on a widescreen monitor.",
                          isLast: true) {
                        Toggle("", isOn: $settings.crashStretchToFill)
                            .labelsHidden().toggleStyle(.switch).tint(.rmAccent)
                    }
                }
            }
            .padding(RMSpacing.page)
        }
        .onAppear { refresh() }
    }

    private func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !settings.crashDisabledScenarios.contains(id) },
            set: { on in
                var list = Set(settings.crashDisabledScenarios)
                if on { list.remove(id) } else { list.insert(id) }
                settings.crashDisabledScenarios = Array(list).sorted()
            })
    }

    private func fire(_ id: String?) {
        guard license.isLicensed else {
            (NSApp.delegate as? AppDelegate)?.presentUnlockScreen()
            return
        }
        let hold = CrashScheduler.shared.hold(ignoringSchedule: true)
        guard hold == .ready else {
            holdReason = hold.explanation
            return
        }
        holdReason = ""
        // Get out of the way first: a crash screen over the Settings window looks like a bug.
        NSApp.windows.first { $0.title == "RetroMac Settings" }?.orderOut(nil)
        let countdown = isParty ? settings.crashCountdown : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            CrashScheduler.shared.fire(scenarioID: id, source: .manual, countdown: countdown)
        }
    }

    private func refresh() {
        canFreeze = DesktopFreeze.canFreeze()
        scheduleReason = CrashScheduler.shared.hold().explanation
        holdReason = ""
        tick += 1
    }
}
