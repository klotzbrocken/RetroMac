import SwiftUI
import ScreenCaptureKit

/// General: getting RetroMac set up and letting it start. Its own tab now that Advanced has
/// become Shader — everything about the effect, including when it runs and what happens around
/// sleep, moved there, so what is left here is genuinely about the app rather than the effect.
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
                spacesCard
                permissionsCard
                defaultsCard
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .task { checkPermissions() }
    }

    /// The theme on every Space, or only on chosen ones. Spaces are added from the Space itself
    /// (Themes ▸ On This Space in the menu, or the button here), because macOS has no names for them.
    private var spacesCard: some View {
        RMCard(title: "Spaces",
               subtitle: "Keep the theme to some Spaces and plain macOS on the others. Appearance, accent colour, Finder and Terminal changes stay on every Space.",
               bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Only on chosen Spaces",
                      hint: "Off: the theme is on every Space.",
                      isLast: !settings.themeOnChosenSpaces) {
                    Toggle("", isOn: Binding(
                        get: { settings.themeOnChosenSpaces },
                        set: { on in
                            if on, settings.themeSpaces.isEmpty, let here = ThemeSpaces.currentSpace { settings.themeSpaces = [here] }
                            settings.themeOnChosenSpaces = on
                        }))
                        .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                }
                if settings.themeOnChosenSpaces {
                    ForEach(settings.themeSpaces, id: \.self) { space in
                        RMRow(label: ThemeSpaces.label(for: space) ?? "A Space that is gone",
                              hint: space == ThemeSpaces.currentSpace ? "The one you are on." : nil) {
                            Button("Remove") {
                                settings.themeSpaces.removeAll { $0 == space }
                                if settings.themeSpaces.isEmpty { settings.themeOnChosenSpaces = false }
                            }
                            .buttonStyle(RMGhostButtonStyle())
                        }
                    }
                    RMRow(label: "Add the Space you are on",
                          hint: "Or switch to a Space and choose Themes ▸ On This Space in the menu.",
                          isLast: true) {
                        Button("Add") {
                            if let here = ThemeSpaces.currentSpace, !settings.themeSpaces.contains(here) { settings.themeSpaces.append(here) }
                        }
                        .buttonStyle(RMDefaultButtonStyle())
                        .disabled(ThemeSpaces.currentSpace.map { settings.themeSpaces.contains($0) } ?? true)
                    }
                }
            }
        }
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

    /// The emergency exit: everything RetroMac can change about the system, back to macOS.
    private var defaultsCard: some View {
        RMCard(title: "macOS defaults",
               subtitle: "If something stayed behind — cursors, square window corners, a hidden or moved Dock — this puts the system back, whether or not RetroMac remembers changing it.",
               bodyPadding: 0) {
            RMRow(label: "Restore macOS defaults",
                  hint: "Turns the theme and the shader off, then restores the cursors, the window corners and every Finder and animation default, the Dock (shown, bottom, Genie), the menu bar, the desktop icons, the wallpaper, the appearance and the Terminal profile.",
                  isLast: true) {
                Button("Restore\u{2026}") {
                    let alert = NSAlert()
                    alert.messageText = "Restore macOS defaults?"
                    alert.informativeText = "The theme and the shader are turned off, and cursors, window corners, the Dock, the menu bar, the desktop icons, the wallpaper, the appearance and the Terminal profile go back to macOS — including settings you may have chosen yourself (the Finder's view style, the Dock's position). RetroMac's own settings stay."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Restore")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        (NSApp.delegate as? AppDelegate)?.restoreMacOSDefaults()
                    }
                }
                .buttonStyle(RMDefaultButtonStyle())
            }
        }
    }

    private var startupCard: some View {
        RMCard(title: "Startup", bodyPadding: 0) {
            VStack(spacing: 0) {
                // "Turn the shader on when RetroMac launches" lives in Shader ▸ When now, next
                // to the per-theme switch it has to agree with.
                RMRow(label: "Start RetroMac at login", isLast: true) {
                    Toggle("", isOn: $settings.launchAtLogin)
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
                    hint: "Lets RetroMac hide the Dock and menu bar through System Events.",
                    granted: automationGranted,
                    isLast: true,
                    pane: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
                    // Ask first: that is what brings up macOS's prompt and puts RetroMac in the
                    // Automation list. Only a refusal from before needs System Settings.
                    request: { done in
                        DispatchQueue.global(qos: .userInitiated).async {
                            let ok = SystemUIHelper.testAutomation()
                            DispatchQueue.main.async { automationGranted = ok; done(ok) }
                        }
                    }
                )
            }
            .padding(.vertical, 4)
        }
    }

    private func checkPermissions() {
        screenRecordingGranted = nil
        accessibilityGranted = AXIsProcessTrusted()
        // Off the main thread: the first time, asking System Events shows macOS's prompt, and
        // the question waits for the answer.
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = SystemUIHelper.testAutomation()
            DispatchQueue.main.async { automationGranted = ok }
        }
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
    /// Ask macOS directly before sending anyone to System Settings; `done(true)` when granted.
    var request: ((@escaping (Bool) -> Void) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(granted == true ? Color.rmAccentSoft : Color(red: 0.992, green: 0.914, blue: 0.898))
                        .frame(width: 18, height: 18)
                    Image(systemName: granted == true ? "checkmark" : "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(granted == true ? .rmAccent : .rmDanger).accessibilityHidden(true)
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
                        let openPane = { if let url = URL(string: pane) { NSWorkspace.shared.open(url) } }
                        if let request { request { granted in if !granted { openPane() } } } else { openPane() }
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
