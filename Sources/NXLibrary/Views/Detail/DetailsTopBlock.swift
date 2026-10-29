import SwiftUI
import AppKit
import NXLibraryCore

/// The Details top block (Selene GameDetails `SeleneDetailsTop`): the logo (or
/// the name), the developer line, the Play or Build and Game options pills,
/// the stats row, the genre chips and the description. A 1060-wide column
/// placed at (110, 96) on the stage; every length is in Selene units.
struct DetailsTopBlock: View {
    @Environment(\.seleneCanvas) private var canvas

    let game: PortedGame
    let logo: NSImage?
    let presentation: GameDetailPresentation
    /// The focused pill: 0 Play or Build, 1 Game options; nil when the block has no focus.
    let focusedPill: Int?
    /// Build is dim (no sources to build from) but still takes focus.
    let primaryEnabled: Bool
    /// Description expanded by "Read more" (the page passes wheel scrolling through meanwhile).
    @Binding var expanded: Bool
    let onPrimary: () -> Void
    let onOptions: () -> Void
    let onHoverPill: (Int) -> Void

    /// Longer than this, the description gets a "Read more" (five lines hold about 520 characters at this width).
    static let readMoreThreshold = 520

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logoArea
            if let developer = presentation.developerLine {
                Text(developer)
                    .seleneFont(17)
                    .foregroundColor(SeleneTheme.ink90)
                    .padding(.leading, canvas.u(2))
                    .padding(.top, canvas.u(16))
            }
            pills
                .padding(.top, canvas.u(26))
            stats
                .padding(.top, canvas.u(28))
            if !presentation.genres.isEmpty {
                genres
                    .padding(.top, canvas.u(22))
            }
            description
                .padding(.top, canvas.u(18))
        }
        .frame(width: canvas.u(1060), alignment: .topLeading)
        .shadow(color: .black.opacity(0.45), radius: canvas.u(4))
    }

    // MARK: - Logo

    private var logoArea: some View {
        ZStack(alignment: .bottomLeading) {
            if let logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: canvas.u(680), maxHeight: canvas.u(180), alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.35), radius: canvas.u(8))
            } else {
                Text(game.name)
                    .seleneFont(62)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: canvas.u(1060), alignment: .leading)
            }
        }
        .frame(width: canvas.u(1060), height: canvas.u(180), alignment: .bottomLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.name)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Pills

    private var pills: some View {
        HStack(spacing: canvas.u(14)) {
            SelenePillButton(title: presentation.canPlay ? "Play" : "Build", minWidth: 200, height: 52,
                             horizontalPadding: 36, focused: focusedPill == 0,
                             enabled: primaryEnabled, action: onPrimary)
                .onHover { if $0 { onHoverPill(0) } }
            SelenePillButton(title: "Game options", minWidth: 200, height: 52,
                             horizontalPadding: 36, focused: focusedPill == 1,
                             action: onOptions)
                .onHover { if $0 { onHoverPill(1) } }
        }
    }

    // MARK: - Stats

    /// PLAYTIME · LAST PLAYED · RELEASED · PLATFORM, 28 either side of each rule.
    private var stats: some View {
        var items = [
            SeleneStat.text("PLAYTIME", presentation.playtime),
            SeleneStat.text("LAST PLAYED", presentation.lastPlayed)
        ]
        if let released = presentation.released {
            items.append(SeleneStat.text("RELEASED", released))
        }
        items.append(SeleneStat.platform)
        return SeleneStatsRow(items: items, gap: 28)
            .padding(.leading, canvas.u(4))
    }

    // MARK: - Genres

    private var genres: some View {
        HStack(spacing: 0) {
            ForEach(Array(presentation.genres.prefix(6)), id: \.self) { genre in
                Text(genre)
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink90)
                    .padding(.horizontal, canvas.u(12))
                    .padding(.vertical, canvas.u(4))
                    .background(RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous)
                        .fill(SeleneTheme.ink15))
                    .padding(.trailing, canvas.u(8))
                    .padding(.bottom, canvas.u(8))
            }
        }
        .padding(.leading, canvas.u(2))
    }

    // MARK: - Description

    @ViewBuilder
    private var description: some View {
        let text = presentation.description
        VStack(alignment: .leading, spacing: canvas.u(6)) {
            if text.isEmpty {
                Text("No description for this game yet.")
                    .seleneFont(17)
                    .foregroundColor(SeleneTheme.ink60)
            } else {
                if expanded {
                    ScrollView(.vertical, showsIndicators: false) {
                        descriptionText(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: canvas.u(130))
                } else {
                    descriptionText(text)
                        .lineLimit(5)
                        .frame(maxHeight: canvas.u(130), alignment: .top)
                        .clipped()
                }
                if text.count > Self.readMoreThreshold {
                    Button(expanded ? "Show less" : "Read more") { expanded.toggle() }
                        .buttonStyle(.plain)
                        .seleneFont(15, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                }
            }
        }
        .padding(.leading, canvas.u(2))
        .frame(minWidth: canvas.u(700), maxWidth: canvas.u(1034), alignment: .leading)
    }

    private func descriptionText(_ text: String) -> some View {
        Text(text)
            .seleneFont(17)
            .lineSpacing(canvas.u(3))
            .foregroundColor(SeleneTheme.ink90)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }
}
