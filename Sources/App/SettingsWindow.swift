import SwiftUI
import Carbon.HIToolbox
import ScreenCaptureKit
import Sparkle

// MARK: - App Info (used by per-app rules + old apps tab)

struct AppInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: NSImage?
    let path: String

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.id == rhs.id }
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable {
    case dock = "dock"
    case retroMode = "retroMode"
    case camera = "camera"
    case games = "games"
    case advanced = "advanced"
    case about = "about"

    var label: String {
        switch self {
        case .dock: return "Themes"
        case .retroMode: return "Retro Mode"
        case .camera: return "Camera & Streaming"
        case .games: return "Games"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .dock: return "paintpalette"
        case .retroMode: return "wand.and.stars"
        case .camera: return "camera.fill"
        case .games: return "gamecontroller"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }

    /// Section grouping: nil = Main, "Surfaces", "System"
    var section: String? {
        switch self {
        case .dock, .retroMode: return nil
        case .camera, .games: return "Surfaces"
        case .advanced, .about: return "System"
        }
    }

    /// Title bar subtitle
    var subtitle: String? {
        switch self {
        case .dock: return "Pick a theme and configure the retro dock."
        case .advanced: return "Performance, hotkeys, per-app rules and timers."
        default: return nil
        }
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var selectedTab: SettingsTab
    let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        let saved = AppSettings.shared.lastSettingsTab
        _selectedTab = State(initialValue: SettingsTab(rawValue: saved) ?? .dock)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            SettingsSidebar(selectedTab: $selectedTab)
                .frame(width: 200)

            // Vertical divider
            Rectangle()
                .fill(Color.rmBorder)
                .frame(width: 1)

            // Detail pane
            SettingsDetailPane(selectedTab: $selectedTab, updater: updater)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 640)
        .background(ZStack { Color.rmBg; RMScanline() })
        .onChange(of: selectedTab) { newTab in
            settings.lastSettingsTab = newTab.rawValue
        }
    }
}

// MARK: - Sidebar

struct SettingsSidebar: View {
    @Binding var selectedTab: SettingsTab
    @ObservedObject private var settings = AppSettings.shared

    // Group tabs by section in order
    private var mainTabs: [SettingsTab] { [.dock, .retroMode] }
    private var surfacesTabs: [SettingsTab] { [.camera, .games] }
    private var systemTabs: [SettingsTab] { [.advanced, .about] }

    var body: some View {
        VStack(spacing: 0) {
            // Brand mark area (44 px title bar)
            HStack(spacing: 8) {
                // App icon
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                Text("RetroMac")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.rmTextPrimary)
                Spacer()
            }
            .frame(height: 44)
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .padding(.top, 24) // higher than before but clear of the traffic-light buttons

            // Nav items
            ScrollView {
                VStack(spacing: 2) {
                    // Main group (no header)
                    ForEach(mainTabs, id: \.self) { tab in
                        SidebarNavItem(tab: tab, isSelected: selectedTab == tab) {
                            selectedTab = tab
                        }
                    }

                    // Surfaces
                    SidebarSectionHeader(title: "Surfaces")
                    ForEach(surfacesTabs, id: \.self) { tab in
                        SidebarNavItem(tab: tab, isSelected: selectedTab == tab) {
                            selectedTab = tab
                        }
                    }

                    // System
                    SidebarSectionHeader(title: "System")
                    ForEach(systemTabs, id: \.self) { tab in
                        SidebarNavItem(tab: tab, isSelected: selectedTab == tab) {
                            selectedTab = tab
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }

            Spacer()

            // Status footer
            SidebarStatusFooter()
        }
        .background(Color.rmSidebarBg)
    }
}

// MARK: - Sidebar Components

struct CRTBrandMark: View {
    var body: some View {
        ZStack {
            // Dark CRT body
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.172, green: 0.192, blue: 0.220), Color(red: 0.094, green: 0.106, blue: 0.122)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 22, height: 18)

            // Green phosphor glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.247, green: 0.725, blue: 0.420).opacity(0.55), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 9
                    )
                )
                .frame(width: 18, height: 14)

