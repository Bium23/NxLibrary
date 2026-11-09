import SwiftUI
import NXLibraryCore

/// One action in Build & Sources: a Selene row. `enabled` dims the title; the
/// row still takes focus and a click (the page decides what a press does).
struct BuildSourcesRow: Identifiable {
    let id: String
    let title: String
    var enabled: Bool = true
    let action: () -> Void
}

/// Band 2's left column (Selene's "Your captures" slot, spec §5.4): the sources
/// status with the engine and toolchain, the app's version, size and file, and
/// the page's actions as a grid of small buttons, three to a row: Left and Right
/// move within a row, Up and Down between rows (see `DetailsFocus`). Narrower
/// than `wide` (Spotlight's column beside About this game), the status and the
/// app's file take two lines each.
struct BuildSourcesPanel: View {
    @Environment(\.seleneCanvas) private var canvas

    let presentation: GameDetailPresentation
    /// The app's file name, shown with the version and size.
    let appFileName: String
    /// The Metal gate refuses new builds: the status line says where to fix it.
    let buildBlocked: Bool
    /// The gate's line for the refusal (ToolchainGateCopy); a newer Metal compiler reads calm, not orange.
    var blockedHint: ToolchainGateCopy.Summary? = nil
    let rows: [BuildSourcesRow]
    /// The focused row, nil when the band has no focus.
    let focusedRow: Int?
    let onHoverRow: (Int) -> Void
    let onPressRow: (Int) -> Void
    /// The panel's width in canvas units.
    var width: CGFloat = Self.width

    static let width: CGFloat = 1100
    /// Spotlight's column: three buttons and their gaps.
    static let narrowWidth: CGFloat = 520
    static let columns = SpotlightState.actionColumns
    static let cellWidth: CGFloat = 168

