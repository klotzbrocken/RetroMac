import SwiftUI

struct AboutTab: View {
    @State private var updateStatus: String?
    @State private var isChecking = false

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
                    LabeledContent("SimpleBanking") {
                        Link("simplebanking.de", destination: URL(string: "https://www.simplebanking.de")!)
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

                Section("Theme Disclaimer") {
                    Text("Theme icons and wallpapers depicting macOS and Windows interfaces are trademarks and copyrighted material of Apple Inc. and Microsoft Corporation respectively. They are included for personal, non-commercial use to recreate the look and feel of classic operating systems. RetroMac is not affiliated with or endorsed by Apple or Microsoft.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Open Source") {
                    Text("RetroMac uses the following Apple frameworks: Metal, MetalKit, ScreenCaptureKit, AVKit, WebKit, AppKit, SwiftUI. No third-party libraries are used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Updates") {
                    HStack {
                        Button(isChecking ? "Checking..." : "Check for Updates") {
                            checkForUpdates()
                        }
                        .disabled(isChecking)
                        Spacer()
                        if let status = updateStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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

    private func checkForUpdates() {
        isChecking = true
        updateStatus = nil

        guard let url = URL(string: "https://www.klotzbrocken.de/retromac/version.json") else {
            updateStatus = "Invalid URL"
            isChecking = false
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                isChecking = false
                if let error = error {
                    updateStatus = "Connection failed"
                    print("[Update] Error: \(error.localizedDescription)")
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let latest = json["version"] as? String else {
                    updateStatus = "Could not check"
                    return
                }
                if latest == appVersion {
                    updateStatus = "Up to date \u{2713}"
                } else {
                    updateStatus = "v\(latest) available"
                    if let urlStr = json["url"] as? String, let downloadURL = URL(string: urlStr) {
                        NSWorkspace.shared.open(downloadURL)
                    }
                }
            }
        }.resume()
    }
}
