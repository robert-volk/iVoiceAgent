import Foundation

/// One prior turn of conversation, kept as plain text — only the *current*
/// question gets document blocks attached (see `userTurnJSON`), since each
/// turn re-retrieves its own excerpts independently rather than
/// accumulating documents across the whole conversation.
struct ConversationTurn {
    enum Role: String { case user, assistant }
    let role: Role
    let text: String
}

struct WebSearchResult {
    let title: String
    let url: String
}

/// High-level events the UI actually reacts to. `SourceTracker` turns these
/// into the on-screen `.folder` / `.web` state; `AgentViewModel` turns the
/// text deltas into speech, sentence by sentence.
enum ClaudeStreamEvent {
    case textDelta(String)
    case webSearchStarted
    case webSearchResults([WebSearchResult])
    case citation(filename: String, pageNumber: Int?)
    case refused
    case finished(stopReason: String)
}

enum ClaudeClientError: LocalizedError {
    case badResponse
    case api(Int, String)

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Unexpected response from Claude."
        case .api(let code, let message): return "Claude API error \(code): \(message)"
        }
    }
}

/// Raw SSE client for the Messages API. There's no official Anthropic Swift
/// SDK, so this talks to `/v1/messages` directly over `URLSession` rather
/// than reaching for a third-party wrapper.
final class ClaudeClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-opus-5"
    private static let maxContinuations = 3

    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Streams one full answer, including automatic `pause_turn`
    /// continuations (capped at `maxContinuations` — a multi-round web
    /// search inside a single turn can legitimately hit the model's
    /// server-tool iteration limit).
    func streamAnswer(history: [ConversationTurn], question: String, excerpts: [Excerpt]) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var messages = history.map(Self.turnJSON)
                    messages.append(Self.userTurnJSON(question: question, excerpts: excerpts))

                    var attempts = 0
                    var lastStopReason = "end_turn"

                    while true {
                        try Task.checkCancellation()
                        let (stopReason, content) = try await self.streamOnce(
                            messages: messages, excerpts: excerpts, continuation: continuation
                        )
                        lastStopReason = stopReason

                        if stopReason == "refusal" {
                            continuation.yield(.refused)
                            break
                        }
                        if stopReason == "pause_turn", attempts < Self.maxContinuations {
                            attempts += 1
                            messages.append(["role": "assistant", "content": content])
                            continue
                        }
                        break
                    }

                    continuation.yield(.finished(stopReason: lastStopReason))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - One HTTP request / SSE stream

    private func streamOnce(
        messages: [[String: Any]],
        excerpts: [Excerpt],
        continuation: AsyncThrowingStream<ClaudeStreamEvent, Error>.Continuation
    ) async throws -> (stopReason: String, content: [[String: Any]]) {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 1024,
            "stream": true,
            "system": SystemPrompt.text,
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": "low"],
            "tools": [["type": "web_search_20260209", "name": "web_search"]],
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeClientError.badResponse }

        guard (200..<300).contains(http.statusCode) else {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            let message = (try? JSONSerialization.jsonObject(with: errorData) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                ?? "HTTP \(http.statusCode)"
            throw ClaudeClientError.api(http.statusCode, message)
        }

        // document_index (as sent to the API, in request order) -> our own
        // Excerpt, so a citation delta maps straight back to a real
        // filename/page without trusting the model to echo it in prose.
        let excerptsByIndex = Dictionary(uniqueKeysWithValues: excerpts.enumerated().map { ($0.offset, $0.element) })

        var blocks: [Int: BlockState] = [:]
        var order: [Int] = []
        var stopReason = "end_turn"

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let jsonString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard let data = jsonString.data(using: .utf8),
                  let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let type = event["type"] as? String
            else { continue }

            switch type {
            case "content_block_start":
                guard let index = event["index"] as? Int,
                      let block = event["content_block"] as? [String: Any]
                else { continue }
                let state = BlockState(raw: block)
                blocks[index] = state
                order.append(index)

                if let blockType = block["type"] as? String {
                    if blockType == "server_tool_use", (block["name"] as? String) == "web_search" {
                        continuation.yield(.webSearchStarted)
                    } else if blockType == "web_search_tool_result" {
                        let results = Self.parseWebSearchResults(block)
                        if !results.isEmpty { continuation.yield(.webSearchResults(results)) }
                    }
                }

            case "content_block_delta":
                guard let index = event["index"] as? Int,
                      let delta = event["delta"] as? [String: Any],
                      let state = blocks[index]
                else { continue }
                state.applyDelta(delta)

                switch delta["type"] as? String {
                case "text_delta":
                    if let text = delta["text"] as? String { continuation.yield(.textDelta(text)) }
                case "citations_delta":
                    if let citation = delta["citation"] as? [String: Any],
                       let docIndex = citation["document_index"] as? Int,
                       let excerpt = excerptsByIndex[docIndex] {
                        continuation.yield(.citation(filename: excerpt.filename, pageNumber: excerpt.pageNumber))
                    }
                default:
                    break
                }

            case "message_delta":
                if let delta = event["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
                    stopReason = reason
                }

            default:
                break
            }
        }

        let finalContent = order.compactMap { blocks[$0]?.finalized() }
        return (stopReason, finalContent)
    }

    private static func parseWebSearchResults(_ block: [String: Any]) -> [WebSearchResult] {
        guard let content = block["content"] as? [[String: Any]] else { return [] }
        return content.compactMap { item in
            guard let title = item["title"] as? String, let url = item["url"] as? String else { return nil }
            return WebSearchResult(title: title, url: url)
        }
    }

    // MARK: - Request JSON construction

    private static func turnJSON(_ turn: ConversationTurn) -> [String: Any] {
        ["role": turn.role.rawValue, "content": turn.text]
    }

    /// Attaches the current turn's retrieved excerpts as citation-enabled
    /// `document` blocks ahead of the question text, so grounded answers
    /// come back with real citations instead of the model naming a file
    /// from memory. See SystemPrompt.swift for the accompanying instruction
    /// not to read citation/page detail aloud.
    private static func userTurnJSON(question: String, excerpts: [Excerpt]) -> [String: Any] {
        guard !excerpts.isEmpty else {
            return ["role": "user", "content": question]
        }

        var content: [[String: Any]] = excerpts.map { excerpt in
            var title = excerpt.filename
            if let page = excerpt.pageNumber { title += " · p. \(page)" }
            return [
                "type": "document",
                "source": ["type": "text", "media_type": "text/plain", "data": excerpt.text],
                "title": title,
                "citations": ["enabled": true]
            ] as [String: Any]
        }
        content.append(["type": "text", "text": question])
        return ["role": "user", "content": content]
    }
}

