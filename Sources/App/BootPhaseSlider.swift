import SwiftUI

/// Boot Phases as three stops on a slider, each with its name and what it plays. Arrow keys
/// move between the stops; VoiceOver reads the stop's name.
struct BootPhaseSlider: View {
    @Binding var mode: BootPhaseMode
    /// Shown under the stops when the theme cannot play the chosen one in full.
    var note: String? = nil

    private static let preview: [BootPhaseMode: String] = [
        .desktop: "The theme comes straight up, without a boot animation.",
        .os: "The operating system starts, then the desktop.",
        .full: "The machine's firmware first (on a PC theme a BIOS you can enter with DEL, on the AmigaOne its U-Boot), then the operating system.",
    ]

    var body: some View {
        let all = BootPhaseMode.allCases
        VStack(alignment: .leading, spacing: 4) {
            Slider(value: Binding(get: { Double(all.firstIndex(of: mode) ?? 0) },
                                  set: { mode = all[min(all.count - 1, max(0, Int($0.rounded())))] }),
                   in: 0...Double(all.count - 1), step: 1)
                .accessibilityLabel("Boot Phases")
                .accessibilityValue(mode.title)
            HStack {
                ForEach(all, id: \.self) { m in
                    Text(m.title).font(.caption2)
                        .foregroundStyle(m == mode ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: m == all.first ? .leading : m == all.last ? .trailing : .center)
                }
            }
            .accessibilityHidden(true)
            Text(note ?? Self.preview[mode] ?? "").font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
