import AppKit

/// Shared "Set Custom Icon" context-menu used by every surface that shows an app icon
/// (Dock/Taskbar already have their own copy in DockController; this powers the Start menu,
/// BeOS deskbar menu and the Applications folder). It offers the active theme's bundled
/// icons, a Browse… option and a Reset, all persisted via `ThemeManager.setCustomIcon`
/// (keyed by bundleID per theme) so a chosen icon shows consistently across all surfaces.
final class CustomIconPicker: NSObject {

    private let bundleID: String
    private let onChange: () -> Void
    private static var retained: CustomIconPicker?   // keep alive across the async Browse panel

    private init(bundleID: String, onChange: @escaping () -> Void) {
        self.bundleID = bundleID
        self.onChange = onChange
    }

    /// Pop up the icon picker for `bundleID`, anchored at `point` (in `view` coordinates).
    static func present(for bundleID: String, in view: NSView, at point: NSPoint,
                        onChange: @escaping () -> Void) {
        let picker = CustomIconPicker(bundleID: bundleID, onChange: onChange)
        retained = picker
        let menu = picker.buildMenu()
        menu.popUp(positioning: nil, at: point, in: view)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "Choose Icon")

        if let theme = ThemeManager.shared.activeTheme {
            let header = NSMenuItem(title: "Theme Icons (\(theme.name))", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())

            for iconInfo in theme.availableIcons() {
                let item = NSMenuItem(title: iconInfo.name, action: #selector(pickThemeIcon(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = iconInfo.url.path
                if let img = NSImage(contentsOf: iconInfo.url) {
                    img.size = NSSize(width: 20, height: 20)
                    item.image = img
                }
                menu.addItem(item)
            }
            if !theme.availableIcons().isEmpty { menu.addItem(.separator()) }
        }

        let browse = NSMenuItem(title: "Set Custom Icon…", action: #selector(browse(_:)), keyEquivalent: "")
        browse.target = self
        browse.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(browse)

        if ThemeManager.shared.customIconPath(for: bundleID) != nil {
            let reset = NSMenuItem(title: "Reset to Default", action: #selector(reset(_:)), keyEquivalent: "")
            reset.target = self
            reset.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
            menu.addItem(reset)
        }
        return menu
    }

    @objc private func pickThemeIcon(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        ThemeManager.shared.setCustomIcon(for: bundleID, path: path)
        finish()
    }

    @objc private func browse(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .icns, .tiff, .jpeg, .image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a custom icon for the current theme"
        panel.prompt = "Set Icon"
        guard panel.runModal() == .OK, let url = panel.url else { Self.retained = nil; return }
        ThemeManager.shared.setCustomIcon(for: bundleID, path: url.path)
        finish()
    }

    @objc private func reset(_ sender: NSMenuItem) {
        ThemeManager.shared.setCustomIcon(for: bundleID, path: nil)
        finish()
    }

    private func finish() {
        onChange()
        Self.retained = nil
    }
}
