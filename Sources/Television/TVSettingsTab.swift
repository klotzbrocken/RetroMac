import SwiftUI

struct TVSettingsTab: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var newName: String = ""
    @State private var newURL: String = ""

    private var allPresets: [(String, String)] {
        var list: [(String, String)] = [("", "None")]
        for (_, presets) in PresetRegistry.categorizedPresets {
            for p in presets {
                list.append((p.id, p.displayName))
            }
        }
        return list
    }

    var body: some View {
        Form {
            Section("Television Bookmarks") {
                if settings.tvBookmarks.isEmpty {
                    Text("No bookmarks configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(settings.tvBookmarks.enumerated()), id: \.element.id) { index, bookmark in
                        bookmarkRow(index: index, bookmark: bookmark)
                    }
                }
            }

            Section("Add Bookmark") {
                HStack {
                    TextField("Name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    TextField("URL", text: $newURL)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        guard !newName.isEmpty, !newURL.isEmpty else { return }
                        var url = newURL
                        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
                            url = "https://" + url
                        }
                        settings.tvBookmarks.append(TVBookmark(name: newName, url: url))
                        newName = ""
                        newURL = ""
                    }
                    .disabled(newName.isEmpty || newURL.isEmpty)
                }
            }

            Section("Info") {
                Text("Television plays m3u/m3u8 streams with CRT shader effects. Each bookmark can have a default shader preset that activates automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func bookmarkRow(index: Int, bookmark: TVBookmark) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bookmark.name)
                        .fontWeight(.medium)
                    Text(bookmark.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    settings.tvBookmarks.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("Preset:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { bookmark.presetID ?? "" },
                    set: { newVal in
                        var updated = settings.tvBookmarks
                        updated[index].presetID = newVal.isEmpty ? nil : newVal
                        settings.tvBookmarks = updated
                    }
                )) {
                    ForEach(allPresets, id: \.0) { id, name in
                        Text(name).tag(id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }
        }
    }
}
