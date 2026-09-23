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
                Text("System 7.1 in 256 colours, a starfield, and an emergency exit")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 16)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "desktopcomputer",
                        color: .blue,
                        title: "System 7.1 (authentic)",
                        description: "System 7.1 as a colour Mac showed it at 256 colours: every icon on the desktop, in the Apple menu, the Application menu and the Applications window snapped to the Mac\u{2019}s standard colour table, the rainbow apple, and windows in System 7\u{2019}s lavender-grey \u{2014} striped title bar, sunken close and zoom boxes, the scroll bars of the day, measured pixel for pixel from the real thing. The Control Strip is System 7.5\u{2019}s, taken pixel for pixel from the original: AppleTalk, File Sharing, colour depth, resolution and sound. No dock; the Application menu at the right of the menu bar and Balloon Help beside it."
                    )

                    featureRow(
                        icon: "sparkles",
                        color: .purple,
                        title: "Starfield Simulation",
                        description: "The Windows 2000 screen saver, for every theme: white squares flying out of the centre, with the constants recovered from the original binary."
                    )

                    featureRow(
                        icon: "lifepreserver",
                        color: .orange,
                        title: "Settings \u{25B8} General \u{25B8} macOS defaults",
                        description: "The emergency exit: turns the theme and the shader off and puts back everything RetroMac can have changed about the system \u{2014} cursors, window corners, the Dock, the menu bar, desktop icons, wallpaper and appearance."
                    )

                    featureRow(
                        icon: "wrench.and.screwdriver.fill",
                        color: .gray,
                        title: "Fixes",
                        description: "Switching the Dock\u{2019}s auto-hide off in System Settings no longer brings the macOS Dock back over the Snow Leopard or Mountain Lion dock. A click on a background window\u{2019}s themed title bar brings that very window forward at once, without the spinning cursor, and dragging by the bar no longer loses track. The menu names the theme chosen in Settings. Desktop names that wrap get a plate that fits. The Apple cover takes the first click and stays off without Accessibility."
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
