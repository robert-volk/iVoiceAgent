import SwiftUI

/// Design tokens for the "Terminal" visual direction: monospaced,
/// transcript-forward, phosphor-on-black. See the build spec §5 — this is
/// the single source of truth for the palette so no view hardcodes a hex
/// value.
enum Theme {
    static let background = Color(red: 0x0B / 255, green: 0x0D / 255, blue: 0x0C / 255)
    static let agentText = Color(red: 0x7C / 255, green: 0xE0 / 255, blue: 0xA6 / 255)
    static let userText = Color(red: 0xD6 / 255, green: 0xE0 / 255, blue: 0xD8 / 255)
    /// Labels, metadata, dim rules. Under 4.5:1 contrast on `background` —
    /// decorative use only, never for load-bearing information.
    static let dim = Color(red: 0x4E / 255, green: 0x5A / 255, blue: 0x52 / 255)
    static let hairline = Color(red: 0x23 / 255, green: 0x30 / 255, blue: 0x2A / 255)
    static let webAccent = Color(red: 0xE0 / 255, green: 0xA0 / 255, blue: 0x3C / 255)

    static let cornerRadius: CGFloat = 4

    static let mono = Font.system(.body, design: .monospaced)
    static let monoSmall = Font.system(.footnote, design: .monospaced)
    static let monoLabel = Font.system(.caption, design: .monospaced)
}
