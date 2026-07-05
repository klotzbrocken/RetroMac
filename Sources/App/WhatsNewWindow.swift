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
                Text("What's New in RetroMac 1.9.7")
                    .font(.title2.bold())
                Text("Two new Mac themes, a retro TV, and matching system looks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "sparkles",
                        color: .indigo,
                        title: "New theme: Mac OS 6 classic",
                        description: "A full black-and-white System 6 desktop — 1-bit icons, selectable 8×8 desktop patterns, Chicago/Geneva fonts, and a Control Strip that can switch to a 2D Platinum-style dock. Every running app's icon is shown in monochrome to match."
                    )

                    featureRow(
                        icon: "macwindow",
                        color: .gray,
                        title: "Mac OS 9 merged + Platinum widgets",
                        description: "The old “Mac OS 9.2” theme is now a Platinum-dock option inside Mac OS 9 Classic. Every Mac OS 9 / 6 desktop widget (Clock, CPU, Applications, TV, Notepad) has a pixel-faithful Platinum title bar with pinstripes and working close/collapse/zoom boxes."
                    )

                    featureRow(
                        icon: "tv",
                        color: .blue,
                        title: "TV Tube mode",
                        description: "One click in the flyout turns your streams into a floating retro TV — a free-standing TV set in a window (resize it), or fullscreen on an external display with a downloadable TV bezel and the Joel GDV-NTSC CRT shader. Right-click to change channel, shader, bezel or TV set."
                    )

                    featureRow(
                        icon: "paintpalette",
                        color: .purple,
                        title: "Themes match your Mac",
                        description: "Optional per-theme matching of the macOS appearance + accent colour (Graphite for Mac OS, and more), a Terminal profile that fits the theme (DOS green, BeOS, Classic Mac…), and a crown marks the special themes. Your originals are remembered and restored."
                    )

                    featureRow(
                        icon: "moon.stars",
                        color: .teal,
                        title: "Real screensavers",
                        description: "Install Pipes, FlowerBox, Flying Toasters and Flurry as genuine macOS .saver modules from Settings ▸ Screensaver."
                    )

                    featureRow(
                        icon: "wrench.and.screwdriver",
                        color: .gray,
                        title: "Consistency & fixes",
                        description: "Unified dock icon sizes across the Mac docks (and desktop icons follow the size slider), Snow Leopard / Mountain Lion shown as “Mac OS …”, sturdier crash-recovery for the matched appearance/Terminal, and many smaller fixes."
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
