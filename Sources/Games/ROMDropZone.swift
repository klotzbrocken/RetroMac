import SwiftUI
import UniformTypeIdentifiers

/// Drop zone view for adding ROMs to the library via drag & drop or file browser.
struct ROMDropZone: View {
    @ObservedObject private var library = ROMLibrary.shared
    @State private var isTargeted = false
    @State private var lastAddedMessage: String?
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                    )

                VStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 24))
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

                    Text("Drop ROM files here")
                        .font(.headline)
                        .foregroundStyle(isTargeted ? .primary : .secondary)

                    Text(supportedExtensionsText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Button("Browse...") {
                        browseForROMs()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 16)
            }
            .frame(height: 130)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }

            if let message = lastAddedMessage {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
        .animation(.easeInOut(duration: 0.3), value: lastAddedMessage)
        .alert("ROM Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                DispatchQueue.main.async {
                    addROM(from: url)
                }
            }
        }
    }

    private func browseForROMs() {
        let panel = NSOpenPanel()
        panel.title = "Select ROM Files"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        let extensions = Array(RetroSystem.allSupportedExtensions)
        panel.allowedContentTypes = extensions.compactMap { ext in
            UTType(filenameExtension: ext)
        }

        if panel.runModal() == .OK {
            for url in panel.urls {
                addROM(from: url)
            }
        }
    }

    private func addROM(from url: URL) {
        // Check for ambiguous extensions — ask user to pick the system
        let candidates = RetroSystem.detectAll(from: url)
        if candidates.count > 1 {
            let chosen = showSystemPicker(for: url, candidates: candidates)
            guard let system = chosen else { return } // user cancelled
            finishAddROM(from: url, system: system)
        } else {
            finishAddROM(from: url, system: candidates.first)
        }
    }

    private func finishAddROM(from url: URL, system: RetroSystem?) {
        if let entry = library.addROM(from: url, system: system) {
            lastAddedMessage = "Added \(entry.displayName) (\(entry.system.shortName))"
            // Clear message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if lastAddedMessage?.contains(entry.displayName) == true {
                    lastAddedMessage = nil
                }
            }
        } else {
            let ext = url.pathExtension.lowercased()
            if RetroSystem.detect(from: url) == nil && system == nil {
                errorMessage = "Unsupported file type: .\(ext)\n\nSupported: \(supportedExtensionsText)"
            } else {
                errorMessage = "This ROM is already in your library."
            }
            showError = true
        }
    }

    /// Show a system picker dialog for ambiguous ROM extensions (.iso, .bin, etc.)
    private func showSystemPicker(for url: URL, candidates: [RetroSystem]) -> RetroSystem? {
        let alert = NSAlert()
        alert.messageText = "Which system is this ROM for?"
        alert.informativeText = "\"\(url.lastPathComponent)\" matches multiple systems. Please select the correct one."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 28), pullsDown: false)
        for system in candidates {
            popup.addItem(withTitle: "\(system.displayName) (\(system.shortName))")
        }
        popup.selectItem(at: 0)
        alert.accessoryView = popup

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let selectedIndex = popup.indexOfSelectedItem
        guard selectedIndex >= 0, selectedIndex < candidates.count else { return candidates.first }
        return candidates[selectedIndex]
    }

    private var supportedExtensionsText: String {
        let exts = RetroSystem.allSupportedExtensions.sorted().map { ".\($0)" }
        return exts.joined(separator: " ")
    }
}

// MARK: - ROM Library List View

struct ROMLibrarySection: View {
    @ObservedObject private var library = ROMLibrary.shared
    @State private var romToDelete: ROMEntry?
    @State private var showDeleteConfirm = false

