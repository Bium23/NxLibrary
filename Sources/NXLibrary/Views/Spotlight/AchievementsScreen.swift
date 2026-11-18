import SwiftUI
import AppKit
import NXLibraryCore

/// A Steam game's achievements, over the game's art (darker), laid out like Selene's: the logo and the recently
/// unlocked icons on the left, the progress and the tier crystals on the right, filters between LB and RB, a
/// one-column list.
/// A pure view like `ScreenshotViewer`: Spotlight owns `AchievementsScreenState` and routes input through
/// `AchievementsScreen.handle`. Present it as an overlay inside the canvas root so the canvas scaling applies.
struct AchievementsScreen: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    /// The earned Arcane comes to colour just after the screen opens (`arcaneOrb`).
    @State private var arcaneLit = false
    @ObservedObject private var logos = SteamLogoCache.shared
    @ObservedObject private var picks = SteamPersonalizations.shared.artwork
    @ObservedObject var model: AchievementsScreenModel

    let game: CatalogGame
    let summary: AchievementSummary
    /// The page's art, as on Spotlight behind it.
    let art: NSImage?
    let onFilter: (AchievementFilter) -> Void
    /// LB (-1) or RB (+1), as the controller does.
    let onShiftFilter: (Int) -> Void
    /// Y or a click on the order: the next order.
    let onCycleOrder: () -> Void
    let onFocus: (Int) -> Void
    /// A, the hint or a click on the focused row: the focused achievement's detail.
    let onOpen: () -> Void
    let onCloseDetail: () -> Void
    let onClose: () -> Void

    static let side: CGFloat = 110
    /// The list's one column, as wide as the two columns and their gap it replaced.
    static let listWidth: CGFloat = 1700
    static let rowHeight: CGFloat = 96
    /// The Recently unlocked strip's length.
    static let recentLimit = 12
    /// The list's last row can rise this far above the bottom edge: clear of the fade and the hints bar.
    static let bottomRoom: CGFloat = hintsBand + bottomFade
    /// The fades at the list's edges.
    static let topFade: CGFloat = 40
    static let bottomFade: CGFloat = 110
    /// The shared footer stays entirely clear of rows, below the fade.
    static let hintsBand: CGFloat = SeleneBottomScrim.contentClearance
    static let rowSpacing: CGFloat = 16
    /// Room for the focus ring around the rows.
    static let ring: CGFloat = 6

    private var state: AchievementsScreenState { model.state }

    var body: some View {
        let rows = summary.rows(state.filter, order: state.order)
        ZStack(alignment: .topLeading) {
            backdrop
            VStack(alignment: .leading, spacing: 0) {
                // The game on the left; the progress on the right, level with the list's right edge.
                // The medallion sits centred on the game's column (logo and Recently unlocked); the gauge, at its top.
                HStack(alignment: summary.isComplete ? .center : .top, spacing: 0) {
                    header
                    Spacer(minLength: canvas.u(40))
                    progress
                }
                .frame(width: canvas.u(Self.listWidth + Self.ring))
                .padding(.top, canvas.u(70))
                pills.padding(.top, canvas.u(30))
                AchievementsList(scroll: model.scroll, model: model, rows: rows, focused: state.index,
                                 appID: game.steamGame?.appID ?? 0, onFocus: onFocus)
                    .padding(.top, canvas.u(28))
            }
            .padding(.leading, canvas.u(Self.side))
            if state.isDetailOpen, let id = state.focusedID, let row = rows.first(where: { $0.id == id }) {
                AchievementDetail(row: row, appID: game.steamGame?.appID ?? 0, onClose: onCloseDetail)
                    .transition(.opacity)
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                SeleneHintsBar(left: [HintItem(.b, L10n.text("Back")) {
                                   if state.isDetailOpen { onCloseDetail() } else { onClose() }
                               }],
                               right: state.isDetailOpen ? [] : listHints(hasRows: !rows.isEmpty),
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
            }
        }
        .animation(SeleneTheme.quick, value: state.isDetailOpen)
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
            // A little more shade at the bottom, under the hints.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                    .frame(height: canvas.u(240))
            }
        }
        .ignoresSafeArea()
        // Swallows clicks so the page underneath never takes them.
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    /// The logo, then the newest unlocked icons (look only, no focus stop); no strip before the first unlock.
    private var header: some View {
        let recent = summary.recentUnlockedIcons(limit: Self.recentLimit)
        return VStack(alignment: .leading, spacing: canvas.u(24)) {
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

            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: canvas.u(12)) {
                    Text(L10n.text("Recently unlocked"))
                        .seleneFont(19, .semibold)
                        .foregroundColor(SeleneTheme.ink90)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: canvas.u(14)) {
                        ForEach(Array(recent.enumerated()), id: \.offset) { _, icon in
                            AchievementIcon(appID: game.steamGame?.appID ?? 0, file: icon, size: 72)
                        }
                    }
                }
            }
        }
    }

    /// Arcane, Gold, Silver, Bronze with unlocked/total under each, as PS5 trophies, dimmed while not earned (only
    /// Arcane until Steam's rarity arrives). Under them the gauge, as wide as the four trophies: the large
    /// percentage, its bar and the count line, all starting at the first trophy's edge (layout "A, barra larga",
    /// maintainer's choice, 16 Nov 2026). Arcane earned, the medallion instead.
    @ViewBuilder
    private var progress: some View {
        if summary.isComplete {
            medallion
        } else {
            TrophyColumn(minWidth: canvas.u(Self.fourTrophies), spacing: canvas.u(24)) {
                board
                gauge
            }
        }
    }

    private var gauge: some View {
        let fraction = summary.total > 0 ? Double(summary.unlocked) / Double(summary.total) : 0
        return VStack(alignment: .leading, spacing: 0) {
            Text(Self.wholePercent(summary.percentComplete))
                .seleneFont(44, .semibold)
                .monospacedDigit()
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(1)
            // As wide as the trophies above, the width `TrophyColumn` gives the gauge.
            AchievementProgressBar(fraction: fraction, height: 4, track: SeleneTheme.ink25)
                .frame(maxWidth: .infinity)
                .padding(.top, canvas.u(4))
            // A long language wraps under the trophies rather than overflowing them.
            countLineText(lines: 2)
                .padding(.top, canvas.u(10))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("Achievements: %d of %d", [summary.unlocked, summary.total]))
    }

    /// The board's trophies, in canvas units.
    private static let trophy: CGFloat = 64
    private static let trophySpacing: CGFloat = 26
    /// All four trophies' width: the gauge keeps it while only Arcane shows, so Arcane does not move when Steam's
    /// rarity brings the other three.
    private static let fourTrophies: CGFloat = 4 * trophy + 3 * trophySpacing

    private var board: some View {
        let counts = summary.tierCounts
        let tiers = summary.hasRarity ? AchievementTier.allCases : [.arcane]
        return HStack(alignment: .top, spacing: canvas.u(Self.trophySpacing)) {
            ForEach(tiers, id: \.self) { tier in
                let count = counts[tier] ?? TierCount(unlocked: 0, total: 0)
                VStack(spacing: canvas.u(6)) {
                    TierCrystal(tier: tier, size: Self.trophy, dimmed: count.unlocked == 0)
                    countText(count, size: 18)
                }
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.tierLabel(tier, count))
            }
        }
    }

    /// Arcane earned (layout "B", the medallion, maintainer's choice, 16 Nov 2026): everything on one centred axis,
    /// the orb on top, its name, the count line, and Gold, Silver and Bronze as small crystals with their counts. It
    /// replaces the gauge and the board: "100%", a full bar and "1 / 1" would only repeat the orb.
    private var medallion: some View {
        VStack(spacing: 0) {
            arcaneOrb
            Text(AchievementTier.arcane.displayName())
                .seleneFont(40, .semibold)
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(1)
                .padding(.top, canvas.u(10))
            countLineText(lines: 1)
                .padding(.top, canvas.u(4))
            if summary.hasRarity {
                let counts = summary.tierCounts
                HStack(spacing: canvas.u(24)) {
                    ForEach([AchievementTier.gold, .silver, .bronze], id: \.self) { tier in
                        let count = counts[tier] ?? TierCount(unlocked: 0, total: 0)
                        HStack(spacing: canvas.u(6)) {
                            TierCrystal(tier: tier, size: 28, dimmed: count.unlocked == 0)
                            countText(count, size: 16)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Self.tierLabel(tier, count))
                    }
                }
                .padding(.top, canvas.u(16))
            }
        }
        .fixedSize()
    }

    /// The card's looping orb, large, coming to colour just after the screen opens and playing while it stays
    /// open (still, in colour, with Reduce motion). The still orb without the video.
    private var arcaneOrb: some View {
        Group {
            if let video = AchievementTier.arcane.videoURL {
                ArcaneOrbVideo(url: video, active: arcaneLit, moves: !reduceMotion)
            } else {
                TierCrystal(tier: .arcane, size: 128)
            }
        }
        .frame(width: canvas.u(128), height: canvas.u(128))
        .task {
            // After the orb's first, grey state is drawn, so the change to colour is seen.
            try? await Task.sleep(nanoseconds: 150_000_000)
            arcaneLit = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("%@, every achievement unlocked", [AchievementTier.arcane.displayName()]))
    }

    /// "36 / 36": the unlocked count bright, the total dimmer.
    private func countText(_ count: TierCount, size: CGFloat) -> some View {
        (Text("\(count.unlocked)").foregroundColor(SeleneTheme.ink)
         + Text(" / \(count.total)").foregroundColor(SeleneTheme.ink75))
            .seleneFont(size, .semibold)
            .monospacedDigit()
            // Its own width, never a share of the crystal's: squeezed, "0 / 13" read "0…".
            .fixedSize()
    }

    /// The count line as the gauge and the medallion show it, in up to `lines` lines.
    private func countLineText(lines: Int) -> some View {
        Text(countLine)
            .seleneFont(16)
            .foregroundColor(SeleneTheme.ink75)
            .monospacedDigit()
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "Gold, 3 of 12", for VoiceOver.
    private static func tierLabel(_ tier: AchievementTier, _ count: TierCount) -> String {
        L10n.format("%1$@, %2$d of %3$d", [tier.displayName(), count.unlocked, count.total])
    }

    /// "17 of 50 unlocked · last on 31 Jul 2026"; the count alone before the first unlock.
    private var countLine: String {
        if let last = summary.lastUnlockedAt {
            return L10n.format("%1$d of %2$d unlocked · last on %3$@",
                               [summary.unlocked, summary.total, Self.date(last)])
        }
        return L10n.format("%1$d of %2$d unlocked", [summary.unlocked, summary.total])
    }

    /// 34 → "34%" in the app's locale ("34 %" in French).
    static func wholePercent(_ value: Int) -> String {
        (Double(value) / 100).formatted(.percent.precision(.fractionLength(0)).locale(L10n.context.formatLocale))
    }

    /// The filters between the shoulder badges, as on Selene: LB and RB step through them (and take a click).
    private var pills: some View {
        HStack(spacing: canvas.u(12)) {
            shoulder(.lb, L10n.text("Previous"), step: -1)
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
            shoulder(.rb, L10n.text("Next"), step: 1)
        }
        .animation(SeleneTheme.quick, value: state.filter)
    }

    private func shoulder(_ button: PromptButton, _ label: String, step: Int) -> some View {
        Button { onShiftFilter(step) } label: {
            SelenePromptBadge(button: button, height: 22)
                .frame(minWidth: canvas.u(30), minHeight: canvas.u(36))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    static func title(_ filter: AchievementFilter) -> String {
        switch filter {
        case .all: return L10n.text("All")
        case .unlocked: return L10n.text("Unlocked")
        case .locked: return L10n.text("Locked")
        }
    }

    /// Order and Open share the bottom-right hints. Keep Order available even when the filter is empty.
    private func listHints(hasRows: Bool) -> [HintItem] {
        var hints = [HintItem(.y, Self.title(state.order)) { onCycleOrder() }]
        if hasRows { hints.append(HintItem(.a, L10n.text("Open")) { onOpen() }) }
        return hints
    }

    static func title(_ order: AchievementOrder) -> String {
        switch order {
        case .default: return L10n.text("Default order")
        case .rarest: return L10n.text("Rarest first")
        case .commonest: return L10n.text("Most common first")
        }
    }

    /// "31 Jul 2026" in the app's locale.
    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(L10n.context.formatLocale))
    }

    /// 4.5 → "4.5%" in the app's locale ("4,5 %" in French).
    static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(1)).locale(L10n.context.formatLocale))
    }
}

