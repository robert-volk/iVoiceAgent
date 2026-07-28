import Foundation
import SwiftUI

enum AgentPhase: Equatable {
    case idle
    case listening
    case thinking
    case answering
}

struct TranscriptEntry: Identifiable, Equatable {
    enum Speaker: Equatable { case user, agent }
    let id: UUID
    let speaker: Speaker
    var text: String
    var isComplete: Bool

    init(speaker: Speaker, text: String, isComplete: Bool = true) {
        self.id = UUID()
        self.speaker = speaker
        self.text = text
        self.isComplete = isComplete
    }
}

/// Owns the turn loop: idle -> listening -> thinking -> answering -> idle,
/// with barge-in able to cut back from thinking/answering straight to
/// listening at any point. This is the one place that wires
/// DictationController, MemoryStore, ClaudeClient, the VoiceProvider, and
/// SourceTracker together — every other type in the app only knows about
/// its own concern.
@MainActor
final class AgentViewModel: ObservableObject {
    @Published private(set) var phase: AgentPhase = .idle
    @Published private(set) var transcript: [TranscriptEntry] = []
    @Published var errorMessage: String?
    @Published private(set) var justRemembered: String?

    let dictation = DictationController()
    let memory = MemoryStore()
    let sourceTracker = SourceTracker()

    private var voiceProvider: VoiceProvider = VoiceProviderFactory.current()
    private var currentStreamTask: Task<Void, Never>?
    private var history: [ConversationTurn] = []
    /// In-flight `prepare()` calls for the sentence(s) currently being
    /// spoken — tracked so barge-in/Stop can cancel them, since a plain
    /// `Task { ... }` isn't automatically cancelled just because the
    /// enclosing `currentStreamTask` is. See `speak(_:)`.
    private var pendingPrepareTasks: [Task<VoiceUtterance, Error>] = []

    /// "Last ~10 turns" — a turn is a user+agent pair, so this caps the
    /// transcript at 20 entries and the model's own history at the same.
    private static let maxTurns = 10

    init() {
        dictation.onEndpoint = { [weak self] text in
            self?.handleEndpoint(text)
        }
        dictation.onBargeIn = { [weak self] in
            self?.handleBargeIn()
        }
    }

    // MARK: - Lifecycle

    func onAppear() async {
        await dictation.requestPermissionsIfNeeded()
    }

    // MARK: - Primary button

    func primaryButtonTapped() {
        switch phase {
        case .idle:
            startListening()
        case .listening:
            dictation.stopListeningManually()
        case .thinking, .answering:
            stopAnswering(returnToIdle: true)
        }
    }

    // MARK: - Turn loop

    private func startListening() {
        errorMessage = nil
        justRemembered = nil
        phase = .listening
        announce("Listening")
        dictation.startListening()
    }

