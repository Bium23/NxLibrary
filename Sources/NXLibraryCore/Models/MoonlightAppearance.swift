import Foundation

public enum MoonlightParticleStyle: String, Codable, CaseIterable, Sendable {
    case soft, crystal

    public var title: String { L10n.text(self == .soft ? "Particle style: Soft" : "Crystal dust") }
}

/// Arcane's slow spatial colour field. The Metal shader takes its constants
/// from here; the static fallback samples the same field without a timer.
public enum MoonlightChromatics {
    public static let period: Float = 25
    public static let intensity: Float = 0.5
    public static let colors: [SIMD3<Float>] = [
        SIMD3(92, 174, 255), SIMD3(171, 120, 244), SIMD3(236, 133, 172),
        SIMD3(253, 203, 150), SIMD3(106, 208, 230)
    ].map { $0 / 255 }

    public static func sample(x: Float, y: Float, time: Float, offset: Float = 0) -> SIMD3<Float> {
        let phase = time / period + x * 0.19 + y * 0.11 + offset
        let position = (phase - floor(phase)) * Float(colors.count)
        let index = min(Int(position), colors.count - 1)
        let fraction = position - floor(position)
        let eased = fraction * fraction * (3 - 2 * fraction)
        return colors[index] + (colors[(index + 1) % colors.count] - colors[index]) * eased
    }
}
