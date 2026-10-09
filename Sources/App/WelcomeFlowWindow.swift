import SwiftUI
import ScreenCaptureKit

/// Pages that can appear in the unified welcome flow.
enum WelcomePage: Equatable {
    case whatsNew
    case getMore
    case setupScreenRecording
    case setupAccessibility
    case coffee

    /// One size for every page here, taken from What's New because that is the tallest and the
    /// least willing to shrink. The Setup Assistant shares the width but is shorter
    /// (`SetupWizardView.windowHeight`): its pages are lists of switches, and at 700 points
    /// most of them were empty.
    static let windowWidth: CGFloat = 460
    static let windowHeight: CGFloat = 700

    var preferredHeight: CGFloat { Self.windowHeight }
}

/// One window, multiple pages: What's New → Setup → Coffee/Unlock, shown conditionally.
struct WelcomeFlowView: View {
    let pages: [WelcomePage]
    let onFinish: (_ coffeeAcknowledged: Bool) -> Void

    @State private var index = 0
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false
    @State private var coffeeAck = false
    @State private var keyInput = ""
    @State private var activationMessage: String?
    @State private var activationSuccess: Bool?
    @ObservedObject private var license = LicenseManager.shared

    private var page: WelcomePage { pages.indices.contains(index) ? pages[index] : .coffee }
    private var isLast: Bool { index >= pages.count - 1 }

