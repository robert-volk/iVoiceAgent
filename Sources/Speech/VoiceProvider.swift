import Foundation

/// What `prepare(_:)` hands back to `play(_:)`. The on-device voice has
/// nothing to prepare ahead of time — `AVSpeechSynthesizer` takes text
/// directly — so it just carries the text through; the network-backed
/// voice carries already-synthesized audio.
enum VoiceUtterance {
    case text(String)
    case audio(Data)
}

/// Abstraction over "speak this sentence out loud." The agent speaks answers
/// one sentence at a time as they stream in (see AgentViewModel), so the unit
/// of work here is a single sentence, not a whole answer — that's what lets
/// speech start before the model has finished thinking.
///
/// `prepare`/`play` are split rather than one `speak(_:)` call so that, for a
/// network-backed voice, sentence N+1's synthesis can run concurrently with
/// sentence N's playback instead of paying a full round-trip of dead air
/// between every sentence — see AgentViewModel.speak(_:).
///
/// Two implementations ship: `SystemVoice` (on-device, free, always
/// available) and `BreezeVoice` (opt-in, needs a key and a voice ID, sounds
/// far more natural). Neither is "the Claude voice chat voice" — see the
/// README and the note in SettingsSheet.swift for why that specific voice
/// isn't reachable from the API.
protocol VoiceProvider {
    var requiresNetwork: Bool { get }

    /// Prepares a sentence to be spoken, without playing it yet.
    func prepare(_ sentence: String) async throws -> VoiceUtterance

    /// Plays an already-prepared utterance. Suspends until playback
    /// finishes naturally, is cancelled via `stop()`, or throws.
    func play(_ utterance: VoiceUtterance) async throws

    /// Stop whatever is currently playing immediately. Used for barge-in.
    func stop()
}

enum VoiceProviderFactory {
    /// Picks Breeze when both a key AND a voice ID are present (Breeze's
    /// text-to-speech endpoint requires a voice ID in the URL path -- there
    /// is no "just use a default voice" option), the on-device voice
    /// otherwise. This is the one place that decision is made — everything
    /// downstream just talks to `VoiceProvider`. `@MainActor` because it
    /// reads `AppSettings.shared`, which is main-actor-isolated; every call
    /// site (AgentViewModel) is already on the main actor.
    @MainActor
    static func current() -> VoiceProvider {
        let voiceID = AppSettings.shared.breezeVoiceID
        if let key = Keychain.load(.breezeAPIKey), !key.isEmpty, !voiceID.isEmpty {
            return BreezeVoice(apiKey: key, voiceID: voiceID)
        }
        return SystemVoice()
    }
}
