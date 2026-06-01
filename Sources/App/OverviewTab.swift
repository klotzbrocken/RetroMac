import SwiftUI
import ScreenCaptureKit

// MARK: - Overview Tab

struct OverviewTab: View {
    @Binding var selectedTab: SettingsTab
    @ObservedObject private var settings = AppSettings.shared
    @State private var screenRecordingGranted: Bool?
    @State private var accessibilityGranted: Bool?
    @State private var automationGranted: Bool?

    private var overlayIsOn: Bool {
        (NSApp.delegate as? AppDelegate)?.isActive ?? false
    }

    private var presetDisplayName: String {
        PresetRegistry.availablePresets.first(where: { $0.id == settings.defaultPreset })?.displayName ?? settings.defaultPreset
    }

    private var missingPermissions: Int {
        var count = 0
        if screenRecordingGranted == false { count += 1 }
        if accessibilityGranted == false { count += 1 }
        if automationGranted == false { count += 1 }
        return count
    }

    private var allPermissionsGranted: Bool {
        screenRecordingGranted == true && accessibilityGranted == true && automationGranted == true
    }

    var body: some View {
        ScrollView {
            VStack(spacing: RMSpacing.section) {
                // 1. Hero row — 2-column grid
                heroRow

                // 2. Quick actions
                quickActionsSection

                // 3. Permissions (only when missing)
                if !allPermissionsGranted {
                    permissionsCard
                }

                // 4. Sleep card
                sleepCard
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .padding(.bottom, 8)
        }
        .task { checkPermissions() }
    }

    // MARK: - Hero Row

    private var heroRow: some View {
        HStack(alignment: .top, spacing: RMSpacing.xxl) {
            // Status card
            statusCard
                .frame(maxWidth: .infinity)

            // Live preview — click opens Viewport
            VStack(alignment: .leading, spacing: RMSpacing.md) {
                Button {
                    (NSApp.delegate as? AppDelegate)?.toggleViewport()
                } label: {
                    LivePreviewView()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: RMRadius.card))
                        .overlay(
                            RoundedRectangle(cornerRadius: RMRadius.card)
                                .stroke(Color.rmBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Image(systemName: "viewfinder.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.rmTextSecondary)
                    Text("Click to open the Retro Viewport.")
                        .font(.rmSecondary)
                        .foregroundColor(.rmTextSecondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var statusCard: some View {
        RMCard(bodyPadding: 0) {
            VStack(spacing: 0) {
                // Top region
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        // Status dot
                        Circle()
                            .fill(overlayIsOn ? Color.rmAccent : Color.rmTextTertiary)
                            .frame(width: 10, height: 10)

                        Text("OVERLAY")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(0.5)
                            .foregroundColor(.rmTextSecondary)

                        RMChip(text: overlayIsOn ? "Running" : "Off", tone: overlayIsOn ? .on : .neutral, showDot: false)

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { overlayIsOn },
                            set: { newValue in
                                if let delegate = NSApp.delegate as? AppDelegate {
                                    delegate.toggleOverlay()
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                    }
                    .padding(.bottom, 2)

                    Text(presetDisplayName)
                        .font(.rmHero)
                        .tracking(-0.4)
                        .foregroundColor(.rmTextPrimary)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    let displayName = NSScreen.main?.localizedName ?? "Built-in Display"
                    let profileName = settings.performanceProfile.displayName
                    Text("on \(displayName) \u{00B7} \(profileName) \u{00B7} \(settings.targetFPS) fps")
                        .font(.system(size: 12))
                        .foregroundColor(.rmTextSecondary)
                }
                .padding(18)

                // Footer stats strip
                Rectangle()
                    .fill(Color.rmDivider)
                    .frame(height: 1)

                HStack(spacing: 8) {
                    StatCell(label: "Intensity", value: "\(Int(settings.defaultIntensity * 100))%")
                    StatCell(label: "Vignette", value: "\(Int(settings.vignetteIntensity * 100))%")
                    StatCell(label: "Scanlines", value: settings.scanlineOverlayName.isEmpty ? "Off" : "On")
                    StatCell(label: "GPU", value: "\u{2014}")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.rmSurface2)
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            RMSectionHeaderView(title: "Quick actions")

            HStack(spacing: RMSpacing.lg) {
                QuickActionTile(icon: "wand.and.stars.inverse", label: "Switch effect", value: presetDisplayName) {
                    selectedTab = .effect
                }
                QuickActionTile(icon: "display", label: "Target display", value: NSScreen.main?.localizedName ?? "Built-in") {
                    selectedTab = .effect
                }
                QuickActionTile(icon: "dock.rectangle", label: "Retro dock", value: settings.dockEnabled ? "On" : "Off") {
                    selectedTab = .dock
                }
                QuickActionTile(icon: "star", label: "Save preset", value: "My Look 1") {
                    selectedTab = .effect
                }
            }
        }
    }

    // MARK: - Permissions Card

    private var permissionsCard: some View {
        RMCard(
            title: "Permissions",
            subtitle: "RetroMac can\u{2019}t capture your screen without these.",
            headerAction: AnyView(
                HStack(spacing: 10) {
                    if missingPermissions > 0 {
                        RMChip(text: "\(missingPermissions) missing", tone: .warn)
                    }
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(RMGhostButtonStyle())
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
                    isLast: false
                )
                PermissionRow(
                    name: "Automation",
                    hint: "Lets RetroMac auto-switch presets per app.",
                    granted: automationGranted,
                    isLast: true
                )
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Sleep Card

    private var sleepCard: some View {
        RMCard(title: "When my Mac sleeps", bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Stop overlay on sleep or lock") {
                    Toggle("", isOn: $settings.stopOnSleep)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                }
                RMRow(label: "Resume overlay after wake") {
                    Toggle("", isOn: $settings.resumeAfterSleep)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                        .disabled(!settings.stopOnSleep)
                }
                RMRow(
                    label: "Reset to default preset after wake",
                    hint: "Restores \(presetDisplayName) regardless of last-used preset.",
                    isLast: true
                ) {
                    Toggle("", isOn: $settings.resetOnWake)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                        .disabled(!settings.stopOnSleep || !settings.resumeAfterSleep)
                }
            }
        }
    }

    // MARK: - Permission Check

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

// MARK: - Sub-Components

private struct StatCell: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(.rmTextTertiary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .tracking(-0.1)
                .foregroundColor(.rmTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuickActionTile: View {
    var icon: String
    var label: String
    var value: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.rmSurface2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.rmBorder, lineWidth: 1)
                        )
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.rmTextPrimary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.rmTextTertiary)
            }

            Text(label)
                .font(.rmSecondary)
                .foregroundColor(.rmTextSecondary)
                .padding(.top, 2)

            Text(value)
                .font(.system(size: 13.5, weight: .semibold))
                .tracking(-0.1)
                .foregroundColor(.rmTextPrimary)
                .padding(.top, 2)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .padding(.bottom, 2)
        .background(Color.rmSurface)
        .clipShape(RoundedRectangle(cornerRadius: RMRadius.tile))
        .overlay(
            RoundedRectangle(cornerRadius: RMRadius.tile)
                .stroke(Color.rmBorder, lineWidth: 1)
        )
        .rmCardShadow()
        }
        .buttonStyle(.plain)
    }
}

private struct PermissionRow: View {
    var name: String
    var hint: String
    var granted: Bool?
    var isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Status circle
                ZStack {
                    Circle()
                        .fill(granted == true ? Color.rmAccentSoft : Color(red: 0.992, green: 0.914, blue: 0.898))
                        .frame(width: 18, height: 18)
                    Image(systemName: granted == true ? "checkmark" : "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(granted == true ? .rmAccent : .rmDanger)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.rmTextPrimary)
                    Text(hint)
                        .font(.rmSecondary)
                        .foregroundColor(.rmTextSecondary)
                }

                Spacer()

                if granted == true {
                    RMChip(text: "Granted", tone: .on, showDot: false)
                } else if granted == nil {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Grant\u{2026}") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(RMDefaultButtonStyle())
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, RMSpacing.card)

            if !isLast {
                Rectangle()
                    .fill(Color.rmDivider)
                    .frame(height: 1)
                    .padding(.horizontal, RMSpacing.card)
            }
        }
    }
}
