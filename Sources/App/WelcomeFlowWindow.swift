import SwiftUI
import ScreenCaptureKit

/// Pages that can appear in the unified welcome flow.
enum WelcomePage: Equatable {
    case whatsNew
    case setupScreenRecording
    case setupAccessibility
    case coffee

    /// Window height this page wants. The setup pages are a heading, two paragraphs and a
    /// button. What's New is taller than anything sensible now that it carries the previous
    /// release along, so it is capped here and scrolls the rest.
    var preferredHeight: CGFloat {
        switch self {
        case .whatsNew:                            return 700
        case .setupScreenRecording, .setupAccessibility: return 460
        case .coffee:                              return 600
        }
    }
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
                Text("Snow Leopard, properly \u{2014} with Dashboard and Expos\u{00E9}").font(.subheadline).foregroundStyle(.secondary)
            }.padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    feature("macwindow", .blue, "Snow Leopard has its own chrome",
                            "10.6 no longer borrows Cheetah\u{2019}s early-Aqua look. The title bar is measured off the original \u{2014} unified grey, flat traffic lights, the separator along the bottom \u{2014} and it comes with blue gel scrollers, period-correct icons for Chrome, iWork, Claude and ChatGPT, and the striped Macintosh HD.")
                    feature("square.grid.2x2.fill", .indigo, "Dashboard is back",
                            "The widget layer macOS dropped in Catalina, rebuilt. \u{2303}F12 brings up Clock, Calculator, Weather, Calendar, Stickies, a Google search pill and a CPU monitor. Add and remove them from the bar, drag them where you like, and they stay put.")
                    feature("rectangle.3.group.fill", .teal, "Expos\u{00E9}",
                            "Every window on the desktop, shrunk so none overlap, each card travelling from where its window actually sits. \u{2303}F9 for all of them, \u{2303}F10 for the front app \u{2014} or hold a dock icon, the way 10.6 changed that gesture to work.")
                    feature("square.stack.3d.up.fill", .orange, "Stacks, drawn the way 10.6 drew them",
                            "Applications and Downloads open as a grid with real Quick Look previews, sitting next to the Trash where they belong, and hanging from the callout nose that points back at the dock icon.")
                    feature("sparkles.tv.fill", .purple, "Desktop extras",
                            "The real Flurry screensaver, five more wallpapers (Rocks, Earth, Aurora Blue, Zebra, Stones), and an optional tint for the menu bar so a modern translucent one stops fighting the theme.")
                    feature("waveform.path.ecg", .pink, "Phosphor persistence",
                            "Afterglow across frames, applied to the signal ahead of the mask, in every Metal renderer. Bright things trail the way a real tube trails.")
                    feature("gearshape.fill", .gray, "Settings, sorted out",
                            "A Desktop tab that is actually listed in the sidebar, a frame-rate choice that offers 120 only on panels that reach it and stops being reset by the Quality picker, hotkey rows for Expos\u{00E9} and Dashboard, and a theme import that can no longer lose the theme it replaces.")

                    sectionHeader("Also in 2.7")

                    feature("desktopcomputer", .blue, "Windows 95 theme",
                            "The one that started it all: solid navy title bars, the silver 3D chrome, the clouds wallpaper and an authentic boot screen. The Start menu is period-correct too \u{2014} large icons in a narrow first level, small ones in the wider submenus, and neither Windows Update nor Log Off, because Windows 95 had neither.")
                    feature("opticaldisc", .indigo, "Fun Stuff (D:)",
                            "The CD-ROM is back on the desktop. Browse FUNSTUFF into HOVER, VIDEOS and PICTURES: music videos play in a bare title-bar window, and Clouds.exe / WINBMP.EXE set your wallpaper the way a 1995 CD-ROM would.")
                    feature("gamecontroller.fill", .green, "Hover! plays again",
                            "The Microsoft HTML5 remake of the Windows 95 classic, self-hosted and fully offline in its original pixel-graphics mode. No Wine, no emulator, no internet needed.")
                    feature("slider.horizontal.below.rectangle", .orange, "Authentic Win95/98 details",
                            "Scrollbars with a single arrow at each end, raised bevels and a dithered track. The status bar sits below its own scrollbar row, the program icon is back in the title bar, and 98/Me/XP drop the running-app dots \u{2014} their taskbars already show what is running.")
                    feature("doc.text.fill", .purple, "Readmes overhauled",
                            "Every theme\u{2019}s About This Theme is closable again, fills its window edge-to-edge, sizes itself so it needs no scrolling, and shows its artwork. Futurama finally has one too. Plus: a setting that starts you straight into your last theme.")
                }.padding(.horizontal, 24).padding(.bottom, 12)
            }
        }
    }

    private var whatsNewVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.3"
    }

    /// Divider between this release's entries and the ones carried over from the last. 2.7 was
    /// short-lived, so anyone updating from 2.6 would otherwise never be told what it brought.
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

                    // Already-supported + license key
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("I already chipped in (hide this next time)", isOn: $coffeeAck)
                            .toggleStyle(.checkbox).font(.caption)
                        HStack(spacing: 8) {
                            TextField("License key", text: $keyInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                            Button(license.isValidating ? "…" : "Activate") { activateKey() }
                                .buttonStyle(.bordered)
                                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty || license.isValidating)
                        }
                        if let msg = activationMessage {
                            Text(msg).font(.caption).foregroundStyle(activationSuccess == true ? .green : .red)
                        }
                    }.padding(.top, 4)
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
