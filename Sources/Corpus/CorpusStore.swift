import Foundation

/// Owns the folder this app treats as ground truth: a security-scoped
/// bookmark to an iCloud Drive folder the user picked via the Files app, or —
/// until they've picked one — a local sandbox fallback folder.
///
/// Re-indexing is triggered from three places, not a live file watcher:
/// launch, the app returning to the foreground, and a manual tap on the
/// header. A real `NSFilePresenter`/`NSMetadataQuery` live watcher was
/// deliberately left out to keep the app's promised behavior simple and
/// exactly matched by the README and the acceptance checklist — the three
/// explicit triggers above are what's actually guaranteed, rather than a
/// "should usually update live" feeling that's harder to pin down.
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
        folderLabel = settings.corpusBookmarkData != nil ? "Voice Agent (iCloud)" : "Voice Agent (local)"
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
            folderLabel = "Voice Agent (iCloud)"
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
            // A bookmark existed but no longer resolves. Previously this
            // silently fell back to the empty local folder -- Settings
            // would still say "folder selected" (it only checks whether
            // bookmark *data* exists, not whether it resolves), and
            // rescan() would report 0 docs with no error anywhere,
            // indistinguishable from "the folder is genuinely empty."
            lastError = "Couldn't reach your iCloud folder — re-pick it in Settings."
            return try body(localFallbackFolder)
        }
        guard url.startAccessingSecurityScopedResource() else {
            lastError = "Couldn't access your iCloud folder — re-pick it in Settings."
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
    /// the mirror of dragging a file into the iCloud folder on the PC.
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

        folderLabel = settings.corpusBookmarkData != nil ? "Voice Agent (iCloud)" : "Voice Agent (local)"
        lastError = nil

        let files: [URL] = withFolderAccess { folder in
            (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        }

        let supportedFiles = files.filter { TextExtractor.supportedExtensions.contains($0.pathExtension.lowercased()) }
        var seenFilenames = Set<String>()
        var failures: [String] = []

        for fileURL in supportedFiles {
            let filename = fileURL.lastPathComponent
            seenFilenames.insert(filename)

            // iCloud Drive files can exist as cloud-only placeholders (the
            // familiar cloud-with-arrow icon in Files) until something asks
            // for them. This resource key is simply absent for local files
            // and other providers, so the same loop serves every folder
            // without branching on which one is active.
            if let downloadNote = Self.startDownloadIfNeeded(fileURL) {
                failures.append(downloadNote)
                continue
            }

            guard let signature = Self.signature(for: fileURL) else { continue }
            if fileSignatures[filename] == signature { continue }  // unchanged since last scan

            do {
                let document = try withFolderAccess { _ in try TextExtractor.extract(from: fileURL) }
                let chunks = Chunker.chunk(document)
                index.replaceChunks(forFilename: filename, with: chunks)
                fileSignatures[filename] = signature
            } catch {
                // Most often a scanned/image-only PDF with no text layer, or
                // an empty file. Recorded so it surfaces on screen instead
                // of silently inflating "N docs indexed" with a file that
                // contributed zero chunks to retrieval.
                failures.append("\(filename) — \(error.localizedDescription)")
            }
        }

        // Anything indexed previously but no longer present gets dropped.
        let removedFilenames = Set(fileSignatures.keys).subtracting(seenFilenames)
        for filename in removedFilenames {
            index.removeFile(filename)
            fileSignatures.removeValue(forKey: filename)
        }

        // Ground truth: how many distinct files actually contributed at
        // least one chunk to the index right now — not just how many
        // supported-extension files happen to be sitting in the folder.
        indexedDocumentCount = Set(index.chunks.map(\.filename)).count

        if !failures.isEmpty {
            lastError = "Couldn't read: " + failures.joined(separator: "; ")
        }
    }

    /// Returns a note (and kicks off the download) if `url` is an
    /// iCloud-only placeholder not yet materialized on this device;
    /// returns nil — proceed normally — for anything already local,
    /// which is every non-iCloud provider and any already-downloaded
    /// iCloud file.
    private static func startDownloadIfNeeded(_ url: URL) -> String? {
        guard let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus, status != .current
        else { return nil }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return "\(url.lastPathComponent) (still downloading from iCloud — try again shortly)"
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
