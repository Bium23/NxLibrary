import SwiftUI
import CoreText
import NXLibraryCore

enum SeleneFonts {
    private static var registered = false

    /// Registers the bundled Material Icons font for this process. Idempotent.
    static func register() {
        guard !registered else { return }
        registered = true
        guard let url = Bundle.main.url(forResource: "MaterialIcons-Regular",
                                        withExtension: "ttf",
                                        subdirectory: "Selene/Fonts") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

/// Centres an icon on the capitals of the text beside it, in a `.firstTextBaseline` row. A Material Icons glyph's
/// line box is its em square standing on the baseline, its ink centred in it, so baseline alignment alone leaves it
/// higher than the words: the capitals of 21-point semibold text are centred 7.4 points up, the icon 11 points up.
struct IconOnCaps: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneMinimumFont) private var minimum
    /// The text's size in canvas units and weight, as given to `seleneFont`.
    let size: CGFloat
    let weight: NSFont.Weight

    func body(content: Content) -> some View {
        let caps = NSFont.systemFont(ofSize: max(minimum, canvas.u(size)), weight: weight).capHeight
        return content.alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + caps / 2 }
    }
}

extension View {
    /// See `IconOnCaps`.
    func iconOnCaps(of size: CGFloat, _ weight: NSFont.Weight) -> some View {
        modifier(IconOnCaps(size: size, weight: weight))
    }
}

/// A Material Icons glyph sized in Selene canvas units.
struct MaterialIconView: View {
    @Environment(\.seleneCanvas) private var canvas
    let icon: MaterialIcon
    let size: CGFloat

    init(_ icon: MaterialIcon, size: CGFloat) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        Text(icon.rawValue)
            .font(.custom(MaterialIcon.fontName, fixedSize: canvas.u(size)))
            .accessibilityHidden(true)
    }
}
