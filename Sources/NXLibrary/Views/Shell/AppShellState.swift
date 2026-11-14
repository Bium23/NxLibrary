import NXLibraryCore

/// Prepared before the shell enters SwiftUI's view graph. Model startup can
/// update AppKit and shared observable services; it must not run in a view's
/// StateObject creation while replacing the already-visible preparation screen.
@MainActor
final class AppShellState {
    let settings: AppSettingsStore
    let viewModel: AppViewModel
    let router: AppRouter
    let sources: CatalogSourcesModel

    init(settings: AppSettingsStore, catalog: CatalogDocument, repository: CatalogRepository) {
        self.settings = settings
        AppLocalization.shared.configure(settings.settings)
        ThemeStore.shared.apply(id: settings.settings.colorThemeID)
        let model = AppViewModel(settingsStore: settings, catalog: catalog, repository: repository)
        viewModel = model
        sources = CatalogSourcesModel(repository: repository, initialConfiguration: catalog.source(.steam) ?? .init(integration: .steam)) { [weak model] document in
            model?.applyCatalog(document)
        }
        let router = AppRouter()
        router.setInitialRoute(AppRouter.initialRoute(for: settings.settings.startOn, last: settings.settings.lastHome))
        router.isIntroShowing = settings.settings.introAnimation
        self.router = router
    }
}
