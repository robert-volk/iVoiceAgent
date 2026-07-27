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
    static let supportedExtensions: Set<String> = ["pdf", "txt", "md", "csv", "rtf", "docx"]

    /// For the `+` button's `.fileImporter` — resolved defensively since not
    /// every one of these has a guaranteed built-in `UTType` constant (`.md`
    /// in particular); a failed resolution is simply left out rather than
    /// crashing the picker.
    static let supportedContentTypes: [UTType] = {
        var types: [UTType] = [.pdf, .plainText, .rtf, .commaSeparatedText]
        if let markdown = UTType(filenameExtension: "md") { types.append(markdown) }
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
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
        case "docx":
            // NSAttributedString's OOXML reader is solidly documented on
            // macOS; iOS support for this exact path has been less
            // consistently documented across OS versions. If a real .docx
            // ever comes back unreadable here, extractAttributed's failure
            // is caught by CorpusStore.rescan() (the file is just skipped,
            // not a crash) — worth a look if docx indexing seems flaky.
            return try extractAttributed(url, filename: filename, documentType: .officeOpenXML)
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
