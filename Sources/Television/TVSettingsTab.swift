import SwiftUI

struct TVSettingsTab: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var newName: String = ""
    @State private var newURL: String = ""
    @State private var bezelStatus: String = ""
    @State private var downloadingBezel: String? = nil

    private var allPresets: [(String, String)] {
        var list: [(String, String)] = [("", "None")]
        for (_, presets) in PresetRegistry.categorizedPresets {
            for p in presets { list.append((p.id, p.displayName)) }
        }
        return list
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RMSpacing.section) {
                RMCard(title: "Television bookmarks",
                       subtitle: "m3u/m3u8 streams with CRT effects. Each bookmark can auto-activate a preset.",
                       bodyPadding: 0) {
                    if settings.tvBookmarks.isEmpty {
                        Text("No bookmarks configured.")
                            .font(.rmSecondary).foregroundColor(.rmTextSecondary)
                            .padding(RMSpacing.card)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(settings.tvBookmarks.enumerated()), id: \.element.id) { index, bookmark in
                                bookmarkRow(index: index, bookmark: bookmark,
                                            isLast: index == settings.tvBookmarks.count - 1)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                RMCard(title: "Tube Mode",
                       subtitle: "The flyout's one-click retro TV: streams inside a real TV bezel with a CRT shader. Arrow keys zap channels, ESC turns it off, double-click toggles fullscreen.",
                       bodyPadding: RMSpacing.card) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("TV bezel").frame(width: 90, alignment: .leading)
                            Picker("", selection: $settings.tvTubeBezel) {
                                Text("Simple frame (built-in)").tag("")
                                ForEach(BezelStore.shared.available) { b in
                                    Text(BezelStore.shared.isDownloaded(b) ? b.name : "\(b.name)  (download)")
                                        .tag(b.file)
                                }
                            }
                            .labelsHidden().frame(width: 260)
                            .onChange(of: settings.tvTubeBezel) { _, file in
                                guard let bezel = BezelStore.shared.bezel(named: file),
                                      !BezelStore.shared.isDownloaded(bezel) else {
                                    TubeModeController.shared.refreshAppearance(); return
                                }
                                downloadingBezel = file
                                bezelStatus = "Downloading \(bezel.name)…"
                                BezelStore.shared.download(bezel) { result in
                                    downloadingBezel = nil
                                    switch result {
                                    case .success:
                                        bezelStatus = "\(bezel.name) ready."
                                        TubeModeController.shared.refreshAppearance()
                                    case .failure(let e):
                                        bezelStatus = "Download failed: \(e.localizedDescription)"
                                        settings.tvTubeBezel = ""
                                    }
                                }
                            }
                            if downloadingBezel != nil { ProgressView().controlSize(.small) }
                        }
                        HStack {
                            Text("Shader").frame(width: 90, alignment: .leading)
                            Picker("", selection: $settings.tvTubePreset) {
                                ForEach(allPresets.filter { !$0.0.isEmpty }, id: \.0) { id, name in
                                    Text(name).tag(id)
                                }
                            }
                            .labelsHidden().frame(width: 260)
                            .onChange(of: settings.tvTubePreset) { _, _ in
                                TubeModeController.shared.refreshAppearance()
                            }
                        }
                        HStack {
                            Text("Display").frame(width: 90, alignment: .leading)
                            Picker("", selection: $settings.tvTubeDisplayID) {
                                Text("Auto (external if connected)").tag(CGDirectDisplayID(0))
                                ForEach(NSScreen.screens, id: \.displayID) { s in
                                    Text(s.localizedName).tag(s.displayID)
                                }
                            }
                            .labelsHidden().frame(width: 260)
                        }
                        if !bezelStatus.isEmpty {
                            Text(bezelStatus).font(.rmSecondary).foregroundColor(.rmTextSecondary)
                        }
                        Text("Bezel artwork: Soqueroeu Mega Bezel TV Backgrounds — downloaded on demand from the author's GitHub.")
                            .font(.rmSecondary).foregroundColor(.rmTextSecondary)
                    }
                }

                RMCard(title: "Add bookmark", bodyPadding: RMSpacing.card) {
                    HStack(spacing: 8) {
                        TextField("Name", text: $newName)
                            .textFieldStyle(.roundedBorder).frame(width: 140)
                        TextField("URL", text: $newURL)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            guard !newName.isEmpty, !newURL.isEmpty else { return }
                            var url = newURL
                            if !url.hasPrefix("http://") && !url.hasPrefix("https://") { url = "https://" + url }
                            settings.tvBookmarks.append(TVBookmark(name: newName, url: url))
                            newName = ""; newURL = ""
                        }
                        .buttonStyle(RMPrimaryButtonStyle())
                        .disabled(newName.isEmpty || newURL.isEmpty)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private func bookmarkRow(index: Int, bookmark: TVBookmark, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bookmark.name).font(.rmBody).foregroundColor(.rmTextPrimary)
                        Text(bookmark.url).font(.rmSecondary).foregroundColor(.rmTextSecondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button { settings.tvBookmarks.remove(at: index) } label: {
                        Image(systemName: "minus.circle.fill").foregroundColor(.rmDanger)
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Text("Preset").font(.rmSecondary).foregroundColor(.rmTextSecondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { bookmark.presetID ?? "" },
                        set: { newVal in
                            var updated = settings.tvBookmarks
                            updated[index].presetID = newVal.isEmpty ? nil : newVal
                            settings.tvBookmarks = updated
                        }
                    )) {
                        ForEach(allPresets, id: \.0) { item in Text(item.1).tag(item.0) }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 180)
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
