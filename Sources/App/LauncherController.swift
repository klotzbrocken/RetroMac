import AppKit
import SwiftUI

/// Dock Mode launcher: a slim, popover-styled borderless panel shown just above the Dock
/// when the user left-clicks RetroMac's Dock icon. Quick access to themes, effect toggles,
/// the active theme's apps, and Settings/Quit. Closes on outside click or Esc.
/// Borderless launcher window that can still become key (so its controls take keyboard
/// focus) and closes on Escape. A plain borderless NSWindow returns false for canBecomeKey.
private final class LauncherWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

final class LauncherController {
    static let shared = LauncherController()

    private var panel: NSPanel?
    private var window: NSWindow?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var isOpen: Bool { panel?.isVisible == true }
    var isWindowOpen: Bool { window?.isVisible == true }

    func toggle() { isOpen ? close() : open() }
    func toggle(anchorRect: NSRect?) { isOpen ? close() : open(anchorRect: anchorRect) }
    func toggleWindow() { isWindowOpen ? closeWindow() : openWindow() }

    /// Open the popover. When `anchorRect` (screen coords, e.g. the floating button's frame)
    /// is given, the popover hangs next to it instead of centring above the Dock.
    func open(anchorRect: NSRect? = nil) {
        if panel == nil { buildPanel() }
        guard let panel = panel else { return }
        if let rect = anchorRect { position(panel, near: rect) } else { position(panel) }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installDismissMonitors()
    }

    func close() {
        removeDismissMonitors()
        panel?.orderOut(nil)
    }

    // MARK: - Window mode (Dock Mode: a real, movable, persistent window)

    func openWindow() {
        if window == nil { buildWindow() }
        guard let window = window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() { window?.orderOut(nil) }

    private func buildWindow() {
        let host = NSHostingView(rootView: LauncherView { [weak self] in self?.closeWindow() })
        host.setFrameSize(host.fittingSize)
        let w = LauncherWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                               styleMask: [.borderless, .fullSizeContentView],
                               backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isMovableByWindowBackground = true   // drag the card anywhere to move it
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.onCancel = { [weak self] in self?.closeWindow() }   // Esc closes the window
        w.contentView = host
        // Restore the remembered position; first ever launch → sit just above the Dock.
        if !w.setFrameUsingName("RetroMacLauncherWindow") {
            if let vf = NSScreen.main?.visibleFrame {
                w.setFrameOrigin(NSPoint(x: vf.midX - w.frame.width / 2, y: vf.minY + 12))
            } else { w.center() }
        }
        w.setFrameAutosaveName("RetroMacLauncherWindow")
        window = w
    }

    private func buildPanel() {
        let host = NSHostingView(rootView: LauncherView { [weak self] in self?.close() })
        host.setFrameSize(host.fittingSize)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.contentView = host
        p.worksWhenModal = true
        panel = p
    }

    /// Centre the panel horizontally, sitting just above the Dock (visibleFrame.minY).
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        if let host = panel.contentView { panel.setContentSize(host.fittingSize) }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        let x = vf.midX - size.width / 2
        let y = vf.minY + 12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Position the popover hanging next to `rect` (the floating button): above it and
    /// right-aligned, flipping below if there's no room, clamped to the visible frame.
    private func position(_ panel: NSPanel, near rect: NSRect) {
        if let host = panel.contentView { panel.setContentSize(host.fittingSize) }
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { position(panel); return }
        var x = rect.maxX - size.width          // right edges aligned
        var y = rect.maxY + 8                    // hang above the button
        if y + size.height > vf.maxY { y = rect.minY - 8 - size.height }   // no room above → below
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        y = min(max(y, vf.minY + 8), vf.maxY - size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self = self, let panel = self.panel else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.close(); return nil }   // Esc
                return event
            }
            // Click outside the panel → dismiss. Clicks on the floating button are left to
            // the button itself (so it can toggle the popover closed).
            if event.window !== panel && event.window !== FloatingLauncherButton.shared.buttonWindow {
                self.close()
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }
}

// MARK: - Model

/// Publishes the live state the launcher renders, refreshed on the relevant notifications.
final class LauncherModel: ObservableObject {
    struct ThemeItem: Identifiable { let id = UUID(); let name: String; let icon: NSImage? }
    struct PresetGroup: Identifiable { let id = UUID(); let title: String; let items: [(id: String, name: String)] }

