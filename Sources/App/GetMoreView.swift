import SwiftUI

/// The one place that describes what the paid unlock adds.
///
/// Shared by the Setup Assistant and the What's New flow on purpose: two hand-written copies of
/// a feature list drift, and a stale one here is worse than elsewhere because it is the page that
/// asks for money. Whoever gates a new feature changes this list, and both wizards follow.
struct GetMoreView: View {
    @ObservedObject private var license = LicenseManager.shared

    /// Shown as the page's own heading in the Setup Assistant, which has no other title.
    var showsHeader = true

    struct Perk: Identifiable {
        let id = UUID()
        let icon: String, tint: Color, title: String, subtitle: String
        /// The `LicenseManager.premiumFeatures` entry this line sells, where it sells one.
        ///
        /// The two lists have to agree and nothing made them: Retro Crashes was gated, added to
        /// `premiumFeatures`, and never mentioned on the page that asks for the money. This is
        /// what a test can hold on to.
        var feature: String? = nil
    }

    static let perks: [Perk] = [
        Perk(icon: "tv.fill", tint: .blue, title: "Every shader",
             subtitle: "The full preset library — CRT, VHS, Trinitron, LCD and the rest — plus your own imported ones."),
        Perk(icon: "camera.fill", tint: .purple, title: "Webcam support",
             subtitle: "Run the effect through a virtual camera, so your calls and streams get it too.",
             feature: "Virtual Camera"),
        Perk(icon: "photo.fill", tint: .teal, title: "Shader as live wallpaper",
             subtitle: "Draw the effect on the desktop picture alone: animated, behind your icons and windows.",
             feature: "Live Wallpaper"),
        Perk(icon: "exclamationmark.triangle.fill", tint: .orange, title: "Retro Crashes",
             subtitle: "Period system failures on the themed desktop — the blue screen, the illegal operation, the bomb — on a timer or on demand. Nothing ever really crashes.",
             feature: "Retro Crashes"),
        Perk(icon: "heart.fill", tint: .pink, title: "Support the developer",
             subtitle: "One payment, no subscription. It is what keeps RetroMac being worked on."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHeader {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "sparkles").font(.system(size: 36)).foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Get more").font(.title2.bold())
                        Text("RetroMac is free and stays free. A one-off unlock opens the rest.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if license.isLicensed {
                Label("License active — everything below is already unlocked",
                      systemImage: "checkmark.seal.fill")
                    .font(.body).foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Self.perks.enumerated()), id: \.element.id) { i, perk in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: perk.icon)
                            .font(.system(size: 18)).foregroundStyle(perk.tint).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(perk.title).font(.body.weight(.medium))
                            Text(perk.subtitle).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                    if i < Self.perks.count - 1 { Divider() }
                }
            }

            if !license.isLicensed {
                Button {
                    if let url = URL(string: LicenseManager.purchaseURL) { NSWorkspace.shared.open(url) }
                } label: {
                    Label("Unlock RetroMac", systemImage: "lock.open.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                Text("Already bought it? Enter your key on the next page.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
