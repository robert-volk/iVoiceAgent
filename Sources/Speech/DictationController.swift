import Foundation
import Speech
import AVFoundation

/// Drives on-device speech-to-text and, separately, the light-weight level
/// watch used to detect barge-in while the agent is speaking. Two distinct
/// modes share the same audio engine but are never active simultaneously:
///
/// - `startListening()` — full dictation: partial transcript + on-device
///   endpointing (900ms of silence after speech ends the turn, same as a
///   manual tap-to-stop).
/// - `watchForBargeIn()` — no SFSpeechRecognizer task at all, just an input
///   level tap. Cheaper, and avoids two recognition sessions fighting over
///   the mic. When the user talks over the agent, `onBargeIn` fires; the
///   view model then stops playback and calls `startListening()` to
///   actually capture what they're saying. See the caveat in that method's
///   doc comment.
///
/// Speech stays entirely on-device: `requiresOnDeviceRecognition` is set
/// whenever the locale supports it, matching the rest of this developer's
/// apps.
@MainActor
final class DictationController: ObservableObject {
    enum PermissionState: Equatable {
        case notDetermined, granted, denied
    }

    @Published private(set) var isListening = false
    @Published private(set) var isWatchingForBargeIn = false
    @Published var permissionState: PermissionState = .notDetermined
    @Published var errorMessage: String?
    @Published private(set) var partialTranscript: String = ""
    /// Smoothed 0...1 input level, driven by whichever mode is active —
    /// used for the terminal UI's inline `▁▂▃▄▅▆▇` meter.
    @Published private(set) var inputLevel: Float = 0

    /// Fires once with the recognized text when ~900ms of silence follows
    /// speech, the recognizer reports a final result, or the user taps Stop.
    var onEndpoint: ((String) -> Void)?

    /// Fires when, during `watchForBargeIn()`, input level stays above
    /// threshold for a sustained window — the user is talking over the agent.
    var onBargeIn: (() -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: .current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var silenceTimer: Timer?
    private var levelAboveThresholdSince: Date?

    private static let silenceTimeout: TimeInterval = 0.9
    private static let bargeInThreshold: Float = 0.18
    private static let bargeInSustain: TimeInterval = 0.15

    // MARK: - Permissions

    func requestPermissionsIfNeeded() async {
        async let speechOK = requestSpeechAuthorization()
        async let micOK = requestMicAuthorization()
        let granted = await speechOK && (await micOK)
        permissionState = granted ? .granted : .denied
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Full dictation (listening state)

    func startListening() {
        guard permissionState == .granted else { return }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }

        stopEverything()

        do {
            try AudioSession.activateConversationSession()
        } catch {
            errorMessage = "Couldn't start the microphone."
            return
        }

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request = recognitionRequest

        installTap(recognitionRequest: recognitionRequest) { [weak self] level in
            self?.inputLevel = level
        }

        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Couldn't start the microphone."
            teardownTap()
            return
        }

        partialTranscript = ""
        isListening = true

        task = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.partialTranscript = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                    if result.isFinal {
                        self.finishListening()
                    }
                }
                if error != nil {
                    self.finishListening()
                }
            }
        }
    }

    /// Manual "tap to stop" — ends listening and reports whatever was heard.
    func stopListeningManually() {
        finishListening()
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        guard !partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        silenceTimer = Timer.scheduledTimer(withTimeInterval: Self.silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finishListening() }
        }
    }

    private func finishListening() {
        guard isListening else { return }
        let text = partialTranscript
        isListening = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        teardownRecognition()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onEndpoint?(trimmed)
        }
    }

    // MARK: - Barge-in watch (answering state)

    /// Installs a level-only tap while the agent is speaking. Deliberately
    /// does not run a full SFSpeechRecognizer task (that would mean two
    /// recognition sessions contending for the mic at once). The first
    /// fraction of a second of an interruption is lost — once `onBargeIn`
    /// fires, the caller stops playback and calls `startListening()` fresh,
    /// which is an accepted trade-off for a personal app rather than true
    /// full-duplex capture.
    func watchForBargeIn() {
        guard permissionState == .granted, !isWatchingForBargeIn, !isListening else { return }
        do {
            try AudioSession.activateConversationSession()
        } catch {
            return
        }
        levelAboveThresholdSince = nil
        installTap(recognitionRequest: nil) { [weak self] level in
            self?.handleBargeInLevel(level)
        }
        do {
            try audioEngine.start()
            isWatchingForBargeIn = true
        } catch {
            teardownTap()
        }
    }

    func stopWatchingForBargeIn() {
        guard isWatchingForBargeIn else { return }
        isWatchingForBargeIn = false
        teardownTap()
    }

    private func handleBargeInLevel(_ level: Float) {
        inputLevel = level
        if level > Self.bargeInThreshold {
            if let since = levelAboveThresholdSince {
                if Date().timeIntervalSince(since) >= Self.bargeInSustain {
                    levelAboveThresholdSince = nil
                    onBargeIn?()
                }
            } else {
                levelAboveThresholdSince = Date()
            }
        } else {
            levelAboveThresholdSince = nil
        }
    }

    // MARK: - Engine plumbing

    /// `recognitionRequest` is captured as a plain local value by the tap
    /// closure (never `self.request`) so the real-time audio-thread callback
    /// never touches this MainActor-isolated instance directly — it only
    /// appends to the request and computes a pure RMS value, then hops back
    /// to the main actor to publish the result.
    private func installTap(recognitionRequest: SFSpeechAudioBufferRecognitionRequest?,
                             onLevel: @escaping (Float) -> Void) {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            recognitionRequest?.append(buffer)
            let level = Self.rmsLevel(of: buffer)
            Task { @MainActor in
                onLevel(level)
            }
        }
        audioEngine.prepare()
    }

    private func teardownTap() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        inputLevel = 0
    }

    private func teardownRecognition() {
        teardownTap()
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private func stopEverything() {
        if isWatchingForBargeIn {
            stopWatchingForBargeIn()
        }
        if isListening {
            isListening = false
            silenceTimer?.invalidate()
            silenceTimer = nil
            teardownRecognition()
        }
    }

    private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        let samples = channelData[0]
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = samples[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        // Typical speech RMS through the built-in mic tops out well under 1.0;
        // this gain just spreads that range across the 0...1 UI scale.
        return min(1.0, rms * 6)
    }
}
