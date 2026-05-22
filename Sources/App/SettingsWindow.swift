import SwiftUI
import Carbon.HIToolbox

struct AppInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: NSImage?
    let path: String

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.id == rhs.id }
}

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case display = "Display"
    case overlays = "Overlays"
    case dock = "Dock"
    case television = "Television"
    case apps = "Apps"
    case presets = "Presets"
    case health = "Health"
    case license = "License"
    case about = "About"

    var icon: String {
        switch self {
        case .general: return "gear"
        case .display: return "display"
        case .overlays: return "square.stack.3d.up"
        case .dock: return "dock.rectangle"
        case .television: return "tv"
        case .apps: return "app.dashed"
        case .presets: return "slider.horizontal.3"
        case .health: return "heart.text.square"
        case .license: return "key"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var customPresetFiles: [String] = []
    @State private var installedApps: [AppInfo] = []
    @State private var searchText: String = ""
    @State private var showAppPicker = false
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14))
                            Text(tab.rawValue)
                                .font(.system(size: 10))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case .general: generalTab
                case .display: displayTab
                case .overlays: overlaysTab
                case .dock: DockSettingsTab()
                case .television: TVSettingsTab()
                case .apps: appsTab
                case .presets: presetsTab
                case .health: HealthCheckTab()
                case .license: LicenseTab()
                case .about: AboutTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 500)
        .onAppear {
            refreshCustomPresets()
            refreshInstalledApps()
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                Toggle("Enable Overlay on Launch", isOn: $settings.enableOnLaunch)
            }

            Section("Sleep & Lock") {
                Toggle("Stop Overlay on Sleep / Lock", isOn: $settings.stopOnSleep)
                Toggle("Resume Overlay after Wake", isOn: $settings.resumeAfterSleep)
                    .disabled(!settings.stopOnSleep)
                Text("Automatically stops the overlay when the Mac sleeps or the screen is locked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Defaults") {
                Picker("Default Preset", selection: $settings.defaultPreset) {
                    ForEach(PresetRegistry.availablePresets, id: \.id) { preset in
                        Text(preset.displayName).tag(preset.id)
                    }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Default Intensity")
                    HStack {
                        Slider(value: $settings.defaultIntensity, in: 0.1...1.0, step: 0.05)
                        Text("\(Int(settings.defaultIntensity * 100))%")
                            .frame(width: 40, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
            }

            Section("Hotkey") {
                HotkeyRecorderView()
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    // MARK: - Display

    private var displayTab: some View {
        Form {
            Section("System UI") {
                Toggle("Hide Dock & Menu Bar", isOn: $settings.hideSystemUI)
                Text("Hides the Dock and menu bar while the shader overlay is active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Vignette") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(settings.vignetteIntensity < 0.01 ? "Off" : "\(Int(settings.vignetteIntensity * 100))%")
                            .frame(width: 40)
                            .monospacedDigit()
                        Slider(value: $settings.vignetteIntensity, in: 0.0...1.0, step: 0.05)
                    }
                }
                Text("Darkens screen edges for a more authentic CRT look.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Performance") {
                Toggle("Low Latency Mode", isOn: $settings.lowLatencyMode)
                Text("60 fps capture & render. Reduces mouse lag but uses more GPU.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Half Resolution", isOn: $settings.halfResolution)
                Text("Capture at 1× instead of 2× (Retina). Halves GPU load, slightly softer image.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Monitor") {
                Text("Select target display in the menu bar under Display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let screens = NSScreen.screens
                ForEach(Array(screens.enumerated()), id: \.offset) { _, screen in
                    let res = "\(Int(screen.frame.width))×\(Int(screen.frame.height))"
                    LabeledContent(screen.localizedName, value: res)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    // MARK: - Overlays

    private var overlaysTab: some View {
        Form {
            Section("Scanline Overlay") {
                Picker("Scanlines", selection: $settings.scanlineOverlayName) {
                    Text("None").tag("")
                    ForEach(OverlayManager.builtinScanlines) { s in
                        Text(s.displayName).tag(s.id)
                    }
                    let custom = OverlayManager.customOverlays(type: .scanline)
                    if !custom.isEmpty {
                        Divider()
                        ForEach(custom) { overlay in
                            Text(overlay.displayName).tag(overlay.id)
                        }
                    }
                }
                .pickerStyle(.menu)

                if !settings.scanlineOverlayName.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(Int(settings.scanlineOverlayIntensity * 100))%")
                                .frame(width: 40)
                                .monospacedDigit()
                            Slider(value: $settings.scanlineOverlayIntensity, in: 0.1...1.0, step: 0.05)
                        }
                    }
                }
                Text("Additional scanline texture layered over the shader effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Screen Reflection") {
                Picker("Reflection", selection: $settings.reflectionName) {
                    Text("None").tag("")
                    ForEach(OverlayManager.builtinReflections) { r in
                        Text(r.displayName).tag(r.id)
                    }
                    let custom = OverlayManager.customOverlays(type: .reflection)
                    if !custom.isEmpty {
                        Divider()
                        ForEach(custom) { overlay in
                            Text(overlay.displayName).tag(overlay.id)
                        }
                    }
                }
                .pickerStyle(.menu)

                if !settings.reflectionName.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(Int(settings.reflectionIntensity * 100))%")
                                .frame(width: 40)
                                .monospacedDigit()
                            Slider(value: $settings.reflectionIntensity, in: 0.05...1.0, step: 0.05)
                        }
                    }
                }
                Text("Simulated glass glare / light reflection on the screen surface.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Custom Overlays") {
                Button("Open Overlays Folder") {
                    NSWorkspace.shared.open(OverlayManager.overlaysDirectory())
                }
                Text("Place PNG images in the scanline or reflection subfolder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    // MARK: - Apps

    private var appsTab: some View {
        Form {
            Section {
                Text("Assign a shader preset per app. When you apply the overlay to that app's window, the preset switches automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Per-App Presets") {
                let rules = settings.perAppPresets.sorted(by: { $0.key < $1.key })
                if rules.isEmpty {
                    Text("No per-app presets configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rules, id: \.key) { bundleID, presetID in
                        HStack(spacing: 8) {
                            appIconView(for: bundleID)
                                .frame(width: 24, height: 24)

                            Text(appDisplayName(for: bundleID))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Picker("", selection: Binding(
                                get: { presetID },
                                set: { settings.perAppPresets[bundleID] = $0 }
                            )) {
                                ForEach(PresetRegistry.availablePresets, id: \.id) { preset in
                                    Text(preset.displayName).tag(preset.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 180)

                            Button {
                                settings.perAppPresets.removeValue(forKey: bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section("Add Application") {
                HStack {
                    Button("Browse…") {
                        browseForApp()
                    }

                    Button("From Applications…") {
                        showAppPicker = true
                    }
                }

                if showAppPicker {
                    VStack(spacing: 6) {
                        TextField("Search apps…", text: $searchText)
                            .textFieldStyle(.roundedBorder)

                        let filtered = filteredInstalledApps
                        if filtered.isEmpty {
                            Text("No apps found.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 2) {
                                    ForEach(filtered) { app in
                                        Button {
                                            addApp(app)
                                        } label: {
                                            HStack(spacing: 8) {
                                                if let icon = app.icon {
                                                    Image(nsImage: icon)
                                                        .resizable()
                                                        .frame(width: 20, height: 20)
                                                }
                                                Text(app.name)
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                                if settings.perAppPresets.keys.contains(app.id) {
                                                    Image(systemName: "checkmark")
                                                        .foregroundStyle(.green)
                                                        .font(.caption)
                                                }
                                            }
                                            .contentShape(Rectangle())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                        }
                                        .buttonStyle(.plain)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.primary.opacity(0.05))
                                        )
                                    }
                                }
                            }
                            .frame(height: min(CGFloat(filtered.count) * 30, 160))
                        }

                        HStack {
                            Spacer()
                            Button("Done") {
                                showAppPicker = false
                                searchText = ""
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private var filteredInstalledApps: [AppInfo] {
        let available = installedApps.filter { !settings.perAppPresets.keys.contains($0.id) }
        if searchText.isEmpty { return available }
        let query = searchText.lowercased()
        return available.filter { $0.name.lowercased().contains(query) }
    }

    private func addApp(_ app: AppInfo) {
        settings.perAppPresets[app.id] = settings.defaultPreset
    }

    private func browseForApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an application"
        panel.prompt = "Add"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return }

        let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        settings.perAppPresets[bundleID] = settings.defaultPreset

        if !installedApps.contains(where: { $0.id == bundleID }) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            installedApps.append(AppInfo(id: bundleID, name: name, icon: icon, path: url.path))
            installedApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    @ViewBuilder
    private func appIconView(for bundleID: String) -> some View {
        if let app = installedApps.first(where: { $0.id == bundleID }),
           let icon = app.icon {
            Image(nsImage: icon)
                .resizable()
        } else if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path {
            let icon = NSWorkspace.shared.icon(forFile: path)
            Image(nsImage: icon)
                .resizable()
        } else {
            Image(systemName: "app")
                .resizable()
        }
    }

    private func appDisplayName(for bundleID: String) -> String {
        if let app = installedApps.first(where: { $0.id == bundleID }) {
            return app.name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID.components(separatedBy: ".").last ?? bundleID
    }

    private func refreshInstalledApps() {
        var apps: [AppInfo] = []
        var seen = Set<String>()
        let ownBundle = Bundle.main.bundleIdentifier ?? ""
        let searchPaths = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            NSHomeDirectory() + "/Applications",
        ]

        for searchPath in searchPaths {
            let url = URL(fileURLWithPath: searchPath)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil
            ) else { continue }

            for appURL in contents where appURL.pathExtension == "app" {
                guard let bundle = Bundle(url: appURL),
                      let bundleID = bundle.bundleIdentifier,
                      !bundleID.isEmpty,
                      bundleID != ownBundle,
                      !seen.contains(bundleID) else { continue }
                seen.insert(bundleID)

                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? appURL.deletingPathExtension().lastPathComponent

                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                icon.size = NSSize(width: 32, height: 32)
                apps.append(AppInfo(id: bundleID, name: name, icon: icon, path: appURL.path))
            }
        }

        installedApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Presets

    private var presetsTab: some View {
        Form {
            ForEach(PresetRegistry.categorizedPresets, id: \.0) { category, presets in
                Section(category.rawValue) {
                    ForEach(presets, id: \.id) { preset in
                        LabeledContent(preset.displayName, value: preset.description)
                    }
                }
            }

            Section("Custom Presets") {
                if customPresetFiles.isEmpty {
                    Text("No custom presets installed.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customPresetFiles, id: \.self) { name in
                        Text(name)
                    }
                }

                Button("Open Presets Folder") {
                    NSWorkspace.shared.open(settings.customPresetsDirectory)
                }

                Text("Place .metal shader files in the Presets folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private func refreshCustomPresets() {
        let fm = FileManager.default
        let dir = settings.customPresetsDirectory
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        customPresetFiles = files
            .filter { $0.pathExtension == "metal" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }
}

// MARK: - Hotkey Recorder

struct HotkeyRecorderView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text("Toggle Overlay")
            Spacer()
            Button(action: { isRecording.toggle() }) {
                Text(isRecording ? "Press keys…" : settings.hotkeyDisplayString)
                    .frame(minWidth: 100)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .overlay(
                HotkeyListenerView(isRecording: $isRecording)
                    .frame(width: 0, height: 0)
            )
        }
    }
}

struct HotkeyListenerView: NSViewRepresentable {
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> HotkeyNSView {
        let view = HotkeyNSView()
        view.onKeyRecorded = { keyCode, modifiers in
            let settings = AppSettings.shared
            settings.hotkeyCode = UInt32(keyCode)

            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift) { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option) { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            settings.hotkeyModifiers = carbonMods

            DispatchQueue.main.async {
                self.isRecording = false
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.registerHotkey()
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyNSView, context: Context) {
        if isRecording {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class HotkeyNSView: NSView {
    var onKeyRecorded: ((UInt16, NSEvent.ModifierFlags) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard !event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty else { return }
        onKeyRecorded?(event.keyCode, event.modifierFlags)
    }
}

// MARK: - Window Controller

final class SettingsWindowController {
    private var window: NSWindow?
    private var savedMenu: NSMenu?

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            installEditMenu()
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "RetroMac Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = SettingsWindowDelegate(controller: self)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        installEditMenu()
    }

    /// Install a standard Edit menu so ⌘C/⌘V/⌘A work in TextFields
    /// (LSUIElement / .accessory apps have no menu bar by default)
    func installEditMenu() {
        if NSApp.mainMenu != nil { return }

        let mainMenu = NSMenu()

        // App menu (empty, needed as first item)
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = NSMenu()
        mainMenu.addItem(appMenuItem)

        // Edit menu with standard actions
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    func removeEditMenu() {
        NSApp.mainMenu = nil
    }
}

/// Removes the Edit menu when the settings window closes
private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    weak var controller: SettingsWindowController?

    init(controller: SettingsWindowController) {
        self.controller = controller
    }

    func windowWillClose(_ notification: Notification) {
        controller?.removeEditMenu()
    }
}
