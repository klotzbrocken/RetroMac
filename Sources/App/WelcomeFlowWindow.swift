import SwiftUI
import ScreenCaptureKit

/// Pages that can appear in the unified welcome flow.
enum WelcomePage: Equatable {
    case whatsNew
    case getMore
    case setupScreenRecording
    case setupAccessibility
    case coffee

    /// One size for every page here AND for the Setup Assistant, taken from What's New because
    /// that is the tallest and the least willing to shrink. The two wizards run back to back on
    /// a first launch, and they used to resize between and between each other, which read as two
    /// unrelated windows rather than one flow. The sparse pages have more air now; that is the
    /// trade.
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
                Text("What's New in RetroMac \(whatsNewVersion)").font(.title2.bold())
                Text("Mac OS 9 as it was, a title bar over every window, and a dock that stays smooth")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    feature("menubar.rectangle", .blue, "Mac OS 9 (authentic)",
                            "A second Mac OS 9, next to the Classic theme, laid out the way the machine was: no dock. The Control Strip at the bottom edge holds the system \u{2014} network, battery, media bay, sharing, keychain, colour depth, monitor resolution (it really switches, with the old keep-or-revert question), printer, sound volume with the slider of its day, sound source, video mirroring \u{2014} and rolls in and out under its tab. Option-drag rearranges the modules or moves the strip.")
                    feature("apple.logo", .gray, "\u{2026} with the menus of the day",
                            "The Application menu at the right end of the menu bar switches programs, the front one\u{2019}s icon and name beside it. The Apple menu opens the menu of the day \u{2014} About This Computer, Applications, Control Panels, Recent Applications, Recent Documents, Sherlock 2 \u{2014} each pointed at what macOS has now. All of it drawn in Platinum, with Chicago as a bitmap face; the desktop holds Macintosh HD, Applications and the Trash on the pale label plate. A minimised window does not shrink into a corner: it zooms away to the top of the desktop and is gone.")
                    feature("macwindow", .purple, "Experiment: title bars in theme style",
                            "Under Themes \u{25B8} System integration: a Platinum or Luna title bar over every real window, or Aqua and Snow Leopard traffic lights in place of the modern ones. RetroMac\u{2019}s own panel above the window, not a change to the app; close, minimise, zoom the way the era did and dragging all go through Accessibility, and apps can be left alone. An experiment: a toolbar that shares the title bar (Safari, Finder) loses its top edge, and a window the size of the screen gets no bar.")
                    feature("dock.rectangle", .green, "The dock stays smooth",
                            "With the title bars on, the dock\u{2019}s magnification juddered: the pointer was watched through a global mouse monitor, and from the first change of front app on, the WindowServer handed the dock its mouse moves in bursts. The monitor is gone. The Aqua dock also stopped looking every app\u{2019}s name up on disk on every mouse move, and the dock\u{2019}s own auto-hide no longer watches the pointer that way either.")
                    feature("wrench.and.screwdriver.fill", .gray, "And a long list of fixes",
                            "The \u{201C}Classic window corners\u{201D} hint no longer traps the Windows Me and Mac OS 9 boot animation in a loop. The lights and the frame leave with a window that is minimised or closed from the bar. A new Chrome tab no longer buries the lights, and the menu-bar Apple logo stopped blinking. A crash on a theme that keeps the menu bar runs to the end. The boot screen can always be clicked away, and a stuck switch cannot lock the Mac. Paint, Solitaire, Minesweeper, Internet Explorer and 3D Pinball open again from 98.js.org.")

                    sectionHeader("Also in 2.8")

                    feature("desktopcomputer", .blue, "Windows Me, gone over in detail",
                            "The animated Me boot logo, three original wallpapers, Defrag as its own program, and folder windows that are Explorer now \u{2014} back, forward, up, an address bar, the info panel and a status line.")
                    feature("exclamationmark.triangle.fill", .red, "Retro Glitches & Crashes",
                            "Failure, in period: the Windows 9x blue screen, the Illegal Operation dialog, the XP and 7 stop error, the Mac OS bomb. Nothing actually crashes \u{2014} the frozen desktop is a photograph of itself, laid on top. By hand, or on a schedule from very rare to chaotic.")
                    feature("photo.on.rectangle.angled", .purple, "Live Wallpaper covers the whole desktop",
                            "One switch runs the selected shader over the desktop picture, RetroMac\u{2019}s own desktop icons, the retro dock and an open start menu in a single pass. Application windows are never touched.")
                    feature("gamecontroller.fill", .green, "The Game Library",
                            "A cover gallery for everything RetroMac can start: it installs the engine, finds the copy in your Steam library, and fetches what the rights holder released for sharing \u{2014} Freedoom and the shareware episodes of Doom, Heretic, Duke Nukem 3D, Quake, Quake II and Shadow Warrior.")
                    feature("square.grid.2x2.fill", .indigo, "Snow Leopard chrome, Dashboard, Expos\u{00E9}, phosphor persistence",
                            "10.6 measured off the original; the widget layer macOS dropped in Catalina, rebuilt (\u{2303}F12); every window shrunk so none overlap (\u{2303}F9, \u{2303}F10, or hold a dock icon); afterglow across frames in every Metal renderer.")

                }.padding(.horizontal, 24).padding(.bottom, 12)
            }
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
