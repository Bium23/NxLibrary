import SwiftUI

public enum SeleneTheme {
    public static let canvas = Color(hex: 0x05070A)
    public static let canvasRaised = Color(hex: 0x0B0E13)
    public static let surface = Color(hex: 0x14181F)
    public static let surfaceHover = Color(hex: 0x1B2029)
    public static let border = Color(hex: 0x262C36)
    public static let borderStrong = Color(hex: 0x3A424F)
    public static let ink = Color(hex: 0xF4F6F8)
    public static let inkSecondary = Color(hex: 0xB6BEC9)
    public static let inkMuted = Color(hex: 0x8C96A3)
    public static let accent = Color(hex: 0x9CCBFF)
    public static let focus = Color.white
    public static let success = Color(hex: 0x3DDC84)
    public static let warning = Color(hex: 0xE8B65C)
    public static let danger = Color(hex: 0xFF6B6B)

    public static let rowRadius: CGFloat = 11
    public static let cardRadius: CGFloat = 12
    public static let coverRadius: CGFloat = 5
    public static let quick = Animation.easeOut(duration: 0.18)
    public static let standard = Animation.easeOut(duration: 0.24)

    public static let heroLeftScrim = LinearGradient(
        colors: [.black.opacity(0.95), .black.opacity(0.80), .black.opacity(0.30), .clear],
        startPoint: .leading, endPoint: .trailing
    )
    public static let heroBottomScrim = LinearGradient(
        colors: [.black.opacity(0.99), .black.opacity(0.88), .black.opacity(0.22), .clear],
        startPoint: .bottom, endPoint: .top
    )
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
