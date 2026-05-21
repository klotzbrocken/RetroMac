import SwiftUI

struct AboutTab: View {
    @State private var updateStatus: String?
    @State private var isChecking = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)

                        Text("RetroMac")
                            .font(.title3)
                            .fontWeight(.bold)

                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
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

            Section("Updates") {
                HStack {
                    Button(isChecking ? "Checking…" : "Check for Updates") {
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
                    Text("\u{00A9} 2026 Maik Klotz")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
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
                    updateStatus = "Up to date ✓"
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