    var body: some View {
        if library.entries.isEmpty {
            Text("No ROMs added yet. Drop ROM files above to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        } else {
            ForEach(library.entriesBySystem, id: \.system) { group in
                systemSection(system: group.system, roms: group.roms)
            }
        }
    }

    private func systemSection(system: RetroSystem, roms: [ROMEntry]) -> some View {
        Section {
            ForEach(roms) { rom in
                romRow(rom: rom)
            }
        } header: {
            HStack(spacing: 4) {
                Image(systemName: system.sfSymbol)
                    .font(.caption)
                Text("\(system.displayName) (\(roms.count))")
            }
        }
    }

    private func romRow(rom: ROMEntry) -> some View {
        HStack(spacing: 8) {
            // Play button — always enabled; ROMLauncher handles missing emulators via auto-install
            Button {
                ROMLauncher.shared.launch(rom)
            } label: {
                Image(systemName: rom.system.emulator.isInstalled ? "play.fill" : "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundColor(rom.system.emulator.isInstalled ? .primary : .orange)
            }
            .buttonStyle(.borderless)
            .help(rom.system.emulator.isInstalled ? "Play \(rom.displayName)" : "Install \(rom.system.emulator.displayName) & Play")

            // Name + system
            VStack(alignment: .leading, spacing: 1) {
                Text(rom.displayName)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(rom.system.shortName)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(3)

                    if !rom.system.emulator.isInstalled {
                        Text("No emulator")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            // Shader preset picker
            Picker("", selection: Binding(
                get: { rom.presetID ?? "" },
                set: { newValue in
                    var updated = rom
                    updated.presetID = newValue.isEmpty ? nil : newValue
                    library.updateROM(updated)
                }
            )) {
                Text("Default (\(rom.system.defaultPresetID))").tag("")
                Divider()
                // Lite — no screen recording needed
                Text("⚡ CRT Lite").tag("crt-lite")
                Text("⚡ LCD Lite").tag("lcd-lite")
                Text("⚡ LCD Retro Lite").tag("lcd-retro-lite")
                Text("⚡ LCD Sharp Lite").tag("lcd-sharp-lite")
                Text("⚡ LCD Broken Lite").tag("lcd-broken-lite")
                Text("⚡ B&W Lite").tag("bw-lite")
                Text("⚡ Amber Lite").tag("amber-lite")
                Text("⚡ Scanlines Lite").tag("scanlines-lite")
                Text("⚡ VHS Lite").tag("vhs-lite")
                Text("⚡ Film Scratches Lite").tag("grain-lite")
                Divider()
                // Full shaders (screen recording)
                Text("CRT Royale").tag("crt-royale-lite")
                Text("Trinitron").tag("trinitron-tv")
                Text("NTSC").tag("ntsc")
                Text("PAL").tag("pal")
                Text("Game Boy").tag("gameboy")
                Text("LCD Grid").tag("lcd-grid")
                Text("VHS").tag("vhs")
                Text("Amber Monitor").tag("amber-monitor")
            }
            .pickerStyle(.menu)
            .frame(width: 140)
            .help("CRT shader preset")

            // Delete button
            Button {
                romToDelete = rom
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
            .help("Remove from library")
        }
        .alert("Remove ROM?", isPresented: $showDeleteConfirm) {
            Button("Remove (keep file)") {
                if let rom = romToDelete {
                    library.removeROM(id: rom.id, deleteFile: false)
                }
            }
            Button("Remove & Delete File", role: .destructive) {
                if let rom = romToDelete {
                    library.removeROM(id: rom.id, deleteFile: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let rom = romToDelete {
                Text("Remove \"\(rom.displayName)\" from your library?")
            }
        }
    }
}

// MARK: - Emulator Status Section

struct EmulatorStatusSection: View {
    var body: some View {
        Section("Emulators") {
            ForEach(EmulatorType.allCases) { emulator in
                emulatorRow(emulator)
            }
        }
    }

    private func emulatorRow(_ emulator: EmulatorType) -> some View {
        HStack {
            Image(systemName: emulator.isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(emulator.isInstalled ? .green : .red)

            Text(emulator.displayName)

            Spacer()

            if emulator.isInstalled {
                Text("Installed")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else if emulator.canAutoInstall {
                Button("Install") {
                    EmulatorInstaller.shared.install(emulator) { _ in }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            } else {
                Button("Get") {
                    if let url = URL(string: emulator.websiteURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            Text(emulator.supportedSystems.map(\.shortName).joined(separator: ", "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 120, alignment: .trailing)
        }
    }
}
