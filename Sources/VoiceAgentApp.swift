import SwiftUI

@main
struct VoiceAgentApp: App {
    // Permission requests (mic + speech) and the first corpus scan happen in
    // AgentViewModel.onAppear(), triggered by AgentView's `.task` — kept out
    // of this bootstrap so there's exactly one place that owns app startup
    // sequencing.
    var body: some Scene {
        WindowGroup {
            AgentView()
        }
    }
}