/// One achievement: icon, name and description; on the right its tier crystal with how many players have it,
/// and the unlock date (or Not unlocked).
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
            AchievementIcon(appID: appID, file: row.icon, size: 64, dimmed: !unlocked, secret: row.isMasked)
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
            }
            Spacer(minLength: canvas.u(16))
            // The tier with its crystal and how many players have it, the date under it.
            VStack(alignment: .trailing, spacing: canvas.u(6)) {
                if let tier = row.tier, let percent = row.percent {
                    HStack(spacing: canvas.u(6)) {
                        TierCrystal(tier: tier, size: 24, dimmed: !unlocked)
                        Text(tier.displayName())
                            .foregroundColor(unlocked ? SeleneTheme.ink : SeleneTheme.ink75)
                        Text("· \(AchievementsScreen.percent(percent))")
                            .foregroundColor(SeleneTheme.ink60)
                            .monospacedDigit()
                    }
                }
                if let date = row.unlockedAt {
                    Label {
                        Text(AchievementsScreen.date(date))
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .foregroundColor(SeleneTheme.ink82)
                } else {
                    Text(L10n.text("Not unlocked"))
                        .foregroundColor(SeleneTheme.ink.opacity(0.45))
                }
            }
            .seleneFont(13, .semibold)
            .lineLimit(1)
            .fixedSize()
        }
        .padding(.horizontal, canvas.u(18))
        .frame(width: canvas.u(AchievementsScreen.listWidth), height: canvas.u(AchievementsScreen.rowHeight), alignment: .leading)
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
}

