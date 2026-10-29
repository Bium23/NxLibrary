import SwiftUI
import AppKit
import NXLibraryCore

/// The selected game under the row (Main.xaml SeleneInfoIntro): logo area 170
/// high (logo up to 620 × 215, bottom-left, may rise 45 above), the "now
/// playing" chip, the Play / Details / Favorite pills and the stats line.
/// Starts 30 below the row; the caller places it.
struct SpotlightGameInfoView: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let game: PortedGame
    let logo: NSImage?
    let presentation: LibraryPresentation
    let isRunning: Bool
    /// Focused pill (0 Play, 1 Details, 2 Favorite), nil when the pills are not focused.
    let focusedPill: Int?
    let onPill: (Int) -> Void
    let onHoverPill: (Int) -> Void

    /// Selene's change motion: hold at 0 for 0.3 s, fade in by 0.7 s, slide x −30 → 0 (0.4 s cubic out from 0.3 s).
    @State private var shown = true
    @State private var slid = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logoArea
                .offset(x: slid ? 0 : canvas.u(-30))
            Group {
                if isRunning {
                    nowPlaying
                        .padding(.leading, canvas.u(2))
                        .padding(.top, canvas.u(24))
                }
                pills
                    .padding(.leading, canvas.u(2))
                    .padding(.top, canvas.u(18))
                stats
                    .padding(.leading, canvas.u(4))
                    .padding(.top, canvas.u(26))
            }
        }
        .opacity(shown ? 1 : 0)
        .frame(width: canvas.u(900), alignment: .leading)
        .onAppear { reveal() }
        .onChange(of: game.id) { _ in reveal() }
    }

    private var logoArea: some View {
        ZStack(alignment: .bottomLeading) {
            if let logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    // Selene's logo box: 620 × 215 (170 plus its −45 top margin), bottom-left.
                    .frame(width: canvas.u(620), height: canvas.u(215), alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.35), radius: canvas.u(8))
                    .transition(.opacity)
            } else {
                Text(game.name)
                    .seleneFont(56)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .shadow(color: .black.opacity(0.45), radius: canvas.u(6))
            }
        }
        .frame(width: canvas.u(900), height: canvas.u(170), alignment: .bottomLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.name)
        .accessibilityAddTraits(.isHeader)
    }

    private var pills: some View {
        HStack(spacing: canvas.u(14)) {
            pill(0, SelenePillButton(title: isRunning ? "Resume" : "Play", height: 52,
                                     focused: focusedPill == 0) { onPill(0) })
            pill(1, SelenePillButton(title: isRunning ? "Close Game" : "Details", height: 52,
                                     focused: focusedPill == 1) { onPill(1) })
            pill(2, SelenePillButton(title: nil, icon: game.isFavorite ? .favorite : .favoriteBorder,
                                     iconSize: 20, minWidth: 52, height: 52, horizontalPadding: 0,
                                     focused: focusedPill == 2) { onPill(2) })
                .accessibilityLabel(game.isFavorite ? "Remove from favorites" : "Add to favorites")
        }
    }

    /// Selene's pill Button is 60 high around a 52 high capsule.
    private func pill<V: View>(_ index: Int, _ view: V) -> some View {
        view
            .frame(height: canvas.u(60))
            .onHover { if $0 { onHoverPill(index) } }
    }

    private var stats: some View {
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

    private var nowPlaying: some View {
        HStack(spacing: 0) {
            NowPlayingDot()
                .frame(width: canvas.u(20), height: canvas.u(20))
                .padding(.trailing, canvas.u(9))
            Text("NOW PLAYING").seleneFont(14, .bold).foregroundColor(SeleneTheme.success)
            Rectangle().fill(SeleneTheme.ink25)
                .frame(width: max(1, canvas.u(1)), height: canvas.u(18))
                .padding(.horizontal, canvas.u(14))
            Text("Continue where you left off").seleneFont(17).foregroundColor(SeleneTheme.ink90)
        }
        .padding(EdgeInsets(top: canvas.u(6), leading: canvas.u(12), bottom: canvas.u(7), trailing: canvas.u(18)))
        .background(RoundedRectangle(cornerRadius: canvas.u(19), style: .continuous).fill(SeleneTheme.glassLight))
        .overlay(RoundedRectangle(cornerRadius: canvas.u(19), style: .continuous)
            .strokeBorder(SeleneTheme.ink25, lineWidth: max(1, canvas.u(1))))
    }

    private func reveal() {
        guard !reduceMotion else {
            shown = true
            slid = true
            return
        }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            shown = false
            slid = false
        }
        DispatchQueue.main.async {
            withAnimation(.linear(duration: 0.4).delay(0.3)) { shown = true }
            withAnimation(SeleneTheme.cubicOut(0.4).delay(0.3)) { slid = true }
        }
    }
}

/// Selene's success dot: a 9u dot with a ring pulsing 0.5 → 1 and fading 0.45 → 0 over 1.4 s.
private struct NowPlayingDot: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion {
                TimelineView(.animation) { context in
                    let p = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                    let eased = 1 - pow(1 - p, 3)
                    Circle().fill(SeleneTheme.success)
                        .scaleEffect(0.5 + 0.5 * eased)
                        .opacity(0.45 * (1 - p))
                }
            }
            Circle().fill(SeleneTheme.success)
                .frame(width: canvas.u(9), height: canvas.u(9))
        }
    }
}

/// A section card selected in the row: its name where the logo goes and one line about it.
struct SpotlightCardInfoView: View {
    @Environment(\.seleneCanvas) private var canvas

    let card: SpotlightCard

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(10)) {
            Text(card.title)
                .seleneFont(56)
                .foregroundColor(SeleneTheme.ink)
                .frame(height: canvas.u(170), alignment: .bottomLeading)
            Text(about)
                .seleneFont(19)
                .foregroundColor(SeleneTheme.ink90)
                .padding(.leading, canvas.u(2))
        }
        .frame(width: canvas.u(900), alignment: .leading)
        .shadow(color: .black.opacity(0.45), radius: canvas.u(6))
    }

    private var about: String {
        switch card {
        case .collection: return "Every game in your library, in one grid."
        case .surprise: return "Can't decide? Let NX Library pick one of your games."
        case .activity: return "What you played and for how long."
        case .addGame: return "Build a game from your own dumps."
        }
    }
}
