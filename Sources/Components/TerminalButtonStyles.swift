import SwiftUI

/// The primary "speak / stop" control: outlined, not filled — 1pt phosphor
/// border on transparent, filling solid only while pressed. Corner radius
/// 4pt everywhere in this design; no pills, no circles.
struct TerminalPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Theme.background : Theme.agentText)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(configuration.isPressed ? Theme.agentText : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.agentText, lineWidth: 1)
            )
    }
}

/// The `+` (add document) button: quiet hairline border, dim glyph.
struct TerminalSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.dim)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(configuration.isPressed ? Theme.hairline : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}
