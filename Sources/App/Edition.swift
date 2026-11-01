import Foundation

/// Which RetroMac this is. The full app, or a single-click edition: one theme, switched on at
/// launch, no settings, no permissions, a welcome lightbox that points to the full RetroMac.
/// Set by the build (`./build.sh … snowleopard`) as `RetroMacEdition` in Info.plist; missing
/// means the full app, which none of the edition's gates touch.
enum Edition {
    struct Single {
        let key: String
        let themeID: String
        let themeName: String
        let appName: String
    }

    static let snowLeopard = Single(key: "snowleopard", themeID: "com.retromac.apple.snow-leopard",
                                    themeName: "Snow Leopard", appName: "RetroMac Snow Leopard")

    /// The single edition this build is, or nil for the full app.
    static let single: Single? = edition(for: Bundle.main.object(forInfoDictionaryKey: "RetroMacEdition") as? String)

    static var isSingle: Bool { single != nil }

    static func edition(for key: String?) -> Single? {
        [snowLeopard].first { $0.key == key }
    }

    /// The full RetroMac's site, marked so its visits from this edition can be counted there.
    /// The app itself reports nothing.
    static var fullAppURL: URL {
        URL(string: "https://myretromac.app/?ref=\(single?.key ?? "retromac")")!
    }
}
