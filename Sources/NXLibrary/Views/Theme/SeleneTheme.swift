import SwiftUI

public enum SeleneTheme {
    public static let canvas = Color(hex: 0x05070A)
    public static let canvasRaised = Color(hex: 0x0B0E13)
    public static let surface = Color(hex: 0x12161D)
    public static let surfaceHover = Color(hex: 0x1A1F27)
    public static let surfaceActive = Color(hex: 0x232A35)
    public static let border = Color(hex: 0x262C36)
    public static let borderStrong = Color(hex: 0x3A424F)
    public static let ink = Color(hex: 0xF2F5F9)
    public static let inkSecondary = Color(hex: 0xC3CAD4)
    public static let inkMuted = Color(hex: 0x8B95A3)
    public static let inkFaint = Color(hex: 0x5C6673)
    public static let accent = Color(hex: 0x9CCBFF)
    public static let focus = Color.white
    public static let success = Color(hex: 0x3DDC84)
    public static let warning = Color(hex: 0xE8B65C)
    public static let danger = Color(hex: 0xFF6B6B)

    public static let rowRadius: CGFloat = 10
    public static let contentRadius: CGFloat = 12
    public static let cardRadius: CGFloat = 16
    public static let modalRadius: CGFloat = 20
    public static let coverRadius: CGFloat = 6
    public static let quick = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)
    public static let standard = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.24)
    public static let focusIn = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)
    public static let focusOut = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)
    public static let screen = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.32)
    public static let art = Animation.easeOut(duration: 0.42)
    public static let menu = Animation.spring(response: 0.26, dampingFraction: 0.88)
    public static let expand = Animation.spring(response: 0.42, dampingFraction: 0.86)

    public static let heroLeftScrim = LinearGradient(
        stops: [
            .init(color: .black.opacity(0.48), location: 0.00),
            .init(color: .black.opacity(0.38), location: 0.22),
            .init(color: .black.opacity(0.22), location: 0.44),
            .init(color: .black.opacity(0.08), location: 0.62),
            .init(color: .clear, location: 0.78)
        ],
        startPoint: .leading, endPoint: .trailing
    )
    public static let heroBottomScrim = LinearGradient(
        stops: [
            .init(color: .black.opacity(0.86), location: 0.00),
            .init(color: .black.opacity(0.60), location: 0.14),
            .init(color: .black.opacity(0.24), location: 0.28),
            .init(color: .clear, location: 0.45)
        ],
        startPoint: .bottom, endPoint: .top
    )
    public static let topScrim = LinearGradient(
        stops: [
            .init(color: .black.opacity(0.45), location: 0.00),
            .init(color: .black.opacity(0.20), location: 0.08),
            .init(color: .clear, location: 0.16)
        ],
        startPoint: .top, endPoint: .bottom
    )
    public static let heroAmbientVignette = RadialGradient(
        colors: [
            .black.opacity(0.42),
            .black.opacity(0.20),
            .clear
        ],
        center: .topLeading,
        startRadius: 50,
        endRadius: 750
    )
}

public extension View {
    /// The single focus language for the app: a white ring with a black halo,
    /// visible over both dark chrome and bright artwork.
    func seleneFocus(_ focused: Bool, radius: CGFloat = SeleneTheme.rowRadius) -> some View {
        overlay {
            ZStack {
                RoundedRectangle(cornerRadius: radius + 2, style: .continuous)
                    .strokeBorder(.black.opacity(focused ? 0.55 : 0), lineWidth: 4)
                RoundedRectangle(cornerRadius: radius + 2, style: .continuous)
                    .strokeBorder(SeleneTheme.focus.opacity(focused ? 0.96 : 0), lineWidth: 2)
            }
        }
        .animation(SeleneTheme.focusIn, value: focused)
    }

    /// Capsule variant of the single focus language, for pills and chips.
    func seleneCapsuleFocus(_ focused: Bool, offset: CGFloat = 0) -> some View {
        overlay {
            ZStack {
                Capsule()
                    .strokeBorder(.black.opacity(focused ? 0.55 : 0), lineWidth: 4)
                Capsule()
                    .strokeBorder(SeleneTheme.focus.opacity(focused ? 0.96 : 0), lineWidth: 2)
            }
            .padding(-offset)
        }
        .animation(SeleneTheme.focusIn, value: focused)
    }
}

private struct SeleneFocusedRowKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

public extension EnvironmentValues {
    var seleneFocusedRowTitle: String? {
        get { self[SeleneFocusedRowKey.self] }
        set { self[SeleneFocusedRowKey.self] = newValue }
    }
}

private struct SeleneReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var seleneReduceMotion: Bool {
        get { self[SeleneReduceMotionKey.self] }
        set { self[SeleneReduceMotionKey.self] = newValue }
    }
}

public extension View {
    /// Activates the virtual focus ring with Return or Space on macOS 14+.
    /// Text fields and other focusable controls consume their own keys first.
    @ViewBuilder
    func seleneActivationKeys(_ activate: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self
                .onKeyPress(.return) {
                    activate()
                    return .handled
                }
                .onKeyPress(.space) {
                    activate()
                    return .handled
                }
        } else {
            self
        }
    }
}

public extension Color {
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