    @Published var specialThemes: [ThemeItem] = []
    @Published var otherThemes: [ThemeItem] = []
    @Published var allThemes: [ThemeItem] = []
    @Published var activeTheme: String = ""

    func icon(for name: String) -> NSImage? { allThemes.first { $0.name == name }?.icon }
    @Published var shaderActive = false
    @Published var webcamRunning = false
    @Published var tubeActive = false
    @Published var currentPreset: String = ""

    let presetGroups: [PresetGroup] = PresetRegistry.categorizedPresets.map { cat, infos in
        PresetGroup(title: cat.rawValue, items: infos.map { ($0.id, $0.displayName) })
    }

    /// Special themes (full retro chrome/widgets) shown in the grid; the rest go in a dropdown.
    static func isSpecial(_ name: String) -> Bool {
        let tn = name.lowercased()
        return tn.contains("windows xp") || tn.contains("windows 98")
            || (tn.contains("mac os 9") && tn.contains("classic"))
            || (tn.contains("beos") && tn.contains("classic"))
            || tn.contains("maiks favourite") || tn == "mac os x"
            || tn.contains("snow leopard")
    }

    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .dockThemeChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        observers.append(nc.addObserver(forName: .virtualCameraStateChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        // Shader/preset state can settle asynchronously (full overlay starts on a Task);
        // update the toggle + preset dropdown when it does, without a full theme reload.
        observers.append(nc.addObserver(forName: .overlayStateChanged, object: nil, queue: .main) { [weak self] _ in self?.refreshState() })
        observers.append(nc.addObserver(forName: .tubeModeChanged, object: nil, queue: .main) { [weak self] _ in self?.refreshState() })
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    func refresh() {
        let mgr = ThemeManager.shared
        let all = mgr.availableThemes.map { t -> ThemeItem in
            let img = t.themeIconURL().flatMap { NSImage(contentsOf: $0) }
            return ThemeItem(name: t.config.name, icon: img)
        }
        allThemes = all
        specialThemes = all.filter { Self.isSpecial($0.name) }
        otherThemes = all.filter { !Self.isSpecial($0.name) }
        // Only mark a theme active when one is actually ON. ThemeManager keeps the
        // last theme in memory even when dockEnabled is false, which would otherwise
        // mark a tile active when nothing is applied.
        activeTheme = AppSettings.shared.dockEnabled ? (mgr.activeTheme?.config.name ?? "") : ""
        refreshState()
    }

    /// Lightweight update of the transient shader/camera state (no theme/disk reload).
    /// Driven by .overlayStateChanged so the toggle + preset dropdown reflect the real
    /// state even after the full overlay finishes starting asynchronously.
    func refreshState() {
        shaderActive = AppDelegate.shared?.launcherShaderActive ?? false
        webcamRunning = VirtualCameraManager.shared.isRunning
        tubeActive = TubeModeController.shared.isActive
        currentPreset = AppDelegate.shared?.launcherCurrentPreset ?? ""
    }
}

// MARK: - View

struct LauncherView: View {
    @StateObject private var model = LauncherModel()
    @ObservedObject private var settings = AppSettings.shared
    @State private var editMode = false
    @State private var changingSlot: Int? = nil
    var onClose: () -> Void

    private let accentBlue = Color(red: 0.039, green: 0.478, blue: 1.0)    // #0a7aff
    private let destructive = Color(red: 1.0, green: 0.231, blue: 0.188)   // #ff3b30
    private let switchGreen = Color(red: 0.204, green: 0.780, blue: 0.349) // #34c759

    /// Menu-bar Apple icons for the flyout cycle (colored = on, desaturated = off).
    private static func bundledIcon(_ name: String) -> NSImage {
        if let p = Bundle.main.path(forResource: name, ofType: "png"),
           let img = NSImage(contentsOfFile: p) { return img }
        return NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil) ?? NSImage()
    }
    private static let rainbowAppleIcon: NSImage = bundledIcon("rainbow_apple")
    private static let aquaAppleIcon: NSImage = bundledIcon("aqua_apple")
    private static let aquaClassicAppleIcon: NSImage = bundledIcon("aqua_classic_apple")
    private static let hellAppleIcon: NSImage = bundledIcon("apple_hell")

    private static func appleIcon(forStyle style: Int) -> NSImage {
        switch style {
        case 2: return aquaAppleIcon
        case 3: return aquaClassicAppleIcon
        case 4: return hellAppleIcon
        default: return rainbowAppleIcon
        }
    }
    private static func appleStyleName(_ style: Int) -> String {
        switch style {
        case 1: return "Rainbow"
        case 2: return "Aqua"
        case 3: return "Aqua Classic"
        case 4: return "Apple Hell"
        default: return "Off"
        }
    }

    /// Exactly 8 slot entries ("" = empty).
    private var slots: [String] {
        var s = settings.quickAccessSlots
        if s.count < 8 { s += Array(repeating: "", count: 8 - s.count) }
        return Array(s.prefix(8))
    }

    var body: some View {
        Group {
            if changingSlot != nil { themePicker } else { mainContent }
        }
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.15)))
        .onAppear { prefillSlotsIfNeeded() }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            quickAccess
            dockOnlyRow
            effects
            Divider()
            powerRow
        }
        .padding(16)
    }

    /// In-panel theme picker (stays inside the panel so the dismiss monitors don't close
    /// the flyout, and scrolls so the full theme list is reachable).
    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { changingSlot = nil } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                }.buttonStyle(.plain)
                Text("Choose a theme").font(.system(size: 13, weight: .bold))
                Spacer()
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    ForEach(model.allThemes) { t in
                        Button {
                            if let s = changingSlot { setSlot(s, t.name) }
                            changingSlot = nil
                        } label: { pickerTile(t) }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 280)
        }
        .padding(16)
    }

    private func pickerTile(_ t: LauncherModel.ThemeItem) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if let img = t.icon {
                    Image(nsImage: img).resizable().scaledToFit().frame(width: 48, height: 36)
                } else {
                    Image(systemName: "square.dashed").font(.system(size: 18)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 44).clipped()
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.15)))
            Text(t.name).font(.system(size: 9)).lineLimit(2).multilineTextAlignment(.center)
                .foregroundStyle(.secondary).frame(width: 64, height: 24)
        }
        .frame(width: 64, height: 74)
    }

    // MARK: - Slot helpers

    private func prefillSlotsIfNeeded() {
        guard settings.quickAccessSlots.allSatisfy({ $0.isEmpty }) else { return }
        let starter = model.specialThemes.map { $0.name } + model.otherThemes.map { $0.name }
        var s = Array(starter.prefix(8))
        if s.count < 8 { s += Array(repeating: "", count: 8 - s.count) }
        settings.quickAccessSlots = s
    }

    private func setSlot(_ index: Int, _ name: String) {
        var s = slots
        s[index] = name
        settings.quickAccessSlots = s
    }

    /// Tap a slot: activate its theme, or deactivate if it's already active.
    private func tapSlot(_ name: String) {
        if name == model.activeTheme {
            AppDelegate.shared?.launcherDisableTheme()
        } else {
            AppDelegate.shared?.launcherActivateTheme(name)
        }
        model.refresh()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Group {
                if let icon = (NSApp.delegate as? AppDelegate)?.menuBarIconImage(size: NSSize(width: 18, height: 18)) {
                    Image(nsImage: icon).renderingMode(.template).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "sparkles.tv").font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            Text("RetroMac").font(.system(size: 14, weight: .bold))
            Spacer()
        }
    }

    private var quickAccess: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("QUICK ACCESS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(editMode ? "Done" : "Edit") {
                    editMode.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accentBlue)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                ForEach(0..<8, id: \.self) { i in slotView(i) }
            }
        }
    }

    @ViewBuilder
    private func slotView(_ i: Int) -> some View {
        let name = slots[i]
        if name.isEmpty {
            Button { changingSlot = i } label: { emptyTile }
                .buttonStyle(.plain)
        } else {
            let active = name == model.activeTheme
            ZStack(alignment: .topLeading) {
                Button {
                    if editMode { changingSlot = i } else { tapSlot(name) }
                } label: { filledTile(name, active: active) }
                .buttonStyle(.plain)

                if editMode {
                    Button { setSlot(i, "") } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 15)).foregroundStyle(destructive)
                            .background(Circle().fill(.white).frame(width: 13, height: 13))
                    }
                    .buttonStyle(.plain).offset(x: -5, y: -5)
                }
            }
        }
    }

    private func filledTile(_ name: String, active: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if let img = model.icon(for: name) {
                    Image(nsImage: img).resizable().scaledToFit().frame(width: 48, height: 36)
                } else {
                    Image(systemName: "square.dashed").font(.system(size: 18)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 44)
            .clipped()
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(active ? accentBlue : .white.opacity(0.15), lineWidth: active ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13)).foregroundStyle(accentBlue)
                        .background(Circle().fill(.white).frame(width: 11, height: 11))
                        .offset(x: 5, y: -5)
                }
            }
            Text(name).font(.system(size: 9)).lineLimit(2).multilineTextAlignment(.center)
                .foregroundStyle(active ? accentBlue : .secondary)
                .frame(width: 64, height: 24)
        }
        .frame(width: 64, height: 74)
    }

    private var emptyTile: some View {
        VStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 56, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary.opacity(0.5)))
            Text("Add").font(.system(size: 9)).foregroundStyle(.secondary).frame(height: 24)
        }
        .frame(width: 64, height: 74)
    }

    private var dockOnlyRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Dock only").font(.system(size: 12))
                Text("Restyle the Dock, not the whole system")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $settings.dockOnly)
                .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(switchGreen)
                .onChange(of: settings.dockOnly) { _, _ in
                    AppDelegate.shared?.refreshDockOnlyScope()
                }
        }
    }

    private var effects: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EFFECTS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            HStack {
                Label("CRT Shader", systemImage: "tv")
                Spacer()
                Toggle("", isOn: Binding(get: { model.shaderActive },
                                         set: { _ in AppDelegate.shared?.launcherToggleShader(); model.refresh() }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(switchGreen)
            }

            if model.shaderActive {
                shaderPicker.padding(.leading, 22)
            }

            HStack {
                Label("Virtual Camera", systemImage: "camera")
                Spacer()
                Toggle("", isOn: Binding(get: { model.webcamRunning },
                                         set: { _ in AppDelegate.shared?.launcherToggleWebcam(); model.refresh() }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(switchGreen)
            }

            HStack {
                Label("TV Tube", systemImage: "sparkles.tv")
                Spacer()
                Toggle("", isOn: Binding(get: { model.tubeActive },
                                         set: { _ in AppDelegate.shared?.toggleTubeMode(); model.refreshState() }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(switchGreen)
            }

            appleCycleRow
        }
        .font(.system(size: 12))
    }

    /// Menu-bar Apple cover — theme-independent. Each tap cycles Off → Rainbow → Aqua.
    /// Icon shows the current style; grey = off.
    private var appleCycleRow: some View {
        let style = settings.menuBarAppleStyle
        return HStack(spacing: 8) {
            Image(nsImage: Self.appleIcon(forStyle: style))
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: 16, height: 16)
                .saturation(style == 0 ? 0 : 1)
                .opacity(style == 0 ? 0.4 : 1)
            Text("Apple logo: " + Self.appleStyleName(style))
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { settings.menuBarAppleStyle = (settings.menuBarAppleStyle + 1) % 5 }
    }

    private var shaderPicker: some View {
        Picker(selection: Binding(get: { model.currentPreset },
                                  set: { AppDelegate.shared?.launcherSelectPreset($0); model.refresh() })) {
            ForEach(model.presetGroups) { group in
                Section(group.title) {
                    ForEach(group.items, id: \.id) { item in
                        Text(item.name).tag(item.id)
                    }
                }
            }
        } label: { Text("Shader") }
        .font(.system(size: 12))
    }

    private var powerRow: some View {
        HStack(spacing: 10) {
            Button { AppDelegate.shared?.launcherOpenSettings(); onClose() } label: {
                Image(systemName: "gearshape").foregroundStyle(.secondary)
            }
            .help("Settings")
            .accessibilityLabel("Settings")
            Spacer()
            Button(role: .destructive) { NSApp.terminate(nil) } label: {
                Image(systemName: "power").foregroundStyle(destructive)
            }
            .help("Quit")
            .accessibilityLabel("Quit")
        }
        .font(.system(size: 15, weight: .medium))
        .buttonStyle(.plain)
    }
}
