import SwiftUI
import NXLibraryCore

/// Selene's at-a-glance stats line: PLAYTIME · LAST PLAYED · PLATFORM · RELEASED.
/// Shared by Spotlight (left aligned) and Collection (centered); the caller places it.
struct SeleneStatsRow: View {
    @Environment(\.seleneCanvas) private var canvas

    let presentation: LibraryPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            stat("PLAYTIME") { value(presentation.playtime) }
            divider
            stat("LAST PLAYED") { value(presentation.lastPlayed) }
            divider
            stat("PLATFORM") {
                HStack(spacing: canvas.u(9)) {
                    MaterialIconView(.platform, size: 21)
                        .foregroundColor(SeleneTheme.ink)
                        .frame(width: canvas.u(22), height: canvas.u(22))
                    value("Nintendo Switch")
                }
            }
            if let year = presentation.releaseYear {
                divider
                stat("RELEASED") { value(year) }
            }
        }
        .fixedSize()
        .shadow(color: .black.opacity(0.45), radius: canvas.u(4))
    }

    private func stat<V: View>(_ label: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(2)) {
            // Line boxes of Selene's Segoe UI 12 / 21 (16 and 28), so the strip lands 34 below.
            Text(label)
                .seleneFont(12, .semibold)
                .foregroundColor(SeleneTheme.ink60)
                .frame(height: canvas.u(16), alignment: .leading)
            content()
                .frame(minHeight: canvas.u(28))
        }
        .accessibilityElement(children: .combine)
    }

    private func value(_ text: String) -> some View {
        Text(text).seleneFont(21, .semibold).foregroundColor(SeleneTheme.ink)
    }

    /// 1u ink25 rule, 26 either side, inset 4 top and bottom.
    private var divider: some View {
        Rectangle()
            .fill(SeleneTheme.ink25)
            .frame(width: max(1, canvas.u(1)))
            .padding(.vertical, canvas.u(4))
            .padding(.horizontal, canvas.u(26))
    }
}
