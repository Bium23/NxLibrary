import SwiftUI
import NXLibraryCore

struct SeleneOptionRow<Trailing: View>: View {
    @Environment(\.seleneCanvas) private var canvas

    let icon: MaterialIcon?
    let title: String
    let about: String?
    let focused: Bool
    var destructive = false
    /// False draws the row dim (ink60 text and icon), as Selene's disabled pills do. It still takes focus.
    var enabled = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: canvas.u(18)) {
            if let icon {
                MaterialIconView(icon, size: 24)
                    .foregroundColor(destructive ? SeleneTheme.danger : (enabled ? SeleneTheme.glyph : SeleneTheme.ink60))
            }
            VStack(alignment: .leading, spacing: canvas.u(3)) {
                Text(title)
                    .seleneFont(21, .medium)
                    .foregroundColor(destructive ? SeleneTheme.danger : (enabled ? SeleneTheme.ink : SeleneTheme.ink60))
                if let about {
                    Text(about)
                        .seleneFont(15)
                        .foregroundColor(SeleneTheme.ink60)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: canvas.u(16))
            trailing()
        }
        .padding(.leading, canvas.u(26))
        .padding(.top, canvas.u(18))
        .padding(.trailing, canvas.u(24))
        .padding(.bottom, canvas.u(18))
        .background(RoundedRectangle(cornerRadius: canvas.u(16), style: .continuous).fill(SeleneTheme.glass))
        .seleneRowFocus(focused, radius: canvas.u(16))
    }
}
