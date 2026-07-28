import SwiftUI

/// THE screen — the only view in this app. No tabs, no navigation stack; the
/// only modal is the system file picker and the Settings sheet.
struct AgentView: View {
    @StateObject private var viewModel: AgentViewModel
    @ObservedObject private var dictation: DictationController
    @ObservedObject private var corpus: CorpusStore
    @ObservedObject private var settings = AppSettings.shared

    @Environment(\.scenePhase) private var scenePhase

    @State private var showingSettings = false
    @State private var showingImporter = false

    /// `viewModel`'s child objects (`dictation`, `corpus`) are also observed
    /// directly here — a plain `let` reference on `viewModel` alone wouldn't
    /// propagate their own `@Published` changes up to this view, since
    /// SwiftUI only tracks objects actually held via `@StateObject` /
    /// `@ObservedObject` at the point they're read.
    @MainActor
    init() {
        let vm = AgentViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _dictation = ObservedObject(wrappedValue: vm.dictation)
        _corpus = ObservedObject(wrappedValue: vm.corpus)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            TranscriptView(
                entries: viewModel.transcript,
                partialTranscript: dictation.partialTranscript,
                isListening: viewModel.phase == .listening,
                inputLevel: dictation.inputLevel
            )
            .frame(maxHeight: .infinity)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(Theme.monoLabel)
                    .foregroundStyle(Theme.webAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
            }

            if let corpusError = corpus.lastError {
                Text(corpusError)
                    .font(Theme.monoLabel)
                    .foregroundStyle(Theme.webAccent)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
            }

            SourceChipView(tracker: viewModel.sourceTracker)
                .padding(.bottom, 8)

            if !settings.hasSeenFirstLaunch {
                firstLaunchNote
            }

            controls
        }
        .padding(16)
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            await viewModel.onAppear()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel.onForeground() }
            }
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            settings.hasSeenFirstLaunch = true
        }) {
            SettingsSheet(onPickFolder: { url in corpus.saveFolderSelection(url) })
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: TextExtractor.supportedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.importFile(url)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("~/voice-agent · \(corpus.indexedDocumentCount) docs indexed")
                .font(Theme.monoLabel)
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
            if corpus.isIndexing {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.dim)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await viewModel.rescanFolder() }
        }
        .onLongPressGesture {
            showingSettings = true
        }
        .padding(.bottom, 12)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Voice Agent, \(corpus.indexedDocumentCount) documents indexed")
        .accessibilityHint("Tap to rescan your folder. Long-press for settings.")
    }

    // MARK: - First-launch note

    private var firstLaunchNote: some View {
        Button {
            showingSettings = true
        } label: {
            Text(firstLaunchMessage)
                .font(Theme.monoLabel)
                .foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    private var firstLaunchMessage: String {
        if settings.corpusBookmarkData == nil {
            return "Pick your Voice Agent folder (in iCloud Drive) and add your Anthropic key in Settings."
        }
        return "Using the on-device voice. Add an ElevenLabs key for a natural one."
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button(action: { viewModel.primaryButtonTapped() }) {
                Text(primaryButtonLabel)
                    .font(Theme.mono)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(TerminalPrimaryButtonStyle())
            .accessibilityLabel(primaryButtonAccessibilityLabel)

            Button {
                showingImporter = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(TerminalSecondaryButtonStyle())
            .accessibilityLabel("Add a document")
        }
    }

    private var primaryButtonLabel: String {
        viewModel.phase == .idle ? "▍ speak" : "▍ stop"
    }

    private var primaryButtonAccessibilityLabel: String {
        viewModel.phase == .idle ? "Speak" : "Stop"
    }
}
