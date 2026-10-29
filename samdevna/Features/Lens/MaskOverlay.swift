import CoreGraphics
import SwiftUI

/// Draws a SAM 3.1 mask (or a demo region) over the aspect-filled photo.
struct MaskOverlay: View {
    let object: SAMObject
    let transform: FillTransform
    var label: String?
    var emphasized = true

    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let rect = transform.toView(object.maskRect)
        let shape = RoundedRectangle(cornerRadius: min(14, min(rect.width, rect.height) * 0.25), style: .continuous)
        ZStack(alignment: .topLeading) {
            Group {
                if let overlay = object.overlay {
                    Image(uiImage: overlay)
                        .resizable()
                        .interpolation(.medium)
                } else {
                    shape
                        .fill(Palette.amber.opacity(0.16))
                        .overlay(shape.strokeBorder(Palette.amber, style: StrokeStyle(lineWidth: 2.5, dash: object.isDemoRegion ? [8, 5] : [])))
                }
            }
            .frame(width: rect.width, height: rect.height)
            .shadow(color: Palette.amber.opacity(emphasized ? (glow ? 0.85 : 0.35) : 0), radius: glow ? 18 : 8)

            if let label, !label.isEmpty {
                Text(label)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.onAmber)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Palette.amber, in: Capsule())
                    .fixedSize()
                    .offset(y: rect.minY > 40 ? -30 : rect.height + 6)
            }
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
        .onAppear {
            guard emphasized, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { glow = true }
        }
        .accessibilityElement()
        .accessibilityLabel(label.map { "Highlighted: \($0)" } ?? "Highlighted part")
    }
}

struct TapRipple: View {
    @State private var expanded = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.amber, lineWidth: 2)
                .frame(width: 22, height: 22)
                .scaleEffect(expanded ? 3.4 : 1)
                .opacity(expanded ? 0 : 1)
            Circle()
                .fill(Palette.amber)
                .frame(width: 10, height: 10)
                .shadow(color: Palette.amber, radius: 6)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).repeatCount(2, autoreverses: false)) { expanded = true }
        }
        .accessibilityHidden(true)
    }
}

/// A scan line sweeping down the photo while SAM 3.1 works.
struct ScanSweep: View {
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, Palette.amber.opacity(0.35), Palette.amber.opacity(0.9), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 90)
            .offset(y: progress * (geo.size.height + 90) - 90)
            .blendMode(.screen)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { progress = 0.5; return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { progress = 1 }
        }
        .accessibilityHidden(true)
    }
}

/// Corner brackets that invite a tap.
struct CoachReticle: View {
    let text: String
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.s) {
            ZStack {
                ForEach(0..<4, id: \.self) { corner in
                    Bracket()
                        .stroke(Palette.amber, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 26, height: 26)
                        .rotationEffect(.degrees(Double(corner) * 90))
                        .offset(x: corner == 0 || corner == 3 ? -46 : 46, y: corner < 2 ? -46 : 46)
                }
            }
            .frame(width: 120, height: 120)
            .scaleEffect(breathe ? 1.06 : 0.96)
            Text(text)
                .font(Typo.subheadline)
                .foregroundStyle(Palette.onNight)
                .padding(.horizontal, Space.s)
                .padding(.vertical, 6)
                .glassCapsule()
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityHidden(true)
    }

    private struct Bracket: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            return path
        }
    }
}
