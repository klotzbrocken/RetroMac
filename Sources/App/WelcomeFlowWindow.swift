import SwiftUI
import ScreenCaptureKit

/// Pages that can appear in the unified welcome flow.
enum WelcomePage: Equatable {
    case whatsNew
    case setupWelcome
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
                case .setupWelcome: setupWelcomePage
                case .setupScreenRecording: screenRecordingPage
                case .setupAccessibility: accessibilityPage
                case .coffee: coffeePage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            navBar
        }
        .frame(width: 440, height: 460)
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
                Text("What's New in RetroMac").font(.title2.bold())
                Text("Themes, Program Manager, SGI desktop & more").font(.subheadline).foregroundStyle(.secondary)
            }.padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    feature("desktopcomputer", .cyan, "Retro Desktops", "Windows 3.1 Program Manager & SGI IRIX desktops — authentic windows, menus, and icons.")
                    feature("paintpalette.fill", .pink, "More Themes", "Mac OS 9, Windows XP, BeOS, OS/2 Warp and more — each with matching wallpapers and shaders.")
                    feature("camera.fill", .purple, "Screenshot with Shader", "Capture the screen with the active CRT/VHS effect baked in, via a global hotkey.")
                    feature("gamecontroller.fill", .green, "Retro Games", "Drop ROMs to play with CRT shaders; native Quake engines included.")
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

    private var setupWelcomePage: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tv.and.mediabox").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Welcome to RetroMac").font(.title2.bold())
            Text("RetroMac needs two permissions to apply retro shader effects to your screen.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 40)
            Spacer()
        }.padding()
    }

    private var screenRecordingPage: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "record.circle").font(.system(size: 36)).foregroundStyle(.orange)
            Text("Screen Recording").font(.title3.bold())
            Text("RetroMac captures your screen to apply real-time shader effects. No data is recorded or stored.")
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
        VStack(spacing: 16) {
            VStack(spacing: 5) {
                Image(systemName: "heart").font(.system(size: 26)).foregroundStyle(.secondary).padding(.top, 26)
                Text("Enjoying RetroMac?").font(.title3.bold())
                Text("It's free. If you'd like to support it — no pressure.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if license.isLicensed {
                Label("License active — everything unlocked", systemImage: "checkmark.seal.fill")
                    .font(.body).foregroundStyle(.green)
                Spacer()
            } else {
                VStack(spacing: 10) {
                    Button { if let u = URL(string: LicenseManager.kofiURL) { NSWorkspace.shared.open(u) } } label: {
                        Label("Buy me a coffee", systemImage: "cup.and.saucer.fill").frame(maxWidth: .infinity)
                    }.controlSize(.large).buttonStyle(.bordered)

                    Button { if let u = URL(string: LicenseManager.purchaseURL) { NSWorkspace.shared.open(u) } } label: {
                        Label("Unlock all presets, webcam & custom shaders", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }.controlSize(.large).buttonStyle(.borderedProminent)
                }.padding(.horizontal, 36)

                Divider().padding(.horizontal, 36)

                VStack(spacing: 7) {
                    Text("Already have a key?").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("License key", text: $keyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, design: .monospaced))
                        Button(license.isValidating ? "…" : "Activate") { activateKey() }
                            .buttonStyle(.bordered)
                            .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty || license.isValidating)
                    }
                    if let msg = activationMessage {
                        Text(msg).font(.caption).foregroundStyle(activationSuccess == true ? .green : .red)
                    }
                    Toggle("I already donated", isOn: $coffeeAck).toggleStyle(.checkbox).font(.caption)
                }.padding(.horizontal, 36)
                Spacer(minLength: 6)
            }
        }
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
        if needSetup { pages += [.setupWelcome, .setupScreenRecording, .setupAccessibility] }
        // Coffee: always on setup/version events (if unlicensed); otherwise honor 30-day ack
        if !lm.isLicensed {
            if needSetup || newVersion || firstRun || lm.shouldShowCoffee { pages.append(.coffee) }
        }
        guard !pages.isEmpty else { return }
        present(pages: pages)
    }

    /// Open directly at the setup pages (menu "Re-run setup").
    func showSetup() {
        present(pages: [.setupWelcome, .setupScreenRecording, .setupAccessibility])
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
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 460),
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
