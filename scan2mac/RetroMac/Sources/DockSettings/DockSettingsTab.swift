import SwiftUI
import UniformTypeIdentifiers
import Carbon.HIToolbox

struct DockSettingsTab: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var dockApps: [DockApp] = []
    @State private var themes: [ThemeBundle] = []
    @State private var newThemeName: String = ""
    @State private var showingSaveSheet: Bool = false
    @State private var iconOverrideRefresh: Bool = false

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Hide System Dock", isOn: $settings.dockHideSystemDock)
                Picker("Theme", selection: $settings.dockTheme) {
                    ForEach(themes, id: \.name) { theme in
                        Text(theme.name).tag(theme.name)
                    }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(Int(settings.dockIconScale * 100))%")
                            .frame(width: 40)
                            .monospacedDigit()
                        Slider(value: $settings.dockIconScale, in: 0.5...2.0, step: 0.1)
                    }
                    Text("Dock size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(Int(settings.dockTransparency * 100))%")
                            .frame(width: 40)
                            .monospacedDigit()
                        Slider(value: $settings.dockTransparency, in: 0.3...1.0, step: 0.05)
                    }
                    Text("Dock transparency")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Theme Presets") {
                ForEach(themes, id: \.name) { theme in
                    HStack {
                        Text(theme.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Picker("", selection: Binding(
                            get: {
                                if let override = settings.themePresetOverrides[theme.name] {
                                    return override  // empty = "None"
                                }
                                return theme.config.defaultPreset ?? ""
                            },
                            set: { newVal in
                                settings.themePresetOverrides[theme.name] = newVal
                            }
                        )) {
                            Text("None").tag("")
                            ForEach(PresetRegistry.builtinPresets, id: \.id) { preset in
                                Text(preset.displayName).tag(preset.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200)
                    }
                }
                Text("Choose a default shader preset for each theme. Activated automatically when switching themes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Display") {
                Picker("Target Display", selection: $settings.dockTargetDisplayID) {
                    Text("Main Display").tag(CGDirectDisplayID(0))
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in
                        let res = "\(Int(screen.frame.width))x\(Int(screen.frame.height))"
                        Text("\(screen.localizedName) (\(res))").tag(screen.displayID)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Hotkey") {
                DockHotkeyRecorderView()
            }

            Section("Dock Apps") {
                Toggle("Show running apps in Dock", isOn: $settings.dockShowRunningApps)

                if dockApps.isEmpty {
                    Text("No apps configured. Default apps will be added on first launch.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dockApps) { app in
                        dockAppRow(app)
                    }
                }

                HStack {
                    Button("Add App...") {
                        browseForApp()
                    }
                    Spacer()
                    Button("Reset to Defaults") {
                        let fm = FileManager.default
                        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                        let configURL = appSupport.appendingPathComponent("RetroMac/dock-apps.json")
                        try? fm.removeItem(at: configURL)
                        let _ = AppManager.shared
                        AppManager.shared.load()
                        refreshApps()
                    }
                    .font(.caption)
                }
            }

            Section("Themes") {
                HStack {
                    Button("Open Themes Folder") {
                        NSWorkspace.shared.open(ThemeManager.shared.userThemesDirectory)
                    }
                    Button("Import Theme...") {
                        importTheme()
                    }
                }

                if ThemeManager.shared.canSaveExistingTheme {
                    Button("Save Icon Changes to \"\(settings.dockTheme)\"") {
                        do {
                            try ThemeManager.shared.saveExistingTheme()
                            themes = ThemeManager.shared.availableThemes
                            iconOverrideRefresh.toggle()
                        } catch {
                            print("[Dock] Save theme failed: \(error)")
                        }
                    }
                }

                HStack {
                    TextField("New theme name", text: $newThemeName)
                        .textFieldStyle(.roundedBorder)
                    Button("Save as new Theme") {
                        guard !newThemeName.isEmpty else { return }
                        do {
                            try ThemeManager.shared.saveAsNewTheme(name: newThemeName)
                            themes = ThemeManager.shared.availableThemes
                            newThemeName = ""
                            iconOverrideRefresh.toggle()
                        } catch {
                            print("[Dock] Save theme failed: \(error)")
                        }
                    }
                    .disabled(newThemeName.isEmpty)
                }
                if ThemeManager.shared.hasOverrides() {
                    Text("You have custom icon overrides for \"\(settings.dockTheme)\". Save them as a new theme or save to the existing theme.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Place .retromactheme bundles in the themes folder or import them here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .onAppear {
            refreshApps()
            themes = ThemeManager.shared.availableThemes
        }
    }

    @ViewBuilder
    private func dockAppRow(_ app: DockApp) -> some View {
        let hasCustom = ThemeManager.shared.customIconPath(for: app.bundleID) != nil && iconOverrideRefresh == iconOverrideRefresh
        HStack(spacing: 8) {
            DockAppIconView(bundleID: app.bundleID)
                .frame(width: 24, height: 24)
            Text(app.displayName)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                browseForCustomIcon(bundleID: app.bundleID)
            } label: {
                Image(systemName: hasCustom ? "paintbrush.fill" : "paintbrush")
                    .foregroundStyle(hasCustom ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Set custom icon for current theme")
            if hasCustom {
                Button {
                    ThemeManager.shared.setCustomIcon(for: app.bundleID, path: nil)
                    iconOverrideRefresh.toggle()
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to theme icon")
            }
            Button {
                AppManager.shared.removeApp(bundleID: app.bundleID)
                refreshApps()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    private func refreshApps() {
        dockApps = AppManager.shared.apps
    }

    private func browseForCustomIcon(bundleID: String) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.png, UTType.icns, UTType.tiff, UTType.jpeg]
        panel.message = "Choose a custom icon for \"\(settings.dockTheme)\" theme"
        panel.prompt = "Set Icon"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.level = .floating
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ThemeManager.shared.setCustomIcon(for: bundleID, path: url.path)
        iconOverrideRefresh.toggle()
        print("[Dock] Custom icon set for \(bundleID): \(url.path)")
    }

    private func browseForApp() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an application to add to the Dock"
        panel.prompt = "Add"
        panel.level = .floating

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return }

        AppManager.shared.addApp(bundleID: bundleID)
        refreshApps()
    }

    private func importTheme() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.folder]
        panel.message = "Select a .retromactheme bundle"
        panel.prompt = "Import"
        panel.level = .floating

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.pathExtension == "retromactheme" else {
            print("[Dock] Not a .retromactheme bundle")
            return
        }
        do {
            try ThemeManager.shared.importTheme(from: url)
            themes = ThemeManager.shared.availableThemes
        } catch {
            print("[Dock] Import failed: \(error)")
        }
    }
}

struct DockAppIconView: View {
    let bundleID: String

    var body: some View {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path {
            let icon = NSWorkspace.shared.icon(forFile: path)
            Image(nsImage: icon)
                .resizable()
        } else {
            Image(systemName: "app")
                .resizable()
        }
    }
}

struct DockHotkeyRecorderView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text("Toggle Dock")
            Spacer()
            Button(action: { isRecording.toggle() }) {
                Text(isRecording ? "Press keys..." : dockHotkeyDisplayString)
                    .frame(minWidth: 100)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .overlay(
                DockHotkeyListenerView(isRecording: $isRecording)
                    .frame(width: 0, height: 0)
            )
        }
    }

    private var dockHotkeyDisplayString: String {
        var parts: [String] = []
        if settings.dockHotkeyModifiers & UInt32(controlKey) != 0 { parts.append("\u{2303}") }
        if settings.dockHotkeyModifiers & UInt32(optionKey) != 0 { parts.append("\u{2325}") }
        if settings.dockHotkeyModifiers & UInt32(shiftKey) != 0 { parts.append("\u{21E7}") }
        if settings.dockHotkeyModifiers & UInt32(cmdKey) != 0 { parts.append("\u{2318}") }
        parts.append(AppSettings.keyName(for: settings.dockHotkeyCode))
        return parts.joined()
    }
}

struct DockHotkeyListenerView: NSViewRepresentable {
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> DockHotkeyNSView {
        let view = DockHotkeyNSView()
        view.onKeyRecorded = { keyCode, modifiers in
            let settings = AppSettings.shared
            settings.dockHotkeyCode = UInt32(keyCode)
            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift) { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option) { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            settings.dockHotkeyModifiers = carbonMods
            DispatchQueue.main.async { self.isRecording = false }
        }
        return view
    }

    func updateNSView(_ nsView: DockHotkeyNSView, context: Context) {
        if isRecording { nsView.window?.makeFirstResponder(nsView) }
    }
}

final class DockHotkeyNSView: NSView {
    var onKeyRecorded: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        guard !event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty else { return }
        onKeyRecorded?(event.keyCode, event.modifierFlags)
    }
}
