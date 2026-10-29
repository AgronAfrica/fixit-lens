import CoreGraphics
import AVFoundation
import Combine
import Foundation

/// Reads the guide aloud with the on-device voice. Meta's Model API has no text-to-speech endpoint,
/// so this is the one piece of the voice loop that doesn't call Meta; it sends nothing off the device.
@MainActor
final class SpeechService: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false

    private let synth = AVSpeechSynthesizer()
    private var pending: (id: ObjectIdentifier, continuation: CheckedContinuation<Void, Never>)?

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Speaks `text` and returns when it has finished, been interrupted, or the task was cancelled.
    func say(_ text: String, language: AppLanguage, rate: Float = AVSpeechUtteranceDefaultSpeechRate) async {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !Task.isCancelled else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.bestVoice(for: language.voiceCode)
        utterance.rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.1
        try? AudioSession.activate()

        let id = ObjectIdentifier(utterance)
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending = (id, continuation)
                isSpeaking = true
                synth.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    /// Fire-and-forget variant.
    func speak(_ text: String, language: AppLanguage, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        Task { await say(text, language: language, rate: rate) }
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        finish(nil)
    }

    fileprivate func finish(_ id: ObjectIdentifier?) {
        guard let current = pending, id == nil || current.id == id else { return }
        pending = nil
        isSpeaking = false
        current.continuation.resume()
    }

    private static func bestVoice(for code: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == code && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: code)
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finish(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finish(id) }
    }
}
