import SwiftUI
import Carbon.HIToolbox

// MARK: - Shortcuts Tab

struct ShortcutsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(spacing: RMSpacing.section) {
                // Global hotkeys
                globalHotkeysCard

                // Two side-by-side cards
                HStack(alignment: .top, spacing: RMSpacing.xxl) {
                    menuBarCard
                    onboardingCard
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Global Hotkeys Card

    private var globalHotkeysCard: some View {
        RMCard(title: "Global hotkeys", bodyPadding: 0) {
            VStack(spacing: 0) {
                // 1. Toggle overlay
                HotkeyRow(
                    label: "Toggle overlay",
                    hint: "Turns the CRT effect on or off, system-wide.",
                    hotkeyCode: settings.hotkeyCode,
                    hotkeyModifiers: settings.hotkeyModifiers,
                    onSet: { code, mods in
                        settings.hotkeyCode = code
                        settings.hotkeyModifiers = mods
                        AppDelegate.shared?.registerHotkey()
                    },
                    onClear: {
                        settings.hotkeyCode = 0
                        settings.hotkeyModifiers = 0
                        AppDelegate.shared?.registerHotkey()
                    }
                )

                // 2. Toggle retro dock
                HotkeyRow(
                    label: "Toggle retro dock",
                    hint: nil,
                    hotkeyCode: settings.dockHotkeyCode,
                    hotkeyModifiers: settings.dockHotkeyModifiers,
                    onSet: { code, mods in
                        settings.dockHotkeyCode = code
                        settings.dockHotkeyModifiers = mods
                    },
                    onClear: {
                        settings.dockHotkeyCode = 0
                        settings.dockHotkeyModifiers = 0
                    }
                )

                // 3. Cycle effect preset
                HotkeyRow(
                    label: "Cycle effect preset",
                    hint: "Steps through the library forwards.",
                    hotkeyCode: settings.cyclePresetHotkeyCode,
                    hotkeyModifiers: settings.cyclePresetHotkeyModifiers,
                    onSet: { code, mods in
                        settings.cyclePresetHotkeyCode = code
                        settings.cyclePresetHotkeyModifiers = mods
                    },
                    onClear: {
                        settings.cyclePresetHotkeyCode = 0
                        settings.cyclePresetHotkeyModifiers = 0
                    }
                )

                // 4. Bump intensity
                HotkeyRow(
                    label: "Bump intensity \u{00B1}",
                    hint: "\u{2303}\u{2325}+ and \u{2303}\u{2325}\u{2212} change the active preset\u{2019}s strength.",
                    hotkeyCode: settings.bumpIntensityHotkeyCode,
                    hotkeyModifiers: settings.bumpIntensityHotkeyModifiers,
                    onSet: { code, mods in
                        settings.bumpIntensityHotkeyCode = code
                        settings.bumpIntensityHotkeyModifiers = mods
                    },
                    onClear: {
                        settings.bumpIntensityHotkeyCode = 0
                        settings.bumpIntensityHotkeyModifiers = 0
                    }
                )

                // 5. Toggle menu bar visibility
                HotkeyRow(
                    label: "Toggle menu bar visibility",
                    hint: nil,
                    hotkeyCode: settings.menuBarToggleHotkeyCode,
                    hotkeyModifiers: settings.menuBarToggleHotkeyModifiers,
                    onSet: { code, mods in
                        settings.menuBarToggleHotkeyCode = code
                        settings.menuBarToggleHotkeyModifiers = mods
                    },
                    onClear: {
                        settings.menuBarToggleHotkeyCode = 0
                        settings.menuBarToggleHotkeyModifiers = 0
                    }
                )

                // 6. Screenshot with shader
                HotkeyRow(
                    label: "Screenshot with shader",
                    hint: "Captures the screen including the active CRT effect.",
                    hotkeyCode: settings.screenshotHotkeyCode,
                    hotkeyModifiers: settings.screenshotHotkeyModifiers,
                    isLast: true,
                    onSet: { code, mods in
                        settings.screenshotHotkeyCode = code
                        settings.screenshotHotkeyModifiers = mods
                        AppDelegate.shared?.registerHotkey()
                    },
                    onClear: {
                        settings.screenshotHotkeyCode = 0
                        settings.screenshotHotkeyModifiers = 0
                        AppDelegate.shared?.registerHotkey()
                    }
                )
            }
        }
    }

    // MARK: - Menu Bar Card

    private var menuBarCard: some View {
        RMCard(title: "Menu bar", bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Hide system menu bar when overlay is on") {
                    Toggle("", isOn: $settings.hideMenuBar)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                }
                RMRow(label: "Hide desktop icons when overlay is on", isLast: true) {
                    Toggle("", isOn: $settings.hideDesktopIcons)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                }
            }
        }
    }

    // MARK: - Onboarding Card

    private var onboardingCard: some View {
        RMCard(title: "Onboarding", bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "Show tips on hotkey conflicts") {
                    Toggle("", isOn: $settings.showHotkeyConflictTips)
                        .toggleStyle(.switch)
                        .tint(.rmAccent)
                        .labelsHidden()
                }
                RMRow(label: "Re-run setup assistant", isLast: true) {
                    Button("Open\u{2026}") {
                        AppDelegate.shared?.showOnboarding()
                    }
                    .buttonStyle(RMDefaultButtonStyle())
                }
            }
        }
    }
}

