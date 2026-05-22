import Foundation

final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    // MARK: - Configuration
    static let gumroadProductID = "CgpY00IEkPvaLvnOJXk26g=="
    static let purchaseURL = "https://klotzzy2.gumroad.com/l/ygjrx"
    static let kofiURL = "https://ko-fi.com/N4N11K1NC"

    // Basic presets — always free, no license needed
    static let freePresetIDs: Set<String> = [
        "passthrough",
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
        return Self.freePresetIDs.contains(presetID)
    }

    /// Whether to show the friendly nag (at most once per day)
    var shouldShowNag: Bool {
        if isLicensed { return false }
        if let lastDismissed = defaults.object(forKey: nagDismissedKey) as? Date {
            let daysSince = Calendar.current.dateComponents([.day], from: lastDismissed, to: Date()).day ?? 0
            return daysSince >= 1
        }
        return true
    }

    func markNagDismissed() {
        defaults.set(Date(), forKey: nagDismissedKey)
    }

    init() {
        licenseKey = defaults.string(forKey: licenseKeyKey) ?? ""
        licenseEmail = defaults.string(forKey: licenseEmailKey) ?? ""
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
        defaults.removeObject(forKey: licenseKeyKey)
        defaults.removeObject(forKey: licenseEmailKey)
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
        defaults.set(licenseKey, forKey: licenseKeyKey)
        defaults.set(licenseEmail, forKey: licenseEmailKey)
        defaults.set(true, forKey: licenseValidKey)
        defaults.set(Date(), forKey: lastValidationKey)
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

        let body = "product_id=\(Self.gumroadProductID)&license_key=\(key)"
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
