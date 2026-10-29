import CoreGraphics
import SwiftUI

// MARK: - Surfaces

extension View {
    /// Liquid Glass surface in a continuous rounded rectangle.
    func glass(_ radius: CGFloat = Radius.m, tint: Color? = nil, interactive: Bool = false) -> some View {
        glassEffect(Self.glassStyle(tint: tint, interactive: interactive),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Liquid Glass surface in a capsule.
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        glassEffect(Self.glassStyle(tint: tint, interactive: interactive), in: Capsule())
    }

    /// Liquid Glass surface in a circle.
    func glassCircle(tint: Color? = nil, interactive: Bool = true) -> some View {
        glassEffect(Self.glassStyle(tint: tint, interactive: interactive), in: Circle())
    }

    /// Opaque content card for sheets and lists.
    func card(_ radius: CGFloat = Radius.m, fill: Color = Palette.surface) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.hairline)
            )
    }

    private static func glassStyle(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

// MARK: - Brand

struct BrandMark: View {
    var size: CGFloat = 36

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct Wordmark: View {
    var onDark = true

    var body: some View {
        HStack(spacing: 0) {
            Text("Fix-it ")
                .foregroundStyle(onDark ? Palette.onNight : Palette.text)
            Text("Lens")
                .foregroundStyle(Palette.amber)
        }
        .font(Typo.headline)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .minimumScaleFactor(0.8)
        .layoutPriority(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fix-it Lens")
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Palette.amber
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.headline)
            .foregroundStyle(Palette.onAmber)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, Space.m)
            .background {
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .fill(tint == Palette.amber ? AnyShapeStyle(Palette.brandGradient) : AnyShapeStyle(tint))
            }
            .shadow(color: tint.opacity(configuration.isPressed ? 0.15 : 0.35), radius: configuration.isPressed ? 6 : 16, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .motion(Motion.snappy, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var onDark = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.headline)
            .foregroundStyle(onDark ? Palette.onNight : Palette.text)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Space.m)
            .glass(Radius.m, interactive: true)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .motion(Motion.snappy, value: configuration.isPressed)
    }
}

/// 44-pt circular glass icon button with a required accessibility label.
struct IconButton: View {
    let systemName: String
    let label: String
    var tint: Color = Palette.onNight
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCircle()
        .accessibilityLabel(label)
    }
}

// MARK: - Labels

struct SectionLabel: View {
    let text: String
    var glyph: String?
    var tint: Color = Palette.amber

    init(_ text: String, glyph: String? = nil, tint: Color = Palette.amber) {
        self.text = text
        self.glyph = glyph
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 6) {
            if let glyph { Image(systemName: glyph) }
            Text(text.uppercased()).tracking(1.4)
        }
        .font(Typo.micro)
        .foregroundStyle(tint)
        .accessibilityAddTraits(.isHeader)
    }
}

struct Pill: View {
    let title: String
    var glyph: String?
    var tint: Color = Palette.amber
    var filled = false

    var body: some View {
        HStack(spacing: 5) {
            if let glyph { Image(systemName: glyph).imageScale(.small) }
            Text(title).lineLimit(1)
        }
        .font(Typo.caption)
        .foregroundStyle(filled ? Palette.onAmber : tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.14)), in: Capsule())
    }
}

struct StatusDot: View {
    let color: Color
    var pulsing = false
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .background(
                Circle()
                    .fill(color.opacity(0.45))
                    .scaleEffect(on ? 2.4 : 1)
                    .opacity(on ? 0 : 1)
            )
            .onAppear {
                guard pulsing, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { on = true }
            }
            .accessibilityHidden(true)
    }
}

struct ConfidenceMeter: View {
    let value: Double

    var body: some View {
        let clamped = min(max(value, 0), 1)
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.hairline)
                    Capsule()
                        .fill(Palette.brandGradient)
                        .frame(width: geo.size.width * clamped)
                }
            }
            .frame(width: 56, height: 6)
            Text("\(Int((clamped * 100).rounded()))%")
                .font(Typo.monoSmall)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Confidence \(Int((clamped * 100).rounded())) percent")
    }
}

// MARK: - Loading and empty states

private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.18), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.6)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

struct EmptyStateView: View {
    let glyph: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: glyph)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Palette.amber)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(Typo.title3)
                .foregroundStyle(Palette.text)
            Text(message)
                .font(Typo.callout)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, Space.xs)
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Spotlight

/// Dims everything except `rect`, which glows. Used to point at the part for the current step.
struct Spotlight: View {
    let rect: CGRect?
    var dim: Double = 0.5

    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(rect == nil ? 0 : dim))
            if let rect {
                RoundedRectangle(cornerRadius: min(rect.width, rect.height) * 0.22, style: .continuous)
                    .frame(width: rect.width + 24, height: rect.height + 24)
                    .position(x: rect.midX, y: rect.midY)
                    .blur(radius: 10)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Layout

/// Wraps children onto new lines, like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
