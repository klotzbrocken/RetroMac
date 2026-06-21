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
    @Published var activeTheme: String = ""
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
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            themeStrip
            effects
            Divider()
            powerRow
        }
        .padding(16)
        .frame(width: 380)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("RetroMac").font(.system(size: 14, weight: .bold))
                Text(model.activeTheme.isEmpty ? "No theme" : model.activeTheme)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private var themeStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THEMES").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                // "Off" — deactivate the theme (clean desktop). Active when no theme is on.
                Button { AppDelegate.shared?.launcherDisableTheme(); model.refresh() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "power")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(model.activeTheme.isEmpty ? Color.accentColor : .secondary)
                            .frame(width: 48, height: 48)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(model.activeTheme.isEmpty ? Color.accentColor : .white.opacity(0.15),
                                              lineWidth: model.activeTheme.isEmpty ? 2 : 1))
                        Text("Off").font(.system(size: 9))
                            .foregroundStyle(model.activeTheme.isEmpty ? Color.accentColor : .secondary)
                    }
                }.buttonStyle(.plain)
                ForEach(model.specialThemes) { t in
                    Button { AppDelegate.shared?.launcherActivateTheme(t.name); model.refresh() } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                if let img = t.icon {
                                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(4)
                                } else {
                                    Image(systemName: "square.dashed")
                                        .font(.system(size: 20)).foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 48, height: 48)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(t.name == model.activeTheme ? Color.accentColor : .white.opacity(0.15),
                                              lineWidth: t.name == model.activeTheme ? 2 : 1))
                            Text(t.name).font(.system(size: 9)).lineLimit(1)
                                .foregroundStyle(t.name == model.activeTheme ? Color.accentColor : .secondary)
                        }
                    }.buttonStyle(.plain)
                }
                // "More" — the non-special themes, as a dropdown next to the last grid icon.
                if !model.otherThemes.isEmpty {
                    let moreActive = model.otherThemes.contains { $0.name == model.activeTheme }
                    Menu {
                        ForEach(model.otherThemes) { t in
                            Button(t.name) { AppDelegate.shared?.launcherActivateTheme(t.name); model.refresh() }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(moreActive ? Color.accentColor : .secondary)
                                .frame(width: 48, height: 48)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(moreActive ? Color.accentColor : .white.opacity(0.15),
                                                  lineWidth: moreActive ? 2 : 1))
                            Text(moreActive ? model.activeTheme : "More")
                                .font(.system(size: 9)).lineLimit(1)
                                .foregroundStyle(moreActive ? Color.accentColor : .secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var effects: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EFFECTS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Toggle(isOn: Binding(get: { model.shaderActive },
                                     set: { _ in AppDelegate.shared?.launcherToggleShader(); model.refresh() })) {
                    Label("CRT Shader", systemImage: "tv")
                }.frame(maxWidth: .infinity, alignment: .leading)
                Toggle(isOn: Binding(get: { model.webcamRunning },
                                     set: { _ in AppDelegate.shared?.launcherToggleWebcam(); model.refresh() })) {
                    Label("Virtual Camera", systemImage: "camera")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            shaderPicker
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
