import SwiftUI
import NXLibraryCore

/// A Steam game's achievements at the top of the page's right column, above the source's panel and beside
/// About this game (layout "A", maintainer's choice, 16 Nov 2026): the best crystal earned large on the left, beside it
/// "3/41" over the completion (complete: "Arcane" over "All achievements"), the last three unlocked icons on the right
/// and a thin bar under them while incomplete, in a light, nearly transparent panel with a thin outline, the surface
/// of the panel's buttons without their dark fill (maintainer's choice, 15 Nov 2026). Focused, Selene's ring sits on the panel's edge.
/// Shown only when the game has achievements and Steam's files read. A or a click opens the Achievements screen;
/// under the pointer or the controller's focus it says so (maintainer's choice, 15 Nov 2026): the crystal comes to
/// colour, the line under the headline gives way to "View all", the three icons fan out and brighten, and
/// the panel lightens. Details, not a button, does none of it.
/// With Reduce motion the text and light change without movement.
struct DetailsAchievementsCard: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @State private var hovered = false

    /// What the card shows: set from hover and focus inside its own animation, so only the fan, the text swap
    /// and the light animate (an `.animation` on the card would catch every other change in the same update).
    @State private var active = false
    /// The fan and the text's slide move only where the card can move as one block (`CardGeometryGroup`);
    /// elsewhere, as with Reduce motion, only the text and the light change.
    private var moves: Bool { !reduceMotion && CardGeometryGroup.available }
    private var fanned: Bool { active && moves }
    /// Slow and soft, and never past its target (a spring overshot); interrupted, it blends towards the new end.
    private var reveal: Animation { !moves ? SeleneTheme.quick : .timingCurve(0.22, 1, 0.36, 1, duration: 0.45) }

    let summary: AchievementSummary
    let appID: UInt32
    let focused: Bool
    let onOpen: () -> Void

    /// The column's width (`DetailsPanel.narrowWidth`).
    static let width = DetailsPanel.narrowWidth
    private static let radius: CGFloat = SeleneTheme.contentRadius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: canvas.u(Self.radius), style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            DetailsBandTitle(text: L10n.text("Achievements"))
            VStack(alignment: .leading, spacing: canvas.u(16)) {
                HStack(alignment: .center, spacing: canvas.u(16)) {
                    if let tier = summary.bestTier { crystal(tier) }
                    VStack(alignment: .leading, spacing: canvas.u(4)) {
                        headline
                        ZStack(alignment: .leading) {
                            Text(complete ? L10n.text("All achievements")
                                          : L10n.format("%d%% complete", [summary.percentComplete]))
                                .foregroundColor(SeleneTheme.ink60)
                                .monospacedDigit()
                                .opacity(active ? 0 : 1)
                                .offset(y: fanned ? -canvas.u(5) : 0)
                            Text(L10n.text("View all"))
                                .foregroundColor(SeleneTheme.ink)
                                .opacity(active ? 1 : 0)
                                .offset(y: active || !moves ? 0 : canvas.u(5))
                        }
                        .seleneFont(14, .semibold)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    icons
                }
                if !complete {
                    AchievementProgressBar(fraction: summary.total > 0 ? Double(summary.unlocked) / Double(summary.total) : 0,
                                           height: 5, track: SeleneTheme.ink25)
                }
            }
            .padding(.horizontal, canvas.u(18))
            .padding(.vertical, canvas.u(16))
            .frame(width: canvas.u(Self.width), alignment: .leading)
            // Match the option 3 mockup: a transparent tint, without a second layer of material blur.
            .background(shape.fill(SeleneTheme.ink.opacity(active ? 0.10 : 0.05)))
            .overlay(shape.strokeBorder(SeleneTheme.ink.opacity(active ? 0.32 : 0.16), lineWidth: max(1, canvas.u(1))))
            .contentShape(shape)
            .onHover { hovered = $0 }
            .onAppear { active = hovered || focused }
            .onChange(of: hovered || focused) { wanted in
                withAnimation(reveal) { active = wanted }
            }
            .seleneRowFocus(focused, radius: canvas.u(Self.radius))
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.format("Achievements: %d of %d", [summary.unlocked, summary.total]))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen() }
        }
        .modifier(CardGeometryGroup())
    }
}

