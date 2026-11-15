import SwiftUI
import AppKit
import NXLibraryCore

/// A Steam game's achievements, over the game's art (darker): logo, progress, filters and a two-column list.
/// A pure view like `ScreenshotViewer`: Spotlight owns `AchievementsScreenState` and routes input through
/// `AchievementsScreen.handle`. Present it as an overlay inside the canvas root so the canvas scaling applies.
struct AchievementsScreen: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @ObservedObject private var logos = SteamLogoCache.shared
    @ObservedObject private var picks = SteamPersonalizations.shared.artwork
    /// Whether the list has rows above or below what shows: the edge fades and the chevrons follow it.
    /// Changes only when a chevron appears or goes, not on every frame of a scroll.
    @State private var more = ListMore()
    /// Where the list's content sits, every frame: a reference, so writing it redraws nothing.
    @State private var metrics = ListMetrics()

    let game: CatalogGame
    let summary: AchievementSummary
    let state: AchievementsScreenState
    /// The page's art, as on Spotlight behind it.
    let art: NSImage?
    let onFilter: (AchievementFilter) -> Void
    let onFocus: (Int) -> Void
    let onClose: () -> Void

    static let side: CGFloat = 110
    static let columnWidth: CGFloat = 838
    static let gap: CGFloat = 24
    static let rowHeight: CGFloat = 104
    /// The list's last row can rise this far above the bottom edge: clear of the fade and the hints bar.
    static let bottomRoom: CGFloat = 130
    /// The fades at the list's edges.
    static let topFade: CGFloat = 40
    static let bottomFade: CGFloat = 100
    static let rowSpacing: CGFloat = 16

    enum Outcome { case ignored, moved, filtered, close }

    /// The arrows move through the list, LB/RB switch the filter, B closes; the host swallows the rest.
    static func handle(_ action: GamepadAction, state: inout AchievementsScreenState, summary: AchievementSummary) -> Outcome {
        switch action {
        case .navigateLeft: return state.move(.left) ? .moved : .ignored
        case .navigateRight: return state.move(.right) ? .moved : .ignored
        case .navigateUp: return state.move(.up) ? .moved : .ignored
        case .navigateDown: return state.move(.down) ? .moved : .ignored
        case .tabPrevious, .tabNext:
            state.shiftFilter(by: action == .tabPrevious ? -1 : 1) { summary.rows($0).map(\.id) }
            return .filtered
        case .cancel: return .close
        default: return .ignored
        }
    }

    var body: some View {
        let rows = summary.rows(state.filter)
        ZStack(alignment: .topLeading) {
            backdrop
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, canvas.u(70))
                pills
                    .padding(.top, canvas.u(30))
                list(rows)
                    .padding(.top, canvas.u(28))
            }
            .padding(.leading, canvas.u(Self.side))
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                SeleneHintsBar(left: [HintItem(.b, L10n.text("Back")) { onClose() }],
                               right: [HintItem(.lb, L10n.text("Previous")) { onFilter(Self.filter(after: state.filter, by: -1)) },
                                       HintItem(.rb, L10n.text("Next")) { onFilter(Self.filter(after: state.filter, by: 1)) }],
                               bottom: 40, leftInset: 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("Achievements"))
    }

    // MARK: - Parts

    private var backdrop: some View {
        ZStack {
            Rectangle().fill(SeleneTheme.baseGradient)
            if let art {
                // The art fills the screen's frame and is cut to it: an `.aspectRatio(.fill)` image under a
                // `.frame(maxWidth: .infinity)` made the frame as wide as the filled art, which widened the
                // whole screen past the window's edges (most in full screen) and pushed it off-centre.
                Color.clear
                    .overlay(Image(nsImage: art)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill))
                    .clipped()
            }
            LinearGradient(colors: [.black.opacity(0.8), .black.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
        }
        .ignoresSafeArea()
        // Swallows clicks so the page underneath never takes them.
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: canvas.u(14)) {
            Group {
                if let logo = logos.logo(for: "\(game.id)|\(picks.revision)") {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: canvas.u(520), maxHeight: canvas.u(130), alignment: .leading)
                } else {
                    Text(game.name)
                        .seleneFont(40, .semibold)
                        .foregroundColor(SeleneTheme.ink)
                        .lineLimit(1)
                }
            }
            .shadow(color: .black.opacity(0.4), radius: canvas.u(6))
            .accessibilityLabel(game.name)

            // The page's card, larger: the title, "17/50" with the completion beside it, the bar, the rarest.
            Text(L10n.text("Achievements"))
                .seleneFont(21, .semibold)
                .foregroundColor(SeleneTheme.ink82)
                .padding(.top, canvas.u(10))
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: canvas.u(18)) {
                (Text("\(summary.unlocked)").foregroundColor(SeleneTheme.ink)
                 + Text("/\(summary.total)").foregroundColor(SeleneTheme.ink60))
                    .seleneFont(48, .semibold)
                    .monospacedDigit()
                Text(L10n.format("%d%% complete", [summary.percentComplete]))
                    .seleneFont(19, .semibold)
                    .foregroundColor(SeleneTheme.ink75)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.format("Achievements: %d of %d", [summary.unlocked, summary.total]))
            AchievementProgressBar(fraction: summary.total > 0 ? Double(summary.unlocked) / Double(summary.total) : 0,
                                   height: 6, track: SeleneTheme.ink25)
                .frame(width: canvas.u(620))
            if let rarest = summary.rarestUnlocked, let percent = rarest.percent {
                Text(L10n.format("Rarest: %@ (%@)", [rarest.name, Self.percent(percent)]))
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
                    .lineLimit(1)
            }
        }
    }

    private var pills: some View {
        HStack(spacing: canvas.u(12)) {
            ForEach(AchievementFilter.allCases, id: \.self) { filter in
                let selected = filter == state.filter
                let count = summary.rows(filter).count
                Button { onFilter(filter) } label: {
                    (Text(Self.title(filter))
                     + Text("  \(count)").foregroundColor(selected ? SeleneTheme.onFocus.opacity(0.7) : SeleneTheme.ink60))
                        .seleneFont(16, .semibold)
                        .monospacedDigit()
                        .foregroundColor(selected ? SeleneTheme.onFocus : SeleneTheme.ink90)
                        .padding(.horizontal, canvas.u(20))
                        .padding(.vertical, canvas.u(8))
                        .background(Capsule().fill(selected ? SeleneTheme.focus : SeleneTheme.ink15))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Self.title(filter)), \(count)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(SeleneTheme.quick, value: state.filter)
    }

    private func list(_ rows: [AchievementRow]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                if rows.isEmpty {
                    Text(L10n.text("No achievements here yet."))
                        .seleneFont(17)
                        .foregroundColor(SeleneTheme.ink60)
                        .padding(.top, canvas.u(20))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(canvas.u(Self.columnWidth)), spacing: canvas.u(Self.gap),
                                                                 alignment: .leading),
                                             count: AchievementsScreenState.columns),
                              alignment: .leading, spacing: canvas.u(Self.rowSpacing)) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            AchievementsScreenRow(row: row, appID: game.steamGame?.appID ?? 0, focused: index == state.index)
                                .id(row.id)
                                .onTapGesture { onFocus(index) }
                        }
                    }
                    // Room for the focus ring and, at the end, for the hints bar.
                    .padding(.vertical, canvas.u(6))
                    .padding(.horizontal, canvas.u(4))
                    .padding(.bottom, canvas.u(Self.bottomRoom))
                    .background(GeometryReader { content in
                        Color.clear.preference(key: ListContentKey.self, value: content.frame(in: .named(Self.listSpace)))
                    })
                }
            }
            .coordinateSpace(name: Self.listSpace)
            .background(GeometryReader { viewport in
                Color.clear.preference(key: ListViewportKey.self, value: viewport.size.height)
            })
            .onPreferenceChange(ListContentKey.self) { frame in
                metrics.content = frame
                updateMore()
            }
            .onPreferenceChange(ListViewportKey.self) { height in
                metrics.viewport = height
                updateMore()
            }
            // The rows fade out under the hints bar, and at the top once the list has scrolled: no row sits
            // under a button. The chevrons say there is more.
            .mask(listMask)
            .overlay(alignment: .top) {
                SpotlightUpHint()
                    .padding(.top, canvas.u(4))
                    .opacity(more.above ? 1 : 0)
            }
            .overlay(alignment: .bottom) {
                SpotlightUpHint()
                    .rotationEffect(.degrees(180))
                    .padding(.bottom, canvas.u(Self.bottomFade - 8))
                    .opacity(more.below ? 1 : 0)
            }
            .frame(width: canvas.u(Self.columnWidth * 2 + Self.gap + 8))
            .onChange(of: state.index) { _ in scroll(proxy, rows) }
            .onChange(of: state.filter) { _ in
                if let first = rows.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }

    private static let listSpace = "achievementsList"

    /// Opaque in the middle; the top fades only once rows have scrolled past it, the bottom always fades to
    /// nothing where the hints bar sits.
    private var listMask: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(more.above ? 0 : 1), .black],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: canvas.u(Self.topFade))
            Color.black
            // To a trace, not to nothing: the bottom stays lit, not a dark band.
            LinearGradient(colors: [.black, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                .frame(height: canvas.u(Self.bottomFade))
        }
    }

    /// Sets `more` only when a chevron appears or goes, so a scroll does not redraw the screen every frame.
    private func updateMore() {
        let next = ListMore(above: metrics.content.minY < -1,
                            below: metrics.viewport > 0
                                && metrics.content.maxY - canvas.u(Self.bottomRoom) > metrics.viewport + 1)
        guard next != more else { return }
        withAnimation(.easeInOut(duration: 0.3)) { more = next }
    }

    /// Scrolls only when the focused row leaves the band between the fades, and then just enough
    /// (`ListScrollBand`): inside the band the list stays still.
    private func scroll(_ proxy: ScrollViewProxy, _ rows: [AchievementRow]) {
        guard rows.indices.contains(state.index) else { return }
        let id = rows[state.index].id
        let line = CGFloat(state.index / AchievementsScreenState.columns)
        let rowTop = metrics.content.minY + canvas.u(6) + line * canvas.u(Self.rowHeight + Self.rowSpacing)
        guard let anchor = ListScrollBand.anchor(rowTop: rowTop, rowHeight: canvas.u(Self.rowHeight),
                                                 viewport: metrics.viewport,
                                                 safeTop: canvas.u(Self.topFade),
                                                 safeBottom: metrics.viewport - canvas.u(Self.bottomRoom))
        else { return }
        let point = UnitPoint(x: 0.5, y: anchor)
        if reduceMotion { proxy.scrollTo(id, anchor: point) }
        else { withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.32)) { proxy.scrollTo(id, anchor: point) } }
    }

    /// The filter LB (-1) or RB (+1) picks from `filter`, wrapping as the controller does.
    static func filter(after filter: AchievementFilter, by step: Int) -> AchievementFilter {
        let all = AchievementFilter.allCases
        let index = all.firstIndex(of: filter) ?? 0
        return all[(index + step + all.count) % all.count]
    }

    static func title(_ filter: AchievementFilter) -> String {
        switch filter {
        case .all: return L10n.text("All")
        case .unlocked: return L10n.text("Unlocked")
        case .locked: return L10n.text("Locked")
        case .rarest: return L10n.text("Rarest")
        }
    }

    /// 4.5 → "4.5%" in the app's locale ("4,5 %" in French).
    static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(1)).locale(L10n.context.formatLocale))
    }
}

