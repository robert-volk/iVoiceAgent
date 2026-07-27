import Foundation
import AVFoundation

/// Owns the single AVAudioSession configuration this app uses everywhere.
///
/// The mic and the speaker need to be live at the same time — barge-in only
/// works if we can hear the user while the agent is talking. `.playAndRecord`
/// with `mode: .voiceChat` is what makes that safe: `.voiceChat` turns on the
/// system's acoustic echo cancellation, so the mic doesn't just hear the
/// device's own speaker output and mistake it for the user interrupting.
/// Every other mode (`.measurement`, `.default`) skips AEC and would make
/// barge-in fire on the agent's own voice.
enum AudioSession {
    static func activateConversationSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.duckOthers, .allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
