import CoreGraphics
import Combine
import Foundation
import SwiftUI
import UIKit

/// "Fix it together": a Fixer streams their camera (iPhone or Ray-Ban Meta glasses) to up to three
/// Helpers (another iPhone running Fix-it Lens, or any web browser). A Helper taps the picture and
/// SAM 3.1 outlines that part on the Fixer's frame; the outline is drawn on every screen and re-anchored
/// on keyframes so it follows the part. Speech goes through Muse Voice Transcribe and Muse Spark
/// translates it into the listener's language (spoken with on-device TTS). Muse Spark writes the
/// session up as a replayable guide ("Repair memory").
///
/// Every Meta model call runs here, on the Fixer's phone, with the Fixer's key. Helpers and the relay
/// never see a key, and the relay never sees anything but frames, taps and text.
@MainActor
final class TogetherSession: ObservableObject {
    enum Phase: Equatable { case idle, connecting, active, ended(String) }

    struct Peer: Identifiable, Equatable {
        var id: String { name }
        var name: String
        var language: String
        var platform: String
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var role: TogetherRole = .fixer
    @Published private(set) var code = ""
    @Published private(set) var link: TogetherTransport.Link = .connecting
    @Published private(set) var peers: [Peer] = []
    @Published private(set) var peerCount = 0
    @Published private(set) var frame: UIImage?          // Helper: the Fixer's picture. Fixer: own latest frame.
    @Published private(set) var mask: SharedMask?
    @Published private(set) var maskOverlay: UIImage?
    @Published private(set) var captions: [Caption] = []
    @Published private(set) var memorySteps: [String] = []
    @Published private(set) var memoryTitle = ""
    @Published private(set) var safetyStop: String?
    @Published private(set) var busy: String?            // "SAM 3.1 outlining…" etc.
    @Published private(set) var lastTiming: String?
    @Published private(set) var isDemo = false
    @Published private(set) var savedMemory: RepairMemory?
    @Published private(set) var fps: Double = 0

    var shareURL: URL? { code.isEmpty ? nil : Together.shareURL(relay: relay, code: code) }

    let relay: URL
    let frames = FrameRing()
    private(set) var language: AppLanguage = .english
    private var name = "Fixer"
    private var transport: TogetherTransport?
    private var pacer = StreamPacer()
    private var tracker = MaskTracker()
    private var masks: [SharedMask] = []
    private var trackTask: Task<Void, Never>?
    private var memoryTask: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?
    private var frameEncoding = false
    private var sentFrames = 0
    private var fpsWindow = Date()
    private var nextMaskID = 1
    private let sam = SAMService()
    private let voice: SpeechService
    private let mic: TranscribeService
    private let store = RepairMemoryStore()

    init(relay: URL, voice: SpeechService, mic: TranscribeService) {
        self.relay = relay
        self.voice = voice
        self.mic = mic
    }

    // MARK: Start / join / leave

    /// Fixer: open a room and start streaming whatever `feed` delivers (wired to the active camera source).
    func startAsFixer(name: String, language: AppLanguage, demo: Bool = false) {
        reset()
        role = .fixer
        self.name = name
        self.language = language
        code = Together.newCode()
        isDemo = demo
        phase = .connecting
        if demo {
            link = .live
            phase = .active
            runFixerDemo()
            return
        }
        connect()
    }

    /// Helper on an iPhone: join a code (or a pasted share link).
    func join(_ codeOrLink: String, name: String, language: AppLanguage) -> Bool {
        guard let code = Together.code(from: codeOrLink) ?? Together.normalize(code: codeOrLink) else { return false }
        reset()
        role = .helper
        self.name = name
        self.language = language
        self.code = code
        phase = .connecting
        connect()
        return true
    }

    func leave() {
        if role == .fixer, !isDemo, !captions.isEmpty || !masks.isEmpty { writeMemory(final: true) }
        transport?.close()
        transport = nil
        trackTask?.cancel()
        demoTask?.cancel()
        phase = .ended("Session ended")
        voice.stop()
    }

    private func reset() {
        transport?.close()
        transport = nil
        trackTask?.cancel(); memoryTask?.cancel(); demoTask?.cancel()
        frames.clear()
        pacer = StreamPacer()
        tracker = MaskTracker()
        masks = []
        mask = nil; maskOverlay = nil; frame = nil
        captions = []; memorySteps = []; memoryTitle = ""
        safetyStop = nil; busy = nil; lastTiming = nil; savedMemory = nil
        peers = []; peerCount = 0
    }

