import SwiftUI
import NXLibraryCore

private struct SeleneCanvasKey: EnvironmentKey {
    static let defaultValue = SeleneCanvas(size: SeleneCanvas.design)
}

public extension EnvironmentValues {
    var seleneCanvas: SeleneCanvas {
        get { self[SeleneCanvasKey.self] }
        set { self[SeleneCanvasKey.self] = newValue }
    }
}

private struct SeleneFontModifier: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    let size: CGFloat
    let weight: Font.Weight
    var design: Font.Design = .default

    func body(content: Content) -> some View {
        content.font(.system(size: canvas.u(size), weight: weight, design: design))
    }
}

private struct SeleneCanvasRoot: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .environment(\.seleneCanvas, SeleneCanvas(size: proxy.size))
        }
        // Full bleed under the hidden title bar: windowed looks like full screen.
        .ignoresSafeArea()
    }
}

public extension View {
    /// System font sized in Selene canvas units.
    func seleneFont(_ size: CGFloat, _ weight: Font.Weight = .regular,
                    design: Font.Design = .default) -> some View {
        modifier(SeleneFontModifier(size: size, weight: weight, design: design))
    }

    /// Measures the available space and publishes it as `seleneCanvas`.
    func seleneCanvasRoot() -> some View {
        modifier(SeleneCanvasRoot())
    }
}
