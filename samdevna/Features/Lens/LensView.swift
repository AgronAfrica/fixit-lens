import CoreGraphics
import PhotosUI
import SwiftUI

struct LensView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var showSettings = false
    @State private var showTogether = false

    var body: some View {
        ZStack {
            LensStage()
            VStack(spacing: Space.s) {
                TopBar(showSettings: $showSettings, showTogether: $showTogether)
                StatusCard()
                Spacer(minLength: 0)
                if model.photo == nil {
                    SampleStrip()
                } else {
                    PipelineRail()
                }
                BottomDock(pickerItem: $pickerItem)
            }
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.xs)
        }
        .background(Palette.night.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $model.showPlan) {
            RepairSheet()
                .environmentObject(model)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $model.guideActive) {
            GuideView().environmentObject(model)
        }
        .sheet(isPresented: $showSettings, onDismiss: model.refreshKey) {
            SettingsView().environmentObject(model)
        }
        .sheet(isPresented: $showTogether) {
            TogetherLobby().environmentObject(model)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: Binding(get: { model.together != nil }, set: { if !$0 { model.endTogether() } })) {
            if let session = model.together {
                TogetherView(session: session).environmentObject(model)
            }
        }
        .onChange(of: pickerItem) { _, item in
            Task { await importPhoto(item) }
        }
        .onAppear {
            if model.photo == nil { model.startCamera() }
        }
    }

    private func importPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        model.load(image)
    }
}

// MARK: - Stage: photo or camera, masks, tap feedback

private struct LensStage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                backdrop(size)
                if let photo = model.photo {
                    let transform = FillTransform(imageSize: photo.size, viewSize: size)
                    if let target = model.target {
                        MaskOverlay(object: target, transform: transform, label: model.plan?.partName ?? model.transcript.nilIfEmpty)
                            .id(target.box.rect.debugDescription)
                    }
                    if model.stage == .segmenting || (model.stage.isBusy && model.target == nil && model.tap != nil) {
                        ScanSweep().transition(.opacity)
                    }
                    if model.target == nil, model.plan == nil, !model.stage.isBusy, model.stage != .listening {
                        CoachReticle(text: model.scene == nil ? "Tap the broken part" : "Tap the \(model.scene?.targetPart ?? "part")")
                            .position(x: size.width / 2, y: size.height * 0.46)
                            .transition(.opacity)
                    }
                }
                if let tap = model.tap {
                    TapRipple().position(tap.point).id(tap.id)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                model.handleTap(at: location, in: size)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(model.photo == nil ? "Camera" : "Photo. Double-tap the broken part to outline it.")
            .accessibilityIdentifier("lens.photo")
            .accessibilityAction(named: "Diagnose the sample") { model.tapScripted() }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func backdrop(_ size: CGSize) -> some View {
        if let photo = model.photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 220)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 280)
                }
                .accessibilityHidden(true)
        } else if model.cameraSource == .glasses {
            GlassesPreview(glasses: model.glasses)
        } else {
            CameraBackdrop(camera: model.camera)
        }
    }
}

private struct CameraBackdrop: View {
    @ObservedObject var camera: CameraService

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3, height: 3,
                points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.6, 0.45], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
                colors: [
                    Palette.night, Color(hex: 0x1A1408), Palette.night,
                    Color(hex: 0x0E1A1A), Color(hex: 0x2A1E06), Color(hex: 0x0B0F1C),
                    Palette.night, Color(hex: 0x111827), Palette.night,
                ]
            )
            if camera.isRunning {
                CameraPreview(session: camera.session)
                    .transition(.opacity)
            } else if camera.permissionDenied {
                VStack(spacing: Space.xs) {
                    Image(systemName: "camera.metering.unknown")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Palette.amber)
                    Text("Camera unavailable")
                        .font(Typo.headline)
                        .foregroundStyle(Palette.onNight)
                    Text("Pick a photo or try a demo below.")
                        .font(Typo.footnote)
                        .foregroundStyle(Palette.onNightSecondary)
                }
                .padding(.bottom, 120)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showSettings: Bool
    @Binding var showTogether: Bool

    var body: some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                HStack(spacing: Space.xs) {
                    BrandMark(size: 30)
                    Wordmark()
                }
                Spacer()
                ModePill()
                IconButton(systemName: "person.2.wave.2.fill", label: "Fix it together") { showTogether = true }
                    .accessibilityIdentifier("lens.together")
                IconButton(systemName: "gearshape.fill", label: "Settings") { showSettings = true }
                    .accessibilityIdentifier("lens.settings")
            }
            if model.photo != nil, model.scene == nil {
                DomainPicker()
            }
        }
        .padding(.top, Space.xs)
    }
}

