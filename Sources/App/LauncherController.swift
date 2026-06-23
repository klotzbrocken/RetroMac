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
    }

    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .dockThemeChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        observers.append(nc.addObserver(forName: .virtualCameraStateChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
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
        activeTheme = mgr.activeTheme?.config.name ?? ""
        shaderActive = AppDelegate.shared?.launcherShaderActive ?? false
        webcamRunning = VirtualCameraManager.shared.isRunning
        currentPreset = AppDelegate.shared?.launcherCurrentPreset ?? ""
    }
}

// MARK: - View

struct LauncherView: View {
    @StateObject private var model = LauncherModel()
    @ObservedObject private var settings = AppSettings.shared
    @State private var editMode = false
    @State private var wobble = false
    var onClose: () -> Void

    private let accentBlue = Color(red: 0.039, green: 0.478, blue: 1.0)    // #0a7aff
    private let destructive = Color(red: 1.0, green: 0.231, blue: 0.188)   // #ff3b30
    private let switchGreen = Color(red: 0.204, green: 0.780, blue: 0.349) // #34c759

    /// Exactly 8 slot entries ("" = empty).
    private var slots: [String] {
        var s = settings.quickAccessSlots
        if s.count < 8 { s += Array(repeating: "", count: 8 - s.count) }
        return Array(s.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            quickAccess
            dockOnlyRow
            effects
            Divider()
            powerRow
        }
        .padding(16)
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.15)))
        .onAppear { prefillSlotsIfNeeded() }
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
            VStack(alignment: .leading, spacing: 2) {
                Text("RetroMac").font(.system(size: 14, weight: .bold))
                HStack(spacing: 5) {
                    Circle().fill(model.activeTheme.isEmpty ? Color.secondary : switchGreen)
                        .frame(width: 6, height: 6)
                    Text(model.activeTheme.isEmpty ? "No theme" : model.activeTheme)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private var quickAccess: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("QUICK ACCESS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(editMode ? "Done" : "Edit") {
                    withAnimation(.easeInOut(duration: 0.15)) { editMode.toggle(); wobble = editMode }
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
            Menu {
                ForEach(model.allThemes) { t in Button(t.name) { setSlot(i, t.name) } }
            } label: { emptyTile }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).buttonStyle(.plain)
        } else {
            let active = name == model.activeTheme
            ZStack(alignment: .topLeading) {
                if editMode {
                    Menu {
                        ForEach(model.allThemes) { t in Button(t.name) { setSlot(i, t.name) } }
                    } label: { filledTile(name, active: active) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).buttonStyle(.plain)

                    Button { setSlot(i, "") } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 15)).foregroundStyle(destructive)
                            .background(Circle().fill(.white).frame(width: 13, height: 13))
                    }
                    .buttonStyle(.plain).offset(x: -5, y: -5)
                } else {
                    Button { tapSlot(name) } label: { filledTile(name, active: active) }
                        .buttonStyle(.plain)
                }
            }
            .rotationEffect(.degrees(editMode ? (wobble ? 1.5 : -1.5) : 0))
            .animation(editMode ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true) : .default, value: wobble)
        }
    }

    private func filledTile(_ name: String, active: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if let img = model.icon(for: name) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(4)
                } else {
                    Image(systemName: "square.dashed").font(.system(size: 18)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 44)
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
                .frame(height: 24)
        }
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
    }

    private var dockOnlyRow: some View {
        Toggle(isOn: $settings.dockOnly) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Dock only").font(.system(size: 12))
                Text("Restyle the Dock, not the whole system")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch).tint(switchGreen)
    }

    private var effects: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EFFECTS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Toggle(isOn: Binding(get: { model.shaderActive },
                                 set: { _ in AppDelegate.shared?.launcherToggleShader(); model.refresh() })) {
                Label("CRT Shader", systemImage: "tv")
            }
            .toggleStyle(.switch).tint(switchGreen)

            if model.shaderActive {
                shaderPicker.padding(.leading, 22)
            }

            Toggle(isOn: Binding(get: { model.webcamRunning },
                                 set: { _ in AppDelegate.shared?.launcherToggleWebcam(); model.refresh() })) {
                Label("Virtual Camera", systemImage: "camera")
            }
            .toggleStyle(.switch).tint(switchGreen)
        }
        .font(.system(size: 12))
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
                Label("Settings", systemImage: "gearshape")
            }
            Spacer()
            Button(role: .destructive) { NSApp.terminate(nil) } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .buttonStyle(.plain)
    }
}
