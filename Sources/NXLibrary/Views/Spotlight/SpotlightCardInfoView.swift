import SwiftUI
import NXLibraryCore

/// What a selected card shows under the row: headline (28 SemiBold), body
/// (19, ink82), its numbers, and the "A" action. Activity adds this week's
/// total, seven day bars and the top games.
struct SpotlightCardInfoView: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let card: SpotlightCard
    let gameCount: Int
    let installedCount: Int
    let poolLabel: String
    let activity: ActivitySummary
    let topGames: [PortedGame]
    let focusedTop: Int?
    let artwork: ArtworkStore
    let onTopGame: (Int) -> Void

    /// Monday first, whatever the locale (matches `Activity.summary`).
    private static let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headline)
                .seleneFont(28, .semibold)
                .foregroundColor(SeleneTheme.ink)
            Text(about)
                .seleneFont(19)
                .foregroundColor(SeleneTheme.ink82)
                .padding(.top, canvas.u(8))
            detail
                .padding(.top, canvas.u(22))
            if let action {
                actionChip(action)
                    .padding(.top, canvas.u(22))
            }
        }
        .frame(width: canvas.u(900), alignment: .leading)
        .shadow(color: .black.opacity(0.45), radius: canvas.u(6))
    }

    private var headline: String {
        switch card {
        case .collection: return "Collection"
        case .surprise: return "Surprise me"
        case .activity: return "Activity"
        case .addGame: return "Add a game"
        }
    }

    private var about: String {
        switch card {
        case .collection: return "Every game in your library, in one grid."
        case .surprise: return "Can't decide? Pick a game for me."
        case .activity: return "What you played this week."
        case .addGame: return "Build a game from your own dumps."
        }
    }

    private var action: String? {
        switch card {
        case .collection: return "Open"
        case .surprise: return "Pick"
        case .activity: return nil
        case .addGame: return "Add"
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch card {
        case .collection:
            HStack(spacing: canvas.u(26)) {
                stat("GAMES", "\(gameCount)")
                divider
                stat("INSTALLED", "\(installedCount)")
            }
        case .surprise:
            stat("PICKS FROM", poolLabel)
        case .activity:
            activityDetail
        case .addGame:
            EmptyView()
        }
    }

    private var activityDetail: some View {
        VStack(alignment: .leading, spacing: canvas.u(18)) {
            HStack(alignment: .bottom, spacing: canvas.u(44)) {
                stat("THIS WEEK", Self.duration(activity.thisWeek))
                bars
            }
            if !topGames.isEmpty {
                VStack(alignment: .leading, spacing: canvas.u(8)) {
                    Text("MOST PLAYED").seleneFont(12, .semibold).foregroundColor(SeleneTheme.ink60)
                    HStack(spacing: canvas.u(14)) {
                        ForEach(Array(topGames.enumerated()), id: \.element.id) { index, game in
                            topTile(game, focused: focusedTop == index)
                                .onTapGesture { onTopGame(index) }
                        }
                    }
                    .padding(canvas.u(6))
                    .padding(canvas.u(-6))
                }
            }
        }
    }

    private var bars: some View {
        let peak = max(activity.perDay.max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: canvas.u(10)) {
            ForEach(0..<7, id: \.self) { day in
                let value = day < activity.perDay.count ? activity.perDay[day] : 0
                VStack(spacing: canvas.u(6)) {
                    RoundedRectangle(cornerRadius: canvas.u(4), style: .continuous)
                        .fill(value > 0 ? SeleneTheme.focus : SeleneTheme.ink15)
                        .frame(width: canvas.u(22), height: canvas.u(value > 0 ? max(6, 56 * value / peak) : 4))
                    Text(Self.dayLetters[day]).seleneFont(12, .semibold).foregroundColor(SeleneTheme.ink60)
                }
            }
        }
        .frame(height: canvas.u(80), alignment: .bottom)
    }

    private func topTile(_ game: PortedGame, focused: Bool) -> some View {
        let side = canvas.u(64)
        let shape = RoundedRectangle(cornerRadius: canvas.u(10), style: .continuous)
        return SpotlightTileArtwork(game: game, side: side,
                                    artwork: artwork)
            .clipShape(shape)
            .overlay(shape.strokeBorder(SeleneTheme.ink15, lineWidth: max(1, canvas.u(1))))
            .overlay(shape.inset(by: canvas.u(-4))
                .strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(3))
                .opacity(focused ? 1 : 0))
            .scaleEffect(focused && !reduceMotion ? 1.06 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: focused)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(4)) {
            Text(label).seleneFont(12, .semibold).foregroundColor(SeleneTheme.ink60)
            Text(value).seleneFont(21, .semibold).foregroundColor(SeleneTheme.ink)
        }
    }

    private var divider: some View {
        Rectangle().fill(SeleneTheme.ink25).frame(width: max(1, canvas.u(1)), height: canvas.u(36))
    }

    private func actionChip(_ label: String) -> some View {
        HStack(spacing: canvas.u(10)) {
            SelenePromptBadge(button: .a)
            Text(label).seleneFont(19).foregroundColor(SeleneTheme.ink90)
        }
    }

    /// "0 min", "42 min", "3 h 20 min".
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(max(0, interval) / 60)
        if minutes < 60 { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(rest) min"
    }
}

