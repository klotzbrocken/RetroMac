import SwiftUI

/// "Camera & Streaming" — virtual camera / lower-third plus TV stream bookmarks, behind
/// one tab via a segmented switch (each sub-view keeps its own scroll region).
struct CameraStreamingTab: View {
    @State private var section: Sec = .camera
    enum Sec: String, CaseIterable, Identifiable {
        case camera = "Camera", streaming = "Streaming"
        var id: String { rawValue }
    }
    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(Sec.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            // VoiceOver: a pop-up with its own name, like the sidebar's. As a radio group called
            // "Section" it was taken for the sidebar's and could not be found.
            .accessibilityRepresentation {
                Picker("Camera section", selection: $section) {
                    ForEach(Sec.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            Rectangle().fill(Color.rmDivider).frame(height: 1)
            Group {
                switch section {
                case .camera:    CameraTab()
                case .streaming: TVSettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// "Dock & Themes" — retro dock configuration plus per-theme screensaver / boot screen,
/// behind one tab via a segmented switch.
struct DockThemesTab: View {
    @State private var section: Sec = .dock
    enum Sec: String, CaseIterable, Identifiable {
        case dock = "Themes", screensaver = "Screensaver"
        var id: String { rawValue }
    }
    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(Sec.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            // VoiceOver: a pop-up with its own name, like the sidebar's. As a radio group called
            // "Section" it was taken for the sidebar's and could not be found.
            .accessibilityRepresentation {
                Picker("Themes section", selection: $section) {
                    ForEach(Sec.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            Rectangle().fill(Color.rmDivider).frame(height: 1)
            Group {
                switch section {
                case .dock:        DockSettingsTab()
                case .screensaver: ScreensaverSettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
