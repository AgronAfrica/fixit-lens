import CoreGraphics
import SwiftUI

/// Full-screen, hands-free repair guide. Each step's part is outlined on the photo (SAM 3.1, or
/// a scripted region in demo replay) and read aloud; the user answers by voice or with the buttons.
struct GuideView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PhotoWithSpotlight(size: geo.size)
                VStack(spacing: Space.s) {
                    GuideTopBar()
                    if model.review == .running || model.review == .passed {
                        ReviewBadge(state: model.review)
                    }
                    if let stop = model.guideStop {
                        SafetyBanner(reason: stop)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                    if model.guidePhase == .finished {
                        FinishedCard()
                    } else {
                        StepCard()
                    }
                }
                .padding(.horizontal, Space.m)
                .padding(.bottom, Space.xs)
            }
        }
        .background(Palette.night.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .motion(Motion.smooth, value: model.stepIndex)
        .motion(Motion.snappy, value: model.guideStop)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model.endGuide()
        }
    }
}

private struct PhotoWithSpotlight: View {
    @EnvironmentObject private var model: AppModel
    let size: CGSize

    var body: some View {
        ZStack {
            if let photo = model.photo {
                let transform = FillTransform(imageSize: photo.size, viewSize: size)
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .accessibilityHidden(true)
                Spotlight(rect: model.highlight.map { transform.toView($0.maskRect) }, dim: 0.55)
                if let highlight = model.highlight {
                    MaskOverlay(object: highlight, transform: transform, label: model.currentStep?.part.nilIfEmpty)
                        .id(highlight.box.rect.debugDescription)
                        .accessibilityIdentifier("guide.highlight")
                }
                if model.guidePhase == .locating {
                    ScanSweep().opacity(0.6)
                }
            }
            LinearGradient(colors: [.black.opacity(0.6), .clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .ignoresSafeArea()
    }
}

private struct GuideTopBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let total = model.plan?.steps.count ?? 0
        VStack(spacing: Space.s) {
            HStack {
                IconButton(systemName: "xmark", label: "End guide") { model.endGuide() }
                    .accessibilityIdentifier("guide.close")
                Spacer()
                VStack(spacing: 2) {
                    Text(model.plan?.objectName ?? "")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.onNightSecondary)
                    Text(total > 0 ? "Step \(min(model.stepIndex + 1, total)) of \(total)" : "")
                        .font(Typo.headline)
                        .foregroundStyle(Palette.onNight)
                        .monospacedDigit()
                        .accessibilityIdentifier("guide.progress")
                }
                Spacer()
                Pill(title: model.isReplay ? "Replay" : (model.handsFree ? "Hands-free" : "Manual"),
                     glyph: model.isReplay ? "play.rectangle.fill" : (model.handsFree ? "ear.fill" : "hand.tap.fill"),
                     tint: model.isReplay ? Palette.sky : Palette.teal)
            }
            HStack(spacing: 4) {
                ForEach(0..<max(total, 1), id: \.self) { index in
                    Capsule()
                        .fill(index < model.stepIndex || model.guidePhase == .finished
                              ? Palette.teal
                              : (index == model.stepIndex ? Palette.amber : Color.white.opacity(0.2)))
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.top, Space.xs)
    }
}

private struct SafetyBanner: View {
    @EnvironmentObject private var model: AppModel
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label("Safety stop", systemImage: "hand.raised.fill")
                .font(Typo.headline)
                .foregroundStyle(.white)
            Text(reason)
                .font(Typo.callout)
                .foregroundStyle(.white.opacity(0.92))
            Button("End guide") { model.endGuide() }
                .font(Typo.headline)
                .foregroundStyle(Palette.coral)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.xs)
                .background(.white, in: Capsule())
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.coral, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide.safetyStop")
    }
}

private struct StepCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let step = model.currentStep {
                PhaseIndicator()
                Text(step.title)
                    .font(Typo.title)
                    .foregroundStyle(Palette.onNight)
                    .accessibilityIdentifier("guide.stepTitle")
                Text(step.instruction)
                    .font(Typo.body)
                    .foregroundStyle(Palette.onNight.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                if !step.tool.isEmpty || !step.caution.isEmpty {
                    HStack(spacing: 6) {
                        if !step.tool.isEmpty { Pill(title: step.tool, glyph: "wrench.adjustable", tint: Palette.sky) }
                        if !step.caution.isEmpty { Pill(title: step.caution, glyph: "exclamationmark.triangle.fill", tint: Palette.saffron) }
                    }
                }
                Conversation()
                if let notice = model.guideNotice {
                    Label(notice, systemImage: "exclamationmark.circle")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.coral)
                }
                QuickChips()
                Controls()
            }
        }
        .padding(Space.m)
        .glass(Radius.xl)
        .id(model.stepIndex)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }
}

