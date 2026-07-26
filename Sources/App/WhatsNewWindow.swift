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
                Text("NeXTSTEP joins the lineup")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "cube",
                        color: .purple,
                        title: "NeXTSTEP theme",
                        description: "The full NeXT desktop, rebuilt natively: a vertical Workspace menu, a right-edge dock with a live clock/calendar and the Recycler, black title bars with the four-grey chiseled bevel, the MegaPixel wallpaper, and the NeXT cursor. Running apps float free as draggable icons."
                    )

                    featureRow(
                        icon: "macwindow.on.rectangle",
                        color: .gray,
                        title: "The File Viewer",
                        description: "The NeXT Workspace file browser is back: the shelf of drawers, a current-location path strip, a grid of your apps and TV streams, and the authentic left-side scroller. It opens on its own when the theme starts, just like it always did."
                    )

                    featureRow(
                        icon: "square.grid.2x2",
                        color: .orange,
                        title: "Change any dock icon",
                        description: "Right-click a dock or app tile and pick from 120 authentic NeXT \u{201C}Fleet\u{201D} icons or your own image. A \u{201C}fill the whole tile\u{201D} option chooses edge-to-edge or inset on the silver tile."
                    )

                    featureRow(
                        icon: "tv",
                        color: .blue,
                        title: "TV in themed windows",
                        description: "The Classic Themed Window for TV streams now wears the NeXT window chrome too, alongside BeOS, Mac OS 9, Windows XP and System 6."
                    )

                    featureRow(
                        icon: "tag",
                        color: .green,
                        title: "Stable theme identity",
                        description: "Renaming or duplicating a theme now keeps its wallpaper, dock position and other settings, and two themes can share a name without clashing. Your existing settings migrate automatically."
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
