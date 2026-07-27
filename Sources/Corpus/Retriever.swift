import Foundation

/// A single retrieved passage, ready to become both a Claude `document`
/// content block and a line in the expanded source chip.
struct Excerpt {
    let filename: String
    let pageNumber: Int?
    let text: String
    let score: Double
}

/// Cosine-similarity retrieval over the on-device embedding index.
/// `@MainActor` because `EmbeddingIndex` (which this reads) is — every call
/// site (AgentViewModel) is already on the main actor.
@MainActor
enum Retriever {
    /// Below this, a chunk is treated as "not actually about the question."
    /// This is a heuristic, not a hard cutoff — phrasing varies enough that
    /// the model, not this floor, makes the final call on whether the
    /// documents actually answer the question (see SystemPrompt.swift and
    /// the `.folder` vs `.web` split in SourceTracker).
    static let similarityFloor = 0.28
    static let topK = 6

    static func topExcerpts(for query: String, index: EmbeddingIndex) -> [Excerpt] {
        guard let queryVector = index.vector(for: query) else { return [] }

        let scored: [Excerpt] = index.chunks.compactMap { chunk in
            let score = cosineSimilarity(queryVector, chunk.vector)
            guard score >= similarityFloor else { return nil }
            return Excerpt(filename: chunk.filename, pageNumber: chunk.pageNumber, text: chunk.text, score: score)
        }
        return Array(scored.sorted { $0.score > $1.score }.prefix(topK))
    }

    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}
