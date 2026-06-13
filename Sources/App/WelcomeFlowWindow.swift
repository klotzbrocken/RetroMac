import SwiftUI
import ScreenCaptureKit

/// Pages that can appear in the unified welcome flow.
enum WelcomePage: Equatable {
    case whatsNew
    case setupScreenRecording
    case setupAccessibility
    case coffee
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
        .frame(width: 460, height: 560)
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
                Text("What's New in RetroMac 1.8").font(.title2.bold())
                Text("New Special Themes, boot screens & screensavers").font(.subheadline).foregroundStyle(.secondary)
            }.padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    feature("sparkles", .cyan, "New Special Themes — true to the originals",
                            "Windows 98 (with classic games and sheep.exe!), Windows XP, and Mac OS X with its glossy Aqua look — plus classic apps like Internet Explorer, Notepad and Paint.")
                    feature("play.tv", .blue, "Boot Screens",
                            "Authentic startup videos play when you switch to Windows XP, Windows 98 or Mac OS 9 — click to skip to the desktop.")
                    feature("display", .purple, "Classic Screensavers",
                            "A per-theme screensaver: 3D Pipes, FlowerBox, Flying Toasters and Flurry — pick yours in Settings ▸ Screensaver.")
                    feature("arrow.down.right.and.arrow.up.left.rectangle", .orange, "Smarter Minimize",
                            "Windows now minimize into the themed dock instead of the system Dock.")
                    feature("gauge.with.dots.needle.67percent", .green, "New Widgets & lots of fixes",
                            "CPU Monitor and Desktop Clock widgets, plus widget, dock and stability fixes throughout.")
                }.padding(.horizontal, 24).padding(.bottom, 12)
            }
        }
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
                        Text("No ads, no tracking, no feature locks. Optional support helps the developer keep improving the app.")
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
                               subtitle: "Unlock all presets & Webcam Mode",
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
    private var window: NSWindow?

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

        // Reuse an existing window but ALWAYS swap in the requested pages, so e.g.
        // clicking a locked feature reliably shows the coffee/unlock page even if the
        // window was already open on a different page.
        if let window = window {
            window.contentView = hosting
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Welcome to RetroMac"
        win.contentView = hosting
        win.center()
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    func windowWillClose(_ notification: Notification) {
        // Closing via X still marks onboarding + version seen (matches old behavior)
        let s = AppSettings.shared
        s.onboardingComplete = true
        s.lastSeenVersion = currentVersion
        window = nil
    }
}
