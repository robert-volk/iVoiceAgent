import Foundation
import NaturalLanguage

/// One embedded, persisted chunk.
struct IndexedChunk: Codable {
    let filename: String
    let pageNumber: Int?
    let text: String
    let vector: [Double]
}

/// On-device embeddings for the whole corpus — no API call, no cost. Uses
/// `NLEmbedding`'s sentence embedding, persisted to a small JSON file so a
/// relaunch doesn't have to re-embed unchanged documents.
///
/// Deliberately stored in the app's own Application Support directory, not
/// "beside the corpus" in the Drive-bookmarked folder: writing our own
/// artifact into the user's synced folder would itself sync back through
/// Google Drive as a stray file, and would need its own write-access
/// bookkeeping on top of what CorpusStore already does for the documents
/// themselves. Keeping the index purely local avoids both.
@MainActor
final class EmbeddingIndex {
    private(set) var chunks: [IndexedChunk] = []

    private let embedding = NLEmbedding.sentenceEmbedding(for: .english)
    private let indexFileURL: URL

    init() {
        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceAgentIndex", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        indexFileURL = supportDir.appendingPathComponent("index.json")
        load()
    }

    /// `nil` only if on-device sentence embeddings aren't available at all
    /// for this language/device — in that case retrieval always comes back
    /// empty and every question is answered from the web, which is an honest
    /// (if degraded) fallback rather than a crash.
    func vector(for text: String) -> [Double]? {
        embedding?.vector(for: text)
    }

    func replaceChunks(forFilename filename: String, with newChunks: [Chunk]) {
        chunks.removeAll { $0.filename == filename }
        for chunk in newChunks {
            guard let vector = vector(for: chunk.text) else { continue }
            chunks.append(IndexedChunk(filename: chunk.filename, pageNumber: chunk.pageNumber,
                                        text: chunk.text, vector: vector))
        }
        save()
    }

    func removeFile(_ filename: String) {
        chunks.removeAll { $0.filename == filename }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexFileURL),
              let decoded = try? JSONDecoder().decode([IndexedChunk].self, from: data)
        else { return }
        chunks = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(chunks) else { return }
        try? data.write(to: indexFileURL, options: .atomic)
    }
}
