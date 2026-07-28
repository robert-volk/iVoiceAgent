import Foundation

/// One remembered fact about the person, learned from conversation.
struct MemoryFact: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let learnedAt: Date

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.learnedAt = Date()
    }
}

/// Everything this app "knows" about the person it talks to — persisted
/// locally, included as context in every request, and grown over time by a
/// lightweight extraction pass after each turn (see
/// AgentViewModel.finishTurn / ClaudeClient.extractFact). Deliberately not
/// synced anywhere; this is the one thing in the app that's genuinely
/// private to this device, aside from whatever gets sent to Anthropic as
/// conversational context on each turn — see the README.
@MainActor
final class MemoryStore: ObservableObject {
    @Published private(set) var facts: [MemoryFact] = []

    private let fileURL: URL

    init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        fileURL = supportDir.appendingPathComponent("memory.json")
        load()
    }

    /// Formatted for inclusion in the system prompt — empty (not a
    /// placeholder sentence) when nothing's been learned yet, so the prompt
    /// can just conditionally include this section.
    var factsForPrompt: String {
        facts.map { "- \($0.text)" }.joined(separator: "\n")
    }

    /// Skips near-duplicates (case-insensitive exact match) rather than
    /// re-appending the same fact every time it comes up in conversation.
    func remember(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !facts.contains(where: { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return }
        facts.append(MemoryFact(text: trimmed))
        save()
    }

    func forget(_ id: MemoryFact.ID) {
        facts.removeAll { $0.id == id }
        save()
    }

    func forgetEverything() {
        facts.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([MemoryFact].self, from: data)
        else { return }
        facts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(facts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
