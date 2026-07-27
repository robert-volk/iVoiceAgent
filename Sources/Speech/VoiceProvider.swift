import Foundation

/// Abstraction over "speak this sentence out loud." The agent speaks answers
/// one sentence at a time as they stream in (see AgentViewModel), so the unit
/// of work here is a single sentence, not a whole answer — that's what lets
/// speech start before the model has finished thinking.
///
/// Two implementations ship: `SystemVoice` (on-device, free, always
/// available) and `ElevenLabsVoice` (opt-in, needs a key, sounds far more
/// natural). Neither is "the Claude voice chat voice" — see the README and
/// the note in SettingsSheet.swift for why that specific voice isn't
/// reachable from the API.
protocol VoiceProvider {
    var requiresNetwork: Bool { get }

    /// Speak one sentence. Suspends until playback finishes naturally, is
    /// cancelled via `stop()`, or throws. Callers await this in a queue so
    /// sentence N+1 doesn't start until sentence N has finished playing.
    func speak(_ sentence: String) async throws

    /// Stop whatever is currently playing immediately. Used for barge-in.
    func stop()
}

enum VoiceProviderFactory {
    /// Picks ElevenLabs when a key is present, the on-device voice otherwise.
    /// This is the one place that decision is made — everything downstream
    /// just talks to `VoiceProvider`. `@MainActor` because it reads
    /// `AppSettings.shared`, which is main-actor-isolated; every call site
    /// (AgentViewModel) is already on the main actor.
    @MainActor
    static func current() -> VoiceProvider {
        if let key = Keychain.load(.elevenLabsAPIKey), !key.isEmpty {
            return ElevenLabsVoice(apiKey: key, voiceID: AppSettings.shared.elevenLabsVoiceID)
        }
        return SystemVoice()
    }
}
