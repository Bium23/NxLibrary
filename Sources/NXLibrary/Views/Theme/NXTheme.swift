import SwiftUI

public enum NXTheme {
    // MARK: - Coral / Graphite Palette
    public static let primary = Color(red: 1.00, green: 0.35, blue: 0.37)   // coral
    public static let secondary = Color(red: 0.35, green: 0.78, blue: 0.98) // cyan selection
    public static let tertiary = Color(red: 0.20, green: 0.78, blue: 0.35)  // green
    public static let canvasObsidian = Color(red: 0.082, green: 0.082, blue: 0.090)
    
    // MARK: - Glass Surfaces
    public static let glassSurface = Color(red: 0.118, green: 0.118, blue: 0.133)
    public static let glassSurfaceElevated = Color(red: 0.165, green: 0.165, blue: 0.188)
    public static let glassSurfaceActive = Color(red: 0.215, green: 0.215, blue: 0.245)
    public static let borderSubtle = Color(red: 0.22, green: 0.22, blue: 0.25)
    
    // MARK: - Typography Colors
    public static let textPrimary = Color.white
    public static let textSecondary = Color(red: 0.63, green: 0.63, blue: 0.67)
    public static let textMuted = Color(red: 0.38, green: 0.38, blue: 0.42)
    
    // MARK: - Semantic Colors
    public static let success = Color(red: 0.20, green: 0.78, blue: 0.35)
    public static let warning = Color(red: 1.00, green: 0.62, blue: 0.04)
    public static let error = Color(red: 1.00, green: 0.27, blue: 0.23)
    
    // MARK: - Gradients
    public static let primaryGradient = LinearGradient(
        colors: [primary, Color(red: 0.91, green: 0.22, blue: 0.25)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
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