    private func connect() {
        let transport = TogetherTransport(relay: relay, code: code, role: role, name: name, language: language.rawValue)
        transport.onLink = { [weak self] link in
            guard let self else { return }
            self.link = link
            if case .closed(let why) = link { self.phase = .ended(why) }
            if link == .live || link == .snapshot { self.phase = .active }
            if link == .snapshot, self.role == .fixer { self.pacer.linkDegraded(); self.transport?.send(.mode("snapshot")) }
            if link == .live, self.role == .fixer { self.transport?.send(.mode("live")) }
        }
        transport.onMessage = { [weak self] in self?.handle($0) }
        transport.onMedia = { [weak self] in self?.handle($0) }
        self.transport = transport
        transport.connect()
        if role == .fixer { startTracking() }
    }

    // MARK: Fixer: frames

    /// Feed every camera frame here (from CameraService.onFrame or GlassesCameraService.onFrame, any thread).
    nonisolated func ingest(_ image: UIImage) {
        Task { @MainActor in self.ingestOnMain(image) }
    }

    private func ingestOnMain(_ image: UIImage) {
        guard role == .fixer, phase == .active || phase == .connecting else { return }
        let stored = frames.push(image)
        frame = image
        let now = ProcessInfo.processInfo.systemUptime
        guard !isDemo, !frameEncoding, peerCount > 1 || link == .snapshot,
              pacer.shouldSend(now: now, hasViewers: peerCount > 1 || link == .snapshot) else { return }
        frameEncoding = true
        let seq = stored.seq
        let live = pacer.mode == .live
        Task.detached(priority: .userInitiated) {
            // 640 px long edge at q0.55 is ~35-60 KB: smooth at 12 fps on LTE, still sharp enough to point at a nut.
            let jpeg = ImageCodec.normalized(image, maxEdge: live ? 640 : 960).jpegData(compressionQuality: live ? 0.55 : 0.7)
            await MainActor.run {
                self.frameEncoding = false
                guard let jpeg, let transport = self.transport else { return }
                if transport.send(TogetherMedia(kind: .jpeg, seq: seq, payload: jpeg)) {
                    self.pacer.didSend(seq: seq, now: ProcessInfo.processInfo.systemUptime)
                    self.countFrame()
                }
            }
        }
    }

    private func countFrame() {
        sentFrames += 1
        let elapsed = Date().timeIntervalSince(fpsWindow)
        if elapsed >= 1 {
            fps = Double(sentFrames) / elapsed
            sentFrames = 0
            fpsWindow = Date()
        }
    }

    // MARK: Incoming

    private func handle(_ message: TogetherMessage) {
        switch message {
        case let .peers(count, helpers):
            peerCount = count
            if role == .helper { peers = helpers.map { Peer(name: $0, language: "", platform: "") } }
        case let .hello(role, name, language, platform):
            guard self.role == .fixer, role == .helper else { return }
            peers.removeAll { $0.name == name }
            peers.append(Peer(name: name, language: language, platform: platform))
            send(.status("\(self.name) is streaming. Tap anything to outline it for them."))
        case let .tap(seq, x, y, by):
            guard role == .fixer, safetyStop == nil else { return }
            Task { await outline(at: CGPoint(x: x, y: y), seq: seq, by: by) }
        case .clearMask:
            clearMask(broadcast: role == .fixer)
        case .mask(let shared):
            guard role == .helper else { return }
            show(shared)
        case .caption(let caption):
            guard role == .helper else { return }
            captions.insert(caption, at: 0)
            if caption.from == .fixer, let lang = AppLanguage(rawValue: caption.translatedLanguage) {
                voice.speak(caption.translated, language: lang)
            }
        case let .memory(steps, title):
            memorySteps = steps
            memoryTitle = title
        case .safety(let reason):
            raiseStop(reason, broadcast: false)
        case .ack(let seq):
            pacer.didAck(seq: seq, now: ProcessInfo.processInfo.systemUptime)
        case .mode, .status, .unknown:
            break
        }
    }

    private func handle(_ media: TogetherMedia) {
        switch (role, media.kind) {
        case (.helper, .jpeg):
            guard let image = UIImage(data: media.payload) else { return }
            frame = image
            _ = frames.push(image)
            countFrame()
            transport?.send(.ack(seq: media.seq))
        case (.fixer, .wav):
            Task { await hearHelper(media.payload) }
        default:
            break
        }
    }

    private func send(_ message: TogetherMessage) {
        if !isDemo { transport?.send(message) }
    }

