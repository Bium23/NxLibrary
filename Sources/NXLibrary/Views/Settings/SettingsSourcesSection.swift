import SwiftUI
import AppKit
import NXLibraryCore

@MainActor
struct SettingsSourcesSection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    @EnvironmentObject private var sources: CatalogSourcesModel
    @Environment(\.nxAppLocale) private var localization
    let onActions: ([SettingsRowAction]) -> Void

    private var defaultRoot: URL { AppData.profile.home.appendingPathComponent("Library/Application Support/Steam") }
    private var hidden: [CatalogGame] { viewModel.catalogGames.filter { $0.integration == .steam && $0.isHidden } }
    private var review: [CatalogGame] {
        viewModel.catalogGames.filter { !$0.isHidden && $0.steamGame.map { !$0.hasBeenRecognized || $0.needsInstallationReview } == true }
    }
    private var statusText: String {
        switch sources.status {
        case .disabled: return L10n.text("Enable Steam to find its installed Mac games.", context: localization)
        case .idle: return L10n.text("Ready to check Steam.", context: localization)
        case .scanning: return L10n.text("Checking Steam libraries…", context: localization)
        case .ready: return L10n.count("%lld Steam installations found", sources.observedGameCount, context: localization)
        case .partial: return L10n.text("Some installations could not be checked. Your library has been kept.", context: localization)
        case .cancelled: return L10n.text("Scan stopped. Refresh when you are ready.", context: localization)
        case .failed: return L10n.text("Steam could not be refreshed. Your library has been kept.", context: localization)
        }
    }
    var body: some View {
        VStack(spacing: 9) {
            SeleneToggleRow("Steam", subtitle: "Find installed native Mac games in your Steam libraries.",
                            info: "Your Steam files stay where they are. Disabling this source keeps its games and personal choices.",
                            isOn: Binding(get: { sources.configuration.isEnabled }, set: { enabled in
                                sources.configure(enabled: enabled, root: sources.configuration.rootURL ?? defaultRoot)
                            }))
            SeleneButtonRow("Refresh Steam", subtitle: statusText,
                            buttonTitle: sources.status == .scanning ? "Cancel" : "Refresh") {
                if sources.status == .scanning { sources.cancel() } else { sources.refresh() }
            }.disabled(!sources.configuration.isEnabled)
            SeleneValueRow("Steam folder", subtitle: "Choose the Steam folder containing steamapps.",
                           value: (sources.configuration.rootURL ?? defaultRoot).path, actionTitle: "Change", action: chooseFolder)
            SeleneToggleRow("Keep Steam in the background",
                            subtitle: "Steam stays out of sight while a game starts, and comes back if it needs you.",
                            info: "When Play opens Steam, it starts without its window. An open Steam is hidden until the game appears. If the game takes longer than 15 seconds, Steam comes back so you can answer it.",
                            isOn: $settings.settings.steamInBackground)
            if let error = sources.errorMessage {
                Text(error).seleneFont(14).foregroundColor(SeleneTheme.danger)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
            if sources.reviewCount > 0 {
                Text(L10n.count("%lld Steam games need review", sources.reviewCount, context: localization))
                    .seleneFont(15).foregroundColor(SeleneTheme.ink60).padding(.vertical, 10)
            }
            if !review.isEmpty {
                SettingsSubheading("Review installations")
                Text(L10n.text("Check these installations in Steam, then refresh this source. Only recognized native Mac games appear in the library.", context: localization))
                    .seleneFont(14).foregroundColor(SeleneTheme.ink60).fixedSize(horizontal: false, vertical: true)
                ForEach(review) { game in
                    SeleneRow(game.name, id: "review-\(game.id)", subtitle: "Needs review", verbatimTitle: true) {
                        Button(L10n.text("Reveal", context: localization)) { reveal(game) }.buttonStyle(.plain).foregroundColor(SeleneTheme.glyph)
                    }
                }
            }
            if !hidden.isEmpty {
                SettingsSubheading("Hidden Steam games")
                ForEach(hidden) { game in
                    SeleneRow(game.name, id: "hidden-\(game.id)", subtitle: "Hidden from the library", verbatimTitle: true) {
                        Button(L10n.text("Show", context: localization)) { viewModel.setCatalogHidden(false, game: game) }
                            .buttonStyle(.plain).foregroundColor(SeleneTheme.glyph)
                    }
                }
            }
        }
        .onAppear(perform: publishActions)
        .onChange(of: sources.status) { _ in publishActions() }
        .onChange(of: sources.configuration) { _ in publishActions() }
        .onChange(of: viewModel.catalogGames) { _ in publishActions() }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = sources.configuration.rootURL ?? defaultRoot
        panel.message = L10n.text("Choose the Steam folder containing steamapps.", context: localization)
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        let root = chosen.resolvingSymlinksInPath().standardizedFileURL
        let apps = root.appendingPathComponent("steamapps").resolvingSymlinksInPath().standardizedFileURL
        var directory: ObjCBool = false
        guard apps.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: apps.path, isDirectory: &directory), directory.boolValue else {
            viewModel.showSettingsNotice(title: L10n.text("Steam folder", context: localization), message: L10n.text("Choose the Steam folder containing steamapps.", context: localization))
            return
        }
        sources.configure(enabled: sources.configuration.isEnabled, root: root)
    }
    private func reveal(_ game: CatalogGame) {
        guard let location = game.steamGame?.installations.first?.contentURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([location])
    }
    private func publishActions() {
        var rows: [SettingsRowAction] = [
            .init(id: "steamSource", title: "Steam") { sources.configure(enabled: !sources.configuration.isEnabled, root: sources.configuration.rootURL ?? defaultRoot) },
            .init(id: "steamRefresh", title: "Refresh Steam", isEnabled: sources.configuration.isEnabled) {
                if sources.status == .scanning { sources.cancel() } else { sources.refresh() }
            },
            .init(id: "steamFolder", title: "Steam folder", activate: chooseFolder),
            .init(id: "steamInBackground", title: "Keep Steam in the background") { settings.settings.steamInBackground.toggle() }
        ]
        rows += review.map { game in .init(id: "review-\(game.id)", title: game.name, rowID: "review-\(game.id)") { reveal(game) } }
        rows += hidden.map { game in .init(id: "hidden-\(game.id)", title: game.name, rowID: "hidden-\(game.id)") { viewModel.setCatalogHidden(false, game: game) } }
        onActions(rows)
    }
}
