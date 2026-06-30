import SwiftUI
import ScreenCaptureKit
import Metal

struct HealthCheckTab: View {
    @State private var screenRecordingGranted: Bool?
    @State private var accessibilityGranted: Bool?
    @State private var automationGranted: Bool?
    @State private var caps: [SystemCapability: CapabilityStatus] = [:]

    private let capLabels: [SystemCapability: String] = [
        .systemDockControl: "System Dock control",
        .menuBarAutohide: "Menu-bar auto-hide",
        .desktopIconsToggle: "Desktop icons toggle",
        .accessibility: "Accessibility",
        .screenCapture: "Screen Recording",
        .finderAutomation: "Finder automation (trash)",
        .virtualDisplay: "Virtual display (iPad)"
    ]

    var body: some View {
        Form {
            Section("System Capabilities") {
                ForEach(SystemCapability.allCases, id: \.self) { cap in
                    capabilityRow(capLabels[cap] ?? cap.rawValue, caps[cap])
                }
                Button("Refresh") {
                    SystemBridge.shared.probeAll { loadCaps() }
                }
                .font(.caption)
            }

            Section("Permissions") {
                permissionRow("Screen Recording", status: screenRecordingGranted)
                permissionRow("Accessibility", status: accessibilityGranted)
                permissionRow("Automation", status: automationGranted)

                Button("Recheck") {
                    checkPermissions()
                }
                .font(.caption)
            }

            Section("Capture Status") {
                if let delegate = AppDelegate.shared {
                    LabeledContent("Overlay", value: delegate.isActive ? "Active" : "Inactive")
                    if delegate.isActive {
                        LabeledContent("Preset", value: delegate.currentPresetName ?? "—")
                        LabeledContent("Intensity", value: "\(Int(delegate.currentIntensity * 100))%")
                        LabeledContent("Mode", value: delegate.captureModeDescription)
                    }
                } else {
                    Text("Not available")
                        .foregroundStyle(.secondary)
                }
            }

            Section("System") {
                if let name = MTLCreateSystemDefaultDevice()?.name {
                    LabeledContent("GPU", value: name)
                }
                let screens = NSScreen.screens
                LabeledContent("Displays", value: "\(screens.count)")
                ForEach(Array(screens.enumerated()), id: \.offset) { _, screen in
                    let res = "\(Int(screen.frame.width))×\(Int(screen.frame.height))"
                    let scale = "\(Int(screen.backingScaleFactor))x"
                    LabeledContent(screen.localizedName, value: "\(res) @\(scale)")
                }
            }

            Section("Dock") {
                let settings = AppSettings.shared
                LabeledContent("Status", value: settings.dockEnabled ? "Enabled" : "Disabled")
                LabeledContent("Theme", value: settings.dockTheme)
                LabeledContent("System Dock Hidden", value: settings.dockHideSystemDock ? "Yes" : "No")
            }

            Section {
                Button("Re-run Setup Assistant") {
                    AppDelegate.shared?.showOnboarding()
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .task {
            checkPermissions()
            loadCaps()
        }
        .onReceive(NotificationCenter.default.publisher(for: .systemCapabilitiesChanged)) { _ in
            loadCaps()
        }
    }

    private func loadCaps() {
        var snap: [SystemCapability: CapabilityStatus] = [:]
        for c in SystemCapability.allCases { snap[c] = SystemBridge.shared.capability(c) }
        caps = snap
    }

    @ViewBuilder
    private func capabilityRow(_ name: String, _ status: CapabilityStatus?) -> some View {
        HStack(alignment: .top) {
            Text(name)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                switch status {
                case .some(let s) where s.available && !s.degraded:
                    Label("Available", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon).foregroundStyle(.green)
                case .some(let s) where s.available:
                    Label("Degraded", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.titleAndIcon).foregroundStyle(.orange)
                case .some:
                    Label("Unavailable", systemImage: "xmark.circle.fill")
                        .labelStyle(.titleAndIcon).foregroundStyle(.red)
                case .none:
                    ProgressView().controlSize(.small)
                }
                if let reason = status?.reason {
                    Text(reason).font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 280)
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

    @ViewBuilder
    private func permissionRow(_ name: String, status: Bool?) -> some View {
        HStack {
            Text(name)
            Spacer()
            switch status {
            case .some(true):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Granted").foregroundStyle(.secondary)
            case .some(false):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Not Granted").foregroundStyle(.secondary)
            case .none:
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}
