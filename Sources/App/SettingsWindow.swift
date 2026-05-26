import SwiftUI
import Carbon.HIToolbox
import ScreenCaptureKit
import Sparkle

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
    case dock = "Dock"
    case television = "Television"
    case camera = "Camera"
    case games = "Games"
    case apps = "Apps"
    case shader = "Shader"
    case about = "About"

    var icon: String {
        switch self {
        case .general: return "gear"
        case .display: return "display"
        case .dock: return "dock.rectangle"
        case .television: return "tv"
        case .camera: return "camera.fill"
        case .games: return "gamecontroller"
        case .apps: return "app.dashed"
        case .shader: return "slider.horizontal.3"
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
    let updater: SPUUpdater

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
                case .dock: DockSettingsTab()
                case .television: TVSettingsTab()
                case .camera: cameraTab
                case .games: GamesSettingsTab()
                case .apps: appsTab
                case .shader: shaderTab
                case .about: AboutTab(updater: updater)
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

    @State private var screenRecordingGranted: Bool?
    @State private var accessibilityGranted: Bool?
    @State private var automationGranted: Bool?

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
                Toggle("Reset to Defaults after Awake", isOn: $settings.resetOnWake)
                    .disabled(!settings.stopOnSleep || !settings.resumeAfterSleep)
                Text("Automatically stops the overlay when the Mac sleeps or the screen is locked. Reset restores the default shader preset on wake.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hotkey") {
                HotkeyRecorderView()
            }

            Section("Permissions") {
                permissionRow("Screen Recording", status: screenRecordingGranted)
                permissionRow("Accessibility", status: accessibilityGranted)
                permissionRow("Automation", status: automationGranted)

                HStack {
                    Button("Recheck") {
                        checkPermissions()
                    }
                    .font(.caption)
                    Spacer()
                    Button("Re-run Setup Assistant") {
                        AppDelegate.shared?.showOnboarding()
                    }
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .task {
            checkPermissions()
        }
    }

    @ViewBuilder
    private func permissionRow(_ name: String, status: Bool?) -> some View {
        HStack {
            Text(name)
            Spacer()
            switch status {
            case .some(true):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Granted").foregroundStyle(.secondary)
            case .some(false):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Not Granted").foregroundStyle(.secondary)
            case .none:
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func checkPermissions() {
        screenRecordingGranted = nil
        accessibilityGranted = AXIsProcessTrusted()
        automationGranted = SystemUIHelper.testAutomation()

        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                await MainActor.run { screenRecordingGranted = true }
            } catch {
                await MainActor.run { screenRecordingGranted = false }
            }
        }
    }

    // MARK: - Display

    private var displayTab: some View {
        Form {
            Section("Performance") {
                Picker("Profile", selection: $settings.performanceProfile) {
                    ForEach(PerformanceProfile.allCases) { profile in
                        HStack {
                            Image(systemName: profile.icon)
                            VStack(alignment: .leading) {
                                Text(profile.displayName)
                                Text(profile.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(profile)
                    }
                }
                .pickerStyle(.radioGroup)
                Text("Changes take effect when the overlay is restarted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Low Latency Mode (60 fps)", isOn: $settings.lowLatencyMode)
                Text("Overrides profile FPS to 60. Reduces mouse lag but uses more GPU.")
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

    // MARK: - Shader

    private var cameraTab: some View {
        Form {
            Section("Virtual Camera") {
                let vcam = VirtualCameraManager.shared
                HStack {
                    Circle()
                        .fill(vcam.isRunning ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(vcam.isRunning ? "Camera active" : "Camera inactive")
                        .foregroundStyle(.secondary)
                }

                Picker("Shader", selection: Binding(
                    get: { vcam.selectedShader },
                    set: { vcam.changeShader($0) }
                )) {
                    ForEach(PresetRegistry.categorizedPresets, id: \.0) { category, presets in
                        ForEach(presets, id: \.id) { preset in
                            Text(preset.displayName).tag(preset.id)
                        }
                    }
                }

                Slider(value: Binding(
                    get: { vcam.shaderIntensity },
                    set: { vcam.updateIntensity($0) }
                ), in: 0...1) {
                    Text("Intensity")
                }
            }

            Section("Lower Third (Bauchbinde)") {
                Text("Available with Late Night CRT and Newsroom 1987 shaders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show Lower Third", isOn: $settings.lowerThirdEnabled)

                TextField("Name", text: $settings.lowerThirdName, prompt: Text("Your Name"))
                TextField("Title", text: $settings.lowerThirdTitle, prompt: Text("Host / Reporter / Guest"))

                Picker("Style", selection: $settings.lowerThirdStyle) {
                    Text("Late Night (Gold)").tag("latenight")
                    Text("Newsroom (Red/Blue)").tag("newsroom")
                }
                .pickerStyle(.segmented)

                Text("The style is auto-selected based on the active shader. Manual override applies when using other shaders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private var shaderTab: some View {
        Form {
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

            ForEach(PresetRegistry.categorizedPresets, id: \.0) { category, presets in
                Section(category.rawValue) {
                    ForEach(presets, id: \.id) { preset in
                        LabeledContent(preset.displayName, value: preset.description)
                    }
                }
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
    var updater: SPUUpdater?

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            installEditMenu()
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView(updater: updater!))
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
