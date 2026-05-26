import SwiftUI
import ScreenCaptureKit

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case screenRecording
    case accessibility
    case done
}

struct OnboardingView: View {
    @State private var step: OnboardingStep = .welcome
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .welcome:
                welcomeStep
            case .screenRecording:
                screenRecordingStep
            case .accessibility:
                accessibilityStep
            case .done:
                doneStep
            }
        }
        .frame(width: 420, height: 320)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tv.and.mediabox")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Welcome to RetroMac")
                .font(.title2.bold())
            Text("RetroMac needs two permissions to apply retro shader effects to your screen.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Spacer()
            nextButton("Get Started") { step = .screenRecording }
        }
        .padding()
    }

    private var screenRecordingStep: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "record.circle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Screen Recording")
                .font(.title3.bold())
            Text("RetroMac captures your screen to apply real-time shader effects. No data is recorded or stored.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            .padding(.top, 4)

            statusIndicator(granted: screenRecordingGranted)

            Spacer()
            nextButton("Continue") { step = .accessibility }
        }
        .padding()
        .onAppear { checkScreenRecording() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            if !screenRecordingGranted { checkScreenRecording() }
        }
    }

    private func checkScreenRecording() {
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                screenRecordingGranted = true
            } catch {
                screenRecordingGranted = false
            }
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "hand.raised.circle")
                .font(.system(size: 36))
                .foregroundStyle(.blue)
            Text("Accessibility")
                .font(.title3.bold())
            Text("Needed for global hotkeys and hiding the system dock/menu bar. Optional but recommended.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button("Check Permission") {
                    accessibilityGranted = AXIsProcessTrusted()
                }
            }
            .padding(.top, 4)

            statusIndicator(granted: accessibilityGranted)

            Spacer()
            nextButton("Continue") { step = .done }
        }
        .padding()
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("You're All Set!")
                .font(.title2.bold())
            Text("Use the menu bar icon to toggle effects, change presets, and configure your retro dock.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Spacer()
            Button("Start RetroMac") {
                AppSettings.shared.onboardingComplete = true
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 20)
        }
        .padding()
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusIndicator(granted: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
            Text(granted ? "Granted" : "Not yet granted")
                .font(.caption)
                .foregroundStyle(granted ? .primary : .secondary)
        }
        .padding(.top, 2)
    }

    private func nextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 20)
    }
}

final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: OnboardingView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "RetroMac Setup"
        window.contentView = hostingView
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    // Mark onboarding complete even if the user closes via the X button
    func windowWillClose(_ notification: Notification) {
        AppSettings.shared.onboardingComplete = true
    }
}
