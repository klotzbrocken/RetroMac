import SwiftUI
import AppKit

/// Settings for the automation timers: a daily time window and a one-shot countdown,
/// each targeting the shader overlay or Retro Mode.
struct TimerTab: View {
    @ObservedObject private var settings = AppSettings.shared

    private let targets = [("overlay", "Shader overlay"), ("retroMode", "Retro Mode")]

    private func timeBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let mins = settings[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: mins / 60, minute: mins % 60, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Automatically switch the shader overlay or Retro Mode on a schedule. Each timer can target the plain overlay or the full Retro Mode.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox("Daily window") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Active during a daily time window", isOn: $settings.timerWindowEnabled)
                        Group {
                            DatePicker("From", selection: timeBinding(\.timerWindowStart), displayedComponents: .hourAndMinute)
                            DatePicker("To", selection: timeBinding(\.timerWindowEnd), displayedComponents: .hourAndMinute)
                            Picker("Activate", selection: $settings.timerWindowTarget) {
                                ForEach(targets, id: \.0) { Text($0.1).tag($0.0) }
                            }
                        }
                        .disabled(!settings.timerWindowEnabled)
                    }
                    .padding(8)
                }

                GroupBox("Countdown") {
                    VStack(alignment: .leading, spacing: 12) {
                        Stepper("Active for \(settings.timerCountdownMinutes) min",
                                value: $settings.timerCountdownMinutes, in: 1...600, step: 5)
                        Picker("Activate", selection: $settings.timerCountdownTarget) {
                            ForEach(targets, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        HStack(spacing: 10) {
                            Button {
                                TimerController.shared.startCountdown(
                                    minutes: settings.timerCountdownMinutes,
                                    target: settings.timerCountdownTarget)
                            } label: { Label("Start countdown", systemImage: "play.fill") }
                            Button {
                                TimerController.shared.cancelCountdown()
                            } label: { Label("Stop", systemImage: "stop.fill") }
                        }
                        if let ends = TimerController.shared.countdownEndsAt {
                            Text("Ends at \(ends.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
