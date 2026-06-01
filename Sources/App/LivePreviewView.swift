import SwiftUI
import AppKit

/// A sampled-screenshot preview of what the overlay looks like.
/// Refreshes every 2 seconds with a capture of the current screen.
/// Shows a gradient placeholder when the overlay is off.
struct LivePreviewView: View {
    @State private var previewImage: NSImage?
    @ObservedObject private var settings = AppSettings.shared

    /// Optional label override (e.g. "zfast CRT · 100%")
    var labelOverride: String? = nil

    private var overlayIsOn: Bool {
        (NSApp.delegate as? AppDelegate)?.isActive ?? false
    }

    private var presetDisplayName: String {
        PresetRegistry.availablePresets.first(where: { $0.id == settings.defaultPreset })?.displayName ?? settings.defaultPreset
    }

    private var labelText: String {
        if let override = labelOverride { return override }
        return "Live \u{00B7} \(presetDisplayName)"
    }

    var body: some View {
        ZStack {
            // Background
            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Gradient placeholder — always show a "desktop-like" preview
                desktopPlaceholder
            }

            // Label chip top-left
            VStack {
                HStack {
                    Text(labelText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())
                        .padding(8)

                    Spacer()
                }
                Spacer()
            }
        }
        .background(Color(red: 0.04, green: 0.05, blue: 0.07))
        .onAppear { capturePreview() }
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
            capturePreview()
        }
    }

    /// A CSS-style fake desktop placeholder (menu bar, window, dock-like bar)
    private var desktopPlaceholder: some View {
        ZStack {
            // Desktop gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.22, blue: 0.35),
                    Color(red: 0.08, green: 0.12, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle radial light
            RadialGradient(
                colors: [Color.white.opacity(0.06), Color.clear],
                center: UnitPoint(x: 0.6, y: 0.3),
                startRadius: 10,
                endRadius: 200
            )

            VStack(spacing: 0) {
                // Fake menu bar
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 12)
                    .overlay(
                        HStack(spacing: 4) {
                            Circle().fill(Color.red.opacity(0.5)).frame(width: 4, height: 4)
                            Circle().fill(Color.yellow.opacity(0.5)).frame(width: 4, height: 4)
                            Circle().fill(Color.green.opacity(0.5)).frame(width: 4, height: 4)
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                    )

                Spacer()

                // Fake window
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                    .frame(width: 200, height: 100)
                    .overlay(
                        VStack(spacing: 0) {
                            // Title bar
                            HStack(spacing: 3) {
                                Circle().fill(Color.red.opacity(0.4)).frame(width: 4, height: 4)
                                Circle().fill(Color.yellow.opacity(0.4)).frame(width: 4, height: 4)
                                Circle().fill(Color.green.opacity(0.4)).frame(width: 4, height: 4)
                                Spacer()
                            }
                            .padding(.horizontal, 6)
                            .padding(.top, 4)
                            Spacer()
                        }
                    )

                Spacer()

                // Fake dock bar at bottom
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { i in
                        let colors: [Color] = [.blue, .green, .orange, .purple, .cyan, .red, .yellow]
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors[i].opacity(0.5))
                            .frame(width: 12, height: 12)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                )
                .padding(.bottom, 6)
            }

            // CRT scanline overlay hint
            if overlayIsOn {
                VStack(spacing: 2) {
                    ForEach(0..<80, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.black.opacity(0.15))
                            .frame(height: 1)
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func capturePreview() {
        // Collect window IDs to exclude (settings window + its children)
        // so the preview doesn't create an infinity-mirror effect.
        let excludeIDs: Set<CGWindowID> = {
            var ids = Set<CGWindowID>()
            for win in NSApp.windows where win.title == "RetroMac Settings" {
                ids.insert(CGWindowID(win.windowNumber))
            }
            return ids
        }()

        DispatchQueue.global(qos: .utility).async {
            let displayID = CGMainDisplayID()
            let bounds = CGDisplayBounds(displayID)
            let captureW: CGFloat = min(bounds.width, 960)
            let captureH: CGFloat = min(bounds.height, 600)
            let captureX = (bounds.width - captureW) / 2
            let captureY = (bounds.height - captureH) / 2
            let rect = CGRect(x: captureX, y: captureY, width: captureW, height: captureH)

            // Build a list of all on-screen windows EXCEPT the settings window,
            // then composite them into a single image. This includes the overlay
            // window (which sits at a higher level) and everything else.
            let cgImage: CGImage?
            if !excludeIDs.isEmpty,
               let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] {
                let windowIDs: [CGWindowID] = windowList.compactMap { info in
                    guard let winID = info[kCGWindowNumber] as? CGWindowID else { return nil }
                    if excludeIDs.contains(winID) { return nil }
                    return winID
                }
                let idArray = windowIDs as CFArray
                cgImage = CGImage(
                    windowListFromArrayScreenBounds: rect,
                    windowArray: idArray,
                    imageOption: [.boundsIgnoreFraming, .nominalResolution]
                )
            } else {
                cgImage = CGDisplayCreateImage(displayID, rect: rect)
            }

            guard let image = cgImage else { return }
            let nsImage = NSImage(cgImage: image, size: NSSize(width: captureW / 2, height: captureH / 2))
            DispatchQueue.main.async {
                self.previewImage = nsImage
            }
        }
    }
}