/// The page glides by an animated offset, which SwiftUI hands down to each leaf view (text, icon), and a leaf
/// applies the animation of the change that touches it. The fan changed the icons and the text in their own,
/// faster animation, so they took the rest of the glide with it and ran ahead of the panel, out of its box.
/// A geometry group moves the card as one block with the glide and keeps the fan inside it (macOS 14).
struct CardGeometryGroup: ViewModifier {
    static var available: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.geometryGroup()
        } else {
            content
        }
    }
}

extension DetailsAchievementsCard {
    /// Every achievement unlocked: the card names the reward instead of counting (layout "A", 16 Nov 2026).
    private var complete: Bool { summary.isComplete }

    /// Complete, the tier's name ("Arcane"); otherwise "3/41", the unlocked count bright and the total dimmer.
    private var headline: some View {
        Group {
            if complete {
                Text(AchievementTier.arcane.displayName()).foregroundColor(SeleneTheme.ink)
            } else {
                Text("\(summary.unlocked)").foregroundColor(SeleneTheme.ink)
                    + Text("/\(summary.total)").foregroundColor(SeleneTheme.ink60)
            }
        }
        .seleneFont(22, .bold)
        .monospacedDigit()
    }

    /// The best crystal earned (`AchievementSummary.bestTier`), large at the card's left (maintainer's choice,
    /// 16 Nov 2026): black and white at rest, fully opaque so it doesn't read as a locked tier, in colour when the
    /// card is hovered or focused, with the fan. The Arcane orb a size up: it fills less of its square.
    /// Arcane is the maintainer's looping video (16 Nov 2026), which greys, lights, scales and plays itself in
    /// Core Animation; without it (a damaged bundle) the still orb does the same in SwiftUI.
    @ViewBuilder
    private func crystal(_ tier: AchievementTier) -> some View {
        if let video = tier.videoURL {
            ArcaneOrbVideo(url: video, active: active, moves: moves)
                .frame(width: canvas.u(76), height: canvas.u(76))
                .accessibilityHidden(true)
        } else {
            TierCrystal(tier: tier, size: tier == .arcane ? 76 : 64)
                .saturation(active ? 1 : 0)
                .opacity(active ? 1 : 0.88)
                .scaleEffect(fanned ? 1.06 : 1)
        }
    }

    /// The last three unlocked icons. Active, they fan out like a held hand of cards: the outer ones tilt
    /// and drop a little, the gaps open, and all three brighten.
    private var icons: some View {
        let count = summary.recentIcons.count
        let middle = Double(max(count - 1, 0)) / 2
        return HStack(spacing: canvas.u(fanned ? 12 : 8)) {
            ForEach(Array(summary.recentIcons.enumerated()), id: \.offset) { index, icon in
                let side = Double(index) - middle
                AchievementIcon(appID: appID, file: icon, size: 44, dimmed: summary.unlocked == 0)
                    .opacity(active ? 1 : 0.88)
                    .scaleEffect(fanned ? 1.04 : 1)
                    .rotationEffect(.degrees(fanned ? side * 5 : 0), anchor: .bottom)
                    .offset(y: fanned ? canvas.u(CGFloat(abs(side)) * 2) : 0)
                    .zIndex(-abs(side))
            }
        }
    }
}

/// A thin completion bar in the focus colour on a faint track.
struct AchievementProgressBar: View {
    @Environment(\.seleneCanvas) private var canvas
    let fraction: Double
    /// Canvas units: the page's open block uses a finer bar than the screen.
    var height: CGFloat = 6
    var track: Color = SeleneTheme.ink15

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(SeleneTheme.focus)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: canvas.u(height))
        .accessibilityHidden(true)
    }
}
