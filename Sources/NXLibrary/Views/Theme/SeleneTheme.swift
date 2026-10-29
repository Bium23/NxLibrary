import SwiftUI
import NXLibraryCore

public enum SeleneTheme {
    private static var palette: SelenePalette { ThemeStore.shared.palette }

    public static var focus: Color { Color(hex: palette.focus) }
    public static var onFocus: Color { Color(hex: palette.onFocus) }
    public static var ink: Color { Color(hex: palette.ink) }
    public static var ink90: Color { ink.opacity(0.90) }
    public static var ink82: Color { ink.opacity(0.82) }
    public static var ink60: Color { ink.opacity(0.60) }
    public static var ink25: Color { ink.opacity(0.25) }
    public static var ink15: Color { ink.opacity(0.15) }
    public static var scrim: Color { Color(hex: palette.scrim) }
    public static var scrim65: Color { scrim.opacity(0.65) }
    public static var scrim45: Color { scrim.opacity(0.45) }
    public static var glass: Color { Color(hex: palette.glass, opacity: 0.75) }
    public static var glassSolid: Color { Color(hex: palette.glass, opacity: 0.88) }
    public static var glassLight: Color { Color(hex: palette.glass, opacity: 0.45) }
    public static var glyph: Color { Color(hex: palette.glyph) }
    public static var success: Color { Color(hex: palette.success) }
    public static let danger = Color(hex: 0xFF6B6B)
    public static let untested = Color(hex: 0xE8B65C)
    public static var focusGlow: Color { focus.opacity(0.35) }
    public static var focusGlowStrong: Color { focus.opacity(0.55) }

    public static var baseGradient: AnyShapeStyle {
        let stops = palette.base.stops.map {
            Gradient.Stop(color: Color(hex: $0.color), location: $0.location)
        }
        switch palette.base.kind {
        case .linear:
            return AnyShapeStyle(LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom))
        case .radial:
            return AnyShapeStyle(RadialGradient(
                gradient: Gradient(stops: stops), center: UnitPoint(x: 0.5, y: 0.2),
                startRadius: 0, endRadius: 900))
        }
    }

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
    public static func cubicOut(_ duration: Double) -> Animation {
        .timingCurve(0.215, 0.61, 0.355, 1, duration: duration)
    }
    public static func sineInOut(_ duration: Double) -> Animation {
        .timingCurve(0.445, 0.05, 0.55, 0.95, duration: duration)
    }
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

private struct SeleneRowFocusModifier: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    let focused: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(2))
                    .opacity(focused ? 1 : 0)
            }
            .animation(SeleneTheme.focusIn, value: focused)
    }
}

public extension View {
    /// Selene focus language for rows and cards: a 2u focus border at the
    /// element's own corner radius (in points, already scaled by the caller).
    func seleneRowFocus(_ focused: Bool, radius: CGFloat = SeleneTheme.rowRadius) -> some View {
        modifier(SeleneRowFocusModifier(focused: focused, radius: radius))
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

private struct SeleneShowButtonHintsKey: EnvironmentKey {
    static let defaultValue = true
}

private struct SeleneButtonNamesKey: EnvironmentKey {
    static let defaultValue = ButtonNameStyle.automatic
}

public extension EnvironmentValues {
    var seleneShowButtonHints: Bool {
        get { self[SeleneShowButtonHintsKey.self] }
        set { self[SeleneShowButtonHintsKey.self] = newValue }
    }
    var seleneButtonNames: ButtonNameStyle {
        get { self[SeleneButtonNamesKey.self] }
        set { self[SeleneButtonNamesKey.self] = newValue }
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
