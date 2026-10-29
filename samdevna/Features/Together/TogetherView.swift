import CoreGraphics
import CoreImage.CIFilterBuiltins
import SwiftUI

/// The live session, for both roles. Fixer: own camera (iPhone or glasses) with the shared outline.
/// Helper: the Fixer's picture; tap to outline, hold to talk.
struct TogetherView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: TogetherSession
    @State private var talking = false
    @State private var showShare = false

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            stage
            VStack(spacing: Space.s) {
                header
                if let stop = session.safetyStop { SafetyBanner(reason: stop) }
                Spacer(minLength: 0)
                if !session.memorySteps.isEmpty { MemoryCard(title: session.memoryTitle, steps: session.memorySteps) }
                CaptionList(captions: Array(session.captions.prefix(3)))
                controls
            }
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.xs)
        }
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showShare) { ShareCodeSheet(session: session) .presentationDetents([.medium]) }
        .onAppear { if session.role == .fixer, !session.isDemo { showShare = true } }
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                if session.role == .fixer, session.frame == nil {
                    if model.cameraSource == .glasses { GlassesPreview(glasses: model.glasses) } else { CameraPreview(session: model.camera.session) }
                }
                if let frame = session.frame {
                    Image(uiImage: frame).resizable().scaledToFill().frame(width: size.width, height: size.height).clipped()
                }
                if let mask = session.mask, let frameSize = session.frame?.size {
                    SharedMaskView(mask: mask, overlay: session.maskOverlay, transform: FillTransform(imageSize: frameSize, viewSize: size))
                        .id(mask.id)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                guard let frameSize = session.frame?.size else { return }
                let transform = FillTransform(imageSize: frameSize, viewSize: size)
                let p = transform.toImage(location)
                let normalized = CGPoint(x: p.x / frameSize.width, y: p.y / frameSize.height)
                guard (0...1).contains(normalized.x), (0...1).contains(normalized.y) else { return }
                Haptics.tap()
                if session.role == .helper { session.tap(normalized) } else if !session.isDemo { Task { await session.outline(at: normalized, by: "You") } }
            }
        }
        .ignoresSafeArea()
        .accessibilityLabel(session.role == .helper ? "The fixer's camera. Tap a part to outline it for them." : "Your camera, shared live.")
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.xs) {
            LinkPill(link: session.link, fps: session.fps, demo: session.isDemo)
            if model.cameraSource == .glasses, session.role == .fixer {
                Label(model.glasses.usingMock ? "Mock glasses" : "Glasses", systemImage: "eyeglasses")
                    .font(Typo.micro).foregroundStyle(Palette.sky)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
            if session.role == .fixer {
                Button { showShare = true } label: {
                    Text(session.code).font(Typo.mono).tracking(2)
                        .padding(.horizontal, 12).padding(.vertical, 8).background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityLabel("Join code \(session.code). Show share options.")
            }
            Text("\(max(session.peerCount, 1))").font(Typo.micro)
                .padding(8).background(.ultraThinMaterial, in: Circle())
                .accessibilityLabel("\(session.peerCount) people in the session")
            IconButton(systemName: "xmark", label: "Leave session") { model.endTogether() }
        }
        .padding(.top, Space.xs)
        .overlay(alignment: .bottom) {
            if let busy = session.busy {
                Text(busy).font(Typo.caption).foregroundStyle(Palette.amber)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(.ultraThinMaterial, in: Capsule())
                    .offset(y: 40)
            } else if let timing = session.lastTiming {
                Text(timing).font(Typo.monoSmall).foregroundStyle(Palette.onNightSecondary).offset(y: 34)
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack {
            Button { session.clearMask(broadcast: true) } label: {
                Label("Clear", systemImage: "eraser").font(Typo.footnote)
            }
            .buttonStyle(.bordered)
            .disabled(session.mask == nil)
            Spacer()
            Circle()
                .fill(talking ? Palette.sky : Palette.amber)
                .frame(width: 84, height: 84)
                .overlay(Image(systemName: talking ? "waveform" : "mic.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(Palette.onAmber))
                .shadow(color: Palette.amber.opacity(0.35), radius: 18)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !talking else { return }
                        talking = true
                        Task { await session.beginTalking() }
                    }
                    .onEnded { _ in
                        talking = false
                        Task { await session.endTalking() }
                    })
                .accessibilityLabel("Hold to talk")
                .accessibilityAddTraits(.isButton)
            Spacer()
            if session.role == .fixer {
                Button { session.saveMemoryNow() } label: { Label("Save", systemImage: "square.and.arrow.down").font(Typo.footnote) }
                    .buttonStyle(.bordered)
                    .disabled(session.isDemo)
            } else {
                Color.clear.frame(width: 80, height: 1)
            }
        }
        .tint(Palette.onNight)
    }
}

// MARK: - Pieces

private struct SharedMaskView: View {
    let mask: SharedMask
    let overlay: UIImage?
    let transform: FillTransform

    var body: some View {
        let size = transform.imageSize
        let rect = CGRect(x: mask.box[0] * size.width, y: mask.box[1] * size.height,
                          width: (mask.box[2] - mask.box[0]) * size.width, height: (mask.box[3] - mask.box[1]) * size.height)
        let view = transform.toView(rect)
        ZStack(alignment: .topLeading) {
            if let overlay {
                Image(uiImage: overlay).resizable().frame(width: view.width, height: view.height)
                    .position(x: view.midX, y: view.midY)
            }
            RoundedRectangle(cornerRadius: 10)
                .stroke(Palette.amber, style: StrokeStyle(lineWidth: 3, dash: overlay == nil ? [10, 6] : []))
                .frame(width: view.width, height: view.height)
                .position(x: view.midX, y: view.midY)
            Text([mask.label.isEmpty ? nil : mask.label, mask.model, mask.by.isEmpty ? nil : "by \(mask.by)"].compactMap { $0 }.joined(separator: " · "))
                .font(Typo.monoSmall).foregroundStyle(Palette.onAmber)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Palette.amber, in: Capsule())
                .position(x: view.midX, y: max(14, view.minY - 16))
        }
        .animation(.smooth(duration: 0.35), value: mask.box)
        .allowsHitTesting(false)
    }
}

private struct LinkPill: View {
    let link: TogetherTransport.Link
    let fps: Double
    let demo: Bool

    var body: some View {
        let (text, color): (String, Color) = {
            if demo { return ("Demo mode · scripted", Palette.sky) }
            switch link {
            case .connecting: return ("Connecting…", Palette.onNightSecondary)
            case .live: return (fps > 0 ? "Live · \(Int(fps.rounded())) fps" : "Live", Palette.teal)
            case .snapshot: return ("Snapshot mode · 1 frame/s", Palette.amber)
            case .closed(let why): return (why, Palette.coral)
            }
        }()
        HStack(spacing: 6) {
            StatusDot(color: color, pulsing: link == .connecting)
            Text(text).font(Typo.micro)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct SafetyBanner: View {
    let reason: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Safety stop", systemImage: "exclamationmark.octagon.fill").font(Typo.headline).foregroundStyle(Palette.coral)
            Text(reason).font(Typo.footnote).foregroundStyle(Palette.onNight)
            Text(SafetyGuard.spokenStop).font(Typo.caption).foregroundStyle(Palette.onNightSecondary)
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.coral.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.m))
        .overlay(RoundedRectangle(cornerRadius: Radius.m).stroke(Palette.coral.opacity(0.6)))
    }
}

private struct CaptionList: View {
    let captions: [Caption]
    var body: some View {
        VStack(spacing: Space.xs) {
            ForEach(captions) { caption in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(caption.name).font(Typo.caption).foregroundStyle(Palette.onNightSecondary)
                        Text(caption.translated != caption.original ? "muse-voice-transcribe → muse-spark" : "muse-voice-transcribe")
                            .font(Typo.monoSmall).foregroundStyle(Palette.sky)
                    }
                    Text(caption.translated).font(Typo.bodyEmphasis).foregroundStyle(Palette.onNight)
                    if caption.translated != caption.original {
                        Text(caption.original).font(Typo.footnote).foregroundStyle(Palette.onNightSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.s))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: captions.map(\.id))
    }
}

private struct MemoryCard: View {
    let title: String
    let steps: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Repair memory", systemImage: "book.pages").font(Typo.caption).foregroundStyle(Palette.amber)
                Spacer()
                Text("muse-spark-1.3").font(Typo.monoSmall).foregroundStyle(Palette.onNightSecondary)
            }
            Text(title).font(Typo.headline).foregroundStyle(Palette.onNight)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)").font(Typo.footnote).foregroundStyle(Palette.onNight)
            }
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.m))
    }
}

private struct ShareCodeSheet: View {
    @ObservedObject var session: TogetherSession

    var body: some View {
        VStack(spacing: Space.m) {
            Text("Invite a helper").font(Typo.title3)
            Text(session.code).font(.system(size: 44, weight: .heavy, design: .monospaced)).tracking(6)
            if let url = session.shareURL {
                if let qr = Self.qr(url.absoluteString) {
                    Image(uiImage: qr).interpolation(.none).resizable().frame(width: 170, height: 170)
                        .padding(10).background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("QR code for the join link")
                }
                ShareLink(item: url, message: Text("Help me fix this, live: \(url.absoluteString)")) {
                    Label("Share link", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                Text("Opens in any browser. In Fix-it Lens: Fix it together → Join.").font(Typo.footnote).foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(Space.l)
    }

    static func qr(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