/// One achievement: icon, name, description, unlock date (or Not unlocked) and how many players have it.
private struct AchievementsScreenRow: View {
    @Environment(\.seleneCanvas) private var canvas
    @State private var hovered = false

    let row: AchievementRow
    let appID: UInt32
    let focused: Bool

    var body: some View {
        let radius = canvas.u(SeleneTheme.contentRadius)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let unlocked = row.unlockedAt != nil
        HStack(spacing: canvas.u(18)) {
            AchievementIcon(appID: appID, file: row.icon, size: 64, dimmed: !unlocked)
            VStack(alignment: .leading, spacing: canvas.u(4)) {
                Text(row.name)
                    .seleneFont(18, .semibold)
                    .foregroundColor(unlocked ? SeleneTheme.ink : SeleneTheme.ink82)
                    .lineLimit(1)
                Text(row.description)
                    .seleneFont(14)
                    .foregroundColor(SeleneTheme.ink60)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: canvas.u(14)) {
                    if let date = row.unlockedAt {
                        Label {
                            Text(Self.date(date))
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .labelStyle(.titleAndIcon)
                        .foregroundColor(SeleneTheme.ink82)
                    } else {
                        Text(L10n.text("Not unlocked"))
                            .foregroundColor(SeleneTheme.ink.opacity(0.45))
                    }
                    if let percent = row.percent {
                        Text(L10n.format("%@ of players", [AchievementsScreen.percent(percent)]))
                            .foregroundColor(row.isRare ? SeleneTheme.rare : SeleneTheme.ink60)
                    }
                }
                .seleneFont(13, .semibold)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, canvas.u(18))
        .frame(width: canvas.u(AchievementsScreen.columnWidth), height: canvas.u(AchievementsScreen.rowHeight), alignment: .leading)
        // The page's card surface: lightly tinted, a thin outline, a little lighter focused or under the pointer.
        .background(shape.fill(SeleneTheme.ink.opacity(focused ? 0.10 : hovered ? 0.08 : 0.05)))
        .overlay(shape.strokeBorder(hovered || focused ? SeleneTheme.ink25 : SeleneTheme.ink15,
                                    lineWidth: max(1, canvas.u(1))))
        .seleneRowFocus(focused, radius: radius)
        .contentShape(shape)
        // Instant: the list scrolling under a still pointer flips rows in and out of hover, and an animation
        // for each would pile up on the scroll.
        .onHover { hovered = $0 }
        .animation(SeleneTheme.quick, value: focused)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(focused ? .isSelected : [])
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(L10n.context.formatLocale))
    }
}

/// Rows hidden above or below the list's edges (the bottom less the room kept for the hints bar).
private struct ListMore: Equatable {
    var above = false
    var below = false
}

/// The list's content frame in its viewport and the viewport's height, written on every scroll frame.
private final class ListMetrics {
    var content: CGRect = .zero
    var viewport: CGFloat = 0
}

private struct ListContentKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct ListViewportKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
