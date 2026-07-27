import SwiftUI

/// The most important element after the transcript itself: which source is
/// this answer coming from. The colour flip from phosphor green (grounded)
/// to amber (web) is the primary "we left your folder" signal, driven
/// directly by `SourceTracker`'s state — never by this view guessing from
/// the text. Tapping expands it in place to list every file or result used
/// this turn; nothing here navigates away from the single screen.
struct SourceChipView: View {
    @ObservedObject var tracker: SourceTracker
    @State private var isExpanded = false

    var body: some View {
        if tracker.state != .none {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tracker.state == .web ? "globe" : "folder")
                            .font(.system(size: 12))
                        Text(collapsedLabel)
                            .font(Theme.monoLabel)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(accentColor)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        if tracker.state == .folder {
                            ForEach(tracker.folderReferences, id: \.self) { reference in
                                Text(reference)
                                    .font(Theme.monoLabel)
                                    .foregroundStyle(Theme.dim)
                            }
                        } else {
                            ForEach(tracker.webResults, id: \.url) { result in
                                Text("\(result.title) — \(result.url)")
                                    .font(Theme.monoLabel)
                                    .foregroundStyle(Theme.dim)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.leading, 18)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(accentColor, lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(collapsedLabel)
        }
    }

    private var accentColor: Color {
        tracker.state == .web ? Theme.webAccent : Theme.agentText
    }

    private var collapsedLabel: String {
        switch tracker.state {
        case .none:
            return ""
        case .folder:
            if let first = tracker.folderReferences.first {
                return "local · \(first)"
            }
            return "local"
        case .web:
            let count = tracker.webResults.count
            return count > 0 ? "web · \(count) results" : "web · searching"
        }
    }
}
