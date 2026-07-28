import Foundation
import SwiftUI

/// Small persisted preferences — everything here is non-secret (secrets live
/// in Keychain) and there is deliberately very little of it, per the
/// one-screen / no-settings-screen constraint. This backs the single
/// Settings sheet reachable from the first-launch note and a header
/// long-press — never a full settings screen.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let hasSeenFirstLaunch = "hasSeenFirstLaunch"
        static let breezeVoiceID = "breezeVoiceID"
    }

    /// No baked-in default: Breeze voice IDs (`voc_...`) are per-account, and
    /// the text-to-speech endpoint requires one in the URL path — there's no
    /// "just use whatever's default" option the way ElevenLabs has. Empty
    /// means VoiceProviderFactory falls back to the on-device voice even if
    /// a Breeze key is present, until a real voice ID is entered.
    static let defaultBreezeVoiceID = ""

    @Published var hasSeenFirstLaunch: Bool {
        didSet { UserDefaults.standard.set(hasSeenFirstLaunch, forKey: Keys.hasSeenFirstLaunch) }
    }

    @Published var breezeVoiceID: String {
        didSet { UserDefaults.standard.set(breezeVoiceID, forKey: Keys.breezeVoiceID) }
    }

    private init() {
        let defaults = UserDefaults.standard
        hasSeenFirstLaunch = defaults.bool(forKey: Keys.hasSeenFirstLaunch)
        breezeVoiceID = defaults.string(forKey: Keys.breezeVoiceID) ?? Self.defaultBreezeVoiceID
    }
}
