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
                SeleneStatsRow(presentation: presentation)
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

    /// Hold 0.3 s, then fade in linearly to 0.7 s while the logo slides in.
    /// Reduce motion keeps the fade and drops the slide.
    private func reveal() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            shown = false
            slid = reduceMotion
        }
        DispatchQueue.main.async {
            withAnimation(.linear(duration: 0.4).delay(0.3)) { shown = true }
            if !reduceMotion {
                withAnimation(SeleneTheme.cubicOut(0.4).delay(0.3)) { slid = true }
            }
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
