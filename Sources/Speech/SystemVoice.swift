import Foundation
import AVFoundation

/// On-device voice via AVSpeechSynthesizer. Free, fully offline, always
/// available — this is the default until a Breeze key and voice ID are entered, and
/// the permanent fallback if one never is. Clearly synthetic, but reliable.
final class SystemVoice: NSObject, VoiceProvider {
    let requiresNetwork = false

    private let synthesizer = AVSpeechSynthesizer()
    private var pendingContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Nothing to prepare ahead of time for the on-device voice — it just
    /// carries the text through to `play(_:)`.
    func prepare(_ sentence: String) async throws -> VoiceUtterance {
        .text(sentence)
    }

    func play(_ utterance: VoiceUtterance) async throws {
        guard case .text(let sentence) = utterance else { return }
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try Task.checkCancellation()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingContinuation = continuation

            let speechUtterance = AVSpeechUtterance(string: trimmed)
            speechUtterance.voice = Self.preferredVoice()
            speechUtterance.rate = AVSpeechUtteranceDefaultSpeechRate
            speechUtterance.pitchMultiplier = 1.0
            synthesizer.speak(speechUtterance)
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
