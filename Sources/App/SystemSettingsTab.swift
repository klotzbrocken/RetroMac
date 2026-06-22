import SwiftUI
import ScreenCaptureKit

/// System sub-section (lives under Advanced): permission status + sleep/wake behaviour.
/// Replaces the former Overview tab — overlay status and the active preset are shown in
/// the status-bar menu, so they no longer need a Settings home.
struct SystemSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var screenRecordingGranted: Bool?
    @State private var accessibilityGranted: Bool?
    @State private var automationGranted: Bool?

    private var missingPermissions: Int {
        var count = 0
        if screenRecordingGranted == false { count += 1 }
        if accessibilityGranted == false { count += 1 }
        if automationGranted == false { count += 1 }
        return count
    }

    private var presetDisplayName: String {
        PresetRegistry.availablePresets.first(where: { $0.id == settings.defaultPreset })?.displayName ?? settings.defaultPreset
    }

    var body: some View {
        ScrollView {
            VStack(spacing: RMSpacing.section) {
                setupCard
                startupCard
                permissionsCard
                sleepCard
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .task { checkPermissions() }
    }

    private var setupCard: some View {
        RMCard(title: "Setup", bodyPadding: 0) {
            RMRow(label: "Setup Assistant",
                  hint: "Re-run the post-install configuration wizard.",
                  isLast: true) {
                Button("Re-run\u{2026}") {
                    (NSApp.delegate as? AppDelegate)?.openSetupWizard()
                }
                .buttonStyle(RMDefaultButtonStyle())
            }
        }
    }

    private var startupCard: some View {
        RMCard(title: "Startup", bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Start RetroMac at login") {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                }
                RMRow(label: "Turn the shader on when RetroMac launches", isLast: true) {
                    Toggle("", isOn: $settings.enableOnLaunch)
                        .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                }
            }
        }
    }

    private var permissionsCard: some View {
        RMCard(
            title: "Permissions",
            subtitle: "RetroMac can\u{2019}t capture your screen without these.",
            headerAction: AnyView(
                HStack(spacing: 10) {
                    if missingPermissions > 0 {
                        RMChip(text: "\(missingPermissions) missing", tone: .warn)
                    }
                    Button("Reset Permissions\u{2026}") {
                        (NSApp.delegate as? AppDelegate)?.resetPermissions()
                    }
                    .buttonStyle(RMGhostButtonStyle())
                    .help("Reset Screen Recording & Camera grants, then reopen the panels — useful after an update.")
                }
            ),
            bodyPadding: 0
        ) {
            VStack(spacing: 0) {
                PermissionRow(
                    name: "Screen Recording",
                    hint: "Required for capturing the desktop.",
                    granted: screenRecordingGranted,
                    isLast: false
                )
                PermissionRow(
                    name: "Accessibility",
                    hint: "Needed for global hotkey + window targeting.",
                    granted: accessibilityGranted,
                    isLast: false,
                    pane: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )
                PermissionRow(
                    name: "Automation",
                    hint: "Lets RetroMac auto-switch presets per app.",
                    granted: automationGranted,
                    isLast: true,
                    pane: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                )
            }
            .padding(.vertical, 4)
        }
    }

    private var sleepCard: some View {
        RMCard(title: "When my Mac sleeps", bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Stop overlay on sleep or lock") {
                    Toggle("", isOn: $settings.stopOnSleep)
                        .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                }
                RMRow(label: "Resume overlay after wake") {
                    Toggle("", isOn: $settings.resumeAfterSleep)
                        .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                        .disabled(!settings.stopOnSleep)
                }
                RMRow(
                    label: "Reset to default preset after wake",
                    hint: "Restores \(presetDisplayName) regardless of last-used preset.",
                    isLast: true
                ) {
                    Toggle("", isOn: $settings.resetOnWake)
                        .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                        .disabled(!settings.stopOnSleep || !settings.resumeAfterSleep)
                }
            }
        }
    }

    private func checkPermissions() {
        screenRecordingGranted = nil
        accessibilityGranted = AXIsProcessTrusted()
        automationGranted = SystemUIHelper.testAutomation()
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                await MainActor.run { screenRecordingGranted = true }
            } catch {
                await MainActor.run { screenRecordingGranted = false }
            }
        }
    }
}

private struct PermissionRow: View {
    var name: String
    var hint: String
    var granted: Bool?
    var isLast: Bool
    var pane: String = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(granted == true ? Color.rmAccentSoft : Color(red: 0.992, green: 0.914, blue: 0.898))
                        .frame(width: 18, height: 18)
                    Image(systemName: granted == true ? "checkmark" : "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(granted == true ? .rmAccent : .rmDanger)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.system(size: 13, weight: .medium)).foregroundColor(.rmTextPrimary)
                    Text(hint).font(.rmSecondary).foregroundColor(.rmTextSecondary)
                }
                Spacer()
                if granted == true {
                    RMChip(text: "Granted", tone: .on, showDot: false)
                } else if granted == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Grant\u{2026}") {
                        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(RMDefaultButtonStyle())
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, RMSpacing.card)

            if !isLast {
                Rectangle().fill(Color.rmDivider).frame(height: 1)
                    .padding(.horizontal, RMSpacing.card)
            }
        }
    }
}
