import CoreGraphics
import SwiftUI
import UIKit

// MARK: - Fix-it Lens design system
//
// One source of truth for colour, type, spacing, shape, motion and haptics.
// Colours adapt to light and dark mode; the camera lens itself always renders dark
// so overlays stay legible on top of any photo.

enum Palette {
    // Surfaces (adaptive)
    static let canvas = adaptive(light: 0xF5F3EE, dark: 0x0A0B0F)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x14161D)
    static let elevated = adaptive(light: 0xECE9E2, dark: 0x1D2029)
    static let hairline = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.10)

    // Text (adaptive)
    static let text = adaptive(light: 0x14161C, dark: 0xF4F2EC)
    static let textSecondary = adaptive(light: 0x5B6070, dark: 0xA4AABA)
    static let textTertiary = adaptive(light: 0x8A8F9C, dark: 0x6E7482)

    // Brand + semantic (fixed)
    /// Signal amber: the brand colour, primary actions and SAM masks.
    static let amber = Color(hex: 0xFFB020)
    static let amberDeep = Color(hex: 0xE88A00)
    static let onAmber = Color(hex: 0x16120A)
    /// Safe / done.
    static let teal = Color(hex: 0x34D1B0)
    /// Listening / information.
    static let sky = Color(hex: 0x5AB4FF)
    /// Caution.
    static let saffron = Color(hex: 0xFF8A3D)
    /// Safety stop / errors.
    static let coral = Color(hex: 0xFF5247)

    // Lens chrome (always dark)
    static let night = Color(hex: 0x06070A)
    static let nightRaised = Color(hex: 0x161922)
    static let onNight = Color(hex: 0xF4F2EC)
    static let onNightSecondary = Color(hex: 0xA4AABA)

    static let brandGradient = LinearGradient(
        colors: [Color(hex: 0xFFC94D), amber, amberDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static func adaptive(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Type scale built on Dynamic Type text styles, so every label scales with the user's setting.
enum Typo {
    static let hero = Font.system(.largeTitle, design: .rounded, weight: .heavy)
    static let display = Font.system(.title, design: .rounded, weight: .bold)
    static let title = Font.system(.title2, design: .rounded, weight: .bold)
    static let title3 = Font.system(.title3, design: .rounded, weight: .semibold)
    static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
    static let body = Font.system(.body, design: .rounded)
    static let bodyEmphasis = Font.system(.body, design: .rounded, weight: .semibold)
    static let callout = Font.system(.callout, design: .rounded, weight: .medium)
    static let subheadline = Font.system(.subheadline, design: .rounded, weight: .medium)
    static let footnote = Font.system(.footnote, design: .rounded, weight: .medium)
    static let caption = Font.system(.caption, design: .rounded, weight: .semibold)
    static let micro = Font.system(.caption2, design: .rounded, weight: .bold)
    static let mono = Font.system(.footnote, design: .monospaced, weight: .medium)
    static let monoSmall = Font.system(.caption2, design: .monospaced, weight: .semibold)
}

enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 40
}

enum Radius {
    static let s: CGFloat = 12
    static let m: CGFloat = 18
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
}

/// Motion presets. Use `Motion.animate` from model code and `.motion(_:value:)` in views:
/// both fall back to a short cross-fade when Reduce Motion is on.
enum Motion {
    static let snappy = Animation.spring(duration: 0.32, bounce: 0.18)
    static let smooth = Animation.smooth(duration: 0.45)
    static let gentle = Animation.spring(duration: 0.6, bounce: 0.12)
    static let reduced = Animation.easeInOut(duration: 0.15)

    @MainActor
    static func animate(_ animation: Animation = snappy, _ body: () -> Void) {
        withAnimation(UIAccessibility.isReduceMotionEnabled ? reduced : animation, body)
    }
}

private struct MotionAware<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? Motion.reduced : animation, value: value)
    }
}

extension View {
    func motion<V: Equatable>(_ animation: Animation = Motion.snappy, value: V) -> some View {
        modifier(MotionAware(animation: animation, value: value))
    }
}

/// Haptic vocabulary: one meaning per pattern.
@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func found() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func step() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8) }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, dark, light

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}