    // MARK: Fixer: SAM 3.1 outline + tracking

    /// SAM 3.1 point prompt on the exact frame the Helper tapped.
    func outline(at point: CGPoint, seq: UInt32? = nil, by: String) async {
        guard let source = (seq.flatMap { frames.frame(seq: $0) } ?? frames.latest)?.image else { return }
        busy = "SAM 3.1 outlining what \(by) tapped…"
        let started = Date()
        defer { busy = nil }
        let image = ImageCodec.normalized(source, maxEdge: 1024)
        let pixel = CGPoint(x: point.x * image.size.width, y: point.y * image.size.height)
        do {
            guard let object = try await sam.object(at: pixel, in: image) else {
                send(.status("SAM 3.1 couldn't find a part there. Try tapping its middle."))
                return
            }
            let shared = sharedMask(from: object, in: image.size, label: "", by: by, seq: seq ?? 0)
            lastTiming = String(format: "sam-3.1 outline in %.1fs", Date().timeIntervalSince(started))
            tracker.reset(to: shared.box, now: ProcessInfo.processInfo.systemUptime)
            masks.append(shared)
            show(shared)
            send(.mask(shared))
            scheduleMemory()
        } catch {
            send(.status("Outline failed: \(error.localizedDescription)"))
        }
    }

    func clearMask(broadcast: Bool) {
        tracker.clear()
        mask = nil
        maskOverlay = nil
        if broadcast { send(.clearMask) }
    }

    /// Helper on iPhone: send a tap (normalised to the frame they are looking at).
    func tap(_ point: CGPoint) {
        guard role == .helper, let latest = frames.latest else { return }
        transport?.send(.tap(seq: latest.seq, x: point.x, y: point.y, by: name))
    }

