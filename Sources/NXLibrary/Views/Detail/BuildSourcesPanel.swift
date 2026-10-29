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
/// the page's actions as a two-column grid of rows. Rows are laid out in pairs,
/// so Left and Right move within a row and Up and Down between rows (see `DetailsFocus`).
struct BuildSourcesPanel: View {
    @Environment(\.seleneCanvas) private var canvas

    let presentation: GameDetailPresentation
    /// The app's file name, shown with the version and size.
    let appFileName: String
    /// The Metal gate refuses new builds: the status line says where to fix it.
    let buildBlocked: Bool
    let rows: [BuildSourcesRow]
    /// The focused row, nil when the band has no focus.
    let focusedRow: Int?
    let onHoverRow: (Int) -> Void
    let onPressRow: (Int) -> Void

    static let width: CGFloat = 1100
    static let columns = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            status
            Text("Version \(presentation.version)  ·  \(presentation.size)  ·  \(appFileName)")
                .seleneFont(15)
                .foregroundColor(SeleneTheme.ink60)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, canvas.u(4))
                .padding(.leading, canvas.u(2))
            if presentation.sourcesDetached {
                Text("The installed app is playable. A rebuild needs the original XCI/NSP files; attach them again without touching saves.")
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
                    .padding(.top, canvas.u(4))
                    .padding(.leading, canvas.u(2))
            }
            grid
                .padding(.top, canvas.u(14))
        }
        .frame(width: canvas.u(Self.width), alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: canvas.u(8)) {
            Text("Build & Sources")
                .seleneFont(21, .semibold)
                .foregroundColor(SeleneTheme.ink)
            SeleneInfoTip("NX Library uses symlinks to your game ROM files to build the macOS native binary. Rebuilding uses your current engine pin and settings, and preserves your game saves. "
                          + (presentation.sourcesDetached
                             ? "The sources are detached: attach them again to rebuild."
                             : "The original sources are attached. Rebuild writes a new app and keeps the previous one if it fails."))
        }
        .padding(.top, canvas.u(2))
        .padding(.bottom, canvas.u(14))
        .padding(.leading, canvas.u(2))
    }

    private var status: some View {
        HStack(spacing: canvas.u(14)) {
            HStack(spacing: canvas.u(7)) {
                Circle()
                    .fill(presentation.sourcesDetached ? SeleneTheme.untested : SeleneTheme.success)
                    .frame(width: canvas.u(9), height: canvas.u(9))
                Text(presentation.sourcesDetached ? "Sources detached" : "Sources attached")
                    .seleneFont(15, .medium)
                    .foregroundColor(presentation.sourcesDetached
                                     ? SeleneTheme.untested.opacity(0.9)
                                     : SeleneTheme.success.opacity(0.9))
            }
            Text("Engine \(presentation.engineCommitShort)")
                .seleneFont(15, .semibold)
                .monospacedDigit()
                .foregroundColor(SeleneTheme.ink82)
            Text(presentation.toolchainVerified ? "Certified" : "Untested toolchain")
                .seleneFont(15, .medium)
                .foregroundColor(presentation.toolchainVerified
                                 ? SeleneTheme.success.opacity(0.85)
                                 : SeleneTheme.untested.opacity(0.9))
            if buildBlocked {
                Text("Build blocked — Settings → Engine")
                    .seleneFont(15, .semibold)
                    .foregroundColor(SeleneTheme.untested)
            }
        }
        .padding(.leading, canvas.u(2))
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: canvas.u(8)) {
            ForEach(Array(stride(from: 0, to: rows.count, by: Self.columns)), id: \.self) { first in
                HStack(spacing: canvas.u(14)) {
                    ForEach(first..<min(first + Self.columns, rows.count), id: \.self) { index in
                        cell(rows[index], index: index)
                    }
                    if rows.count - first < Self.columns {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: canvas.u(44))
                    }
                }
            }
        }
    }

    private func cell(_ row: BuildSourcesRow, index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: canvas.u(12), style: .continuous)
        return Button { onPressRow(index) } label: {
            Text(row.title)
                .seleneFont(19)
                .foregroundColor(row.enabled ? SeleneTheme.ink90 : SeleneTheme.ink60)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, canvas.u(20))
                .frame(height: canvas.u(44))
                .background(shape.fill(SeleneTheme.glass))
                .overlay(shape.strokeBorder(SeleneTheme.ink15, lineWidth: max(1, canvas.u(1))))
                .contentShape(shape)
                .seleneRowFocus(focusedRow == index, radius: canvas.u(12))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
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
            BuildSourcesRow(id: "attach", title: "Attach sources…") {
                viewModel.locateSources(for: game)
            },
            BuildSourcesRow(id: "rebuild", title: "Rebuild", enabled: p.canRebuild && !buildBlocked) {
                rebuild()
            },
            BuildSourcesRow(id: "log", title: "Open log") {
                viewModel.revealLog(for: game)
            },
            BuildSourcesRow(id: "save", title: "Open save folder") {
                viewModel.revealSaveFolder(URL(fileURLWithPath: p.savePath))
            },
            BuildSourcesRow(id: "app", title: "Reveal app in Finder") {
                viewModel.revealInFinder(url: game.url)
            }
        ]
        if let store = p.storeURL {
            rows.append(BuildSourcesRow(id: "store", title: "Store page") { viewModel.openURL(store) })
        }
        if let hltb = p.hltbURL {
            rows.append(BuildSourcesRow(id: "hltb", title: "HowLongToBeat") { viewModel.openURL(hltb) })
        }
        if p.description.isEmpty, let search = viewModel.nintendoStoreSearchURL(for: game) {
            rows.append(BuildSourcesRow(id: "search", title: "Search Nintendo Store") {
                viewModel.openURL(search)
            })
        }
        return rows
    }
}