// MARK: - Hotkey Row (with key recording)

private struct HotkeyRow: View {
    let label: String
    let hint: String?
    let hotkeyCode: UInt32
    let hotkeyModifiers: UInt32
    var isLast: Bool = false
    let onSet: (UInt32, UInt32) -> Void
    let onClear: () -> Void

    @State private var isRecording = false

    private var isSet: Bool { hotkeyCode != 0 || hotkeyModifiers != 0 }

    private var keySymbols: [String] {
        var keys: [String] = []
        if hotkeyModifiers & UInt32(controlKey) != 0 { keys.append("\u{2303}") }
        if hotkeyModifiers & UInt32(optionKey) != 0 { keys.append("\u{2325}") }
        if hotkeyModifiers & UInt32(shiftKey) != 0 { keys.append("\u{21E7}") }
        if hotkeyModifiers & UInt32(cmdKey) != 0 { keys.append("\u{2318}") }
        keys.append(AppSettings.keyName(for: hotkeyCode))
        return keys
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .tracking(-0.05)
                        .foregroundColor(.rmTextPrimary)
                    if let hint = hint {
                        Text(hint)
                            .font(.rmSecondary)
                            .foregroundColor(.rmTextSecondary)
                            .lineSpacing(1.4)
                    }
                }

                Spacer(minLength: 16)

                if isRecording {
                    // Recording state — pulsing indicator
                    HStack(spacing: 6) {
                        Text("Press shortcut\u{2026}")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.rmAccent)

                        Button("Cancel") {
                            isRecording = false
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.rmTextSecondary)
                    }
                    .onAppear { startRecording() }
                } else if isSet {
                    HStack(spacing: 3) {
                        RMHotkeyChip(keys: keySymbols)

                        // Clear button
                        Button(action: onClear) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.rmTextTertiary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 20, height: 20)
                    }
                    .onTapGesture {
                        isRecording = true
                    }
                } else {
                    Button("Set shortcut\u{2026}") {
                        isRecording = true
                    }
                    .buttonStyle(RMDefaultButtonStyle())
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, RMSpacing.card)

            if !isLast {
                Rectangle()
                    .fill(Color.rmDivider)
                    .frame(height: 1)
                    .padding(.horizontal, RMSpacing.card)
            }
        }
    }

    // MARK: - Key Recording

    private func startRecording() {
        // Listen for the next key press (local monitor — works when our window is active)
        var localMonitor: Any?
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Convert Cocoa modifiers to Carbon modifiers
            let carbonMods = Self.carbonModifiers(from: event.modifierFlags)

            // Require at least one modifier (Ctrl, Opt, Cmd, Shift) for a valid shortcut
            if carbonMods == 0 {
                // Escape cancels recording
                if event.keyCode == 53 { // Escape
                    DispatchQueue.main.async {
                        isRecording = false
                    }
                    if let m = localMonitor { NSEvent.removeMonitor(m) }
                    return nil // swallow
                }
                return event // ignore plain keys, let them through
            }

            let keyCode = UInt32(event.keyCode)

            DispatchQueue.main.async {
                onSet(keyCode, carbonMods)
                isRecording = false
            }

            if let m = localMonitor { NSEvent.removeMonitor(m) }
            return nil // swallow the key event
        }
    }

    /// Convert Cocoa NSEvent.ModifierFlags to Carbon modifier mask
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }
}
