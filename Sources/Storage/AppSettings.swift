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
        static let corpusBookmark = "corpusBookmarkData"
        static let elevenLabsVoiceID = "elevenLabsVoiceID"
    }

    /// "Breeze Blue" — Robert's chosen ElevenLabs voice for the agent. Not a
    /// claim of matching any particular product's voice — see
    /// VoiceProvider.swift and the README for why.
    static let defaultElevenLabsVoiceID = "brz_mDQBUuJ_P2R8xaDKwiVdQ8M0xJhGkasp"

    @Published var hasSeenFirstLaunch: Bool {
        didSet { UserDefaults.standard.set(hasSeenFirstLaunch, forKey: Keys.hasSeenFirstLaunch) }
    }

    /// Security-scoped bookmark to the user-picked Drive (or other Files
    /// provider) folder. Nil until the user completes the one-time folder
    /// pick; CorpusStore falls back to a local sandbox folder until then.
    @Published var corpusBookmarkData: Data? {
        didSet { UserDefaults.standard.set(corpusBookmarkData, forKey: Keys.corpusBookmark) }
    }

    @Published var elevenLabsVoiceID: String {
        didSet { UserDefaults.standard.set(elevenLabsVoiceID, forKey: Keys.elevenLabsVoiceID) }
    }

    private init() {
        let defaults = UserDefaults.standard
        hasSeenFirstLaunch = defaults.bool(forKey: Keys.hasSeenFirstLaunch)
        corpusBookmarkData = defaults.data(forKey: Keys.corpusBookmark)
        elevenLabsVoiceID = defaults.string(forKey: Keys.elevenLabsVoiceID) ?? Self.defaultElevenLabsVoiceID
    }
}
