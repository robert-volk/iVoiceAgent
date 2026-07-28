import Foundation
import AVFoundation

enum BreezeVoiceError: LocalizedError {
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .http(let code, let message): return "Breeze error \(code): \(message)"
        case .badResponse: return "Unexpected response from Breeze."
        }
    }
}

/// Opt-in voice via the Breeze Blue API (api.breeze.blue) — the closest
/// available stand-in for a natural conversational voice. Requires network,
/// an API key, and a voice ID (Breeze has no "default voice"; the endpoint
/// requires one in the URL path). See https://docs.breezeblue.ai.
///
/// "Streaming" here means low end-to-end latency: each sentence is one
/// small, fast request, and playback starts the moment that sentence's
/// audio is fully in hand — not incremental byte-level playback of a
/// partially-downloaded file. For sentence-length text (a few seconds of
/// audio) the difference is not perceptible, and this keeps the playback
/// path a plain AVAudioPlayer rather than a hand-built streaming decoder.
final class BreezeVoice: NSObject, VoiceProvider {
    let requiresNetwork = true

    private let apiKey: String
    private let voiceID: String
    private var player: AVAudioPlayer?
    private var pendingContinuation: CheckedContinuation<Void, Error>?

    init(apiKey: String, voiceID: String) {
        self.apiKey = apiKey
        self.voiceID = voiceID
    }

    /// Lightweight key check used by the Settings sheet before saving.
    /// Breeze has no dedicated "am I authenticated" endpoint, so this just
    /// lists voices (a GET any valid key can make) and checks for 200.
    static func validate(apiKey: String) async -> Bool {
        var request = URLRequest(url: URL(string: "https://api.breeze.blue/v1/voices")!)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return false }
        return http.statusCode == 200
    }

    func speak(_ sentence: String) async throws {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try Task.checkCancellation()
        let audioData = try await synthesize(trimmed)
        try Task.checkCancellation()
        try await play(audioData)
    }

    func stop() {
        player?.stop()
        player = nil
        pendingContinuation?.resume(throwing: CancellationError())
        pendingContinuation = nil
    }

    // MARK: - Network

    private func synthesize(_ text: String) async throws -> Data {
        var components = URLComponents(
            url: URL(string: "https://api.breeze.blue/v1/text-to-speech/\(voiceID)")!,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "output_format", value: "mp3")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = ["text": text]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BreezeVoiceError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw BreezeVoiceError.http(http.statusCode, String(message.prefix(200)))
        }
        return data
    }

    // MARK: - Playback

    @MainActor
    private func play(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let newPlayer = try AVAudioPlayer(data: data)
                newPlayer.delegate = self
                pendingContinuation = continuation
                player = newPlayer
                newPlayer.play()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

extension BreezeVoice: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        pendingContinuation?.resume()
        pendingContinuation = nil
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        pendingContinuation?.resume(throwing: error ?? BreezeVoiceError.badResponse)
        pendingContinuation = nil
    }
}
