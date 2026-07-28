import SwiftUI

/// Shown only when this turn involved a web search — silent the rest of the
/// time, since a plain conversational answer from what the agent already
/// knows doesn't need a source callout the way leaving a document folder
/// used to. Tapping expands it in place to list the actual results used;
/// nothing here navigates away from the single screen.
struct SourceChipView: View {
    @ObservedObject var tracker: SourceTracker
    @State private var isExpanded = false

    var body: some View {
        if tracker.state == .web {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.system(size: 12))
                        Text(collapsedLabel)
                            .font(Theme.monoLabel)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.webAccent)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(tracker.webResults, id: \.url) { result in
                            Text("\(result.title) — \(result.url)")
                                .font(Theme.monoLabel)
                                .foregroundStyle(Theme.dim)
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 18)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.webAccent, lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(collapsedLabel)
        }
    }

    private var collapsedLabel: String {
        let count = tracker.webResults.count
        return count > 0 ? "web · \(count) results" : "web · searching"
    }
}
