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
                Text("What's New in RetroMac 1.9")
                    .font(.title2.bold())
                Text("A Dock launcher, real taskbar tabs, and shaders on every screen")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "menubar.dock.rectangle",
                        color: .blue,
                        title: "Dock Mode & quick launcher",
                        description: "Optionally show RetroMac in the Dock; click its icon for a slim launcher to switch themes and toggle the shader or virtual camera. Turn it on in Settings ▸ Dock."
                    )

                    featureRow(
                        icon: "rectangle.on.rectangle",
                        color: .cyan,
                        title: "Authentic Windows taskbar",
                        description: "Windows 98 and XP now show one elongated taskbar button per open window — click to minimize or restore, just like the real thing."
                    )

                    featureRow(
                        icon: "display.2",
                        color: .green,
                        title: "Shaders on all your displays",
                        description: "Fixed the CRT shader on secondary monitors — \"All Displays\" now lights up every screen, not just the main one."
                    )

                    featureRow(
                        icon: "tv.inset.filled",
                        color: .orange,
                        title: "New Retro Crisis shaders + fixes",
                        description: "Two GDV-NTSC \"Retro Crisis\" looks (Composite & RGB), and the classic 98.js desktop apps (Notepad, Paint, Minesweeper…) work again."
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
