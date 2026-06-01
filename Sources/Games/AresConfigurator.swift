import Foundation

/// Configures ares emulator settings before launch.
/// Ensures keyboard bindings are set and Defocus mode allows background input.
final class AresConfigurator {
    static let shared = AresConfigurator()
    private init() {}

    private var settingsPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/ares/settings.bml"
    }

    /// Configure ares settings before launching a ROM.
    /// - Sets default keyboard bindings if none are configured
    /// - Sets Defocus to Allow so input works with shader overlay on top
    func configureIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsPath) else {
            print("[AresConfig] settings.bml not found — ares may not have been run yet")
            return
        }

        guard var content = try? String(contentsOfFile: settingsPath, encoding: .utf8) else {
            print("[AresConfig] Could not read settings.bml")
            return
        }

        var changed = false

        // Fix Defocus: Pause → Defocus: Allow
        if content.contains("Defocus: Pause") {
            content = content.replacingOccurrences(of: "Defocus: Pause", with: "Defocus: Allow")
            changed = true
            print("[AresConfig] Set Defocus: Allow")
        }

        // Check if keyboard bindings are empty (all VirtualPad1 entries are `;;`)
        if needsKeyboardBindings(content) {
            content = applyDefaultKeyboardBindings(content)
            changed = true
            print("[AresConfig] Applied default keyboard bindings")
        }

        if changed {
            do {
                try content.write(toFile: settingsPath, atomically: true, encoding: .utf8)
                print("[AresConfig] Saved updated settings.bml")
            } catch {
                print("[AresConfig] Failed to save settings.bml: \(error.localizedDescription)")
            }
        } else {
            print("[AresConfig] Settings already configured")
        }
    }

    // MARK: - Keyboard Bindings

    /// Check if VirtualPad1 has any real bindings (not just `;;`)
    private func needsKeyboardBindings(_ content: String) -> Bool {
        let lines = content.components(separatedBy: "\n")
        var inVirtualPad1 = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "VirtualPad1" {
                inVirtualPad1 = true
                continue
            }
            // Exited VirtualPad1 section (next top-level key)
            if inVirtualPad1 && !line.hasPrefix("  ") && !trimmed.isEmpty {
                break
            }
            if inVirtualPad1 && trimmed.contains(": ") {
                let value = trimmed.components(separatedBy: ": ").last ?? ""
                // If any binding has a real value (not just `;;`), bindings exist
                if value != ";;" && !value.isEmpty {
                    return false
                }
            }
        }
        return true
    }

    /// Replace VirtualPad1 empty bindings with default keyboard layout.
    ///
    /// Layout (SNES-style, works for all ares systems):
    ///   D-Pad: Arrow keys
    ///   A (South): X
    ///   B (East): Z
    ///   X (West): S
    ///   Y (North): A
    ///   L: Q
    ///   R: W
    ///   Start: Return/Enter
    ///   Select: Right Shift
    ///
    /// ares keyboard binding format: `0x1/0/<keyID>;;`
    ///   0x1 = keyboard device (path=0, vendor=0x0000, product=0x0001)
    ///   0 = HID::Keyboard::GroupID::Button
    ///   keyID = index from ruby/input/keyboard/quartz.cpp
    private func applyDefaultKeyboardBindings(_ content: String) -> String {
        // Key IDs from ares source (ruby/input/keyboard/quartz.cpp)
        let bindings: [(key: String, value: String)] = [
            ("Pad.Up",         "0x1/0/92;;"),    // Up arrow
            ("Pad.Down",       "0x1/0/93;;"),    // Down arrow
            ("Pad.Left",       "0x1/0/94;;"),    // Left arrow
            ("Pad.Right",      "0x1/0/95;;"),    // Right arrow
            ("Select",         "0x1/0/99;;"),     // Left Shift
            ("Start",          "0x1/0/97;;"),     // Return/Enter
            ("A..South",       "0x1/0/63;;"),     // X key
            ("B..East",        "0x1/0/65;;"),     // Z key
            ("X..West",        "0x1/0/58;;"),     // S key
            ("Y..North",       "0x1/0/40;;"),     // A key
            ("L-Bumper",       "0x1/0/56;;"),     // Q key
            ("R-Bumper",       "0x1/0/62;;"),     // W key
        ]

        var lines = content.components(separatedBy: "\n")
        var inVirtualPad1 = false

        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed == "VirtualPad1" {
                inVirtualPad1 = true
                continue
            }
            if inVirtualPad1 && !lines[i].hasPrefix("  ") && !trimmed.isEmpty {
                break
            }
            if inVirtualPad1 {
                for binding in bindings {
                    if trimmed.hasPrefix("\(binding.key):") {
                        lines[i] = "  \(binding.key): \(binding.value)"
                        break
                    }
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}
