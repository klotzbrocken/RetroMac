import Foundation
import Security

final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    // MARK: - Configuration
    static let gumroadProductID = "CgpY00IEkPvaLvnOJXk26g=="
    static let purchaseURL = "https://klotzzy2.gumroad.com/l/retromac-licence"
    static let kofiURL = "https://ko-fi.com/N4N11K1NC"

    // Basic presets — always free, no license needed
    static let freePresetIDs: Set<String> = [
        "passthrough",
        "crt-lite",          // CRT Lite — transparent overlay, no screen recording
        "lcd-lite",          // LCD Lite — standard TFT pixel grid
        "lcd-retro-lite",    // LCD Retro Lite — chunky early-2000s TN panel
        "lcd-sharp-lite",    // LCD Sharp Lite — fine IPS-style grid
        "lcd-broken-lite",   // LCD Broken Lite — damaged LCD panel
        "bw-lite",           // B&W Lite — grayscale + film grain overlay
        "amber-lite",        // Amber Lite — amber phosphor monitor overlay
        "vhs-lite",          // VHS Lite — transparent overlay, no screen recording
        "scanlines-lite",    // Scanlines Lite — transparent overlay, no screen recording
        "grain-lite",        // Film Scratches Lite — scratches, dust, flicker
        "crt-royale-lite",   // CRT Royale
        "trinitron-tv",      // Sony Trinitron
        "ntsc",              // NTSC
        "pal",               // PAL
        "aqua",              // macOS Aqua
        "vhs",               // VHS
        "lcd-grid",          // Retro LCD
        "vcr-tracking",      // VCR
        "mac-classic",       // Macintosh Classic
        "gameboy",           // Game Boy
        "amber-monitor",     // Amber Monitor
    ]

    /// Returns a random free preset ID for the "Surprise" feature
    static var surprisePresetID: String {
        freePresetIDs.filter { $0 != "passthrough" }.randomElement() ?? "crt-royale-lite"
    }

    /// What the licence unlocks BESIDES the presets.
    ///
    /// `freePresetIDs` above only covers presets, so every other paid feature used to be an
    /// ad-hoc `isLicensed` check at each call site — and every place that shows a lock or
    /// lists what you get had to remember on its own. It didn't: the Virtual Camera row never
    /// got a lock, and Live Wallpaper appeared in none of the three licence blurbs. One list,
    /// so the next feature can't drift the same way.
    struct PremiumFeature {
        let name: String
        let symbol: String
    }
    static let premiumFeatures: [PremiumFeature] = [
        PremiumFeature(name: "Live Wallpaper", symbol: "photo.on.rectangle.angled"),
        PremiumFeature(name: "Virtual Camera", symbol: "camera.fill"),
    ]

    /// A feature's name, with a padlock appended while it's locked — e.g. "Live Camera 🔒".
    /// Use this everywhere a paid feature is labelled, so the two never disagree again.
    func label(_ name: String) -> String {
        isLicensed ? name : "\(name) \u{1F512}"
    }

    /// What a licence gets you, in one sentence — presets plus everything in `premiumFeatures`.
    /// Welcome, About and Settings each used to word this themselves, so each was wrong in a
    /// different way: none mentioned Live Wallpaper, and only one mentioned the camera.
    static var unlockSummary: String {
        let items = ["all \(PresetRegistry.builtinPresets.count) presets", "custom shaders"]
            + premiumFeatures.map(\.name)
        guard let last = items.last, items.count > 1 else { return "Unlock \(items.first ?? "")" }
        return "Unlock " + items.dropLast().joined(separator: ", ") + " & " + last
    }

    /// Licensed-state heading. Deliberately not "All Presets Unlocked": that framed the licence
    /// as a presets-only deal, which stopped being true once the camera and Live Wallpaper
    /// were gated behind it.
    static let unlockedTitle = "Everything Unlocked"

    private let defaults = UserDefaults.standard
    private let licenseKeyKey = "licenseKey"
    private let licenseEmailKey = "licenseEmail"
    private let licenseValidKey = "licenseValid"
    private let lastValidationKey = "lastLicenseValidation"
    private let nagDismissedKey = "lastNagDismissed"

    @Published var licenseKey: String
    @Published var licenseEmail: String
    @Published var isLicensed: Bool
    @Published var validationError: String?
    @Published var isValidating = false

    /// All presets unlocked (licensed)
    var hasAllPresets: Bool { isLicensed }

    /// Check if a specific preset is available
    func isPresetAvailable(_ presetID: String) -> Bool {
        if isLicensed { return true }
        if presetID.hasPrefix("custom:") { return true }  // user's own shaders are always available
        return Self.freePresetIDs.contains(presetID)
    }

    /// Whether to show the friendly nag (at most once per day, not on first launch)
    var shouldShowNag: Bool {
        if isLicensed { return false }
        if !AppSettings.shared.onboardingComplete { return false }
        if let lastDismissed = defaults.object(forKey: nagDismissedKey) as? Date {
            let daysSince = Calendar.current.dateComponents([.day], from: lastDismissed, to: Date()).day ?? 0
            return daysSince >= 1
        }
        return true
    }

    func markNagDismissed() {
        defaults.set(Date(), forKey: nagDismissedKey)
    }

    /// Whether the recurring coffee/unlock page should appear (unlicensed + 30-day ack window).
    var shouldShowCoffee: Bool {
        if isLicensed { return false }
        if let ack = AppSettings.shared.coffeeAckDate {
            let days = Calendar.current.dateComponents([.day], from: ack, to: Date()).day ?? 0
            return days >= 30
        }
        return true
    }

    init() {
        // Migrate license key from UserDefaults to Keychain (one-time)
        if let legacyKey = UserDefaults.standard.string(forKey: licenseKeyKey), !legacyKey.isEmpty,
           Self.keychainLoad(key: licenseKeyKey) == nil {
            Self.keychainSave(key: licenseKeyKey, value: legacyKey)
            UserDefaults.standard.removeObject(forKey: licenseKeyKey)
            print("[License] Migrated license key from UserDefaults to Keychain")
        }
        if let legacyEmail = UserDefaults.standard.string(forKey: licenseEmailKey), !legacyEmail.isEmpty,
           Self.keychainLoad(key: licenseEmailKey) == nil {
            Self.keychainSave(key: licenseEmailKey, value: legacyEmail)
            UserDefaults.standard.removeObject(forKey: licenseEmailKey)
        }

        licenseKey = Self.keychainLoad(key: licenseKeyKey) ?? ""
        licenseEmail = Self.keychainLoad(key: licenseEmailKey) ?? ""
        isLicensed = defaults.bool(forKey: licenseValidKey)

        // Re-validate periodically (every 7 days)
        if isLicensed, let lastValidation = defaults.object(forKey: lastValidationKey) as? Date {
            let daysSince = Calendar.current.dateComponents([.day], from: lastValidation, to: Date()).day ?? 0
            if daysSince > 7 {
                revalidate()
            }
        }
    }

    // MARK: - Activation

    func activate(key: String, completion: @escaping (Bool, String?) -> Void) {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            completion(false, "Please enter a license key.")
            return
        }

        isValidating = true
        validationError = nil

        verifyWithGumroad(key: trimmedKey) { [weak self] success, email, error in
            DispatchQueue.main.async {
                self?.isValidating = false
                if success {
                    self?.licenseKey = trimmedKey
                    self?.licenseEmail = email ?? ""
                    self?.isLicensed = true
                    self?.validationError = nil
                    self?.saveLicense()
                    print("[License] Activated for \(email ?? "unknown")")
                } else {
                    self?.validationError = error ?? "Validation failed"
                    print("[License] Activation failed: \(error ?? "unknown")")
                }
                completion(success, error)
            }
        }
    }

    func deactivate() {
        licenseKey = ""
        licenseEmail = ""
        isLicensed = false
        validationError = nil
        Self.keychainDelete(key: licenseKeyKey)
        Self.keychainDelete(key: licenseEmailKey)
        defaults.set(false, forKey: licenseValidKey)
        defaults.removeObject(forKey: lastValidationKey)
        print("[License] Deactivated")
    }

    private func revalidate() {
        guard !licenseKey.isEmpty else { return }
        verifyWithGumroad(key: licenseKey) { [weak self] success, _, error in
            DispatchQueue.main.async {
                if !success {
                    print("[License] Revalidation failed: \(error ?? "unknown")")
                }
            }
        }
    }

    private func saveLicense() {
        Self.keychainSave(key: licenseKeyKey, value: licenseKey)
        Self.keychainSave(key: licenseEmailKey, value: licenseEmail)
        defaults.set(true, forKey: licenseValidKey)
        defaults.set(Date(), forKey: lastValidationKey)
    }

    // MARK: - Keychain

    private static let keychainService = "com.retromac.app.license"

    private static func keychainSave(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func keychainLoad(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainDelete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Gumroad API

    private func verifyWithGumroad(key: String, completion: @escaping (Bool, String?, String?) -> Void) {
        guard let url = URL(string: "https://api.gumroad.com/v2/licenses/verify") else {
            completion(false, nil, "Invalid API URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        func formEncode(_ s: String) -> String {
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        }
        let body = "product_id=\(formEncode(Self.gumroadProductID))&license_key=\(formEncode(key))"
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, nil, "Network error: \(error.localizedDescription)")
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(false, nil, "Invalid response")
                return
            }

            let success = json["success"] as? Bool ?? false
            if success {
                let purchase = json["purchase"] as? [String: Any]
                let email = purchase?["email"] as? String

                if let refunded = purchase?["refunded"] as? Bool, refunded {
                    completion(false, nil, "This license has been refunded.")
                    return
                }

                if let chargebacked = purchase?["chargebacked"] as? Bool, chargebacked {
                    completion(false, nil, "This license has been chargebacked.")
                    return
                }

                completion(true, email, nil)
            } else {
                let message = json["message"] as? String ?? "Invalid license key"
                completion(false, nil, message)
            }
        }.resume()
    }
}
