import SwiftUI

/// A sheet that displays available icons from the current theme for quick selection
struct ThemeIconPickerSheet: View {
    let bundleID: String
    let theme: ThemeBundle?
    let onSelectThemeIcon: (String) -> Void
    let onBrowse: () -> Void
    let onCancel: () -> Void

    @State private var searchText = ""

    private var themeIcons: [(name: String, url: URL)] {
        guard let theme = theme else { return [] }
        let icons = theme.availableIcons()
        if searchText.isEmpty { return icons }
        let query = searchText.lowercased()
        return icons.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Choose Icon")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            if let theme = theme {
                Text("Icons from \"\(theme.name)\" theme")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            // Search
            TextField("Search icons...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            Divider()

            // Icon grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 8)
                ], spacing: 8) {
                    ForEach(themeIcons, id: \.url) { iconInfo in
                        Button {
                            onSelectThemeIcon(iconInfo.url.path)
                        } label: {
                            VStack(spacing: 4) {
                                if let img = NSImage(contentsOf: iconInfo.url) {
                                    Image(nsImage: img)
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: 40, height: 40)
                                } else {
                                    Image(systemName: "questionmark.square")
                                        .font(.system(size: 30))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 40, height: 40)
                                }
                                Text(iconInfo.name)
                                    .font(.system(size: 9))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.primary)
                            }
                            .frame(width: 70, height: 70)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.primary.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .frame(minHeight: 200, maxHeight: 300)

            Divider()

            // Browse option
            HStack {
                Button {
                    onBrowse()
                } label: {
                    Label("Browse Files...", systemImage: "folder")
                }
                Spacer()
            }
            .padding()
        }
        .frame(width: 380, height: 440)
    }
}
