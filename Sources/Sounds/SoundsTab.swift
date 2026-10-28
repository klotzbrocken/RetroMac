import SwiftUI

/// Settings ▸ Sounds. The one place the keyboard, drive and fan are switched and tuned.
struct SoundsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var engine = SoundEngine.shared
    @State private var section: Sec = .overview

    enum Sec: String, CaseIterable, Identifiable {
        case overview = "Overview", keyboard = "Keyboard", driveFan = "Drive & Fan", behaviour = "Behaviour"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(Sec.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .accessibilityRepresentation {
                Picker("Sounds section", selection: $section) {
                    ForEach(Sec.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            Rectangle().fill(Color.rmDivider).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: RMSpacing.section) {
                    switch section {
                    case .overview: overview
                    case .keyboard: keyboard
                    case .driveFan: drive; fan
                    case .behaviour: behaviour
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 20)
            }
        }
    }

    // MARK: - Overview

    private var status: String {
        if !settings.sounds.enabled { return "Off." }
        if engine.held { return "Paused until you resume." }
        if let reason = engine.pauseReason { return reason }
        let s = settings.sounds
        return s.keyboard.enabled || s.drive.enabled || s.fan.enabled ? "Playing." : "On, but every module is off."
    }

    private func moduleStatus(_ m: SoundEngine.Module) -> String {
        let s = settings.sounds
        switch m {
        case .keyboard:
            if !s.keyboard.enabled { return "Off" }
            return engine.keyboard.isTrusted ? "On" : "On, but it needs Accessibility to hear keys"
        case .drive:
            if !s.drive.enabled { return "Off" }
            return engine.drive.countersFound ? (s.drive.ambient ? "On, ambient" : "On, follows disk activity")
                                              : "On, ambient: this Mac reports no disk activity"
        case .fan:
            return s.fan.enabled ? "On, follows CPU load" : "Off"
        }
    }

    @ViewBuilder private var overview: some View {
        Text("Your Mac makes no sound of its own any more. These put some back: keys that click, a hard drive that seeks when the disk is busy, a fan that rises with the CPU. Everything is synthesized on the spot, nothing leaves the Mac, and the real keyboard, disk and fans are never touched.")
            .font(.rmSecondary).foregroundColor(.rmTextSecondary)
            .fixedSize(horizontal: false, vertical: true)

        RMCard(title: "RetroMac Sounds", bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Sounds", hint: "Off silences everything at once. The settings stay.") {
                    toggle($settings.sounds.enabled)
                }
                RMRow(label: "Volume", hint: "The ceiling for all of them. The Mac's own volume is not touched.", stacked: true) {
                    PercentSlider(value: $settings.sounds.volume)
                }
                RMRow(label: "Status", hint: status, isLast: true) {
                    Button(engine.held ? "Resume" : "Pause all") { engine.held.toggle() }
                        .buttonStyle(RMGhostButtonStyle())
                        .disabled(!settings.sounds.enabled)
                }
            }
        }

        RMCard(title: "Modules", bodyPadding: 0) {
            VStack(spacing: 0) {
                moduleRow("Keyboard", .keyboard, $settings.sounds.keyboard.enabled)
                moduleRow("Virtual drive", .drive, $settings.sounds.drive.enabled)
                moduleRow("Fan", .fan, $settings.sounds.fan.enabled, last: true)
            }
        }

        RMCard(title: "Interface sounds", bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Device chime",
                      hint: DeviceSounds.uiSoundsOn
                      ? "Windows XP, Vista and 7: a chime when a USB device is plugged in or pulled out."
                      : "Quiet while macOS's \u{201C}Play user interface sound effects\u{201D} is off (System Settings ▸ Sound).",
                      isLast: true) {
                    HStack(spacing: 10) {
                        Button("Preview") { engine.playPreview(DeviceSounds.chime(connect: true)) }
                            .buttonStyle(RMGhostButtonStyle())
                            .accessibilityLabel("Preview device chime")
                        toggle($settings.sounds.deviceSounds)
                    }
                }
            }
        }

        HStack {
            Spacer()
            Button("Reset all sounds") { settings.sounds = SoundPrefs() }
                .buttonStyle(RMGhostButtonStyle())
        }
    }

    private func moduleRow(_ label: String, _ m: SoundEngine.Module, _ on: Binding<Bool>, last: Bool = false) -> some View {
        RMRow(label: label, hint: moduleStatus(m), isLast: last) {
            HStack(spacing: 10) {
                Button("Preview") { engine.preview(m) }
                    .buttonStyle(RMGhostButtonStyle())
                    .accessibilityLabel("Preview \(label.lowercased())")
                toggle(on)
            }
        }
    }

    // MARK: - Keyboard

    @ViewBuilder private var keyboard: some View {
        if !engine.keyboard.isTrusted {
            RMCard(title: "Accessibility", subtitle: "To click along, RetroMac has to notice that a key went down in another app, and macOS only tells apps with Accessibility access. RetroMac learns only which kind of key it was (a letter, Space, Return or a modifier), never what you typed, and keeps nothing. Without it the keyboard stays quiet and its settings stay as they are.") {
                Button("Grant Accessibility…") { TaskbarNoticeView.requestAccessibility() }
                    .buttonStyle(RMPrimaryButtonStyle())
            }
        }
        RMCard(title: "Keyboard", bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Key clicks", hint: "In every app. Password fields stay silent: macOS hides their keys.") {
                    toggle($settings.sounds.keyboard.enabled)
                }
                RMRow(label: "Sound", stacked: true) {
                    Picker("", selection: $settings.sounds.keyboard.profile) {
                        ForEach(KeyProfile.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 380)
                }
                RMRow(label: "Key down") { toggle($settings.sounds.keyboard.keyDown) }
                RMRow(label: "Key up", hint: "A second, softer click on release.") { toggle($settings.sounds.keyboard.keyUp) }
                RMRow(label: "Modifier keys", hint: "Shift, Control, Option, Command and Caps Lock.") { toggle($settings.sounds.keyboard.modifiers) }
                RMRow(label: "Click on key repeat", hint: "Off: a held key clicks once, not at the repeat rate.") { toggle($settings.sounds.keyboard.repeats) }
                RMRow(label: "Volume", stacked: true) { PercentSlider(value: $settings.sounds.keyboard.volume) }
                RMRow(label: "Pitch variation", hint: "No two keys sound quite alike.", stacked: true) {
                    PercentSlider(value: $settings.sounds.keyboard.pitchVariation)
                }
                previewReset(.keyboard) { settings.sounds.keyboard = .init() }
            }
        }
    }

    // MARK: - Drive & Fan

    private var thresholdKB: Binding<Double> {
        Binding(get: { log10(settings.sounds.drive.customThreshold / 1000) },
                set: { settings.sounds.drive.customThreshold = pow(10, $0) * 1000 })
    }

    @ViewBuilder private var drive: some View {
        RMCard(title: "Virtual drive",
               subtitle: "A simulation, not a recording: the Mac's disk activity, counted and nothing more, sets the heads moving. No file names, no apps.",
               bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Virtual drive", hint: "Spins up when you turn it on, parks and spins down when you turn it off.") {
                    toggle($settings.sounds.drive.enabled)
                }
                RMRow(label: "Drive") {
                    Picker("", selection: $settings.sounds.drive.profile) {
                        ForEach(DriveModule.profiles, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden().frame(width: 240)
                }
                RMRow(label: "Volume", stacked: true) { PercentSlider(value: $settings.sounds.drive.volume) }
                RMRow(label: "Spindle hum", hint: "The motor between accesses.", stacked: true) {
                    PercentSlider(value: $settings.sounds.drive.hum)
                }
                RMRow(label: "Sensitivity", hint: "How busy the disk must be before the drive seeks. Quiet ignores everything but real work.", stacked: true) {
                    Picker("", selection: $settings.sounds.drive.sensitivity) {
                        Text("Quiet").tag(SoundPrefs.Sensitivity.quiet)
                        Text("Balanced").tag(SoundPrefs.Sensitivity.balanced)
                        Text("Clear").tag(SoundPrefs.Sensitivity.clear)
                        Text("Custom").tag(SoundPrefs.Sensitivity.custom)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 340)
                }
                if settings.sounds.drive.sensitivity == .custom {
                    RMRow(label: "Threshold", hint: String(format: "%.0f KB/s", settings.sounds.drive.customThreshold / 1000), stacked: true) {
                        Slider(value: thresholdKB, in: log10(20)...log10(20_000)).frame(width: 300)
                    }
                    RMRow(label: "Shortest access", hint: String(format: "%.0f ms", settings.sounds.drive.minDuration * 1000), stacked: true) {
                        Slider(value: $settings.sounds.drive.minDuration, in: 0.05...1).frame(width: 300)
                    }
                }
                RMRow(label: "Ambient", hint: "Plays light activity of its own, whatever the disk does.") {
                    toggle($settings.sounds.drive.ambient)
                }
                previewReset(.drive) { settings.sounds.drive = .init() }
            }
        }
    }

    @ViewBuilder private var fan: some View {
        RMCard(title: "Fan",
               subtitle: "An effect, not a measurement: it follows CPU load, never the Mac's temperature or its real fans, and controls nothing.",
               bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Fan") { toggle($settings.sounds.fan.enabled) }
                RMRow(label: "Kind", stacked: true) {
                    Picker("", selection: $settings.sounds.fan.profile) {
                        ForEach(FanProfile.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 280)
                }
                RMRow(label: "Base noise", hint: "A quiet whir even when the CPU is idle.") { toggle($settings.sounds.fan.baseNoise) }
                RMRow(label: "Starts at", hint: String(format: "%.0f %% CPU load, smoothed", settings.sounds.fan.threshold * 100), stacked: true) {
                    Slider(value: $settings.sounds.fan.threshold, in: 0.1...0.9).frame(width: 300)
                }
                RMRow(label: "Loudest", stacked: true) { PercentSlider(value: $settings.sounds.fan.volume) }
                RMRow(label: "Response", stacked: true) {
                    Picker("", selection: $settings.sounds.fan.response) {
                        Text("Slow").tag(SoundPrefs.Response.slow)
                        Text("Medium").tag(SoundPrefs.Response.medium)
                        Text("Fast").tag(SoundPrefs.Response.fast)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                }
                RMRow(label: "Run-on", hint: String(format: "%.0f seconds to fall quiet", settings.sounds.fan.decay), stacked: true) {
                    Slider(value: $settings.sounds.fan.decay, in: 2...20, step: 1).frame(width: 300)
                }
                if settings.sounds.fan.enabled {
                    RMRow(label: "Last minute", hint: "CPU load (grey) and the fan's speed (accent).", stacked: true) {
                        FanChart(fan: engine.fan)
                    }
                }
                previewReset(.fan) { settings.sounds.fan = .init() }
            }
        }
    }

    // MARK: - Behaviour

    @ViewBuilder private var behaviour: some View {
        RMCard(title: "Behaviour", bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Output", hint: "The Mac's current output device. Change it in Control Centre; the sounds follow.") {
                    Text("System output").font(.rmSecondary).foregroundColor(.rmTextSecondary)
                }
                RMRow(label: "Pause while the screen is shared", hint: "macOS Screen Sharing. A video call's screen share cannot be seen from outside; the microphone pause covers calls.") {
                    toggle($settings.sounds.pauseOnScreenSharing)
                }
                RMRow(label: "Pause while recording", hint: "While any app uses a microphone or audio input, so nothing simulated ends up in a recording or a call.") {
                    toggle($settings.sounds.pauseOnRecording)
                }
                RMRow(label: "Pause while the Mac is muted") { toggle($settings.sounds.pauseWhenMuted) }
                RMRow(label: "Start with RetroMac", hint: "Off: after a restart they wait for Resume on the Overview.", isLast: true) {
                    toggle($settings.sounds.startAtLaunch)
                }
            }
        }
        RMCard(title: "Diagnostics", bodyPadding: 0) {
            VStack(spacing: 0) {
                diag("Audio engine", engine.isRunning ? "Running" : "Stopped")
                diag("Microphone or audio input in use", SoundEngine.inputInUse() ? "Yes" : "No")
                diag("Screen Sharing session", SoundEngine.screenShared() ? "Yes" : "No")
                diag("Mac muted", SystemVolume.isMuted ? "Yes" : "No")
                diag("Disk activity counters", engine.drive.countersFound ? "Found" : "Not reported by macOS")
                diag("Accessibility", engine.keyboard.isTrusted ? "Granted" : "Not granted", last: true)
            }
        }
    }

    private func diag(_ label: String, _ value: String, last: Bool = false) -> some View {
        RMRow(label: label, isLast: last) {
            Text(value).font(.rmSecondary).foregroundColor(.rmTextSecondary)
        }
    }

    // MARK: - Parts

    private func toggle(_ on: Binding<Bool>) -> some View {
        Toggle("", isOn: on).toggleStyle(.switch).tint(.rmAccent).labelsHidden()
    }

    private func previewReset(_ m: SoundEngine.Module, reset: @escaping () -> Void) -> some View {
        RMRow(label: "Try it", hint: "Plays a few seconds without turning it on.", isLast: true) {
            HStack(spacing: 10) {
                Button("Preview") { engine.preview(m) }.buttonStyle(RMDefaultButtonStyle())
                Button("Reset") { reset() }.buttonStyle(RMGhostButtonStyle())
            }
        }
    }
}

private struct PercentSlider: View {
    @Binding var value: Double
    var body: some View {
        HStack(spacing: 10) {
            Slider(value: $value, in: 0...1).frame(width: 260)
            Text("\(Int((value * 100).rounded())) %")
                .font(.rmSecondary).foregroundColor(.rmTextSecondary)
                .frame(width: 44, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

private struct FanChart: View {
    @ObservedObject var fan: FanModule
    var body: some View {
        Canvas { ctx, size in
            func line(_ values: [Double]) -> Path {
                var p = Path()
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: size.width * CGFloat(i) / 59, y: size.height * (1 - CGFloat(min(1, max(0, v)))))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                return p
            }
            ctx.stroke(line(fan.history.map(\.cpu)), with: .color(.gray.opacity(0.6)), lineWidth: 1.5)
            ctx.stroke(line(fan.history.map(\.fan)), with: .color(.rmAccent), lineWidth: 2)
        }
        .frame(width: 360, height: 60)
        .background(Color.rmDivider.opacity(0.3))
        .accessibilityLabel(String(format: "CPU load %.0f percent, fan %.0f percent",
                                   (fan.history.last?.cpu ?? 0) * 100, (fan.history.last?.fan ?? 0) * 100))
    }
}