    private func startTracking() {
        trackTask?.cancel()
        trackTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                await self?.trackOnce()
            }
        }
    }

    /// Keyframe re-anchoring: every ~1.2 s, SAM 3.1 again on the newest frame with a point prompt at the
    /// centre of the last accepted box. Implausible jumps or size changes are rejected (MaskTracker).
    private func trackOnce() async {
        guard role == .fixer, let current = mask, let prompt = tracker.nextPrompt(now: ProcessInfo.processInfo.systemUptime),
              let latest = frames.latest else { return }
        let image = ImageCodec.normalized(latest.image, maxEdge: 768)
        let pixel = CGPoint(x: prompt.x * image.size.width, y: prompt.y * image.size.height)
        let object = try? await sam.object(at: pixel, in: image)
        let candidate = object.map { normalizedBox($0.maskRect, in: image.size) }
        guard mask?.id == current.id else { tracker.update(with: nil); return }
        if tracker.update(with: candidate), let object {
            var moved = sharedMask(from: object, in: image.size, label: current.label, by: current.by, seq: latest.seq)
            moved.id = current.id
            show(moved)
            send(.mask(moved))
        } else if tracker.isLost {
            clearMask(broadcast: true)
            send(.status("Lost the outline. Tap the part again."))
        }
    }

    private func sharedMask(from object: SAMObject, in size: CGSize, label: String, by: String, seq: UInt32) -> SharedMask {
        let id = nextMaskID
        nextMaskID += 1
        return SharedMask(
            id: id, seq: seq, box: normalizedBox(object.maskRect, in: size),
            png: Self.maskPNG(object)?.base64EncodedString() ?? "",
            label: label, confidence: object.confidence, by: by, model: MetaModel.sam
        )
    }

    private func normalizedBox(_ rect: CGRect, in size: CGSize) -> [Double] {
        let w = max(size.width, 1), h = max(size.height, 1)
        return [rect.minX / w, rect.minY / h, rect.maxX / w, rect.maxY / h].map { min(1, max(0, Double($0))) }
    }

    private func show(_ shared: SharedMask) {
        mask = shared
        if let data = Data(base64Encoded: shared.png), let image = UIImage(data: data) {
            maskOverlay = Self.tinted(image)
        } else {
            maskOverlay = nil
        }
    }

    /// White-on-transparent mask PNG, at most 256 px, so it stays a few KB on the wire.
    static func maskPNG(_ object: SAMObject) -> Data? {
        guard object.hasRaster else { return nil }
        let w = object.maskWidth, h = object.maskHeight
        let step = max(1, Int((Double(max(w, h)) / 256).rounded(.up)))
        let ow = max(1, w / step), oh = max(1, h / step)
        var pixels = [UInt8](repeating: 0, count: ow * oh * 4)
        for y in 0..<oh {
            for x in 0..<ow where object.raster[min(h - 1, y * step) * w + min(w - 1, x * step)] == 1 {
                let o = (y * ow + x) * 4
                pixels[o] = 255; pixels[o + 1] = 255; pixels[o + 2] = 255; pixels[o + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cg = CGImage(width: ow, height: oh, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: ow * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cg).pngData()
    }

    static func tinted(_ mask: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: mask.size)
        return renderer.image { context in
            mask.draw(at: .zero)
            UIColor(red: 1, green: 0.69, blue: 0.125, alpha: 0.5).setFill()
            context.fill(CGRect(origin: .zero, size: mask.size), blendMode: .sourceIn)
        }
    }

    // MARK: Voice: Muse Voice Transcribe → safety → Muse Spark translation → TTS

    private func hearHelper(_ wav: Data) async {
        guard let helper = peers.last else { return await hear(wav, from: .helper, speaker: "Helper", speakerLanguage: .english) }
        await hear(wav, from: .helper, speaker: helper.name, speakerLanguage: AppLanguage(rawValue: helper.language) ?? .english)
    }

    /// Fixer push-to-talk (also used for the Helper on iPhone, which only records and uploads).
    func beginTalking() async {
        voice.stop()
        try? await mic.start()
    }

    func endTalking() async {
        guard let wav = mic.stop() else { return }
        if role == .helper {
            transport?.send(TogetherMedia(kind: .wav, seq: UInt32(Date().timeIntervalSince1970) & 0xFFFF_FFFF, payload: wav))
            return
        }
        await hear(wav, from: .fixer, speaker: name, speakerLanguage: language)
    }

    private func hear(_ wav: Data, from side: TogetherRole, speaker: String, speakerLanguage: AppLanguage) async {
        busy = "Muse Voice Transcribe is listening…"
        defer { busy = nil }
        do {
            let text = try await mic.transcribe(wav: wav, language: speakerLanguage, extraKeywords: masks.map(\.label).filter { !$0.isEmpty })
            if let reason = SafetyGuard.reason(for: text) {
                raiseStop(reason, broadcast: true)
                return
            }
            let target: AppLanguage = side == .fixer
                ? (peers.compactMap { AppLanguage(rawValue: $0.language) }.first ?? .english)
                : language
            busy = "Muse Spark translating…"
            let translated = target == speakerLanguage ? text : try await translate(text, from: speakerLanguage, to: target)
            let caption = Caption(
                id: UUID().uuidString, from: side, name: speaker, original: text,
                originalLanguage: speakerLanguage.rawValue, translated: translated,
                translatedLanguage: target.rawValue, at: Date().timeIntervalSince1970
            )
            captions.insert(caption, at: 0)
            send(.caption(caption))
            if side == .helper { voice.speak(translated, language: target) }   // the Fixer hears the Helper in their language (and in the glasses, over Bluetooth)
            scheduleMemory()
        } catch FixError.nothingHeard {
            send(.status("Didn't catch that. Hold the mic and try again."))
        } catch {
            send(.status("Voice failed: \(error.localizedDescription)"))
        }
    }

    private func translate(_ text: String, from: AppLanguage, to: AppLanguage) async throws -> String {
        let response = try await MetaClient.shared.responses(model: MetaModel.spark, purpose: "Translate for the session", body: [
            "input": TogetherPrompts.translate(text, from: from.label, to: to.label),
            "reasoning": ["effort": "minimal"],
        ])
        let out = response.text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
        return out.isEmpty ? text : out
    }

    // MARK: Safety

    private func raiseStop(_ reason: String, broadcast: Bool) {
        safetyStop = reason
        clearMask(broadcast: false)
        voice.stop()
        if broadcast { send(.safety(reason: reason)) }
        voice.speak(SafetyGuard.spokenStop, language: language)
    }

    // MARK: Repair memory (Muse Spark)

    private func scheduleMemory() {
        guard role == .fixer, !isDemo else { return }
        memoryTask?.cancel()
        memoryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.writeMemory(final: false)
        }
    }

    /// Muse Spark turns the conversation and outlined parts into a RepairPlan, shared live with Helpers
    /// and saved (with a keyframe) when the session ends. Replay it from "Repair memory" in the guide.
    func writeMemory(final: Bool) {
        let lines = Array(captions.reversed())
        let masks = self.masks
        let fixerLanguage = language
        let keyframe = frames.latest?.image
        let participants = [name] + peers.map(\.name)
        Task {
            do {
                let response = try await MetaClient.shared.responses(model: MetaModel.spark, purpose: "Write the repair memory", body: [
                    "instructions": TogetherPrompts.memory,
                    "input": TogetherPrompts.memoryInput(lines: lines, masks: masks, fixerLanguage: fixerLanguage.label),
                    "reasoning": ["effort": "low"],
                ])
                var plan = try ModelJSON.plan(response.text, fallbackDomain: .home)
                plan.usedModel = MetaModel.spark
                plan.isDemo = false
                plan = SafetyGuard.enforce(plan, transcript: lines.map(\.original).joined(separator: " "))
                memoryTitle = plan.fault.isEmpty ? "Repair memory" : plan.fault
                memorySteps = plan.steps.map(\.title)
                send(.memory(steps: memorySteps, title: memoryTitle))
                if final || savedMemory != nil {
                    let id = savedMemory?.id ?? UUID()
                    let memory = RepairMemory(
                        id: id, title: memoryTitle, createdAt: savedMemory?.createdAt ?? Date(),
                        plan: plan, transcript: lines, photoFile: "\(id.uuidString).jpg",
                        participants: participants
                    )
                    try store.save(memory, photoJPEG: keyframe?.jpegData(compressionQuality: 0.7))
                    savedMemory = memory
                }
            } catch {
                if final { send(.status("Couldn't write the repair memory: \(error.localizedDescription)")) }
            }
        }
    }

    func saveMemoryNow() { writeMemory(final: true) }

    func allMemories() -> [RepairMemory] { store.all() }
    func photo(for memory: RepairMemory) -> UIImage? { UIImage(contentsOfFile: store.photoURL(for: memory).path) }
    func delete(_ memory: RepairMemory) { store.delete(memory) }

    // MARK: Two-device demo mode (scripted, labelled)

    /// Plays a scripted Helper on the Fixer's phone so the session can be shown with one device:
    /// frames come from the active camera (the Mock Device glasses feed in the demo), the outline box is
    /// the DemoLibrary's hand-placed region, and captions are scripted. The UI shows "Demo mode · scripted".
    private func runFixerDemo() {
        peers = [Peer(name: "Sam (Helper)", language: AppLanguage.english.rawValue, platform: "web")]
        peerCount = 2
        demoTask = Task { [weak self] in
            func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
            await wait(1.5)
            guard let self else { return }
            self.demoCaption(from: .fixer, name: self.name, original: "Hay agua goteando debajo del fregadero.", originalLanguage: .spanish,
                             translated: "There's water dripping under the sink.", translatedLanguage: .english, speak: false)
            await wait(2.5)
            self.busy = "Sam tapped the picture · outlining…"
            await wait(0.8)
            self.busy = nil
            let shared = SharedMask(id: 1, seq: 0, box: [0.52, 0.42, 0.64, 0.49], png: "", label: "slip nut", confidence: nil, by: "Sam (Helper)", model: "demo (scripted box)")
            self.masks = [shared]
            self.show(shared)
            await wait(1.2)
            self.demoCaption(from: .helper, name: "Sam (Helper)", original: "That's the slip nut. Turn it clockwise, hand tight, then a quarter more.", originalLanguage: .english,
                             translated: "Esa es la tuerca. Gírala en el sentido del reloj, a mano, y luego un cuarto más.", translatedLanguage: .spanish, speak: true)
            await wait(6)
            self.demoCaption(from: .fixer, name: self.name, original: "Listo, ya no gotea.", originalLanguage: .spanish,
                             translated: "Done, it's not dripping any more.", translatedLanguage: .english, speak: false)
            await wait(1.5)
            self.memoryTitle = "Arreglar la fuga del sifón"
            self.memorySteps = ["Pon un cubo debajo del sifón.", "Busca la tuerca que gotea.", "Gírala a mano y un cuarto más.", "Abre el grifo y revisa."]
        }
    }

    private func demoCaption(from: TogetherRole, name: String, original: String, originalLanguage: AppLanguage, translated: String, translatedLanguage: AppLanguage, speak: Bool) {
        captions.insert(Caption(id: UUID().uuidString, from: from, name: name, original: original, originalLanguage: originalLanguage.rawValue,
                                translated: translated, translatedLanguage: translatedLanguage.rawValue, at: Date().timeIntervalSince1970), at: 0)
        if speak { voice.speak(translated, language: translatedLanguage) }
    }
}