    /// Grow/shrink the window to the current page, keeping its top edge put — resizing from
    /// the bottom-left origin would otherwise make the window appear to jump up the screen.
    private func resizeWindowForPage() {
        guard let win = NSApp.windows.first(where: { $0.title == WelcomeFlowWindowController.windowTitle })
        else { return }
        let target = page.preferredHeight
        var frame = win.frame
        let newFrame = win.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 460, height: target))
        guard abs(frame.height - newFrame.height) > 0.5 else { return }
        frame.origin.y += frame.height - newFrame.height
        frame.size.height = newFrame.height
        win.setFrame(frame, display: true, animate: true)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case .whatsNew: whatsNewPage
                case .setupScreenRecording: screenRecordingPage
                case .setupAccessibility: accessibilityPage
                // Like the coffee page: the shared view carries no margin of its own, the
                // Setup Assistant pads it and this window has to as well.
                case .getMore: ScrollView { GetMoreView().padding(20) }
                case .coffee: coffeePage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            navBar
        }
        // Per page, not one size for all: What's New is a long list, the setup pages are a
        // couple of paragraphs and a button. Sizing everything to the tallest left the short
        // ones mostly empty. The ScrollViews stay as a safety net for short screens.
        .frame(width: 460, height: page.preferredHeight)
        // The hosting view can't resize its window on its own, so carry the height over
        // whenever the page changes.
        .onChange(of: index) { _ in resizeWindowForPage() }
    }

    // MARK: - Nav

    private var navBar: some View {
        HStack {
            if index > 0 {
                Button("Back") { index -= 1 }
                    .buttonStyle(RMDefaultButtonStyleSafe())
            }
            Spacer()
            // Page indicator dots
            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { i in
                    Circle().fill(i == index ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            Button(isLast ? "Done" : "Next") { advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func advance() {
        if isLast { finish() } else { index += 1 }
    }

    private func finish() {
        onFinish(coffeeAck)
        NSApp.keyWindow?.close()
    }

    // MARK: - What's New

    private var whatsNewPage: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(.yellow).padding(.top, 24)
                Text("What's New in RetroMac \(whatsNewVersion) Beta").font(.title2.bold())   // drop "Beta" for the release
                Text("Spaces, new themes, historic icons \u{2014} and a lot of fixes")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    feature("rectangle.split.3x1", .indigo, "A theme on your Spaces of choice",
                            "Keep the theme to one Space, or a few, and plain macOS on the others: Only on this Space in the flyout. The theme slides away with its Space; the others have the Mac\u{2019}s Dock, menu bar and your own wallpaper. Every Space also gets its own wallpaper back when a theme goes off.")
                    feature("sun.max.fill", .purple, "New: Solaris 8 \u{2014} CDE",
                            "The Unix desktop of 2000: the Front Panel with its live clock and subpanels, mauve title bars with the window menu, the Workspace Menu on a right-click, minimised windows as icons, the Application Manager, and crashes on the Sun console.")
                    feature("cpu", .blue, "New: QNX 6.2.1 \u{2014} Photon",
                            "The realtime OS\u{2019}s desktop from its 2003 CD: the shelf with groups you fold open and shut and a live system monitor, the taskbar with Launch and one entry per window, and Photon\u{2019}s blue title bars.")
                    feature("macwindow.on.rectangle", .cyan, "New: Windows Vista and its Sidebar",
                            "Aero glass windows on a black glass taskbar with the round Start orb, eight Vista wallpapers, Vista\u{2019}s own icons, and the Sidebar with a clock, a calendar and a CPU meter.")
                    feature("paintbrush.pointed.fill", .yellow, "Themes, closer to the originals",
                            "BeOS gets its yellow window tabs. Snow Leopard\u{2019}s dock reflections grow with the icon and fade out on the shelf. Amiga Workbench and SGI IRIX have the top of the screen to themselves.")
                    feature("photo.on.rectangle.angled", .teal, "Historic icons for modern apps",
                            "Over 200 new icons: Office, Teams, Slack, Zoom, Figma, VS Code, Firefox, Spotify and many more, drawn in the style of Mac OS 9, System 7, Mac OS X, BeOS, Windows 3.1 to 7. Import your own icon packages in Settings \u{25B8} Dock \u{25B8} Historic icons.")
                    feature("lifepreserver", .red, "Rescue Desktop",
                            "One action turns the theme and every effect off, brings back windows you cannot reach and the menu bar a theme hid. Your settings stay. \u{2303}\u{2325}\u{2318}R, the flyout or the menu-bar menu.")
                    feature("rectangle.stack", .orange, "The window switcher of each era",
                            "\u{2303}\u{2325}Tab does what the theme\u{2019}s era did: Solaris moves the focus window by window, Snow Leopard opens Expos\u{00E9}, Mountain Lion Mission Control.")
                    feature("gauge.with.dots.needle.33percent", .green, "Task Manager, all five pages",
                            "Under Windows XP: Applications, Processes, Performance, Networking and Users. Open it with Ctrl+Option+Delete or from the Start menu.")
                    feature("accessibility", .blue, "VoiceOver",
                            "RetroMac\u{2019}s drawing no longer shows up as empty windows, and the docks, taskbars, Start menus and panels are named buttons and menus VoiceOver can use.")
                    feature("gearshape.2", .gray, "Settings, tidied up",
                            "Themes first, the shader in four clear tabs, Retro Mode is now Favourite, a shorter Setup Assistant with themes by family, and betas on request in About.")
                    feature("wrench.and.screwdriver.fill", .gray, "Fixes",
                            "Theme switches no longer restart the Dock and Finder for nothing. Pac-Man starts again. The shader is off behind the lock screen. No more log file on the Desktop. A rolled-up window keeps its way back, even across a crash. Mission Control no longer shows the title bars as little windows.")

                    sectionHeader("Also in 2.8.8")

                    feature("macwindow", .cyan, "Mac OS X, closer to 10.0",
                            "White pinstriped title bars with glossy Aqua lights, and the pill that rolls a window up into its bar like a garage door. The Dock on the screen\u{2019}s edge with bouncing icons and outlined names, 10.0\u{2019}s Apple menu, a proper boot screen and dozens of original Mac OS X icons.")
                    feature("dock.rectangle", .blue, "Rearrange the dock",
                            "Drag an icon along the dock and it stays where you let go; an app or a folder dragged in from the Finder lands where it is dropped. A folder takes the icon you choose for it.")
                    feature("rectangle.compress.vertical", .purple, "WindowShade",
                            "Under the Mac OS 8/9 title bars the collapse box and a double-click roll a window up to its bar and down again; under System 7.1 a double-click does it, as System 7.5\u{2019}s WindowShade did.")


                }.padding(.horizontal, 24).padding(.bottom, 12)
            }
            // Stars are how RetroMac gets into Homebrew and in front of new people.
            Link("Like RetroMac? \u{2605} Star it on GitHub", destination: URL(string: "https://github.com/klotzbrocken/RetroMac")!)
                .font(.callout).padding(.vertical, 8)
        }
    }

    private var whatsNewVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.3"
    }

    /// Divider between this release's entries and the ones carried over from the last, so anyone
    /// updating across two versions is still told what the one in between brought.
    private func sectionHeader(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
        }
        .padding(.top, 2)
    }

    private func feature(_ icon: String, _ color: Color, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(desc).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Setup pages

    private var screenRecordingPage: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tv.and.mediabox").font(.system(size: 44)).foregroundStyle(.orange)
            Text("Welcome to RetroMac").font(.title2.bold())
            Text("To paint retro shader effects over your screen, RetroMac needs Screen Recording access. It reads the screen live — nothing is ever recorded or stored.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }.padding(.top, 4)
            statusIndicator(granted: screenRecordingGranted)
            Spacer()
        }
        .padding()
        .onAppear { checkScreenRecording() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            if !screenRecordingGranted { checkScreenRecording() }
        }
    }

    private var accessibilityPage: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "hand.raised.circle").font(.system(size: 36)).foregroundStyle(.blue)
            Text("Accessibility").font(.title3.bold())
            Text("Needed for global hotkeys and hiding the system dock/menu bar. Optional but recommended.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
            HStack(spacing: 12) {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Check Permission") { accessibilityGranted = AXIsProcessTrusted() }
            }.padding(.top, 4)
            statusIndicator(granted: accessibilityGranted)
            Spacer()
        }.padding()
    }

    // MARK: - Coffee / Unlock

    private var coffeePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "heart.fill").font(.system(size: 40)).foregroundStyle(.pink)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keep RetroMac free").font(.title2.bold())
                        // Not "no feature locks" any more — presets, Live Wallpaper and the
                        // Virtual Camera are gated, and claiming otherwise on the very page
                        // that sells the unlock was a bad look.
                        Text("No ads, no tracking. The core is free forever; a one-off unlock opens the rest and helps the developer keep improving the app.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if license.isLicensed {
                    Label("License active — everything unlocked", systemImage: "checkmark.seal.fill")
                        .font(.body).foregroundStyle(.green).padding(.vertical, 24)
                } else {
                    // Three benefits
                    HStack(spacing: 10) {
                        benefitCard("lock.fill", .blue, "No Tracking")
                        benefitCard("xmark.octagon.fill", .purple, "Ad-Free")
                        benefitCard("heart.fill", .pink, "100% Optional")
                    }

                    Divider()

                    Text("Choose your support").font(.headline)

                    supportRow(emoji: "☕️", title: "Tasty Coffee",
                               subtitle: "Treat the developer — thank you!",
                               chip: nil) { open(LicenseManager.kofiURL) }

                    supportRow(emoji: "🍕", title: "Buy a Pizza",
                               subtitle: LicenseManager.unlockSummary,
                               chip: "Unlock") { open(LicenseManager.purchaseURL) }

                    supportRow(emoji: "🙁", title: "None of these :-(",
                               subtitle: "Just start using RetroMac",
                               chip: nil) { finish() }

                    // The licence key. Its own card with a heading and a sentence of help: the
                    // bare field under the support rows was easy to miss, and a pasted key in a
                    // small system field was hard to see at all.
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill").font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.orange)
                            Text("Already have a licence key?").font(.headline)
                        }
                        Text("Paste the key from your purchase email here and click Activate. It looks like XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            TextField("XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX", text: $keyInput)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .textBackgroundColor)))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1))
                            Button(license.isValidating ? "…" : "Activate") { activateKey() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty || license.isValidating)
                        }
                        if let msg = activationMessage {
                            Label(msg, systemImage: activationSuccess == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(activationSuccess == true ? .green : .red)
                        }
                        Toggle("I already chipped in (hide this next time)", isOn: $coffeeAck)
                            .toggleStyle(.checkbox).font(.caption)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.35), lineWidth: 1))
                    .padding(.top, 4)
                    .onAppear {
                        // A key that was entered before but never validated is worth showing
                        // again, the way the Settings tab does.
                        if keyInput.isEmpty && !license.licenseKey.isEmpty { keyInput = license.licenseKey }
                    }
                }
            }
            .padding(20)
        }
    }

    private func benefitCard(_ icon: String, _ tint: Color, _ label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    private func supportRow(emoji: String, title: String, subtitle: String,
                            chip: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(emoji).font(.system(size: 24))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.10)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let chip = chip {
                    Text(chip).font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.orange))
                } else {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func open(_ urlString: String) {
        if let u = URL(string: urlString) { NSWorkspace.shared.open(u) }
    }

    private func activateKey() {
        activationMessage = nil; activationSuccess = nil
        license.activate(key: keyInput) { success, error in
            activationSuccess = success
            activationMessage = success ? "Unlocked — thank you!" : (error ?? "Activation failed")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusIndicator(granted: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle").foregroundStyle(granted ? .green : .secondary)
            Text(granted ? "Granted" : "Not yet granted").font(.caption).foregroundStyle(granted ? .primary : .secondary)
        }.padding(.top, 2)
    }

    private func checkScreenRecording() {
        Task {
            do { _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                 screenRecordingGranted = true }
            catch { screenRecordingGranted = false }
        }
    }
}

/// Fallback plain button style (avoids depending on the Settings design-system button).
private struct RMDefaultButtonStyleSafe: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 10).padding(.vertical, 4)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Controller

