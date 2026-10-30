import SwiftUI
import NXLibraryCore

/// A game's art while it ports (`PortingTileLook`): black and white, colour rising
/// from the bottom with the progress and a thin luminous line on its edge; before
/// the shaders a soft ring turns over the blurred art with "k/n", then the
/// percentage fades in with a pastel sheen. A failed porting with no app keeps the
/// art black and white, lightly blurred, under a lock.
///
/// The art is drawn once: a grey layer in `.saturation` blend takes the colour out
/// above the fill line. The ring and the sheen move only while porting, and stand
/// still with Reduce motion.
struct PortingArtLook: ViewModifier {
    let look: PortingTileLook
    let cornerRadius: CGFloat

    @Environment(\.seleneReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                ZStack(alignment: .top) {
                    content
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: side * blur, opaque: true)
                    Rectangle()
                        .fill(Color(white: 0.5))
                        .frame(height: geo.size.height * (1 - fill))
                        .blendMode(.saturation)
                }
                .compositingGroup()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                if fill > 0, fill < 1 {
                    edge(width: geo.size.width, side: side)
                        .offset(y: geo.size.height * (0.5 - fill))
                }
                overlay(side: side)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeInOut(duration: 0.9), value: fill)
        .animation(.easeInOut(duration: 0.8), value: stage)
    }

    // MARK: - Look

    private var fill: Double {
        switch look {
        case .normal: return 1
        case .preparing, .locked: return 0
        case .filling(let value): return min(max(value, 0), 1)
        }
    }

    /// Blur as a fraction of the side.
    private var blur: CGFloat {
        switch look {
        case .preparing: return 0.03
        case .locked: return 0.012
        case .normal, .filling: return 0
        }
    }

    /// What sits on the art; animating between them is the slow dissolve.
    private enum Stage: Equatable { case none, ring, percent, lock }

    private var stage: Stage {
        switch look {
        case .normal: return .none
        case .preparing: return .ring
        case .filling: return .percent
        case .locked: return .lock
        }
    }

    private var moving: Bool {
        guard !reduceMotion else { return false }
        if case .normal = look { return false }
        if case .locked = look { return false }
        return true
    }

    private func edge(width: CGFloat, side: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.85))
            .frame(width: width, height: max(1, side * 0.008))
            .shadow(color: Color.white.opacity(0.7), radius: side * 0.025)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func overlay(side: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                if stage == .ring, case .preparing(let step, let count) = look {
                    ring(side: side, angle: moving ? time.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360 : 0)
                    Text(count > 0 ? "\(step)/\(count)" : "…")
                        .font(.system(size: side * 0.15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.5), radius: side * 0.03)
                        .transition(.opacity)
                }
                if stage == .percent, case .filling(let value) = look {
                    percent(value, side: side, phase: moving ? time.truncatingRemainder(dividingBy: 3.2) / 3.2 : 0.3)
                        .transition(.opacity)
                }
                if stage == .lock {
                    MaterialIconView(.lock, size: side * 0.24)
                        .foregroundColor(.white.opacity(0.88))
                        .shadow(color: .black.opacity(0.55), radius: side * 0.04)
                        .transition(.opacity)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// A soft black-and-white ring, brighter at its head.
    private func ring(side: CGFloat, angle: Double) -> some View {
        let diameter = side * 0.56
        let width = max(1.5, side * 0.022)
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: width)
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(AngularGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.9)],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(260)),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(angle))
        }
        .frame(width: diameter, height: diameter)
        .blur(radius: side * 0.006)
        .shadow(color: .black.opacity(0.35), radius: side * 0.03)
        .transition(.opacity)
    }

    /// Soft pastels, never vivid: pink, peach, butter, mint, sky, lavender.
    private static let pastels: [Color] = [0xF6C1D1, 0xF9D9B5, 0xF6EFB0, 0xC4EBD3, 0xBFDDF7, 0xD9CBF5]
        .map { Color(hex: $0) }

    /// The percentage, small and centred, with a pastel sheen sweeping across it.
    private func percent(_ value: Double, side: CGFloat, phase: Double) -> some View {
        let text = Text("\(Int((value * 100).rounded(.down)))%")
            .font(.system(size: side * 0.15, weight: .semibold, design: .rounded))
            .monospacedDigit()
        let stops = [Color.white] + Self.pastels + [Color.white] + Self.pastels + [Color.white]
        let shift = CGFloat(phase) * 2 - 1
        return text
            .foregroundColor(.white)
            .overlay(
                LinearGradient(colors: stops,
                               startPoint: UnitPoint(x: -1 + shift, y: 0.2),
                               endPoint: UnitPoint(x: 2 + shift, y: 0.8))
                    .mask(text)
                    .opacity(0.9)
            )
            .shadow(color: .black.opacity(0.55), radius: side * 0.035)
    }
}

extension View {
    func portingLook(_ look: PortingTileLook, cornerRadius: CGFloat) -> some View {
        modifier(PortingArtLook(look: look, cornerRadius: cornerRadius))
    }
}
