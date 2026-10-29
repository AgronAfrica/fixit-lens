import CoreGraphics
import Combine
import SwiftUI
import UIKit

/// Orchestrates the Fix-it Lens pipeline:
/// tap or speak → SAM 3.1 outlines the part → Muse Spark 1.3 finds the fault → safety guard →
/// Muse Wonder 1.0 checks the plan while Muse Image 1.0 draws it → hands-free guide that highlights
/// each step's part with SAM 3.1 and listens through Muse Voice Transcribe.
@MainActor
final class AppModel: ObservableObject {
    // MARK: Settings (persisted)

    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: Keys.language) } }
    @Published var preferReplay: Bool { didSet { defaults.set(preferReplay, forKey: Keys.preferReplay) } }
    @Published var handsFree: Bool { didSet { defaults.set(handsFree, forKey: Keys.handsFree) } }
    @Published var speechRate: Double { didSet { defaults.set(speechRate, forKey: Keys.speechRate) } }
    @Published var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    @Published private(set) var hasKey = SecretStore.hasCloudKey
    /// Camera source for Lens, the guide and Fix it together: the iPhone or Ray-Ban Meta glasses (DAT SDK).
    @Published var cameraSource: CameraSource { didSet { defaults.set(cameraSource.rawValue, forKey: Keys.cameraSource); cameraSourceChanged() } }
    /// Fix it together relay (Cloudflare Worker or `node together/relay/server.mjs`).
    /// Defaults to the deployed Worker; override in Settings (an empty value falls back to the default).
    static let defaultRelayURL = "https://fixit-together.joinreson.workers.dev"
    @Published var relayURL: String { didSet { defaults.set(relayURL, forKey: Keys.relayURL) } }
    @Published var displayName: String { didSet { defaults.set(displayName, forKey: Keys.displayName) } }

    // MARK: Scene

    @Published var domain: RepairDomain = .home
    @Published private(set) var photo: UIImage?
    @Published private(set) var scene: DemoScene?
    @Published private(set) var stage: PipelineStage = .idle
    @Published private(set) var tap: TapMark?
    @Published private(set) var target: SAMObject?
    @Published private(set) var transcript = ""
    @Published private(set) var plan: RepairPlan?
    @Published var showPlan = false
    @Published private(set) var illustration: UIImage?
    @Published private(set) var illustrationState: IllustrationState = .none
    /// Muse Wonder's background safety review of the plan on screen.
    @Published private(set) var review: ReviewState = .idle
    /// Live pipeline timeline: model, task and elapsed time per call.
    @Published private(set) var progress: [ProgressItem] = []
    /// Steps revealed so far (the plan arrives whole; steps are revealed one by one as it lands).
    @Published private(set) var revealedSteps = 0
    var refining: Bool { review == .running }

    // MARK: Guide

    @Published var guideActive = false
    @Published private(set) var stepIndex = 0
    @Published private(set) var guidePhase: GuidePhase = .waiting
    @Published private(set) var highlight: SAMObject?
    @Published private(set) var heard = ""
    @Published private(set) var exchanges: [GuideExchange] = []
    @Published private(set) var guideNotice: String?
    @Published private(set) var guideStop: String?

    let camera = CameraService()
    let glasses = GlassesCameraService()
    /// The live "Fix it together" session, if one is open.
    @Published private(set) var together: TogetherSession?
    let mic = TranscribeService()
    let voice = SpeechService()
    let trace = MetaTrace.shared

    private let sam = SAMService()
    private let brain = RepairBrain()
    private let artist = IllustrationService()
    private let defaults = UserDefaults.standard
    private var runTask: Task<Void, Never>?
    private var enrichTask: Task<Void, Never>?
    private var guideTask: Task<Void, Never>?
    private var retryAction: (() -> Void)?
    private var partCache: [String: SAMObject] = [:]
    private var maskTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    /// Increments on every new diagnosis so late SAM masks from an old photo or tap are ignored.
    private var generation = 0
    /// A tap made while the mic was recording (normalized); runs with ASR when they let go.
    private var pendingTap: CGPoint?
    /// The last tap (normalized), reused when the user then speaks about the same part.
    private var lastTap: CGPoint?
    private var forwarders: Set<AnyCancellable> = []

    private enum Keys {
        static let language = "language"
        static let preferReplay = "preferReplay"
        static let handsFree = "handsFree"
        static let speechRate = "speechRate"
        static let appearance = "appearance"
        static let cameraSource = "cameraSource"
        static let relayURL = "relayURL"
        static let displayName = "displayName"
    }

    init() {
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .english
        preferReplay = defaults.bool(forKey: Keys.preferReplay)
        handsFree = defaults.object(forKey: Keys.handsFree) as? Bool ?? true
        speechRate = defaults.object(forKey: Keys.speechRate) as? Double ?? 0.5
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        cameraSource = CameraSource(rawValue: defaults.string(forKey: Keys.cameraSource) ?? "") ?? .iPhone
        let storedRelay = defaults.string(forKey: Keys.relayURL)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        relayURL = storedRelay.isEmpty ? Self.defaultRelayURL : storedRelay
        displayName = defaults.string(forKey: Keys.displayName) ?? ""
        // Re-publish nested observable changes (mic level, speaking state, call trace) to views observing the model.
        for publisher in [mic.objectWillChange.eraseToAnyPublisher(),
                          voice.objectWillChange.eraseToAnyPublisher(),
                          trace.objectWillChange.eraseToAnyPublisher(),
                          glasses.objectWillChange.eraseToAnyPublisher()] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &forwarders)
        }
    }

    // MARK: Derived state

    /// Replay runs only on the built-in samples, when there's no key or the user asked for it.
    var isReplay: Bool { scene != nil && (preferReplay || !hasKey) }
    var canRetry: Bool { retryAction != nil && stage.isFailure }
    var currentStep: RepairStep? {
        guard let plan, plan.steps.indices.contains(stepIndex) else { return nil }
        return plan.steps[stepIndex]
    }
    var suggestedQuestion: String {
        scene?.suggestedQuestion(for: currentStep) ?? "What's this part?"
    }

    func refreshKey() { hasKey = SecretStore.hasCloudKey }

    // MARK: Photo in

    func capture() {
        run(retry: nil) { [self] in
            if cameraSource == .glasses {
                // The newest glasses frame (504 x 896 at "medium"): plenty for SAM 3.1 and Muse Spark at 768 px.
                guard let frame = glasses.snapshot() else { throw FixError.noImage }
                load(frame)
            } else {
                load(try await camera.capture())
            }
        }
    }

    // MARK: Camera source (iPhone / Meta glasses)

    func startCamera() {
        switch cameraSource {
        case .iPhone:
            glasses.stop()
            camera.start()
        case .glasses:
            camera.stop()
            Task { await glasses.start() }
        }
    }

    private func cameraSourceChanged() {
        if photo == nil { startCamera() }
        routeFrames()
    }

    /// Sends live frames from the active source into the Fix it together session (only while one is open).
    private func routeFrames() {
        let sink: (@Sendable (UIImage) -> Void)? = together.map { session in { image in session.ingest(image) } }
        camera.onFrame = cameraSource == .iPhone ? sink : nil
        glasses.onFrame = cameraSource == .glasses ? sink : nil
    }

    // MARK: Fix it together

    var relay: URL? {
        let trimmed = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, ["https", "http"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    /// Fixer: open a session. `demo` plays a scripted Helper (labelled) so it can be shown on one device.
    func startTogether(demo: Bool = false) {
        guard demo || relay != nil else { return }
        let session = TogetherSession(relay: relay ?? URL(string: "https://relay.invalid")!, voice: voice, mic: mic)
        session.startAsFixer(name: displayName.isEmpty ? "Fixer" : displayName, language: language, demo: demo)
        together = session
        if photo != nil { retake() } else { startCamera() }
        routeFrames()
    }

    /// Helper on this iPhone: join someone else's session by code or link.
    @discardableResult
    func joinTogether(_ codeOrLink: String) -> Bool {
        guard let relay else { return false }
        let session = TogetherSession(relay: relay, voice: voice, mic: mic)
        guard session.join(codeOrLink, name: displayName.isEmpty ? "Helper" : displayName, language: language) else { return false }
        together = session
        camera.stop()
        glasses.stop()
        return true
    }

    func endTogether() {
        together?.leave()
        together = nil
        routeFrames()
        if photo == nil { startCamera() }
    }

    /// Open a saved repair memory in the normal plan sheet and guide.
    func replay(_ memory: RepairMemory, photo image: UIImage?) {
        reset()
        scene = nil
        photo = image.map { ImageCodec.normalized($0) }
        camera.stop()
        present(memory.plan)
    }

    /// fixitlens://join?code=… (or a https://…/j/CODE link) and Meta AI's DAT callbacks.
    func open(url: URL) {
        if GlassesCameraService.handles(url) {
            Task { await glasses.handle(url) }
        } else if let code = Together.code(from: url.absoluteString) {
            joinTogether(code)
        }
    }

    func load(_ image: UIImage) {
        reset()
        scene = nil
        photo = ImageCodec.normalized(image)
        camera.stop()
        Haptics.tap()
    }

    func open(_ sample: DemoScene) {
        guard let image = UIImage(named: sample.assetName) else { return }
        reset()
        scene = sample
        domain = sample.domain
        photo = ImageCodec.normalized(image)
        camera.stop()
        Haptics.tap()
        if sample.id == DemoLibrary.safety.id { speakScripted() }
    }

    func retake() {
        reset()
        photo = nil
        scene = nil
        startCamera()
    }

    func reset() {
        runTask?.cancel()
        enrichTask?.cancel()
        maskTask?.cancel()
        revealTask?.cancel()
        generation += 1
        endGuide()
        mic.cancel()
        voice.stop()
        runTask = nil
        stage = .idle
        tap = nil
        target = nil
        transcript = ""
        plan = nil
        showPlan = false
        illustration = nil
        illustrationState = .none
        review = .idle
        progress = []
        revealedSteps = 0
        pendingTap = nil
        lastTap = nil
        retryAction = nil
        partCache = [:]
        trace.reset()
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
        mic.cancel()
        voice.stop()
        stage = plan == nil ? .idle : .ready
    }

    func retry() { retryAction?() }

    // MARK: Tap → SAM point prompt ∥ Muse Spark

    /// `location` is in the lens view's coordinates; `viewSize` is the lens size (aspect-fill).
    /// Tapping while holding the mic is allowed: the tap is kept and runs alongside ASR when they let go.
    func handleTap(at location: CGPoint, in viewSize: CGSize) {
        guard let photo, !stage.isBusy else { return }
        let pixel = FillTransform(imageSize: photo.size, viewSize: viewSize).toImage(location)
        let point = CGPoint(x: pixel.x / photo.size.width, y: pixel.y / photo.size.height)
        tap = TapMark(point: location)
        Haptics.tap()
        if mic.isRecording {
            pendingTap = point
            return
        }
        diagnose(at: point)
    }

    /// Tap the scripted spot on a sample (used by the "Tap the leak" hint and UI tests).
    func tapScripted() {
        guard let scene else { return }
        diagnose(at: scene.tapPoint)
    }

    /// The latency-critical path. SAM 3.1 (point prompt) starts immediately and runs in parallel with
    /// Muse Voice Transcribe (if they also spoke) and Muse Spark 1.3, which reads a local close-up plus the
    /// whole scene with the tap marked, so it never waits for the mask. The plan is shown as soon as
    /// Spark answers; the mask lands whenever SAM does. No concept-extraction call on this path.
    private func diagnose(at point: CGPoint, wav: Data? = nil) {
        guard let photo else { return }
        run(retry: { [weak self] in self?.diagnose(at: point, wav: wav) }) { [self] in
            target = nil
            plan = nil
            if isReplay, let scene {
                try await replayDiagnosis(scene, tapAt: point, transcript: "")
                return
            }
            beginRun()
            lastTap = point
            let token = generation
            let pixel = CGPoint(x: point.x * photo.size.width, y: point.y * photo.size.height)
            startProgress("sam", MetaModel.sam, "Outlining the part you tapped")
            maskTask = Task { [weak self, sam] in
                let object = try? await sam.object(at: pixel, in: photo)
                self?.applyMask(object, token: token)
            }

            var text = transcript
            if let wav {
                stage = .transcribing
                startProgress("asr", MetaModel.transcribe, "Hearing what you said")
                text = try await mic.transcribe(wav: wav, language: language)
                finishProgress("asr", detail: "“\(text)”")
                Motion.animate { transcript = text }
                if let reason = SafetyGuard.reason(for: text) {
                    maskTask?.cancel()
                    finishProgress("sam", status: .skipped)
                    present(.safetyStop(reason: reason, domain: domain, fault: text))
                    return
                }
            }

            stage = .diagnosing
            startProgress("spark", MetaModel.spark, "Reading the close-up and the whole scene")
            let plan = try await brain.assess(
                closeUp: ImageCodec.closeUp(photo, around: point), scene: photo, tap: point,
                partHint: "", domain: domain, transcript: text, language: language
            )
            finishProgress("spark", detail: plan.hazard == .stop ? "safety stop" : "\(plan.steps.count) steps")
            present(plan)
            if plan.hazard != .stop { enrich(plan) }
        }
    }

    private func applyMask(_ object: SAMObject?, token: Int) {
        guard token == generation, !Task.isCancelled else { return }
        guard let object else {
            finishProgress("sam", status: .failed, detail: "no outline; using the tap point")
            return
        }
        finishProgress("sam", detail: object.confidence.map { String(format: "mask · %.0f%%", $0 * 100) } ?? "mask")
        if target == nil || target?.isDemoRegion == true {
            Motion.animate { target = object }
            Haptics.found()
        }
    }

    // MARK: Voice → ASR → Muse Spark (no concept extraction)

    func beginTalking() {
        guard photo != nil, !stage.isBusy, !mic.isRecording else { return }
        voice.stop()
        pendingTap = nil
        if isReplay { stage = .listening; return }
        run(retry: nil, keepTask: true) { [self] in
            stage = .listening
            try await mic.start()
        }
    }

    func endTalking() {
        if isReplay {
            guard stage == .listening else { return }
            speakScripted()
            return
        }
        guard mic.isRecording else { return }
        let wav = mic.stop()
        guard let wav else {
            stage = .failed(FixError.nothingHeard.localizedDescription)
            Haptics.warning()
            return
        }
        if let point = pendingTap {
            pendingTap = nil
            diagnose(at: point, wav: wav)
        } else {
            listen(to: wav)
        }
    }

    /// Replay only: play the sample's scripted utterance through the pipeline.
    func speakScripted() {
        guard let scene else { return }
        run(retry: { [weak self] in self?.speakScripted() }) { [self] in
            stage = .transcribing
            try await Task.sleep(for: .milliseconds(650))
            Motion.animate { transcript = scene.utterance }
            try await replayDiagnosis(scene, tapAt: nil, transcript: scene.utterance)
        }
    }

    /// Voice only. If something is already outlined, Spark reuses that outline (no new SAM call); otherwise
    /// Spark reads the whole scene and returns where the part is, and SAM 3.1 outlines it in the background.
    private func listen(to wav: Data) {
        guard let photo else { return }
        run(retry: { [weak self] in self?.listen(to: wav) }) { [self] in
            beginRun()
            stage = .transcribing
            startProgress("asr", MetaModel.transcribe, "Hearing what you said")
            let text = try await mic.transcribe(wav: wav, language: language)
            finishProgress("asr", detail: "“\(text)”")
            Motion.animate { transcript = text }

            // Stop before any further model call if the user is describing gas or mains work.
            if let reason = SafetyGuard.reason(for: text) {
                present(.safetyStop(reason: reason, domain: domain, fault: text))
                return
            }

            stage = .diagnosing
            let existing = target
            startProgress("spark", MetaModel.spark, existing == nil ? "Finding the part in the scene" : "Reading the outlined part and the scene")
            let plan = try await brain.assess(
                closeUp: existing.map { SAMParser.crop(photo, to: $0) }, scene: photo,
                tap: existing == nil ? nil : lastTap, partHint: "", domain: domain,
                transcript: text, language: language
            )
            finishProgress("spark", detail: plan.hazard == .stop ? "safety stop" : "\(plan.steps.count) steps")
            present(plan)
            guard plan.hazard != .stop else { return }
            enrich(plan)
            if existing == nil { outline(plan) }
        }
    }

    /// Background SAM 3.1 outline for the voice path: point prompt at Spark's location, then concept text.
    private func outline(_ plan: RepairPlan) {
        guard let photo else { return }
        let token = generation
        startProgress("sam", MetaModel.sam, "Outlining \(plan.partName.isEmpty ? "the part" : plan.partName)")
        maskTask = Task { [weak self, sam] in
            var object: SAMObject?
            if let location = plan.target {
                let pixel = CGPoint(x: location.x * photo.size.width, y: location.y * photo.size.height)
                if let hit = try? await sam.object(at: pixel, in: photo), Locator.plausible(hit, for: location) { object = hit }
            }
            if object == nil, !plan.partName.isEmpty {
                object = try? await sam.best(plan.partName, in: photo, purpose: "Find “\(plan.partName)”")
            }
            self?.applyMask(object, token: token)
        }
    }

    // MARK: Reasoning

    private func beginRun() {
        trace.reset()
        maskTask?.cancel()
        generation += 1
        progress = []
        review = .idle
    }

    private func startProgress(_ id: String, _ model: String, _ label: String) {
        progress.removeAll { $0.id == id }
        Motion.animate { progress.append(ProgressItem(id: id, model: model, label: label, started: .now)) }
    }

    private func finishProgress(_ id: String, status: ProgressItem.Status = .done, detail: String = "") {
        guard let index = progress.firstIndex(where: { $0.id == id }), progress[index].finished == nil else { return }
        Motion.animate {
            progress[index].finished = .now
            progress[index].status = status
            progress[index].detail = detail
        }
    }

    private func present(_ newPlan: RepairPlan) {
        Motion.animate(Motion.gentle) {
            plan = newPlan
            showPlan = true
        }
        illustration = nil
        illustrationState = .none
        revealSteps(of: newPlan)
        if newPlan.hazard == .stop {
            stage = .stopped
            Haptics.warning()
        } else {
            stage = newPlan.isDemo ? .ready : .planning
            Haptics.success()
        }
        voice.speak(newPlan.spokenIntro, language: language, rate: Float(speechRate))
    }

    /// Reveals steps one by one so the sheet fills in as the plan lands (the plan itself arrives in one response).
    private func revealSteps(of plan: RepairPlan) {
        revealTask?.cancel()
        revealedSteps = 0
        let count = plan.steps.count
        revealTask = Task { [weak self] in
            for index in 0..<count {
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                Motion.animate { self?.revealedSteps = index + 1 }
            }
        }
    }

    /// Muse Wonder (safety review) and Muse Image (illustration) run in parallel after the plan is shown.
    /// The user can start the guide straight away; a real stop from the review still ends it.
    private func enrich(_ draft: RepairPlan) {
        enrichTask?.cancel()
        let photo = self.photo
        let language = self.language
        review = .running
        illustrationState = .drawing
        startProgress("wonder", MetaModel.wonder, "Safety check of the plan")
        startProgress("image", MetaModel.image, "Drawing the fix")
        enrichTask = Task { [weak self, brain, artist] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let refined = try? await brain.refine(draft, language: language)
                    await self?.applyRefined(refined, to: draft)
                }
                group.addTask {
                    let image = try? await artist.illustrate(draft, reference: photo, language: language)
                    await self?.applyIllustration(image)
                }
            }
            await self?.finishEnrich()
        }
    }

    private func applyRefined(_ result: (plan: RepairPlan, outcome: PlanReview.Outcome)?, to draft: RepairPlan) {
        guard plan?.id == draft.id else { return }
        guard let result else {
            review = .failed
            finishProgress("wonder", status: .failed, detail: "local safety rules still apply")
            return
        }
        let refined = result.plan
        switch result.outcome {
        case .stopped(let reason):
            review = .stopped(reason)
            finishProgress("wonder", detail: "stop: \(refined.stopCategory.replacingOccurrences(of: "_", with: " "))")
            if guideActive { endGuide() }
            Motion.animate {
                plan = refined
                showPlan = true
            }
            stage = .stopped
            Haptics.warning()
            voice.speak(refined.spokenIntro, language: language, rate: Float(speechRate))
            return
        case .stopRejected(let reason):
            review = .overruled(reason)
            finishProgress("wonder", detail: "stop overruled: no valid category")
        case .raisedToCaution:
            review = .raised(refined.hazardReason)
            finishProgress("wonder", detail: "raised to caution")
        case .improved, .unchanged:
            review = .passed
            finishProgress("wonder", detail: "\(refined.steps.count) steps checked")
        }
        if guideActive {
            // Never swap steps under someone mid-guide; take only the safety fields.
            plan?.hazard = refined.hazard
            plan?.hazardReason = refined.hazardReason
        } else {
            Motion.animate { plan = refined }
            revealedSteps = refined.steps.count
        }
    }

    private func applyIllustration(_ image: UIImage?) {
        finishProgress("image", status: image == nil ? .failed : .done)
        Motion.animate {
            illustration = image
            illustrationState = image == nil ? .failed : .ready
        }
    }

    private func finishEnrich() {
        enrichTask = nil
        if stage == .planning { stage = .ready }
    }

    // MARK: Replay

    private func replayDiagnosis(_ scene: DemoScene, tapAt point: CGPoint?, transcript: String) async throws {
        guard let photo else { return }
        if let reason = SafetyGuard.reason(for: transcript) {
            try await Task.sleep(for: .milliseconds(400))
            present(.safetyStop(reason: reason, domain: scene.domain, objectName: scene.plan.objectName, fault: transcript, isDemo: true))
            return
        }
        stage = .segmenting
        try await Task.sleep(for: .milliseconds(700))
        let hit: (part: String, rect: CGRect) = point.map(scene.region(containing:))
            ?? (part: scene.targetPart, rect: scene.regions[scene.targetPart] ?? CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        Motion.animate { target = .region(hit.rect, in: photo.size) }
        Haptics.found()
        stage = .diagnosing
        try await Task.sleep(for: .milliseconds(900))
        present(scene.plan)
    }

    // MARK: Hands-free guide

    func startGuide() {
        guard let plan, plan.hazard != .stop, !plan.steps.isEmpty else { return }
        voice.stop()
        showPlan = false
        exchanges = []
        guideNotice = nil
        guideStop = nil
        heard = ""
        guideActive = true
        restartGuide(at: 0, speak: true, intro: true)
    }

    func endGuide() {
        guideTask?.cancel()
        guideTask = nil
        guard guideActive else { return }
        mic.cancel()
        voice.stop()
        guideActive = false
        highlight = nil
        guidePhase = .waiting
    }

    func guideNext() { restartGuide(at: stepIndex + 1, speak: true) }
    func guideBack() { restartGuide(at: max(0, stepIndex - 1), speak: true) }
    func guideRepeat() { restartGuide(at: stepIndex, speak: true) }
    func guideRepeatFromStart() {
        exchanges = []
        heard = ""
        restartGuide(at: 0, speak: true)
    }

    /// Tap the mic in the guide to talk now (also the only way to talk when hands-free is off).
    func guideListen() {
        guard guideActive else { return }
        if isReplay {
            ask(suggestedQuestion)
            return
        }
        let index = stepIndex
        replaceGuideTask { [self] in
            let action = await listenForReply(retries: 0)
            await follow(action, from: index)
        }
    }

    /// A question from a chip or typed by the judge in replay.
    func ask(_ question: String) {
        guard guideActive else { return }
        let index = stepIndex
        replaceGuideTask { [self] in
            heard = question
            let action = await handle(utterance: question)
            await follow(action, from: index)
        }
    }

    private enum GuideAction {
        case goTo(Int)
        case listenAgain
        case wait
        case end
    }

    private func restartGuide(at index: Int, speak: Bool, intro: Bool = false) {
        replaceGuideTask { [self] in
            await runSteps(from: index, speak: speak, intro: intro)
        }
    }

    private func replaceGuideTask(_ body: @escaping @MainActor () async -> Void) {
        guideTask?.cancel()
        mic.cancel()
        voice.stop()
        guideTask = Task { await body() }
    }

    private func follow(_ action: GuideAction, from index: Int) async {
        switch action {
        case .goTo(let next): await runSteps(from: next, speak: true)
        case .listenAgain: await runSteps(from: index, speak: false)
        case .wait: guidePhase = .waiting
        case .end: endGuide()
        }
    }

    private func runSteps(from start: Int, speak: Bool, intro: Bool = false) async {
        var index = start
        var shouldSpeak = speak
        var first = intro
        while guideActive, !Task.isCancelled {
            guard let plan else { return }
            guard index < plan.steps.count else {
                await finishGuide()
                return
            }
            if stepIndex != index { Motion.animate { stepIndex = index } }
            let step = plan.steps[index]
            if shouldSpeak {
                guidePhase = .locating
                let located = await locate(step.part, at: step.location)
                guard !Task.isCancelled else { return }
                Motion.animate(Motion.smooth) { highlight = located }
                Haptics.step()
                guidePhase = .speaking
                await voice.say(speech(for: step, index: index, total: plan.steps.count, first: first),
                                language: language, rate: Float(speechRate))
                first = false
            }
            guard !Task.isCancelled else { return }
            shouldSpeak = true
            switch await listenForReply(retries: 1) {
            case .goTo(let next): index = next
            case .listenAgain: shouldSpeak = false
            case .wait:
                guidePhase = .waiting
                return
            case .end:
                endGuide()
                return
            }
        }
    }

    private func listenForReply(retries: Int) async -> GuideAction {
        guard handsFree || retries == 0 else { return .wait }
        // Replay never opens the mic: chips and buttons drive it.
        if isReplay { return .wait }
        var misses = 0
        while !Task.isCancelled {
            guidePhase = .listening
            do {
                guard let wav = try await mic.listenOnce() else {
                    misses += 1
                    if misses > retries { return .wait }
                    continue
                }
                guidePhase = .hearing
                let text = try await mic.transcribe(wav: wav, language: language, extraKeywords: currentStep.map { [$0.part, $0.tool] } ?? [])
                heard = text
                return await handle(utterance: text)
            } catch is CancellationError {
                return .wait
            } catch FixError.nothingHeard {
                misses += 1
                if misses > retries { return .wait }
            } catch {
                guideNotice = error.localizedDescription
                Haptics.error()
                return .wait
            }
        }
        return .wait
    }

    private func handle(utterance: String) async -> GuideAction {
        guideNotice = nil
        if let reason = SafetyGuard.reason(for: utterance) {
            await raiseGuideStop(reason)
            return .wait
        }
        switch VoiceIntent.parse(utterance) {
        case .next: return .goTo(stepIndex + 1)
        case .back: return .goTo(max(0, stepIndex - 1))
        case .repeatStep: return .goTo(stepIndex)
        case .stop: return .end
        case .question(let question):
            await answer(question)
            return guideStop == nil ? .listenAgain : .wait
        }
    }

    private func answer(_ question: String) async {
        guard let plan, let photo else { return }
        guidePhase = .thinking
        let reply: GuideAnswer
        if let scene, isReplay {
            try? await Task.sleep(for: .milliseconds(600))
            reply = scene.answer(to: question, step: currentStep)
        } else {
            do {
                reply = try await brain.answer(question, plan: plan, stepIndex: stepIndex, scene: photo, language: language)
            } catch is CancellationError {
                return
            } catch {
                guideNotice = error.localizedDescription
                Haptics.error()
                return
            }
        }
        guard !Task.isCancelled else { return }
        exchanges.append(GuideExchange(question: question, answer: reply.answer))
        if reply.safetyStop {
            await raiseGuideStop(reply.answer)
            return
        }
        if !reply.highlight.isEmpty || reply.location != nil {
            guidePhase = .locating
            if let located = await locate(reply.highlight, at: reply.location) {
                Motion.animate(Motion.smooth) { highlight = located }
                Haptics.found()
            }
        }
        guidePhase = .speaking
        await voice.say(reply.answer, language: language, rate: Float(speechRate))
    }

    private func raiseGuideStop(_ reason: String) async {
        Motion.animate { guideStop = reason }
        Haptics.warning()
        guidePhase = .speaking
        await voice.say(SafetyGuard.spokenStop, language: language, rate: Float(speechRate))
        guidePhase = .waiting
    }

    private func finishGuide() async {
        Motion.animate {
            highlight = nil
            guidePhase = .finished
        }
        Haptics.success()
        await voice.say(
            "Nice work, that's every step. Give it a test, and if it still isn't right, tap the part again.",
            language: language, rate: Float(speechRate)
        )
    }

    /// Highlight for a step or answer, cached. Order:
    /// 1. SAM 3.1 point prompt at Muse Spark's estimated location (best for small parts like a slip nut),
    ///    accepted only if the mask is plausibly that part (not half the photo);
    /// 2. SAM 3.1 concept prompt on the part name;
    /// 3. Spark's own box, drawn dashed as an estimate;
    /// 4. the original tap outline.
    private func locate(_ part: String, at location: PartLocation? = nil) async -> SAMObject? {
        let key = part.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let photo, !key.isEmpty || location != nil else { return target }
        let cacheKey = key + (location.map { String(format: "@%.2f,%.2f", $0.x, $0.y) } ?? "")
        if let cached = partCache[cacheKey] { return cached }
        var found: SAMObject?
        if let scene, isReplay {
            try? await Task.sleep(for: .milliseconds(250))
            found = scene.region(for: key).map { SAMObject.region($0, in: photo.size) }
        } else {
            if let location {
                let pixel = CGPoint(x: location.x * photo.size.width, y: location.y * photo.size.height)
                if let hit = try? await sam.object(at: pixel, in: photo), Locator.plausible(hit, for: location) { found = hit }
            }
            if found == nil, !key.isEmpty, !Task.isCancelled {
                found = try? await sam.best(key, in: photo, purpose: "Highlight “\(key)”")
            }
            if found == nil, let rect = location?.rect { found = .region(rect, in: photo.size) }
        }
        if let found { partCache[cacheKey] = found }
        return found ?? target
    }

    private func speech(for step: RepairStep, index: Int, total: Int, first: Bool) -> String {
        var parts = ["Step \(index + 1) of \(total). \(step.title).", step.instruction]
        if !step.caution.isEmpty { parts.append("Careful: \(step.caution)") }
        if first {
            parts.append(handsFree && !isReplay
                ? "Say done when you're ready, or ask me a question."
                : "Tap next when you're ready, or ask me a question.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Task plumbing

    /// Runs one pipeline job; maps errors to a visible state and keeps a retry closure.
    private func run(retry: (() -> Void)?, keepTask: Bool = false, _ body: @escaping @MainActor () async throws -> Void) {
        runTask?.cancel()
        retryAction = retry
        runTask = Task { [weak self] in
            do {
                try await body()
                if !keepTask { self?.runTask = nil }
            } catch is CancellationError {
                self?.runTask = nil
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.runTask = nil
                self.mic.cancel()
                Motion.animate { self.stage = .failed(error.localizedDescription) }
                Haptics.error()
            }
        }
    }
}

extension Locator {
    static func plausible(_ object: SAMObject, for estimate: PartLocation) -> Bool {
        let total = Double(max(object.box.width * object.box.height, 1))
        let boxArea = Double(object.box.rect.width * object.box.rect.height)
        return plausible(maskFraction: Double(object.area) / total, maskBoxFraction: boxArea / total, estimate: estimate)
    }
}