            // Scanlines hint
            VStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.rmAccent.opacity(0.3))
                        .frame(height: 1.5)
                }
            }
            .frame(width: 18, height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

struct SidebarSectionHeader: View {
    var title: String

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.rmSidebarHeader)
                .tracking(0.6)
                .foregroundColor(.rmTextTertiary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}

struct SidebarNavItem: View {
    var tab: SettingsTab
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Active accent bar
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.rmAccent)
                        .frame(width: 2, height: 16)
                        .padding(.trailing, 8)
                } else {
                    Color.clear
                        .frame(width: 2)
                        .padding(.trailing, 8)
                }

                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 14, height: 14)
                    .foregroundColor(isSelected ? .rmTextPrimary : .rmTextSecondary)

                Text(tab.label)
                    .font(.rmSidebarItem)
                    .fontWeight(isSelected ? .medium : .regular)
                    .foregroundColor(isSelected ? .rmTextPrimary : .rmTextSecondary)
                    .padding(.leading, 10)

                Spacer()
            }
            .frame(height: 28)
            .padding(.horizontal, 2)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: RMRadius.button)
                            .fill(Color.rmSurface)
                            .rmSidebarActiveShadow()
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

struct SidebarStatusFooter: View {
    @ObservedObject private var settings = AppSettings.shared

    private var overlayIsOn: Bool {
        (NSApp.delegate as? AppDelegate)?.isActive ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.rmDivider)
                .frame(height: 1)

