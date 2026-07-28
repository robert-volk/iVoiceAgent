import SwiftUI

/// THE screen — the only view in this app. No tabs, no navigation stack; the
/// only modal is the Settings sheet.
struct AgentView: View {
    @StateObject private var viewModel: AgentViewModel
    @ObservedObject private var dictation: DictationController
    @ObservedObject private var memory: MemoryStore
    @ObservedObject private var settings = AppSettings.shared

    @State private var showingSettings = false

    /// `viewModel`'s child objects (`dictation`, `memory`) are also observed
    /// directly here — a plain `let` reference on `viewModel` alone wouldn't
    /// propagate their own `@Published` changes up to this view, since
    /// SwiftUI only tracks objects actually held via `@StateObject` /
    /// `@ObservedObject` at the point they're read.
    @MainActor
    init() {
        let vm = AgentViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _dictation = ObservedObject(wrappedValue: vm.dictation)
        _memory = ObservedObject(wrappedValue: vm.memory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            TranscriptView(
                entries: viewModel.transcript,
                partialTranscript: dictation.partialTranscript,
                isListening: viewModel.phase == .listening || viewModel.phase == .recordingMemory,
                inputLevel: dictation.inputLevel
            )
            .frame(maxHeight: .infinity)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(Theme.monoLabel)
                    .foregroundStyle(Theme.webAccent)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
            }

            if let remembered = viewModel.justRemembered {
                Text("Remembered: \(remembered)")
                    .font(Theme.monoLabel)
                    .foregroundStyle(Theme.agentText)
                    .lineLimit(2)
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
        .sheet(isPresented: $showingSettings, onDismiss: {
            settings.hasSeenFirstLaunch = true
        }) {
            SettingsSheet(memory: memory)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("~/voice-agent · \(memory.facts.count) things remembered")
                .font(Theme.monoLabel)
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onLongPressGesture {
            showingSettings = true
        }
        .padding(.bottom, 12)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Voice Agent, \(memory.facts.count) things remembered")
        .accessibilityHint("Long-press for settings.")
    }

    // MARK: - First-launch note

    private var firstLaunchNote: some View {
        Button {
            showingSettings = true
        } label: {
            Text("Add your Anthropic key in Settings to talk to the agent. A Breeze key and voice ID are optional, for a more natural voice.")
                .font(Theme.monoLabel)
                .foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    // MARK: - Controls

    private var controls: some View {
        Button(action: { viewModel.primaryButtonTapped() }) {
            Text(primaryButtonLabel)
                .font(Theme.mono)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(TerminalPrimaryButtonStyle())
        .accessibilityLabel(primaryButtonAccessibilityLabel)
    }

    private var primaryButtonLabel: String {
        viewModel.phase == .idle ? "▍ speak" : "▍ stop"
    }

    private var primaryButtonAccessibilityLabel: String {
        viewModel.phase == .idle ? "Speak" : "Stop"
    }
}