private struct PhaseIndicator: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let phase = model.guidePhase
        HStack(spacing: Space.xs) {
            Image(systemName: phase.glyph)
                .foregroundStyle(phase.tint)
                .symbolEffect(.variableColor.iterative, isActive: phase == .speaking || phase == .listening)
            Text(phase.label)
                .font(Typo.caption)
                .foregroundStyle(phase.tint)
            if phase == .listening {
                LevelBars(level: model.mic.level)
            } else if phase == .locating || phase == .thinking || phase == .hearing {
                ProgressView().controlSize(.mini).tint(phase.tint)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide.phase")
    }
}

private struct LevelBars: View {
    let level: Float

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                let threshold = Float(index) * 0.012
                Capsule()
                    .fill(Palette.sky.opacity(level > threshold ? 1 : 0.25))
                    .frame(width: 3, height: 6 + CGFloat(index) * 3)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct Conversation: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if !model.heard.isEmpty || model.exchanges.last != nil {
            VStack(alignment: .leading, spacing: 6) {
                if !model.heard.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "person.wave.2.fill").foregroundStyle(Palette.sky)
                        Text("“\(model.heard)”").italic()
                    }
                    .font(Typo.footnote)
                    .foregroundStyle(Palette.onNight)
                    .accessibilityLabel("You said \(model.heard)")
                }
                if let last = model.exchanges.last {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkle").foregroundStyle(Palette.amber)
                        Text(last.answer)
                    }
                    .font(Typo.footnote)
                    .foregroundStyle(Palette.onNight)
                    .accessibilityIdentifier("guide.answer")
                }
            }
            .padding(Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        }
    }
}

private struct QuickChips: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                chip(model.suggestedQuestion, glyph: "questionmark.bubble.fill", id: "guide.ask") { model.ask(model.suggestedQuestion) }
                chip("Done", glyph: "checkmark", id: "guide.done") { model.ask("Done") }
                if model.isReplay {
                    chip("I smell gas", glyph: "flame.fill", id: "guide.gas") { model.ask("Wait, I think I can smell gas") }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, glyph: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title, systemImage: glyph)
                .font(Typo.caption)
                .foregroundStyle(Palette.onNight)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .glassCapsule(interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

private struct Controls: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let listening = model.guidePhase == .listening
        HStack {
            IconButton(systemName: "backward.fill", label: "Previous step", size: 50) { model.guideBack() }
                .disabled(model.stepIndex == 0)
                .opacity(model.stepIndex == 0 ? 0.4 : 1)
            Spacer()
            IconButton(systemName: "arrow.counterclockwise", label: "Repeat step", size: 50) { model.guideRepeat() }
            Spacer()
            Button {
                Haptics.found()
                model.guideListen()
            } label: {
                Image(systemName: listening ? "waveform" : "mic.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Palette.onAmber)
                    .frame(width: 64, height: 64)
                    .background(listening ? AnyShapeStyle(Palette.sky) : AnyShapeStyle(Palette.brandGradient), in: Circle())
                    .symbolEffect(.variableColor.iterative, isActive: listening)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isReplay ? "Ask the suggested question" : "Talk now")
            .accessibilityIdentifier("guide.mic")
            Spacer()
            Button {
                Haptics.step()
                model.guideNext()
            } label: {
                Label("Next", systemImage: "forward.fill")
                    .labelStyle(.titleAndIcon)
                    .font(Typo.headline)
                    .foregroundStyle(Palette.onAmber)
                    .padding(.horizontal, Space.m)
                    .frame(height: 50)
                    .background(Palette.amber, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("guide.next")
        }
    }
}

private struct FinishedCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Palette.teal)
                .symbolEffect(.bounce, value: model.guidePhase)
            Text("Fixed? Give it a test.")
                .font(Typo.title)
                .foregroundStyle(Palette.onNight)
            Text("If it still isn't right, tap the part again for a fresh look.")
                .font(Typo.callout)
                .foregroundStyle(Palette.onNightSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: Space.s) {
                Button("Start over") { model.guideRepeatFromStart() }
                    .buttonStyle(SecondaryButtonStyle(onDark: true))
                Button("Finish") {
                    model.endGuide()
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("guide.finish")
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity)
        .glass(Radius.xl)
        .accessibilityIdentifier("guide.finished")
    }
}
