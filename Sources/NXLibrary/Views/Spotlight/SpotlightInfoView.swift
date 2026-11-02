import SwiftUI
import AppKit
import NXLibraryCore

/// The selected game under the row (Main.xaml SeleneInfoIntro): logo area 195
/// high (logo up to 700 × 240, bottom-left, may rise 45 above; a touch larger
/// than Selene's 620 × 215), the "now playing" chip, the Play / Options /
/// Favorite pills and the stats line.
/// Starts 30 below the row; the caller places it.
struct SpotlightGameInfoView: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let game: PortedGame
    let logo: NSImage?
    let presentation: LibraryPresentation
    let isRunning: Bool
    /// Focused pill (0 Play, 1 Options, 2 Favorite), nil when the pills are not focused.
    let focusedPill: Int?
    let onPill: (Int) -> Void
    let onHoverPill: (Int) -> Void
    /// The pills follow the porting (`PortingPills`).
    var pillSet: PortingPills = .normal
    /// "About 8 min left" under the Porting pill.
    var etaText: String? = nil
    /// "Last porting failed · Open log".
    var onOpenLog: () -> Void = {}

    /// Change motion, after the row has glided: the logo holds 0.3 s, then fades
    /// in over 0.45 s while sliding x −30 → 0 (0.55 s cubic out); the pills and
    /// stats follow 0.12 s later.
    @State private var shown = true
    @State private var restShown = true
    @State private var slid = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logoArea
                .offset(x: slid ? 0 : canvas.u(-30))
                .opacity(shown ? 1 : 0)
            Group {
                if isRunning {
                    nowPlaying
                        .padding(.leading, canvas.u(2))
                        .padding(.top, canvas.u(24))
                }
                if case .failed(let failure) = pillSet {
                    Text(failure == .cancelled ? "Porting cancelled" : "Porting failed")
                        .seleneFont(19, .semibold)
                        .foregroundColor(PortingPillCopy.softRed)
                        .padding(.leading, canvas.u(4))
                        .padding(.top, canvas.u(20))
                }
                if let reason = pillSet.unavailableReason {
                    Text(reason.title)
                        .seleneFont(19, .semibold)
                        .foregroundColor(SeleneTheme.ink75)
                        .padding(.leading, canvas.u(4))
                        .padding(.top, canvas.u(20))
                }
                pills
                    .padding(.leading, canvas.u(2))
                    .padding(.top, canvas.u(pillSet.isFailed ? 10 : 18))
                note
                    .padding(.leading, canvas.u(4))
                    .padding(.top, canvas.u(12))
                SeleneStatsRow(presentation: presentation)
                    .padding(.leading, canvas.u(4))
                    .padding(.top, canvas.u(26))
            }
            .opacity(restShown ? 1 : 0)
        }
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
                    // The logo box: 700 × 240 (195 plus a −45 top margin), bottom-left.
                    .frame(width: canvas.u(700), height: canvas.u(240), alignment: .bottomLeading)
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
        .frame(width: canvas.u(900), height: canvas.u(195), alignment: .bottomLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.name)
        .accessibilityAddTraits(.isHeader)
    }

    /// The time left while porting, or the last failure over a working app.
    @ViewBuilder private var note: some View {
        switch pillSet {
        case .porting:
            if let etaText {
                Text(etaText)
                    .seleneFont(16)
                    .foregroundColor(SeleneTheme.ink75)
                    .transition(.opacity)
            }
        case .normalAfterFailure(let failure):
            Button(action: onOpenLog) {
                Text(PortingPillCopy.lastFailure(failure, reason: game.portingFailureReason))
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
            }
            .buttonStyle(.plain)
        case .failed(let failure):
            if failure == .failed, let reason = game.portingFailureReason {
                Text(reason.title)
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
            }
        case .unavailable(let reason):
            Text(reason.detail).seleneFont(15).foregroundColor(SeleneTheme.ink60)
        case .normal:
            if !game.sources.isEmpty, !GameResourceState.sourcesAvailable(for: game) {
                Text("Game files not found · Rebuild unavailable")
                    .seleneFont(15).foregroundColor(SeleneTheme.ink60)
            } else if !game.isPlayableLocally {
                Text("Not built yet").seleneFont(15).foregroundColor(SeleneTheme.ink60)
            }
        }
    }

    @ViewBuilder private var pills: some View {
        switch pillSet {
        case .porting:
            pill(0, SelenePillButton(title: "Porting", height: 52, focused: focusedPill == 0,
                                     waveDots: true) { onPill(0) })
                .accessibilityLabel("Porting, show progress")
        case .failed:
            HStack(spacing: canvas.u(14)) {
                ForEach(Array(PortingPillCopy.failedTitles.enumerated()), id: \.offset) { index, title in
                    pill(index, SelenePillButton(title: title, height: 52,
                                                 focused: focusedPill == index) { onPill(index) })
                }
            }
        case .normal, .normalAfterFailure, .unavailable:
            normalPills
        }
    }

    private var normalPills: some View {
        HStack(spacing: canvas.u(14)) {
            pill(0, SelenePillButton(title: primaryTitle, height: 52, focused: focusedPill == 0,
                                     enabled: isRunning || pillSet.unavailableReason == nil) { onPill(0) })
            pill(1, SelenePillButton(title: isRunning ? "Close Game" : "Options", height: 52,
                                     focused: focusedPill == 1) { onPill(1) })
            pill(2, SelenePillButton(title: nil, icon: game.isFavorite ? .favorite : .favoriteBorder,
                                     iconSize: 20, minWidth: 52, height: 52, horizontalPadding: 0,
                                     focused: focusedPill == 2) { onPill(2) })
                .accessibilityLabel(game.isFavorite ? "Remove from favorites" : "Add to favorites")
        }
    }

    private var primaryTitle: String {
        if isRunning { return "Resume" }
        if pillSet.unavailableReason != nil { return "Unavailable" }
        return game.isPlayableLocally ? "Play" : "Build"
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

    /// Reduce motion keeps the fades and drops the slide.
    private func reveal() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            shown = false
            restShown = false
            slid = reduceMotion
        }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.45).delay(0.3)) { shown = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.42)) { restShown = true }
            if !reduceMotion {
                withAnimation(SeleneTheme.cubicOut(0.55).delay(0.3)) { slid = true }
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

/// Copy shared by Spotlight's and Details' porting pills.
enum PortingPillCopy {
    static let failedTitles = ["Try again", "Open log", "Delete"]
    /// Soft, never alarm red.
    static let softRed = Color(hex: 0xF2A0A0)

    static func lastFailure(_ failure: PortingFailure, reason: PortingFailureReason? = nil) -> String {
        if failure == .cancelled { return "Last porting cancelled · Open log" }
        return "\(reason?.title ?? "Last porting failed") · Open log"
    }
}

extension PortingPills {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
