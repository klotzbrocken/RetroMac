import AppKit

/// What the single edition does besides what the full RetroMac does: start its one theme, give
/// it up and take it back, and the ways out a newcomer finds without being told (⌘Q, the app's
/// menu, the Apple menu, a right-click on the desktop, the floating button).
enum SingleEdition {
    private static var edition: Edition.Single { Edition.single ?? Edition.snowLeopard }

    /// Whether the edition's theme is on the screen now.
    static var themeIsOn: Bool { AppSettings.shared.dockEnabled && ThemeManager.shared.activeTheme != nil }

    /// The theme on, at once: no boot screen, the Retro Dock up, the theme's Lite shader chosen
    /// (off until switched on in the lightbox).
    static func startTheme() {
        AppSettings.shared.showSplashScreen = false
        AppSettings.shared.shaderOnThemeChange = false   // the shader is the lightbox's switch
        AppDelegate.shared?.launcherActivateTheme(edition.themeID)
    }

    /// Plain macOS back, the app still running: the floating button turns the theme on again.
    static func returnToDesktop() {
        guard themeIsOn else { return }
        SingleWelcome.shared.close()
        SingleWelcome.shared.showGoodbyeIfNeeded {
            AppDelegate.shared?.launcherDisableTheme()
        }
    }

    /// Everything put back, and gone.
    static func exit() {
        SingleWelcome.shared.close()
        SingleWelcome.shared.showGoodbyeIfNeeded {
            AppDelegate.shared?.quitApp()
        }
    }

    static func openFullApp() { NSWorkspace.shared.open(Edition.fullAppURL) }

    // MARK: - The full RetroMac

    /// Another RetroMac (the full app or its dev build) running: the two must not both drive
    /// the Dock and the desktop.
    static func otherRetroMacRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.processIdentifier != getpid() && ($0.bundleIdentifier ?? "").hasPrefix("com.retromac.app")
        }
    }

    static func refuseAndQuit() {
        let alert = NSAlert()
        alert.messageText = "RetroMac is already running"
        alert.informativeText = "\(edition.appName) and RetroMac change the same Dock and desktop. Quit RetroMac first, then open \(edition.appName) again."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }

    // MARK: - Menus

    /// The app's own menu, shown while it is in front: the way out every Mac user knows.
    static func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let menu = NSMenu(title: edition.appName)
        menu.addItem(ClosureMenuItem(title: "About \(edition.appName)", run: {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        }))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Welcome\u{2026}", run: { SingleWelcome.shared.show(countdown: false) }))
        menu.addItem(ClosureMenuItem(title: "Get the full RetroMac\u{2026}", run: openFullApp))
        menu.addItem(.separator())
        let toggle = ToggleThemeItem()
        menu.addItem(toggle)
        menu.addItem(.separator())
        let quit = ClosureMenuItem(title: "Quit \(edition.appName)", run: exit)
        quit.keyEquivalent = "q"
        menu.addItem(quit)
        menu.delegate = toggle
        appItem.submenu = menu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    /// The floating button's menu: the theme on or off, the shader, the lightbox, the full app, out.
    static func showButtonMenu(in view: NSView) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(themeIsOn
            ? ClosureMenuItem(title: "Return to macOS", run: returnToDesktop)
            : ClosureMenuItem(title: "Start \(edition.themeName)", run: startTheme))
        let shader = ClosureMenuItem(title: "CRT Shader", run: { AppDelegate.shared?.launcherToggleShader() })
        shader.state = AppDelegate.shared?.isActive == true ? .on : .off
        shader.isEnabled = themeIsOn
        menu.addItem(shader)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Welcome\u{2026}", run: { SingleWelcome.shared.show(countdown: false) }))
        menu.addItem(ClosureMenuItem(title: "Get the full RetroMac\u{2026}", run: openFullApp))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Exit", run: exit))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }

    /// "Return to macOS" or "Start Snow Leopard", whichever fits when the menu opens.
    private final class ToggleThemeItem: NSMenuItem, NSMenuDelegate {
        init() {
            super.init(title: "Return to macOS", action: #selector(fire), keyEquivalent: "")
            target = self
        }
        @available(*, unavailable) required init(coder: NSCoder) { fatalError() }
        func menuNeedsUpdate(_ menu: NSMenu) {
            title = SingleEdition.themeIsOn ? "Return to macOS" : "Start \(SingleEdition.edition.themeName)"
        }
        @objc private func fire() {
            if SingleEdition.themeIsOn { SingleEdition.returnToDesktop() } else { SingleEdition.startTheme() }
        }
    }
}
