import SwiftUI
import NXLibraryCore

/// One stat in the row: a label over a value, or the platform (icon and name; Steam's logo alone).
struct SeleneStat: Identifiable {
    enum Value {
        case text(String)
        case platform(String)
    }

    let label: String
    let value: Value

    var id: String { label }

    static func text(_ label: String, _ value: String) -> SeleneStat {
        SeleneStat(label: label, value: .text(value))
    }

    static func platform(_ console: String) -> SeleneStat { SeleneStat(label: L10n.text("PLATFORM"), value: .platform(console)) }
}

/// Selene's at-a-glance stats line, with a 1u rule between items. Spotlight and
/// Collection use the default order and 26 either side of each rule; Details
/// passes its own items and a 28 gap. The caller places it.
struct SeleneStatsRow: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.displayScale) private var displayScale

    let items: [SeleneStat]
    /// Space either side of each rule, in Selene units.
    var gap: CGFloat = 26

    /// PLAYTIME · LAST PLAYED · PLATFORM · RELEASED (Spotlight, Collection).
    init(presentation: LibraryPresentation) {
        var items = [
            SeleneStat.text(L10n.text("PLAYTIME"), presentation.playtime),
            SeleneStat.text(L10n.text("LAST PLAYED"), presentation.lastPlayed),
            SeleneStat.platform(presentation.console)
        ]
        if let year = presentation.releaseYear {
            items.append(SeleneStat.text(L10n.text("RELEASED"), year))
        }
        self.items = items
    }

    init(items: [SeleneStat], gap: CGFloat = 26) {
        self.items = items
        self.gap = gap
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { divider }
                stat(item)
            }
        }
        .fixedSize()
        .shadow(color: .black.opacity(0.45), radius: canvas.u(4))
    }

    @ViewBuilder
    private func stat(_ item: SeleneStat) -> some View {
        if case .platform(let console) = item.value, console == SteamPlatformLogo.platformName {
            steamStat(item.label)
        } else {
            labelled(item)
        }
    }

    /// Valve's logo stands alone, without the label over it, centred in the height of the other stats' label and
    /// value lines (16 + 2 + 28), so the row is as tall for a Steam game as for any other. It is as tall as a
    /// value line or the guidelines' on-screen minimum; the 9 units left above and below are the crank's clear
    /// space at that size, and nothing else in the row comes nearer.
    private func steamStat(_ label: String) -> some View {
        SteamPlatformLogo(height: SteamPlatformLogo.height(canvas.u(28), displayScale: displayScale))
            .frame(height: canvas.u(46))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(L10n.text(label)))
            .accessibilityValue(Text(verbatim: SteamPlatformLogo.platformName))
    }

    private func labelled(_ item: SeleneStat) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(2)) {
            // Line boxes of Selene's Segoe UI 12 / 21 (16 and 28), so the strip lands 34 below.
            Text(L10n.text(item.label))
                .seleneFont(12, .semibold)
                .foregroundColor(SeleneTheme.ink60)
                .frame(height: canvas.u(16), alignment: .leading)
            Group {
                switch item.value {
                case .text(let text):
                    value(text)
                case .platform(let console):
                    HStack(spacing: canvas.u(9)) {
                        SwitchPlatformIcon()
                            .foregroundColor(SeleneTheme.ink)
                            .frame(width: canvas.u(27), height: canvas.u(27))
                        value(console)
                    }
                }
            }
            .frame(minHeight: canvas.u(28))
        }
        .accessibilityElement(children: .combine)
    }

    private func value(_ text: String) -> some View {
        Text(text).seleneFont(21, .semibold).foregroundColor(SeleneTheme.ink)
    }

    /// 1u ink25 rule, inset 4 top and bottom.
    private var divider: some View {
        Rectangle()
            .fill(SeleneTheme.ink25)
            .frame(width: max(1, canvas.u(1)))
            .padding(.vertical, canvas.u(4))
            .padding(.horizontal, canvas.u(gap))
    }
}
