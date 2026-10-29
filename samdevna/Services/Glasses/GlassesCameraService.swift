import Combine
import CoreGraphics
import Foundation
import SwiftUI
import UIKit

#if canImport(MWDATCore) && canImport(MWDATCamera)
import MWDATCamera
import MWDATCore
#endif
#if DEBUG && canImport(MWDATMockDevice)
import MWDATMockDevice
#endif

/// Ray-Ban Meta glasses as a camera, through the Meta Wearables Device Access Toolkit (DAT 1.0.1).
///
/// Flow (from the DAT getting-started guide): `Wearables.configure()` at launch → `startRegistration()`
/// (opens Meta AI once) → `requestPermission(.camera)` → `createSession(AutoDeviceSelector)` → `start()` →
/// wait for `.started` → `addCamera(StreamConfiguration(.raw, .medium, 15 fps))` → `stream.start()`.
/// Frames arrive as `VideoFrame`; `makeUIImage()` gives the picture we hand to SAM 3.1 / Muse Spark / the Helper.
///
/// In DEBUG builds "Use Mock Device" pairs a simulated Ray-Ban Meta from MockDeviceKit and feeds it a
/// bundled point-of-view clip (Demo/GlassesPOV/*.mp4, HEVC as the kit requires), so the whole glasses
/// path runs with no hardware. The app labels this "Mock Device (simulated glasses)" everywhere.
@MainActor
final class GlassesCameraService: ObservableObject {
    @Published private(set) var state: GlassesState
    @Published private(set) var latest: UIImage?
    @Published private(set) var fps: Double = 0
    @Published private(set) var usingMock = false

    /// Called off the main actor for every decoded frame (Together streams these; Lens keeps `latest`).
    nonisolated(unsafe) var onFrame: (@Sendable (UIImage) -> Void)?

    static let isLinked: Bool = {
        #if canImport(MWDATCore) && canImport(MWDATCamera)
        true
        #else
        false
        #endif
    }()

    static var mockAvailable: Bool {
        #if DEBUG && canImport(MWDATMockDevice)
        true
        #else
        false
        #endif
    }

    private var frameCount = 0
    private var fpsStarted = Date()

    #if canImport(MWDATCore) && canImport(MWDATCamera)
    private var deviceSession: DeviceSession?
    private var camera: Camera?
    private let sessionTokens = ListenerTokenBag()
    private let streamTokens = ListenerTokenBag()
    private var registrationTask: Task<Void, Never>?
    #endif
    #if DEBUG && canImport(MWDATMockDevice)
    private var mockGlasses: MockGlasses?
    #endif

    init() {
        state = Self.isLinked ? .notRegistered : .unavailable("Meta Wearables SDK not linked in this build")
        #if canImport(MWDATCore) && canImport(MWDATCamera)
        observeRegistration()
        #endif
    }

    /// Call once at launch (FixitLensApp.init).
    nonisolated static func configure() {
        #if canImport(MWDATCore)
        do { try Wearables.configure() } catch {
            #if DEBUG
            NSLog("[Fix-it Lens] Wearables.configure failed: \(error)")
            #endif
        }
        #endif
    }

