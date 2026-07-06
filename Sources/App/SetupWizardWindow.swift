import SwiftUI
import AppKit
import ScreenCaptureKit

/// Post-install configuration wizard. Walks the user through how RetroMac should behave.
/// Options are grouped onto a few pages (Appearance / System / Permissions) rather than
/// one-question-per-screen. Re-runnable any time from the menu or Settings ▸ Overview.
///
/// Toggles bind directly to AppSettings, so changes apply live via the existing `didSet`
/// side-effects (hide icons, hide menu bar, login item, dock mode, …).
private enum WizardPage: Int, CaseIterable {
    case intro
    case appearance
    case system
    case permissions
    case done
}

struct SetupWizardView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var page: WizardPage = .intro
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false
    @State private var reframeInstalled = SetupWizardView.isReframeInstalled()

    /// Called when the user finishes or skips the wizard.
    let onFinish: () -> Void

    private static let reframeURL = "https://myretromac.app/reframe"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .padding(.horizontal, 28)
                    .padding(.top, 26)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
        }
        .frame(width: 460, height: 500)
        .onAppear { refreshPermissions() }
    }

    // MARK: - Pages

    @ViewBuilder private var content: some View {
        switch page {
        case .intro:       introPage
        case .appearance:  appearancePage
        case .system:      systemPage
        case .permissions: permissionsPage
        case .done:        donePage
        }
    }

    private var introPage: some View {
        VStack(alignment: .center, spacing: 14) {
            Spacer(minLength: 12)
            Image(systemName: "wand.and.stars")
                .font(.system(size: 46)).foregroundStyle(.tint)
            Text("Welcome to RetroMac").font(.title.bold())
            Text("Let’s set up how RetroMac looks and behaves. Just a few choices — change any of them later in Settings, or re-run this assistant from the menu.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                introBullet("paintbrush", "Appearance — desktop, shader, menu bar, widgets")
                introBullet("gearshape.2", "System — Dock Mode, start at login, Reframe")
                introBullet("lock.shield", "Permissions — screen recording & accessibility")
            }
            .padding(.top, 6)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity)
    }

    private func introBullet(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.tint).frame(width: 20)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var appearancePage: some View {
        pageScaffold(icon: "paintbrush.fill", tint: .blue, title: "Appearance",
                     subtitle: "How a theme changes your desktop.") {
            toggleRow(icon: "menubar.dock.rectangle", tint: .blue,
                      title: "Hide original desktop icons",
                      subtitle: "Recommended — hides your real icons while a theme is on.",
                      isOn: $settings.hideDesktopIcons)
            Divider()
            toggleRow(icon: "tv.inset.filled", tint: .purple,
                      title: "Shader on theme change",
                      subtitle: "Turn on a theme’s CRT shader automatically.",
                      isOn: $settings.shaderOnThemeChange)
            Divider()
            toggleRow(icon: "menubar.rectangle", tint: .orange,
                      title: "Hide the macOS menu bar",
                      subtitle: "Show it again by moving the pointer to the top of the screen.",
                      isOn: $settings.hideMenuBar)
            Divider()
            toggleRow(icon: "square.grid.2x2", tint: .green,
                      title: "Also apply theme widgets",
                      subtitle: "On = Dock, Wallpaper & widgets (desktop Clock). Off = Dock & Wallpaper only.",
                      isOn: $settings.themeIncludeWidgets)
            Divider()
            toggleRow(icon: "paintpalette.fill", tint: .pink,
                      title: "Match colour scheme",
                      subtitle: "Set the macOS appearance & accent colour to fit the theme (e.g. Graphite). Your own settings are restored when the theme goes off.",
                      isOn: $settings.themeAdaptAppearance)
            Divider()
            toggleRow(icon: "cursorarrow.rays", tint: .indigo,
                      title: "Match cursor",
                      subtitle: "Replace the system-wide mouse cursor with the theme's set (classic Mac, XP, …). Your normal cursor returns afterwards.",
                      isOn: $settings.themeAdaptCursor)
        }
    }

    private var systemPage: some View {
        pageScaffold(icon: "gearshape.2.fill", tint: .cyan, title: "System",
                     subtitle: "How RetroMac runs on your Mac.") {
            toggleRow(icon: "dock.rectangle", tint: .cyan,
                      title: "Enable Dock Mode",
                      subtitle: "Adds a Dock icon with a quick launcher for themes, shader & camera.",
                      isOn: $settings.dockModeEnabled)
            Divider()
            toggleRow(icon: "power", tint: .pink,
                      title: "Start at login",
                      subtitle: "Launch RetroMac automatically when you log in.",
                      isOn: $settings.launchAtLogin)
            Divider()
            toggleRow(icon: "circle.dashed", tint: .teal,
                      title: "Floating launcher button",
                      subtitle: "Recommended — a small, draggable button (bottom-right) that opens the launcher.",
                      isOn: $settings.floatingLauncherEnabled)
            Divider()
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "globe").font(.system(size: 18)).foregroundStyle(.indigo).frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reframe browser").font(.headline)
                    Text("RetroMac’s companion retro web browser.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if reframeInstalled {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.green)
                } else {
                    Button("Install…") {
                        if let u = URL(string: Self.reframeURL) { NSWorkspace.shared.open(u) }
                        reframeInstalled = Self.isReframeInstalled()
                    }
                }
            }
        }
    }

    private var permissionsPage: some View {
        pageScaffold(icon: "lock.shield.fill", tint: .red, title: "Permissions",
                     subtitle: "RetroMac needs these to draw the shader and use hotkeys.") {
            permissionRow(name: "Screen Recording",
                          detail: "Required to draw the shader over your screen.",
                          granted: screenRecordingGranted,
                          pane: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            Divider()
            permissionRow(name: "Accessibility",
                          detail: "Required for global hotkeys and window control.",
                          granted: accessibilityGranted,
                          pane: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            Divider()
            Button("Re-check") { refreshPermissions() }.buttonStyle(.link)
        }
    }

    private var donePage: some View {
        VStack(alignment: .center, spacing: 14) {
            Spacer(minLength: 20)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46)).foregroundStyle(.green)
            Text("You’re all set!").font(.title.bold())
            Text("RetroMac is configured. Pick a theme from the menu to get started — re-run this assistant any time from the menu or Settings ▸ Overview.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer / navigation

    private var footer: some View {
        HStack {
            if page != .intro {
                Button("Back") { goBack() }.keyboardShortcut(.cancelAction)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(WizardPage.allCases, id: \.rawValue) { p in
                    Circle()
                        .fill(p.rawValue <= page.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            Button(primaryTitle) { goNext() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }

    private var primaryTitle: String {
        switch page {
        case .intro: return "Get Started"
        case .done:  return "Finish"
        default:     return "Continue"
        }
    }

    private func goNext() {
        if page == .done { onFinish(); return }
        if let next = WizardPage(rawValue: page.rawValue + 1) {
            withAnimation(.easeInOut(duration: 0.15)) { page = next }
            if next == .permissions { refreshPermissions() }
        }
    }

    private func goBack() {
        if let prev = WizardPage(rawValue: page.rawValue - 1) {
            withAnimation(.easeInOut(duration: 0.15)) { page = prev }
        }
    }

    // MARK: - Reusable pieces

    @ViewBuilder
    private func pageScaffold<C: View>(
        icon: String, tint: Color, title: String, subtitle: String,
        @ViewBuilder rows: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 24)).foregroundStyle(tint).frame(width: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.title2.bold())
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) { rows() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleRow(icon: String, tint: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }

    private func permissionRow(name: String, detail: String, granted: Bool, pane: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 18)).foregroundStyle(granted ? .green : .orange).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Text("Granted").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Open Settings") {
                    if let u = URL(string: pane) { NSWorkspace.shared.open(u) }
                }
            }
        }
    }

    // MARK: - Permission / install checks

    private func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                await MainActor.run { screenRecordingGranted = true }
            } catch {
                await MainActor.run { screenRecordingGranted = false }
            }
        }
    }

    private static func isReframeInstalled() -> Bool {
        let candidates = ["/Applications/Reframe.app",
                          NSHomeDirectory() + "/Applications/Reframe.app"]
        return candidates.contains { FileManager.default.fileExists(atPath: $0) }
    }
}

// MARK: - Controller

final class SetupWizardWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    /// Optional follow-up after the wizard finishes (e.g. show What's New on first run).
    var onFinishExtra: (() -> Void)?

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SetupWizardView(onFinish: { [weak self] in self?.finish() })
        let hosting = NSHostingView(rootView: view)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        win.title = "RetroMac Setup Assistant"
        win.contentView = hosting
        win.center()
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func finish() {
        AppSettings.shared.setupWizardComplete = true
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window (X or Finish) counts as having seen the wizard.
        AppSettings.shared.setupWizardComplete = true
        let extra = onFinishExtra
        onFinishExtra = nil
        extra?()
    }
}
