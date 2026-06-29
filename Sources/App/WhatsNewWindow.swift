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
                Text("What's New in RetroMac 1.9.5")
                    .font(.title2.bold())
                Text("A new DOOM theme, a 24-hour clock, and a batch of fixes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "flame.fill",
                        color: .red,
                        title: "New theme: Maiks Favourite II (DOOM)",
                        description: "A pixel Doom Slayer patrols the dock — he runs, switches weapons and fires, gets fragged, and a Lost Soul flies in for him to blast. Hover him to frag him, click the DOOM logo tile (next to the trash) to launch DOOM, and top it off with the new \u{201C}Apple Hell\u{201D} menu-bar logo."
                    )

                    featureRow(
                        icon: "apple.logo",
                        color: .pink,
                        title: "Retro menu-bar Apple",
                        description: "Cover the system Apple with the classic Rainbow, Aqua, Aqua Classic or the new Apple Hell logo — cycle it from the flyout, with sensible per-theme defaults."
                    )

                    featureRow(
                        icon: "clock",
                        color: .indigo,
                        title: "24-hour clock",
                        description: "New option (Settings ▸ Dock) for the dock and deskbar clocks, plus a digital readout under the analog Clock widget that follows it."
                    )

                    featureRow(
                        icon: "iphone",
                        color: .blue,
                        title: "iPhone as a camera source",
                        description: "Pick your iPhone (Continuity Camera) or any webcam in Settings ▸ Camera & Streaming — the list updates live as devices connect, and the CRT shader runs on the feed."
                    )

                    featureRow(
                        icon: "square.grid.2x2",
                        color: .cyan,
                        title: "Cleaner theming",
                        description: "\u{201C}Dock only\u{201D} now changes only the dock (no wallpaper / widgets / full-screen shader), the retro TV window no longer borrows a stale theme\u{2019}s chrome, and the quick-access flyout is tidier."
                    )

                    featureRow(
                        icon: "wrench.and.screwdriver",
                        color: .gray,
                        title: "Reliability & polish",
                        description: "Your real Dock reliably returns after turning a theme off (and never peeks out beside the retro dock), Mac OS X / Snow Leopard magnification no longer reacts outside the dock, the floating launcher stays clickable beside a dock, and a clearer privacy/offline note lives in About."
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
