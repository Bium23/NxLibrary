import SwiftUI
import NXLibraryCore

struct SeleneValueChip: View {
    @Environment(\.seleneCanvas) private var canvas
    let text: String

    var body: some View {
        Text(text)
            .seleneFont(17, .semibold)
            .foregroundColor(SeleneTheme.ink)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, canvas.u(16))
            .padding(.trailing, canvas.u(16))
            .padding(.top, canvas.u(4))
            .padding(.bottom, canvas.u(5))
            .background(RoundedRectangle(cornerRadius: canvas.u(17), style: .continuous)
                .fill(SeleneTheme.ink.opacity(0.13)))
    }
}
