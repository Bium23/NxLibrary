import SwiftUI
import AppKit
import NXLibraryCore

/// A Steam game's achievements, over the game's art (darker): logo, progress, filters and a two-column list.
/// A pure view like `ScreenshotViewer`: Spotlight owns `AchievementsScreenState` and routes input through
/// `AchievementsScreen.handle`. Present it as an overlay inside the canvas root so the canvas scaling applies.
struct AchievementsScreen: View {
    @Environment(\.seleneCanvas) private var canvas
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
    /// Room for the focus ring around the rows.
    static let ring: CGFloat = 6

    private var state: AchievementsScreenState { model.state }

    var body: some View {
        let rows = summary.rows(state.filter)
        ZStack(alignment: .topLeading) {
            backdrop
            VStack(alignment: .leading, spacing: 0) {
                // The progress on the left; the tier crystals on the right, level with the list's right edge.
                HStack(alignment: .top, spacing: 0) {
                    header
                    Spacer(minLength: canvas.u(40))
                    tierBoard
                }
                .frame(width: canvas.u(Self.columnWidth * 2 + Self.gap + Self.ring))
                .padding(.top, canvas.u(70))
                pills
                    .padding(.top, canvas.u(30))
                AchievementsList(scroll: model.scroll, model: model, rows: rows, focused: state.index,
                                 appID: game.steamGame?.appID ?? 0, onFocus: onFocus)
                    .padding(.top, canvas.u(28))
            }
            .padding(.leading, canvas.u(Self.side))
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                SeleneHintsBar(left: [HintItem(.b, L10n.text("Back")) { onClose() }],
                               right: [HintItem(.lb, L10n.text("Previous")) { onShiftFilter(-1) },
                                       HintItem(.rb, L10n.text("Next")) { onShiftFilter(1) }],
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

    /// Arcane, Radiant, Aether, Ember with unlocked/total under each, as PS5 trophies; a tier not earned yet is
    /// dimmed. Only Arcane until Steam's rarity arrives: the others come from it.
    private var tierBoard: some View {
        let counts = summary.tierCounts
        let tiers = summary.hasRarity ? AchievementTier.allCases : [.platinum]
        return VStack(alignment: .trailing, spacing: canvas.u(12)) {
            HStack(alignment: .top, spacing: canvas.u(22)) {
                ForEach(tiers, id: \.self) { tier in
                    let count = counts[tier] ?? TierCount(unlocked: 0, total: 0)
                    VStack(spacing: canvas.u(4)) {
                        TierCrystal(tier: tier, size: 60, dimmed: count.unlocked == 0)
                        (Text("\(count.unlocked)").foregroundColor(SeleneTheme.ink)
                         + Text(" / \(count.total)").foregroundColor(SeleneTheme.ink60))
                            .seleneFont(15, .semibold)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.format("%1$@, %2$d of %3$d", [tier.displayName, count.unlocked, count.total]))
                }
            }
            if let last = summary.lastUnlockedAt {
                Text(L10n.format("Last unlocked %@", [AchievementsScreenRow.date(last)]))
                    .seleneFont(14)
                    .foregroundColor(SeleneTheme.ink60)
                    .lineLimit(1)
            }
        }
        .fixedSize()
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
            }
            Spacer(minLength: canvas.u(16))
            // The tier with its crystal and how many players have it, the date under it.
            VStack(alignment: .trailing, spacing: canvas.u(6)) {
                if let tier = row.tier, let percent = row.percent {
                    HStack(spacing: canvas.u(6)) {
                        TierCrystal(tier: tier, size: 24, dimmed: !unlocked)
                        Text(tier.displayName)
                            .foregroundColor(unlocked ? SeleneTheme.ink : SeleneTheme.ink75)
                        Text("· \(AchievementsScreen.percent(percent))")
                            .foregroundColor(SeleneTheme.ink60)
                            .monospacedDigit()
                    }
                }
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
            }
            .seleneFont(13, .semibold)
            .lineLimit(1)
            .fixedSize()
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

/// The two-column list, moved by its own offset (`ListScroll`) instead of a scroll view: the wheel and the
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

    private var width: CGFloat { canvas.u(Screen.columnWidth * 2 + Screen.gap + Screen.ring * 2) }

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
            .onAppear { report(height) }
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
        let pitch = canvas.u(Screen.columnWidth + Screen.gap)
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
        .offset(y: -offset)
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        // The rows fade out under the hints bar, and at the top once the list has scrolled: no row sits under
        // a button. No chevrons (maintainer's choice): the fades alone say there is more.
        .mask(mask(atTop: scroll.state.atTop))
    }

    /// Opaque in the middle; the top fades only once rows have scrolled past it, the bottom always fades to a
    /// trace where the hints bar sits (the bottom stays lit, not a dark band).
    private func mask(atTop: Bool) -> some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(atTop ? 1 : 0), .black], startPoint: .top, endPoint: .bottom)
                .frame(height: canvas.u(Screen.topFade))
                .animation(.easeInOut(duration: 0.3), value: atTop)
            Color.black
            LinearGradient(colors: [.black, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                .frame(height: canvas.u(Screen.bottomFade))
        }
    }

    /// The focused row keeps the top fade and a little more above it, and the bottom room below.
    private func report(_ height: CGFloat) {
        model.setLayout(layout, visible: height, above: canvas.u(Screen.topFade + 12),
                        below: canvas.u(Screen.bottomRoom), animates: !reduceMotion)
    }
}
