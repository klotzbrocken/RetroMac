import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
        closeWindow()   // one launcher at a time: the Dock icon's window gives way to the popover
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
        close()   // ...and the floating button's popover to the Dock icon's window
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
    struct ThemeItem: Identifiable { let id = UUID(); let name: String; let icon: NSImage?; var tab = "Various" }
    struct PresetGroup: Identifiable { let id = UUID(); let title: String; let items: [(id: String, name: String)] }

    @Published var specialThemes: [ThemeItem] = []
    @Published var otherThemes: [ThemeItem] = []
    @Published var allThemes: [ThemeItem] = []
    @Published var activeTheme: String = ""

    func icon(for name: String) -> NSImage? { allThemes.first { $0.name == name }?.icon }
    @Published var shaderActive = false
    @Published var wallpaperOnlyActive = false
    @Published var webcamRunning = false
    @Published var currentPreset: String = ""

    let presetGroups: [PresetGroup] = PresetRegistry.categorizedPresets.map { cat, infos in
        PresetGroup(title: cat.rawValue, items: infos.map { ($0.id, $0.displayName) })
    }

    /// Special themes (full retro chrome/widgets) shown in the grid; the rest go in a dropdown.
    static func isSpecial(_ name: String) -> Bool {
        let tn = name.lowercased()
        return tn.contains("windows xp") || tn.contains("windows 98") || tn.contains("windows 95") || tn.contains("windows me") || tn.contains("windows nt")
            || (tn.contains("mac os 9") && tn.contains("classic"))
            || (tn.contains("beos") && tn.contains("classic"))
            || tn.contains("maiks favourite") || tn == "mac os x"
            || tn.contains("snow leopard")
    }

    private var observers: [NSObjectProtocol] = []

    /// A theme's icon made once at the tiles' size, 36 points at twice the pixels, with
    /// Core Graphics' best filter. Left to SwiftUI, a 128-pixel picture drawn at 36 points
    /// lost its fine detail (fur, stripes, a checkerboard) to a cheap filter and looked grainy.
    static func tileImage(_ img: NSImage) -> NSImage {
        let px = 72
        var r = NSRect(origin: .zero, size: img.size)
        guard let cg = img.cgImage(forProposedRect: &r, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
        ctx.interpolationQuality = .high
        let s = min(CGFloat(px) / CGFloat(cg.width), CGFloat(px) / CGFloat(cg.height))
        let w = CGFloat(cg.width) * s, h = CGFloat(cg.height) * s
        ctx.draw(cg, in: CGRect(x: (CGFloat(px) - w) / 2, y: (CGFloat(px) - h) / 2, width: w, height: h))
        guard let out = ctx.makeImage() else { return img }
        return NSImage(cgImage: out, size: NSSize(width: 36, height: 36))
    }

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
        // Youngest era first, as the menu bar's Themes menu lists them.
        let all = ThemeManager.byAge(mgr.availableThemes).map { t -> ThemeItem in
            let img = t.themeIconURL().flatMap { NSImage(contentsOf: $0) }.map(Self.tileImage)
            return ThemeItem(name: t.config.name, icon: img, tab: ThemeManager.quickAccessTab(of: t))
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
        wallpaperOnlyActive = AppDelegate.shared?.launcherLiveWallpaperActive ?? false
        webcamRunning = VirtualCameraManager.shared.isRunning
        currentPreset = AppDelegate.shared?.launcherCurrentPreset ?? ""
    }
}

// MARK: - View

struct LauncherView: View {
    @StateObject private var model = LauncherModel()
    @ObservedObject private var settings = AppSettings.shared
    @State private var editMode = false
    @State private var changingSlot: Int? = nil
    @State private var draggingSlot: Int? = nil
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
    private static let pumpkinAppleIcon = RainbowAppleController.pumpkin()

