import AppKit

/// What the single edition does besides what the full RetroMac does: start its one theme, and
/// the ways out a newcomer finds without being told (⌘Q, the app's menu, the Apple menu, a
/// right-click on the desktop, its tile in the Dock). Every one of them is the same: quit, which
/// puts the Mac back as it was.
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

    /// "Return to macOS" where a newcomer looks for it (the Apple menu, the desktop): the same as
    /// quitting.
    static func returnToDesktop() { exit() }

    /// Everything put back, and gone.
    static func exit() {
        SingleWelcome.shared.close()
        SingleWelcome.shared.showGoodbyeIfNeeded {
            AppDelegate.shared?.quitApp()
        }
    }

    static func openFullApp() { NSWorkspace.shared.open(Edition.fullAppURL) }

    /// The one shader: CRT Lite, scanlines and a vignette that need no Screen Recording, and
    /// clearly visible (the theme's own LCD Sharp Lite is too fine to tell it is on).
    static func toggleShader() {
        if AppDelegate.shared?.isActive != true { AppDelegate.shared?.currentPresetName = "crt-lite" }
        AppDelegate.shared?.launcherToggleShader()
    }

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
        menu.addItem(ClosureMenuItem(title: "Welcome\u{2026}", run: { SingleWelcome.shared.show(atLaunch: false) }))
        menu.addItem(ClosureMenuItem(title: "Get the full RetroMac\u{2026}", run: openFullApp))
        menu.addItem(.separator())
        let quit = ClosureMenuItem(title: "Quit RetroMac", run: exit)
        quit.keyEquivalent = "q"
        menu.addItem(quit)
        appItem.submenu = menu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    /// The menu of the edition's Dock tile: the shader, the lightbox, the full app, out.
    static func showButtonMenu(in view: NSView) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let shader = ClosureMenuItem(title: "CRT Shader", run: toggleShader)
        shader.state = AppDelegate.shared?.isActive == true ? .on : .off
        shader.isEnabled = themeIsOn
        menu.addItem(shader)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Welcome\u{2026}", run: { SingleWelcome.shared.show(atLaunch: false) }))
        menu.addItem(ClosureMenuItem(title: "Get the full RetroMac\u{2026}", run: openFullApp))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Quit RetroMac", run: exit))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }
}
