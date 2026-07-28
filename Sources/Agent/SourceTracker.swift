import Foundation

enum SourceState: Equatable {
    case none
    case web
}

/// Turns the raw `ClaudeStreamEvent` stream into "did this answer involve a
/// web search" — the state change happens on the stream event itself (a
/// `server_tool_use` block starting), never by scanning the model's prose,
/// so the chip is always telling the truth about what actually happened.
@MainActor
final class SourceTracker: ObservableObject {
    @Published private(set) var state: SourceState = .none
    @Published private(set) var webResults: [WebSearchResult] = []

    func reset() {
        state = .none
        webResults = []
    }

    func handle(_ event: ClaudeStreamEvent) {
        switch event {
        case .webSearchStarted:
            state = .web
        case .webSearchResults(let results):
            webResults.append(contentsOf: results)
        case .textDelta, .refused, .finished:
            break
        }
    }
}
