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
                Text("Windows 95 arrives, with the Fun Stuff CD-ROM and Hover!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "desktopcomputer",
                        color: .blue,
                        title: "Windows 95 theme",
                        description: "The one that started it all: solid navy title bars, the silver 3D chrome, the clouds wallpaper and an authentic boot screen. The Start menu is period-correct too \u{2014} large icons in a narrow first level, small ones in the wider submenus, and neither Windows Update nor Log Off, because Windows 95 had neither."
                    )

                    featureRow(
                        icon: "opticaldisc",
                        color: .indigo,
                        title: "Fun Stuff (D:)",
                        description: "The CD-ROM is back on the desktop. Browse FUNSTUFF into HOVER, VIDEOS and PICTURES: music videos play in a bare title-bar window, and Clouds.exe / WINBMP.EXE set your wallpaper the way a 1995 CD-ROM would."
                    )

                    featureRow(
                        icon: "gamecontroller.fill",
                        color: .green,
                        title: "Hover! plays again",
                        description: "The Microsoft HTML5 remake of the Windows 95 classic, self-hosted and fully offline in its original pixel-graphics mode. No Wine, no emulator, no internet needed."
                    )

                    featureRow(
                        icon: "slider.horizontal.below.rectangle",
                        color: .orange,
                        title: "Authentic Win95/98 details",
                        description: "Scrollbars with a single arrow at each end, raised bevels and a dithered track. The status bar sits below its own scrollbar row, the program icon is back in the title bar, and 98/Me/XP drop the running-app dots \u{2014} their taskbars already show what is running."
                    )

                    featureRow(
                        icon: "doc.text.fill",
                        color: .purple,
                        title: "Readmes overhauled",
                        description: "Every theme\u{2019}s About This Theme is closable again, fills its window edge-to-edge, sizes itself so it needs no scrolling, and shows its artwork. Futurama finally has one too. Plus: a new setting starts you straight into your last theme."
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
