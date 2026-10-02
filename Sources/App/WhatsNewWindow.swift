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
                Text("Mac OS X as 10.0 looked, a Task Manager for XP, and a dock you can rearrange")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 16)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "macwindow",
                        color: .cyan,
                        title: "Mac OS X, closer to 10.0",
                        description: "White pinstriped title bars with glossy Aqua lights, and the pill that rolls a window up into its bar like a garage door. The Dock sits on the screen\u{2019}s edge with one divider, black triangles, bouncing icons and outlined names. 10.0\u{2019}s Apple menu, its blue apple, a Finder-style Applications window, a proper boot screen and dozens of original Mac OS X icons."
                    )

                    featureRow(
                        icon: "gauge.with.dots.needle.33percent",
                        color: .green,
                        title: "Windows Task Manager",
                        description: "Under Windows XP, Ctrl+Option+Delete \u{2014} or \u{201C}Task Manager\u{201D} in the taskbar\u{2019}s menu \u{2014} opens XP\u{2019}s Task Manager with a live Performance page: the green meters, the history graphs and all the numbers, from what your Mac reports."
                    )

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
                        description: "The dock hides over full-screen apps again, and the green light takes a window out of full screen. The dock no longer stays magnified when the pointer leaves for a display below. A theme picked in Settings now reaches Quick Access, the status menu, the shader and the Apple menu. Rolled-up windows always find their way back. The wallpaper cache stays small. \u{201C}Quit RetroMac\u{201D} from the dock asks first."
                    )

                }
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: 300)

            Spacer()

            // Stars are how RetroMac gets into Homebrew and in front of new people.
            Link("Like RetroMac? \u{2605} Star it on GitHub", destination: URL(string: "https://github.com/klotzbrocken/RetroMac")!)
                .font(.callout)
                .padding(.bottom, 10)

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
