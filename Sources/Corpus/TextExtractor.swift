import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// One page (or, for formats with no page concept, the whole document) of
/// extracted text. `pageNumber` is 1-indexed and only ever set for PDFs —
/// it's what lets the source chip say "lease_2025.pdf · p. 4" instead of
/// just naming the file.
struct ExtractedPage {
    let pageNumber: Int?
    let text: String
}

struct ExtractedDocument {
    let filename: String
    let pages: [ExtractedPage]
}

enum TextExtractorError: LocalizedError {
    case unsupportedType(String)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let ext): return "Unsupported file type: .\(ext)"
        case .unreadable: return "Couldn't read this file."
        }
    }
}

/// Turns a document into plain text. Deliberately narrow: these are the
/// formats a personal "drop it in a folder" corpus actually contains.
enum TextExtractor {
    // .docx is deliberately not supported: NSAttributedString.DocumentType
    // has no OOXML case on iOS (that's a macOS-only reader — confirmed by a
    // real build failure, not just a guess), and parsing a .docx by hand
    // means unzipping it and reading word/document.xml, which needs either
    // a real archive library (a third-party package, ruled out for this
    // app) or a hand-rolled zip reader. Not worth it for v1 — a dropped
    // .docx is simply skipped at indexing time (see CorpusStore.rescan()),
    // not a crash.
    static let supportedExtensions: Set<String> = ["pdf", "txt", "md", "csv", "rtf"]

    /// For the `+` button's `.fileImporter` — resolved defensively since not
    /// every one of these has a guaranteed built-in `UTType` constant (`.md`
    /// in particular); a failed resolution is simply left out rather than
    /// crashing the picker.
    static let supportedContentTypes: [UTType] = {
        var types: [UTType] = [.pdf, .plainText, .rtf, .commaSeparatedText]
        if let markdown = UTType(filenameExtension: "md") { types.append(markdown) }
        return types
    }()

    static func extract(from url: URL) throws -> ExtractedDocument {
        let filename = url.lastPathComponent
        switch url.pathExtension.lowercased() {
        case "pdf":
            return try extractPDF(url, filename: filename)
        case "txt", "md", "csv":
            return try extractPlainText(url, filename: filename)
        case "rtf":
            return try extractAttributed(url, filename: filename, documentType: .rtf)
        default:
            throw TextExtractorError.unsupportedType(url.pathExtension)
        }
    }

    private static func extractPDF(_ url: URL, filename: String) throws -> ExtractedDocument {
        guard let document = PDFDocument(url: url) else { throw TextExtractorError.unreadable }
        var pages: [ExtractedPage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let text = page.string ?? ""
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pages.append(ExtractedPage(pageNumber: index + 1, text: text))
            }
        }
        guard !pages.isEmpty else { throw TextExtractorError.unreadable }
        return ExtractedDocument(filename: filename, pages: pages)
    }

    private static func extractPlainText(_ url: URL, filename: String) throws -> ExtractedDocument {
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            throw TextExtractorError.unreadable
        }
        return ExtractedDocument(filename: filename, pages: [ExtractedPage(pageNumber: nil, text: text)])
    }

    private static func extractAttributed(_ url: URL, filename: String,
                                           documentType: NSAttributedString.DocumentType) throws -> ExtractedDocument {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: documentType]
        guard let attributed = try? NSAttributedString(url: url, options: options, documentAttributes: nil),
              !attributed.string.isEmpty
        else {
            throw TextExtractorError.unreadable
        }
        return ExtractedDocument(filename: filename, pages: [ExtractedPage(pageNumber: nil, text: attributed.string)])
    }
}
