import Sparkle
import SwiftUI

struct AboutTab: View {
    @ObservedObject private var license = LicenseManager.shared
    @State private var keyInput: String = ""
    @State private var activationMessage: String?
    @State private var activationSuccess: Bool?
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    private let shaderCredits: [(name: String, author: String, license: String)] = [
        ("zfast-crt", "Greg Hogan", "GPL-2.0"),
        ("crt-lottes", "Timothy Lottes", "MIT"),
        ("crt-geom", "cgwg / Themaister", "GPL-2.0"),
        ("crt-royale-lite", "TroggleMonkey", "GPL-2.0"),
        ("crt-hyllian-glow", "Hyllian", "MIT"),
        ("crt-gdv-mini-ultra", "Guest.r", "GPL-2.0"),
        ("newpixie-crt", "NewPixie / Shadertoy community", "CC BY-NC-SA 3.0"),
        ("trinitron-tv", "Inspired by Sony Trinitron CRTs", "Original"),
        ("vcr-tracking", "Inspired by VHS aesthetics", "Original"),
        ("cinema-film", "Inspired by analog film processing", "Original"),
    ]

    var body: some View {
        ScrollView {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(nsImage: Self.appIcon)
                                .resizable()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)

                            Text("RetroMac")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Real-time retro shader overlay for macOS")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Version \(appVersion)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                Section("Developer") {
                    LabeledContent("Developer", value: "Maik Klotz")
                    LabeledContent("Website") {
                        Link("klotzbrocken.de", destination: URL(string: "https://www.klotzbrocken.de")!)
                    }
                    LabeledContent("Contact") {
                        Link("info@klotzbrocken.de", destination: URL(string: "mailto:info@klotzbrocken.de")!)
                    }
                    Text("Questions? Write me an email!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Shader Credits") {
                    Text("Shader presets are original Metal implementations inspired by the following open-source projects from the libretro / RetroArch community:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(shaderCredits, id: \.name) { credit in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(credit.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(credit.author)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(credit.license)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.primary.opacity(0.06))
                                )
                        }
                    }

                    Link("libretro/glsl-shaders on GitHub",
                         destination: URL(string: "https://github.com/libretro/glsl-shaders")!)
                        .font(.caption)
                }

                Section("Theme Disclaimer") {
                    Text("Theme icons and wallpapers depicting macOS and Windows interfaces are trademarks and copyrighted material of Apple Inc. and Microsoft Corporation respectively. They are included for personal, non-commercial use to recreate the look and feel of classic operating systems. RetroMac is not affiliated with or endorsed by Apple or Microsoft.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Resources") {
                    Link("amanchokshi/retro-icons on GitHub",
                         destination: URL(string: "https://github.com/amanchokshi/retro-icons")!)
                        .font(.caption)
                    Text("Sleek Retro theme icons by Aman Chokshi.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("jcherven/BeOS-r5-Icons on GitHub",
                         destination: URL(string: "https://github.com/jcherven/BeOS-r5-Icons")!)
                        .font(.caption)
                    Text("BeOS theme icons by Josh Cherven.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("marchmountain/Windows-XP-Icon-Pack on GitHub",
                         destination: URL(string: "https://github.com/marchmountain/-Windows-XP-High-Resolution-Icon-Pack")!)
                        .font(.caption)
                    Text("Windows XP theme icons.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("kfh83/ExplorerEx on GitHub",
                         destination: URL(string: "https://github.com/kfh83/ExplorerEx")!)
                        .font(.caption)
                    Text("Windows XP Luna Blue theme reference.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Open Source") {
                    Text("RetroMac uses the following Apple frameworks: Metal, MetalKit, ScreenCaptureKit, AVKit, WebKit, AppKit, SwiftUI. No third-party libraries are used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: - License
                Section("License") {
                    HStack {
                        Image(systemName: license.isLicensed ? "checkmark.seal.fill" : "sparkles")
                            .font(.system(size: 20))
                            .foregroundStyle(license.isLicensed ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(license.isLicensed ? "All Presets Unlocked" : "Basic Edition")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(license.isLicensed ? "Thank you for supporting RetroMac!" : "Unlock all \(PresetRegistry.builtinPresets.count) presets + custom shaders")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    if !license.isLicensed {
                        TextField("License Key", text: $keyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))

                        HStack {
                            Button(license.isValidating ? "Validating..." : "Activate") {
                                activateKey()
                            }
                            .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty || license.isValidating)
                            .font(.caption)

                            Spacer()

                            if let msg = activationMessage {
                                Text(msg)
                                    .font(.caption2)
                                    .foregroundStyle(activationSuccess == true ? .green : .red)
                            }
                        }

                        Link("Get All Presets on Gumroad", destination: URL(string: LicenseManager.purchaseURL)!)
                            .font(.caption)

                        Link("Buy me a coffee on Ko-fi", destination: URL(string: LicenseManager.kofiURL)!)
                            .font(.caption)
                    } else {
                        if !license.licenseEmail.isEmpty {
                            LabeledContent("Email") {
                                Text(license.licenseEmail)
                                    .font(.caption)
                            }
                        }
                        LabeledContent("Key") {
                            Text(maskedKey)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Button("Deactivate License") {
                            license.deactivate()
                            keyInput = ""
                            activationMessage = nil
                            activationSuccess = nil
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }

                Section("Updates") {
                    HStack {
                        Button("Check for Updates…") {
                            updater.checkForUpdates()
                        }
                        .disabled(!updater.canCheckForUpdates)
                        Spacer()
                        Toggle("Automatic Updates", isOn: Binding(
                            get: { updater.automaticallyChecksForUpdates },
                            set: { updater.automaticallyChecksForUpdates = $0 }
                        ))
                        .font(.caption)
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Text("\u{00A9} 2025 \u{2013} 2026 Maik Klotz. All rights reserved.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(.top, 8)
        .onAppear {
            if keyInput.isEmpty && !license.licenseKey.isEmpty {
                keyInput = license.licenseKey
            }
        }
    }

    private static var appIcon: NSImage {
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: path) {
            return icon
        }
        return NSApp.applicationIconImage
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var maskedKey: String {
        let key = license.licenseKey
        if key.count > 8 {
            return String(key.prefix(4)) + "..." + String(key.suffix(4))
        }
        return key
    }

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

}
