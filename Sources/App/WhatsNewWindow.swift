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
                Text("Windows 7 Aero, Windows 98 Plus!, and a sharper System 9")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "macwindow",
                        color: .blue,
                        title: "Windows 7 Aero",
                        description: "The Superbar taskbar with the Start orb, translucent glass title bars and the Aero wallpaper. Windows 7 joins the lineup."
                    )

                    featureRow(
                        icon: "paintpalette",
                        color: .orange,
                        title: "Windows 98 Plus! themes",
                        description: "Pick a scheme under Settings, Dock, Scheme: Dangerous Creatures, Leonardo da Vinci or More Windows. Each recolours the whole Windows 98 look and swaps the wallpaper, icons and cursors."
                    )

                    featureRow(
                        icon: "square.grid.3x3",
                        color: .gray,
                        title: "Mac OS System 9",
                        description: "Pixel-accurate Platinum title bars, proxy icons, a Finder info bar and WindowShade collapse. The Control Strip now docks to the left or right edge, just like the original."
                    )

                    featureRow(
                        icon: "shield.lefthalf.filled",
                        color: .red,
                        title: "Warcraft in a real window",
                        description: "Warcraft I and II now run inside a themed window with a matching title bar, so the game sits on your retro desktop with the dock beside it (hidden only in fullscreen)."
                    )

                    featureRow(
                        icon: "wrench.and.screwdriver",
                        color: .indigo,
                        title: "Setup and polish",
                        description: "A new Setup Assistant Games step points RetroMac at your Doom, Quake, Duke Nukem and Warcraft files. Plus a Calculator widget, more classic wallpapers and desktop icons, tighter window borders and hardened theme imports."
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
