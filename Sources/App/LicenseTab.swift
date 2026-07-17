import SwiftUI

struct LicenseTab: View {
    @ObservedObject private var license = LicenseManager.shared
    @State private var keyInput: String = ""
    @State private var activationMessage: String?
    @State private var activationSuccess: Bool?

    var body: some View {
        Form {
            // Status
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 32))
                            .foregroundStyle(statusColor)

                        Text(statusTitle)
                            .font(.headline)

                        Text(statusSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            // Activation
            if !license.isLicensed {
                Section("Unlock All Presets") {
                    TextField("License Key", text: $keyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    HStack {
                        Button(license.isValidating ? "Validating..." : "Activate") {
                            activateKey()
                        }
                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty || license.isValidating)

                        Spacer()

                        if let msg = activationMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(activationSuccess == true ? .green : .red)
                        }
                    }

                    Link("Get All Presets on Gumroad", destination: URL(string: LicenseManager.purchaseURL)!)
                        .font(.caption)

                    Link("Buy me a coffee on Ko-fi", destination: URL(string: LicenseManager.kofiURL)!)
                        .font(.caption)
                }
            } else {
                Section("License Details") {
                    LabeledContent("Status", value: "All Presets Unlocked")
                    if !license.licenseEmail.isEmpty {
                        LabeledContent("Email", value: license.licenseEmail)
                    }
                    LabeledContent("Key") {
                        Text(maskedKey)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Button("Deactivate License") {
                        license.deactivate()
                        keyInput = ""
                        activationMessage = nil
                        activationSuccess = nil
                    }
                    .foregroundStyle(.red)
                }
            }

            // What's included
            Section("Basic (Free)") {
                featureRow("CRT Royale Lite", free: true)
                featureRow("Sony Trinitron TV", free: true)
                featureRow("NTSC / PAL", free: true)
                featureRow("VHS / VCR Tracking", free: true)
                featureRow("macOS Aqua", free: true)
                featureRow("Retro LCD Grid", free: true)
                featureRow("Macintosh Classic", free: true)
                featureRow("Game Boy / Amber Monitor", free: true)
                featureRow("Surprise (Random Preset)", free: true)
                featureRow("Retro-Dock & Themes", free: true)
                featureRow("Television Bookmarks", free: true)
                featureRow("Per-App Presets", free: true)
                featureRow("Scanline & Reflection Overlays", free: true)
            }

            Section("Licensed") {
                featureRow("All \(PresetRegistry.builtinPresets.count) Shader Presets", free: false)
                featureRow("Custom Presets (.metal)", free: false)
                // Driven off the one premium list, so a new paid feature shows up here by
                // itself — Live Wallpaper was gated for ages and never appeared in any of
                // the three places that claim to say what the licence includes.
                ForEach(LicenseManager.premiumFeatures, id: \.name) { feature in
                    featureRow(feature.name, free: false)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .onAppear {
            if keyInput.isEmpty && !license.licenseKey.isEmpty {
                keyInput = license.licenseKey
            }
        }
    }

    // MARK: - Status Display

    private var statusIcon: String {
        license.isLicensed ? "checkmark.seal.fill" : "sparkles"
    }

    private var statusColor: Color {
        license.isLicensed ? .green : .orange
    }

    private var statusTitle: String {
        license.isLicensed ? LicenseManager.unlockedTitle : "Basic Edition"
    }

    private var statusSubtitle: String {
        if license.isLicensed { return "Thank you for supporting RetroMac!" }
        return LicenseManager.unlockSummary
    }

    private var maskedKey: String {
        let key = license.licenseKey
        if key.count > 8 {
            return String(key.prefix(4)) + "..." + String(key.suffix(4))
        }
        return key
    }

    // MARK: - Actions

    private func activateKey() {
        activationMessage = nil
        activationSuccess = nil

        license.activate(key: keyInput) { success, error in
            activationSuccess = success
            if success {
                activationMessage = "All presets unlocked!"
            } else {
                activationMessage = error ?? "Activation failed"
            }
        }
    }

    // MARK: - Feature Rows

    @ViewBuilder
    private func featureRow(_ title: String, free: Bool) -> some View {
        HStack {
            Image(systemName: free ? "checkmark.circle.fill" : "star.fill")
                .foregroundStyle(free ? .green : .orange)
                .font(.caption)
            Text(title)
                .font(.caption)
            Spacer()
            Text(free ? "Free" : "Licensed")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
