import SwiftUI
import AppKit
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
    /// `description` is About this game with the column beside it; `about` and
    /// `column` are its two sides.
    case head, genres, strip, description, about, column, more
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

/// The store description under the screenshots, at least as tall as the
/// column beside it (`excerpt`), with Read more for the rest. Read more takes
/// controller focus left of Build & Sources.
struct SpotlightDescription: View {
    @Environment(\.seleneCanvas) private var canvas
    let text: String
    let excerpt: DescriptionExcerpt
    let expanded: Bool
    let focused: Bool
    let onToggle: () -> Void

    static let width: CGFloat = 1100

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailsBandTitle(text: "About this game")
            Text(text.isEmpty ? "No description for this game yet." : (expanded ? text : excerpt.text))
                .seleneFont(17)
                .lineSpacing(canvas.u(3))
                .foregroundColor(text.isEmpty ? SeleneTheme.ink60 : SeleneTheme.ink90)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            if excerpt.truncated {
                Button(expanded ? "Show less" : "Read more", action: onToggle)
                    .buttonStyle(.plain)
                    .seleneFont(15, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                    .padding(.horizontal, canvas.u(14))
                    .padding(.vertical, canvas.u(5))
                    .background(Capsule().fill(SeleneTheme.ink15))
                    .seleneRowFocus(focused, radius: canvas.u(15))
                    .padding(.top, canvas.u(12))
            }
        }
        .frame(width: canvas.u(Self.width), alignment: .leading)
        .shadow(color: .black.opacity(0.45), radius: canvas.u(4))
    }

    /// The cut that reaches at least `columnHeight` (the column beside it, title
    /// included), estimated from the text's font at this width; four lines before
    /// the column is measured.
    static func excerpt(_ text: String, columnHeight: CGFloat, canvas: SeleneCanvas) -> DescriptionExcerpt {
        let layout = NSLayoutManager()
        let body = NSFont.systemFont(ofSize: canvas.u(17))
        let line = layout.defaultLineHeight(for: body) + canvas.u(3)
        let title = layout.defaultLineHeight(for: .systemFont(ofSize: canvas.u(21), weight: .semibold)) + canvas.u(16)
        let lines = columnHeight > 0 ? Int(((columnHeight - title) / line).rounded(.up)) : 4
        let sample = "Travel across vast fields, through forests, and to mountain peaks as you discover"
        let average = (sample as NSString).size(withAttributes: [.font: body]).width / CGFloat(sample.count)
        let perLine = Int(canvas.u(width) / max(average, 1))
        return DescriptionExcerpt.make(text, minLines: max(lines, 4), charsPerLine: perLine)
    }
}

/// A small, faint chevron at the window's top centre: there is more above.
struct SpotlightUpHint: View {
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: canvas.u(9)))
            path.addLine(to: CGPoint(x: canvas.u(14), y: 0))
            path.addLine(to: CGPoint(x: canvas.u(28), y: canvas.u(9)))
        }
        .stroke(SeleneTheme.ink.opacity(0.45),
                style: StrokeStyle(lineWidth: max(1, canvas.u(2)), lineCap: .round, lineJoin: .round))
        .frame(width: canvas.u(28), height: canvas.u(9))
        .shadow(color: .black.opacity(0.4), radius: canvas.u(3))
        .accessibilityHidden(true)
    }
}
