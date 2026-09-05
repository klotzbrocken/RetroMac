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
                Text("Windows Me in detail, crashes that never crash, a shader over the whole desktop")
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
                        title: "Windows Me, gone over in detail",
                        description: "The boot screen is the animated Me logo instead of a still, three original wallpapers come along, and Defrag is its own program on the desktop. Folder windows are Explorer now \u{2014} back, forward, up, an address bar, the info panel and a status line that counts what is in the folder. Plus a long row of small corrections: the tray carries the theme\u{2019}s colour instead of a foreign grey, its icons share one rhythm instead of three different gaps, mute shows as a red prohibition sign, quick launch stops growing under the pointer because Windows never did that, desktop icons start at the left, and the calculator has its original key colours and the memory indicator it was missing."
                    )

                    featureRow(
                        icon: "exclamationmark.triangle.fill",
                        color: .red,
                        title: "Retro Glitches & Crashes",
                        description: "Failure, in period. The Windows 9x blue screen, the Illegal Operation dialog with its expandable register dump, the XP and 7 stop error with a counting memory dump, the Mac OS bomb. The desktop freezes, the message appears, and the way out is the one the machine offered at the time. Nothing actually crashes: no program is quit, no document closed, no restart triggered \u{2014} the frozen desktop is a photograph of itself, laid on top. By hand, or on a schedule from very rare to chaotic."
                    )

                    featureRow(
                        icon: "photo.on.rectangle.angled",
                        color: .purple,
                        title: "Live Wallpaper covers the whole desktop",
                        description: "One switch runs the selected shader over the desktop picture, RetroMac\u{2019}s own desktop icons, the retro dock and an open start menu \u{2014} in a single pass, so the scanlines run through all of them instead of restarting in each. Application windows are never touched. While it is on, the retro taskbar sits behind them, which is what puts it in the same pass as the desktop."
                    )

                    featureRow(
                        icon: "gamecontroller.fill",
                        color: .green,
                        title: "The Game Library",
                        description: "A cover gallery for everything RetroMac can start. It installs the engine, names the file that engine needs, and looks in your Steam library for the copy you already own, external drives included. What the rights holder released for sharing it fetches itself: Freedoom and the shareware episodes of Doom, Heretic, Duke Nukem 3D, Quake, Quake II and Shadow Warrior. Full versions it does not fetch, and the card says so."
                    )

                    featureRow(
                        icon: "wrench.and.screwdriver.fill",
                        color: .gray,
                        title: "And a long list of fixes",
                        description: "Cancelling a download now cancels it. \u{201C}Forget\u{201D} no longer meant \u{201C}delete\u{201D}. Crashes set to chaotic actually happen. The muted tray speaker is visible again. The Mac OS crash alerts line up and every one has an icon. The menu-bar tint comes back after a display is connected or unplugged. Quake II\u{2019}s demo download works again. And the credits say what is true."
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
