import SwiftUI
import AppKit
import NXLibraryCore

/// One link under the Details panel. `enabled` dims the title; the button still takes focus and a click.
struct DetailsLink: Identifiable {
    let id: String
    let title: String
    var enabled: Bool = true
    let action: () -> Void
}

extension DetailsLink {
    /// Every source's links, in grid order, each only when it has a target. Technical actions
    /// (Rebuild, sources, log, saves) live in Options.
    @MainActor
    static func links(app: URL?, store: URL?, hltb: URL?, viewModel: AppViewModel) -> [DetailsLink] {
        var links: [DetailsLink] = []
        if let app {
            links.append(DetailsLink(id: "app", title: L10n.text("Reveal in Finder")) { viewModel.revealInFinder(url: app) })
        }
        if let store {
            links.append(DetailsLink(id: "store", title: L10n.text("Store page")) { viewModel.openURL(store) })
        }
        if let hltb {
            links.append(DetailsLink(id: "hltb", title: L10n.text("HowLongToBeat")) { viewModel.openURL(hltb) })
        }
        return links
    }

    /// The app's folder by its Finder name ("Applications"); never the path. Read once per folder.
    @MainActor
    static func folderName(of app: URL) -> String? {
        folderNames.name(for: app.deletingLastPathComponent())
    }

    /// The Steam library's volume by its localized name ("Macintosh HD"). Read once per library.
    @MainActor
    static func volumeName(of game: CatalogGame) -> String? {
        guard let library = game.steamGame?.installations.first(where: { $0.availability == .available })?.libraryURL
        else { return nil }
        return volumeNames.name(for: library)
    }

    @MainActor private static let folderNames = DisplayNameCache { folder in
        let name = FileManager.default.displayName(atPath: folder.path)
        return name.isEmpty ? nil : name
    }

    @MainActor private static let volumeNames = DisplayNameCache { library in
        (try? library.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName
    }
}

/// A game's Details in the page's right column, the same for every source (maintainer's choice,
/// 15 Nov 2026): what a player cares about as label → value rows with small grey icons, in the
/// achievements' light outlined panel, and the links under it. Rows without a value are not shown;
/// with none at all only the title and the links remain, and with no links either nothing does. No build, engine or sources state: that is
/// Options' business, and problems that stop the player show in Play's own note.
struct DetailsPanel: View {
    @Environment(\.seleneCanvas) private var canvas

    let facts: [DetailsFact]
    let links: [DetailsLink]
    /// The focused link, nil when the band has no focus.
    let focusedLink: Int?
    let onHoverLink: (Int) -> Void
    let onPressLink: (Int) -> Void
    /// The panel's width in canvas units.
    var width: CGFloat = Self.narrowWidth

    /// Spotlight's column beside About this game: three links and their gaps.
    static let narrowWidth: CGFloat = 520
    /// The Switch Details page's band: the rows in two columns.
    static let wideWidth: CGFloat = 1100
    private static let radius: CGFloat = SeleneTheme.contentRadius
    private static let padding: CGFloat = 18
    private static let columnGap: CGFloat = 40

    private var wide: Bool { width >= 800 }

    var body: some View {
        // With nothing to show, no title alone on the page.
        if !facts.isEmpty || !links.isEmpty { content }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailsBandTitle(text: "Details")
            if !facts.isEmpty {
                panel.padding(.bottom, canvas.u(14))
            }
            SeleneActionGrid(rows: links, focusedRow: focusedLink, onHoverRow: onHoverLink, onPressRow: onPressLink)
        }
        .frame(width: canvas.u(width), alignment: .topLeading)
    }

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: canvas.u(Self.radius), style: .continuous)
        let split = wide ? (facts.count + 1) / 2 : facts.count
        let columnWidth = wide ? (width - Self.padding * 2 - Self.columnGap) / 2 : width - Self.padding * 2
        return HStack(alignment: .top, spacing: canvas.u(Self.columnGap)) {
            column(Array(facts.prefix(split)), width: columnWidth)
            if wide { column(Array(facts.dropFirst(split)), width: columnWidth) }
        }
        .padding(.horizontal, canvas.u(Self.padding))
        .padding(.vertical, canvas.u(16))
        .frame(width: canvas.u(width), alignment: .leading)
        // The achievements' surface: the art's blur shows through, lightly tinted, under a thin outline.
        .background(.ultraThinMaterial, in: shape)
        .background(shape.fill(SeleneTheme.ink.opacity(0.04)))
        .overlay(shape.strokeBorder(SeleneTheme.ink15, lineWidth: max(1, canvas.u(1))))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("Details"))
    }

    private func column(_ facts: [DetailsFact], width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(14)) {
            ForEach(facts) { row($0) }
        }
        .frame(width: canvas.u(width), alignment: .topLeading)
    }

    private func row(_ fact: DetailsFact) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: canvas.u(10)) {
                Image(systemName: fact.symbol)
                    .font(.system(size: canvas.u(14), weight: .regular))
                    .foregroundColor(SeleneTheme.ink.opacity(0.55))
                    .frame(width: canvas.u(18))
                Text(fact.label)
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: canvas.u(182), alignment: .leading)
            Text(fact.value)
                .seleneFont(15, .semibold)
                .foregroundColor(SeleneTheme.ink.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(fact.label): \(fact.value)")
    }
}

/// Small link buttons, three to a row (`SpotlightState.actionColumns`): squarer and quieter than
/// Play and Options above, so they read as secondary. Shared by every source's page, so Left/Right
/// and Up/Down move the same way (`DetailsFocus`).
struct SeleneActionGrid: View {
    @Environment(\.seleneCanvas) private var canvas
    let rows: [DetailsLink]
    let focusedRow: Int?
    let onHoverRow: (Int) -> Void
    let onPressRow: (Int) -> Void
    static let columns = SpotlightState.actionColumns
    static let cellWidth: CGFloat = 168

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(8)) {
            ForEach(Array(stride(from: 0, to: rows.count, by: Self.columns)), id: \.self) { first in
                HStack(spacing: canvas.u(8)) {
                    ForEach(first..<min(first + Self.columns, rows.count), id: \.self) { index in
                        cell(rows[index], index: index)
                    }
                }
            }
        }
    }

    private func cell(_ row: DetailsLink, index: Int) -> some View {
        let radius = canvas.u(7)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return Button { onPressRow(index) } label: {
            Text(row.title)
                .seleneFont(14, .medium)
                .foregroundColor(row.enabled ? SeleneTheme.ink90 : SeleneTheme.ink60)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, canvas.u(10))
                .frame(width: canvas.u(Self.cellWidth), height: canvas.u(32))
                .background(shape.fill(SeleneTheme.glass))
                .overlay(shape.strokeBorder(SeleneTheme.ink15, lineWidth: max(1, canvas.u(1))))
                .contentShape(shape)
                .seleneRowFocus(focusedRow == index, radius: radius)
        }
        .buttonStyle(.plain)
        .onHover { if $0 { onHoverRow(index) } }
        .accessibilityLabel(row.title)
    }
}
