import SwiftUI

/// The "alive" signal in this design in place of an orb — an 8×15pt solid
/// block that trails the agent's streaming text and blinks on a crisp
/// 530ms cycle, disappearing entirely once the turn is complete.
struct CaretView: View {
    @State private var visible = true
    private let timer = Timer.publish(every: 0.53, on: .main, in: .common).autoconnect()

    var body: some View {
        Rectangle()
            .fill(Theme.agentText)
            .frame(width: 8, height: 15)
            .opacity(visible ? 1 : 0)
            .onReceive(timer) { _ in visible.toggle() }
            .accessibilityHidden(true)
    }
}
