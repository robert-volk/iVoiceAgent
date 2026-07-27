import SwiftUI

/// The input-level meter as a single inline row of monospace block glyphs,
/// not a bar chart — keeps it to one line height on the `you` line while
/// listening.
struct LevelMeterView: View {
    let level: Float

    @State private var history: [Float] = Array(repeating: 0, count: 12)

    private static let glyphs: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇"]

    var body: some View {
        Text(rendered)
            .font(Theme.monoSmall)
            .foregroundStyle(Theme.userText)
            .onChange(of: level) { _, newValue in
                history.removeFirst()
                history.append(newValue)
            }
            .accessibilityHidden(true)
    }

    private var rendered: String {
        String(history.map(Self.glyph(for:)))
    }

    private static func glyph(for value: Float) -> Character {
        let clamped = max(0, min(1, value))
        let index = Int(clamped * Float(glyphs.count - 1))
        return glyphs[index]
    }
}