private struct ModePill: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let (title, tint, glyph): (String, Color, String) = {
            if model.isReplay { return ("Demo replay", Palette.sky, "play.rectangle.fill") }
            if model.hasKey { return ("Live · Meta API", Palette.teal, "bolt.fill") }
            return ("No API key", Palette.saffron, "key.fill")
        }()
        HStack(spacing: 6) {
            StatusDot(color: tint, pulsing: model.stage.isBusy)
            Image(systemName: glyph).imageScale(.small)
            Text(title.uppercased()).tracking(0.8)
        }
        .font(Typo.micro)
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .glassCapsule()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityIdentifier("lens.mode")
    }
}

private struct DomainPicker: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(RepairDomain.allCases) { domain in
                let selected = model.domain == domain
                Button {
                    Haptics.tap()
                    Motion.animate { model.domain = domain }
                } label: {
                    Label(domain.title, systemImage: domain.glyph)
                        .font(Typo.caption)
                        .foregroundStyle(selected ? Palette.onAmber : Palette.onNight)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(selected ? Palette.amber : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .glassCapsule()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Status

private struct StatusCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let stage = model.stage
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .top, spacing: Space.s) {
                indicator(stage)
                    .frame(width: 22, height: 22)
                Text(message)
                    .font(Typo.subheadline)
                    .foregroundStyle(Palette.onNight)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)
                if stage.isBusy || stage == .listening {
                    Button("Cancel") { model.cancel() }
                        .font(Typo.caption)
                        .foregroundStyle(Palette.onNightSecondary)
                        .accessibilityIdentifier("lens.cancel")
                } else if model.canRetry {
                    Button("Retry") { model.retry() }
                        .font(Typo.caption)
                        .foregroundStyle(Palette.amber)
                        .accessibilityIdentifier("lens.retry")
                }
            }
            if !model.transcript.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.opening").foregroundStyle(Palette.sky)
                    Text(model.transcript)
                        .italic()
                        .foregroundStyle(Palette.onNight)
                }
                .font(Typo.footnote)
                .accessibilityLabel("You said: \(model.transcript)")
            }
            if model.isReplay, model.photo != nil {
                Text("Scripted demo · highlights are hand-placed · no network calls")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.sky)
            }
        }
        .padding(Space.s)
        .glass(Radius.m, tint: stage.isFailure ? Palette.coral.opacity(0.25) : (stage == .stopped ? Palette.coral.opacity(0.3) : nil))
        .motion(Motion.snappy, value: message)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lens.status")
    }

    private var message: String {
        if model.photo == nil { return "Point at what's broken and take a photo — or try a demo." }
        if model.stage == .idle, model.scene != nil {
            return "Tap the \(model.scene?.targetPart ?? "part"), or hold the mic and ask."
        }
        return model.stage.message
    }

    @ViewBuilder
    private func indicator(_ stage: PipelineStage) -> some View {
        switch stage {
        case .transcribing, .segmenting, .diagnosing:
            ProgressView().tint(Palette.amber)
        case .planning:
            Image(systemName: "shield.lefthalf.filled").foregroundStyle(Palette.sky).symbolEffect(.pulse)
        case .listening:
            Image(systemName: "mic.fill").foregroundStyle(Palette.sky).symbolEffect(.pulse)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.coral)
        case .stopped:
            Image(systemName: "hand.raised.fill").foregroundStyle(Palette.coral)
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.teal)
        case .idle:
            Image(systemName: "viewfinder").foregroundStyle(Palette.amber)
        }
    }
}

// MARK: - Pipeline rail

private struct PipelineRail: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(PipelineStep.allCases.enumerated()), id: \.element) { index, step in
                let state = state(of: step)
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(state == .active ? Palette.amber : (state == .done ? Palette.teal.opacity(0.22) : Color.white.opacity(0.08)))
                            .frame(width: 30, height: 30)
                        Image(systemName: state == .done ? "checkmark" : step.glyph)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(state == .active ? Palette.onAmber : (state == .done ? Palette.teal : Palette.onNightSecondary))
                            .symbolEffect(.pulse, isActive: state == .active)
                    }
                    Text(step.title)
                        .font(Typo.micro)
                        .foregroundStyle(state == .idle ? Palette.onNightSecondary : Palette.onNight)
                    Text(step.model)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.onNightSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(step.title), \(step.model), \(state.label)")
                if index < PipelineStep.allCases.count - 1 {
                    Capsule()
                        .fill(state == .done ? Palette.teal.opacity(0.6) : Color.white.opacity(0.12))
                        .frame(width: 14, height: 2)
                        .offset(y: -18)
                }
            }
        }
        .padding(.vertical, Space.xs)
        .padding(.horizontal, Space.xs)
        .glass(Radius.l)
        .motion(Motion.snappy, value: model.stage)
    }

    private enum StepState {
        case idle, active, done
        var label: String {
            switch self {
            case .idle: "waiting"
            case .active: "working"
            case .done: "done"
            }
        }
    }

    private func state(of step: PipelineStep) -> StepState {
        if model.stage.activeStep == step, model.stage != .ready { return .active }
        switch step {
        case .hear: return model.transcript.isEmpty ? .idle : .done
        case .see: return model.target != nil ? .done : .idle
        case .reason: return model.plan != nil ? .done : .idle
        case .guide: return model.stage == .ready ? .active : .idle
        }
    }
}

