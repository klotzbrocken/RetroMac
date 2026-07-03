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
                Text("What's New in RetroMac 1.9.6")
                    .font(.title2.bold())
                Text("A meaner DOOM dock, a 60% smaller download, and fixes")
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
                        title: "DOOM theme: real firefights",
                        description: "Every weapon now fires with its authentic muzzle-flash animation, the Plasma gun spits a stream of blue bolts, rockets and the new BFG detonate in proper explosions, and Lost Souls charge the Slayer — if he's too slow, they get him. He only goes down to demons or your mouse now, with the full 6-frame fall."
                    )

                    featureRow(
                        icon: "arrow.down.circle.fill",
                        color: .green,
                        title: "60% smaller download",
                        description: "A full asset diet shrank the app from ~151 MB to ~61 MB — same themes, same quality where it counts, much faster downloads and updates."
                    )

                    featureRow(
                        icon: "play.circle",
                        color: .orange,
                        title: "Boot videos are skippable",
                        description: "A click (or any key) now skips the Windows XP / 98 / Mac boot sequences straight to the desktop — the video player used to swallow the click."
                    )

                    featureRow(
                        icon: "display.2",
                        color: .blue,
                        title: "External-display fixes",
                        description: "The retro menu-bar Apple logo now sits correctly on external monitors (it used to drift on extended 1080p displays)."
                    )

                    featureRow(
                        icon: "magnifyingglass",
                        color: .cyan,
                        title: "Magnification polish",
                        description: "The running-app dot stays centred under its icon while the Mac OS X / Snow Leopard docks magnify, and Snow Leopard joins the special themes in the flyout."
                    )

                    featureRow(
                        icon: "wrench.and.screwdriver",
                        color: .gray,
                        title: "Respects your settings",
                        description: "Turning Retro Mode off restores only what RetroMac itself hid — your own Dock auto-hide or hidden desktop icons stay untouched. The CRT Lite app overlay also sticks to one window instead of jumping between windows of the same app."
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
