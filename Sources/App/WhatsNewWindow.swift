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
                Text("What's New in RetroMac 1.9.2")
                    .font(.title2.bold())
                Text("A retro menu-bar Apple, your iPhone as the camera, a tighter \u{201C}Dock only\u{201D} & fixes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "apple.logo",
                        color: .pink,
                        title: "Retro menu-bar Apple",
                        description: "Cover the system Apple with the classic Rainbow, Aqua or Aqua Classic logo — cycle it from the flyout. Snow Leopard and Mac OS 9 pick fitting defaults."
                    )

                    featureRow(
                        icon: "iphone",
                        color: .blue,
                        title: "iPhone as a camera source",
                        description: "Pick your iPhone (Continuity Camera) or any webcam in Settings ▸ Camera & Streaming — the list now updates live as devices connect, and the CRT shader runs on the feed."
                    )

                    featureRow(
                        icon: "menubar.dock.rectangle",
                        color: .green,
                        title: "\u{201C}Dock only\u{201D} really means dock only",
                        description: "Switching a theme with Dock only on no longer touches your wallpaper, desktop icons, widgets or starts a full-screen shader — just the dock changes."
                    )

                    featureRow(
                        icon: "tv",
                        color: .orange,
                        title: "TV windows behave",
                        description: "The retro TV window no longer borrows the last used theme\u{2019}s menu bar / chrome when no theme is active."
                    )

                    featureRow(
                        icon: "square.grid.2x2",
                        color: .cyan,
                        title: "Tidier quick-access flyout",
                        description: "Active theme is highlighted correctly (only when one is really on), Settings and Quit are clean icons, and the floating launcher button is on by default."
                    )

                    featureRow(
                        icon: "wrench.and.screwdriver",
                        color: .gray,
                        title: "Icon & desktop fixes",
                        description: "Correct flyout icons for Snow Leopard, Windows 3.1 and Maiks Favourite, the right app icon in Dock Mode, and desktop-icon visibility now respects other apps."
                    )
                }
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: 280)

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
