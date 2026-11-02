import AppKit
import SwiftUI

/// The single edition's lightbox, at every launch: what this is, how to get out again, the one
/// shader switch, and what the full RetroMac has besides. Opened again later (the floating
/// button, the app's menu, every way into Settings) it only closes. On the way out it asks once
/// per session whether the visitor wants the rest.
final class SingleWelcome {
    static let shared = SingleWelcome()
    /// The other eras in the full RetroMac, for the advertising line.
    static let moreEras = 26

    private var window: NSWindow?
    private let model = Model()
    private var saidGoodbye = false

    final class Model: ObservableObject {
        @Published var goodbye = false
        @Published var shaderOn = false
        /// Opened at launch: its button starts the theme ("Start"); opened later it only closes.
        @Published var atLaunch = false
        var onGoodbyeDone: (() -> Void)?
    }

    /// `atLaunch`: its button starts the theme ("Start"); opened later it only closes.
    func show(atLaunch: Bool) {
        model.goodbye = false
        model.shaderOn = AppDelegate.shared?.isActive == true
        model.atLaunch = atLaunch
        present()
    }

    func close() { window?.orderOut(nil) }

    /// The visitor is leaving (Quit RetroMac, from wherever): once per session the card that points to
    /// the full RetroMac, then `then`. No countdown, no second time.
    func showGoodbyeIfNeeded(then: @escaping () -> Void) {
        guard !saidGoodbye else { return then() }
        saidGoodbye = true
        model.goodbye = true
        model.onGoodbyeDone = { [weak self] in self?.close(); then() }
        present()
    }

    private func present() {
        guard let screen = NSScreen.main else { return }
        let w = window ?? make()
        w.setFrame(screen.frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let w = KeyableWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .themeMenu   // over the Retro Dock, under the shader
        w.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        w.title = "Welcome"
        w.contentView = NSHostingView(rootView: LightboxView(model: model, close: { [weak self] in self?.close() }))
        w.appearance = NSAppearance(named: .aqua)   // Snow Leopard's era was light
        window = w
        return w
    }

    // MARK: - The view

    private struct LightboxView: View {
        @ObservedObject var model: Model
        let close: () -> Void
        private var edition: Edition.Single { Edition.single ?? Edition.snowLeopard }

        var body: some View {
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()
                if model.goodbye { goodbye } else { welcome }
            }
        }

        private var welcome: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to \(edition.appName)").font(.system(size: 26, weight: .bold))
                Text("\(edition.themeName) is on. Use your Mac as always; it only looks like 2009.")
                    .foregroundStyle(.secondary)

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("To leave").font(.headline)
                        Text("Quit RetroMac: \u{2318}Q, the Apple menu \u{25B8} Return to macOS, a right-click on the desktop, or the round button on the screen. Your Dock and desktop picture come straight back.")
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }

                Toggle("CRT shader", isOn: Binding(get: { model.shaderOn }, set: { on in
                    if on != (AppDelegate.shared?.isActive == true) { SingleEdition.toggleShader() }
                    model.shaderOn = on
                })).toggleStyle(.switch)

                Divider()

                Text("\(SingleWelcome.moreEras) more eras in RetroMac").font(.headline)
                previews
                VStack(alignment: .leading, spacing: 3) {
                    Text("Only in RetroMac:").font(.subheadline.weight(.semibold))
                    Text("\u{2022} CRT shaders for the whole screen, games and the webcam")
                    Text("\u{2022} RetroHub: classic games and apps, one click each")
                    Text("\u{2022} Sounds, working taskbars, Start menus and title bars")
                }.font(.subheadline)

                HStack {
                    Button("Get RetroMac \u{2013} it\u{2019}s free") { SingleEdition.openFullApp() }
                    Spacer()
                    Button("Quit RetroMac") { SingleEdition.exit() }
                    Button(model.atLaunch ? "Start" : "Close") { close() }
                        .buttonStyle(.borderedProminent).tint(.green)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
            .frame(width: 640)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
            .shadow(radius: 30)
        }

        private var goodbye: some View {
            VStack(spacing: 14) {
                Text("Liked it?").font(.system(size: 24, weight: .bold))
                Text("There are \(SingleWelcome.moreEras) more: Mac OS 9, Windows 98 and XP, BeOS, the Mac OS that never shipped, and more. RetroMac is free.")
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                previews
                HStack {
                    Button("No thanks") { model.onGoodbyeDone?() }
                    Button("Get RetroMac") { SingleEdition.openFullApp(); model.onGoodbyeDone?() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
            .frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
            .shadow(radius: 30)
        }

        /// Pictures of other themes, copied into the edition's bundle by build.sh (Previews/).
        @ViewBuilder private var previews: some View {
            let images = SingleWelcome.previewImages
            if !images.isEmpty {
                HStack(spacing: 8) {
                    ForEach(images.indices, id: \.self) { i in
                        Image(nsImage: images[i]).resizable().aspectRatio(640.0 / 416.0, contentMode: .fit)
                            .frame(height: 62).clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
    }

    static let previewImages: [NSImage] = {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Previews"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(6).compactMap(NSImage.init(contentsOf:))
    }()
}