    /// The Meta AI app calls back with `fixitlens://…?metaWearablesAction=…` after registration/permission.
    static func handles(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "metaWearablesAction" } ?? false
    }

    func handle(_ url: URL) async {
        #if canImport(MWDATCore)
        _ = try? await Wearables.shared.handleUrl(url)
        #endif
    }

    // MARK: Connect

    func connect() async {
        #if canImport(MWDATCore) && canImport(MWDATCamera)
        do {
            state = .registering
            try await Wearables.shared.startRegistration()
        } catch {
            state = .error("Couldn't open Meta AI to connect: \(error.localizedDescription)")
        }
        #endif
    }

    func disconnect() async {
        stop()
        #if canImport(MWDATCore)
        try? await Wearables.shared.startUnregistration()
        #endif
    }

    // MARK: Mock Device (DEBUG only)

    /// Pairs a simulated Ray-Ban Meta and feeds it the bundled POV clip for `scene` ("sink" or "bike").
    func useMockDevice(scene: String = "sink") {
        #if DEBUG && canImport(MWDATMockDevice)
        do {
            MockDeviceKit.shared.enable()   // registered + camera permission granted
            let glasses = try mockGlasses ?? MockDeviceKit.shared.pairGlasses(model: .rayBanMeta)
            mockGlasses = glasses
            glasses.powerOn()
            glasses.unfold()
            glasses.don()
            if let clip = Bundle.main.url(forResource: "glasses_pov_\(scene)", withExtension: "mp4") {
                glasses.services.camera.setCameraFeed(fileURL: clip)
            } else {
                glasses.services.camera.setCameraFeed(cameraFacing: .back)   // falls back to the iPhone camera
            }
            if let still = Bundle.main.url(forResource: scene == "bike" ? "demo-bike" : "demo-sink", withExtension: "jpg") {
                glasses.services.camera.setCapturedImage(fileURL: still)
            }
            usingMock = true
            Task { await start() }
        } catch {
            state = .error("Mock Device: \(error.localizedDescription)")
        }
        #else
        state = .unavailable("Mock Device is only in DEBUG builds")
        #endif
    }

    func stopMockDevice() {
        stop()
        #if DEBUG && canImport(MWDATMockDevice)
        if let mockGlasses { MockDeviceKit.shared.unpairDevice(mockGlasses) }
        mockGlasses = nil
        MockDeviceKit.shared.disable()
        #endif
        usingMock = false
        state = Self.isLinked ? .notRegistered : state
    }

    // MARK: Stream

    func start() async {
        #if canImport(MWDATCore) && canImport(MWDATCamera)
        guard camera == nil else { return }
        let wearables = Wearables.shared
        do {
            if try await wearables.checkPermissionStatus(.camera) != .granted {
                state = .needsPermission
                guard try await wearables.requestPermission(.camera) == .granted else {
                    state = .error("Camera permission denied in Meta AI")
                    return
                }
            }
            state = .starting
            let session = try wearables.createSession(deviceSelector: AutoDeviceSelector(wearables: wearables))
            deviceSession = session
            session.errorPublisher.listen { [weak self] error in
                Task { @MainActor in self?.state = .error(error.localizedDescription) }
            }.store(in: sessionTokens)
            try session.start()
            for await sessionState in session.stateStream() {
                if sessionState == .started { break }
                if sessionState == .stopped { state = .waitingForDevice; cleanup(); return }
            }
            // medium = 504 x 896: enough detail for SAM 3.1 on small parts, light enough to relay live.
            let config = StreamConfiguration(videoCodec: .raw, resolution: .medium, frameRate: 15)
            guard let camera = try session.addCamera(config: config) else {
                state = .error("Couldn't open the glasses camera")
                return
            }
            self.camera = camera
            let stream = camera.stream
            stream.statePublisher.listen { [weak self] streamState in
                Task { @MainActor in
                    guard let self else { return }
                    if streamState == .streaming { self.state = .streaming(mock: self.usingMock) }
                    if streamState == .stopped { self.cleanup(); self.state = .waitingForDevice }
                }
            }.store(in: streamTokens)
            stream.errorPublisher.listen { [weak self] error in
                Task { @MainActor in self?.state = .error(Self.describe(error)) }
            }.store(in: streamTokens)
            stream.videoFramePublisher.listen { [weak self] frame in
                guard let self, let image = frame.makeUIImage() else { return }
                self.onFrame?(image)
                Task { @MainActor in self.received(image) }
            }.store(in: streamTokens)
            stream.start()
        } catch {
            state = .error(error.localizedDescription)
            cleanup()
        }
        #endif
    }

    func stop() {
        #if canImport(MWDATCore) && canImport(MWDATCamera)
        camera?.stop()
        deviceSession?.stop()
        cleanup()
        #endif
        if state.isStreaming { state = .waitingForDevice }
    }

    /// A still for Lens "capture": the newest stream frame (the glasses' photo capture is slower and
    /// switches the stream mode, and SAM/Spark only need ~768 px anyway).
    func snapshot() -> UIImage? { latest }

    private func received(_ image: UIImage) {
        latest = image
        frameCount += 1
        let elapsed = Date().timeIntervalSince(fpsStarted)
        if elapsed >= 1 {
            fps = Double(frameCount) / elapsed
            frameCount = 0
            fpsStarted = Date()
        }
        if !state.isStreaming { state = .streaming(mock: usingMock) }
    }

    #if canImport(MWDATCore) && canImport(MWDATCamera)
    private func cleanup() {
        streamTokens.clear()
        sessionTokens.clear()
        camera = nil
        deviceSession = nil
        latest = nil
        fps = 0
    }

    private func observeRegistration() {
        registrationTask = Task { [weak self] in
            for await registration in Wearables.shared.registrationStateStream() {
                guard let self else { return }
                switch registration {
                case .registered: if !self.state.isStreaming, self.camera == nil { self.state = .waitingForDevice }
                case .registering: self.state = .registering
                default: if !self.usingMock { self.state = .notRegistered }
                }
            }
        }
    }

    /// The SDK's own messages cover permission, disconnect, hinges closed, thermal and battery (DAT guidance).
    private static func describe(_ error: StreamError) -> String { error.localizedDescription }
    #endif
}

/// Shows the latest glasses frame where the iPhone camera preview would be.
struct GlassesPreview: View {
    @ObservedObject var glasses: GlassesCameraService

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if let frame = glasses.latest {
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "eyeglasses").font(.system(size: 44, weight: .semibold))
                        Text(glasses.state.label).font(.footnote.weight(.semibold)).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(32)
                }
            }
            .overlay(alignment: .topLeading) {
                if glasses.state.isStreaming {
                    Label(glasses.usingMock ? "Mock Device · simulated glasses feed" : "Ray-Ban Meta · live", systemImage: "eyeglasses")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 60).padding(.leading, 14)
                }
            }
        }
        .ignoresSafeArea()
    }
}
