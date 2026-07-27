import SwiftUI

/// The transcript *is* the centrepiece in this design — there's no orb.
/// Speaker labels sit above each turn in dim lowercase (`you`, `agent`); the
/// text below is in the speaker's colour. While listening, the transcript
/// simply grows a new `you` line with the live partial result and an inline
/// level meter — there's no separate "listening" screen.
struct TranscriptView: View {
    let entries: [TranscriptEntry]
    let partialTranscript: String
    let isListening: Bool
    let inputLevel: Float

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(entries) { entry in
                        turnView(for: entry)
                            .id(entry.id)
                    }
                    if isListening {
                        listeningTurnView
                            .id("listening")
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: entries.last?.text) { _, _ in scrollToBottom(proxy) }
            .onChange(of: isListening) { _, _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            if isListening {
                proxy.scrollTo("listening", anchor: .bottom)
            } else if let last = entries.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func turnView(for entry: TranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.speaker == .user ? "you" : "agent")
                .font(Theme.monoLabel)
                .foregroundStyle(Theme.dim)
            HStack(alignment: .top, spacing: 0) {
                Text(entry.text)
                    .font(Theme.mono)
                    .foregroundStyle(entry.speaker == .user ? Theme.userText : Theme.agentText)
                if entry.speaker == .agent && !entry.isComplete {
                    CaretView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.speaker == .user ? "You said" : "Agent said"): \(entry.text)")
    }

    private var listeningTurnView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("you")
                .font(Theme.monoLabel)
                .foregroundStyle(Theme.dim)
            HStack(alignment: .center, spacing: 8) {
                Text(partialTranscript)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.userText)
                LevelMeterView(level: inputLevel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(partialTranscript.isEmpty ? "Listening" : "You said so far: \(partialTranscript)")
    }
}
