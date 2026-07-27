import Foundation

/// A retrievable slice of a document, small enough to embed and cite
/// individually. Carries `(filename, pageNumber)` so the source chip can
/// point at an exact page rather than just a file.
struct Chunk {
    let filename: String
    let pageNumber: Int?
    let text: String
}

/// Splits extracted text into ~800-token chunks with ~15% overlap so an
/// answer near a chunk boundary doesn't lose context. Chunking happens
/// per-page (never spanning two PDF pages) so every chunk keeps a single,
/// unambiguous page number.
///
/// Token count is approximated as whitespace-separated words rather than
/// pulling in a real tokenizer just for chunk sizing — close enough (roughly
/// 1 token ≈ 0.75 words for English prose) and avoids a dependency.
enum Chunker {
    static let targetWordsPerChunk = 600
    static let overlapWords = Int(Double(targetWordsPerChunk) * 0.15)

    static func chunk(_ document: ExtractedDocument) -> [Chunk] {
        var chunks: [Chunk] = []
        for page in document.pages {
            let words = page.text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard !words.isEmpty else { continue }

            var start = 0
            while start < words.count {
                let end = min(start + targetWordsPerChunk, words.count)
                let slice = words[start..<end].joined(separator: " ")
                chunks.append(Chunk(filename: document.filename, pageNumber: page.pageNumber, text: slice))
                if end == words.count { break }
                start = max(0, end - overlapWords)
            }
        }
        return chunks
    }
}
