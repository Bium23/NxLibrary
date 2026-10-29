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

    func body(content: Content) -> some View {
        content.font(.system(size: canvas.u(size), weight: weight))
    }
}

private struct SeleneCanvasRoot: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .environment(\.seleneCanvas, SeleneCanvas(size: proxy.size))
        }
    }
}

public extension View {
    /// System font sized in Selene canvas units.
    func seleneFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        modifier(SeleneFontModifier(size: size, weight: weight))
    }

    /// Measures the available space and publishes it as `seleneCanvas`.
    func seleneCanvasRoot() -> some View {
        modifier(SeleneCanvasRoot())
    }
}