            HStack(spacing: 10) {
                // Status dot
                ZStack {
                    if overlayIsOn {
                        Circle()
                            .fill(Color.rmAccentSoft)
                            .frame(width: 14, height: 14)
                    }
                    Circle()
                        .fill(overlayIsOn ? Color.rmAccent : Color.rmTextTertiary)
                        .frame(width: 8, height: 8)
                }

                HStack(spacing: 4) {
                    Text("Overlay")
                        .font(.rmSecondary)
                        .foregroundColor(.rmTextSecondary)
                    Text(overlayIsOn ? "on" : "off")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(overlayIsOn ? .rmTextPrimary : .rmTextTertiary)
                }

                Spacer()

                if overlayIsOn {
                    Text("\(settings.targetFPS) fps")
                        .font(.rmMono(size: 10.5))
                        .foregroundColor(.rmTextTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Detail Pane

struct SettingsDetailPane: View {
    @Binding var selectedTab: SettingsTab
    let updater: SPUUpdater

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            DetailTitleBar(tab: selectedTab, updater: updater)

            // Content
            Group {
                switch selectedTab {
                case .dock:
                    DockThemesTab()
                case .retroMode:
                    RetroModeTab()
                case .camera:
                    CameraStreamingTab()
                case .games:
                    GamesSettingsTab()
                case .advanced:
                    AdvancedTab()
                case .about:
                    AboutTab(updater: updater)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct DetailTitleBar: View {
    var tab: SettingsTab
    let updater: SPUUpdater

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(tab.label)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundColor(.rmTextPrimary)

                if let subtitle = tab.subtitle {
                    Rectangle()
                        .fill(Color.rmBorder)
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 8)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.rmTextSecondary)
                }

                Spacer()

                // Toolbar buttons per tab
                toolbarButtons
            }
            .frame(height: 46)
            .padding(.horizontal, 20)
            .background(Color.rmSurface)

            Rectangle()
                .fill(Color.rmBorder)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        switch tab {
        case .dock:
            // Theme import lives in-context as "Add custom…" in the Themes section.
            Button("Show dock now") {
                AppSettings.shared.dockEnabled = true
                DockController.shared.start()
            }
            .buttonStyle(RMPrimaryButtonStyle())
        default:
            EmptyView()
        }
    }
}

// MARK: - Updates Tab

// MARK: - Camera Tab (kept from old cameraTab)

struct CameraTab: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        let vcam = VirtualCameraManager.shared
        return ScrollView {
            VStack(alignment: .leading, spacing: RMSpacing.section) {
                RMCard(title: "Virtual Camera", bodyPadding: 0) {
                    VStack(spacing: 0) {
                        RMRow(label: "Status") {
                            HStack(spacing: 6) {
                                Circle().fill(vcam.isRunning ? Color.rmAccent : Color.rmTextTertiary)
                                    .frame(width: 8, height: 8)
                                Text(vcam.isRunning ? "Active" : "Inactive")
                                    .font(.rmSecondary).foregroundColor(.rmTextSecondary)
                            }
                        }
                        RMRow(label: "Shader") {
                            Picker("", selection: Binding(get: { vcam.selectedShader }, set: { vcam.changeShader($0) })) {
                                ForEach(PresetRegistry.categorizedPresets, id: \.0) { _, presets in
                                    ForEach(presets, id: \.id) { Text($0.displayName).tag($0.id) }
                                }
                            }
                            .labelsHidden().frame(width: 180)
                        }
                        RMRow(label: "Intensity", isLast: true) {
                            Slider(value: Binding(get: { vcam.shaderIntensity }, set: { vcam.updateIntensity($0) }), in: 0...1)
                                .frame(width: 180)
                        }
                    }
                }

                RMCard(title: "Lower Third",
                       subtitle: "Available with Late Night CRT and Newsroom 1987 shaders.",
                       bodyPadding: 0) {
                    VStack(spacing: 0) {
                        RMRow(label: "Show lower third") { sw($settings.lowerThirdEnabled) }
                        RMRow(label: "Name") {
                            TextField("Your Name", text: $settings.lowerThirdName)
                                .textFieldStyle(.roundedBorder).frame(width: 180)
                        }
                        RMRow(label: "Title") {
                            TextField("Host / Reporter / Guest", text: $settings.lowerThirdTitle)
                                .textFieldStyle(.roundedBorder).frame(width: 180)
                        }
                        RMRow(label: "Style",
                              hint: "Auto-selected by the active shader; manual override applies to others.",
                              isLast: true) {
                            Picker("", selection: $settings.lowerThirdStyle) {
                                Text("Late Night (Gold)").tag("latenight")
                                Text("Newsroom (Red/Blue)").tag("newsroom")
                            }
                            .labelsHidden().pickerStyle(.menu).frame(width: 180)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environment(\.colorScheme, .light)
    }

    private func sw(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding).toggleStyle(.switch).tint(.rmAccent).labelsHidden()
    }
}

// MARK: - Per-App Rules Tab (migrated from old Apps tab)

struct PerAppRulesTab: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var installedApps: [AppInfo] = []
    @State private var searchText: String = ""
    @State private var showAppPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: RMSpacing.section) {
                // Rules list
                RMCard(
                    title: "Per-app rules",
                    subtitle: "Auto-switch to a specific preset when an app comes to front.",
                    headerAction: AnyView(
                        Button("Add app\u{2026}") {
                            showAppPicker = true
                        }
                        .buttonStyle(RMPrimaryButtonStyle())
                    ),
                    bodyPadding: 0
                ) {
                    let rules = settings.perAppRules.sorted(by: { $0.key < $1.key })
                    if rules.isEmpty {
                        Text("No per-app rules configured.")
                            .font(.rmSecondary)
                            .foregroundColor(.rmTextSecondary)
                            .padding(RMSpacing.card)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(rules.enumerated()), id: \.element.key) { index, item in
                                PerAppRuleRow(
                                    bundleID: item.key,
                                    rule: item.value,
                                    installedApps: installedApps,
                                    isLast: index == rules.count - 1
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Add section (app picker)
                if showAppPicker {
                    RMCard(title: "Add Application", bodyPadding: RMSpacing.card) {
                        VStack(spacing: 8) {
                            HStack {
                                Button("Browse\u{2026}") { browseForApp() }
                                    .buttonStyle(RMDefaultButtonStyle())
                                Spacer()
                                Button("Done") {
                                    showAppPicker = false
                                    searchText = ""
                                }
                                .buttonStyle(RMDefaultButtonStyle())
                            }

                            TextField("Search apps\u{2026}", text: $searchText)
                                .textFieldStyle(.roundedBorder)

                            let filtered = filteredInstalledApps
                            if filtered.isEmpty {
                                Text("No apps found.")
                                    .font(.rmCaption)
                                    .foregroundColor(.rmTextSecondary)
                                    .padding(.vertical, 4)
                            } else {
                                ScrollView {
                                    LazyVStack(spacing: 2) {
                                        ForEach(filtered) { app in
                                            Button { addApp(app) } label: {
                                                HStack(spacing: 8) {
                                                    if let icon = app.icon {
                                                        Image(nsImage: icon)
                                                            .resizable()
                                                            .frame(width: 20, height: 20)
                                                    }
                                                    Text(app.name)
                                                        .font(.rmBody)
                                                        .foregroundColor(.rmTextPrimary)
                                                    Spacer()
                                                    if settings.perAppRules.keys.contains(app.id) {
                                                        Image(systemName: "checkmark")
                                                            .foregroundColor(.rmAccent)
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
                                                    .fill(Color.rmTextPrimary.opacity(0.05))
                                            )
                                        }
                                    }
                                }
                                .frame(height: min(CGFloat(filtered.count) * 30, 200))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .onAppear { refreshInstalledApps() }
    }

    // MARK: - Helpers

    private var filteredInstalledApps: [AppInfo] {
        let available = installedApps.filter { !settings.perAppRules.keys.contains($0.id) }
        if searchText.isEmpty { return available }
        let query = searchText.lowercased()
        return available.filter { $0.name.lowercased().contains(query) }
    }

    private func addApp(_ app: AppInfo) {
        settings.perAppRules[app.id] = AppSettings.PerAppRule(presetID: settings.defaultPreset, reason: nil)
        // Keep old format in sync for backward compat
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

        settings.perAppRules[bundleID] = AppSettings.PerAppRule(presetID: settings.defaultPreset, reason: nil)
        settings.perAppPresets[bundleID] = settings.defaultPreset

        if !installedApps.contains(where: { $0.id == bundleID }) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            installedApps.append(AppInfo(id: bundleID, name: name, icon: icon, path: url.path))
            installedApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
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
}

// MARK: - Per-App Rule Row

struct PerAppRuleRow: View {
    let bundleID: String
    let rule: AppSettings.PerAppRule
    let installedApps: [AppInfo]
    var isLast: Bool = false

    @ObservedObject private var settings = AppSettings.shared

    private var appName: String {
        if let app = installedApps.first(where: { $0.id == bundleID }) {
            return app.name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID.components(separatedBy: ".").last ?? bundleID
    }

    private var appIcon: NSImage? {
        if let app = installedApps.first(where: { $0.id == bundleID }), let icon = app.icon {
            return icon
        }
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: RMSpacing.lg) {
                // App icon
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.rmSurface2)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "app")
                                .font(.system(size: 13))
                                .foregroundColor(.rmTextTertiary)
                        )
                }

                // Name + reason
                VStack(alignment: .leading, spacing: 2) {
                    Text(appName)
                        .font(.system(size: 13, weight: .medium))
                        .tracking(-0.05)
                        .foregroundColor(.rmTextPrimary)
                    if let reason = rule.reason, !reason.isEmpty {
                        Text(reason)
                            .font(.system(size: 11.5))
                            .italic()
                            .foregroundColor(.rmTextTertiary)
                    }
                }

                Spacer()

                // USES label + preset chip
                HStack(spacing: 6) {
                    Text("USES")
                        .font(.rmMono(size: 10.5, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(.rmTextTertiary)

                    let presetName = PresetRegistry.availablePresets.first(where: { $0.id == rule.presetID })?.displayName ?? rule.presetID
                    if rule.presetID.isEmpty {
                        RMChip(text: "None \u{2014} overlay off", tone: .neutral, showDot: false)
                    } else {
                        RMChip(text: presetName, tone: .info, showDot: false)
                    }
                }

                // Delete button
                Button {
                    settings.perAppRules.removeValue(forKey: bundleID)
                    settings.perAppPresets.removeValue(forKey: bundleID)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundColor(.rmTextTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, RMSpacing.card)

            if !isLast {
                Rectangle()
                    .fill(Color.rmDivider)
                    .frame(height: 1)
                    .padding(.horizontal, RMSpacing.card)
            }
        }
    }
}

// MARK: - Hotkey Recorder (kept)

struct HotkeyRecorderView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text("Toggle Overlay")
            Spacer()
            Button(action: { isRecording.toggle() }) {
                Text(isRecording ? "Press keys\u{2026}" : settings.hotkeyDisplayString)
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
    private var windowDelegate: SettingsWindowDelegate?
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
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "RetroMac Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        let delegate = SettingsWindowDelegate(controller: self)
        self.windowDelegate = delegate
        window.delegate = delegate
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        installEditMenu()
    }

    /// Install a standard Edit menu so Cmd+C/V/A work in TextFields
    func installEditMenu() {
        if NSApp.mainMenu != nil { return }

        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = NSMenu()
        mainMenu.addItem(appMenuItem)

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

private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    weak var controller: SettingsWindowController?

    init(controller: SettingsWindowController) {
        self.controller = controller
    }

    func windowWillClose(_ notification: Notification) {
        controller?.removeEditMenu()
    }
}
