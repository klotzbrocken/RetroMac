import SwiftUI

struct WhatsNewView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(.yellow)
                    .padding(.top, 24)
                Text("What's New in RetroMac \(currentAppVersion)")
                    .font(.title2.bold())
                Text("Windows Me joins the family — plus a Windows 7 Aero overhaul")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "desktopcomputer",
                        color: .blue,
                        title: "Windows Me theme",
                        description: "Millennium Edition lands: the Me Start-menu banner in its brush-script logo, a 4K-remastered wallpaper, an authentic boot splash, and the Me shell icons (oval Recycle Bin, Media Player). \u{201C}Windows Update\u{201D} sits atop the Start menu, and it gets the full special-theme treatment — systray, taskbar auto-hide and the desktop pet."
                    )

                    featureRow(
                        icon: "macwindow",
                        color: .cyan,
                        title: "Windows 7 Aero, refined",
                        description: "The Windows 7 Start menu now has its glass frame and the account picture that peeks above the top edge. The taskbar is real translucent Aero glass, and the notification area is finally authentic: a flat tray with an up-chevron, network + volume icons that open the matching macOS settings, and a two-line time/date clock."
                    )

                    featureRow(
                        icon: "checkmark.seal.fill",
                        color: .green,
                        title: "100% themes",
                        description: "The marker on the fully-realised themes is now a 100% badge, shown right after the theme name — and Futurama counts as 100% too."
                    )

                    featureRow(
                        icon: "rectangle.grid.2x2",
                        color: .orange,
                        title: "Flyout upgrades",
                        description: "Drag Quick Access tiles to reorder them in Edit mode, double-click the floating button to toggle your last theme, and the menu-bar Apple-logo cycle now includes the Futurama teal apple."
                    )

                    featureRow(
                        icon: "wave.3.right",
                        color: .purple,
                        title: "New shaders",
                        description: "NLO VHS SP — a real single-pass NTSC comb-demodulation with authentic dot crawl and cross-colour — and CRT EasyMode, a clean, sharp mask-and-scanline CRT."
                    )
                }
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: 300)

            Spacer()

            Button("Let's Go!") {
                AppSettings.shared.lastSeenVersion = currentAppVersion
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 20)
        }
        .frame(width: 440, height: 500)
    }

    private func featureRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.6.0"
    }
}

final class WhatsNewWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    /// Show if the user hasn't seen this version yet
    func showIfNeeded() {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.6.0"
        let lastSeen = AppSettings.shared.lastSeenVersion
        let onboarded = AppSettings.shared.onboardingComplete

        print("[WhatsNew] Check: current=\(currentVersion) lastSeen='\(lastSeen)' onboarded=\(onboarded)")

        guard onboarded else {
            print("[WhatsNew] Skipped — onboarding not complete")
            return
        }
        guard lastSeen != currentVersion else {
            print("[WhatsNew] Skipped — already seen \(currentVersion)")
            return
        }

        print("[WhatsNew] Showing What's New for \(currentVersion)")
        show()
    }

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: WhatsNewView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "What's New"
        window.contentView = hostingView
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.6.0"
        AppSettings.shared.lastSeenVersion = currentVersion
    }
}
