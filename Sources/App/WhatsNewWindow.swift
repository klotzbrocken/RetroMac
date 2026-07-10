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
                Text("What's New in RetroMac 2.1")
                    .font(.title2.bold())
                Text("A living wallpaper — bring your desktop to life")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "photo.on.rectangle.angled",
                        color: .pink,
                        title: "Living wallpaper",
                        description: "A new effect scope applies the CRT/VHS shader to your wallpaper only — it wobbles and scans behind your icons and windows, which stay perfectly crisp. Because it renders the wallpaper instead of capturing the screen, it needs no Screen Recording permission. Set it under Settings ▸ Advanced ▸ Effects ▸ “Apply to: Wallpaper only.”"
                    )

                    featureRow(
                        icon: "book",
                        color: .indigo,
                        title: "Build your own shaders",
                        description: "Advanced ▸ Presets now has an in-app guide with an “Open guide” button for writing and importing your own .metal CRT shaders — they show up right in the Shader Presets menu."
                    )

                    featureRow(
                        icon: "slider.horizontal.3",
                        color: .orange,
                        title: "Settings, refined",
                        description: "A tidier Settings window — a narrower layout, cleaner Advanced controls, 16:9 theme previews, and unified control sizing throughout."
                    )

                    featureRow(
                        icon: "wrench.and.screwdriver",
                        color: .gray,
                        title: "Fixes & polish",
                        description: "Multi-monitor Tube/dock fixes, a hardened trusted-download installer for retro apps, slimmer app download, plus the System 6 Control Strip and boot-splash refinements."
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
