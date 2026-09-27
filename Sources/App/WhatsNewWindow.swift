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
                Text("A dock you can rearrange, WindowShade, and one theme everywhere")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 16)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "dock.rectangle",
                        color: .blue,
                        title: "Rearrange the dock",
                        description: "Drag an icon along the dock and it stays where you let go; an app or a folder dragged in from the Finder lands where it is dropped. In Settings the grip on \u{201C}Apps in the dock\u{201D} works, and the dots open a menu instead of removing the item. A folder in the dock takes the icon you choose for it, and any folder called Downloads wears the theme\u{2019}s Downloads icon."
                    )

                    featureRow(
                        icon: "rectangle.compress.vertical",
                        color: .purple,
                        title: "WindowShade",
                        description: "Under the Mac OS 8/9 title bars the collapse box and a double-click roll a window up to its bar and down again, as Mac OS 8 and 9 did; under System 7.1 a double-click does it, as System 7.5\u{2019}s WindowShade did. The bar stays where the window was and can be dragged."
                    )

                    featureRow(
                        icon: "menubar.rectangle",
                        color: .orange,
                        title: "System 7.1, closer to the original",
                        description: "Its own Apple menu \u{2014} About This Macintosh, Alarm Clock, Applications, Calculator, Chooser, Control Panels, Key Caps, Note Pad, Scrapbook \u{2014} and the Control Strip follows a switch to or from Mac OS 9 at once."
                    )

                    featureRow(
                        icon: "wrench.and.screwdriver.fill",
                        color: .gray,
                        title: "Fixes",
                        description: "A theme picked in Settings now reaches Quick Access, the status menu, the shader and the Apple menu. No dock is left behind after a switch to a theme without one. Dragging a window by its bar no longer loses a short first drag. Disks on the desktop follow mount and unmount. \u{201C}Quit RetroMac\u{201D} from the dock asks first."
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
