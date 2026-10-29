import CoreGraphics
import AVFoundation
import Combine
import Foundation

/// Records the microphone as 24 kHz mono 16-bit PCM and sends it to Muse Voice Transcribe
/// (`POST /v1/asr/transcribe`). Supports push-to-talk (`start` / `stop`) and hands-free
/// (`listenOnce`, which ends on silence using `VoiceActivity`).
@MainActor
final class TranscribeService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var level: Float = 0

    nonisolated static let sampleRate = 24_000.0
    private var engine: AVAudioEngine?
    private var accumulator = PCMAccumulator()
    private var meter: Task<Void, Never>?

    static let keywords = [
        "Fix-it Lens", "slip nut", "washer", "P-trap", "tailpiece", "waste pipe", "tap", "faucet", "valve",
        "chain", "sprocket", "axle nut", "derailleur", "brake pad", "spoke", "hinge", "screw", "Allen key",
        "spanner", "wrench", "pliers", "filter", "seal", "gasket", "done", "next", "repeat", "back",
    ]

    static func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: true
        case .denied: false
        default: await AVAudioApplication.requestRecordPermission()
        }
    }

    // MARK: Push-to-talk

    func start() async throws {
        guard !isRecording else { return }
        guard await Self.requestPermission() else { throw FixError.micDenied }
        try AudioSession.activate()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw FixError.micUnavailable }

        let accumulator = PCMAccumulator()
        self.accumulator = accumulator
        try input.installThrowingTap(
            onBus: 0, bufferSize: 2048, format: format,
            block: Self.makeTap(accumulator, sourceRate: format.sampleRate)
        )
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw FixError.micUnavailable
        }
        self.engine = engine
        isRecording = true
        meter = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self else { return }
                self.level = self.accumulator.latestRMS
            }
        }
    }

    /// Stops recording and returns a WAV, or nil if the clip was too short to contain speech.
    func stop() -> Data? {
        guard isRecording else { return nil }
        teardown()
        let samples = accumulator.drain()
        guard Double(samples.count) / Self.sampleRate >= 0.35 else { return nil }
        return WAVWriter.mono16(samples, sampleRate: Int(Self.sampleRate))
    }

    /// Stops recording and throws the audio away.
    func cancel() {
        guard isRecording else { return }
        teardown()
        _ = accumulator.drain()
    }

    // MARK: Hands-free

    /// Listens until the user stops talking. Returns nil if nobody spoke. Cancellation stops the mic.
    func listenOnce() async throws -> Data? {
        try await start()
        var vad = VoiceActivity()
        while true {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                cancel()
                throw CancellationError()
            }
            guard isRecording else { return nil }
            switch vad.feed(accumulator.latestRMS) {
            case .listening: continue
            case .speechEnded: return stop()
            case .noSpeech:
                cancel()
                return nil
            }
        }
    }

    // MARK: Meta ASR

    func transcribe(wav: Data, language: AppLanguage, extraKeywords: [String] = []) async throws -> String {
        let keywords = Array(Set(Self.keywords + extraKeywords).prefix(60))
        let text = try await MetaClient.shared.transcribeWAV(
            wav, languageBias: language.transcribeBias, keywords: keywords, purpose: "Hear the user"
        )
        if text.isEmpty { throw FixError.nothingHeard }
        return text
    }

    // MARK: Private

    private func teardown() {
        meter?.cancel()
        meter = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRecording = false
        level = 0
    }

    /// Built outside the main actor: the tap runs on the realtime audio thread.
    private nonisolated static func makeTap(_ accumulator: PCMAccumulator, sourceRate: Double) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            let step = sourceRate / sampleRate
            var converted: [Int16] = []
            converted.reserveCapacity(Int(Double(count) / step) + 1)
            var energy: Float = 0
            var index: Double = 0
            while index < Double(count) {
                let sample = max(-1, min(1, channel[min(Int(index), count - 1)]))
                energy += sample * sample
                converted.append(Int16(sample * Float(Int16.max)))
                index += step
            }
            accumulator.append(converted, rms: sqrt(energy / Float(max(converted.count, 1))))
        }
    }
}

/// Thread-safe sample buffer shared between the audio thread and the main actor.
final class PCMAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Int16] = []
    private var rms: Float = 0

    func append(_ chunk: [Int16], rms: Float) {
        lock.withLock {
            samples.append(contentsOf: chunk)
            self.rms = rms
        }
    }

    var latestRMS: Float { lock.withLock { rms } }

    func drain() -> [Int16] {
        lock.withLock {
            defer { samples = []; rms = 0 }
            return samples
        }
    }
}

private extension AVAudioNode {
    /// Single place the tap is installed. The iOS 27 SDK adds an error-returning `__installTap` variant,
    /// but the app targets iOS 26, so this uses the classic `installTap`, which raises an Objective-C
    /// exception rather than throwing. The input format is validated before this is called.
    func installThrowingTap(
        onBus bus: AVAudioNodeBus,
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping AVAudioNodeTapBlock
    ) throws {
        installTap(onBus: bus, bufferSize: bufferSize, format: format, block: block)
    }
}

enum WAVWriter {
    static func mono16(_ samples: [Int16], sampleRate: Int) -> Data {
        let dataSize = UInt32(samples.count * 2)
        var data = Data()
        func ascii(_ s: String) { data.append(contentsOf: s.utf8) }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        ascii("RIFF")
        u32(36 + dataSize)
        ascii("WAVE")
        ascii("fmt ")
        u32(16)
        u16(1)                              // PCM
        u16(1)                              // mono
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))         // byte rate
        u16(2)                              // block align
        u16(16)                             // bits per sample
        ascii("data")
        u32(dataSize)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
