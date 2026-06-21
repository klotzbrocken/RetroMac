import SwiftUI

/// Advanced settings — power-user options collected behind one tab so the rest of the
/// Settings window stays simple. A segmented control switches between sub-sections; only
/// one is shown at a time (each reuses an existing view with its own scroll region).
struct AdvancedTab: View {
    @State private var section: AdvSection = .performance

    enum AdvSection: String, CaseIterable, Identifiable {
        case performance = "Performance"
        case hotkeys = "Hotkeys"
        case rules = "Per-App"
        case timer = "Timer"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(AdvSection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Rectangle().fill(Color.rmDivider).frame(height: 1)

            Group {
                switch section {
                case .performance: PerformanceSection()
                case .hotkeys:     ShortcutsTab()
                case .rules:       PerAppRulesTab()
                case .timer:       TimerTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Single "Quality" control (replaces the old four-tile performance card + scattered
/// toggles). The profile already maps to fps / half-resolution internally.
private struct PerformanceSection: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(spacing: RMSpacing.section) {
                RMCard(title: "Performance", subtitle: "Higher quality uses more GPU.", bodyPadding: 0) {
                    VStack(spacing: 0) {
                        RMRow(label: "Quality", hint: "Balances GPU load against visual fidelity.", isLast: false) {
                            Picker("", selection: $settings.performanceProfile) {
                                ForEach(PerformanceProfile.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 160)
                        }
                        RMRow(label: "Low-latency mode", hint: "Forces 60 fps. Less mouse lag, more GPU.", isLast: true) {
                            Toggle("", isOn: $settings.lowLatencyMode)
                                .toggleStyle(.switch)
                                .tint(.rmAccent)
                                .labelsHidden()
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}
