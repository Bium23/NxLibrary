import SwiftUI

public enum NXTheme {
    // MARK: - Coral / Midnight Palette
    public static let primary = Color(red: 1.00, green: 0.36, blue: 0.41)   // coral
    public static let secondary = Color(red: 0.36, green: 0.80, blue: 0.98) // cyan selection
    public static let tertiary = Color(red: 0.23, green: 0.80, blue: 0.48)  // green
    public static let canvasObsidian = Color(red: 0.035, green: 0.045, blue: 0.075)
    public static let canvasLift = Color(red: 0.075, green: 0.095, blue: 0.145)
    public static let ambientIndigo = Color(red: 0.38, green: 0.30, blue: 0.95)
    public static let ambientTeal = Color(red: 0.12, green: 0.55, blue: 0.62)

    // MARK: - Tinted Surfaces
    public static let glassSurface = Color(red: 0.090, green: 0.112, blue: 0.165)
    public static let glassSurfaceElevated = Color(red: 0.125, green: 0.152, blue: 0.215)
    public static let glassSurfaceActive = Color(red: 0.175, green: 0.210, blue: 0.290)
    public static let borderSubtle = Color(red: 0.230, green: 0.270, blue: 0.360)
    public static let surfaceFill = Color(red: 0.090, green: 0.112, blue: 0.165).opacity(0.92)

    // MARK: - Typography Colors
    public static let textPrimary = Color(red: 0.965, green: 0.955, blue: 0.935)
    public static let textSecondary = Color(red: 0.680, green: 0.730, blue: 0.810)
    public static let textMuted = Color(red: 0.460, green: 0.510, blue: 0.610)

    // MARK: - Semantic Colors
    public static let success = Color(red: 0.25, green: 0.82, blue: 0.52)
    public static let warning = Color(red: 1.00, green: 0.70, blue: 0.20)
    public static let error = Color(red: 1.00, green: 0.32, blue: 0.32)

    // MARK: - Gradients
    public static let primaryGradient = LinearGradient(
        colors: [primary, Color(red: 0.86, green: 0.23, blue: 0.35)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let surfaceGradient = LinearGradient(
        colors: [
            Color(red: 0.160, green: 0.195, blue: 0.270),
            Color(red: 0.075, green: 0.095, blue: 0.155)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let barGradient = LinearGradient(
        colors: [
            Color(red: 0.082, green: 0.102, blue: 0.153).opacity(0.86),
            Color(red: 0.043, green: 0.055, blue: 0.086).opacity(0.94)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    public static let cardShadow = Color(red: 0.005, green: 0.010, blue: 0.030).opacity(0.55)

    public static let logoGradient = LinearGradient(
        colors: [primary, warning],
        startPoint: .leading,
        endPoint: .trailing
    )

    public static let specularRim = LinearGradient(
        colors: [
            Color.white.opacity(0.18),
            Color.white.opacity(0.06),
            Color.white.opacity(0.02)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let selectedBorder = LinearGradient(
        colors: [secondary, primary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let specularRimHover = LinearGradient(
        colors: [
            secondary.opacity(0.6),
            primary.opacity(0.3),
            Color.white.opacity(0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

public extension Color {
    static let nxPrimary = NXTheme.primary
    static let nxSecondary = NXTheme.secondary
    static let nxTertiary = NXTheme.tertiary
    static let nxCanvas = NXTheme.canvasObsidian
    static let nxSurface = NXTheme.glassSurface
    static let nxSurfaceElevated = NXTheme.glassSurfaceElevated
    static let nxBorder = NXTheme.borderSubtle
    static let nxTextPrimary = NXTheme.textPrimary
    static let nxTextSecondary = NXTheme.textSecondary
    static let nxTextMuted = NXTheme.textMuted
}

public extension View {
    /// Removes macOS system blue selection / focus ring around buttons and controls
    @ViewBuilder
    func nxNoFocusRing() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
                .focusable(false)
        } else {
            self.focusable(false)
        }
    }
}

// MARK: - Button Styles
public struct NXPrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NXTheme.primaryGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(configuration.isPressed ? 0.4 : 0.2), lineWidth: 1)
            )
            .shadow(color: NXTheme.primary.opacity(configuration.isPressed ? 0.2 : 0.45), radius: 8, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
            .nxNoFocusRing()
    }
}

public struct NXSecondaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(NXTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? NXTheme.glassSurfaceActive : NXTheme.glassSurfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(NXTheme.specularRim, lineWidth: 0.8)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
            .nxNoFocusRing()
    }
}

public struct NXAccentButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(NXTheme.tertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8)
            )
            .shadow(color: NXTheme.tertiary.opacity(0.4), radius: 6, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
            .nxNoFocusRing()
    }
}
