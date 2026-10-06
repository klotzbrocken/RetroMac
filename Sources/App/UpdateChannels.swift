import Foundation
import Sparkle

/// Which appcast channels this Mac takes. Released versions always; betas only when the user
/// asked for them in About ▸ Software Updates. An appcast item marked
/// `<sparkle:channel>beta</sparkle:channel>` reaches no one else.
final class UpdateChannels: NSObject, SPUUpdaterDelegate {
    static var wantsBetas: Bool {
        get { UserDefaults.standard.bool(forKey: "updateIncludeBetas") }
        set { UserDefaults.standard.set(newValue, forKey: "updateIncludeBetas") }
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Self.wantsBetas ? ["beta"] : []
    }
}
