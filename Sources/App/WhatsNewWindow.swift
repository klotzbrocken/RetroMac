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
                Text("What's New in RetroMac 2.2")
                    .font(.title2.bold())
                Text("Authentic System 6, Warcraft, and a Mac OS X boot")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "square.grid.2x2",
                        color: .gray,
                        title: "Authentic Mac System 6",
                        description: "The “Mac OS 6 classic” theme is now true 1-bit black & white — racing-stripe title bars, hollow close boxes and Chicago type across windows and widgets, instead of the old Mac OS 9 Platinum look. Even the bundled Pac-Man goes monochrome."
                    )

                    featureRow(
                        icon: "shield.lefthalf.filled",
                        color: .red,
                        title: "Warcraft I + II",
                        description: "Play Warcraft: Orcs & Humans and Warcraft II natively on the bundled open-source Stratagus engine — point RetroMac at your own game data and go. The CRT shader lays right over the game."
                    )

                    featureRow(
                        icon: "sparkles",
                        color: .blue,
                        title: "Mac OS X boot animation",
                        description: "Activate the Mac OS X or Snow Leopard theme and it boots like the real thing — the blue screen, the grey Apple with its spinner, the progress splash. Click to skip."
                    )

                    featureRow(
                        icon: "lock.open",
                        color: .green,
                        title: "Clearer Pro unlocks",
                        description: "Live Wallpaper and Virtual Camera now show a consistent lock when they're locked, and the license screens spell out everything the unlock includes — presets, custom shaders, Live Wallpaper and the camera."
                    )

                    featureRow(
                        icon: "wrench.and.screwdriver",
                        color: .indigo,
                        title: "Polish",
                        description: "Themed window frames with live title-bar buttons, boot videos that no longer get cut off partway, and a Welcome window that fits each page without scrolling."
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
