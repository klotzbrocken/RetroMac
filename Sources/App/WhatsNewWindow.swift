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
                Text("What's New in RetroMac 2.0")
                    .font(.title2.bold())
                Text("Themed mouse cursors for every OS — and more")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "cursorarrow.rays",
                        color: .indigo,
                        title: "Themed mouse cursors",
                        description: "Each theme can replace your whole system cursor — the classic Mac pointer with its ticking wristwatch (System 6) or rotating spinner (System 9), the Mac OS X Aqua set with the spinning beach ball, Windows XP, and the retro Windows 3.1 pointers. Toggle it under Settings ▸ Dock ▸ “Match cursor”; your own cursor is captured and restored exactly when the theme goes off."
                    )

                    featureRow(
                        icon: "arrow.up.left.and.arrow.down.right",
                        color: .blue,
                        title: "Windows XP cursor sizes",
                        description: "The Windows XP theme’s cursors come in Normal, Large and XL — pick your size in Settings ▸ Dock while the theme is active."
                    )

                    featureRow(
                        icon: "square.stack.3d.up",
                        color: .green,
                        title: "BeOS, unified",
                        description: "“BeOS” and “BeOS Classic” are now one theme. A Dock-style switch chooses between the classic corner Deskbar and a regular bottom dock."
                    )

                    featureRow(
                        icon: "slider.horizontal.3",
                        color: .orange,
                        title: "Per-theme icon sizes",
                        description: "The dock and desktop icon-size sliders are now remembered per theme, so each look keeps its own sizing."
                    )

                    featureRow(
                        icon: "checklist",
                        color: .purple,
                        title: "Setup Assistant options",
                        description: "The first-run assistant now lets you opt in (on by default) to matching the macOS colour scheme and the themed cursor when a theme is active."
                    )

                    featureRow(
                        icon: "wrench.and.screwdriver",
                        color: .gray,
                        title: "Fixes & polish",
                        description: "The menu-bar Apple logo now resets when a theme (or the app) turns off, the System 6 Control Strip is fully opaque, a new System 6 boot splash, plus TV-Tube and Duke Nukem / GZDoom launch fixes."
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