    private var wide: Bool { width >= 800 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            status
            Text(wide ? L10n.format("Version %@  ·  %@  ·  %@", [String(describing: (presentation.version)), String(describing: (presentation.size)), String(describing: (appFileName))])
                      : L10n.format("Version %@  ·  %@", [String(describing: (presentation.version)), String(describing: (presentation.size))]))
                .seleneFont(15)
                .foregroundColor(SeleneTheme.ink60)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, canvas.u(4))
                .padding(.leading, canvas.u(2))
            if !wide {
                Text(appFileName)
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, canvas.u(2))
            }
            if presentation.sourcesDetached {
                Text(presentation.canPlay
                     ? L10n.text("Game files are missing or not attached. Play is available; attach them to rebuild.")
                     : L10n.text("Game files are missing or not attached. Attach them to build."))
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
                    .padding(.top, canvas.u(4))
                    .padding(.leading, canvas.u(2))
            }
            grid
                .padding(.top, canvas.u(14))
        }
        .frame(width: canvas.u(width), alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: canvas.u(8)) {
            Text(L10n.text("Build & Sources"))
                .seleneFont(21, .semibold)
                .foregroundColor(SeleneTheme.ink)
            SeleneInfoTip(L10n.text("NX Library uses symlinks to your game ROM files to build the macOS native binary. Rebuilding uses your current engine pin and settings, and preserves your game saves. ")
                          + (presentation.sourcesDetached
                             ? L10n.text("The sources are detached: attach them again to rebuild.")
                             : L10n.text("The original sources are attached. Rebuild writes a new app and keeps the previous one if it fails.")))
        }
        .padding(.top, canvas.u(2))
        .padding(.bottom, canvas.u(14))
        .padding(.leading, canvas.u(2))
    }

    @ViewBuilder private var status: some View {
        if wide {
            HStack(spacing: canvas.u(14)) {
                sourcesStatus
                engineStatus
                blockedStatus
            }
            .padding(.leading, canvas.u(2))
        } else {
            VStack(alignment: .leading, spacing: canvas.u(4)) {
                sourcesStatus
                HStack(spacing: canvas.u(14)) { engineStatus }
                blockedStatus
            }
            .padding(.leading, canvas.u(2))
        }
    }

    private var sourcesStatus: some View {
        HStack(spacing: canvas.u(7)) {
            Circle()
                .fill(presentation.sourcesDetached ? SeleneTheme.untested : SeleneTheme.success)
                .frame(width: canvas.u(9), height: canvas.u(9))
            Text(presentation.sourcesDetached ? L10n.text("Sources detached") : L10n.text("Sources attached"))
                .seleneFont(15, .medium)
                .foregroundColor(presentation.sourcesDetached
                                 ? SeleneTheme.untested.opacity(0.9)
                                 : SeleneTheme.success.opacity(0.9))
        }
    }

    /// The engine and the toolchain.
    @ViewBuilder private var engineStatus: some View {
        Text(L10n.format("Engine %@", [String(describing: (presentation.engineCommitShort))]))
            .seleneFont(15, .semibold)
            .monospacedDigit()
            .foregroundColor(SeleneTheme.ink82)
        Text(presentation.toolchainVerified ? L10n.text("Certified") : L10n.text("Untested toolchain"))
            .seleneFont(15, .medium)
            .foregroundColor(presentation.toolchainVerified
                             ? SeleneTheme.success.opacity(0.85)
                             : SeleneTheme.untested.opacity(0.9))
    }

    @ViewBuilder private var blockedStatus: some View {
        if buildBlocked {
            Text(blockedHint.flatMap { $0.buildHint.isEmpty ? nil : $0.buildHint } ?? L10n.text("Build blocked — Settings → Engine"))
                .seleneFont(15, .semibold)
                .foregroundColor(blockedHint?.tone == .info ? SeleneTheme.ink82 : SeleneTheme.untested)
        }
    }

    /// Small tool buttons, three to a row (`SpotlightState.actionColumns`): squarer
    /// and quieter than Play and Options above, so they read as secondary.
    private var grid: some View {
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

    private func cell(_ row: BuildSourcesRow, index: Int) -> some View {
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

extension BuildSourcesRow {
    /// Build & Sources' actions for a game, in grid order. Store links and the
    /// Nintendo search appear only when they have a target. Shared by Details and Spotlight.
    @MainActor
    static func rows(for game: PortedGame, presentation p: GameDetailPresentation, buildBlocked: Bool,
                     viewModel: AppViewModel, rebuild: @escaping () -> Void) -> [BuildSourcesRow] {
        var rows: [BuildSourcesRow] = [
            BuildSourcesRow(id: "attach", title: L10n.text("Attach sources…")) {
                viewModel.locateSources(for: game)
            },
            BuildSourcesRow(id: "rebuild", title: L10n.text("Rebuild"), enabled: p.canRebuild && !buildBlocked) {
                rebuild()
            },
            BuildSourcesRow(id: "log", title: L10n.text("Open log")) {
                viewModel.revealLog(for: game)
            },
            BuildSourcesRow(id: "save", title: L10n.text("Open save folder")) {
                viewModel.revealSaveFolder(URL(fileURLWithPath: p.savePath))
            },
            BuildSourcesRow(id: "app", title: L10n.text("Reveal app in Finder")) {
                viewModel.revealInFinder(url: game.url)
            }
        ]
        if let store = p.storeURL {
            rows.append(BuildSourcesRow(id: "store", title: L10n.text("Store page")) { viewModel.openURL(store) })
        }
        if let hltb = p.hltbURL {
            rows.append(BuildSourcesRow(id: "hltb", title: L10n.text("HowLongToBeat")) { viewModel.openURL(hltb) })
        }
        if p.description.isEmpty, let search = viewModel.nintendoStoreSearchURL(for: game) {
            rows.append(BuildSourcesRow(id: "search", title: L10n.text("Search Nintendo Store")) {
                viewModel.openURL(search)
            })
        }
        return rows
    }
}
