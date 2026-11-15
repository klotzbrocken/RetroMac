import AppKit

/// "All Programs" in the Windows Start menus: every app on the Mac, sorted into a few folders
/// by what it is. The app's own App Store category decides where it can (LSApplicationCategoryType),
/// a short list of well-known apps where the category says nothing (browsers declare none).
/// Whatever fits no folder is listed after them.
enum AllPrograms {

    enum Folder: String, CaseIterable {
        case communication = "Communication", design = "Design", games = "Games", multimedia = "Multimedia",
             office = "Office", online = "Online", systemTools = "System Tools"
    }

    struct App: Equatable {
        let name: String
        let bundleID: String
        let folder: Folder?
    }

    /// Well-known apps whose category is missing or misleading, by bundle id (prefix match for
    /// the families that ship many: Adobe, Microsoft Office).
    private static let known: [(String, Folder)] = [
        // Online: browsers declare no category, and the AI chat apps live in one.
        ("com.apple.Safari", .online), ("com.google.Chrome", .online), ("org.mozilla.firefox", .online),
        ("com.microsoft.edgemac", .online), ("com.operasoftware.Opera", .online), ("com.brave.Browser", .online),
        ("company.thebrowser.Browser", .online), ("com.vivaldi.Vivaldi", .online), ("com.kagi.kagimacOS", .online),
        ("org.torproject.torbrowser", .online), ("com.duckduckgo.macos.browser", .online),
        ("com.openai.chat", .online), ("com.anthropic.claudefordesktop", .online),
        // Office
        ("com.apple.iWork.", .office), ("com.microsoft.Word", .office), ("com.microsoft.Excel", .office),
        ("com.microsoft.Powerpoint", .office), ("com.microsoft.onenote", .office), ("org.libreoffice", .office),
        ("com.apple.TextEdit", .office), ("com.apple.Notes", .office), ("com.apple.reminders", .office),
        ("com.apple.iCal", .office), ("com.apple.Preview", .office),
        // Design
        ("com.adobe.", .design), ("com.pixelmatorteam.", .design), ("com.seriflabs.", .design),
        ("com.bohemiancoding.sketch", .design), ("com.figma.Desktop", .design), ("org.gimp.", .design),
        ("org.inkscape.", .design), ("org.blenderfoundation.blender", .design), ("com.apple.FontBook", .design),
        // Multimedia
        ("com.apple.Music", .multimedia), ("com.apple.Photos", .multimedia), ("com.apple.TV", .multimedia),
        ("com.apple.podcasts", .multimedia), ("com.apple.QuickTimePlayerX", .multimedia), ("org.videolan.vlc", .multimedia),
        ("com.colliderli.iina", .multimedia), ("com.apple.garageband", .multimedia), ("com.spotify.client", .multimedia),
        ("com.apple.PhotoBooth", .multimedia), ("com.apple.VoiceMemos", .multimedia), ("com.apple.iMovieApp", .multimedia),
        // Communication
        ("com.apple.mail", .communication), ("com.apple.MobileSMS", .communication), ("com.apple.FaceTime", .communication),
        ("com.apple.AddressBook", .communication), ("com.tinyspeck.slackmacgap", .communication),
        ("com.microsoft.teams", .communication), ("us.zoom.xos", .communication), ("com.hnc.Discord", .communication),
        ("net.whatsapp.WhatsApp", .communication), ("desktop.WhatsApp", .communication), ("ru.keepcoder.Telegram", .communication),
        ("org.whispersystems.signal-desktop", .communication), ("com.skype.skype", .communication),
        ("com.microsoft.Outlook", .communication),
        // System Tools
        ("com.apple.Terminal", .systemTools), ("com.googlecode.iterm2", .systemTools), ("com.apple.ActivityMonitor", .systemTools),
        ("com.apple.DiskUtility", .systemTools), ("com.apple.systempreferences", .systemTools), ("com.apple.Console", .systemTools),
        ("com.apple.SystemProfiler", .systemTools), ("com.apple.keychainaccess", .systemTools), ("com.apple.backup.launcher", .systemTools),
        // Apple's own apps without a category
        ("com.apple.mobilephone", .communication), ("com.cisco.webex", .communication), ("Cisco-Systems.Spark", .communication),
        ("com.apple.calculator", .office), ("com.apple.clock", .office), ("com.apple.journal", .office),
        ("com.apple.weather", .online), ("com.apple.stocks", .online), ("com.apple.findmy", .online),
        ("com.apple.iBooksX", .multimedia), ("com.apple.Passwords", .systemTools), ("com.apple.Home", .systemTools),
        ("com.apple.Magnifier", .systemTools), ("com.apple.appleseed.FeedbackAssistant", .systemTools),
        ("com.apple.Siri", .systemTools),
    ]

    /// Where an app goes: its bundle id first, then its declared category.
    static func folder(bundleID: String, category: String?) -> Folder? {
        // By prefix: GarageBand is "com.apple.garageband10", Teams "com.microsoft.teams2".
        if let hit = known.first(where: { bundleID.hasPrefix($0.0) }) {
            return hit.1
        }
        guard let c = category?.replacingOccurrences(of: "public.app-category.", with: "") else { return nil }
        if c == "games" || c.hasSuffix("-games") { return .games }
        switch c {
        case "productivity", "business", "education", "reference", "finance": return .office
        case "graphics-design": return .design
        case "music", "video", "entertainment", "photography": return .multimedia
        case "social-networking": return .communication
        case "utilities", "developer-tools": return .systemTools
        case "news", "weather", "travel", "lifestyle": return .online
        default: return nil
        }
    }

    private static var cache: (at: Date, apps: [App])?
    private static var refreshing = false

    /// Every app in the usual places. Reading ~200 bundles takes a fifth of a second, too long
    /// for a menu that opens on a click: the last list is shown at once and, when it is older
    /// than a minute, read again in the background for the next opening. Main thread only.
    static func apps() -> [App] {
        guard let c = cache else { let fresh = scan(); cache = (Date(), fresh); return fresh }
        if Date().timeIntervalSince(c.at) > 60, !refreshing {
            refreshing = true
            DispatchQueue.global(qos: .utility).async {
                let fresh = scan()
                DispatchQueue.main.async { cache = (Date(), fresh); refreshing = false }
            }
        }
        return c.apps
    }

    static func scan() -> [App] {
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                     NSHomeDirectory() + "/Applications"]
        var seen = Set<String>(), list: [App] = []
        for root in roots {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
            for item in items where item.hasSuffix(".app") && !item.hasPrefix(".") {
                guard let bundle = Bundle(url: URL(fileURLWithPath: root).appendingPathComponent(item)),
                      let id = bundle.bundleIdentifier, seen.insert(id).inserted else { continue }
                let name = FileManager.default.displayName(atPath: bundle.bundlePath).replacingOccurrences(of: ".app", with: "")
                let category = bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
                list.append(App(name: name, bundleID: id, folder: folder(bundleID: id, category: category)))
            }
        }
        list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return list
    }
}
