import Foundation
import AVFoundation

/// On-device voice via AVSpeechSynthesizer. Free, fully offline, always
/// available — this is the default until an ElevenLabs key is entered, and
/// the permanent fallback if one never is. Clearly synthetic, but reliable.
final class SystemVoice: NSObject, VoiceProvider {
    let requiresNetwork = false

    private let synthesizer = AVSpeechSynthesizer()
    private var pendingContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ sentence: String) async throws {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try Task.checkCancellation()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingContinuation = continuation

            let utterance = AVSpeechUtterance(string: trimmed)
            utterance.voice = Self.preferredVoice()
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.pitchMultiplier = 1.0
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        pendingContinuation?.resume(throwing: CancellationError())
        pendingContinuation = nil
    }

    /// Best available conversational English voice on this device — prefers
    /// Premium/Enhanced quality (downloaded via Settings > Accessibility >
    /// Spoken Content on most devices) over the default compact voice.
    static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        func rank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
            switch q {
            case .premium: return 3
            case .enhanced: return 2
            default: return 1
            }
        }
        if let best = voices.sorted(by: { rank($0.quality) > rank($1.quality) }).first {
            return best
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension SystemVoice: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        pendingContinuation?.resume()
        pendingContinuation = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        pendingContinuation?.resume(throwing: CancellationError())
        pendingContinuation = nil
    }
}