    private func handleEndpoint(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .idle
            return
        }
        transcript.append(TranscriptEntry(speaker: .user, text: trimmed))
        beginAnswering(question: trimmed)
    }

    private func handleBargeIn() {
        guard phase == .thinking || phase == .answering else { return }
        stopAnswering(returnToIdle: false)
        startListening()
    }

    private func stopAnswering(returnToIdle: Bool) {
        voiceProvider.stop()
        pendingPrepareTasks.forEach { $0.cancel() }
        pendingPrepareTasks.removeAll()
        currentStreamTask?.cancel()
        currentStreamTask = nil
        dictation.stopWatchingForBargeIn()
        if returnToIdle {
            phase = .idle
        }
    }

    private func beginAnswering(question: String) {
        guard let apiKey = Keychain.load(.anthropicAPIKey), !apiKey.isEmpty else {
            errorMessage = "Add your Anthropic API key in Settings to talk to the agent."
            phase = .idle
            return
        }

        phase = .thinking
        announce("Thinking")
        sourceTracker.reset()
        voiceProvider = VoiceProviderFactory.current()
        dictation.watchForBargeIn()

        let client = ClaudeClient(apiKey: apiKey)
        let historySnapshot = history
        let knownFacts = memory.factsForPrompt

        let agentEntry = TranscriptEntry(speaker: .agent, text: "", isComplete: false)
        transcript.append(agentEntry)
        let agentEntryID = agentEntry.id

        currentStreamTask = Task { [weak self] in
            guard let self else { return }
            var sentenceBuffer = ""

            do {
                for try await event in client.streamAnswer(history: historySnapshot, question: question, knownFacts: knownFacts) {
                    try Task.checkCancellation()
                    self.sourceTracker.handle(event)
                    if self.phase == .thinking { self.phase = .answering }

                    switch event {
                    case .webSearchStarted:
                        self.announce("Searching the web")

                    case .webSearchResults:
                        break  // SourceTracker already recorded these for the expanded chip.

                    case .textDelta(let delta):
                        self.appendToTranscript(id: agentEntryID, delta: delta)
                        sentenceBuffer += delta
                        let (complete, remainder) = Self.splitCompleteSentences(sentenceBuffer)
                        sentenceBuffer = remainder
                        if !complete.isEmpty {
                            try await self.speak(complete)
                        }

                    case .refused:
                        let apology = " I can't help with that."
                        self.appendToTranscript(id: agentEntryID, delta: apology)
                        try await self.speak([apology])

                    case .finished:
                        let leftover = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !leftover.isEmpty {
                            try await self.speak([leftover])
                        }
                    }
                }

                self.finishTurn(agentEntryID: agentEntryID, question: question, apiKey: apiKey)
            } catch is CancellationError {
                // Barge-in or a manual Stop already handled the phase change.
            } catch {
                self.finishTranscriptEntry(id: agentEntryID)
                self.errorMessage = error.localizedDescription
                self.dictation.stopWatchingForBargeIn()
                self.phase = .idle
            }
        }
    }

    /// Kicks off `prepare()` for every sentence in this batch immediately
    /// (all at once, not one at a time), then plays them in order. For a
    /// network-backed voice, this overlaps sentence N+1's synthesis with
    /// sentence N's playback instead of paying a full round-trip of dead
    /// air between every sentence -- confirmed by testing as the source of
    /// "too much pause between sentences."
    private func speak(_ sentences: [String]) async throws {
        guard !sentences.isEmpty else { return }
        let provider = voiceProvider
        let tasks = sentences.map { sentence in
            Task { try await provider.prepare(sentence) }
        }
        pendingPrepareTasks = tasks
        defer { pendingPrepareTasks.removeAll() }

        for task in tasks {
            try Task.checkCancellation()
            let utterance = try await task.value
            try await provider.play(utterance)
        }
    }

    private func finishTurn(agentEntryID: UUID, question: String, apiKey: String) {
        finishTranscriptEntry(id: agentEntryID)
        let finalAnswer = transcript.first(where: { $0.id == agentEntryID })?.text ?? ""
        history.append(ConversationTurn(role: .user, text: question))
        history.append(ConversationTurn(role: .assistant, text: finalAnswer))
        trimHistoryAndTranscript()
        dictation.stopWatchingForBargeIn()
        currentStreamTask = nil
        phase = .idle

        // Learning what to remember happens in the background, after the
        // spoken answer is already finished — never delays anything the
        // user hears. A separate, cheap, tool-free call rather than a
        // client-side tool the model invokes mid-stream, to keep the main
        // streaming path's failure modes limited to what's already been
        // hardened there.
        let knownFacts = memory.factsForPrompt
        Task { [weak self] in
            guard let self else { return }
            let extractor = ClaudeClient(apiKey: apiKey)
            if let fact = try? await extractor.extractFact(question: question, answer: finalAnswer, knownFacts: knownFacts) {
                self.memory.remember(fact)
                self.justRemembered = fact
            }
        }
    }

    // MARK: - Transcript helpers

    private func appendToTranscript(id: UUID, delta: String) {
        guard let index = transcript.firstIndex(where: { $0.id == id }) else { return }
        transcript[index].text += delta
    }

    private func finishTranscriptEntry(id: UUID) {
        guard let index = transcript.firstIndex(where: { $0.id == id }) else { return }
        transcript[index].isComplete = true
    }

    private func trimHistoryAndTranscript() {
        let maxEntries = Self.maxTurns * 2
        if transcript.count > maxEntries {
            transcript.removeFirst(transcript.count - maxEntries)
        }
        if history.count > maxEntries {
            history.removeFirst(history.count - maxEntries)
        }
    }

    // MARK: - Sentence splitting

    /// Splits off any sentences that are unambiguously complete — terminal
    /// punctuation immediately followed by whitespace, never just "at the
    /// current end of the streamed-so-far buffer" (which would treat a
    /// still-arriving sentence as finished the moment a period lands, and
    /// would also mis-split decimals like "3.14" since the following
    /// character there is a digit, not whitespace).
    private static func splitCompleteSentences(_ buffer: String) -> (complete: [String], remainder: String) {
        var sentences: [String] = []
        var current = buffer
        while let range = current.range(of: #"[.!?]+\s+"#, options: .regularExpression) {
            let sentence = String(current[current.startIndex..<range.upperBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            current = String(current[range.upperBound...])
        }
        return (sentences, current)
    }

    // MARK: - Accessibility

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}
