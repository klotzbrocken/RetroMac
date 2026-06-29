import Sparkle
import SwiftUI

/// Live view of the captured diagnostics log with Copy / Save (About → Diagnostics).
struct DiagnosticsSectionView: View {
    @State private var text = DiagnosticsLog.shared.snapshot()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(text.isEmpty ? "No log yet." : text)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .frame(height: 170)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))

            HStack {
                Button("Refresh") { text = DiagnosticsLog.shared.snapshot() }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(DiagnosticsLog.shared.fullReport(), forType: .string)
                }
                Button("Save\u{2026}") { saveReport() }
                Spacer()
            }
            .font(.caption)
        }
        .onReceive(NotificationCenter.default.publisher(for: DiagnosticsLog.didChange)) { _ in
            text = DiagnosticsLog.shared.snapshot()
        }
    }

    private func saveReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "RetroMac-diagnostics.txt"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            try? DiagnosticsLog.shared.fullReport().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct AboutTab: View {
    @ObservedObject private var license = LicenseManager.shared
    @State private var keyInput: String = ""
    @State private var activationMessage: String?
    @State private var activationSuccess: Bool?
    @State private var autoCheck: Bool
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _autoCheck = State(initialValue: updater.automaticallyChecksForUpdates)
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
        ("joel-gdv-ntsc", "Joel (Special Thanks)", "Contributed"),
        ("retro-crisis", "Retro Crisis (inspired) — Guest.r, crt-guest-advanced-ntsc", "GPL-2.0"),
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

                Section("Software Updates") {
                    HStack {
                        Button("Check for Updates…") { updater.checkForUpdates() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!updater.canCheckForUpdates)
                        Spacer()
                        if let last = updater.lastUpdateCheckDate {
                            Text("Last checked \(last.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Automatically check for updates", isOn: $autoCheck)
                        .onChange(of: autoCheck) { updater.automaticallyChecksForUpdates = $0 }
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

                // MARK: - License (between Developer and Shader Credits)
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

                Section("Privacy & Offline") {
                    Text("RetroMac works fully offline — every theme (dock, wallpaper, menu bar, icons, window chrome) is bundled and rendered locally; no constant internet connection is required. The network is only used for a few optional extras: the classic in-window web apps in the Windows themes (loaded on demand, nothing bundled), the retro TV browser, the desktop \u{201C}sheep\u{201D} pet sprites (fetched once, then cached), and checking for app updates. RetroMac does not track you or send personal data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Theme Disclaimer") {
                    Text("Theme icons and wallpapers depicting macOS and Windows interfaces are trademarks and copyrighted material of Apple Inc. and Microsoft Corporation respectively. They are included for personal, non-commercial use to recreate the look and feel of classic operating systems. RetroMac is not affiliated with or endorsed by Apple or Microsoft.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("DOOM Theme Credits") {
                    Text("DOOM® and DOOM® II are trademarks of id Software LLC, a ZeniMax Media company. The “Maiks Favourite II” theme uses DOOM character sprites (Doom Slayer, Lost Soul) and is a fan-made tribute, included for personal, non-commercial use. RetroMac is not affiliated with, sponsored by, or endorsed by id Software, Bethesda Softworks, or ZeniMax Media.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Doom Slayer (8-Bit) custom sprite sheet via The Spriters Resource / DOOM Customs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Lost Soul sprites ripped by Dolphman. Original artwork © id Software / Bethesda.")
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

                    Link("mRB0/many-windows-3.1-icons-in-png-format on GitHub",
                         destination: URL(string: "https://github.com/mRB0/many-windows-3.1-icons-in-png-format")!)
                        .font(.caption)
                    Text("Windows 3.1 Program Manager icons.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("rann01/IRIX-tiles on GitHub",
                         destination: URL(string: "https://github.com/rann01/IRIX-tiles")!)
                        .font(.caption)
                    Text("SGI IRIX desktop wallpaper tiles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("SGI IRIX icon pack by darkdoomer (DeviantArt)",
                         destination: URL(string: "https://www.deviantart.com/darkdoomer")!)
                        .font(.caption)
                    Text("SGI IRIX theme application icons.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Web Apps & Desktop Extras") {
                    Link("Bored-Entertainment/98.js on GitHub",
                         destination: URL(string: "https://github.com/Bored-Entertainment/98.js")!)
                        .font(.caption)
                    Text("Classic Windows apps & screensavers (Internet Explorer, Notepad, Paint, Minesweeper, Solitaire, 3D Pipes, FlowerBox) used in the Windows XP & 98 themes — loaded at runtime, nothing bundled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("Adrianotiger/desktopPet on GitHub",
                         destination: URL(string: "https://github.com/Adrianotiger/desktopPet")!)
                        .font(.caption)
                    Text("eSheep desktop pet (GPL) — original sprite artwork fetched & cached at runtime for sheep.exe on the Windows themes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("nestoris/Win98SE on GitHub",
                         destination: URL(string: "https://github.com/nestoris/Win98SE")!)
                        .font(.caption)
                    Text("Windows 98 SE start-menu icons.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("robertventurini/FlyingToasters on GitHub",
                         destination: URL(string: "https://github.com/robertventurini/FlyingToasters")!)
                        .font(.caption)
                    Text("After Dark “Flying Toasters” artwork (MIT) — basis for the Mac OS 9 screensaver.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Bundled Game & Libraries") {
                    Link("ebuc99/pacman on GitHub",
                         destination: URL(string: "https://github.com/ebuc99/pacman")!)
                        .font(.caption)
                    Text("Pac-Man clone (GPLv2) — bundled & built from source as the default game.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("libsdl-org/SDL on GitHub",
                         destination: URL(string: "https://github.com/libsdl-org/SDL")!)
                        .font(.caption)
                    Text("SDL2 — render/input layer for the bundled Pac-Man.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("sparkle-project/Sparkle on GitHub",
                         destination: URL(string: "https://github.com/sparkle-project/Sparkle")!)
                        .font(.caption)
                    Text("Sparkle — secure automatic app updates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Game Engines (user-installed)") {
                    Link("ZDoom/gzdoom on GitHub",
                         destination: URL(string: "https://github.com/ZDoom/gzdoom")!)
                        .font(.caption)
                    Link("ZDoom/Raze on GitHub",
                         destination: URL(string: "https://github.com/ZDoom/Raze")!)
                        .font(.caption)
                    Link("Novum/vkQuake on GitHub",
                         destination: URL(string: "https://github.com/Novum/vkQuake")!)
                        .font(.caption)
                    Text("Optional external engines RetroMac can launch with CRT shaders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Open Source") {
                    Text("RetroMac uses these Apple frameworks: Metal, MetalKit, ScreenCaptureKit, AVKit, WebKit, AppKit, SwiftUI — plus Sparkle (updates) and a bundled Pac-Man built on SDL2 (see above).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Diagnostics") {
                    Text("Captures the app's console output (display matching, screen-capture errors, dock, etc.). Reproduce a problem, then Copy or Save the report and send it over.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DiagnosticsSectionView()
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