    /// Futurama style 5 has no bundled PNG — it's the drawn teal apple. Render a small teal
    /// `apple.logo` silhouette for the flyout row so it can be picked like the others.
    private static let futuramaAppleIcon: NSImage = {
        let teal = NSColor(srgbRed: 0.13, green: 0.46, blue: 0.41, alpha: 1)
        let cfg = NSImage.SymbolConfiguration(pointSize: 64, weight: .black)
        guard let sym = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else { return NSImage() }
        let size = sym.size
        let img = NSImage(size: size)
        img.lockFocus()
        teal.setFill(); NSRect(origin: .zero, size: size).fill()
        sym.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .destinationIn, fraction: 1)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }()

    private static func appleIcon(forStyle style: Int) -> NSImage {
        switch style {
        case 2: return aquaAppleIcon
        case 3: return aquaClassicAppleIcon
        case 4: return hellAppleIcon
        case 5: return futuramaAppleIcon
        case 7: return pumpkinAppleIcon
        default: return rainbowAppleIcon
        }
    }
    private static func appleStyleName(_ style: Int) -> String {
        switch style {
        case 1: return "Rainbow"
        case 2: return "Aqua"
        case 3: return "Aqua Classic"
        case 4: return "Apple Hell"
        case 5: return "Futurama"
        case 6: return "Black"
        case 7: return "Pumpkin"
        default: return "Off"
        }
    }

    static let tabs = ["Apple", "Windows", "Various"]
    private var tab: String { Self.tabs.contains(settings.quickAccessTab) ? settings.quickAccessTab : "Apple" }

    /// Exactly 8 slot entries ("" = empty) of the tab on show.
    private var slots: [String] {
        var s = settings.quickAccessTabs[tab] ?? []
        if s.count < 8 { s += Array(repeating: "", count: 8 - s.count) }
        return Array(s.prefix(8))
    }

    private func store(_ s: [String]) { settings.quickAccessTabs[tab] = Array(s.prefix(8)) }

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
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).accessibilityLabel("Back")
                }.buttonStyle(.plain)
                Text("Choose a theme").font(.system(size: 13, weight: .bold))
                Spacer()
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    ForEach(model.allThemes.filter { $0.tab == tab }) { t in
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
                    Image(nsImage: img).resizable().interpolation(.high).antialiased(true).scaledToFit().frame(width: 48, height: 36)
                } else {
                    Image(systemName: "square.dashed").font(.system(size: 18)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 44).clipped()
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.15)))
            Text(ThemeManager.displayName(for: t.name)).font(.system(size: 9)).lineLimit(2).multilineTextAlignment(.center)
                .foregroundStyle(.secondary).frame(width: 64, height: 24)
        }
        .frame(width: 64, height: 74)
    }

    // MARK: - Slot helpers

    /// First open with tabs: the eight slots the flyout had go to their family's tab, then each
    /// tab fills up with the rest of its family, youngest era first.
    private func prefillSlotsIfNeeded() {
        guard settings.quickAccessTabs.isEmpty else { return }
        settings.quickAccessTabs = Self.sorted(previous: settings.quickAccessSlots, into: model.allThemes)
    }

    static func sorted(previous: [String], into themes: [LauncherModel.ThemeItem]) -> [String: [String]] {
        var tabs: [String: [String]] = [:]
        let byName = Dictionary(themes.map { ($0.name, $0.tab) }, uniquingKeysWith: { a, _ in a })
        for name in previous + themes.map(\.name) {
            guard let t = byName[name], tabs[t, default: []].count < 8, !tabs[t, default: []].contains(name) else { continue }
            tabs[t, default: []].append(name)
        }
        return tabs
    }

    private func setSlot(_ index: Int, _ name: String) {
        var s = slots
        s[index] = name
        store(s)
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
                    Image(nsImage: icon).renderingMode(.template).foregroundStyle(.secondary).accessibilityHidden(true)
                } else {
                    Image(systemName: "sparkles.tv").font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }
            Text("RetroMac").font(.system(size: 14, weight: .bold))
            Spacer()
            Button(editMode ? "Done" : "Edit Quick Access") { editMode.toggle() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accentBlue)
        }
    }

    private var quickAccess: some View {
        VStack(alignment: .leading, spacing: 8) {
            tabBar
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                ForEach(0..<8, id: \.self) { i in slotView(i) }
            }
        }
    }

    /// The three tabs as one quiet strip the width of the slot grid: a faint well, the chosen tab
    /// a raised pill in it. Colours from the system, so it reads in light and dark alike.
    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Self.tabs, id: \.self) { t in
                let on = t == tab
                Button { settings.quickAccessTab = t } label: {
                    Text(t)
                        .font(.system(size: 11, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? .primary : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick Access")
    }

    @ViewBuilder
    private func slotView(_ i: Int) -> some View {
        let name = slots[i]
        Group {
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
                                .background(Circle().fill(.white).frame(width: 13, height: 13)).accessibilityLabel("Remove")
                        }
                        .buttonStyle(.plain).offset(x: -5, y: -5)
                    }
                }
            }
        }
        // Edit mode: drag a slot onto another to reorder (empty slots are valid drop targets).
        .opacity(draggingSlot == i ? 0.35 : 1)
        .applyIf(editMode) { v in
            v.onDrop(of: [.text], isTargeted: nil) { _ in performSlotDrop(onto: i) }
        }
        .applyIf(editMode && !name.isEmpty) { v in
            v.onDrag {
                draggingSlot = i
                return NSItemProvider(object: String(i) as NSString)
            }
        }
    }

    /// Move the dragged slot to the drop target's position, keeping the fixed 8-slot layout.
    private func performSlotDrop(onto index: Int) -> Bool {
        defer { draggingSlot = nil }
        guard let from = draggingSlot, from != index else { return false }
        var s = slots
        let item = s.remove(at: from)
        let dest = from < index ? index - 1 : index
        s.insert(item, at: max(0, min(dest, s.count)))
        store(s)
        return true
    }

    private func filledTile(_ name: String, active: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if let img = model.icon(for: name) {
                    Image(nsImage: img).resizable().interpolation(.high).antialiased(true).scaledToFit().frame(width: 48, height: 36)
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
                        .offset(x: 5, y: -5).accessibilityHidden(true)
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
                    .foregroundStyle(.secondary.opacity(0.5))).accessibilityHidden(true)
            Text("Add").font(.system(size: 9)).foregroundStyle(.secondary).frame(height: 24)
        }
        .frame(width: 64, height: 74)
    }

    private var effects: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EFFECTS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            HStack {
                Label("CRT Shader", systemImage: "tv")
                Spacer()
                Toggle("", isOn: Binding(get: { model.shaderActive && !model.wallpaperOnlyActive },
                                         set: { _ in AppDelegate.shared?.launcherToggleShader(); model.refresh() }))
                    .toggleStyle(.switch).controlSize(.small).tint(switchGreen).accessibilityLabel("CRT Shader")
            }

            if model.shaderActive {
                shaderPicker.padding(.leading, 22)
            }

            // Live Wallpaper: run the filter on the wallpaper only (Pro). Replaces the former
            // Virtual Camera row here — the Virtual Camera entry stays in the menu-bar menu.
            HStack {
                Label("Live Wallpaper", systemImage: "photo.on.rectangle.angled")
                if !LicenseManager.shared.isLicensed {
                    Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary).accessibilityLabel("Pro")
                }
                Spacer()
                Toggle("", isOn: Binding(get: { model.wallpaperOnlyActive },
                                         set: { _ in AppDelegate.shared?.launcherToggleLiveWallpaper(); model.refresh() }))
                    .toggleStyle(.switch).controlSize(.small).tint(switchGreen).accessibilityLabel("Live Wallpaper")
            }

            // Crash Now: the Party-mode trigger where a demo can reach it in one click, without
            // opening Settings. Only offered when the active theme actually has a failure to
            // show, and locked like every other paid feature.
            if CrashEra.current() != nil {
                HStack {
                    Label("Crash Now", systemImage: "exclamationmark.triangle")
                    if !LicenseManager.shared.isLicensed {
                        Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary).accessibilityLabel("Pro")
                    }
                    Spacer()
                    Button("Crash") { AppDelegate.shared?.launcherCrashNow() }
                        .controlSize(.small)
                }
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
                .opacity(style == 0 ? 0.4 : 1).accessibilityHidden(true)
            Text("Apple logo: " + Self.appleStyleName(style))
            Spacer()
        }
        .contentShape(Rectangle())
        // Cycle through every style: Off → Rainbow → Aqua → Aqua Classic → Apple Hell →
        // Futurama → Black → Pumpkin → Off.
        .onTapGesture { settings.menuBarAppleStyle = (settings.menuBarAppleStyle + 1) % 8 }
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
                Image(systemName: "gearshape").foregroundStyle(.secondary).accessibilityLabel("Settings")
            }
            .help("Settings")
            .accessibilityLabel("Settings")
            Spacer()
            // Rescue Desktop, one click from the flyout (RET-01).
            Button { onClose(); AppDelegate.shared?.rescueDesktop() } label: {
                Label("Rescue Desktop", systemImage: "lifepreserver")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .help("Turn the theme and every effect off and bring back windows you cannot reach")
            Spacer()
            Button(role: .destructive) { AppDelegate.shared?.quitApp() } label: {
                Image(systemName: "power").foregroundStyle(destructive).accessibilityLabel("Quit RetroMac")
            }
            .help("Quit")
            .accessibilityLabel("Quit")
        }
        .font(.system(size: 15, weight: .medium))
        .buttonStyle(.plain)
    }
}

private extension View {
    /// Conditionally apply a modifier chain (keeps call sites readable for edit-mode-only drag/drop).
    @ViewBuilder func applyIf<V: View>(_ condition: Bool, _ transform: (Self) -> V) -> some View {
        if condition { transform(self) } else { self }
    }
}
