import CoreGraphics
import AVFoundation

/// One audio-session configuration for the whole app: the guide speaks and listens in turns,
/// through the speaker, a Bluetooth headset or Ray-Ban Meta glasses (HFP for the mic, A2DP for
/// clearer playback when only listening), ducking any music.
enum AudioSession {
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .duckOthers])
        try session.setActive(true)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
