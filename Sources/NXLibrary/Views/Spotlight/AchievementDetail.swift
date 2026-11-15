import SwiftUI
import NXLibraryCore

/// One achievement in full, over the Achievements screen (A on a row): its tier crystal large, the icon, the
/// whole name and description the list cuts, how many players have it and when it was unlocked. The arrows
/// step it through the list, A or B (or a click outside the card) close it. Without Steam's rarity the icon
/// takes the crystal's place.
struct AchievementDetail: View {
    @Environment(\.seleneCanvas) private var canvas

    let row: AchievementRow
    let appID: UInt32
    let onClose: () -> Void

    static let width: CGFloat = 1120
    static let art: CGFloat = 340

    var body: some View {
        let unlocked = row.unlockedAt != nil
        let shape = RoundedRectangle(cornerRadius: canvas.u(SeleneTheme.modalRadius), style: .continuous)
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
            HStack(alignment: .center, spacing: canvas.u(44)) {
                Group {
                    if let tier = row.tier {
                        TierCrystal(tier: tier, size: Self.art, dimmed: !unlocked)
                    } else {
                        AchievementIcon(appID: appID, file: row.icon, size: 180, dimmed: !unlocked)
                            .frame(width: canvas.u(Self.art), height: canvas.u(Self.art))
                    }
                }
                VStack(alignment: .leading, spacing: canvas.u(18)) {
                    HStack(spacing: canvas.u(20)) {
                        AchievementIcon(appID: appID, file: row.icon, size: 88, dimmed: !unlocked)
                        Text(row.name)
                            .seleneFont(30, .semibold)
                            .foregroundColor(SeleneTheme.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !row.description.isEmpty {
                        Text(row.description)
                            .seleneFont(19)
                            .foregroundColor(SeleneTheme.ink82)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Rectangle()
                        .fill(SeleneTheme.ink15)
                        .frame(height: max(1, canvas.u(1)))
                    VStack(alignment: .leading, spacing: canvas.u(10)) {
                        if let tier = row.tier, let percent = row.percent {
                            HStack(spacing: canvas.u(10)) {
                                Text(tier.displayName())
                                    .foregroundColor(SeleneTheme.ink)
                                Text("·").foregroundColor(SeleneTheme.ink60)
                                Text(L10n.format("%@ of players", [AchievementsScreen.percent(percent)]))
                                    .foregroundColor(SeleneTheme.ink75)
                                    .monospacedDigit()
                            }
                        }
                        if let date = row.unlockedAt {
                            Label {
                                Text(L10n.format("Unlocked on %@", [AchievementsScreen.date(date)]))
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            .labelStyle(.titleAndIcon)
                            .foregroundColor(SeleneTheme.ink82)
                        } else {
                            Text(L10n.text("Not unlocked"))
                                .foregroundColor(SeleneTheme.ink.opacity(0.5))
                        }
                    }
                    .seleneFont(18, .semibold)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(canvas.u(48))
            .frame(width: canvas.u(Self.width))
            .background(shape.fill(SeleneTheme.glassCard))
            .overlay(shape.strokeBorder(SeleneTheme.ink15, lineWidth: max(1, canvas.u(1))))
            .shadow(color: .black.opacity(0.45), radius: canvas.u(30), y: canvas.u(10))
            // A click on the card stays on the card.
            .contentShape(shape)
            .onTapGesture {}
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isModal)
        }
    }
}