final class WelcomeFlowWindowController: NSObject, NSWindowDelegate {
    /// Also how the flow view finds this window to resize it per page.
    static let windowTitle = "Welcome to RetroMac"
    private var window: NSWindow?
    private var savedMenu: NSMenu?
    private var installedEditMenu = false

    /// RetroMac is an agent app with no menu bar, so Cmd+C/V/A don't reach text fields
    /// (e.g. the license-key field) unless a main menu with those key equivalents exists.
    /// Install a minimal Edit menu while this window is open; restore on close.
    private func installEditMenu() {
        guard NSApp.mainMenu == nil else { return }
        savedMenu = NSApp.mainMenu
        installedEditMenu = true
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); appItem.submenu = NSMenu(); mainMenu.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func removeEditMenu() {
        guard installedEditMenu else { return }
        NSApp.mainMenu = savedMenu
        savedMenu = nil
        installedEditMenu = false
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Compute the page set from current state and show if non-empty.
    func showIfNeeded() {
        let s = AppSettings.shared
        let lm = LicenseManager.shared
        let newVersion = !s.lastSeenVersion.isEmpty && s.lastSeenVersion != currentVersion
        let firstRun = s.lastSeenVersion.isEmpty
        let needSetup = !s.onboardingComplete

        var pages: [WelcomePage] = []
        if newVersion || firstRun { pages.append(.whatsNew) }
        if needSetup { pages += [.setupScreenRecording, .setupAccessibility] }
        // What the unlock buys, before the page that asks for the money.
        if !LicenseManager.shared.isLicensed, newVersion || firstRun || needSetup {
            pages.append(.getMore)
        }
        // Coffee: always on setup/version events (if unlicensed); otherwise honor 30-day ack
        if !lm.isLicensed {
            if needSetup || newVersion || firstRun || lm.shouldShowCoffee { pages.append(.coffee) }
        }
        guard !pages.isEmpty else { return }
        present(pages: pages)
    }

    /// Open directly at the setup pages (menu "Re-run setup").
    func showSetup() {
        present(pages: [.setupScreenRecording, .setupAccessibility])
    }

    /// Open directly at the coffee / unlock page (e.g. when a locked preset is clicked).
    func showCoffee() {
        present(pages: [.coffee])
    }

    private func present(pages: [WelcomePage]) {
        let view = WelcomeFlowView(pages: pages) { coffeeAck in
            let s = AppSettings.shared
            s.onboardingComplete = true
            s.lastSeenVersion = self.currentVersion
            if coffeeAck { s.coffeeAckDate = Date() }
        }
        let hosting = NSHostingView(rootView: view)
        // The window must follow the page's height (see WelcomePage.preferredHeight) — a
        // fixed content rect would otherwise keep every page at the tallest one's size.
        let startHeight = (pages.first ?? .whatsNew).preferredHeight

        // Reuse an existing window but ALWAYS swap in the requested pages, so e.g.
        // clicking a locked feature reliably shows the coffee/unlock page even if the
        // window was already open on a different page.
        if let window = window {
            window.contentView = hosting
            window.setContentSize(NSSize(width: 460, height: startHeight))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: startHeight),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = Self.windowTitle
        win.contentView = hosting
        win.center()
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installEditMenu()   // enable Cmd+V etc. in the license-key field
        self.window = win
    }

    func windowWillClose(_ notification: Notification) {
        // Closing via X still marks onboarding + version seen (matches old behavior)
        let s = AppSettings.shared
        s.onboardingComplete = true
        s.lastSeenVersion = currentVersion
        removeEditMenu()
        window = nil
    }
}