/// Reconstructs one content block from its `content_block_start` payload
/// plus whatever deltas streamed against it, so it can be resent verbatim on
/// a `pause_turn` continuation. Tool-result blocks (e.g.
/// `web_search_tool_result`) arrive fully-formed at `content_block_start`
/// with no deltas, so they fall through `finalized()` unchanged.
///
/// Best-effort for `thinking` blocks specifically: with `display: "omitted"`
/// (the default this app uses — see ClaudeClient's request body) the
/// `thinking` text is empty and no exotic signature reconstruction should be
/// needed, but this hasn't been exercised against a live `pause_turn` in
/// testing (that path requires the model to hit its own internal 10-round
/// server-tool iteration limit, which a single web search per turn rarely
/// does). If a continuation ever 400s, ClaudeClient surfaces it as a normal
/// thrown error rather than silently retrying — see AgentViewModel's
/// handling of stream errors.
private final class BlockState {
    var raw: [String: Any]
    private var textAccumulator = ""
    private var jsonAccumulator = ""
    private var citationsAccumulator: [[String: Any]] = []

    init(raw: [String: Any]) {
        self.raw = raw
    }

    func applyDelta(_ delta: [String: Any]) {
        switch delta["type"] as? String {
        case "text_delta":
            if let text = delta["text"] as? String { textAccumulator += text }
        case "thinking_delta":
            if let text = delta["thinking"] as? String { textAccumulator += text }
        case "input_json_delta":
            if let partial = delta["partial_json"] as? String { jsonAccumulator += partial }
        case "citations_delta":
            if let citation = delta["citation"] as? [String: Any] { citationsAccumulator.append(citation) }
        case "signature_delta":
            if let signature = delta["signature"] as? String { raw["signature"] = signature }
        default:
            break
        }
    }

    func finalized() -> [String: Any] {
        var block = raw
        switch raw["type"] as? String {
        case "text":
            block["text"] = textAccumulator
            if !citationsAccumulator.isEmpty { block["citations"] = citationsAccumulator }
        case "thinking":
            block["thinking"] = textAccumulator
        case "server_tool_use", "tool_use":
            if !jsonAccumulator.isEmpty,
               let data = jsonAccumulator.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                block["input"] = parsed
            }
        default:
            break
        }
        return block
    }
}