/// The card's Y menu: Move, Hide card.
struct SpotlightCardMenu: View {
    @Environment(\.seleneCanvas) private var canvas

    static let rows: [(title: String, subtitle: String, icon: MaterialIcon)] = [
        ("Move", "Change its place on Spotlight", .swap),
        ("Hide card", "Bring it back in Settings", .hidden)
    ]

    let card: SpotlightCard
    let focusedIndex: Int
    let onFocus: (Int) -> Void
    let onChoose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(14)) {
            Text(card.title).seleneFont(28, .semibold).foregroundColor(SeleneTheme.ink)
            VStack(spacing: canvas.u(8)) {
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                    let focused = index == focusedIndex
                    HStack(spacing: canvas.u(16)) {
                        MaterialIconView(row.icon, size: 28)
                        VStack(alignment: .leading, spacing: canvas.u(2)) {
                            Text(row.title).seleneFont(21, .semibold)
                            Text(row.subtitle).seleneFont(15)
                                .foregroundColor(focused ? SeleneTheme.onFocus.opacity(0.8) : SeleneTheme.ink60)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(focused ? SeleneTheme.onFocus : SeleneTheme.ink)
                    .padding(.horizontal, canvas.u(20))
                    .frame(height: canvas.u(68))
                    .background(RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous)
                        .fill(focused ? SeleneTheme.focus.opacity(0.95) : Color.clear))
                    .contentShape(Rectangle())
                    .onHover { if $0 { onFocus(index) } }
                    .onTapGesture { onFocus(index); onChoose(index) }
                }
            }
        }
        .padding(canvas.u(24))
        .frame(width: canvas.u(560))
        .background(RoundedRectangle(cornerRadius: canvas.u(20), style: .continuous).fill(SeleneTheme.glassSolid))
        .overlay(RoundedRectangle(cornerRadius: canvas.u(20), style: .continuous)
            .strokeBorder(SeleneTheme.ink25, lineWidth: max(1, canvas.u(1))))
        .accessibilityElement(children: .contain)
    }
}

/// "Filter · count" with the LT ◂ ▸ RT hint (spec §5.1).
struct SpotlightFilterPill: View {
    @Environment(\.seleneCanvas) private var canvas

    let filter: LibraryFilter
    let count: Int

    var body: some View {
        HStack(spacing: canvas.u(12)) {
            Text("\(filter.rawValue) · \(count)")
                .seleneFont(17, .semibold)
                .foregroundColor(SeleneTheme.ink)
            HStack(spacing: canvas.u(6)) {
                SelenePromptBadge(button: .lt, height: 22)
                Text("◂ ▸").seleneFont(15).foregroundColor(SeleneTheme.ink60)
                SelenePromptBadge(button: .rt, height: 22)
            }
        }
        .padding(EdgeInsets(top: canvas.u(5), leading: canvas.u(16), bottom: canvas.u(6), trailing: canvas.u(16)))
        .background(RoundedRectangle(cornerRadius: canvas.u(17), style: .continuous).fill(SeleneTheme.glassLight))
        .overlay(RoundedRectangle(cornerRadius: canvas.u(17), style: .continuous)
            .strokeBorder(SeleneTheme.ink25, lineWidth: max(1, canvas.u(1))))
        .allowsHitTesting(false)
    }
}
