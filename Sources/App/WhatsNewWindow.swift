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
                Text("Mac OS 9 as it was, a title bar over every window, and a dock that stays smooth")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 16)

            // Feature list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "menubar.rectangle",
                        color: .blue,
                        title: "Mac OS 9 (authentic)",
                        description: "A second Mac OS 9, next to the Classic theme, laid out the way the machine was: no dock. The Control Strip at the bottom edge holds the system \u{2014} network, battery, media bay, sharing, keychain, colour depth, monitor resolution (it really switches, with the old keep-or-revert question), printer, sound volume with the slider of its day, sound source, video mirroring \u{2014} and rolls in and out under its tab. The Application menu at the right end of the menu bar switches programs, the Apple menu opens the menu of the day, Recent Applications and Recent Documents included, all drawn in Platinum with Chicago as a bitmap face. The desktop holds Macintosh HD, Applications and the Trash, labelled on the pale plate. A minimised window does not shrink into a corner: it zooms away to the top of the desktop and is gone."
                    )

                    featureRow(
                        icon: "macwindow",
                        color: .purple,
                        title: "Experiment: title bars in theme style",
                        description: "Under Themes \u{25B8} System integration: a Platinum or Luna title bar over every real window, or Aqua and Snow Leopard traffic lights in place of the modern ones. RetroMac\u{2019}s own panel above the window, not a change to the app; close, minimise, zoom the way the era did and dragging all go through Accessibility. Apps can be left alone. It is an experiment: a toolbar that shares the title bar (Safari, Finder) loses its top edge, and a window the size of the screen gets no bar."
                    )

                    featureRow(
                        icon: "dock.rectangle",
                        color: .green,
                        title: "The dock stays smooth",
                        description: "With the title bars on, the dock\u{2019}s magnification juddered: the pointer was watched through a global mouse monitor, and from the first change of front app on, the WindowServer handed the dock its mouse moves in bursts. The monitor is gone. The Aqua dock also stopped looking every app\u{2019}s name up on disk on every mouse move, and the dock\u{2019}s own auto-hide no longer watches the pointer that way either."
                    )

                    featureRow(
                        icon: "wrench.and.screwdriver.fill",
                        color: .gray,
                        title: "And a long list of fixes",
                        description: "The \u{201C}Classic window corners\u{201D} hint no longer traps the Windows Me and Mac OS 9 boot animation in a loop. The lights and the frame leave with a window that is minimised or closed from the bar. A new Chrome tab no longer buries the lights, and the menu-bar Apple logo stopped blinking. A crash on a theme that keeps the menu bar runs to the end. The boot screen can always be clicked away, and a stuck switch cannot lock the Mac. Traffic lights keep up with a dragged window, and the windows round their corners the era\u{2019}s way under the Mac OS X and Snow Leopard lights."
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
