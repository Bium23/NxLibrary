import SwiftUI
import NXLibraryCore

/// What Spotlight's page needs below the stats: the game's details,
/// Build & Sources' actions and More like this.
struct SpotlightPageModel {
    let presentation: GameDetailPresentation
    let rows: [BuildSourcesRow]
    let more: [PortedGame]
    /// The Metal gate refuses new builds.
    let buildBlocked: Bool
}

/// The blocks of Spotlight's game column, top to bottom.
enum SpotlightPageBlock: Hashable {
    case head, genres, strip, description, actions, more
}

/// Each block's height, top padding included. Heights, unlike positions, do
/// not change while the page glides, so the scroll never chases itself.
struct SpotlightBlockKey: PreferenceKey {
    static var defaultValue: [SpotlightPageBlock: CGFloat] = [:]
    static func reduce(value: inout [SpotlightPageBlock: CGFloat], nextValue: () -> [SpotlightPageBlock: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// Reports this view's height (apply after its top padding) under `block`.
    func spotlightBlock(_ block: SpotlightPageBlock) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: SpotlightBlockKey.self, value: [block: proxy.size.height])
        })
    }
}

/// The game's genres as chips (as on Details), under the stats.
struct SpotlightGenreChips: View {
    @Environment(\.seleneCanvas) private var canvas
    let genres: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(genres.prefix(6)), id: \.self) { genre in
                Text(genre)
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink90)
                    .padding(.horizontal, canvas.u(12))
                    .padding(.vertical, canvas.u(4))
                    .background(RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous)
                        .fill(SeleneTheme.ink15))
                    .padding(.trailing, canvas.u(8))
            }
        }
        .padding(.leading, canvas.u(2))
        .shadow(color: .black.opacity(0.45), radius: canvas.u(4))
    }
}

/// The store description under the screenshots. A long one shows whole
/// paragraphs or sentences up to about four lines, with Read more for the rest.
struct SpotlightDescription: View {
    @Environment(\.seleneCanvas) private var canvas
    let text: String
    @State private var expanded = false

    /// About four lines at this width.
    static let excerptLimit = 420

    var body: some View {
        let excerpt = DescriptionExcerpt.make(text, limit: Self.excerptLimit)
        VStack(alignment: .leading, spacing: 0) {
            DetailsBandTitle(text: "About this game")
            Text(text.isEmpty ? "No description for this game yet." : (expanded ? text : excerpt.text))
                .seleneFont(17)
                .lineSpacing(canvas.u(3))
                .foregroundColor(text.isEmpty ? SeleneTheme.ink60 : SeleneTheme.ink90)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            if excerpt.truncated {
                Button(expanded ? "Show less" : "Read more") { expanded.toggle() }
                    .buttonStyle(.plain)
                    .seleneFont(15, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                    .padding(.horizontal, canvas.u(14))
                    .padding(.vertical, canvas.u(5))
                    .background(Capsule().fill(SeleneTheme.ink15))
                    .padding(.top, canvas.u(12))
            }
        }
        .frame(width: canvas.u(1100), alignment: .leading)
        .shadow(color: .black.opacity(0.45), radius: canvas.u(4))
    }
}
