import Foundation

enum SourceState: Equatable {
    case none
    case folder
    case web
}

/// Turns the raw `ClaudeStreamEvent` stream into the UI-facing "where is
/// this answer coming from" state. The state change happens on the stream
/// event itself (a `server_tool_use` block starting, or a citation delta
/// arriving) — never by scanning the model's prose — so the chip is always
/// telling the truth about what actually happened, not what the model said
/// happened.
@MainActor
final class SourceTracker: ObservableObject {
    @Published private(set) var state: SourceState = .none
    /// All distinct "filename · p. N" strings cited this turn, in the order
    /// first cited — the collapsed chip shows the first, the expanded chip
    /// (tap-to-expand) shows all of them.
    @Published private(set) var folderReferences: [String] = []
    @Published private(set) var webResults: [WebSearchResult] = []

    func reset() {
        state = .none
        folderReferences = []
        webResults = []
    }

    func handle(_ event: ClaudeStreamEvent) {
        switch event {
        case .webSearchStarted:
            // Once the model has left the folder this turn, the chip stays
            // on "web" — that's the more recent, more relevant signal, even
            // if an earlier citation in the same turn touched a document.
            state = .web

        case .webSearchResults(let results):
            webResults.append(contentsOf: results)

        case .citation(let filename, let pageNumber):
            if state != .web { state = .folder }
            var label = filename
            if let pageNumber { label += " · p. \(pageNumber)" }
            if !folderReferences.contains(label) {
                folderReferences.append(label)
            }

        case .textDelta, .refused, .finished:
            break
        }
    }
}
