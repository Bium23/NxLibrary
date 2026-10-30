import SwiftUI
import NXLibraryCore

/// A game's art while it ports (`PortingTileLook`): black and white, colour rising
/// from the bottom with the progress and a thin luminous line on its edge. Before
/// the shaders compile, a thin "k/n" bar with the stage and its step in small type
/// sits on the softly blurred art; then the percentage fades in, small, with a slow
/// pastel sheen. A failed porting with no app keeps the art black and white,
/// lightly blurred, under a lock.
///
/// The art is drawn once: a grey layer in `.saturation` blend takes the colour out
/// above the fill line. The sheen moves only while compiling, and stands still
/// with Reduce motion.
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
        case .preparing: return 0.02
        case .locked: return 0.012
        case .normal, .filling: return 0
        }
    }

    /// What sits on the art; animating between them is the slow dissolve.
    private enum Stage: Equatable { case none, steps, percent, lock }

    private var stage: Stage {
        switch look {
        case .normal: return .none
        case .preparing: return .steps
        case .filling: return .percent
        case .locked: return .lock
        }
    }

    /// Only the percentage's sheen moves.
    private var moving: Bool {
        guard !reduceMotion, case .filling = look else { return false }
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
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !moving)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                if stage == .steps, case .preparing(let step, let count, let title, let detail) = look {
                    steps(step: step, count: count, title: title, detail: detail, side: side)
                        .transition(.opacity)
                }
                if stage == .percent, case .filling(let value) = look {
                    percent(value, side: side, phase: moving ? time.truncatingRemainder(dividingBy: 9) / 9 : 0.35)
                        .transition(.opacity)
                }
                if stage == .lock {
                    MaterialIconView(.lock, size: side * 0.22)
                        .foregroundColor(.white.opacity(0.88))
                        .shadow(color: .black.opacity(0.55), radius: side * 0.04)
                        .transition(.opacity)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Before the shaders compile: "k/n" over a thin bar, then the stage and its step
    /// in very small type, on a soft shade so the white reads on any art.
    private func steps(step: Int, count: Int, title: String, detail: String, side: CGFloat) -> some View {
        let width = side * 0.62
        let fraction = count > 0 ? min(max(Double(step) / Double(count), 0), 1) : 0
        return ZStack {
            Color.black.opacity(0.28)
            VStack(spacing: side * 0.035) {
                Text(count > 0 ? "\(step)/\(count)" : "…")
                    .font(.system(size: side * 0.085, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.92))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                    Capsule().fill(Color.white.opacity(0.88))
                        .frame(width: width * fraction)
                }
                .frame(width: width, height: max(1.5, side * 0.014))
                .animation(.easeInOut(duration: 0.6), value: fraction)
                VStack(spacing: side * 0.008) {
                    Text(title)
                        .font(.system(size: side * 0.06, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: side * 0.05))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: side * 0.84)
                .animation(.easeInOut(duration: 0.4), value: title)
            }
            .shadow(color: .black.opacity(0.45), radius: side * 0.02)
        }
    }

    /// Soft pastels, never vivid; the blue kept faint: pink, peach, butter, mint, mist, lavender.
    private static let pastels: [Color] = [0xF4CFDA, 0xF6E0C8, 0xF3EECB, 0xD3EBDD, 0xD8E6F2, 0xE2DAF2]
        .map { Color(hex: $0) }

    /// The percentage, small and centred: solid white with a faint pastel sheen
    /// drifting slowly across it.
    private func percent(_ value: Double, side: CGFloat, phase: Double) -> some View {
        let text = Text("\(Int((value * 100).rounded(.down)))%")
            .font(.system(size: side * 0.115, weight: .semibold, design: .rounded))
            .monospacedDigit()
        let stops = [Color.white] + Self.pastels + [Color.white]
        let shift = CGFloat(phase) * 3 - 1.5
        return text
            .foregroundColor(.white)
            .overlay(
                LinearGradient(colors: stops,
                               startPoint: UnitPoint(x: -0.5 + shift, y: 0.3),
                               endPoint: UnitPoint(x: 1.5 + shift, y: 0.7))
                    .mask(text)
                    .opacity(0.55)
            )
            .padding(.horizontal, side * 0.05)
            .padding(.vertical, side * 0.02)
            .background(Capsule().fill(Color.black.opacity(0.32)))
            .shadow(color: .black.opacity(0.35), radius: side * 0.03)
    }
}

extension View {
    func portingLook(_ look: PortingTileLook, cornerRadius: CGFloat) -> some View {
        modifier(PortingArtLook(look: look, cornerRadius: cornerRadius))
    }
}
