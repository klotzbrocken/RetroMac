import SwiftUI
import Metal

/// Read-only: what this Mac can do, and what RetroMac is doing right now. Permissions are
/// checked and granted under General; the Setup Assistant lives there too.
struct HealthCheckTab: View {
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
        ScrollView {
            VStack(spacing: RMSpacing.section) {
                capabilitiesCard
                captureCard
                systemCard
                dockCard
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .task { loadCaps() }
        .onReceive(NotificationCenter.default.publisher(for: .systemCapabilitiesChanged)) { _ in
            loadCaps()
        }
    }

    private var capabilitiesCard: some View {
        RMCard(title: "System capabilities",
               headerAction: AnyView(
                Button("Refresh") { SystemBridge.shared.probeAll { loadCaps() } }
                    .buttonStyle(RMGhostButtonStyle())),
               bodyPadding: 0) {
            VStack(spacing: 0) {
                let all = SystemCapability.allCases
                ForEach(Array(all.enumerated()), id: \.element) { index, cap in
                    RMRow(label: capLabels[cap] ?? cap.rawValue,
                          hint: caps[cap]?.reason,
                          isLast: index == all.count - 1) {
                        capabilityChip(caps[cap])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func capabilityChip(_ status: CapabilityStatus?) -> some View {
        switch status {
        case .some(let s) where s.available && !s.degraded:
            RMChip(text: "Available", tone: .on, showDot: false)
        case .some(let s) where s.available:
            RMChip(text: "Degraded", tone: .warn, showDot: false)
        case .some:
            RMChip(text: "Unavailable", tone: .danger, showDot: false)
        case .none:
            ProgressView().controlSize(.small)
        }
    }

    private var captureCard: some View {
        RMCard(title: "Capture", bodyPadding: 0) {
            VStack(spacing: 0) {
                if let delegate = AppDelegate.shared {
                    valueRow("Overlay", delegate.isActive ? "Active" : "Inactive", isLast: !delegate.isActive)
                    if delegate.isActive {
                        valueRow("Preset", delegate.currentPresetName ?? "\u{2014}")
                        valueRow("Intensity", "\(Int(delegate.currentIntensity * 100))%")
                        valueRow("Mode", delegate.captureModeDescription, isLast: true)
                    }
                } else {
                    RMNote(text: "Not available.")
                }
            }
        }
    }

    private var systemCard: some View {
        RMCard(title: "System", bodyPadding: 0) {
            VStack(spacing: 0) {
                if let name = MTLCreateSystemDefaultDevice()?.name {
                    valueRow("GPU", name)
                }
                let screens = NSScreen.screens
                valueRow("Displays", "\(screens.count)", isLast: screens.isEmpty)
                ForEach(Array(screens.enumerated()), id: \.offset) { index, screen in
                    let res = "\(Int(screen.frame.width))\u{00D7}\(Int(screen.frame.height))"
                    let scale = "\(Int(screen.backingScaleFactor))x"
                    valueRow(screen.localizedName, "\(res) @ \(scale)", isLast: index == screens.count - 1)
                }
            }
        }
    }

    private var dockCard: some View {
        let settings = AppSettings.shared
        return RMCard(title: "Theme", bodyPadding: 0) {
            VStack(spacing: 0) {
                valueRow("Retro dock", settings.dockEnabled ? "On" : "Off")
                valueRow("Selected theme", ThemeManager.shared.theme(for: settings.dockTheme)?.name ?? settings.dockTheme)
                valueRow("System Dock hidden", settings.dockHideSystemDock ? "Yes" : "No", isLast: true)
            }
        }
    }

    private func valueRow(_ label: String, _ value: String, isLast: Bool = false) -> some View {
        RMRow(label: label, isLast: isLast) {
            Text(value)
                .font(.rmMono(size: 11.5))
                .foregroundColor(.rmTextSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 240, alignment: .trailing)
        }
    }

    private func loadCaps() {
        var snap: [SystemCapability: CapabilityStatus] = [:]
        for c in SystemCapability.allCases { snap[c] = SystemBridge.shared.capability(c) }
        caps = snap
    }
}
