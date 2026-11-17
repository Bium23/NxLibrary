import Foundation

public enum MoonlightSurface: String, Sendable {
    case classic, arcane, flow
}

/// Fixed local hues, with only a small drift over three minutes.
public enum MoonlightChromatics {
    public static let period: Float = 180
    public static let intensity: Float = 0.5
    public static let colors: [SIMD3<Float>] = [SIMD3(187,91,179), SIMD3(92,181,228), SIMD3(103,92,165)].map { $0 / 255 }

    public static func sample(x: Float, y: Float, time: Float, offset: Float = 0) -> SIMD3<Float> {
        let phase = time / period * 2 * Float.pi
        let pinkWeight = exp(-pow((x - 0.18) / 0.42, 2) - pow((y - 0.77) / 0.5, 2))
        let cyanWeight = exp(-pow((x - 0.84) / 0.42, 2) - pow((y - 0.43) / 0.5, 2))
        let drift = SIMD3<Float>(2.5 * sin(phase), 1.8 * sin(phase + 1), 2.6 * sin(phase + 2)) / 255
        return (colors[0] * pinkWeight + colors[1] * cyanWeight + colors[2] * 0.25) / (pinkWeight + cyanWeight + 0.25) + drift
    }
}
