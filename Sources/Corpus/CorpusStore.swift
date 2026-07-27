import Foundation

/// Owns the folder this app treats as ground truth: a security-scoped
/// bookmark to a Google Drive folder the user picked via the Files app, or —
/// until they've picked one — a local sandbox fallback folder.
///
/// Re-indexing is triggered from three places, not a live file watcher:
/// launch, the app returning to the foreground, and a manual tap on the
/// header. A real `NSFilePresenter` was deliberately left out — third-party
/// File Provider extensions (Google Drive's included) don't reliably deliver
/// presenter change notifications across process boundaries, so one would
/// give a false sense of live-ness without actually being dependable. The
/// three explicit triggers above are what's actually promised in the
/// README and the acceptance checklist.
@MainActor
final class CorpusStore: ObservableObject {
    @Published private(set) var indexedDocumentCount = 0
    @Published private(set) var isIndexing = false
    @Published private(set) var folderLabel = "no folder selected"
    @Published var lastError: String?

    let index = EmbeddingIndex()

    /// filename -> "size:modificationDate", used to skip re-embedding files
    /// that haven't changed since the last scan.
    private var fileSignatures: [String: String] = [:]
    private let settings = AppSettings.shared

    private lazy var localFallbackFolder: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent("Voice Agent", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    init() {
        folderLabel = settings.corpusBookmarkData != nil ? "Voice Agent (Drive)" : "Voice Agent (local)"
    }

    // MARK: - Folder selection

    /// Called after the user picks a folder via `.fileImporter`. `url` is
    /// security-scoped for this access session only; we use that window to
    /// mint a bookmark that survives relaunches, then let the session lapse.
    func saveFolderSelection(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            lastError = "Couldn't access that folder."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            settings.corpusBookmarkData = bookmark
            folderLabel = "Voice Agent (Drive)"
            Task { await rescan() }
        } catch {
            lastError = "Couldn't remember that folder: \(error.localizedDescription)"
        }
    }

    /// Resolves the active folder (bookmarked, or the local fallback) for
    /// the duration of `body`, holding security-scoped access open only for
    /// that call.
    private func withFolderAccess<T>(_ body: (URL) throws -> T) rethrows -> T {
        guard let bookmarkData = settings.corpusBookmarkData else {
            return try body(localFallbackFolder)
        }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmarkData, options: [],
                                  relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return try body(localFallbackFolder)
        }
        guard url.startAccessingSecurityScopedResource() else {
            return try body(localFallbackFolder)
        }
        defer { url.stopAccessingSecurityScopedResource() }

        if isStale, let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            settings.corpusBookmarkData = refreshed
        }
        return try body(url)
    }

    // MARK: - Import

    /// Copies a phone-picked file into the active folder, then re-indexes —
    /// the mirror of dragging a file into the Drive folder on the PC.
    func importFile(from sourceURL: URL) {
        let didAccessSource = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccessSource { sourceURL.stopAccessingSecurityScopedResource() } }

        withFolderAccess { folder in
            let destination = folder.appendingPathComponent(sourceURL.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destination)
            } catch {
                lastError = "Couldn't import \(sourceURL.lastPathComponent): \(error.localizedDescription)"
            }
        }
        Task { await rescan() }
    }

    // MARK: - Scanning

    func rescan() async {
        guard !isIndexing else { return }
        isIndexing = true
        defer { isIndexing = false }

        folderLabel = settings.corpusBookmarkData != nil ? "Voice Agent (Drive)" : "Voice Agent (local)"

        let files: [URL] = withFolderAccess { folder in
            (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        }

        let supportedFiles = files.filter { TextExtractor.supportedExtensions.contains($0.pathExtension.lowercased()) }
        var seenFilenames = Set<String>()

        for fileURL in supportedFiles {
            let filename = fileURL.lastPathComponent
            seenFilenames.insert(filename)

            guard let signature = Self.signature(for: fileURL) else { continue }
            if fileSignatures[filename] == signature { continue }  // unchanged since last scan

            let extracted: ExtractedDocument? = withFolderAccess { _ in try? TextExtractor.extract(from: fileURL) }
            guard let document = extracted else { continue }

            let chunks = Chunker.chunk(document)
            index.replaceChunks(forFilename: filename, with: chunks)
            fileSignatures[filename] = signature
        }

        // Anything indexed previously but no longer present gets dropped.
        let removedFilenames = Set(fileSignatures.keys).subtracting(seenFilenames)
        for filename in removedFilenames {
            index.removeFile(filename)
            fileSignatures.removeValue(forKey: filename)
        }

        indexedDocumentCount = seenFilenames.count
    }

    private static func signature(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return nil
        }
        let date = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values.fileSize ?? 0
        return "\(size):\(date)"
    }
}
