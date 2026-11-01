import SwiftUI

/// Vector Nintendo Switch console icon adapted from open vector SVG:
/// two Joy-Con halves with minus/plus symbols and asymmetrical thumbsticks.
struct SwitchPlatformIcon: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let s = side / 48.0
            let strokeWidth = max(1.4, 2.4 * s)

            ZStack {
                // Left Joy-Con outline
                Path { path in
                    path.move(to: CGPoint(x: 6 * s, y: 12 * s))
                    path.addCurve(to: CGPoint(x: 14 * s, y: 4 * s),
                                  control1: CGPoint(x: 6 * s, y: 7.58172 * s),
                                  control2: CGPoint(x: 9.58172 * s, y: 4 * s))
                    path.addLine(to: CGPoint(x: 19 * s, y: 4 * s))
                    path.addCurve(to: CGPoint(x: 21 * s, y: 6 * s),
                                  control1: CGPoint(x: 20.1046 * s, y: 4 * s),
                                  control2: CGPoint(x: 21 * s, y: 4.89543 * s))
                    path.addLine(to: CGPoint(x: 21 * s, y: 40 * s))
                    path.addCurve(to: CGPoint(x: 19 * s, y: 42 * s),
                                  control1: CGPoint(x: 21 * s, y: 41.1046 * s),
                                  control2: CGPoint(x: 20.1046 * s, y: 42 * s))
                    path.addLine(to: CGPoint(x: 14 * s, y: 42 * s))
                    path.addCurve(to: CGPoint(x: 6 * s, y: 34 * s),
                                  control1: CGPoint(x: 9.58172 * s, y: 42 * s),
                                  control2: CGPoint(x: 6 * s, y: 38.4183 * s))
                    path.closeSubpath()
                }
                .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))

                // Right Joy-Con outline
                Path { path in
                    path.move(to: CGPoint(x: 42 * s, y: 14 * s))
                    path.addCurve(to: CGPoint(x: 34 * s, y: 6 * s),
                                  control1: CGPoint(x: 42 * s, y: 9.58172 * s),
                                  control2: CGPoint(x: 38.4183 * s, y: 6 * s))
                    path.addLine(to: CGPoint(x: 28 * s, y: 6 * s))
                    path.addCurve(to: CGPoint(x: 26 * s, y: 8 * s),
                                  control1: CGPoint(x: 26.8954 * s, y: 6 * s),
                                  control2: CGPoint(x: 26 * s, y: 6.89543 * s))
                    path.addLine(to: CGPoint(x: 26 * s, y: 42 * s))
                    path.addCurve(to: CGPoint(x: 28 * s, y: 44 * s),
                                  control1: CGPoint(x: 26 * s, y: 43.1046 * s),
                                  control2: CGPoint(x: 26.8954 * s, y: 44 * s))
                    path.addLine(to: CGPoint(x: 34 * s, y: 44 * s))
                    path.addCurve(to: CGPoint(x: 42 * s, y: 36 * s),
                                  control1: CGPoint(x: 38.4183 * s, y: 44 * s),
                                  control2: CGPoint(x: 42 * s, y: 40.4183 * s))
                    path.closeSubpath()
                }
                .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))

                // Left thumbstick
                Path { path in
                    path.addEllipse(in: CGRect(x: 11 * s, y: 30 * s, width: 5 * s, height: 5 * s))
                }
                .fill()

                // Right thumbstick
                Path { path in
                    path.addEllipse(in: CGRect(x: 31.5 * s, y: 14 * s, width: 5 * s, height: 5 * s))
                }
                .fill()

                // Minus sign (-)
                Path { path in
                    path.move(to: CGPoint(x: 12 * s, y: 17 * s))
                    path.addLine(to: CGPoint(x: 15 * s, y: 17 * s))
                }
                .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))

                // Plus sign (+)
                Path { path in
                    path.move(to: CGPoint(x: 34 * s, y: 28 * s))
                    path.addLine(to: CGPoint(x: 34 * s, y: 34 * s))
                    path.move(to: CGPoint(x: 31 * s, y: 31 * s))
                    path.addLine(to: CGPoint(x: 37 * s, y: 31 * s))
                }
                .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

