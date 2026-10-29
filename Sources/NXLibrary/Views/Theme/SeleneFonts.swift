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