// MARK: - Samples

private struct SampleStrip: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel("Try a demo", glyph: "play.rectangle.fill")
                .padding(.leading, Space.xxs)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(DemoLibrary.scenes + [DemoLibrary.safety]) { scene in
                        SampleCard(scene: scene) { model.open(scene) }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

private struct SampleCard: View {
    let scene: DemoScene
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                ZStack {
                    if let image = UIImage(named: scene.assetName) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    if scene.id == DemoLibrary.safety.id {
                        Palette.coral.opacity(0.55)
                        Image(systemName: "hand.raised.fill").foregroundStyle(.white)
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(scene.title)
                        .font(Typo.subheadline)
                        .foregroundStyle(Palette.onNight)
                    Text(scene.subtitle)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.onNightSecondary)
                }
                .padding(.trailing, Space.xs)
            }
            .padding(Space.xs)
            .glass(Radius.m, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Demo: \(scene.title)")
        .accessibilityIdentifier("sample.\(scene.id)")
    }
}

// MARK: - Bottom dock

private struct BottomDock: View {
    @EnvironmentObject private var model: AppModel
    @Binding var pickerItem: PhotosPickerItem?

    var body: some View {
        HStack(alignment: .center) {
            if model.photo == nil {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    DockIcon(systemName: "photo.on.rectangle", label: "Photos")
                }
                .accessibilityLabel("Pick a photo")
                Spacer()
                ShutterButton { model.capture() }
                Spacer()
                DockIcon(systemName: "sparkles", label: "Demo")
                    .onTapGesture { model.open(DemoLibrary.sink) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Open the sink demo")
            } else {
                Button { model.retake() } label: {
                    DockIcon(systemName: "arrow.uturn.backward", label: "Retake")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lens.retake")
                Spacer()
                MicButton()
                Spacer()
                if model.plan != nil {
                    Button { model.showPlan = true } label: {
                        DockIcon(systemName: "list.bullet.clipboard.fill", label: "Plan", tint: Palette.amber)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("lens.openPlan")
                } else if model.scene != nil {
                    Button { model.tapScripted() } label: {
                        DockIcon(systemName: "hand.tap.fill", label: "Tap it", tint: Palette.amber)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.stage.isBusy)
                    .accessibilityLabel("Tap the \(model.scene?.targetPart ?? "part") for me")
                    .accessibilityIdentifier("lens.tapScripted")
                } else {
                    DockIcon(systemName: "hand.tap", label: "Tap", tint: Palette.onNightSecondary).opacity(0.5)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .glass(Radius.xl)
    }
}

private struct DockIcon: View {
    let systemName: String
    let label: String
    var tint: Color = Palette.onNight

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 48, height: 36)
            Text(label).font(Typo.micro)
        }
        .foregroundStyle(tint)
        .frame(minWidth: 56, minHeight: 56)
        .contentShape(Rectangle())
    }
}

private struct ShutterButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.found()
            action()
        } label: {
            ZStack {
                Circle().strokeBorder(Palette.onNight, lineWidth: 4).frame(width: 76, height: 76)
                Circle().fill(Palette.brandGradient).frame(width: 62, height: 62)
                Image(systemName: "viewfinder")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Palette.onAmber)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Take photo")
        .accessibilityIdentifier("lens.shutter")
    }
}

/// Live: hold to talk. Replay: tap to play the scripted question.
private struct MicButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var pressing = false

    var body: some View {
        let listening = model.stage == .listening
        let level = CGFloat(min(model.mic.level * 8, 1))
        ZStack {
            Circle()
                .fill(Palette.sky.opacity(listening ? 0.25 : 0))
                .frame(width: 96 + level * 40, height: 96 + level * 40)
            Circle()
                .fill(listening ? AnyShapeStyle(Palette.sky) : AnyShapeStyle(Palette.brandGradient))
                .frame(width: 72, height: 72)
                .shadow(color: (listening ? Palette.sky : Palette.amber).opacity(0.45), radius: 16, y: 4)
            Image(systemName: listening ? "waveform" : "mic.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Palette.onAmber)
                .symbolEffect(.variableColor.iterative, isActive: listening)
        }
        .frame(width: 96, height: 96)
        .scaleEffect(pressing ? 0.94 : 1)
        .motion(Motion.snappy, value: listening)
        .opacity(model.stage.isBusy ? 0.5 : 1)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressing else { return }
                    pressing = true
                    Haptics.found()
                    model.beginTalking()
                }
                .onEnded { _ in
                    pressing = false
                    model.endTalking()
                }
        )
        .accessibilityElement()
        .accessibilityLabel(model.isReplay ? "Ask the scripted question" : "Hold to describe the problem")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if model.isReplay { model.speakScripted() } else if listening { model.endTalking() } else { model.beginTalking() }
        }
        .accessibilityIdentifier("lens.mic")
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
