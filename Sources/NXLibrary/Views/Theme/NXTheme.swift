import SwiftUI

public enum NXTheme {
    // MARK: - Coral / Switch-inspired Light Palette
    public static let primary = Color(red: 0.878, green: 0.204, blue: 0.259)   // #E03442
    public static let secondary = Color(red: 0.055, green: 0.498, blue: 0.659) // #0E7FA8
    public static let tertiary = Color(red: 0.122, green: 0.620, blue: 0.360)  // #1F9E5C
    public static let canvasObsidian = Color(red: 0.949, green: 0.957, blue: 0.969)
    public static let canvasLift = Color(red: 0.914, green: 0.929, blue: 0.949)
    public static let ambientIndigo = Color(red: 0.45, green: 0.55, blue: 0.95)
    public static let ambientTeal = Color(red: 0.20, green: 0.65, blue: 0.70)

    // MARK: - Light Surfaces
    public static let glassSurface = Color.white
    public static let glassSurfaceElevated = Color(red: 0.980, green: 0.984, blue: 0.992)
    public static let glassSurfaceActive = Color(red: 0.914, green: 0.929, blue: 0.953)
    public static let borderSubtle = Color(red: 0.827, green: 0.851, blue: 0.886)
    public static let surfaceFill = Color(red: 0.992, green: 0.994, blue: 0.998).opacity(0.96)

    // MARK: - Typography Colors
    public static let textPrimary = Color(red: 0.118, green: 0.137, blue: 0.169)
    public static let textSecondary = Color(red: 0.345, green: 0.384, blue: 0.443)
    public static let textMuted = Color(red: 0.529, green: 0.565, blue: 0.624)

    // MARK: - Semantic Colors
    public static let success = Color(red: 0.122, green: 0.620, blue: 0.360)
    public static let warning = Color(red: 0.760, green: 0.435, blue: 0.000)
    public static let error = Color(red: 0.851, green: 0.204, blue: 0.220)

    // MARK: - Gradients
    public static let primaryGradient = LinearGradient(
        colors: [primary, Color(red: 0.78, green: 0.16, blue: 0.22)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let surfaceGradient = LinearGradient(
        colors: [
            Color.white,
            Color(red: 0.965, green: 0.973, blue: 0.984)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let barGradient = LinearGradient(
        colors: [
            Color(red: 0.992, green: 0.994, blue: 1.000).opacity(0.94),
            Color(red: 0.949, green: 0.957, blue: 0.973).opacity(0.96)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    public static let cardShadow = Color(red: 0.12, green: 0.16, blue: 0.25).opacity(0.12)

    public static let logoGradient = LinearGradient(
        colors: [primary, warning],
        startPoint: .leading,
        endPoint: .trailing
    )

    public static let specularRim = LinearGradient(
        colors: [
            Color.white.opacity(0.95),
            Color(red: 0.78, green: 0.81, blue: 0.86).opacity(0.80),
            Color.black.opacity(0.03)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let selectedBorder = LinearGradient(
        colors: [primary, secondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let specularRimHover = LinearGradient(
        colors: [
            secondary.opacity(0.50),
            primary.opacity(0.25),
            Color.white.opacity(0.40)
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

public struct NXDangerButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(NXTheme.error)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(NXTheme.error.opacity(configuration.isPressed ? 0.16 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(NXTheme.error.opacity(0.30), lineWidth: 0.8)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
            .nxNoFocusRing()
    }
}
