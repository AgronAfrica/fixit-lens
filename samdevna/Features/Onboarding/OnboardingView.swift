import CoreGraphics
import SwiftUI

private struct OnboardingPage: Identifiable {
    let id: Int
    let glyph: String
    let model: String
    let title: String
    let body: String
    var tint: Color = Palette.amber
}

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages = [
        OnboardingPage(
            id: 0, glyph: "viewfinder", model: "SAM 3.1",
            title: "Point at what's broken.",
            body: "Tap the drip, the chain or the hinge. Segment Anything 3.1 outlines exactly that part."
        ),
        OnboardingPage(
            id: 1, glyph: "brain", model: "Muse Spark 1.3 · Muse Wonder 1.0",
            title: "Know the fault.",
            body: "Muse Spark works out what's wrong and why. Muse Wonder checks the plan step by step before you start."
        ),
        OnboardingPage(
            id: 2, glyph: "waveform.and.mic", model: "Muse Voice Transcribe",
            title: "Hands busy? Just talk.",
            body: "The guide reads each step aloud and lights up the part to touch. Say “done”, or ask “what's this screw?”.",
            tint: Palette.sky
        ),
        OnboardingPage(
            id: 3, glyph: "hand.raised.fill", model: "Safety stop",
            title: "Knows when to stop.",
            body: "Gas, mains electrics, refrigerant, airbags, fuel leaks or structural damage? It stops and tells you to call a professional. It only looks at objects, never people or health.",
            tint: Palette.coral
        ),
    ]

    var body: some View {
        ZStack {
            AnimatedMesh(animate: !reduceMotion)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    BrandMark(size: 34)
                    Wordmark()
                    Spacer()
                    if page < pages.count - 1 {
                        Button("Skip") { onFinish() }
                            .font(Typo.subheadline)
                            .foregroundStyle(Palette.onNightSecondary)
                            .accessibilityIdentifier("onboarding.skip")
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.s)

                Spacer(minLength: Space.l)

                TabView(selection: $page) {
                    ForEach(pages) { item in
                        PageView(page: item).tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                PageDots(count: pages.count, current: page)
                    .padding(.bottom, Space.l)

                Button {
                    Haptics.tap()
                    if page < pages.count - 1 {
                        Motion.animate(Motion.smooth) { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page == pages.count - 1 ? "Start fixing" : "Continue")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.l)
                .accessibilityIdentifier("onboarding.continue")
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct PageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: Space.l) {
            ZStack {
                Circle()
                    .fill(page.tint.opacity(0.14))
                    .frame(width: 180, height: 180)
                Circle()
                    .strokeBorder(page.tint.opacity(0.4), lineWidth: 1)
                    .frame(width: 140, height: 140)
                Image(systemName: page.glyph)
                    .font(.system(size: 60, weight: .semibold))
                    .foregroundStyle(page.tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)
            VStack(spacing: Space.s) {
                Pill(title: page.model, tint: page.tint)
                Text(page.title)
                    .font(Typo.hero)
                    .foregroundStyle(Palette.onNight)
                    .multilineTextAlignment(.center)
                Text(page.body)
                    .font(Typo.body)
                    .foregroundStyle(Palette.onNightSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.xl)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Palette.amber : Color.white.opacity(0.25))
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .motion(Motion.snappy, value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

/// Slow-drifting dark mesh with an amber glow.
struct AnimatedMesh: View {
    var animate = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animate)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate)
            let drift = animate ? sin(t * 0.35) * 0.12 : 0
            let drift2 = animate ? cos(t * 0.27) * 0.1 : 0
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + drift, 0.42 + drift2], [1, 0.5],
                    [0, 1], [0.5 - drift2, 1], [1, 1],
                ],
                colors: [
                    Palette.night, Color(hex: 0x14110A), Palette.night,
                    Color(hex: 0x0C1618), Color(hex: 0x3A2A08), Color(hex: 0x0D1222),
                    Palette.night, Color(hex: 0x10141F), Palette.night,
                ]
            )
        }
    }
}