/// The one-column list, moved by its own offset (`ListScroll`) instead of a scroll view: the wheel and the
/// arrows glide the same offset, and only the lines in view (and a window's worth either side, for a glide)
/// are drawn. Observes the scroll alone, so a scroll frame redraws the list, not the screen.
private struct AchievementsList: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @ObservedObject var scroll: ListScroll
    /// Not observed: the list only reports its size to it.
    let model: AchievementsScreenModel
    let rows: [AchievementRow]
    let focused: Int
    let appID: UInt32
    let onFocus: (Int) -> Void

    private typealias Screen = AchievementsScreen

    private var layout: GridListLayout {
        GridListLayout(columns: AchievementsScreenState.columns, rowHeight: canvas.u(Screen.rowHeight),
                       spacing: canvas.u(Screen.rowSpacing), topPad: canvas.u(Screen.ring),
                       bottomRoom: canvas.u(Screen.bottomRoom))
    }

    private var width: CGFloat { canvas.u(Screen.listWidth + Screen.ring * 2) }

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            Group {
                if rows.isEmpty {
                    Text(L10n.text("No achievements here yet."))
                        .seleneFont(17)
                        .foregroundColor(SeleneTheme.ink60)
                        .padding(.top, canvas.u(20))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    content(height: height)
                }
            }
            // A rapid reopen reuses the outgoing view at the same size, but the new model needs its layout.
            .task(id: ObjectIdentifier(model)) { report(height) }
            .onChange(of: height) { report($0) }
            .onChange(of: canvas.scale) { _ in report(height) }
            .onChange(of: reduceMotion) { _ in report(height) }
        }
        .frame(width: width)
    }

    private func content(height: CGFloat) -> some View {
        let layout = layout
        let offset = scroll.state.offset
        let lines = layout.visibleLines(count: rows.count, offset: offset, visible: height, buffer: height)
        let indices = lines.map { ($0.lowerBound * layout.columns)..<min(($0.upperBound + 1) * layout.columns, rows.count) }
            ?? 0..<0
        let pitch = canvas.u(Screen.listWidth)
        return ZStack(alignment: .topLeading) {
            ForEach(indices, id: \.self) { index in
                let top = layout.top(of: index)
                // Only rows inside the window take a click: one scrolled under the pills still sits there.
                let inView = top + layout.rowHeight > offset && top < offset + height
                AchievementsScreenRow(row: rows[index], appID: appID, focused: index == focused)
                    .id(rows[index].id)
                    .offset(x: canvas.u(Screen.ring) + CGFloat(index % layout.columns) * pitch, y: top)
                    .onTapGesture { onFocus(index) }
                    .allowsHitTesting(inView)
                    .transition(.identity)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        // Rows made, and icons arriving, during a glide ride it with the rest (`GlideGroup`).
        .modifier(GlideGroup())
        .offset(y: -offset)
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        // The rows fade out above the hints bar, gone before its buttons, and at the top once the list has
        // scrolled: no row sits under a button. No chevrons (maintainer's choice): the fades alone say there is more.
        .mask(mask(atTop: scroll.state.atTop))
        .contentShape(Path(CGRect(x: 0, y: 0, width: width,
                                  height: max(0, height - canvas.u(Screen.hintsBand)))))
    }

    /// Opaque in the middle; the top fades only once rows have scrolled past it; the bottom always fades out,
    /// to nothing by the hints bar's band (at 0.15 the rows showed through the buttons).
    private func mask(atTop: Bool) -> some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(atTop ? 1 : 0), .black], startPoint: .top, endPoint: .bottom)
                .frame(height: canvas.u(Screen.topFade))
                .animation(.easeInOut(duration: 0.3), value: atTop)
            Color.black
            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: canvas.u(Screen.bottomFade))
            Color.clear
                .frame(height: canvas.u(Screen.hintsBand))
        }
    }

    /// The focused row keeps the top fade and a little more above it, and the bottom room below.
    private func report(_ height: CGFloat) {
        model.setLayout(layout, visible: height, above: canvas.u(Screen.topFade + 12),
                        below: canvas.u(Screen.bottomRoom), animates: !reduceMotion)
    }
}

/// The trophies, then the gauge under them: the first view sets the column's width (at least `minWidth`) and every
/// view below is offered that width, left-aligned. A `VStack` would take the widest line's width instead, so a long
/// count line would push the trophies off their place.
private struct TrophyColumn: Layout {
    var minWidth: CGFloat
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = columnWidth(subviews)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let offer = ProposedViewSize(width: columnWidth(subviews), height: nil)
        var y = bounds.minY
        for view in subviews {
            view.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: offer)
            y += view.sizeThatFits(offer).height + spacing
        }
    }

    private func columnWidth(_ subviews: Subviews) -> CGFloat {
        max(minWidth, subviews.first?.sizeThatFits(.unspecified).width ?? 0)
    }
}
